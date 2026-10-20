extends SceneTree
## M5's first slice end to end on roads and areas: a port built by commands
## takes a line's offer, works its first ship, and sends its imports out by
## lorry. godot --headless --script res://tests/test_first_slice.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_first_ship_end_to_end()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## The first slice: a port built by commands takes a line's offer, and its
## first ship's boxes go STS to tractor to yard slot to stack, then out by
## lorry through the gate, while exports come in by lorry and are loaded.
func _test_first_ship_end_to_end() -> void:
	var sim := AreaPort.chain(11)
	var line := ""
	var sailed := -1
	for i in 10 * SimClock.TICKS_PER_DAY:
		sim.tick()
		if i % 20 != 0:
			continue
		for offer: Dictionary in sim.contracts.offers:
			if line == "":
				line = offer.line
				sim.apply({"op": "accept_offer", "id": offer.id})
		if sailed < 0 and not sim.ship_log.is_empty():
			sailed = i
		if sailed >= 0 and not sim.boxes.values().any(func(b: Dictionary) -> bool: return b.kind == "import"):
			break
	_expect(line != "", true, "a line offers a service and it is accepted")
	_expect(sailed >= 0, true, "the first ship arrives at the apron, is worked and sails")
	var spec: Dictionary = sim.rules.ship_classes[sim.ship_log[0].kind] if sailed >= 0 else {}
	_expect(sailed >= 0 and sim.ship_log[0].moves >= spec.import_moves, true, "every import is discharged (%s moves)" % (sim.ship_log[0].moves if sailed >= 0 else 0))
	_expect(sailed >= 0 and sim.ship_log[0].moves > spec.import_moves, true, "and exports brought in by lorry are loaded")
	_expect(sim.boxes.values().any(func(b: Dictionary) -> bool: return b.kind == "import"), false, "after their dwell, lorries take every import out through the gate")
	_expect(sim.turn_times.is_empty(), false, "gate turns are recorded")


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
