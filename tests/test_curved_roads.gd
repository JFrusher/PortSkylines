extends SceneTree
## M10 step 5: every road and rail segment is a curve, a control point
## between its two nodes (save v38). A grid road drawn today, and every
## road in a save from before, is the straight curve on its own line.
## godot --headless --script res://tests/test_curved_roads.gd

const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_a_new_road_is_straight()
	_test_a_split_road_stays_straight()
	_test_older_saves_load_as_straight_curves()
	_test_curves_survive_a_save()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Each of `net`'s segments has its control point at its middle and its
## curve is as long as its line.
func _all_straight(net: RoadNet, what: String) -> void:
	for id: int in net.segments:
		var a := Vector2(net.nodes[net.segments[id].a])
		var b := Vector2(net.nodes[net.segments[id].b])
		_expect(net.segments[id].control, (a + b) / 2.0, "%s: segment %d's control point is at its middle" % [what, id])
		_expect(is_equal_approx(net.curve(id).length, a.distance_to(b)), true, "%s: segment %d's curve is its line" % [what, id])


func _test_a_new_road_is_straight() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	_expect(sim.apply({"op": "build_road", "from": Vector2i(100, 200), "to": Vector2i(140, 240), "type": "terminal_1_1"}), "", "a 45° road is built")
	_all_straight(sim.roads, "a new road")


## A road built across another splits both at the crossing; every piece is
## the straight curve on its own line.
func _test_a_split_road_stays_straight() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	sim.apply({"op": "build_road", "from": Vector2i(100, 220), "to": Vector2i(160, 220), "type": "terminal_1_1"})
	sim.apply({"op": "build_road", "from": Vector2i(130, 200), "to": Vector2i(130, 240), "type": "terminal_1_1"})
	_expect(sim.roads.segments.size(), 4, "the crossing splits both roads")
	_all_straight(sim.roads, "after a split")


## Every committed fixture from the oldest loadable save on loads with its
## roads and track as straight curves.
func _test_older_saves_load_as_straight_curves() -> void:
	for version in range(SaveFile.FIRST, SaveFile.VERSION + 1):
		var path := "res://tests/fixtures/save_v%d.bin" % version
		var loaded := SaveFile.load_from(path)
		_expect(loaded.get("error", ""), "", "save v%d loads" % version)
		if loaded.has("sim"):
			_all_straight(loaded.sim.roads, "save v%d's roads" % version)
			_all_straight(loaded.sim.rails, "save v%d's track" % version)


func _test_curves_survive_a_save() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	sim.apply({"op": "build_road", "from": Vector2i(100, 220), "to": Vector2i(160, 220), "type": "terminal_1_1"})
	var loaded := PortSim.from_dict(sim.to_dict())
	_expect(loaded.roads.segments, sim.roads.segments, "a save keeps every segment's control point")
