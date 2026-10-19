extends SceneTree
## Headless tests for roads and areas on the 4 m grid.
## godot --headless --script res://tests/test_roads.gd

var _failures := 0


func _initialize() -> void:
	_test_segments()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _test_segments() -> void:
	var net := RoadNet.new()
	_expect(net.add(Vector2i(0, 0), Vector2i(5, 0)), "", "a straight road is built")
	_expect(net.add(Vector2i(5, 0), Vector2i(8, 3)), "", "a 45° road is built")
	_expect(net.add(Vector2i(0, 0), Vector2i(2, 5)), "Roads run straight or at 45°", "other angles are refused")
	_expect(net.add(Vector2i(4, 4), Vector2i(4, 4)), "A road needs a length", "a road has a length")
	_expect(net.nodes.size(), 3, "roads meeting at a cell share its node")
	_expect(net.cells(1), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)] as Array[Vector2i], "a straight road covers each cell along it")
	var diagonal := net.cells(2)
	_expect(diagonal.size(), 4, "a 45° road of 3 cells' run covers 4 cells")
	var connected := true
	for i in diagonal.size() - 1:
		connected = connected and (diagonal[i + 1] - diagonal[i]).abs() == Vector2i.ONE
	_expect(connected, true, "a 45° road is a connected diagonal run")
	_expect(RoadNet.line(Vector2i(3, 3), Vector2i(3, 0)), [Vector2i(3, 3), Vector2i(3, 2), Vector2i(3, 1), Vector2i(3, 0)] as Array[Vector2i], "a line runs from its first end")


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
