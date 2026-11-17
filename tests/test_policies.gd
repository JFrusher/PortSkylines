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
	_test_day_shifts()
	_test_appointments()
	_test_dual_cycling()
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


## Day shifts on the quay: a ship alongside is worked by day and not by
## night, and cranes and tractors cost less to crew.
func _test_day_shifts() -> void:
	var sim := AreaPort.working_terminal(400, 0, RandomPort.quick())
	var always := AreaPort.working_terminal(400, 0, RandomPort.quick())
	_expect(sim.apply({"op": "set_policy", "policy": "day_shifts", "on": true}), "", "day shifts switch on")
	_expect(sim.daily_upkeep() < always.daily_upkeep(), true, "day crews cost less (%d against %d a day)" % [sim.daily_upkeep(), always.daily_upkeep()])
	var from: int = sim.rules.policies.day_shifts.effects.quay_work_from
	_run(sim, from * 60.0 - sim.clock.calendar_minutes())
	_run(always, from * 60.0 - always.clock.calendar_minutes())
	_expect(sim.ships[0].moves, 0, "no box is moved before the day shift starts")
	_expect(always.ships[0].moves > 0, true, "the port working nights has moved some (%d)" % always.ships[0].moves)
	_run(sim, 60.0)
	_expect(sim.ships[0].moves > 0, true, "and the day shift moves them (%d in its first hour)" % sim.ships[0].moves)


## Lorry appointments: no hour takes more lorries than the gate books, and
## boxes wait longer in the yard for a free hour: the mixed results the
## roadmap cites. (With no truck park, early lorries also wait in the booths.)
func _test_appointments() -> void:
	var with := AreaPort.base(RandomPort.rules())
	var without := AreaPort.base(RandomPort.rules())
	_expect(with.apply({"op": "set_policy", "policy": "appointments", "on": true}), "", "appointments switch on")
	var gate: int = with.areas.working_gates(1)[0]
	var slots := AreaFlow.slots_per_hour(with, gate)
	_expect(slots, floori(AreaFlow.gate_throughput(with, gate) * with.rules.policies.appointments.effects.appointment_share), "the gate books the policy's share of what its lanes check")
	_expect(AreaFlow.slots_per_hour(without, gate), 0, "and none without the policy")
	var most := 0
	for tick in roundi(600.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		with.tick()
		without.tick()
		for hour: int in with.bookings.get(gate, {}):
			most = maxi(most, with.bookings[gate][hour])
	_expect(most > 0 and most <= slots, true, "no hour is booked past the gate's slots (%d of %d)" % [most, slots])
	_expect(with._average(with.dwell_times) > without._average(without.dwell_times), true, "and imports dwell longer (%.0f against %.0f minutes)" % [with._average(with.dwell_times), without._average(without.dwell_times)])


## Dual cycling: exports go aboard while imports are still coming off, on
## the same tractors, and the ship is done no later.
func _test_dual_cycling() -> void:
	var done := []
	for dual: bool in [true, false]:
		# No dangerous goods, which this port has no block for and would shut out.
		var rules := RandomPort.quick()
		rules.box_mix.dg_share = 0.0
		var sim := AreaPort.working_terminal(60, 40, rules)
		# Exports in the yard before the ship works, so there is something to cycle with.
		var ship: PortSim.Ship = sim.ships[0]
		sim.ships.clear()
		_run(sim, 240.0)
		sim.ships.append(ship)
		ship.berthed = sim.clock.calendar_minutes()
		ship.due = sim.clock.calendar_minutes() + 600.0
		if dual:
			_expect(sim.apply({"op": "set_policy", "policy": "dual_cycling", "on": true}), "", "dual cycling switches on")
		var mixed := false
		var boxes := sim.boxes.size()
		while ship.state == PortSim.Ship.State.WORKING and sim.clock.calendar_minutes() < ship.berthed + 900.0:
			sim.tick()
			mixed = mixed or (ship.exports < 40 and ship.boxes > 0)
		_expect(mixed, dual, "exports %s loaded while imports are still aboard" % ("are" if dual else "aren't"))
		_expect(ship.state, PortSim.Ship.State.LEAVING, "the ship is worked and sails")
		_expect(ship.moves, 100, "every import and export crossed the quay")
		done.append(sim.clock.calendar_minutes() - ship.berthed)
	_expect(done[0] <= done[1], true, "and dual cycling is no slower (%.0f against %.0f minutes)" % done)
