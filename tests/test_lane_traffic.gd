extends SceneTree
## M2's traffic cases on the 4 m lane graph: head-on traffic passes, a queue
## never shares a cell, a full ring shows as waiting, a vehicle never stops in
## a junction, and traffic merging at 45° takes turns.
## godot --headless --script res://tests/test_lane_traffic.gd

const SPEED := 3.0

var _failures := 0
var _next_id := 1


func _initialize() -> void:
	_test_head_on()
	_test_queue()
	_test_ring_waits()
	_test_never_stops_in_a_junction()
	_test_merge_at_45()
	_test_coming_back_frees_the_cell()
	_test_moves_at_its_speed()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _test_head_on() -> void:
	var net := _net([[Vector2i(0, 5), Vector2i(20, 5), "terminal_1_1"]])
	var lanes := LaneGraph.new(net)
	var traffic := LaneTraffic.new(lanes)
	var vehicles := [_vehicle(traffic, lanes.route(Vector2i(0, 5), Vector2i(19, 5), true)), _vehicle(traffic, lanes.route(Vector2i(19, 4), Vector2i(0, 4), true))]
	var waited := _run(traffic, vehicles, 200)
	_expect(vehicles.all(func(v: Vehicle) -> bool: return v.at_end()), true, "two vehicles pass head-on on a 1+1 road")
	_expect(waited, 0, "neither waits for the other")


func _test_queue() -> void:
	var net := _net([[Vector2i(0, 5), Vector2i(20, 5), "terminal_1_1"]])
	var lanes := LaneGraph.new(net)
	var traffic := LaneTraffic.new(lanes)
	var front := _vehicle(traffic, lanes.route(Vector2i(5, 5), Vector2i(19, 5), true))
	var back := _vehicle(traffic, lanes.route(Vector2i(4, 5), Vector2i(18, 5), true))
	var closest := 99
	for i in 200:
		traffic.advance(back, SPEED * 2)  # the faster one behind moves first
		traffic.advance(front, SPEED)
		closest = mini(closest, front.path[int(front.t)].x - back.path[int(back.t)].x)
	_expect(front.at_end() and back.at_end(), true, "both reach the end")
	_expect(closest >= 1, true, "the one behind never enters the cell ahead while it is held (closest %d)" % closest)


func _test_ring_waits() -> void:
	var net := _net([
		[Vector2i(0, 0), Vector2i(4, 0), "tractor_lane"], [Vector2i(4, 0), Vector2i(4, 4), "tractor_lane"],
		[Vector2i(4, 4), Vector2i(0, 4), "tractor_lane"], [Vector2i(0, 4), Vector2i(0, 0), "tractor_lane"],
	])
	var lanes := LaneGraph.new(net)
	var traffic := LaneTraffic.new(lanes)
	# Keeping right, the forward lanes run round the inside of the 4 by 4 cells
	# the square's lines enclose.
	var loop := lanes.route(Vector2i(1, 0), Vector2i(0, 0), false)
	_expect(loop.size(), 12, "the ring's forward lanes are 12 cells round")
	var vehicles := []
	for i in loop.size():
		var path: Array[Vector2i] = loop.slice(i) + loop.slice(0, i)
		vehicles.append(_vehicle(traffic, path))
	_run(traffic, vehicles, 20)
	# Each first creeps to the end of its own cell, then waits there.
	_expect(vehicles.all(func(v: Vehicle) -> bool: return v.waited > 0 and int(v.t) == 0), true, "a full ring all waits: the give-up valve comes over with the box flow (step 19)")


func _test_never_stops_in_a_junction() -> void:
	var net := _net([[Vector2i(0, 10), Vector2i(20, 10), "terminal_1_1"], [Vector2i(10, 0), Vector2i(10, 20), "terminal_1_1"]])
	var lanes := LaneGraph.new(net)
	var traffic := LaneTraffic.new(lanes)
	var crossing := lanes.route(Vector2i(2, 10), Vector2i(18, 10), true)
	var past: Vector2i = crossing.filter(func(c: Vector2i) -> bool: return c.x > 10 and not lanes.is_junction(c))[0]
	var parked := _vehicle(traffic, [past] as Array[Vector2i])
	var mover := _vehicle(traffic, crossing)
	var stopped_in_junction := false
	for i in 60:
		traffic.advance(mover, SPEED)
		stopped_in_junction = stopped_in_junction or lanes.is_junction(mover.path[int(mover.t)])
	_expect(stopped_in_junction, false, "a vehicle waits short of a junction it can't clear")
	_expect(mover.waited > 0, true, "it waits for the cell past the junction")
	traffic.leave(parked)
	_run(traffic, [mover], 120)
	_expect(mover.at_end(), true, "it crosses once the way is clear")


func _test_merge_at_45() -> void:
	var net := _net([
		[Vector2i(0, 10), Vector2i(10, 10), "one_way"], [Vector2i(10, 10), Vector2i(30, 10), "one_way"],
		[Vector2i(4, 4), Vector2i(10, 10), "one_way"],
	])
	var lanes := LaneGraph.new(net)
	var traffic := LaneTraffic.new(lanes)
	var vehicles := []
	var waiting := []
	for i in 6:
		waiting.append(lanes.route(Vector2i(0, 10), Vector2i(29, 10), true))
		waiting.append(lanes.route(Vector2i(4, 4), Vector2i(29, 10), true))
	var shared := false
	for tick in 600:
		if not waiting.is_empty():
			var vehicle := Vehicle.new(_next_id, "lorry", waiting[0])
			if traffic.place(vehicle):
				_next_id += 1
				waiting.pop_front()
				vehicles.append(vehicle)
		_run(traffic, vehicles, 1)
		var cells := {}
		for vehicle: Vehicle in vehicles:
			if not vehicle.at_end():
				var cell := vehicle.path[int(vehicle.t)]
				shared = shared or cell in cells
				cells[cell] = true
	_expect(waiting.is_empty(), true, "every vehicle from both roads gets on")
	_expect(vehicles.all(func(v: Vehicle) -> bool: return v.at_end()), true, "every vehicle gets through the 45° merge")
	_expect(shared, false, "no two vehicles are ever in one cell")


func _test_coming_back_frees_the_cell() -> void:
	var lanes := LaneGraph.new(_net([]))
	var traffic := LaneTraffic.new(lanes)
	# A route that passes (1, 0) twice, as one turning back at a bend does.
	var loop: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0)]
	var vehicle := _vehicle(traffic, loop)
	while int(vehicle.t) < 2:
		traffic.advance(vehicle, SPEED)
	_expect(traffic.holder(Vector2i(1, 0)), 0, "a cell left behind is free, even though the route comes back to it")
	_expect(traffic.holder(Vector2i(2, 0)), vehicle.id, "the cell it is in is held")


func _test_moves_at_its_speed() -> void:
	var lanes := LaneGraph.new(_net([[Vector2i(0, 5), Vector2i(200, 5), "terminal_1_1"]]))
	var traffic := LaneTraffic.new(lanes)
	for speed: float in [10.0, 31.25, 37.5]:
		var vehicle := _vehicle(traffic, lanes.route(Vector2i(0, 5), Vector2i(199, 5), true))
		for i in SimClock.TICKS_PER_SECOND:
			traffic.advance(vehicle, speed)
		_expect(absf(vehicle.t - speed) < 0.01, true, "on a clear road a vehicle covers its speed in cells a vehicle second (%.2f at %.2f)" % [vehicle.t, speed])
		traffic.leave(vehicle)
	var front := _vehicle(traffic, [Vector2i(30, 5)] as Array[Vector2i])
	var behind := _vehicle(traffic, lanes.route(Vector2i(0, 5), Vector2i(199, 5), true))
	for i in SimClock.TICKS_PER_SECOND:
		traffic.advance(behind, 37.5)
	_expect(behind.path[int(behind.t)], Vector2i(29, 5), "a fast vehicle still stops in the cell behind one ahead")
	traffic.leave(front)
	traffic.leave(behind)


## Runs `vehicles` for `ticks`, removing each at its end. Returns the longest wait.
func _run(traffic: LaneTraffic, vehicles: Array, ticks: int) -> int:
	var most := 0
	for i in ticks:
		for vehicle: Vehicle in vehicles:
			if not vehicle.at_end() and traffic.advance(vehicle, SPEED):
				traffic.leave(vehicle)
			most = maxi(most, vehicle.waited)
	return most


func _net(roads: Array) -> RoadNet:
	var net := RoadNet.new(Content.base().road_types)
	for road: Array in roads:
		_expect(net.add(road[0], road[1], road[2]), "", "road %s to %s is built" % [road[0], road[1]])
	return net


func _vehicle(traffic: LaneTraffic, path: Array[Vector2i]) -> Vehicle:
	var vehicle := Vehicle.new(_next_id, "lorry", path)
	_next_id += 1
	_expect(traffic.place(vehicle), true, "vehicle %d starts in a free cell" % vehicle.id)
	return vehicle


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
