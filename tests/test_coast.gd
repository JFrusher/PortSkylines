extends SceneTree
## M8 step B: the coast comes from a map in the data. Land, water and the
## water's depth follow the map's curves; a berth on a curved coast builds a
## straight quay and fills the water behind it, at a price.
## godot --headless --script res://tests/test_coast.gd

var _failures := 0


func _initialize() -> void:
	_test_the_game_plays_the_estuary()
	_test_depth_grows_offshore()
	_test_a_berth_fills_behind_its_quay()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The first water west of `cell` on its row.
func _shore(sim: PortSim, row: int) -> Vector2i:
	var cell := Vector2i(sim.areas.coast.size.x / 2, row)
	while not sim.areas.is_water(cell):
		cell.x -= 1
	return cell


func _test_the_game_plays_the_estuary() -> void:
	var sim := PortSim.new(1)
	_expect(sim.map, "estuary", "a new game is played on the data's map")
	var shores := range(200, 400, 10).map(func(row: int) -> int: return _shore(sim, row).x)
	_expect(shores.max() - shores.min() > 3, true, "its coast curves: the shore moves %d cells over the start land's rows" % (shores.max() - shores.min()))
	_expect(sim.areas.is_water(Vector2i(sim.areas.coast.size.x - 1, sim.areas.coast.size.y / 2)), false, "the highway comes in on land")
	var river := 0
	for x: int in range(sim.areas.coast.size.x / 2, sim.areas.coast.size.x):
		river += 1 if sim.areas.is_water(Vector2i(x, 40)) else 0
	_expect(river > 0, true, "a river crosses the land in the north")
	var water := _shore(sim, 300)
	_expect(sim.build_road_error(water + Vector2i(-10, 0), water + Vector2i(10, 0), "terminal_1_1"), "Roads can't be built on water", "roads stay off the water")


func _test_depth_grows_offshore() -> void:
	var sim := PortSim.new(1)
	var shore := _shore(sim, 200)
	var coast := sim.areas.coast
	var rule: Dictionary = sim.rules.maps.estuary.depth
	_expect(coast.depth(shore + Vector2i(1, 0)), 0.0, "land has no depth")
	_expect(coast.depth(shore) < coast.depth(shore - Vector2i(20, 0)), true, "the water deepens away from the shore (%.1f m, then %.1f m)" % [coast.depth(shore), coast.depth(shore - Vector2i(20, 0))])
	_expect(coast.depth(shore) >= rule.shore and coast.depth(shore) <= rule.shore + 1.0, true, "beside the shore it is about the map's shore depth (%.1f m)" % coast.depth(shore))
	var deepest := 0.0
	for x: int in range(0, shore.x):
		deepest = maxf(deepest, coast.depth(Vector2i(x, 200)))
	_expect(deepest <= rule.max, true, "and never deeper than the map's deepest")


func _test_a_berth_fills_behind_its_quay() -> void:
	var sim := PortSim.new(1)
	var click := _shore(sim, 300) + Vector2i(8, 0)
	var plan := sim.berth_plan("feeder", click)
	_expect(plan.get("out"), Vector2i.LEFT, "a berth faces the nearest water, west here")
	var cells: Array[Vector2i] = plan.cells
	var water := cells.filter(sim.areas.is_water).size()
	_expect(water > 0, true, "on a curved coast part of its apron is water (%d cells)" % water)
	var money := sim.money
	var road: Array[Vector2i] = plan.line
	_expect(sim.apply({"op": "build_berth", "kind": "feeder", "cell": click}), "", "the berth is built")
	var apron: int = sim.areas.list.keys().max()
	_expect(money - sim.money, sim.road_price(road[0], road[1], PortSim.BERTH_ROAD) + cells.size() * sim.rules.area_types.quay_apron.cost_per_cell + water * sim.rules.reclaim.cost_per_cell, "it costs its road, its apron and the water it fills")
	_expect(sim.areas.filled.size(), water, "that water is filled")
	_expect(sim.areas.cells(apron).any(sim.areas.is_water), false, "the apron stands on land")
	var quay := RoadNet.line(sim.areas.list[apron].start, sim.areas.list[apron].end).map(func(c: Vector2i) -> Vector2i: return c + sim.areas.list[apron].out * sim.areas.depth_of(sim.areas.list[apron]))
	_expect(quay.all(sim.areas.is_water), true, "and its straight quay faces water all along")
	var loaded := PortSim.from_dict(sim.to_dict())
	_expect([loaded.map, loaded.areas.filled], [sim.map, sim.areas.filled], "the map and the filled water are saved")
	_expect(sim.apply({"op": "remove_area", "id": apron}), "", "the apron is taken out")
	_expect(sim.areas.filled.size(), water, "and the filled land stays land")
