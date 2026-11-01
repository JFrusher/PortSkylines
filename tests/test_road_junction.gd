extends SceneTree
## M10 step 3: a junction trims each of its roads back from the node far
## enough that no two roads' edges overlap, plus the data's corner radius,
## and refuses roads meeting at less than the data's minimum angle.
## godot --headless --script res://tests/test_road_junction.gd

var _failures := 0
var _rules: Dictionary = Content.base().junctions


func _initialize() -> void:
	_test_a_t_junction()
	_test_straight_on_needs_no_trim()
	_test_a_sharp_junction_is_refused()
	_test_wider_roads_trim_further()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _near(actual: float, expected: float, what: String) -> void:
	_expect(absf(actual - expected) <= 0.001, true, "%s (%.3f, want %.3f)" % [what, actual, expected])


## Roads leaving a node in `directions` (degrees, 0 east, 90 south), each
## `half` cells either side of its line.
func _shape(directions: Array, half: Array) -> Dictionary:
	var roads: Array[Dictionary] = []
	for i in directions.size():
		roads.append({"direction": Vector2.from_angle(deg_to_rad(directions[i])), "half_width": half[i]})
	return RoadJunction.shape(roads, _rules)


## A 2+2 road east-west with a 2+2 stem south: each road's edge clears the
## next at 2 cells (the other's half width at 90°), plus the corner.
func _test_a_t_junction() -> void:
	var shape := _shape([0.0, 180.0, 90.0], [2.0, 2.0, 2.0])
	_expect(shape.get("error", ""), "", "a T junction is built")
	for i in 3:
		_near(shape.trims[i], 2.0 + _rules.corner_cells, "road %d is trimmed back by the stem's half width and the corner" % i)


## Two roads meeting straight on, as one road split at a node, need no trim.
func _test_straight_on_needs_no_trim() -> void:
	var shape := _shape([0.0, 180.0], [2.0, 2.0])
	_expect(shape.trims, [0.0, 0.0], "a road carrying straight on is not trimmed")


func _test_a_sharp_junction_is_refused() -> void:
	var shape := _shape([0.0, 20.0], [1.0, 1.0])
	_expect(shape.get("error", ""), "Roads meet at 20°; a junction needs at least %d°" % roundi(_rules.min_angle), "a 20° junction is refused")
	_expect(_shape([0.0, _rules.min_angle + 1.0], [1.0, 1.0]).get("error", ""), "", "one just over the minimum is built")


## A 2+2 crossing a 1+1 at right angles: the narrow road is trimmed by the
## wide one's half width, the wide by the narrow's.
func _test_wider_roads_trim_further() -> void:
	var shape := _shape([0.0, 90.0, 180.0, 270.0], [2.0, 1.0, 2.0, 1.0])
	_near(shape.trims[1], 2.0 + _rules.corner_cells, "the narrow road clears the wide one")
	_near(shape.trims[0], 1.0 + _rules.corner_cells, "the wide road clears the narrow one")
