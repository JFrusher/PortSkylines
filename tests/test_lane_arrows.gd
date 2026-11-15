extends SceneTree
## M10 step 16: lane arrows at a junction, as Cities: Skylines edits them.
## Each lane coming in may be given the turns it takes (left, straight,
## right); its connections across the junction follow them in place of
## M7's turn rules, and they are saved with the junction's signals and signs.
## godot --headless --script res://tests/test_lane_arrows.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")
const POINT := Vector2(130, 250)

var _failures := 0


func _initialize() -> void:
	_test_arrows_set_the_turns()
	_test_bad_arrows_are_refused()
	_test_arrows_are_saved()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A 2+2 road east along y = 250 and a 2+2 stem south from (130, 250).
func _port() -> PortSim:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	_expect(sim.apply({"op": "build_road", "from": Vector2(100, 250), "to": Vector2(160, 250), "type": "terminal_2_2"}), "", "a road east")
	_expect(sim.apply({"op": "build_road", "from": POINT, "to": Vector2(130, 290), "type": "terminal_2_2"}), "", "a stem south")
	return sim


## Where each connection leaving the west arm's inner lane (nearest the
## middle, lane 0) goes: "south", "east" or "back" west.
func _turns(sim: PortSim) -> Array:
	Drive._refresh(sim)
	var west := LaneNetwork.arm_key(Vector2(-1, 0))
	var inner: Array = sim.network.approach(POINT, west).filter(func(p: int) -> bool: return absf(sim.network.pieces[p].points[-1].y - 250.5) < 0.01)
	var found := []
	for link: int in sim.network.pieces[inner[0]].next:
		var end: Vector2 = sim.network.pieces[link].points[-1]
		found.append("south" if end.y > 252.0 else ("back" if end.x < 128.0 else "east"))
	found.sort()
	return found


## By M7's rules the inner lane from the west goes straight on or turns back;
## given only a right arrow it turns south instead (a lane turns back only
## with a left arrow).
func _test_arrows_set_the_turns() -> void:
	var sim := _port()
	_expect(_turns(sim), ["back", "back", "east"], "by default the inner lane from the west goes straight on, or turns back")
	_expect(sim.apply({"op": "set_lane_arrows", "point": POINT, "arm": LaneNetwork.arm_key(Vector2(-1, 0)), "lane": 0, "turns": ["right"]}), "", "it is given a right arrow")
	_expect(_turns(sim).has("south") and not _turns(sim).has("east"), true, "and turns south, not straight on (%s)" % [_turns(sim)])
	_expect(sim.apply({"op": "set_lane_arrows", "point": POINT, "arm": LaneNetwork.arm_key(Vector2(-1, 0)), "lane": 0, "turns": []}), "", "its arrows are cleared")
	_expect(_turns(sim), ["back", "back", "east"], "and it goes straight on, or back, again")


func _test_bad_arrows_are_refused() -> void:
	var sim := _port()
	var west := LaneNetwork.arm_key(Vector2(-1, 0))
	_expect(sim.apply({"op": "set_lane_arrows", "point": POINT, "arm": west, "lane": 0, "turns": ["sideways"]}), "Lanes turn left, straight or right", "an unknown turn is refused")
	_expect(sim.apply({"op": "set_lane_arrows", "point": POINT, "arm": west, "lane": 5, "turns": ["right"]}), "No such lane", "a lane the arm hasn't is refused")
	_expect(sim.apply({"op": "set_lane_arrows", "point": POINT, "arm": LaneNetwork.arm_key(Vector2(0, -1)), "lane": 0, "turns": ["right"]}), "No road there", "an arm the junction hasn't is refused")


func _test_arrows_are_saved() -> void:
	var sim := _port()
	sim.apply({"op": "set_lane_arrows", "point": POINT, "arm": LaneNetwork.arm_key(Vector2(-1, 0)), "lane": 0, "turns": ["right"]})
	_expect(SaveFile.save("user://arrows.bin", sim), "", "saved")
	var loaded: PortSim = SaveFile.load_from("user://arrows.bin").sim
	_expect(_turns(loaded).has("south") and not _turns(loaded).has("east"), true, "loaded, the lane still turns south only")
