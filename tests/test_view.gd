extends SceneTree
## Headless tests for the view's pure helpers: road meshes, vehicle poses,
## the STS crane's move and ships' deck stacks.
## godot --headless --script res://tests/test_view.gd

var _failures := 0


func _initialize() -> void:
	_test_road_mesh_faces_up()
	_expect(WorldView.grid_cell(Vector3(1, 0, 0.5)), Vector2i(6, 3), "a world point finds its 4 m cell (25 m a unit)")
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	_expect(WorldView.path_pose(path, 0.25), [Vector2(0.25, 0), Vector2(1, 0)] as Array[Vector2], "a straight stretch lerps")
	var last := WorldView.path_pose(path, 0.5)
	for step in range(1, 21):
		var pose := WorldView.path_pose(path, 0.5 + step * 0.05)
		_expect(pose[0].distance_to(last[0]) < 0.1, true, "no jump at t=%.2f" % (0.5 + step * 0.05))
		_expect(pose[1].normalized().angle_to(last[1].normalized()) < 0.2, true, "no snap in heading at t=%.2f" % (0.5 + step * 0.05))
		last = pose
	var middle := WorldView.path_pose(path, 1.0)
	_expect(middle[0].distance_to(Vector2(0.5, 0.5) + Vector2(1, -1).normalized() * 0.5) < 0.001, true, "a corner cell is crossed on a quarter circle about its inner corner")
	for discharging: bool in [true, false]:
		var from := 1.0 if discharging else 0.0
		_expect(WorldView.crane_pose(0.0, discharging), [from, 0.0] as Array[float], "a move starts raised over its pick-up end (discharging %s)" % discharging)
		_expect(WorldView.crane_pose(0.15, discharging), [from, 1.0] as Array[float], "it lowers at the pick-up end (discharging %s)" % discharging)
		_expect(WorldView.crane_pose(0.85, discharging), [1.0 - from, 1.0] as Array[float], "it lowers at the drop end (discharging %s)" % discharging)
		var before := WorldView.crane_pose(0.0, discharging)
		for step in range(1, 101):
			var now := WorldView.crane_pose(step / 100.0, discharging)
			_expect(absf(now[0] - before[0]) < 0.05 and absf(now[1] - before[1]) < 0.1, true, "the trolley moves smoothly at %.2f" % (step / 100.0))
			before = now
	var feeder := WorldView.deck_slots(8, 999)
	_expect(feeder.size(), floori((8 - WorldView.SHIP_BOW - WorldView.SHIP_STERN) / WorldView.DECK_BAY) * WorldView.DECK_ROWS * WorldView.DECK_TIERS, "a full deck stops at the top tier")
	_expect(WorldView.deck_slots(8, 5).size(), 5, "each box aboard gets a slot")
	_expect(feeder.all(func(p: Vector3) -> bool: return absf(p.z) < 4.0 - 0.2 and absf(p.x) < 0.7), true, "deck boxes stay over the hull")
	var unique := {}
	for p: Vector3 in feeder:
		unique[p] = true
	_expect(unique.size(), feeder.size(), "no two deck boxes share a slot")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## Godot draws a triangle's front when its corners run clockwise seen from
## the camera; a road wound the other way vanishes from above.
func _test_road_mesh_faces_up() -> void:
	var types: Dictionary = Content.base().road_types
	var surface := WorldView._road_tool()
	WorldView._add_road(surface, null, Vector2i(10, 10), Vector2i(30, 10), types.terminal_1_1)
	WorldView._add_road(surface, null, Vector2i(30, 10), Vector2i(40, 20), types.tractor_lane)
	WorldView._cell_quad(surface, Vector2i(5, 7), 0.2)
	var vertices: PackedVector3Array = surface.commit().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var clockwise := true
	for i in range(0, vertices.size(), 3):
		var normal := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
		clockwise = clockwise and normal.y < 0.0
	_expect(vertices.size() > 0 and clockwise, true, "every road and area triangle runs clockwise from above, so it faces the camera")


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
