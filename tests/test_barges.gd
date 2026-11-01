extends SceneTree
## M9 step D: barges come and go only by a river's inland end, where it
## leaves the site; every other ship only by the open sea.
## godot --headless --script res://tests/test_barges.gd

const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_barges_come_by_the_river()
	_test_barges_unlock_at_the_terminal()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The strait with a river 12 m deep in from the north edge at x = 300
## cells, turning west at y = 300 to the sea, and an anchorage in the sea
## off its mouth.
func _river_port() -> PortSim:
	var rules := RandomPort.strait()
	rules.maps.strait.rivers = [{"points": [[1202, 0], [1202, 1202], [0, 1202]], "width": 120, "depth": 12}]
	var sim := PortSim.new(0, rules, true)
	_expect(sim.apply({"op": "build_anchorage", "from": Vector2i(20, 275), "to": Vector2i(70, 325)}), "", "an anchorage off the river's mouth")
	return sim


func _test_barges_come_by_the_river() -> void:
	var sim := _river_port()
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(0, 300), "to": Vector2i(50, 300), "type": "narrow"}), "", "a lane in from the sea to the anchorage")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(50, 300), "to": Vector2i(300, 300), "type": "narrow"}), "", "and on up the river to its turn")
	_expect(Marine.route_to_anchorage(sim, "barge", 1), [] as Array[Vector2], "with no lane down the river a barge can't come")
	_expect(Marine.route_to_anchorage(sim, "feeder", 1)[0], Vector2(0.5, 300.5), "a feeder comes in from the sea")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(300, 0), "to": Vector2i(300, 300), "type": "narrow"}), "", "a lane down the river")
	_expect(Marine.route_to_anchorage(sim, "barge", 1)[0], Vector2(300.5, 0.5), "a barge comes down the river from its inland end")
	_expect(Marine.route_to_anchorage(sim, "feeder", 1)[0], Vector2(0.5, 300.5), "a feeder still comes from the sea, though the river is deep enough")
	_expect(Marine.edge_nodes(sim, false).size(), 1, "the river's end isn't open sea")


func _test_barges_unlock_at_the_terminal() -> void:
	var sim := PortSim.new(0, RandomPort.strait())
	_expect(sim.lock_error("barge"), "Unlocked at milestone 2: %d TEU across the quay" % sim.milestones()[1].teu, "barges come with milestone 2")
