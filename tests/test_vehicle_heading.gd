extends SceneTree
## A vehicle's body swings round a driveway's corners instead of snapping:
## going into a yard slot (a road lane, a step sideways along the buffer,
## then into the slot), it never flicks one way and straight back.
## godot --headless --script res://tests/test_vehicle_heading.gd

const Showcase := preload("res://bench/showcase_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_no_flicks_into_a_slot()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## In the showcase's first half hour, no vehicle bound for a slot turns 30° or more and back
## to its first heading within ten ticks.
func _test_no_flicks_into_a_slot() -> void:
	var refused: Array[String] = []
	var sim := Showcase.build(refused)
	var turns := {}  # vehicle id -> [[tick, heading]] each time it changed
	var flicks := 0
	var slotting := 0
	for tick in 600:
		sim.tick()
		for v: Vehicle in sim.vehicles:
			if v.id not in sim.traffic.cars or v.state != "to_slot":
				continue
			slotting += 1
			var heading: Vector2 = Drive.pose(sim, v, 1.0)[1]
			var seen: Array = turns.get(v.id, [])
			if seen.is_empty() or seen[-1][1] != heading:
				seen.append([tick, heading])
			if seen.size() > 3:
				seen.pop_front()
			turns[v.id] = seen
			if seen.size() == 3 and seen[2][0] - seen[0][0] <= 10 and absf(seen[0][1].angle_to(seen[1][1])) > deg_to_rad(30.0) and absf(seen[0][1].angle_to(seen[2][1])) < deg_to_rad(5.0):
				flicks += 1
				turns[v.id] = []
	_expect(slotting > 0, true, "vehicles drive to slots (%d vehicle-ticks)" % slotting)
	_expect(flicks, 0, "flicks one way and back on the way into a slot")
