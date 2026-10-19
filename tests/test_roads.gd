extends SceneTree
## Headless tests for roads and areas on the 4 m grid.
## godot --headless --script res://tests/test_roads.gd

var _failures := 0


func _initialize() -> void:
	_test_segments()
	_test_lanes()
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


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
