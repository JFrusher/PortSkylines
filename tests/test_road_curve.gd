extends SceneTree
## M10 step 1: a road segment is a quadratic Bézier curve from `a` through
## control point `c` to `b`, measured along its length from a sampled table.
## Step 2: its lanes are the curve offset sideways, backward lanes left of
## the way from a to b and forward ones right, one cell apart.
## godot --headless --script res://tests/test_road_curve.gd

var _failures := 0


func _initialize() -> void:
	_test_a_straight_curve_is_its_line()
	_test_lengths_match_a_fine_sum()
	_test_points_and_directions_along_a_bend()
	_test_nearest_distance()
	_test_lanes_sit_where_grid_lanes_do()
	_test_lanes_on_a_bend_stay_parallel()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _near(actual: float, expected: float, tolerance: float, what: String) -> void:
	_expect(absf(actual - expected) <= tolerance, true, "%s (%.4f, want %.4f ± %.4f)" % [what, actual, expected, tolerance])


## Today's grid road from (0, 0) to (40, 30), as a curve with its control
## point at its middle, is that line: same length, points evenly along it.
func _test_a_straight_curve_is_its_line() -> void:
	var curve := RoadCurve.straight(Vector2(0, 0), Vector2(40, 30))
	_near(curve.length, 50.0, 0.001, "a straight curve is as long as its line")
	for d: float in [0.0, 12.5, 25.0, 50.0]:
		var at := curve.point_at(d)
		_near(at.distance_to(Vector2(40, 30) * d / 50.0), 0.0, 0.001, "the point %.1f along is on the line" % d)
		_near(curve.direction_at(d).distance_to(Vector2(0.8, 0.6)), 0.0, 0.001, "and faces along it")


## Bends of every sharpness are within 0.5% of a sum over 100,000 pieces.
func _test_lengths_match_a_fine_sum() -> void:
	for c: Vector2 in [Vector2(20, 0), Vector2(40, 0), Vector2(0, 40), Vector2(100, -60)]:
		var curve := RoadCurve.new(Vector2(0, 0), c, Vector2(40, 40))
		var fine := 0.0
		var last := Vector2(0, 0)
		for i in range(1, 100001):
			var p := curve.point(i / 100000.0)
			fine += last.distance_to(p)
			last = p
		_near(curve.length, fine, fine * 0.005, "the curve through %s is as long as its fine sum" % c)


## A quarter turn from (0, 0) to (40, 40) with its control point at (40, 0):
## it starts heading east, ends heading south, and its middle by length lies
## on its line of symmetry.
func _test_points_and_directions_along_a_bend() -> void:
	var curve := RoadCurve.new(Vector2(0, 0), Vector2(40, 0), Vector2(40, 40))
	_near(curve.direction_at(0.0).distance_to(Vector2.RIGHT), 0.0, 0.001, "it starts heading east")
	_near(curve.direction_at(curve.length).distance_to(Vector2.DOWN), 0.0, 0.001, "and ends heading south")
	var middle := curve.point_at(curve.length / 2.0)
	_near(middle.x + middle.y, 40.0, 0.05, "its middle by length is on its line of symmetry, x + y = 40")
	_expect(curve.point_at(-5.0), Vector2(0, 0), "a distance before the start is the start")
	_expect(curve.point_at(curve.length + 5.0), Vector2(40, 40), "and past the end is the end")


## The nearest distance along the curve to a point beside it.
func _test_nearest_distance() -> void:
	var line := RoadCurve.straight(Vector2(0, 0), Vector2(40, 0))
	_near(line.nearest(Vector2(10, 7)), 10.0, 0.05, "beside a straight curve, the nearest point is straight across")
	var bend := RoadCurve.new(Vector2(0, 0), Vector2(40, 0), Vector2(40, 40))
	for d: float in [5.0, 20.0, 33.0]:
		var beside := bend.point_at(d) + Vector2(-bend.direction_at(d).y, bend.direction_at(d).x) * 3.0
		_near(bend.nearest(beside), d, 0.1, "3 cells off the bend at %.0f, the nearest is %.0f along" % [d, d])


## On a straight road east, a 1+1 road's lanes run half a cell either side,
## the backward one north, as today's grid lanes do; a 2+2's four lanes
## run 1.5 and 0.5 cells either side.
func _test_lanes_sit_where_grid_lanes_do() -> void:
	var types: Dictionary = Content.base().road_types
	var two := RoadCurve.lanes(types.terminal_1_1)
	_expect(two.map(func(l: Dictionary) -> Array: return [l.offset, l.forward]), [[-0.5, false], [0.5, true]], "a two-lane road: backward on the left, forward on the right")
	var four := RoadCurve.lanes(types.terminal_2_2)
	_expect(four.map(func(l: Dictionary) -> float: return l.offset), [-1.5, -0.5, 0.5, 1.5], "a four-lane road's lanes, one cell apart")
	var road := RoadCurve.straight(Vector2(0, 0), Vector2(10, 0))
	var north := road.offset_points(-0.5)
	_expect(north[0], Vector2(0, -0.5), "the backward lane of a road east runs half a cell north")
	_expect(north[-1], Vector2(10, -0.5), "all along")
	# Today's grid cells for the same lane have their middles on it.
	var cells: Array = RoadNet._lanes(Vector2i(0, 0), Vector2i(10, 0), types.terminal_1_1)[0].cells
	_expect(cells.all(func(cell: Vector2i) -> bool: return is_equal_approx(Vector2(cell).y + 0.5, -0.5)), true, "and today's grid lane has its cell middles on it")


## A 2+2 road round a quarter turn: every lane stays its offset from the
## road's line all along, so they never cross or pinch.
func _test_lanes_on_a_bend_stay_parallel() -> void:
	var bend := RoadCurve.new(Vector2(0, 0), Vector2(40, 0), Vector2(40, 40))
	for lane: Dictionary in RoadCurve.lanes(Content.base().road_types.terminal_2_2):
		var points := bend.offset_points(lane.offset)
		_expect(points.size() > 50, true, "a lane is sampled finely (%d points)" % points.size())
		var worst := 0.0
		for p: Vector2 in points:
			worst = maxf(worst, absf(bend.point_at(bend.nearest(p)).distance_to(p) - absf(lane.offset)))
		_near(worst, 0.0, 0.02, "the lane %.1f cells across stays that far from the line" % lane.offset)
