extends SceneTree
## M7 step E's signals and signs as the player sets them: picked by Inspect,
## set by command, kept in a save. How traffic keeps to them is
## test_traffic_junctions'.
## godot --headless --script res://tests/test_signals.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_inspect_and_commands()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])

## In the game: Inspect picks the T the test port's coast road makes where
## it bends into the east road, with a stub road on south from the bend, and
## the commands the panel's buttons send set it up.
func _test_inspect_and_commands() -> void:
	var sim := AreaPort.terminal(80)
	var point := Vector2i(86, sim.site_entry().y)
	sim.creative = true
	_expect(sim.apply({"op": "build_road", "from": point, "to": point + Vector2i(0, 20), "type": "terminal_1_1"}), "", "a stub road south makes the bend a T")
	Drive.arms(sim, point)
	var node := sim.network.node_at(point)
	var connection: Dictionary = sim.network.pieces.values().filter(func(p: Dictionary) -> bool: return p.node == node)[0]
	var picked: Variant = Inspect.pick(sim, Vector2i(connection.points[connection.points.size() / 2].floor()))
	_expect(picked, {"junction": point}, "a click in the box picks the junction")
	_expect(Inspect.describe(sim, picked).slice(0, 2), ["Junction of 3 roads", "No signals"] as Array[String], "it says what it is")
	_expect(sim.apply({"op": "set_signals", "point": point, "on": true}), "", "signals go on")
	_expect(Inspect.describe(sim, picked)[1].begins_with("Phase 1, north and south: 20 s green"), true, "phases show with their green time (%s)" % Inspect.describe(sim, picked)[1])
	_expect(sim.apply({"op": "set_green", "point": point, "phase": 1, "seconds": 2.0}), "Green lasts 5 to 120 s", "a green too short is refused")
	_expect(sim.apply({"op": "set_green", "point": point, "phase": 1, "seconds": 30.0}), "", "a green in range is set")
	_expect(sim.apply({"op": "set_sign", "point": point, "arm": Vector2i(1, 0), "sign": "stop"}), "", "the east arm gets a stop sign")
	_expect(Inspect.describe(sim, picked)[-1], "From the east: stop", "and shows it")
	var copy := PortSim.from_dict(sim.to_dict())
	_expect(copy.junctions.to_dict(), sim.junctions.to_dict(), "signals and signs survive a save")

