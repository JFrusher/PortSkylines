extends SceneTree
## Headless tests for M13's automation tier on M11's transfer blocks, the
## ASC blocks: unlocked by milestone, built with their ASCs bought, a ramp-up
## penalty against a manual block, and an IT cost a day.
## godot --headless --script res://tests/test_automation.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_unlock_gating()
	_test_ramp_up_matches_the_curve()
	_test_automation_costs()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _run(sim: PortSim, minutes: float) -> void:
	for i in roundi(minutes / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()


## Roads to build a transfer block on the base port's east road: one behind
## it, the road it runs back to. The sim is left creative, so it costs nothing
## to build them; the block is built by the caller.
func _roads(sim: PortSim) -> int:
	sim.creative = true
	sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(200, 300), "to": Vector2i(200, 270)})
	sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(200, 270), "to": Vector2i(130, 270)})
	return sim.roads.segment_at(Vector2i(150, 300))


func _block(sim: PortSim, east: int) -> Dictionary:
	return {"op": "build_area", "type": "transfer_block", "segment": east, "side": -1, "from": 55, "to": 66}


func _test_unlock_gating() -> void:
	var sim := AreaPort.base(RandomPort.strait())
	var east := _roads(sim)
	_expect(sim.lock_error("asc"), "Unlocked at milestone 4: 15000 TEU across the quay", "ASCs wait for the hub milestone")
	_expect(sim.apply(_block(sim, east)), sim.lock_error("asc"), "so a transfer block can't be built before it")
	sim.milestones_passed = 4
	_expect(sim.apply(_block(sim, east)), "", "at the hub it can")


## The exit criterion: a block automated today works below a manual block
## of the same gear times, one automated long ago above it, and at every age
## the ratio is the data curve's pace.
func _test_ramp_up_matches_the_curve() -> void:
	var sim := AreaPort.base(RandomPort.quick())
	var manual := AreaPort.add_export_block(sim)
	_expect(sim.apply({"op": "set_area", "id": manual, "settings": {"gear": "rmg"}}), "", "one block works RMGs, by hand")
	var east := _roads(sim)
	sim.milestones_passed = 4
	_expect(sim.apply(_block(sim, east)), "", "the other is an ASC block")
	var automated: int = sim.areas.list.keys().max()
	_expect(automated in sim.automated_since, true, "building it automates it")
	sim.tick()
	var ramp: Array = sim.rules.automation.ramp_up
	var first := 0.0
	var last := 0.0
	for days: float in [0.0, 10.0, 30.0, 45.0, 90.0, 200.0]:
		sim.automated_since[automated] = sim.clock.calendar_minutes() - days * SimClock.MINUTES_PER_DAY
		var times := []
		# The automated block at its pace, at its gear's own full pace, and the manual block.
		for work: Array in [[automated, AreaFlow.pace(sim, automated)], [automated, 1.0], [manual, 1.0]]:
			var machine: int = sim.machines.list.keys().filter(func(m: int) -> bool: return sim.machines.list[m].area == work[0])[0]
			sim.machines.list[machine].bay = 0
			sim.machines.give(machine, 0, 2, 20, work[1])
			var ticks := 0
			while not sim.machines.list[machine].job.is_empty():
				sim.machines.tick([] as Array[String])
				ticks += 1
			times.append(ticks * Machines.SECONDS_PER_TICK)
		_expect(absf(times[1] / times[0] - AreaFlow.ramp_pace(ramp, days)) < 0.02, true, "%d days in, the automated block works at the curve's %.2f of its gear's own pace (%.2f)" % [days, AreaFlow.ramp_pace(ramp, days), times[1] / times[0]])
		var performance: float = times[2] / times[0]  # moves an hour against the manual block's
		if days == 0.0:
			first = performance
		last = performance
	_expect(first < 1.0, true, "at first it performs below the manual block (%.2f)" % first)
	_expect(last > 1.0, true, "in steady state above it (%.2f)" % last)


func _test_automation_costs() -> void:
	var sim := AreaPort.base(RandomPort.quick())
	var east := _roads(sim)
	sim.milestones_passed = 4
	sim.creative = false
	sim.ledger.cash = 10000000
	var command := _block(sim, east)
	var price := sim.area_price("transfer_block", east, -1, 55, 66)
	var cells: int = sim.areas.cells_of("transfer_block", east, -1, 55, 66).size() * sim.rules.area_types.transfer_block.cost_per_cell
	var machines := sim.machines.count_for("asc", 12 / AreaLayout.BAY)
	_expect(price - cells, machines * sim.rules.yard_gear.asc.cost_per_machine, "a transfer block's price includes its ASCs: capex")
	var cash := sim.money
	_expect(sim.apply(command), "", "it is built")
	_expect(cash - sim.money, price, "and paid for")
	_expect(sim.rules.yard_gear.asc.upkeep_per_machine < sim.rules.yard_gear.rmg.upkeep_per_machine, true, "an ASC costs less to keep than an RMG: no driver")
	_expect(sim.rules.upkeep.agv < sim.rules.upkeep.tractor, true, "and an AGV less than a tractor")
	var poor := AreaPort.base(RandomPort.quick())
	var poor_east := _roads(poor)
	poor.milestones_passed = 4
	poor.creative = false
	poor.ledger.cash = cells
	_expect(poor.apply(_block(poor, poor_east)), "Not enough money", "automation needs the money for it")
	_run(sim, SimClock.MINUTES_PER_DAY)
	_expect(sim.ledger.days[-1].lines.get("it_systems", 0), -sim.rules.automation.it_upkeep_per_block, "the IT systems are a ledger line a day")
	_expect(sim.it_upkeep(), sim.rules.automation.it_upkeep_per_block, "one block's IT systems cost a day")
	sim.remove_area(sim.areas.list.keys().max())
	_expect(sim.it_upkeep(), 0, "and stop once the block is gone")
