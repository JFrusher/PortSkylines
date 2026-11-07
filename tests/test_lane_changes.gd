extends SceneTree
## M10 step 9: lane changes where marked. A vehicle changes lane along a
## road before its turn, as Cities: Skylines' do, so both lanes of a 2+2
## road carry traffic bound for a T's two ways (M7's "both lanes carry"),
## and on a one-way road a route to the other lane is no longer than one
## along its own ("a lane change costs no extra cells").
## godot --headless --script res://tests/test_lane_changes.gd

const RandomPort := preload("res://tests/random_port.gd")
const STEP := SimClock.TICK_SECONDS

var _failures := 0
var _rules: Dictionary = Content.base()


func _initialize() -> void:
	_test_both_lanes_carry()
	_test_a_lane_change_costs_nothing()
	_test_nearest_is_the_road_lane()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The piece of `network`'s road lanes passing through `position`.
func _piece_at(network: LaneNetwork, position: Vector2) -> int:
	var found := network.nearest(position, false)
	return found[0] if found[0] != 0 and network.point_along(found[0], found[1])[0].distance_to(position) < 0.01 else 0


## M7's lane-use exit criterion: forty lorries come in at the west end of a
## 2+2 road (east along y = 250) to a T with one south down x = 140, all in
## its inner lane, every other one bound south. At x = 135 the outer lane
## carries those turning south and the inner those going on, and every
## lorry gets through.
func _test_both_lanes_carry() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	_expect(sim.apply({"op": "build_road", "from": Vector2i(100, 250), "to": Vector2i(180, 250), "type": "terminal_2_2"}), "", "a 2+2 road east")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(140, 250), "to": Vector2i(140, 290), "type": "terminal_2_2"}), "", "and one south from its middle")
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	var traffic := Traffic.new(network, _rules, Junctions.new(_rules.traffic))
	# Keeping right, the east-bound lanes run along y = 250.5 (inner) and 251.5 (outer).
	var start := _piece_at(network, Vector2(102, 250.5))
	var ends := [_piece_at(network, Vector2(175, 250.5)), _piece_at(network, Vector2(138.5, 285))]
	_expect(ends.has(0) or start == 0, false, "the start and both ends are found")
	var routes := ends.map(func(end: int) -> Array: return network.route(start, end))
	_expect(routes.all(func(r: Array) -> bool: return not r.is_empty()), true, "the inner lane reaches both")
	var outer := {}
	for id: int in network.pieces:
		var piece: Dictionary = network.pieces[id]
		if piece.segment != 0 and Array(piece.points).any(func(p: Vector2) -> bool: return p.distance_to(Vector2(135, 251.5)) < 0.8):
			outer[id] = true
	var at_135 := {}  # each lorry's lane at x = 135: true for the outer
	var waiting := 40
	var through := 0
	for tick in 20000:
		if waiting > 0 and traffic.fits(start, 0.0, _rules.traffic.lorry_m):
			var id := 41 - waiting
			if traffic.place(id, routes[id % 2], _rules.lorry_speed, _rules.traffic.lorry_m):
				waiting -= 1
		traffic.junctions.tick(network, traffic, STEP)
		traffic.tick(STEP)
		for id: int in traffic.cars:
			var car: Dictionary = traffic.cars[id]
			if id not in at_135 and network.point_along(car.route[car.i], car.s)[0].x > 135.0:
				at_135[id] = car.route[car.i] in outer
		for id: int in traffic.cars.keys():
			if traffic.arrived(id):
				traffic.remove(id)
				through += 1
		if through == 40:
			break
	_expect(through, 40, "every lorry gets through the T")
	var outer_south := at_135.keys().filter(func(id: int) -> bool: return at_135[id] and id % 2 == 1).size()
	var inner_on := at_135.keys().filter(func(id: int) -> bool: return not at_135[id] and id % 2 == 0).size()
	_expect([outer_south, inner_on], [20, 20], "at x = 135 the outer lane carries those turning south, the inner those going on")


## A one-way road east along y = 250: from its north lane's start, its
## south lane's end is reached by a route as long as the one to its own end.
func _test_a_lane_change_costs_nothing() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	_expect(sim.apply({"op": "build_road", "from": Vector2i(100, 250), "to": Vector2i(140, 250), "type": "one_way"}), "", "a one-way road")
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	var start := _piece_at(network, Vector2(102, 249.5))
	var own := _piece_at(network, Vector2(138, 249.5))
	var other := _piece_at(network, Vector2(138, 250.5))
	_expect([start != 0, own != 0, other != 0], [true, true, true], "both lanes are found")
	var length := func(route: Array) -> float: return route.reduce(func(sum: float, id: int) -> float: return sum + network.pieces[id].length, 0.0)
	var to_own := network.route(start, own)
	var to_other := network.route(start, other)
	_expect(to_other.is_empty(), false, "the other lane is reached")
	_expect(absf(length.call(to_other) - length.call(to_own)) < 1.0, true, "no further than its own lane's end (%.1f against %.1f)" % [length.call(to_other), length.call(to_own)])



## Where a lane change ends on a lane, the lane is the nearest piece there,
## so an area's driveway beside it joins the road (a gate whose way out met
## a change's end had none, and its lorries never left).
func _test_nearest_is_the_road_lane() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	_expect(sim.apply({"op": "build_road", "from": Vector2i(100, 250), "to": Vector2i(140, 250), "type": "one_way"}), "", "a one-way road")
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	var ends := network.pieces.keys().filter(func(id: int) -> bool: return network.pieces[id].node < 0).map(func(id: int) -> Vector2: return network.pieces[id].points[-1])
	_expect(ends.size(), 2, "a lane change each way")
	for end: Vector2 in ends:
		_expect(network.pieces[network.nearest(end, false)[0]].segment != 0, true, "at a change's end %s the nearest piece is the road lane" % end)
