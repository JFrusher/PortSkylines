extends SceneTree
## M10 step 12b: a road's shape. Its lanes are quads along its curve, as an
## area's cells are (AreaShape), half its lanes either side of its line; its
## ground (water, land, cost, what it blocks) is the grid cells under their
## middles. On a straight grid road that is today's footprint, and on a road
## at any angle it follows the road.
## godot --headless --script res://tests/test_road_shapes.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0
var _types: Dictionary = Content.base().road_types


func _initialize() -> void:
	_test_straight_roads_keep_their_cells()
	_test_a_road_at_an_angle_follows_its_line()
	_test_an_area_along_a_road_at_an_angle()
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


## A 2+2 road from (100, 250) turned to (130, 267), about 30° off east, and
## a yard block along its south side from its 4th column to its 23rd: its
## cells lie along the road, clear of its lanes, a drag from beside the road
## attaches to it, and a road runs along it.
func _test_an_area_along_a_road_at_an_angle() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	_expect(sim.apply({"op": "build_road", "from": Vector2i(100, 250), "to": Vector2i(110, 250), "type": "terminal_2_2"}), "", "a road")
	var road: Dictionary = sim.roads.segments[1]
	sim.roads.nodes[road.b] = Vector2(130, 267)
	road.control = Vector2(115, 258.5)
	sim.roads.version += 1
	var way := Vector2(30, 17).normalized()
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": 1, "from": 3, "to": 22}), "", "a yard block along it")
	var block: int = sim.areas.list.keys().max()
	var out := func(p: Vector2) -> float: return way.cross(p - Vector2(100, 250))
	var shape := sim.areas.shape(block)
	_expect(shape.cells.size(), 20 * sim.rules.area_types.yard_block.depth, "20 columns of its rows")
	_expect(shape.cells.all(func(c: Dictionary) -> bool: return out.call(c.centre) > 2.0), true, "every cell lies beyond the road's two lanes on its side")
	var first: Vector2 = shape.cells.filter(func(c: Dictionary) -> bool: return c.k == 0 and c.r == 0)[0].centre
	var beside := sim.areas.attach(Vector2i(first.floor()), "yard_block")
	_expect([beside.get("segment"), beside.get("side"), beside.get("index")], [1, 1, 3], "a drag from its first cell attaches to the road there")
	_expect(sim.areas.road_beside(block), true, "a road runs along it")
