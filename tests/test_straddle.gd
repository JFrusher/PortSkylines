extends SceneTree
## M9 step G: straddle carriers stack in their block and carry boxes to and
## from the quay themselves, so a straddle block works a ship with no
## tractors, at the rate its carriers (from the data) allow.
## godot --headless --script res://tests/test_straddle.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_a_straddle_block_works_a_ship_with_no_tractors()
	_test_more_carriers_work_faster()
	_test_straddles_unlock_at_the_gateway()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The test port's import block and an export block of 10 boxes, both with
## straddle carriers, no tractors, and a feeder alongside with `imports` to
## land and the 10 exports to load. Returns {"sim", "ship"}.
func _straddle_port(rules: Dictionary, imports: int) -> Dictionary:
	var sim := AreaPort.base(rules, "")
	var exports := AreaPort.add_export_block(sim)
	for block: int in [3, exports]:
		_expect(sim.apply({"op": "set_area", "id": block, "settings": {"gear": "straddle"}}), "", "block %d gets straddle carriers" % block)
	sim.tractors = 0
	for i in 10:
		var box := sim._new_box("export", sim.clock.calendar_minutes() + 600.0, "aurora")
		_expect(AreaFlow._stacks(sim, exports).place(box, sim.boxes[box].teu) >= 0, true, "an export is stacked")
		sim.boxes[box].in = sim.clock.calendar_minutes()
	var ship := PortSim.Ship.new("feeder", "aurora", sim.clock.calendar_minutes() + 6000.0, imports, 10)
	sim.ships.append(ship)
	_expect(AreaFlow.berth(sim, ship), true, "the feeder berths")
	ship.state = PortSim.Ship.State.WORKING
	ship.sail = 1.0
	ship.berthed = sim.clock.calendar_minutes()
	return {"sim": sim, "ship": ship}


## Minutes until `ship` has landed and loaded everything, at most `limit`.
func _work(sim: PortSim, ship: PortSim.Ship, limit: float) -> float:
	var start := sim.clock.calendar_minutes()
	var pool_out := 0
	while sim.clock.calendar_minutes() < start + limit and (ship.boxes > 0 or ship.exports > 0):
		sim.tick()
		pool_out = maxi(pool_out, sim._tractors_out())
	_expect(pool_out, 0, "no tractor from the pool ever goes out")
	return sim.clock.calendar_minutes() - start


func _test_a_straddle_block_works_a_ship_with_no_tractors() -> void:
	var port := _straddle_port(RandomPort.quick(), 40)
	var sim: PortSim = port.sim
	var ship: PortSim.Ship = port.ship
	var carried := {}
	var start := sim.clock.calendar_minutes()
	while sim.clock.calendar_minutes() < start + 8 * 60.0 and (ship.boxes > 0 or ship.exports > 0):
		sim.tick()
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.straddle:
				carried[vehicle.id] = true
	_expect([ship.boxes, ship.exports], [0, 0], "the feeder is landed and loaded with no tractors")
	_expect(carried.size() > 1, true, "by straddle carriers from the blocks (%d trips)" % carried.size())
	_expect(sim._tractors_out(), 0, "none of them counts against the tractor pool")


## At the data's one carrier per 2 bays, the test port's 10-bay blocks get
## five each; one carrier a block (one per 1,000 bays) works far slower.
func _test_more_carriers_work_faster() -> void:
	var minutes := {}
	for bays: int in [0, 1000]:
		var rules := RandomPort.quick()
		if bays:
			rules.yard_gear.straddle.bays_per_machine = bays
		var port := _straddle_port(rules, 40)
		minutes[bays] = _work(port.sim, port.ship, 12 * 60.0)
	_expect(minutes[0] < 12 * 60.0, true, "the data's carriers finish (%.0f min)" % minutes[0])
	_expect(minutes[1000] > minutes[0] * 1.5, true, "one carrier a block takes far longer (%.0f min against %.0f)" % [minutes[1000], minutes[0]])


func _test_straddles_unlock_at_the_gateway() -> void:
	var sim := AreaPort.base(RandomPort.strait(), "")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"gear": "straddle"}}), sim.lock_error("straddle"), "straddle carriers wait for milestone 3")
	_expect(sim.lock_error("straddle").begins_with("Unlocked at milestone 3"), true, "milestone 3 (%s)" % sim.lock_error("straddle"))
