extends SceneTree
## M10 step 12c: roads meeting at any angle, by commands. A road crossing
## another splits both at the exact crossing point; one ending on or near
## another's line or end joins it there; junctions sharper than min_angle
## are refused, as is a road along another; road and track cross down to
## min_angle too.
## godot --headless --script res://tests/test_road_meetings.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_crossing_at_an_angle()
	_test_ending_on_a_road()
	_test_ending_near_a_road_end()
	_test_too_sharp_is_refused()
	_test_along_another_is_refused()
	_test_track_at_an_angle()
	_test_junctions_need_room()
	_test_the_tool_snaps_onto_roads()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A road north to south across the road at x = 130, then another at x = 132:
## the 2-cell stretch of the road between them is shorter than both junctions
## cut it back, leaving it no lane, so the second is refused; one at x = 140
## is built.
func _test_junctions_need_room() -> void:
	var sim := _port()
	_expect(_road(sim, Vector2i(130, 230), Vector2i(130, 270), "terminal_1_1"), "", "a 1+1 road across at x = 130")
	_expect(_road(sim, Vector2i(132, 230), Vector2i(132, 270), "terminal_1_1"), "Too close to a junction: a road needs room between its junctions", "one two cells on is refused")
	_expect(_road(sim, Vector2i(140, 230), Vector2i(140, 270), "terminal_1_1"), "", "one ten cells on is built")


## The straight tool (12d) snaps a drag's end onto the roads: to a road's
## end within SNAP_CELLS before any other point, else onto the nearest point
## of a road's line that close, at any angle; never back onto the road the
## drag starts on; and nowhere when no road is that near.
func _test_the_tool_snaps_onto_roads() -> void:
	var sim := _port()
	var roads := sim.roads
	_expect(roads.snap_point(Vector2(158, 252)), Vector2(160, 250), "near its end, a drag snaps to the end")
	_expect(roads.snap_point(Vector2(131.3, 252)).distance_to(Vector2(131.3, 250)) < 0.01, true, "near its line, to the nearest point on it")
	_expect(roads.snap_point(Vector2(131.3, 252), Vector2(120, 250)), Vector2(131.3, 252), "but not back onto the road the drag starts on")
	_expect(roads.snap_point(Vector2(131.3, 256)), Vector2(131.3, 256), "and not from further than SNAP_CELLS")
	var at: Vector2 = roads.snap_point(Vector2(132.4, 247.5))
	_expect(_road(sim, Vector2i(150, 225), Vector2i(150, 235)), "", "a road north of it")
	_expect(at.distance_to(Vector2(132.4, 250)) < 0.01, true, "a drag ending beside the road snaps onto it")
	_expect(sim.apply({"op": "build_road", "from": Vector2(150, 235), "to": at, "type": "terminal_1_1"}), "", "a drag from that road's end to the snapped point builds a road at any angle")
	_expect(_node(sim, at) != 0, true, "ending on the road at the snapped point (nodes near: %s)" % sim.roads.nodes.values().filter(func(p: Vector2) -> bool: return p.distance_to(at) < 3.0))


## A port with a 2+2 road east along y = 250 from x = 100 to 160.
func _port() -> PortSim:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	_expect(_road(sim, Vector2i(100, 250), Vector2i(160, 250)), "", "a road east")
	return sim


func _road(sim: PortSim, from: Vector2i, to: Vector2i, type := "terminal_2_2") -> String:
	return sim.apply({"op": "build_road", "from": from, "to": to, "type": type})


## The node within a hundredth of a cell of `at`, or 0.
func _node(sim: PortSim, at: Vector2) -> int:
	for id: int in sim.roads.nodes:
		if sim.roads.nodes[id].distance_to(at) < 0.01:
			return id
	return 0


## A road from (110, 239) to (150, 263), 31° off east, crosses at
## x = 128.33..., off the grid: both roads split there into a 4-way junction.
func _test_crossing_at_an_angle() -> void:
	var sim := _port()
	_expect(_road(sim, Vector2i(110, 239), Vector2i(150, 263)), "", "a road 31° off east across it")
	var at := Vector2(110, 239) + Vector2(40, 24) * (11.0 / 24.0)
	var node := _node(sim, at)
	_expect(node != 0, true, "a node at the crossing point %s" % at)
	_expect(sim.roads.degree(node) if node else 0, 4, "where four roads meet")
	_expect(sim.roads.segments.size(), 4, "both roads split there")
	Drive._refresh(sim)
	_expect(sim.network.arms(sim.roads.nodes[node]).size() if node else 0, 4, "and the lane network makes it a junction of four arms")


## A road from (125, 220) to (130, 249) ends a cell short of the road's line,
## within its half width: it joins it at a T on the line, at the point nearest
## its end.
func _test_ending_on_a_road() -> void:
	var sim := _port()
	_expect(_road(sim, Vector2i(125, 220), Vector2i(130, 249)), "", "a road ending a cell short of the road")
	var t := _node(sim, Vector2(130, 250))
	_expect(sim.roads.degree(t) if t else 0, 3, "joins it at a T on its line")


## A road ending a cell and a half from the road's east end, within its half
## width, joins that end: a bend, not a new node.
func _test_ending_near_a_road_end() -> void:
	var sim := _port()
	var nodes := sim.roads.nodes.size()
	_expect(_road(sim, Vector2i(180, 230), Vector2i(161, 251)), "", "a road ending a cell off the road's end")
	_expect(sim.roads.nodes.size(), nodes + 1, "only its far end is a new node")
	_expect(sim.roads.degree(_node(sim, Vector2(160, 250))), 2, "it joins the end")


## A road ending on the road 20° off it is refused; at 31° it is built.
func _test_too_sharp_is_refused() -> void:
	var sim := _port()
	var sharp := _road(sim, Vector2i(100, 239), Vector2i(130, 250))
	_expect(sharp.begins_with("Roads meet at 20°"), true, "a junction of 20° is refused (%s)" % sharp)
	_expect(_road(sim, Vector2i(114, 232), Vector2i(144, 250)), "", "one of 31° is built")


## A road laid along the road, a cell off its line, is refused.
func _test_along_another_is_refused() -> void:
	var sim := _port()
	_expect(_road(sim, Vector2i(110, 251), Vector2i(150, 251)), "A road already runs here", "a road along it is refused")


## Straight track north to south down x = 130 (track stays straight or at
## 45° until step 19): a road 31° off east, 59° off the track, crosses it and
## makes a level crossing; one 20° off the track is refused.
func _test_track_at_an_angle() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(RandomPort.quick()), true))
	_expect(sim.apply({"op": "build_rail", "from": Vector2i(130, 220), "to": Vector2i(130, 280)}), "", "track north to south")
	_expect(_road(sim, Vector2i(110, 239), Vector2i(150, 263)), "", "a road 31° off east, 59° off the track, crosses it")
	_expect(Drive.crossings(sim).is_empty(), false, "a level crossing")
	_expect(_road(sim, Vector2i(115, 225), Vector2i(118, 235)), "", "a road ending clear of both is fine")
	var shallow := _road(sim, Vector2i(122, 228), Vector2i(140, 278))
	_expect(shallow.begins_with("Road and track cross at"), true, "a road 20° off the track is refused (%s)" % shallow)
