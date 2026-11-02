extends SceneTree
## M10 step 8d-1: signals, priority signs and level crossings on continuous
## traffic, as on today's cells (test_signals): a red holds a lorry until
## its phase comes round, a stop sign stops it for stop_seconds, a give-way
## waits while the other road's approach is busy, and a train's booking of
## a crossing stops a lorry short of it.
## godot --headless --script res://tests/test_traffic_junctions.gd

const RandomPort := preload("res://tests/random_port.gd")
const STEP := SimClock.TICK_SECONDS
const POINT := Vector2i(120, 250)

var _failures := 0
var _rules: Dictionary = Content.base()


func _initialize() -> void:
	_test_red_holds_a_lorry()
	_test_stop_stops()
	_test_give_way_waits_for_the_approach()
	_test_a_train_holds_a_lorry_back()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A 1+1 crossroads at POINT: a road south down x = 120 and one east along
## y = 250, and traffic on it.
func _crossroads() -> Traffic:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	for road: Array in [[Vector2i(100, 250), Vector2i(140, 250)], [Vector2i(120, 230), Vector2i(120, 270)]]:
		_expect(sim.apply({"op": "build_road", "from": road[0], "to": road[1], "type": "terminal_1_1"}), "", "a road is built")
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	return Traffic.new(network, _rules, Junctions.new(_rules.traffic))


func _piece_at(network: LaneNetwork, position: Vector2) -> int:
	for id: int in network.pieces:
		var piece: Dictionary = network.pieces[id]
		if piece.segment != 0 and Geometry2D.get_closest_point_to_segment(position, piece.points[0], piece.points[-1]).distance_to(position) < 0.01:
			return id
	return 0


## A lorry `id` from the west (east-bound) or north (south-bound), straight over.
func _send(traffic: Traffic, id: int, from_west: bool) -> void:
	var network := traffic.network
	var route := network.route(_piece_at(network, Vector2(105, 250.5)), _piece_at(network, Vector2(135, 250.5))) if from_west else network.route(_piece_at(network, Vector2(119.5, 235)), _piece_at(network, Vector2(119.5, 265)))
	_expect(traffic.place(id, route, _rules.lorry_speed, _rules.traffic.lorry_m), true, "lorry %d sets off" % id)


## Whether lorry `id` has crossed the junction: it is past its route's middle piece.
func _across(traffic: Traffic, id: int) -> bool:
	return traffic.cars[id].i >= 2


## Steps `traffic` and its signals on `seconds`.
func _run(traffic: Traffic, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		traffic.junctions.tick(traffic.network, traffic)
		traffic.tick(STEP)


## Signals at the crossroads start with the east-west phase green: a lorry
## from the north waits at its red until its own phase comes round.
func _test_red_holds_a_lorry() -> void:
	var traffic := _crossroads()
	_expect(traffic.junctions.set_signals(traffic.network, POINT, true), "", "signals go up")
	_expect(traffic.junctions.phases(traffic.network, POINT).size(), 2, "two phases, each road's arms together")
	var north_first: bool = Vector2i(0, -1) in traffic.junctions.phases(traffic.network, POINT)[0]
	_send(traffic, 1, false)
	var green: float = _rules.traffic.signal_green_seconds
	_run(traffic, green - 2.0)
	_expect(_across(traffic, 1), north_first, "the lorry from the north crosses only on its own phase")
	_run(traffic, green + 15.0)
	_expect(_across(traffic, 1), true, "and does once its phase comes round")


## A stop sign on the west arm: a lorry from the west stands at the line for
## stop_seconds before it goes in.
func _test_stop_stops() -> void:
	var traffic := _crossroads()
	_expect(traffic.junctions.set_sign(traffic.network, POINT, Vector2i(-1, 0), "stop"), "", "a stop sign on the west arm")
	_send(traffic, 1, true)
	var stopped := 0.0
	for i in roundi(40.0 / STEP):
		traffic.junctions.tick(traffic.network, traffic)
		traffic.tick(STEP)
		if traffic.cars[1].i == 0 and traffic.cars[1].v == 0.0:
			stopped += STEP
	_expect(_across(traffic, 1), true, "the lorry from the west crosses")
	_expect(stopped >= _rules.traffic.stop_seconds - STEP, true, "after standing at the line for the stop (%.1f s)" % stopped)


## A give-way on the west arm under a lorry from the north every 8 s: the
## west lorry books its way in only at a moment no lorry from the north is on
## its approach (with no sign it cuts in between them), and still gets across.
func _test_give_way_waits_for_the_approach() -> void:
	_expect(_cuts_in(true), false, "with a give-way, the west lorry never books in while the north approach is busy")
	_expect(_cuts_in(false), true, "without one it does: the test has teeth")


## Whether the west lorry books its way in while a lorry from the north is on
## its approach, with or without a give-way (`sign`); it must get across.
func _cuts_in(sign: bool) -> bool:
	var traffic := _crossroads()
	if sign:
		traffic.junctions.set_sign(traffic.network, POINT, Vector2i(-1, 0), "give_way")
	var cut := false
	var next_id := 2
	_send(traffic, 1, true)
	for i in roundi(90.0 / STEP):
		if i % roundi(8.0 / STEP) == 0 and next_id < 30:
			var north := traffic.network.route(_piece_at(traffic.network, Vector2(119.5, 235)), _piece_at(traffic.network, Vector2(119.5, 265)))
			if traffic.place(next_id, north, _rules.lorry_speed, _rules.traffic.lorry_m):
				next_id += 1
		var was: int = traffic.cars[1].booked
		var busy := traffic.approach_busy(POINT, Vector2i(0, -1))
		traffic.junctions.tick(traffic.network, traffic)
		traffic.tick(STEP)
		if was == 0 and traffic.cars[1].booked != 0 and busy:
			cut = true
	_expect(_across(traffic, 1), true, "the west lorry gets across (sign %s)" % sign)
	return cut


## Rail track across the east road at x = 110: while a train books it, a
## lorry from the west stops short of it; once it's released, the lorry goes.
func _test_a_train_holds_a_lorry_back() -> void:
	var traffic := _crossroads()
	var crossing: Array[Vector2i] = [Vector2i(110, 249), Vector2i(110, 250)]
	traffic.set_crossings(crossing)
	_expect(traffic.rebook(-1, crossing), true, "a train books the crossing")
	_send(traffic, 1, true)
	_run(traffic, 20.0)
	var car: Dictionary = traffic.cars[1]
	var front: Vector2 = traffic.network.pieces[car.route[car.i]].points[0].lerp(traffic.network.pieces[car.route[car.i]].points[-1], car.s / traffic.network.pieces[car.route[car.i]].length)
	_expect(car.i == 0 and front.x < 110.0, true, "the lorry waits short of the crossing (front at %s)" % front)
	traffic.release(-1)
	_run(traffic, 20.0)
	_expect(_across(traffic, 1), true, "and crosses once the train has gone")
