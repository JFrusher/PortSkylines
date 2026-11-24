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
	_test_boats_serve_a_ship_at_berth()
	_test_unserved_needs_cost_only_what_is_offered()
	_test_a_ship_at_anchor_is_served()
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


## The base port with a services jetty and a boat of each kind, creative.
func _serviced_port() -> PortSim:
	var sim := AreaPort.base()
	sim.creative = true
	sim.apply({"op": "build_services_jetty", "cell": Vector2i(66, 180)})
	var jetty: int = sim.service_jetties.keys()[0]
	for service: String in ["bunkers", "provisions", "waste"]:
		sim.apply({"op": "buy_service_boats", "jetty": jetty, "service": service, "count": 1})
	return sim


## A feeder working at its berth wanting all three services: each boat sails
## out, works its minutes alongside, the fee is paid and the need met, and
## the boats sail home.
func _test_boats_serve_a_ship_at_berth() -> void:
	var sim := _serviced_port()
	var ship: PortSim.Ship = null
	for i in roundi(12 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		ship = null
		for s: PortSim.Ship in sim.ships:
			if s.state == PortSim.Ship.State.WORKING:
				ship = s
		if ship:
			break
	_expect(ship != null, true, "a feeder comes alongside")
	if ship == null:
		return
	ship.needs.assign(["bunkers", "provisions", "waste"])
	var paid_before: int = sim.ledger.today.get("services", 0)
	var served_by := {}
	for i in roundi(6 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for boat: Dictionary in sim.boats.list.values():
			if boat.job == "serve":
				served_by[boat.kind] = true
		if ship.needs.is_empty() or ship.state != PortSim.Ship.State.WORKING:
			break
	var fees := 0
	for service: String in ["bunkers", "provisions", "waste"]:
		fees += sim.rules.ship_classes[ship.kind].services[service].fee
	_expect(served_by.size(), 3, "a boat of each kind worked alongside (%s)" % [served_by.keys()])
	_expect(ship.needs.is_empty(), true, "every need is met while it works")
	_expect(sim.ledger.today.get("services", 0) - paid_before, fees, "and each fee is paid")
	for i in roundi(60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(sim.boats.list.values().all(func(b: Dictionary) -> bool: return b.job == "home"), true, "the boats are home again")


## A ship sailing with needs unmet: only a service the port offers (some
## jetty has its boat) costs its line reputation.
func _test_unserved_needs_cost_only_what_is_offered() -> void:
	var sim := AreaPort.base()
	sim.creative = true
	sim.apply({"op": "build_services_jetty", "cell": Vector2i(66, 180)})
	sim.apply({"op": "buy_service_boats", "jetty": sim.service_jetties.keys()[0], "service": "bunkers", "count": 1})
	var line: String = sim.rules.lines.keys()[0]
	var ship := PortSim.Ship.new("feeder", line, 0.0, 0, 0)
	ship.needs.assign(["bunkers", "provisions"])
	var before: float = sim.contracts.reputation[line]
	Services.sailed(sim, ship)
	var lost: float = before - sim.contracts.reputation[line]
	_expect(is_equal_approx(lost, sim.rules.water.services.unserved_reputation * sim.rules.lines[line].sensitivity), true, "only the unmet bunkers cost reputation (lost %.2f)" % lost)
	_expect(ship.needs.is_empty(), true, "its needs go with it")


## A ship waiting at an anchorage spot is bunkered there.
func _test_a_ship_at_anchor_is_served() -> void:
	var sim := _serviced_port()
	_expect(sim.apply({"op": "build_anchorage", "from": Vector2i(0, 150), "to": Vector2i(49, 249)}), "", "an anchorage")
	var ship := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 6000.0, 0, 0)
	ship.id = 900
	ship.state = PortSim.Ship.State.ANCHORED
	ship.anchorage = sim.anchorages.keys()[0]
	ship.spot = 0
	ship.path.assign([Marine.spots(sim, ship.anchorage)[0]])
	ship.sail = 1.0
	ship.needs.assign(["bunkers"])
	# Lie at anchor: nothing to berth at for now.
	ship.berth = -1
	ship.any_berth = false
	sim.ships.append(ship)
	for i in roundi(4 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if ship.needs.is_empty():
			break
	_expect(ship.state, PortSim.Ship.State.ANCHORED, "it is still at anchor")
	_expect(ship.needs.is_empty(), true, "and bunkered there")
