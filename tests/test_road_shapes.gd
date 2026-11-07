extends SceneTree
## M10 step 12b: a road's shape. Its lanes are quads along its curve, as an
## area's cells are (AreaShape), half its lanes either side of its line; its
## ground (water, land, cost, what it blocks) is the grid cells under their
## middles. On a straight grid road that is today's footprint, and on a road
## at any angle it follows the road.
## godot --headless --script res://tests/test_road_shapes.gd

var _failures := 0
var _types: Dictionary = Content.base().road_types


func _initialize() -> void:
	_test_straight_roads_keep_their_cells()
	_test_a_road_at_an_angle_follows_its_line()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _sorted(cells: Array) -> Array:
	var found := cells.duplicate()
	found.sort()
	return found


## East and north, 1+1 and 2+2: the ground is the cells its lanes covered.
func _test_straight_roads_keep_their_cells() -> void:
	for c: Array in [[Vector2i(0, 0), Vector2i(10, 0), "terminal_1_1"], [Vector2i(0, 0), Vector2i(0, -10), "terminal_2_2"]]:
		var net := RoadNet.new(_types)
		net.add(c[0], c[1], c[2])
		var lanes: Array = []
		for lane in net.lanes(1):
			lanes.append_array(lane.cells)
		_expect(_sorted(net.ground(1)), _sorted(lanes), "%s to %s: its ground is its lanes' cells" % [c[0], c[1]])
		_expect(net.shape(1).cells.size(), lanes.size(), "a quad for each")
		_expect(net.segment_at(lanes[0]), 1, "and picking finds it there")


## A 2+2 road from (0, 0) to (30, 17), about 30° off east: 4 quads per cell
## along it, every one's middle within 2 cells of its line, and its ground the
## cells under them, so nothing beside it is taken.
func _test_a_road_at_an_angle_follows_its_line() -> void:
	var net := RoadNet.new(_types)
	net.add(Vector2i(0, 0), Vector2i(10, 0), "terminal_2_2")
	# Turned to (30, 17) by hand: the tool that draws it is 12d's.
	net.nodes[net.segments[1].b] = Vector2(30, 17)
	net.segments[1].control = Vector2(15, 8.5)
	net.version += 1
	var length := Vector2(30, 17).length()
	_expect(net.shape(1).cells.size(), 4 * ceili(length), "four lanes of quads, the length of the road")
	var line := func(p: Vector2) -> float: return absf(p.cross(Vector2(30, 17).normalized()))
	_expect(net.shape(1).cells.all(func(c: Dictionary) -> bool: return line.call(c.centre) < 2.0), true, "each quad's middle lies within the road")
	var under := {}
	for c: Dictionary in net.shape(1).cells:
		under[Vector2i(c.centre.floor())] = true
	_expect(_sorted(net.ground(1)), _sorted(under.keys()), "its ground is the grid cells under them")
	_expect(net.segment_at(Vector2i(15, 2)), 0, "a cell off to its side isn't taken")
	_expect(net.segment_at(Vector2i(Vector2(15, 8.5).floor())), 1, "one on its line is")
