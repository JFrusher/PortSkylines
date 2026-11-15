extends SceneTree
## M11 ship services: a ship wants bunkers, provisions and waste taken off
## with its class's chances, given when it calls and kept in the save.
## godot --headless --script res://tests/test_services.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_needs_follow_the_chances()
	_test_a_calling_ship_has_its_needs()
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
