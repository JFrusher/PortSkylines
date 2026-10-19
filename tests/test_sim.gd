extends SceneTree
## Headless tests for the build rules and the ship-to-lorry loop.
## godot --headless --script res://tests/test_sim.gd

const ROAD := PortMap.Tile.ROAD
const QUAY := PortMap.Tile.QUAY
const YARD := PortMap.Tile.YARD

var _failures := 0


func _initialize() -> void:
	_test_build_rules()
	_test_bulldoze_rules()
	_test_no_ship_without_a_road()
	_test_ships_unload_and_lorries_pay()
	_test_commands()
	_test_round_trip()
	_test_cells_of_matches_a_scan()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A road from the highway to the coast, a quay at its end and a yard beside it.
func _port() -> PortSim:
	var sim := PortSim.new()
	var row := sim.map.entry.y
	var coast := sim.map.sea_width
	for x in range(coast + 1, sim.map.entry.x):
		_expect(sim.build(ROAD, Vector2i(x, row)), "", "road at x=%d" % x)
	_expect(sim.build(QUAY, Vector2i(coast, row)), "", "quay")
	_expect(sim.build(YARD, Vector2i(coast + 2, row - 1)), "", "yard")
	return sim


func _run(sim: PortSim, minutes: float) -> void:
	for i in roundi(minutes / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()


func _test_build_rules() -> void:
	var sim := PortSim.new()
	_expect(sim.build(ROAD, Vector2i(3, 3)), "Can't build on water", "road on water")
	_expect(sim.build(QUAY, Vector2i(30, 3)), "A quay must face the water", "inland quay")
	_expect(sim.build(QUAY, Vector2i(12, 3)), "", "coastal quay")
	_expect(sim.build(ROAD, Vector2i(12, 3)), "Bulldoze first", "road on a quay")
	_expect(sim.build(ROAD, Vector2i(99, 3)), "Off the map", "road off the map")
	_expect(sim.build(QUAY, Vector2i(12, 0)), "", "quay on the north edge faces the sea")
	_expect(sim.build(QUAY, Vector2i(30, 0)), "A quay must face the water", "map edge is not water")
	_expect(sim.money, sim.rules.start_money - 400, "quays cost money")
	sim.money = 5
	_expect(sim.build(ROAD, Vector2i(30, 3)), "Not enough money", "building while broke")


func _test_bulldoze_rules() -> void:
	var sim := _port()
	var yard := Vector2i(sim.map.sea_width + 2, sim.map.entry.y - 1)
	_expect(sim.bulldoze(sim.map.entry), "That's the highway", "bulldoze highway")
	_expect(sim.bulldoze(Vector2i(30, 3)), "Nothing to bulldoze", "bulldoze empty land")
	sim.stacked[yard] = 1
	_expect(sim.bulldoze(yard), "The yard still holds boxes", "bulldoze a full yard")
	sim.stacked[yard] = 0
	_expect(sim.bulldoze(yard), "", "bulldoze an empty yard")
	_expect(sim.map.tile(yard), PortMap.Tile.LAND, "bulldozed yard is land again")


func _test_no_ship_without_a_road() -> void:
	var sim := PortSim.new()
	sim.build(QUAY, Vector2i(12, 3))
	_run(sim, sim.rules.first_ship_minutes + 1)
	_expect(sim.ships.size(), 0, "no ship calls at an unconnected quay")


func _test_ships_unload_and_lorries_pay() -> void:
	var sim := _port()
	var before := sim.money
	_run(sim, sim.rules.first_ship_minutes + 120)
	_expect(sim.delivered >= sim.rules.ship_boxes, true, "first ship's boxes all delivered (%d)" % sim.delivered)
	_expect(sim.money, before + sim.delivered * sim.rules.fee_per_box, "every delivery is paid")


func _test_commands() -> void:
	var by_command := PortSim.new()
	var direct := PortSim.new()
	var cell := Vector2i(12, 3)
	_expect(by_command.apply({"op": "build", "kind": QUAY, "cell": cell}), "", "build command")
	direct.build(QUAY, cell)
	_expect(by_command.map.tile(cell), direct.map.tile(cell), "a build command builds like build()")
	_expect(by_command.money, direct.money, "a build command charges like build()")
	_expect(by_command.apply({"op": "bulldoze", "cell": cell}), "", "bulldoze command")
	_expect(by_command.map.tile(cell), PortMap.Tile.LAND, "a bulldoze command clears the tile")
	_expect(by_command.apply({"op": "fly"}), "Unknown command: fly", "unknown command is refused")


func _test_round_trip() -> void:
	var straight := _port()
	var halves := _port()
	_run(straight, 50)
	_run(halves, 25)
	var copy := PortSim.from_dict(halves.to_dict())
	_expect(copy.state_hash(), halves.state_hash(), "to_dict -> from_dict keeps the state")
	_run(copy, 25)
	_expect(copy.ships.is_empty() and copy.lorries.is_empty(), false, "the round trip happened mid-traffic")
	_expect(copy.state_hash(), straight.state_hash(), "a round trip mid-run changes nothing")
	_expect(copy.build(ROAD, Vector2i(30, 3)), "", "the copy's map still accepts builds")
	_expect(copy.map.route(copy.map.entry, Vector2i(copy.map.sea_width, copy.map.entry.y)).is_empty(), false, "the copy's road routing works")


func _test_cells_of_matches_a_scan() -> void:
	var sim := PortSim.new()
	var map := sim.map
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var kinds := [PortMap.Tile.LAND, ROAD, QUAY, YARD]
	for i in 1000:
		map.place(kinds[rng.randi() % kinds.size()], Vector2i(rng.randi_range(map.sea_width, map.size.x - 1), rng.randi_range(0, map.size.y - 1)))
	for kind: int in PortMap.Tile.values():
		var scan: Array[Vector2i] = []
		for y in map.size.y:
			for x in map.size.x:
				if map.tile(Vector2i(x, y)) == kind:
					scan.append(Vector2i(x, y))
		_expect(map.cells_of(kind), scan, "cells_of(%s) matches a full scan after 1,000 places" % PortMap.Tile.keys()[kind])
