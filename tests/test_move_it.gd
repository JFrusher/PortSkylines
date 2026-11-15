extends SceneTree
## M10 step 18: Move It, as Cities: Skylines' mod moves a road: drag a
## node or a road's control point to reshape the roads there, moving the
## areas built along them, or be refused with the reason, leaving all as it
## was.
## godot --headless --script res://tests/test_move_it.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_a_control_point_bends_a_road_and_its_area()
	_test_a_node_drags_its_roads()
	_test_moved_road_hits_an_unrelated_area()
	_test_refit_with_a_warm_cache()
	_test_bad_moves_are_refused()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _port() -> PortSim:
	return AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))


## A 2+2 road east along y = 250 with a yard block south of it: its control
## point dragged 8 cells north bends it, and the block bends with it.
func _test_a_control_point_bends_a_road_and_its_area() -> void:
	var sim := _port()
	_expect(sim.apply({"op": "build_road", "from": Vector2(100, 250), "to": Vector2(160, 250), "type": "terminal_2_2"}), "", "a road east")
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": 1, "from": 10, "to": 49}), "", "a yard block south of it")
	var block: int = sim.areas.list.keys()[0]
	var before := sim.areas.centre(Vector3i(block, 20, 0))
	_expect(sim.apply({"op": "move_road_control", "segment": 1, "control": Vector2(130, 242)}), "", "its control point is moved north")
	_expect(sim.roads.segments[1].control, Vector2(130, 242), "the road bends")
	_expect(sim.areas.list[block].curve, [Vector2(100, 250), Vector2(130, 242), Vector2(160, 250)], "and the block is laid along the bent road")
	_expect(sim.areas.centre(Vector3i(block, 20, 0)).y < before.y - 2.0, true, "its middle moved north with it (%s to %s)" % [before, sim.areas.centre(Vector3i(block, 20, 0))])


## A T: a road east along y = 250 and a stem south from (130, 250). The T's
## node dragged 3 cells east moves both roads' ends; the straight ones stay
## straight.
func _test_a_node_drags_its_roads() -> void:
	var sim := _port()
	sim.apply({"op": "build_road", "from": Vector2(100, 250), "to": Vector2(160, 250), "type": "terminal_1_1"})
	sim.apply({"op": "build_road", "from": Vector2(130, 250), "to": Vector2(130, 280), "type": "terminal_1_1"})
	var node: int = sim.roads.nodes.find_key(Vector2(130, 250))
	_expect(sim.apply({"op": "move_road_node", "node": node, "to": Vector2(133, 250)}), "", "the T's node is moved east")
	_expect(sim.roads.nodes[node], Vector2(133, 250), "it moves")
	_expect(sim.roads.segments.values().all(func(r: Dictionary) -> bool: return r.control.is_equal_approx((sim.roads.nodes[r.a] + sim.roads.nodes[r.b]) / 2.0)), true, "every road at it stays straight")


## Refused, each leaving the roads as they were: a stub north of the road
## with its end dragged south across it (it would cross it), a T's stem
## dragged so it meets the road at 20°, and a stem's control point dragged
## out past its end so it folds back in a hairpin.
func _test_bad_moves_are_refused() -> void:
	var sim := _port()
	sim.apply({"op": "build_road", "from": Vector2(100, 250), "to": Vector2(160, 250), "type": "terminal_1_1"})
	sim.apply({"op": "build_road", "from": Vector2(130, 250), "to": Vector2(130, 270), "type": "terminal_1_1"})
	sim.apply({"op": "build_road", "from": Vector2(145, 225), "to": Vector2(145, 240), "type": "terminal_1_1"})
	var before: Dictionary = sim.roads.to_dict()
	var stub: int = sim.roads.nodes.find_key(Vector2(145, 240))
	_expect(sim.apply({"op": "move_road_node", "node": stub, "to": Vector2(145, 262)}), "A road would cross another: draw it again instead", "a stub dragged across the road is refused")
	var tail: int = sim.roads.nodes.find_key(Vector2(130, 270))
	var err := sim.apply({"op": "move_road_node", "node": tail, "to": Vector2(130, 250) + Vector2.from_angle(deg_to_rad(20.0)) * 20.0})
	_expect(err.begins_with("Roads meet at 20°"), true, "a stem dragged to 20° off the road is refused (%s)" % err)
	var stem: int = sim.roads.segments.keys().filter(func(id: int) -> bool: return tail in [sim.roads.segments[id].a, sim.roads.segments[id].b])[0]
	err = sim.apply({"op": "move_road_control", "segment": stem, "control": Vector2(131, 300)})
	_expect(err.begins_with("Too tight a curve"), true, "a hairpin is refused (%s)" % err)
	_expect(sim.roads.to_dict(), before, "and the roads are as they were")
	_expect(sim.apply({"op": "move_road_node", "node": 99, "to": Vector2(1, 1)}), "No road there", "a node that isn't there is refused")


func _test_refit_with_a_warm_cache() -> void:
	var sim := _port()
	sim.apply({"op": "build_road", "from": Vector2(100, 250), "to": Vector2(160, 250), "type": "terminal_2_2"})
	sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": 1, "from": 10, "to": 49})
	var id: int = sim.areas.list.keys()[0]
	sim.areas.area_over(Areas.square(sim.areas.cell_at(id, 20, 1)))
	_expect(sim.areas.refit(id, 1), "", "refit ignores its removed cached quads")


func _test_moved_road_hits_an_unrelated_area() -> void:
	var sim := _port()
	sim.apply({"op": "build_road", "from": Vector2(100, 250), "to": Vector2(180, 250), "type": "terminal_1_1"})
	sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": 1, "from": 10, "to": 49})
	sim.apply({"op": "build_road", "from": Vector2(110, 280), "to": Vector2(160, 280), "type": "terminal_1_1"})
	var id := sim.roads.segment_at(Vector2i(130, 280))
	var before := sim.roads.to_dict()
	_expect(sim.move_road({"segment": id, "control": Vector2(135, 234)}, true), "Something is already built here", "a moved road cannot cut through an unrelated yard")
	_expect(sim.roads.to_dict(), before, "rejected move restores roads")
