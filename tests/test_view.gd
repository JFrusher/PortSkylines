extends SceneTree
## Headless tests for the view's pure helpers: road pieces and vehicle poses.
## godot --headless --script res://tests/test_view.gd

var _failures := 0


func _initialize() -> void:
	var map := PortMap.new(Vector2i(16, 16), 2)
	var road := PortMap.Tile.ROAD
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(8, 6), Vector2i(3, 9)]:
		map.place(road, cell)
	_expect(WorldView.road_piece(map, Vector2i(6, 5))[0], "straight", "a road between two roads is straight")
	_expect(WorldView.road_piece(map, Vector2i(5, 5))[0], "end", "a road with one neighbour is an end")
	_expect(WorldView.road_piece(map, Vector2i(7, 5))[0], "corner", "a road joining two adjacent sides is a corner")
	_expect(WorldView.road_piece(map, Vector2i(7, 6))[0], "junction", "three roads meeting is a junction")
	_expect(WorldView.road_piece(map, Vector2i(3, 9))[0], "junction", "a lone road tile is drawn whole")
	_expect(WorldView.road_piece(map, map.entry)[0], "end", "the entry joins the highway off the map")
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]:
		var piece := WorldView.road_piece(map, cell)
		var joined: Array = WorldView.ROAD_SHAPES[piece[0]].map(func(side: Vector2i) -> Vector2i: return WorldView._turn(side, piece[1]))
		for side: Vector2i in joined:
			_expect(map.tile(cell + side), road, "%s's turned piece at %s joins a road at %s" % [piece[0], cell, side])
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	_expect(WorldView.path_pose(path, 0.25), [Vector2(0.25, 0), Vector2(1, 0)] as Array[Vector2], "a straight stretch lerps")
	var last := WorldView.path_pose(path, 0.5)
	for step in range(1, 21):
		var pose := WorldView.path_pose(path, 0.5 + step * 0.05)
		_expect(pose[0].distance_to(last[0]) < 0.1, true, "no jump at t=%.2f" % (0.5 + step * 0.05))
		_expect(pose[1].normalized().angle_to(last[1].normalized()) < 0.2, true, "no snap in heading at t=%.2f" % (0.5 + step * 0.05))
		last = pose
	var middle := WorldView.path_pose(path, 1.0)
	_expect(middle[0].distance_to(Vector2(0.5, 0.5) + Vector2(1, -1).normalized() * 0.5) < 0.001, true, "the corner tile is crossed on a quarter circle about its inner corner")
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
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
