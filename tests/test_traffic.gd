extends SceneTree
## M10 step 8b: continuous traffic on the lane network. Vehicles keep the
## standstill gap plus a second of travel behind the one ahead, drive at the
## lower of the road's limit and their own top speed, speed up and brake at
## the data's rates, and never take a connection crossing one in use.
## godot --headless --script res://tests/test_traffic.gd

const RandomPort := preload("res://tests/random_port.gd")
## Seconds per step of these tests.
const STEP := 0.05

var _failures := 0
var _rules: Dictionary = Content.base()


func _initialize() -> void:
	_test_a_queue_stops_at_the_standstill_gap()
	_test_cars_keep_to_the_limit()
	_test_a_follower_keeps_a_second_back()
	_test_crossing_traffic_takes_turns()
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


## The lane piece whose line runs through `position`.
func _piece_at(network: LaneNetwork, position: Vector2) -> int:
	for id: int in network.pieces:
		var piece: Dictionary = network.pieces[id]
		if piece.segment != 0 and Geometry2D.get_closest_point_to_segment(position, piece.points[0], piece.points[-1]).distance_to(position) < 0.01:
			return id
	return 0


## Metres in cells.
func _cells(metres: float) -> float:
	return metres / Grid.CELL


## Five lorries sent along a 1+1 road east, the route ending at its end: they
## all stop there in a queue, each the standstill gap behind the one ahead.
func _test_a_queue_stops_at_the_standstill_gap() -> void:
	var network := _network([[Vector2i(100, 250), Vector2i(160, 250), "terminal_1_1"]])
	var traffic := Traffic.new(network, _rules, Junctions.new(_rules.traffic))
	var east := _piece_at(network, Vector2(130, 250.5))
	var placed := 0
	for i in roundi(120.0 / STEP):
		if placed < 5 and traffic.place(placed + 1, [east] as Array[int], _rules.lorry_speed, _rules.traffic.lorry_m):
			placed += 1
		traffic.tick(STEP)
	_expect(placed, 5, "all five lorries set off")
	var cars := range(1, 6).map(func(id: int) -> Dictionary: return traffic.cars[id])
	_expect(absf(cars[0].s - network.pieces[east].length) < 0.01, true, "the first stops at the road's end")
	for i in range(1, 5):
		var gap: float = cars[i - 1].s - cars[i - 1].length - cars[i].s
		_expect(gap >= _cells(_rules.traffic.standstill_gap_m) - 0.01 and gap <= _cells(_rules.traffic.standstill_gap_m) + 0.25, true, "lorry %d stops the standstill gap behind the one ahead (%.2f cells)" % [i + 1, gap])
		_expect(cars[i].v, 0.0, "and is stopped")


## A tractor alone on a long two-lane road reaches the road's 30 km/h, not its
## own higher top speed... unless its own is lower.
func _test_cars_keep_to_the_limit() -> void:
	var network := _network([[Vector2i(100, 250), Vector2i(199, 250), "terminal_1_1"]])
	var traffic := Traffic.new(network, _rules, Junctions.new(_rules.traffic))
	var east := _piece_at(network, Vector2(130, 250.5))
	var limit: float = _cells(_rules.road_types.terminal_1_1.speed_kmh / 3.6)
	traffic.place(1, [east] as Array[int], limit * 60.0 * Grid.CELL * 2.0, _rules.traffic.tractor_m)
	var fastest := 0.0
	for i in roundi(40.0 / STEP):
		traffic.tick(STEP)
		fastest = maxf(fastest, traffic.cars[1].v)
	_expect(absf(fastest - limit) < 0.01, true, "it drives at the road's limit (%.2f cells/s, limit %.2f)" % [fastest, limit])


## A lorry following a slow one at a steady speed keeps the standstill gap
## plus a second of travel behind it.
func _test_a_follower_keeps_a_second_back() -> void:
	var network := _network([[Vector2i(100, 250), Vector2i(380, 250), "terminal_1_1"]])
	var traffic := Traffic.new(network, _rules, Junctions.new(_rules.traffic))
	var east := _piece_at(network, Vector2(130, 250.5))
	var slow := 1.0  # cells a second
	traffic.place(1, [east] as Array[int], slow * 60.0 * Grid.CELL, _rules.traffic.lorry_m)
	for i in roundi(10.0 / STEP):
		traffic.tick(STEP)
	traffic.place(2, [east] as Array[int], _rules.lorry_speed, _rules.traffic.lorry_m)
	for i in roundi(60.0 / STEP):
		traffic.tick(STEP)
	var lead: Dictionary = traffic.cars[1]
	var follow: Dictionary = traffic.cars[2]
	var gap: float = lead.s - lead.length - follow.s
	var want: float = _cells(_rules.traffic.standstill_gap_m) + slow * _rules.traffic.headway_seconds
	_expect(absf(follow.v - slow) < 0.01, true, "the follower settles at the leader's speed (%.2f)" % follow.v)
	_expect(absf(gap - want) < 0.1, true, "a second of travel plus the standstill gap behind (%.2f cells, want %.2f)" % [gap, want])


## Two 2+2 roads cross; a stream eastbound and a stream southbound, going
## straight over, never both inside crossing connections at once, and every
## car gets across.
func _test_crossing_traffic_takes_turns() -> void:
	var network := _network([[Vector2i(100, 250), Vector2i(160, 250), "terminal_2_2"], [Vector2i(130, 220), Vector2i(130, 280), "terminal_2_2"]])
	var traffic := Traffic.new(network, _rules, Junctions.new(_rules.traffic))
	var routes: Array = []
	for pair: Array in [[Vector2(110, 251.5), Vector2(150, 251.5)], [Vector2(128.5, 230), Vector2(128.5, 270)]]:
		routes.append(network.route(_piece_at(network, pair[0]), _piece_at(network, pair[1])))
	_expect(routes.all(func(r: Array) -> bool: return r.size() == 3), true, "each stream goes straight over")
	var crossing: Array = [routes[0][1], routes[1][1]]
	_expect(crossing[1] in network.conflicts(crossing[0]), true, "the two straight-over connections cross")
	var next_id := 1
	var both := 0
	for i in roundi(120.0 / STEP):
		if next_id <= 8 and i % 40 == 0:
			for route: Array in routes:
				if traffic.place(next_id, route as Array[int], _rules.lorry_speed, _rules.traffic.lorry_m):
					next_id += 1
		traffic.tick(STEP)
		var inside := crossing.map(func(piece: int) -> bool: return traffic.cars.values().any(func(car: Dictionary) -> bool: return car.route[car.i] == piece))
		if inside[0] and inside[1]:
			both += 1
	_expect(both, 0, "the crossing connections are never both in use")
	_expect(next_id, 9, "all eight lorries set off")
	_expect(traffic.cars.values().filter(func(car: Dictionary) -> bool: return car.i > 0).size() >= next_id - 3, true, "and nearly all have crossed")
