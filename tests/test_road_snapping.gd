extends SceneTree
## M10 step 14: where the road tool's drag ends (RoadNet.snap_drag), as Cities:
## Skylines snaps. Onto a road near the mouse first; else onto a guide line
## near it: on from a road's end, or parallel to a nearby road at the gap
## that just clears it; else its way snaps to the nearest 15° step (from
## east, or from the road it starts on) within ANGLE_SNAP, and its length to
## whole cells.
## godot --headless --script res://tests/test_road_snapping.gd

var _failures := 0
var _types: Dictionary = Content.base().road_types


func _initialize() -> void:
	_test_angle_and_length()
	_test_angles_from_the_road_it_starts_on()
	_test_a_road_wins()
	_test_guides_from_road_ends()
	_test_parallel_roads()
	_test_grid_snap()
	_test_anchors()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.01


func _net() -> RoadNet:
	return RoadNet.new(_types, Content.base().junctions)


## On open ground: a drag 28.5° off east snaps to 30° and 12 cells long; one
## 37.5° off, between steps, keeps its way, its length still whole cells.
func _test_angle_and_length() -> void:
	var net := _net()
	var from := Vector2(100, 100)
	var snapped: Vector2 = net.snap_drag(from, from + Vector2.from_angle(deg_to_rad(28.5)) * 11.7, "terminal_1_1").point
	_expect(_near(snapped, from + Vector2.from_angle(deg_to_rad(30.0)) * 12.0), true, "28.5° snaps to 30°, 11.7 cells to 12 (%s)" % snapped)
	var free: Vector2 = net.snap_drag(from, from + Vector2.from_angle(deg_to_rad(37.5)) * 11.7, "terminal_1_1").point
	_expect(_near(free, from + Vector2.from_angle(deg_to_rad(37.5)) * 12.0), true, "37.5° keeps its way, 12 cells long (%s)" % free)


## From the end of a road 20° off east, a drag about square to it snaps
## square to the road, not to east's 15° steps (110° is one of those too, so
## the drag is at 112° from east, 92° from the road).
func _test_angles_from_the_road_it_starts_on() -> void:
	var net := _net()
	var end := Vector2(100, 100) + Vector2.from_angle(deg_to_rad(20.0)) * 20.0
	_expect(net.add(Vector2(100, 100), end, "terminal_1_1"), "", "a road 20° off east")
	var snapped: Vector2 = net.snap_drag(end, end + Vector2.from_angle(deg_to_rad(112.0)) * 10.0, "terminal_1_1").point
	_expect(_near(snapped, end + Vector2.from_angle(deg_to_rad(110.0)) * 10.0), true, "a drag 92° off it snaps to 90° off it (%s)" % snapped)


## Near a road, the drag ends on it, whatever the angle.
func _test_a_road_wins() -> void:
	var net := _net()
	net.add(Vector2(100, 100), Vector2(140, 100), "terminal_1_1")
	_expect(net.snap_drag(Vector2(120, 80), Vector2(123.4, 98.8), "terminal_1_1").point.distance_to(Vector2(123.4, 100)) < 0.01, true, "a drag ending beside a road ends on it")


## A road east ending at (140, 100): a drag ending a cell off its line further
## east lands on the line, with the guide from the road's end to it.
func _test_guides_from_road_ends() -> void:
	var net := _net()
	net.add(Vector2(100, 100), Vector2(140, 100), "terminal_1_1")
	var found: Dictionary = net.snap_drag(Vector2(160, 120), Vector2(152.3, 100.8), "terminal_1_1")
	_expect(_near(found.point, Vector2(152.3, 100)), true, "onto the line the road's end leads on (%s)" % found.point)
	_expect(found.guides.size(), 1, "with its guide")
	_expect(_near(found.guides[0][0], Vector2(140, 100)) if found.guides.size() == 1 else false, true, "drawn from the road's end")


## A 2+2 road east along y = 100: a 2+2 drag from (110, 104.6) to
## (140, 104.4) ends on the line 4 cells south of it, where its lanes just
## clear the road's.
func _test_parallel_roads() -> void:
	var net := _net()
	net.add(Vector2(100, 100), Vector2(160, 100), "terminal_2_2")
	var found: Dictionary = net.snap_drag(Vector2(110, 104.6), Vector2(140, 104.4), "terminal_2_2")
	_expect(_near(found.point, Vector2(140, 104)), true, "parallel, 4 cells off (%s)" % found.point)
	_expect(found.guides.size(), 1, "with the parallel guide")


## With grid snap on, a drag away from roads ends on a grid point, straight
## or at 45° from its start, as today's grid layouts; one ending near a road
## still ends on it.
func _test_grid_snap() -> void:
	var net := _net()
	net.add(Vector2(100, 100), Vector2(140, 100), "terminal_1_1")
	_expect(net.snap_drag(Vector2(60, 20), Vector2(61.3, 30.2), "terminal_1_1", true).point, Vector2(60, 30), "a nearly upright drag ends straight, on a grid point")
	_expect(net.snap_drag(Vector2(60, 20), Vector2(66.2, 24.4), "terminal_1_1", true), {"point": Vector2(65, 25), "guides": []}, "an in-between one at 45°, with no guides")
	_expect(net.snap_drag(Vector2(120, 80), Vector2(123.4, 98.8), "terminal_1_1", true).point.distance_to(Vector2(123.4, 100)) < 0.01, true, "and one ending beside a road ends on it")


## The highway's anchor at the site edge: a drag ending near it ends on it.
func _test_anchors() -> void:
	var net := _net()
	net.anchors = [Vector2(100, 70)] as Array[Vector2]
	_expect(net.snap_point(Vector2(101, 72)), Vector2(100, 70), "a drag starting near the highway starts on it")
	_expect(net.snap_drag(Vector2(60, 70), Vector2(98, 72), "terminal_1_1").point, Vector2(100, 70), "and one ending near it ends on it")
