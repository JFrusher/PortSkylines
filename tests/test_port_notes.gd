extends SceneTree
## M6 notes from the M5 playtest: one STS crane comes down without its apron.
## godot --headless --script res://tests/test_port_notes.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_remove_one_crane()
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


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
