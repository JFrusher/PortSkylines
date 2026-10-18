extends SceneTree
## Lanes: traffic passes both ways on a one-tile road, queues one way, and a
## ring of vehicles all waiting on each other clears through the give-up valve.
## godot --headless --script res://tests/test_traffic.gd

var _failures := 0


func _initialize() -> void:
	_test_head_on_traffic_passes()
	_test_queue_never_shares_a_lane()
	_test_deadlocked_ring_clears()
	_test_blocked_lorry_gives_up()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A sim with no ships, a straight road along row 5 from x=20 to x=40.
func _road_sim() -> PortSim:
	var rules := Content.base().duplicate(true)
	rules.first_ship_minutes = 1e9
	var sim := PortSim.new(0, rules)
	for x in range(20, 41):
		sim.map.place(PortMap.Tile.ROAD, Vector2i(x, 5))
	return sim


## Puts a lorry with an import box on `path`: it drives to the end and leaves.
func _lorry(sim: PortSim, path: Array[Vector2i]) -> Vehicle:
	var lorry := Vehicle.new(sim.vehicles.size() + 100, "lorry", path)
	lorry.box = sim._new_box("import", 0.0)
	lorry.loaded = true
	lorry.lane = Traffic.lane(sim.map, path, 0)
	_expect(sim.traffic.claim(lorry.lane, lorry.id), true, "lorry %d starts in a free lane" % lorry.id)
	sim.vehicles.append(lorry)
	return lorry


func _row(from: int, to: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	for x in range(from, to + (1 if to >= from else -1), 1 if to >= from else -1):
		path.append(Vector2i(x, 5))
	return path


func _test_head_on_traffic_passes() -> void:
	var sim := _road_sim()
	_lorry(sim, _row(20, 40))
	_lorry(sim, _row(40, 20))
	var most_waited := 0
	for i in 200:
		for vehicle: Vehicle in sim.vehicles:
			most_waited = maxi(most_waited, vehicle.waited)
		sim.tick()
	_expect(sim.vehicles.is_empty(), true, "two lorries pass head-on on a one-tile road")
	_expect(most_waited, 0, "neither waits for the other")


func _test_queue_never_shares_a_lane() -> void:
	var sim := _road_sim()
	var front := _lorry(sim, _row(25, 40))
	var back := _lorry(sim, _row(24, 40))
	front.t = 0.0
	sim.vehicles.erase(front)
	sim.vehicles.append(front)  # the one behind moves first each tick
	var closest := 99.0
	for i in 200:
		sim.tick()
		if front in sim.vehicles and back in sim.vehicles:
			closest = minf(closest, (front.path[int(front.t)].x) - (back.path[int(back.t)].x))
	_expect(sim.vehicles.is_empty(), true, "both lorries reach the end")
	_expect(closest >= 1, true, "the one behind never enters the tile ahead while it is held (closest %.0f)" % closest)


func _test_deadlocked_ring_clears() -> void:
	var rules := Content.base().duplicate(true)
	rules.first_ship_minutes = 1e9
	var sim := PortSim.new(0, rules)
	var ring: Array[Vector2i] = [Vector2i(30, 30), Vector2i(31, 30), Vector2i(31, 31), Vector2i(30, 31)]
	for cell in ring:
		sim.map.place(PortMap.Tile.ROAD, cell)
	for start in 4:
		var path: Array[Vector2i] = []
		for step in 9:
			path.append(ring[(start + step) % 4])
		_lorry(sim, path)
	var limit := roundi(sim.rules.give_up_seconds / SimClock.TICK_SECONDS)
	for i in 10:
		sim.tick()
	_expect(sim.vehicles.all(func(v: Vehicle) -> bool: return v.waited > 0), true, "four lorries in a full ring all wait on each other")
	for i in limit * 2 + 400:
		sim.tick()
	_expect(sim.vehicles.is_empty(), true, "the ring clears within twice the give-up time")


## A broken-down vehicle holds the only lane ahead on a dead end: the lorry
## behind finds no way round and gives up after twice the give-up time.
func _test_blocked_lorry_gives_up() -> void:
	var sim := _road_sim()
	var lorry := _lorry(sim, _row(20, 40))
	_expect(sim.traffic.claim(Traffic.lane(sim.map, _row(20, 40), 5), 999), true, "a breakdown holds the lane at x=25")
	var limit := roundi(sim.rules.give_up_seconds / SimClock.TICK_SECONDS)
	for i in limit * 2 + 40:
		sim.tick()
	_expect(lorry.replanned, true, "the lorry looked for a way round")
	_expect([sim.vehicles.size(), sim.gave_up], [0, 1], "then gave up and left")
	_expect(sim.last_event().contains("gave up"), true, "the status says so")
