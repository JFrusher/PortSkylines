extends SceneTree
## Headless tests for roads and areas on the 4 m grid.
## godot --headless --script res://tests/test_roads.gd

var _failures := 0


func _initialize() -> void:
	_test_segments()
	_test_lanes()
	_test_junctions()
	_test_routes()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _test_segments() -> void:
	var net := RoadNet.new(Content.base().road_types)
	_expect(net.add(Vector2i(0, 0), Vector2i(5, 0), "terminal_1_1"), "", "a straight road is built")
	_expect(net.add(Vector2i(5, 0), Vector2i(8, 3), "terminal_1_1"), "", "a 45° road is built")
	_expect(net.add(Vector2i(0, 0), Vector2i(2, 5), "terminal_1_1"), "Roads run straight or at 45°", "other angles are refused")
	_expect(net.add(Vector2i(4, 4), Vector2i(4, 4), "terminal_1_1"), "A road needs a length", "a road has a length")
	_expect(net.nodes.size(), 3, "roads meeting at a cell share its node")
	_expect(net.cells(1), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)] as Array[Vector2i], "a straight road covers each cell along it")
	var diagonal := net.cells(2)
	_expect(diagonal.size(), 4, "a 45° road of 3 cells' run covers 4 cells")
	var connected := true
	for i in diagonal.size() - 1:
		connected = connected and (diagonal[i + 1] - diagonal[i]).abs() == Vector2i.ONE
	_expect(connected, true, "a 45° road is a connected diagonal run")
	_expect(RoadNet.line(Vector2i(3, 3), Vector2i(3, 0)), [Vector2i(3, 3), Vector2i(3, 2), Vector2i(3, 1), Vector2i(3, 0)] as Array[Vector2i], "a line runs from its first end")


func _test_lanes() -> void:
	var net := RoadNet.new(Content.base().road_types)
	_expect(net.add(Vector2i(0, 0), Vector2i(3, 0), "dirt_track"), "Unknown road type \"dirt_track\"", "unknown road types are refused")
	net.add(Vector2i(0, 5), Vector2i(3, 5), "terminal_2_2")
	var lanes := net.lanes(1)
	_expect(lanes.size(), 4, "a 2+2 road has 4 lanes")
	_expect(lanes.map(func(l: Dictionary) -> bool: return l.forward), [false, false, true, true], "backward lanes on the left, forward on the right")
	# Drawn eastward, right is south (+y): forward lanes on rows 5 and 6, backward on 3 and 4.
	_expect(lanes.map(func(l: Dictionary) -> int: return l.cells[0].y), [3, 4, 5, 6], "lanes sit side by side, the drawn line being the first forward lane")
	_expect(lanes[0].cells[0], Vector2i(3, 3), "a backward lane is listed in driving order, from b to a")
	net.add(Vector2i(10, 10), Vector2i(13, 7), "one_way")
	var one_way := net.lanes(2)
	_expect(one_way.all(func(l: Dictionary) -> bool: return l.forward), true, "a one-way road's lanes all run forward")
	var touching := true
	var first: Array = one_way[0].cells
	var second: Array = one_way[1].cells
	for i: int in first.size():
		touching = touching and (second[i] - first[i]).abs() in [Vector2i(1, 0), Vector2i(0, 1)]
	_expect(touching, true, "45° lanes touch side by side, with no gap row")
	_expect(Content.base().road_types.tractor_lane.lorries, false, "the tractor lane refuses lorries")
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var right := RoadNet.right_of(d)
		_expect(Vector2(right).dot(Vector2(-d.y, d.x)) > 0, true, "right_of %s is on the right" % d)


func _test_junctions() -> void:
	var net := RoadNet.new(Content.base().road_types)
	net.add(Vector2i(0, 5), Vector2i(10, 5), "terminal_1_1")
	_expect(net.add(Vector2i(5, 0), Vector2i(5, 10), "terminal_1_1"), "", "a road may cross another")
	var crossing := _node(net, Vector2i(5, 5))
	_expect(net.degree(crossing), 4, "a crossing makes a 4-way node")
	_expect(net.segments.size(), 4, "both roads split at the crossing")
	_expect(net.add(Vector2i(8, 5), Vector2i(8, 9), "terminal_1_1"), "", "a road may end on another")
	_expect(net.degree(_node(net, Vector2i(8, 5))), 3, "a T join makes a 3-way node")
	_expect(net.add(Vector2i(2, 5), Vector2i(4, 5), "terminal_1_1"), "A road already runs here", "a road can't run along another")
	_expect(net.add(Vector2i(10, 5), Vector2i(10, 0), "terminal_1_1"), "", "a road may start at another's end")
	_expect(net.degree(_node(net, Vector2i(10, 5))), 2, "a bend is a 2-way node")
	var diagonal := RoadNet.new(Content.base().road_types)
	diagonal.add(Vector2i(0, 0), Vector2i(6, 6), "terminal_1_1")
	_expect(diagonal.add(Vector2i(0, 5), Vector2i(5, 0), "terminal_1_1"), "Roads must cross at a cell, not between two", "45° roads that miss each other's cells are refused")
	_expect(diagonal.add(Vector2i(0, 6), Vector2i(6, 0), "terminal_1_1"), "", "45° roads crossing at a cell are built")
	_expect(diagonal.degree(_node(diagonal, Vector2i(3, 3))), 4, "45° roads crossing at a cell make a 4-way node")
	var lengths := 0
	for id: int in net.segments:
		lengths += net.cells(id).size() - 1
	_expect(lengths, 10 + 10 + 4 + 5, "splitting keeps every cell of road")


func _test_routes() -> void:
	var net := RoadNet.new(Content.base().road_types)
	var lanes := LaneGraph.new(net)
	net.add(Vector2i(0, 0), Vector2i(10, 0), "terminal_1_1")
	net.add(Vector2i(10, 0), Vector2i(10, 10), "terminal_1_1")
	var bend := lanes.route(Vector2i(0, 0), Vector2i(10, 10), true)
	_expect(bend.size(), 21, "round a bend the route is the cells along both roads")
	_expect(_steps_are_single(bend), true, "a route moves one cell at a time")
	var back := lanes.route(Vector2i(4, 0), Vector2i(2, -1), true)
	_expect(not back.is_empty(), true, "the other way is reached by the dead end's U-turn")
	_expect(back.has(Vector2i(10, 10)) or back.has(Vector2i(11, 10)), true, "the U-turn is at the dead end")
	var one_way := RoadNet.new(Content.base().road_types)
	var one_way_lanes := LaneGraph.new(one_way)
	one_way.add(Vector2i(0, 0), Vector2i(10, 0), "one_way")
	_expect(one_way_lanes.route(Vector2i(0, 0), Vector2i(10, 0), true).size(), 11, "a one-way road is driven forward")
	_expect(one_way_lanes.route(Vector2i(10, 0), Vector2i(0, 0), true), [] as Array[Vector2i], "a one-way road can't be driven backwards")
	_expect(one_way_lanes.route(Vector2i(0, 0), Vector2i(10, 1), true).size(), 11, "a lane change costs no extra cells")
	var tractors := RoadNet.new(Content.base().road_types)
	var tractor_lanes := LaneGraph.new(tractors)
	tractors.add(Vector2i(0, 5), Vector2i(10, 5), "tractor_lane")
	_expect(tractor_lanes.route(Vector2i(0, 5), Vector2i(10, 5), true), [] as Array[Vector2i], "lorries can't use the tractor lane")
	_expect(tractor_lanes.route(Vector2i(0, 5), Vector2i(10, 5), false).size(), 11, "tractors can")
	var grid := RoadNet.new(Content.base().road_types)
	var grid_lanes := LaneGraph.new(grid)
	for i in 3:
		grid.add(Vector2i(0, i * 10), Vector2i(30, i * 10), "terminal_2_2")
		grid.add(Vector2i(i * 10 + 5, -5), Vector2i(i * 10 + 5, 25), "terminal_2_2")
	var across := grid_lanes.route(Vector2i(0, 0), Vector2i(25, 20), true)
	_expect(_steps_are_single(across), true, "junction crossings move one cell at a time")
	# East along row 0's eastbound lane to column 25, then down its southbound lane.
	_expect(across.size() - 1, 25 + 20, "a route across a road grid is the shortest by hand")


func _steps_are_single(cells: Array[Vector2i]) -> bool:
	for i in cells.size() - 1:
		var d := (cells[i + 1] - cells[i]).abs()
		if maxi(d.x, d.y) != 1:
			return false
	return true


func _node(net: RoadNet, cell: Vector2i) -> int:
	return net.nodes.find_key(cell)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
