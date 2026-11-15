extends SceneTree
## M11 ship services: a ship wants bunkers, provisions and waste taken off
## with its class's chances, given when it calls and kept in the save.
## godot --headless --script res://tests/test_services.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_needs_follow_the_chances()
	_test_a_calling_ship_has_its_needs()
	_test_a_services_jetty_and_its_boats()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Over many calls each service is wanted as often as its class's chance.
func _test_needs_follow_the_chances() -> void:
	var sim := AreaPort.base()
	for kind: String in ["feeder", "ulcv"]:
		var counts := {}
		var calls := 4000
		for i in calls:
			for service: String in Services.wants(sim, kind):
				counts[service] = counts.get(service, 0) + 1
		var services: Dictionary = sim.rules.ship_classes[kind].services
		for service: String in services:
			var share: float = counts.get(service, 0) / float(calls)
			_expect(absf(share - services[service].chance) < 0.03, true, "a %s wants %s on %.2f of calls (chance %.2f)" % [kind, service, share, services[service].chance])


## The base port's feeders call with needs drawn from their class, and a
## saved and loaded port keeps them.
func _test_a_calling_ship_has_its_needs() -> void:
	var sim := AreaPort.base()
	var seen := {}
	for i in roundi(24 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for ship: PortSim.Ship in sim.ships:
			for need: String in ship.needs:
				seen[need] = true
		if seen.size() == 3:
			break
	_expect(seen.keys().all(func(n: String) -> bool: return n in sim.rules.ship_classes.feeder.services), true, "every need is one of its class's services (%s)" % [seen.keys()])
	_expect(seen.is_empty(), false, "calling feeders want services")
	var ship: PortSim.Ship = sim.ships[0] if not sim.ships.is_empty() else null
	if ship:
		ship.needs.assign(["bunkers", "waste"])
		var loaded := PortSim.from_dict(sim.to_dict())
		_expect(loaded.ships[0].needs, ["bunkers", "waste"] as Array[String], "needs are saved")


## A services jetty holds the boats bought for it, each service's kind, and
## their upkeep; it comes out only once every boat is home.
func _test_a_services_jetty_and_its_boats() -> void:
	var sim := AreaPort.base()
	sim.creative = true
	_expect(sim.apply({"op": "build_services_jetty", "cell": Vector2i(66, 180)}), "", "a services jetty by the shore")
	var jetty: int = sim.service_jetties.keys()[0]
	var before := sim.daily_upkeep()
	for service: String in ["bunkers", "provisions", "waste"]:
		_expect(sim.apply({"op": "buy_service_boats", "jetty": jetty, "service": service, "count": 1}), "", "a boat for %s" % service)
	_expect(sim.apply({"op": "buy_service_boats", "jetty": jetty, "service": "tea", "count": 1}), "No such service boat", "no boat for a service there is none of")
	var kinds := sim.boats.of(jetty).map(func(b: int) -> String: return sim.boats.list[b].kind)
	kinds.sort()
	_expect(kinds, ["bunkers", "provisions", "waste"], "one boat of each kind at the jetty")
	var boats_upkeep := 0
	for service: String in sim.rules.water.services.boats:
		boats_upkeep += sim.rules.water.services.boats[service].upkeep
	_expect(sim.daily_upkeep() - before, boats_upkeep, "their upkeep is paid daily")
	var loaded := PortSim.from_dict(sim.to_dict())
	_expect(loaded.service_jetties.keys(), [jetty], "the jetty is saved")
	sim.boats.list[sim.boats.of(jetty)[0]].job = "out"
	_expect(sim.apply({"op": "remove_marine_base", "id": jetty}), "Wait for its boats to come back", "it stays while a boat is out")
	sim.boats.list[sim.boats.of(jetty)[0]].job = "home"
	_expect(sim.apply({"op": "remove_marine_base", "id": jetty}), "", "and comes out once all are home")
	_expect(sim.boats.list.is_empty(), true, "with its boats")
