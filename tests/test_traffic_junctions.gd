extends SceneTree
## M10 step 8d-1: signals, priority signs and level crossings on continuous
## traffic, as on today's cells (test_signals): a red holds a lorry until
## its phase comes round, a stop sign stops it for stop_seconds, a give-way
## waits while the other road's approach is busy, and a train's booking of
## a crossing stops a lorry short of it, and no lorry stops on one.
## godot --headless --script res://tests/test_traffic_junctions.gd

const RandomPort := preload("res://tests/random_port.gd")
const STEP := SimClock.TICK_SECONDS
const POINT := Vector2i(120, 250)

var _failures := 0
var _rules: Dictionary = Content.base()


func _initialize() -> void:
	_test_split_moves_approach()
	_test_red_holds_a_lorry()
	_test_stop_stops()
	_test_give_way_waits_for_the_approach()
	_test_a_train_holds_a_lorry_back()
	_test_no_lorry_stops_on_a_crossing()
	_test_a_queue_at_a_booked_crossing()
	_test_junctions_closer_than_a_lorry()
	_test_a_queue_goes_on_green()
	_test_no_lorry_blocks_the_box()
	_test_signals_run_in_traffic_seconds()
	_test_room_past_short_pieces()
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
		traffic.junctions.tick(traffic.network, traffic, STEP)
		traffic.tick(STEP)


## Signals at the crossroads start with the east-west phase green: a lorry
## from the north waits at its red until its own phase comes round.
func _test_red_holds_a_lorry() -> void:
	var traffic := _crossroads()
	_expect(traffic.junctions.set_signals(traffic.network, POINT, true), "", "signals go up")
	_expect(traffic.junctions.phases(traffic.network, POINT).size(), 2, "two phases, each road's arms together")
	var north_first: bool = LaneNetwork.arm_key(Vector2(0, -1)) in traffic.junctions.phases(traffic.network, POINT)[0]
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
	_expect(traffic.junctions.set_sign(traffic.network, POINT, LaneNetwork.arm_key(Vector2(-1, 0)), "stop"), "", "a stop sign on the west arm")
	_send(traffic, 1, true)
	var stopped := 0.0
	for i in roundi(40.0 / STEP):
		traffic.junctions.tick(traffic.network, traffic, STEP)
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
		traffic.junctions.set_sign(traffic.network, POINT, LaneNetwork.arm_key(Vector2(-1, 0)), "give_way")
	var cut := false
	var next_id := 2
	_send(traffic, 1, true)
	for i in roundi(90.0 / STEP):
		if i % roundi(8.0 / STEP) == 0 and next_id < 30:
			var north := traffic.network.route(_piece_at(traffic.network, Vector2(119.5, 235)), _piece_at(traffic.network, Vector2(119.5, 265)))
			if traffic.place(next_id, north, _rules.lorry_speed, _rules.traffic.lorry_m):
				next_id += 1
		var was: int = traffic.cars[1].booked.size()
		var busy := traffic.approach_busy(POINT, LaneNetwork.arm_key(Vector2(0, -1)))
		traffic.junctions.tick(traffic.network, traffic, STEP)
		traffic.tick(STEP)
		if was == 0 and not traffic.cars[1].booked.is_empty() and busy:
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


## Rail track across the east road at x = 110 and a lorry standing just past
## it: one following stops short of the crossing, not on it, so a train can
## always book it once the cars on it have gone.
func _test_no_lorry_stops_on_a_crossing() -> void:
	var traffic := _crossroads()
	var crossing: Array[Vector2i] = [Vector2i(110, 249), Vector2i(110, 250)]
	traffic.set_crossings(crossing)
	_send(traffic, 1, true)
	var piece: int = traffic.cars[1].route[0]
	var start: Vector2 = traffic.network.pieces[piece].points[0]
	var route: Array[int] = [piece]
	var length: float = _rules.traffic.lorry_m / Grid.CELL
	traffic.place_at(2, route, 112.0 + length - start.x, 0.0, length)
	_run(traffic, 20.0)
	var front: Vector2 = traffic.pose(1)[0]
	_expect(front.x < 110.0, true, "the lorry waits short of the crossing (front at %s)" % front)
	_expect(traffic.rebook(-1, crossing), true, "so a train can book it")


## A lorry waits at a crossing a train has booked: the one behind it stops
## behind it, not on it, though the crossing is further on.
func _test_a_queue_at_a_booked_crossing() -> void:
	var traffic := _crossroads()
	var crossing: Array[Vector2i] = [Vector2i(115, 249), Vector2i(115, 250)]
	traffic.set_crossings(crossing)
	_expect(traffic.rebook(-1, crossing), true, "a train books the crossing")
	_send(traffic, 1, true)
	var piece: int = traffic.cars[1].route[0]
	var start: Vector2 = traffic.network.pieces[piece].points[0]
	var route: Array[int] = [piece]
	var length: float = _rules.traffic.lorry_m / Grid.CELL
	traffic.place_at(2, route, 110.0 - start.x, 0.0, length)
	_run(traffic, 20.0)
	var gap: float = traffic.pose(2)[0].x - length - traffic.pose(1)[0].x
	_expect(gap >= 0.0, true, "the lorry behind stops behind the one ahead (gap %.2f cells)" % gap)


## Two T-junctions 4 cells apart on the east road, closer than a lorry is
## long: a lorry holds the first junction's connection until its rear is
## clear, and books the second's meanwhile, so it gets through both.
func _test_junctions_closer_than_a_lorry() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	for road: Array in [[Vector2i(100, 250), Vector2i(140, 250)], [Vector2i(120, 230), Vector2i(120, 250)], [Vector2i(124, 250), Vector2i(124, 270)]]:
		_expect(sim.apply({"op": "build_road", "from": road[0], "to": road[1], "type": "terminal_1_1"}), "", "a road is built")
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	var traffic := Traffic.new(network, _rules, Junctions.new(_rules.traffic))
	var route := network.route(_piece_at(network, Vector2(105, 250.5)), _piece_at(network, Vector2(135, 250.5)))
	var between: float = network.pieces[route[2]].length
	_expect(between < _rules.traffic.lorry_m / Grid.CELL, true, "the lane between the junctions (%.2f cells) is shorter than a lorry" % between)
	_expect(traffic.place(1, route, _rules.lorry_speed, _rules.traffic.lorry_m), true, "a lorry sets off east")
	_run(traffic, 60.0)
	_expect(traffic.arrived(1), true, "and gets through both junctions")


## Three lorries from the north queue at the red, stepped as the sim steps
## them (a junction tick, then Drive.STEP of traffic): the first waits at the
## line and the others stand still behind it; once their phase comes round,
## the whole queue gets across.
func _test_a_queue_goes_on_green() -> void:
	var traffic := _crossroads()
	_expect(traffic.junctions.set_signals(traffic.network, POINT, true), "", "signals go up")
	var route := traffic.network.route(_piece_at(traffic.network, Vector2(119.5, 235)), _piece_at(traffic.network, Vector2(119.5, 265)))
	var red := roundi(_rules.traffic.signal_green_seconds / SimClock.TICK_SECONDS)
	var sent := 0
	var stood := 0  # ticks a lorry behind another stood still
	for tick in red * 3:
		if sent < 3 and traffic.place(sent + 1, route.duplicate(), _rules.lorry_speed, _rules.traffic.lorry_m):
			sent += 1
		traffic.junctions.tick(traffic.network, traffic, Drive.STEP)
		traffic.tick(Drive.STEP)
		stood += [2, 3].filter(func(id: int) -> bool: return id in traffic.cars and traffic.cars[id].v == 0.0 and traffic.cars[id].i == 0).size()
	_expect(sent, 3, "three lorries queue from the north")
	_expect(stood > 0, true, "the ones behind stand still behind the first (%d lorry ticks)" % stood)
	_expect([_across(traffic, 1), _across(traffic, 2), _across(traffic, 3)], [true, true, true], "and all of them get across once it's their green")


## A lorry stands just past the crossroads on the east road: one from the
## west waits short of the box rather than stopping in it, so one from the
## north still gets across.
func _test_no_lorry_blocks_the_box() -> void:
	var traffic := _crossroads()
	var network := traffic.network
	var east: Array[int] = network.route(_piece_at(network, Vector2(105, 250.5)), _piece_at(network, Vector2(135, 250.5)))
	var length: float = _rules.traffic.lorry_m / Grid.CELL
	traffic.place_at(9, [east[2]] as Array[int], length, 0.0, length)
	_send(traffic, 1, true)
	_run(traffic, 20.0)
	_expect([traffic.cars[1].i, traffic.cars[1].booked], [0, []], "the lorry from the west waits short of the box")
	_send(traffic, 2, false)
	_run(traffic, 20.0)
	_expect(_across(traffic, 2), true, "so the one from the north gets across")


## Signals count their green in the seconds the traffic drives in: stepped
## as the sim steps (a junction tick, then Drive.STEP of traffic), a lorry
## held at the red is across within two greens' worth of traffic seconds,
## not two greens' worth of sim seconds (each a calendar minute).
func _test_signals_run_in_traffic_seconds() -> void:
	var traffic := _crossroads()
	_expect(traffic.junctions.set_signals(traffic.network, POINT, true), "", "signals go up")
	var north_first: bool = LaneNetwork.arm_key(Vector2(0, -1)) in traffic.junctions.phases(traffic.network, POINT)[0]
	_send(traffic, 1, north_first)
	var green: float = _rules.traffic.signal_green_seconds
	for tick in ceili((green * 2.0 + 30.0) / Drive.STEP):
		traffic.junctions.tick(traffic.network, traffic, Drive.STEP)
		traffic.tick(Drive.STEP)
	_expect(_across(traffic, 1), true, "the lorry held at the red is across within %.0f traffic seconds" % (green * 2.0 + 30.0))


## The east road past the crossroads cut into one-cell pieces, as split
## roads and driveways leave it, and nothing on it: a lorry from the west
## finds room past the box however many pieces that takes, and goes.
func _test_room_past_short_pieces() -> void:
	var traffic := _crossroads()
	var network := traffic.network
	var exit: int = network.route(_piece_at(network, Vector2(105, 250.5)), _piece_at(network, Vector2(135, 250.5)))[2]
	var start: Vector2 = network.pieces[exit].points[0]
	for x in range(1, 7):
		network.split_at(start + Vector2(x, 0))
	traffic = Traffic.new(network, _rules, Junctions.new(_rules.traffic))
	_send(traffic, 1, true)
	_run(traffic, 30.0)
	_expect(_across(traffic, 1), true, "the lorry crosses into the cut-up road")


func _test_split_moves_approach() -> void:
	var network := _crossroads().network
	var id: int = network._arm_of.keys()[0]
	var arm: Array = network.arm_of(id).duplicate()
	var point := network.point_along(id, network.pieces[id].length / 2.0)[0]
	_expect(network.split_at(point), id, "split returns first half")
	var rest: int = network.pieces[id].next[0]
	_expect(network.arm_of(id), [], "first half no longer an approach")
	_expect(network.arm_of(rest), arm, "last half owns approach")
	_expect(id in network.approach(arm[0], arm[1]), false, "old approach removed")
	_expect(rest in network.approach(arm[0], arm[1]), true, "new approach registered")
