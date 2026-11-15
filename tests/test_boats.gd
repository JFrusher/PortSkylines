extends SceneTree
## Pilot boats and tugs on the water: a pilot boat takes its pilot out to a
## Panamax, sails home, and fetches them off once it is alongside, the pilot
## free only once home again; its tugs meet it, stay with it in, then sail
## home. Boats steer round land.
## godot --headless --script res://tests/test_boats.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_a_pilot_and_tugs_see_a_panamax_in()
	_test_boats_steer_round_land()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## AreaPort.base's port, creative, with a pilot station and a tug depot by
## the shore, a pilot and two tugs.
func _port() -> PortSim:
	var rules := RandomPort.quick()
	rules.ship_classes.panamax.pilot = true
	rules.ship_classes.panamax.tugs = 2
	var sim := AreaPort.base(rules, "")
	sim.creative = true
	_expect(sim.apply({"op": "build_pilot_station", "cell": Vector2i(66, 180)}), "", "a pilot station")
	_expect(sim.apply({"op": "hire_pilots", "station": 1, "count": 1}), "", "a pilot")
	_expect(sim.apply({"op": "build_tug_depot", "cell": Vector2i(66, 520)}), "", "a tug depot down the coast")
	_expect(sim.apply({"op": "buy_tugs", "depot": 2, "count": 2}), "", "two tugs")
	return sim


## Every job each boat kind takes, in order, over a Panamax's call.
func _test_a_pilot_and_tugs_see_a_panamax_in() -> void:
	var sim := _port()
	_expect(sim.boats.list.size(), 3, "a boat for the pilot and each tug")
	var ship := PortSim.Ship.new("panamax", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 6000.0, 10, 0)
	ship.id = 100
	sim.ships.append(ship)
	var jobs := {"pilot": [], "tug": []}
	var pilot_aboard_when_moving := true
	for i in roundi(240.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		var before := ship.sail
		sim.tick()
		for boat: Dictionary in sim.boats.list.values():
			var seen: Array = jobs[boat.kind]
			if seen.is_empty() or seen[-1] != boat.job:
				seen.append(boat.job)
		var pilot: Dictionary = sim.boats.list[1]
		if ship.state == PortSim.Ship.State.ARRIVING and ship.sail > before and before == 0.0:
			pilot_aboard_when_moving = pilot.job in ["back", "ashore"] and pilot.ship == ship.id
		if ship.state == PortSim.Ship.State.WORKING and pilot.job == "home" and Marine.free_tugs(sim, 2) == 2:
			break
	_expect(ship.state, PortSim.Ship.State.WORKING, "the Panamax berths")
	_expect(pilot_aboard_when_moving, true, "it sets off only once its pilot is aboard")
	_expect(jobs.pilot, ["home", "out", "back", "ashore", "fetch", "back", "home"], "the pilot boat takes the pilot out, goes home, fetches them and brings them home")
	_expect(jobs.tug, ["home", "out", "with", "back", "home"], "the tugs meet it, see it in and sail home")
	_expect(Marine.free_pilots(sim), 1, "the pilot is free once home")
	_expect(Marine.free_tugs(sim, 2), 2, "the tugs are free once home")


## Round a breakwater between them a boat's way bends, every leg on open
## water; with no water between, there is no way.
func _test_boats_steer_round_land() -> void:
	var sim := _port()
	var a := Vector2(40.5, 300.5)
	var b := Vector2(60.5, 300.5)
	_expect(sim.boats.way(sim.areas, a, b), [b] as Array[Vector2], "open water: straight there")
	_expect(sim.apply({"op": "build_breakwater", "from": Vector2i(50, 280), "to": Vector2i(50, 320)}), "", "a breakwater across the way")
	var way := sim.boats.way(sim.areas, a, b)
	_expect(way.size() > 1, true, "round the breakwater the way bends (%s)" % [way])
	_expect(way[-1] if not way.is_empty() else Vector2.INF, b, "and still gets there")
	var at := a
	var open := true
	for point: Vector2 in way:
		open = open and Boats._open(sim.areas, at, point)
		at = point
	_expect(open, true, "every leg over open water")
	_expect(sim.boats.way(sim.areas, a, Vector2(200.5, 300.5)), [] as Array[Vector2], "no way by water onto land")
