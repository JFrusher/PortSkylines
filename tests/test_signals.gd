extends SceneTree
## M7 step E on a 1+1 crossroads, a road south down x = 20 and one east along
## y = 20: signals let one phase into the box at a time, a give-way waits for
## a gap, and a stop sign stops before it goes.
## godot --headless --script res://tests/test_signals.gd

const AreaPort := preload("res://tests/area_port.gd")
const SPEED := 3.0
const NORTH := Vector2i(0, -1)
const WEST := Vector2i(-1, 0)
const POINT := Vector2i(20, 20)

var _failures := 0
var _next_id := 1


func _initialize() -> void:
	var waited := _test_red_holds_traffic(true)
	var red: float = Content.base().traffic.signal_green_seconds / SimClock.TICK_SECONDS / 2.0
	_expect(waited > red, true, "with signals, a lorry from the north stands at the red (%d ticks)" % waited)
	_expect(_test_red_holds_traffic(false), 0, "without, it never stops")
	_test_give_way_waits_for_a_gap()
	_test_stop_stops()
	_test_inspect_and_commands()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _crossroads() -> Array:
	var net := RoadNet.new(Content.base().road_types)
	net.add(Vector2i(20, 0), Vector2i(20, 40), "terminal_1_1")
	net.add(Vector2i(0, 20), Vector2i(40, 20), "terminal_1_1")
	var lanes := LaneGraph.new(net)
	var traffic := LaneTraffic.new(lanes, Junctions.new(Content.base().traffic))
	return [lanes, traffic, traffic.junctions]


## Runs `ticks` ticks of lorries: one from the north (south-bound) every
## `north_every` ticks and one from the west (east-bound) every `west_every`,
## each to the far side. Calls `look` with each lorry and all the moving ones
## right after that lorry moves, when every other lorry stands where the
## lorry saw it; returns {"north", "west"} lorries through.
func _run(lanes: LaneGraph, traffic: LaneTraffic, ticks: int, north_every: int, west_every: int, look: Callable) -> Dictionary:
	var moving: Array[Vehicle] = []
	var through := {"north": 0, "west": 0}
	for tick in ticks:
		for spawn: Array in [["north", north_every, Vector2i(19, 0), Vector2i(19, 39)], ["west", west_every, Vector2i(0, 20), Vector2i(39, 20)]]:
			if spawn[1] > 0 and tick % spawn[1] == 0 and traffic.holder(spawn[2]) == 0:
				var lorry := Vehicle.new(_next_id, spawn[0], lanes.route(spawn[2], spawn[3], true))
				_next_id += 1
				if traffic.place(lorry):
					moving.append(lorry)
		traffic.junctions.tick(lanes, traffic)
		for lorry: Vehicle in moving.duplicate():
			var done := traffic.advance(lorry, SPEED)
			look.call(lorry, moving)
			if done:
				through[lorry.kind] += 1
				traffic.leave(lorry)
				moving.erase(lorry)
	return through


## The first phase lets the east-west arms go, so a lorry from the north
## stands at its red until its own phase comes round, though nothing else is
## about; then lorries from the north get through. Without signals it never
## stops.
func _test_red_holds_traffic(signalled: bool) -> int:
	var made: Array = _crossroads()
	var lanes: LaneGraph = made[0]
	var traffic: LaneTraffic = made[1]
	var junctions: Junctions = made[2]
	if signalled:
		_expect(lanes.arms(POINT).size(), 4, "the crossroads has four arms")
		_expect(junctions.set_signals(lanes, POINT, true), "", "signals go on at the crossroads")
		_expect(junctions.set_signals(lanes, Vector2i(20, 5), true), "No junction there", "but not on a plain road")
		_expect(junctions.phases(lanes, POINT)[0], [WEST, -WEST], "the first phase is west and east")
	var most := {"ticks": 0}
	var through := _run(lanes, traffic, 1200, 200, 0, func(moved: Vehicle, _moving: Array[Vehicle]) -> void:
		most.ticks = maxi(most.ticks, moved.waited))
	_expect(through.north > 0, true, "lorries from the north get through (%d)" % through.north)
	return most.ticks


## A give-way on the west arm, under a lorry from the north every 50 ticks
## (dense enough that without the sign west lorries cut in, 30 times in this
## run): a west lorry goes into the box only while no
## lorry from the north is in it or on its approach, yet it does get through.
func _test_give_way_waits_for_a_gap() -> void:
	var made: Array = _crossroads()
	var lanes: LaneGraph = made[0]
	var traffic: LaneTraffic = made[1]
	var junctions: Junctions = made[2]
	_expect(junctions.set_sign(lanes, POINT, WEST, "give_way"), "", "the west arm gives way")
	var box := lanes.box(POINT)
	var watched := lanes.approach(POINT, NORTH) + box
	var count := {"bad": 0, "entries": 0}
	var was_out := {}
	var through := _run(lanes, traffic, 6000, 50, 40, func(moved: Vehicle, moving: Array[Vehicle]) -> void:
		if moved.kind != "west":
			return
		var inside: bool = moved.path[int(moved.t)] in box
		if inside and was_out.get(moved.id, true):
			count.entries += 1
			if moving.any(func(v: Vehicle) -> bool: return v.kind == "north" and v.path[int(v.t)] in watched):
				count.bad += 1
		was_out[moved.id] = not inside)
	_expect(count.entries > 10, true, "west lorries go into the box (%d times)" % count.entries)
	_expect(count.bad, 0, "a west lorry never goes in while a north lorry is near or in the box")
	_expect(through.west > 10, true, "and west lorries still get through (%d)" % through.west)


## A stop sign on the west arm, with no other traffic: a west lorry stands
## at the line for stop_seconds before it goes into the box.
func _test_stop_stops() -> void:
	var made: Array = _crossroads()
	var lanes: LaneGraph = made[0]
	var traffic: LaneTraffic = made[1]
	var junctions: Junctions = made[2]
	_expect(junctions.set_sign(lanes, POINT, WEST, "stop"), "", "the west arm has a stop sign")
	var box := lanes.box(POINT)
	var most := {"ticks": 0}
	_run(lanes, traffic, 400, 0, 1000, func(moved: Vehicle, _moving: Array[Vehicle]) -> void:
		most.ticks = maxi(most.ticks, moved.waited))
	_expect(most.ticks * SimClock.TICK_SECONDS >= Content.base().traffic.stop_seconds, true, "the lorry stood at the line for %.2f s" % (most.ticks * SimClock.TICK_SECONDS))


## In the game: Inspect picks the T the test port's coast road makes where
## it bends into the east road, with a stub road on south from the bend, and
## the commands the panel's buttons send set it up.
func _test_inspect_and_commands() -> void:
	var sim := AreaPort.terminal(80)
	var point := Vector2i(86, sim.site_entry().y)
	sim.creative = true
	_expect(sim.apply({"op": "build_road", "from": point, "to": point + Vector2i(0, 20), "type": "terminal_1_1"}), "", "a stub road south makes the bend a T")
	var picked: Variant = Inspect.pick(sim, sim.lanes.box(point)[0])
	_expect(picked, {"junction": point}, "a click in the box picks the junction")
	_expect(Inspect.describe(sim, picked).slice(0, 2), ["Junction of 3 roads", "No signals"] as Array[String], "it says what it is")
	_expect(sim.apply({"op": "set_signals", "point": point, "on": true}), "", "signals go on")
	_expect(Inspect.describe(sim, picked)[1].begins_with("Phase 1, north and south: 20 s green"), true, "phases show with their green time (%s)" % Inspect.describe(sim, picked)[1])
	_expect(sim.apply({"op": "set_green", "point": point, "phase": 1, "seconds": 2.0}), "Green lasts 5 to 120 s", "a green too short is refused")
	_expect(sim.apply({"op": "set_green", "point": point, "phase": 1, "seconds": 30.0}), "", "a green in range is set")
	_expect(sim.apply({"op": "set_sign", "point": point, "arm": Vector2i(1, 0), "sign": "stop"}), "", "the east arm gets a stop sign")
	_expect(Inspect.describe(sim, picked)[-1], "From the east: stop", "and shows it")
	var copy := PortSim.from_dict(sim.to_dict())
	_expect(copy.lane_traffic.junctions.to_dict(), sim.lane_traffic.junctions.to_dict(), "signals and signs survive a save")
