extends SceneTree
## M10 step 13: curved roads by command. A road with a control point off its
## line is built as that curve; one crossing a straight road splits both at
## the crossing point, each piece keeping its part of the curve; a junction
## checks the curve's own way where it meets; a curve tighter than its lanes
## can take is refused.
## godot --headless --script res://tests/test_road_curves.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_a_curve_is_built()
	_test_a_curve_crossing_a_road()
	_test_a_curve_meets_at_its_own_angle()
	_test_too_tight_is_refused()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _port() -> PortSim:
	return AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))


func _curve(sim: PortSim, from: Vector2, control: Vector2, to: Vector2, type := "terminal_2_2") -> String:
	return sim.apply({"op": "build_road", "from": from, "control": control, "to": to, "type": type})


## Whether `point` lies on `curve`, within a hundredth of a cell.
func _on(curve: RoadCurve, point: Vector2) -> bool:
	return curve.point_at(curve.nearest(point)).distance_to(point) < 0.01


## A curve from (100, 250) bowing north through control (120, 230) to (140, 250).
func _test_a_curve_is_built() -> void:
	var sim := _port()
	_expect(_curve(sim, Vector2(100, 250), Vector2(120, 230), Vector2(140, 250)), "", "a curve is built")
	_expect(sim.roads.segments.size(), 1, "as one road")
	var road: Dictionary = sim.roads.segments[1]
	_expect(road.control, Vector2(120, 230), "with its control point")
	_expect(sim.roads.curve(1).length > 44.0, true, "longer than its chord (%.1f)" % sim.roads.curve(1).length)
	_expect(sim.roads.ground(1).any(func(c: Vector2i) -> bool: return c.y < 242), true, "standing where it bows")


## A straight road north to south down x = 120 across the curve's top: both
## split where they cross, at about (120, 240), and each half of the curve
## lies on the curve as drawn.
func _test_a_curve_crossing_a_road() -> void:
	var sim := _port()
	var drawn := RoadCurve.new(Vector2(100, 250), Vector2(120, 230), Vector2(140, 250))
	_expect(_curve(sim, Vector2(100, 250), Vector2(120, 230), Vector2(140, 250)), "", "a curve")
	_expect(sim.apply({"op": "build_road", "from": Vector2(120, 220), "to": Vector2(120, 260), "type": "terminal_2_2"}), "", "a road across its top")
	_expect(sim.roads.segments.size(), 4, "both split at the crossing")
	var top: Array = sim.roads.nodes.values().filter(func(p: Vector2) -> bool: return p.distance_to(Vector2(120, 240)) < 0.05)
	_expect(top.size(), 1, "a node where they cross, at (120, 240)")
	for id: int in sim.roads.segments:
		var piece := sim.roads.curve(id)
		if absf(piece.a.x - piece.b.x) > 1.0:
			for d: float in [0.0, piece.length / 3.0, piece.length * 2.0 / 3.0, piece.length]:
				_expect(_on(drawn, piece.point_at(d)), true, "segment %d keeps to the curve as drawn" % id)


## A road east to (100, 250), and a curve from its end heading back 20°
## off it, north of west, then bending away to (85, 235): refused, though
## its chord leaves the road at 45°.
func _test_a_curve_meets_at_its_own_angle() -> void:
	var sim := _port()
	_expect(sim.apply({"op": "build_road", "from": Vector2(80, 250), "to": Vector2(100, 250), "type": "terminal_2_2"}), "", "a road east to (100, 250)")
	var control := Vector2(100, 250) + Vector2(cos(deg_to_rad(200.0)), sin(deg_to_rad(200.0))) * 8.0
	var err := _curve(sim, Vector2(100, 250), control, Vector2(85, 235))
	_expect(err.begins_with("Roads meet at 20°"), true, "a curve leaving at 20° is refused, by its own way (%s)" % err)


## A 2+2 curve turning through a radius smaller than its lanes can take is
## refused; a gentle one is built.
func _test_too_tight_is_refused() -> void:
	var sim := _port()
	var err := _curve(sim, Vector2(100, 250), Vector2(140, 250), Vector2(100, 252))
	_expect(err.begins_with("Too tight a curve"), true, "a hairpin is refused (%s)" % err)
	_expect(_curve(sim, Vector2(100, 250), Vector2(130, 240), Vector2(160, 250)), "", "a gentle curve is built")
