extends SceneTree
## Headless tests for M12's automation tier: ASCs and AGVs unlocked by
## milestone, the ramp-up penalty against a manual block, automation costs,
## and automated and manual blocks working one ship together.
## godot --headless --script res://tests/test_automation.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_unlock_gating()
	_test_ramp_up_matches_the_curve()
	_test_automation_costs()
	_test_mixed_operations()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _run(sim: PortSim, minutes: float) -> void:
	for i in roundi(minutes / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()


func _test_unlock_gating() -> void:
	var sim := AreaPort.base(RandomPort.strait())
	sim.creative = true
	for name: String in ["asc", "agv"]:
		_expect(sim.lock_error(name), "Unlocked at milestone 4: 15000 TEU across the quay", "%s waits for the hub milestone" % name)
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"gear": "asc"}}), sim.lock_error("asc"), "a block can't be automated before it")
	_expect(sim.apply({"op": "buy_agvs", "count": 2}), sim.lock_error("agv"), "nor AGVs bought")
	sim.milestones_passed = 4
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"gear": "asc"}}), "", "at the hub a block is automated")
	_expect(sim.apply({"op": "buy_agvs", "count": 2}), "", "and AGVs are bought")
	_expect(sim.agvs, 2, "two AGVs")


## The exit criterion: a block automated today works below a manual block
## of the same gear times, one automated long ago above it, and at every age
## the ratio is the data curve's pace.
func _test_ramp_up_matches_the_curve() -> void:
	var sim := AreaPort.base(RandomPort.quick())
	var manual := AreaPort.add_export_block(sim)
	_expect(sim.apply({"op": "set_area", "id": manual, "settings": {"gear": "rmg"}}), "", "one block works RMGs, by hand")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"gear": "asc"}}), "", "the other is automated")
	sim.tick()
	var rmg: Dictionary = sim.rules.yard_gear.rmg
	var asc: Dictionary = sim.rules.yard_gear.asc
	_expect([asc.speed, asc.lift_seconds, asc.set_down_seconds], [rmg.speed, rmg.lift_seconds, rmg.set_down_seconds], "an ASC's own times are an RMG's, so the pace is the whole difference")
	var ramp: Array = sim.rules.automation.ramp_up
	var first := 0.0
	var last := 0.0
	for days: float in [0.0, 10.0, 30.0, 45.0, 90.0, 200.0]:
		sim.automated_since[3] = sim.clock.calendar_minutes() - days * SimClock.MINUTES_PER_DAY
		var times := []
		for block: int in [3, manual]:
			var machine: int = sim.machines.list.keys().filter(func(m: int) -> bool: return sim.machines.list[m].area == block)[0]
			sim.machines.list[machine].bay = 0
			sim.machines.give(machine, 0, 4, 1, AreaFlow.pace(sim, block))
			var ticks := 0
			while not sim.machines.list[machine].job.is_empty():
				sim.machines.tick()
				ticks += 1
			times.append(ticks * Machines.SECONDS_PER_TICK)
		var performance: float = times[1] / times[0]  # moves an hour against the manual block's
		_expect(absf(performance - AreaFlow.ramp_pace(ramp, days)) < 0.02, true, "%d days in, the automated block works at the curve's %.2f of the manual one (%.2f)" % [days, AreaFlow.ramp_pace(ramp, days), performance])
		if days == 0.0:
			first = performance
		last = performance
	_expect(first < 1.0, true, "at first it performs below the manual block (%.2f)" % first)
	_expect(last > 1.0, true, "in steady state above it (%.2f)" % last)


func _test_automation_costs() -> void:
	var sim := AreaPort.base(RandomPort.quick())
	sim.ledger.cash = 10000000
	var block := 3
	var machines := sim.machines.count_for("asc", sim.areas.list[block].columns / AreaLayout.BAY)
	var cash := sim.money
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"gear": "asc"}}), "", "a block is automated")
	_expect(cash - sim.money, machines * sim.rules.yard_gear.asc.cost_per_machine, "its ASCs are bought: capex")
	_expect(sim.rules.yard_gear.asc.upkeep_per_machine < sim.rules.yard_gear.rmg.upkeep_per_machine, true, "an ASC costs less to keep than an RMG: no driver")
	_expect(sim.rules.agv.upkeep < sim.rules.upkeep.tractor, true, "and an AGV less than a tractor")
	var poor := AreaPort.base(RandomPort.quick())
	poor.ledger.cash = 1000
	_expect(poor.apply({"op": "set_area", "id": 3, "settings": {"gear": "asc"}}), "Not enough money", "automation needs the money for it")
	_run(sim, SimClock.MINUTES_PER_DAY)
	_expect(sim.ledger.days[-1].lines.get("it_systems", 0), -sim.rules.automation.it_upkeep_per_block, "the IT systems are a ledger line a day")
	sim.apply({"op": "set_area", "id": block, "settings": {"gear": "rtg"}})
	_run(sim, SimClock.MINUTES_PER_DAY)
	_expect(sim.ledger.days[-1].lines.get("it_systems", 0), 0, "and stop once the block is manual again")


## An automated import block served by AGVs and a manual export block by
## tractors work one ship: AGVs go only to the automated block, tractors
## only to the manual one, and every box is accounted for.
func _test_mixed_operations() -> void:
	var rules := RandomPort.quick()
	rules.box_mix.dg_share = 0.0
	rules.box_mix.reefer_share = 0.0
	var sim := AreaPort.working_terminal(60, 40, rules)
	sim.ledger.cash = 10000000
	var ship: PortSim.Ship = sim.ships[0]
	sim.ships.clear()
	_run(sim, 240.0)
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"gear": "asc"}}), "", "the import block is automated")
	sim.automated_since[3] -= 90.0 * SimClock.MINUTES_PER_DAY
	_expect(sim.apply({"op": "buy_agvs", "count": 4}), "", "AGVs are bought")
	sim.ships.append(ship)
	ship.berthed = sim.clock.calendar_minutes()
	ship.due = sim.clock.calendar_minutes() + 900.0
	var strays := 0
	var agvs_seen := 0
	var tractors_seen := 0
	while ship.state == PortSim.Ship.State.WORKING and sim.clock.calendar_minutes() < ship.berthed + 1200.0:
		sim.tick()
		for v: Vehicle in sim.vehicles:
			if v.kind != "tractor" or v.area == 0:
				continue
			agvs_seen += 1 if v.agv else 0
			tractors_seen += 0 if v.agv else 1
			if AreaFlow.automated(sim, v.area) != v.agv:
				strays += 1
	_expect(ship.state, PortSim.Ship.State.LEAVING, "the ship is worked and sails")
	_expect(ship.moves, 100, "all 60 imports and 40 exports crossed the quay")
	_expect([agvs_seen > 0, tractors_seen > 0], [true, true], "AGVs and tractors both worked it")
	_expect(strays, 0, "AGVs serve only the automated block, tractors only the manual one")
	var stacked: int = sim.area_stacks[3].boxes().filter(func(b: int) -> bool: return sim.boxes[b].kind == "import").size()
	var carried := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.loaded and sim.boxes[v.box].kind == "import").size()
	_expect(stacked + carried + sim.delivered >= 60, true, "no import is lost: %d stacked, %d on the road, %d delivered" % [stacked, carried, sim.delivered])
	_expect(sim.boxes.keys().all(func(b: int) -> bool: return sim.area_stacks.values().any(func(s: AreaStacks) -> bool: return s.has(b)) or sim.vehicles.any(func(v: Vehicle) -> bool: return v.box == b)), true, "every box is in a stack or on a vehicle")
