extends SceneTree
## M6 notes from the M5 playtest: one STS crane comes down without its apron.
## godot --headless --script res://tests/test_port_notes.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_remove_one_crane()
	_test_berth_plan()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## A crane working a ship stays up; once the ship has sailed it comes down
## alone, leaving its apron and the other crane, and the berth works on.
func _test_remove_one_crane() -> void:
	var sim := AreaPort.working_terminal(10)
	sim.creative = true
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": 1, "along": 40}), "", "a second crane goes up")
	sim.tick()
	_expect(sim.apply({"op": "remove_sts", "apron": 1, "along": 20}), "Wait for the ship alongside to sail", "a crane working a ship stays up")
	var ship: PortSim.Ship = sim.ships[0]
	for i in SimClock.TICKS_PER_DAY:
		sim.tick()
		if ship not in sim.ships:
			break
	_expect(ship in sim.ships, false, "the ship is worked and sails")
	_expect(sim.apply({"op": "remove_sts", "apron": 1, "along": 30}), "No crane there", "only a crane's own spot takes it down")
	_expect(sim.apply({"op": "remove_sts", "apron": 1, "along": 20}), "", "an idle crane comes down")
	_expect(sim.cranes.map(func(c: PortSim.Crane) -> int: return c.along), [40], "only that crane is gone")
	_expect(1 in sim.areas.list, true, "its apron stays")
	var cell: Vector2i = sim.areas.list[1].start + (sim.areas.list[1].end - sim.areas.list[1].start).sign() * 40
	_expect(AreaFlow.crane_at(sim, cell) == sim.cranes[0], true, "the crane left is found from a cell under it")


## Two feeder windows that overlap on the port's one berth are a clash; apart
## in the week, or with a second berth to take one, they are not.
func _test_berth_plan() -> void:
	var sim := AreaPort.base(RandomPort.quick(), "")
	var line: String = sim.rules.lines.keys()[0]
	var call := func(id: int, hour: int) -> Dictionary: return {"id": id, "line": line, "kind": "feeder", "start": hour * 60, "window_hours": 12.0, "moves": 40}
	sim.contracts.services.assign([call.call(1, 0), call.call(2, 6)])
	var plan := AreaFlow.berth_plan(sim)
	_expect(plan.map(func(p: Dictionary) -> Array: return [p.service.id, p.apron, p.clash]), [[1, 1, true], [2, 1, true]], "overlapping windows on one berth clash")
	sim.contracts.services.assign([call.call(1, 0), call.call(2, 12), call.call(3, 7 * 24 - 2)])
	plan = AreaFlow.berth_plan(sim)
	_expect(plan.map(func(p: Dictionary) -> Array: return [p.service.id, p.clash]), [[1, true], [2, false], [3, true]], "a window across the week's end clashes with Monday's")
	sim.creative = true
	var entry := sim.site_entry()
	_expect(sim.apply({"op": "build_road", "from": Vector2i(85, entry.y), "to": Vector2i(85, entry.y + 90), "type": "terminal_1_1"}), "", "the coast road runs on south")
	var coast := sim.roads.segment_at(Vector2i(85, entry.y + 50))
	_expect(sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 10, "to": 79}), "", "a second apron")
	sim.apply({"op": "set_terminal", "id": sim.areas.list.keys()[-1], "terminal": 1})
	sim.contracts.services.assign([call.call(1, 0), call.call(2, 6)])
	plan = AreaFlow.berth_plan(sim)
	_expect(plan.map(func(p: Dictionary) -> bool: return p.clash), [false, false], "a second berth takes the overlapping call")
	_expect(plan[0].apron != plan[1].apron, true, "on different berths")


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
