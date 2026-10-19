extends SceneTree
## The guided start, played by commands on the base rules from the start
## money: each command group completes the next step, in order, and the guide
## ends once a ship is worked.
## godot --headless --script res://tests/test_guide.gd

## Calendar days the test waits at most for an offer and then for a ship.
const DAYS := 7

var _failures := 0


func _initialize() -> void:
	var sim := PortSim.new(1)
	var entry := sim.site_entry()
	# The coast road runs south along x = 85, so an apron on its west side
	# reaches the water; the east road runs from it to the highway.
	var steps: Array[Array] = [
		[{"op": "build_road", "from": Vector2i(85, entry.y - 70), "to": Vector2i(85, entry.y), "type": "terminal_1_1"},
			{"op": "build_road", "from": Vector2i(85, entry.y), "to": entry, "type": "terminal_1_1"}],
		[{"op": "build_area", "type": "quay_apron", "segment": 1, "side": 1, "from": 5, "to": 64}],
		[{"op": "build_area", "type": "gate", "segment": 2, "side": -1, "from": 480, "to": 494}],
		[{"op": "set_terminal", "id": 2, "terminal": 1}],
		[{"op": "build_area", "type": "yard_block", "segment": 2, "side": 1, "from": 30, "to": 59}, {"op": "set_terminal", "id": 3, "terminal": 1}],
		[{"op": "place_sts", "apron": 1, "along": 30}],
		[{"op": "buy_tractors", "count": 4}],
	]
	_expect(Guide.current(sim), 0, "a new game starts at the first step")
	for i in steps.size():
		for command: Dictionary in steps[i]:
			_expect(sim.apply(command), "", "step %d: %s" % [i, command])
		_expect(Guide.current(sim), i + 1, "step %d's commands finish it" % i)
	_expect(sim.money > sim.rules.start_money / 2, true, "the first chain costs less than half the start money ($%d left)" % sim.money)
	var crane_up := -1.0
	var accepted := _run_until(sim, func() -> bool:
		if crane_up < 0.0 and not sim.cranes.is_empty():
			crane_up = sim.clock.calendar_minutes()
		if not sim.contracts.offers.is_empty() and crane_up < 0.0:
			_expect(true, false, "no line offers a service before the crane is up")
		for offer in sim.contracts.offers:
			sim.apply({"op": "accept_offer", "id": offer.id})
		return sim.contracts.services.size() >= Guide.SERVICES)
	_expect(accepted, true, "lines offer %d services and they are accepted" % Guide.SERVICES)
	_expect(Guide.current(sim), steps.size() + 1, "accepting the offers finishes their step")
	_expect(_run_until(sim, func() -> bool: return not sim.ship_log.is_empty()), true, "the first ship is worked")
	_expect(Guide.current(sim), Guide.steps(sim).size(), "the guide ends with the first ship worked")
	_expect(sim.money > 0, true, "the port is still in the black after its first ship ($%d)" % sim.money)
	_expect(sim.apply({"op": "remove_area", "id": 2}), "", "bulldoze the gate")
	_expect(Guide.current(sim), Guide.steps(sim).size(), "a finished guide stays finished")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## Ticks `sim` until `done` returns true, for at most DAYS days.
func _run_until(sim: PortSim, done: Callable) -> bool:
	for i in DAYS * SimClock.TICKS_PER_DAY:
		sim.tick()
		if i % 20 == 0 and done.call():
			return true
	return false


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
