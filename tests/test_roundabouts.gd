extends SceneTree
## M10 step 17: roundabouts. The circle tool builds a one-way ring of
## "roundabout" road around a centre (build_roundabout), running anticlockwise
## as seen from above so traffic keeps right; roads joining it give way to
## traffic on the ring unless given a sign of their own.
## godot --headless --script res://tests/test_roundabouts.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")
const CENTRE := Vector2(130, 250)

var _failures := 0


func _initialize() -> void:
	_test_a_ring_is_built()
	_test_entries_give_way()
	_test_a_ring_over_water_is_refused()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _port() -> PortSim:
	return AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))


## A ring of radius 10: eight pieces of roundabout road, each node a bend of
## two, every piece within a cell of the circle, running anticlockwise (from
## its east point it heads north); traffic can drive all the way round.
func _test_a_ring_is_built() -> void:
	var sim := _port()
	_expect(sim.apply({"op": "build_roundabout", "centre": CENTRE, "radius": 10.0}), "", "a roundabout is built")
	_expect(sim.roads.segments.size(), 8, "of eight pieces")
	_expect(sim.roads.segments.values().all(func(r: Dictionary) -> bool: return r.type == "roundabout"), true, "all roundabout road")
	_expect(sim.roads.nodes.keys().all(func(n: int) -> bool: return sim.roads.degree(n) == 2), true, "each node a bend of two")
	var on_circle := true
	for id: int in sim.roads.segments:
		var curve := sim.roads.curve(id)
		for d: float in [0.0, curve.length / 2.0, curve.length]:
			on_circle = on_circle and absf(curve.point_at(d).distance_to(CENTRE) - 10.0) < 0.2
	_expect(on_circle, true, "keeping to the circle")
	var east: int = sim.roads.segments.keys().filter(func(id: int) -> bool: return sim.roads.nodes[sim.roads.segments[id].a].distance_to(CENTRE + Vector2(10, 0)) < 0.01)[0]
	_expect(sim.roads.curve(east).direction_at(0.0).y < -0.9, true, "from its east point it heads north")
	Drive._refresh(sim)
	var network := sim.network
	var start: int = network.nearest(CENTRE + Vector2(10.5, 0), false)[0]
	var across: int = network.nearest(CENTRE + Vector2(-10.5, 0), false)[0]
	_expect(network.route(start, across).is_empty() or network.route(across, start).is_empty(), false, "traffic drives all the way round")


## A 2+2 road from the west ending on the ring: it gives way, the ring doesn't.
func _test_entries_give_way() -> void:
	var sim := _port()
	sim.apply({"op": "build_roundabout", "centre": CENTRE, "radius": 10.0})
	_expect(sim.apply({"op": "build_road", "from": Vector2(90, 250), "to": CENTRE + Vector2(-10, 0), "type": "terminal_2_2"}), "", "a road from the west joins it")
	var point: Vector2 = CENTRE + Vector2(-10, 0)
	var lanes := Drive.junction_lanes(sim)
	var junctions := Drive.junctions(sim)
	_expect(sim.roads.degree(sim.roads.nodes.find_key(point)), 3, "a junction of three roads")
	_expect(lanes.arms(point).size(), 2, "two with lanes coming in: the road and the ring before it (the ring after only leaves)")
	var road := LaneNetwork.arm_key(Vector2(-1, 0))
	_expect(junctions.sign_at(lanes, point, road), "give_way", "the road gives way")
	for arm: Vector2i in lanes.arms(point):
		if arm != road:
			_expect(junctions.sign_at(lanes, point, arm), "", "the ring doesn't")
	_expect(sim.apply({"op": "set_sign", "point": point, "arm": road, "sign": "stop"}), "", "a stop sign on the road")
	_expect(junctions.sign_at(lanes, point, road), "stop", "is its own")


func _test_a_ring_over_water_is_refused() -> void:
	var sim := _port()
	var water := Vector2(75, 40)  # out in the sea, as test_roads' road into it
	_expect(sim.apply({"op": "build_roundabout", "centre": water, "radius": 10.0}) != "", true, "a roundabout over water is refused")
	_expect(sim.roads.segments.size(), 0, "and nothing of it is built")
