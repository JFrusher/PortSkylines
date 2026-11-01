extends SceneTree
## M10 step 6a: an area's cells are its own rows of 4 m cells laid along a
## stretch of road and turned with it, as Cities: Skylines lays zoning cells:
## column k runs one cell along the road's line, row r one cell further out.
## On a straight grid road they are today's grid cells; round a bend the
## outer rows stretch and inner cells too small to use are left out.
## godot --headless --script res://tests/test_area_shape.gd

const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_straight_shapes_are_todays_cells()
	_test_a_bend_keeps_every_outer_cell()
	_test_a_tight_bend_drops_unusable_inner_cells()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Yard blocks either side of a straight 1+1 road east and a 2+2 road
## south: each local cell's centre is in the grid cell today's area covers,
## one each.
func _test_straight_shapes_are_todays_cells() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	sim.apply({"op": "build_road", "from": Vector2i(100, 200), "to": Vector2i(140, 200), "type": "terminal_1_1"})
	sim.apply({"op": "build_road", "from": Vector2i(200, 150), "to": Vector2i(200, 190), "type": "terminal_2_2"})
	for segment: int in sim.roads.segments:
		var road: Dictionary = sim.roads.types[sim.roads.segments[segment].type]
		for side: int in [1, -1]:
			var today := sim.areas.cells_of("yard_block", segment, side, 3, 22)
			var shape := AreaShape.along(sim.roads.curve(segment), side, 3, 22, (road.forward + road.backward) / 2.0, sim.rules.area_types.yard_block.depth)
			var cells := shape.cells.map(func(cell: Dictionary) -> Vector2i: return Vector2i(cell.centre.floor()))
			cells.sort()
			today.sort()
			_expect(cells, today, "segment %d side %d: the local cells are today's grid cells" % [segment, side])


## Round a wide quarter turn, the outside of the bend keeps every cell, each
## a little longer along than across.
func _test_a_bend_keeps_every_outer_cell() -> void:
	var bend := RoadCurve.new(Vector2(0, 0), Vector2(60, 0), Vector2(60, 60))
	# Turning right (south), the outside of the bend is to the left.
	var shape := AreaShape.along(bend, -1, 0, 79, 1.0, 8)
	_expect(shape.cells.size(), 80 * 8, "every cell of the outer side is kept")
	var outer: Dictionary = shape.cells.filter(func(c: Dictionary) -> bool: return c.k == 40 and c.r == 7)[0]
	_expect(outer.corners[0].distance_to(outer.corners[1]) > 1.0, true, "an outer row's cell stretches along the bend")


## A tight bend's inside can't hold full rows: cells whose inner edge would
## shrink below half a cell are left out, and every cell kept is a proper
## quad, its edges running the road's way.
func _test_a_tight_bend_drops_unusable_inner_cells() -> void:
	var bend := RoadCurve.new(Vector2(0, 0), Vector2(8, 0), Vector2(8, 8))
	var shape := AreaShape.along(bend, 1, 0, 10, 1.0, 8)
	_expect(shape.cells.size() < 11 * 8, true, "the inside of a tight bend loses cells (%d of %d kept)" % [shape.cells.size(), 11 * 8])
	_expect(shape.cells.size() > 0, true, "and keeps the near rows")
	for cell: Dictionary in shape.cells:
		_expect(cell.corners[0].distance_to(cell.corners[1]) >= AreaShape.MIN_SIDE - 0.0001, true, "cell %d,%d's inner edge is at least half a cell" % [cell.k, cell.r])
