extends SceneTree
## Headless tests for M12's global policies: the framework (a policy changes
## exactly its parameters, costs its daily line, is locked, saved and a
## command), then one scenario per starter policy.
## godot --headless --script res://tests/test_policies.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")
## A value no policy sets, standing for "the sim's own default".
const UNSET := -12345.0

var _failures := 0


func _initialize() -> void:
	_test_a_policy_changes_exactly_its_parameters()
	_test_a_policy_is_a_saved_command_with_a_ledger_line()
	_test_bad_policy_data_is_refused()
	_test_day_gates()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _run(sim: PortSim, minutes: float) -> void:
	for i in roundi(minutes / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()


## Every parameter any policy can set, read with no default of its own.
func _parameters(sim: PortSim) -> Dictionary:
	var found := {}
	for key: String in Content.POLICY_EFFECTS:
		found[key] = sim.policy_value(key, UNSET)
	return found


func _test_a_policy_changes_exactly_its_parameters() -> void:
	for policy: String in Content.base().policies:
		var sim := PortSim.new(0, RandomPort.quick())
		var effects: Dictionary = sim.rules.policies[policy].effects
		_expect(_parameters(sim).values().all(func(v: float) -> bool: return v == UNSET), true, "with no policy on, every parameter is the sim's own")
		_expect(sim.apply({"op": "set_policy", "policy": policy, "on": true}), "", "%s switches on" % policy)
		var now := _parameters(sim)
		for key: String in now:
			_expect(now[key], float(effects[key]) if key in effects else UNSET, "%s on: %s is %s" % [policy, key, "its value" if key in effects else "untouched"])
		_expect(sim.apply({"op": "set_policy", "policy": policy, "on": false}), "", "%s switches off" % policy)
		_expect(_parameters(sim).values().all(func(v: float) -> bool: return v == UNSET), true, "%s off: every parameter is the sim's own again" % policy)


func _test_a_policy_is_a_saved_command_with_a_ledger_line() -> void:
	var locked := PortSim.new(0, RandomPort.strait())
	_expect(locked.apply({"op": "set_policy", "policy": "day_gates", "on": true}), locked.lock_error("policies"), "policies are locked until their milestone")
	_expect(locked.lock_error("policies") != "", true, "which a new port hasn't reached")
	var rules := RandomPort.quick()
	rules.policies.day_gates.cost_per_day = 250
	var sim := PortSim.new(0, rules)
	_expect(sim.apply({"op": "set_policy", "policy": "nonsense", "on": true}), "Unknown policy: nonsense", "an unknown policy is refused")
	var before := sim.state_hash()
	sim.apply({"op": "set_policy", "policy": "day_gates", "on": true})
	_expect(sim.state_hash() != before, true, "a policy is part of the state the replay hash covers")
	_expect(PortSim.from_dict(sim.to_dict()).state_hash(), sim.state_hash(), "and of the save")
	_expect(PortSim.from_dict(sim.to_dict()).policies, {"day_gates": true}, "a loaded port keeps its policies")
	_run(sim, SimClock.MINUTES_PER_DAY)
	_expect(sim.ledger.days[-1].lines.get("policies", 0), -250, "an active policy's daily cost is a ledger line")
	sim.apply({"op": "set_policy", "policy": "day_gates", "on": false})
	_run(sim, SimClock.MINUTES_PER_DAY)
	_expect(sim.ledger.days[-1].lines.get("policies", 0), 0, "and stops once it is off")


func _test_bad_policy_data_is_refused() -> void:
	var twice := Content.base().duplicate(true)
	twice.policies["copy"] = twice.policies.day_gates.duplicate(true)
	_expect(Content.policies_error(twice.policies).contains("gate_open_from"), true, "two policies can't set the same parameter (%s)" % Content.policies_error(twice.policies))
	var unknown := Content.base().duplicate(true)
	unknown.policies.day_gates.effects["warp_speed"] = 9.0
	_expect(Content.policies_error(unknown.policies).contains("warp_speed"), true, "a parameter the sim doesn't read is refused")
	_expect(Content.policies_error(Content.base().policies), "", "the base game's policies are sound")


## Day gates only: no lorry is sent in while the gates are shut, the queue
## comes in when they open, and the gate lanes cost less to keep.
func _test_day_gates() -> void:
	var rules := RandomPort.rules()
	var open: int = rules.policies.day_gates.effects.gate_open_from
	var shut: int = rules.policies.day_gates.effects.gate_open_to
	var sim := AreaPort.base(rules)
	var always := AreaPort.base(rules)
	# Manual booths cost nothing a lane; OCR portals do.
	for port: PortSim in [sim, always]:
		for id: int in port.areas.list:
			if port.areas.kind_of(port.areas.list[id]) == "gate":
				_expect(port.apply({"op": "set_area", "id": id, "settings": {"level": "ocr"}}), "", "the gate gets OCR portals")
	_expect(sim.apply({"op": "set_policy", "policy": "day_gates", "on": true}), "", "day gates switch on")
	_expect(sim.daily_upkeep() < always.daily_upkeep(), true, "shut gates cost less to keep (%d against %d a day)" % [sim.daily_upkeep(), always.daily_upkeep()])
	var entered := {}  # hour of the day -> lorries first seen in it
	var seen := {}
	for sims: Array in [[sim, true], [always, false]]:
		for tick in SimClock.TICKS_PER_DAY:
			sims[0].tick()
			if not sims[1]:
				continue
			for vehicle: Vehicle in sim.vehicles:
				if vehicle.kind == "lorry" and vehicle.id not in seen:
					seen[vehicle.id] = true
					entered[sim.clock.game_hour()] = entered.get(sim.clock.game_hour(), 0) + 1
	_expect(seen.size() > 0, true, "lorries came in during the day (%d)" % seen.size())
	_expect(entered.keys().all(func(hour: int) -> bool: return hour >= open and hour < shut), true, "and none while the gates were shut (hours %s)" % [entered.keys()])
	_expect(always.vehicles.any(func(v: Vehicle) -> bool: return v.kind == "lorry") or always.delivered > 0, true, "the port without the policy takes lorries all day")
