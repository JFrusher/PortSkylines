extends SceneTree
## M10 step 8d-2a: routes on the lane network go round jams, as M7's did on
## cells: Traffic times how long cars wait on each piece, settles it into a
## smoothed delay each epoch, and a route weighs each piece by its length
## plus the cells that delay is worth; lorries route only on pieces they may
## use.
## godot --headless --script res://tests/test_network_routing.gd

const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0
var _rules: Dictionary = Content.base()


func _initialize() -> void:
	_test_waiting_settles_into_a_delay()
	_test_routes_go_round_a_jam()
	_test_lorries_keep_off_tractor_lanes()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _network(roads: Array) -> LaneNetwork:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	for road: Array in roads:
		_expect(sim.apply({"op": "build_road", "from": road[0], "to": road[1], "type": road[2]}), "", "a road from %s to %s is built" % [road[0], road[1]])
	return LaneNetwork.new(sim.roads, sim.rules.junctions)


func _piece_at(network: LaneNetwork, position: Vector2) -> int:
	for id: int in network.pieces:
		var piece: Dictionary = network.pieces[id]
		if piece.segment != 0 and Geometry2D.get_closest_point_to_segment(position, piece.points[0], piece.points[-1]).distance_to(position) < 0.01:
			return id
	return 0


## Lorries queued at the end of a road wait there; settled, the waiting is
## the piece's delay, seconds per car that entered it.
func _test_waiting_settles_into_a_delay() -> void:
	var network := _network([[Vector2i(100, 250), Vector2i(130, 250), "terminal_1_1"]])
	var traffic := Traffic.new(network, _rules, Junctions.new(_rules.traffic))
	var east := _piece_at(network, Vector2(110, 250.5))
	for id in range(1, 4):
		_expect(traffic.place(id, [east] as Array[int], _rules.lorry_speed, _rules.traffic.lorry_m), true, "lorry %d sets off" % id)
		for i in roundi(8.0 / SimClock.TICK_SECONDS):
			traffic.tick(SimClock.TICK_SECONDS)
	# Long enough for all three to stand in a queue at the road's end.
	for i in roundi(40.0 / SimClock.TICK_SECONDS):
		traffic.tick(SimClock.TICK_SECONDS)
	_expect(traffic.delays().is_empty(), true, "no delay before the epoch settles")
	traffic.settle(1.0)
	_expect(traffic.delays().get(east, 0.0) > 1.0, true, "the queue's waiting is the piece's delay (%.1f s)" % traffic.delays().get(east, 0.0))
	for i in 10:
		traffic.settle(0.5)
	_expect(traffic.delays().get(east, 0.0) > 0.0, true, "it eases off while the cars still stand there")


## A ladder: from an entry road into junction A at (100, 240), two ways to
## junction B at (160, 240), a direct road 60 cells long and one round by
## y = 220, 100 cells, then an exit road on east. `direct` is the direct road's type.
func _ladder(direct: String) -> LaneNetwork:
	return _network([
		[Vector2i(80, 240), Vector2i(100, 240), "terminal_1_1"], [Vector2i(100, 240), Vector2i(160, 240), direct],
		[Vector2i(100, 240), Vector2i(100, 220), "terminal_1_1"], [Vector2i(100, 220), Vector2i(160, 220), "terminal_1_1"],
		[Vector2i(160, 220), Vector2i(160, 240), "terminal_1_1"], [Vector2i(160, 240), Vector2i(180, 240), "terminal_1_1"],
	])


## With a delay on the direct road's eastbound lane worth more than the way
## round, the route goes round; with a small one it doesn't.
func _test_routes_go_round_a_jam() -> void:
	var network := _ladder("terminal_1_1")
	var from := _piece_at(network, Vector2(90, 240.5))
	var to := _piece_at(network, Vector2(170, 240.5))
	var direct := _piece_at(network, Vector2(130, 240.5))
	var clear := network.route(from, to, false)
	_expect(clear.has(direct), true, "with no jam the route takes the direct road")
	_expect(network.route(from, to, false, {direct: 200.0}, 1.0).has(direct), false, "a jam worth more than the way round sends it round")
	_expect(network.route(from, to, false, {direct: 5.0}, 1.0).has(direct), true, "a small one doesn't")


## The direct road is a tractor lane: a tractor takes it, a lorry goes round.
func _test_lorries_keep_off_tractor_lanes() -> void:
	var network := _ladder("tractor_lane")
	var from := _piece_at(network, Vector2(90, 240.5))
	var to := _piece_at(network, Vector2(170, 240.5))
	var tractor := network.route(from, to, false)
	var lorry := network.route(from, to, true)
	_expect(tractor.any(func(id: int) -> bool: return not network.pieces[id].lorries), true, "a tractor takes the tractor lane")
	_expect(lorry.is_empty(), false, "a lorry finds a way")
	_expect(lorry.all(func(id: int) -> bool: return network.pieces[id].lorries), true, "and keeps off it")
