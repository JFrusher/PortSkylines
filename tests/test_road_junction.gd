extends SceneTree
## M10 step 3: a junction trims each of its roads back from the node far
## enough that no two roads' edges overlap, plus the data's corner radius,
## and refuses roads meeting at less than the data's minimum angle. Step 4:
## lanes join across it by M7's turn rules, along short curves.
## godot --headless --script res://tests/test_road_junction.gd

var _failures := 0
var _rules: Dictionary = Content.base().junctions


func _initialize() -> void:
	_test_a_t_junction()
	_test_straight_on_needs_no_trim()
	_test_a_sharp_junction_is_refused()
	_test_wider_roads_trim_further()
	_test_turn_rules_at_a_crossing()
	_test_one_lane_turns_any_way()
	_test_connections_join_their_lanes()
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


## The arms of a crossing of `type` roads, each drawn away from the node:
## east, south, west, north.
func _crossing(type: String) -> Array[Dictionary]:
	var road: Dictionary = Content.base().road_types[type]
	var arms: Array[Dictionary] = []
	for degrees: float in [0.0, 90.0, 180.0, 270.0]:
		arms.append({"direction": Vector2.from_angle(deg_to_rad(degrees)).snapped(Vector2(0.0001, 0.0001)), "road": road})
	return arms


## Which arms a lane `lane` of arm `arm` reaches, as a sorted list.
func _reaches(links: Array[Dictionary], arm: int, lane: int) -> Array:
	var found := {}
	for link: Dictionary in links:
		if link.from == [arm, lane]:
			found[link.to[0]] = true
	var arms := found.keys()
	arms.sort()
	return arms


## Coming in from the west (arm 2) on a 2+2: its left lane turns left
## (north, arm 3), goes straight (east, arm 0) or turns back; its right
## lane turns right (south, arm 1) or goes straight. As _test_lane_rules in
## test_junctions on the grid.
func _test_turn_rules_at_a_crossing() -> void:
	var links := RoadJunction.connections(_crossing("terminal_2_2"), _rules)
	var lanes := RoadCurve.lanes(Content.base().road_types.terminal_2_2)
	# Drawn away from the node, the backward lanes come in: offsets -1.5 and -0.5.
	var inbound := range(lanes.size()).filter(func(k: int) -> bool: return not lanes[k].forward)
	var left: int = inbound.filter(func(k: int) -> bool: return lanes[k].offset == -0.5)[0]
	var right: int = inbound.filter(func(k: int) -> bool: return lanes[k].offset == -1.5)[0]
	_expect(_reaches(links, 2, left), [0, 2, 3], "the left lane goes straight, turns back or turns left")
	_expect(_reaches(links, 2, right), [0, 1], "the right lane goes straight or turns right")


func _test_one_lane_turns_any_way() -> void:
	var links := RoadJunction.connections(_crossing("terminal_1_1"), _rules)
	_expect(_reaches(links, 2, 0), [0, 1, 2, 3], "with one lane in, any turn")


## Each connection curve starts where its arriving lane meets the junction,
## heading the way that lane does, and ends at the leaving lane's start,
## heading its way.
func _test_connections_join_their_lanes() -> void:
	var arms := _crossing("terminal_2_2")
	var trims: Array = RoadJunction.shape(RoadJunction.footprints(arms), _rules).trims
	for link: Dictionary in RoadJunction.connections(arms, _rules):
		var into: Dictionary = arms[link.from[0]]
		var out: Dictionary = arms[link.to[0]]
		var start := RoadJunction.lane_point(into, link.from[1], trims[link.from[0]])
		var end := RoadJunction.lane_point(out, link.to[1], trims[link.to[0]])
		var curve: RoadCurve = link.curve
		_expect(curve.a.distance_to(start) < 0.001 and curve.b.distance_to(end) < 0.001, true, "a connection runs from its lane's end to the next lane's start %s" % [link.from])
		if link.to[0] != link.from[0]:
			_expect(curve.direction_at(0.0).dot(-into.direction) > 0.99, true, "it leaves heading into the junction %s" % [link.from])
			_expect(curve.direction_at(curve.length).dot(out.direction) > 0.99, true, "and ends heading out along its road %s" % [link.to])
