class_name LaneGraph
extends RefCounted
## Routes over the lanes of a RoadNet: each lane cell is a point, joined one
## way to the next cell in its driving direction, across to the next cell of a
## neighbouring lane going the same way, and at nodes to the lanes leading on.
## Lorries route on a graph without the roads they may not use.

var _net: RoadNet
var _version := -1
var _all := AStar2D.new()
var _lorries := AStar2D.new()
var _at := {}  # cell -> point ids of lane cells there


func _init(net: RoadNet) -> void:
	_net = net


## The cells from `from` to `to` along lanes, both ends included, or [] when
## no lane route exists. Junctions are crossed one cell at a time.
func route(from: Vector2i, to: Vector2i, lorry: bool) -> Array[Vector2i]:
	if _version != _net.version:
		_rebuild()
	var graph := _lorries if lorry else _all
	var best := PackedVector2Array()
	var best_length := INF
	for start: int in _at.get(from, []):
		for goal: int in _at.get(to, []):
			if not graph.has_point(start) or not graph.has_point(goal):
				continue
			var path := graph.get_point_path(start, goal)
			var length := _length(path)
			if not path.is_empty() and length < best_length:
				best = path
				best_length = length
	var cells: Array[Vector2i] = []
	for point in best:
		var cell := Vector2i(point)
		if not cells.is_empty():
			if cell == cells[-1]:
				continue
			cells.append_array(_steps(cells[-1], cell))
		cells.append(cell)
	return cells


func _rebuild() -> void:
	_version = _net.version
	_all.clear()
	_lorries.clear()
	_at.clear()
	var ends := {}  # node -> [segment, last point] of lanes arriving there
	var starts := {}  # node -> [segment, first point] of lanes leaving there
	var next_id := 0
	for segment: int in _net.segments:
		var road: Dictionary = _net.segments[segment]
		var lorries: bool = _net.types[road.type].lorries
		var lanes := _net.lanes(segment)
		var first_ids: Array[int] = []
		for lane in lanes:
			var cells: Array = lane.cells
			first_ids.append(next_id)
			for i in cells.size():
				_add_point(next_id + i, cells[i], lorries)
				if i > 0:
					_connect(next_id + i - 1, next_id + i, lorries)
			var arrive: int = road.b if lane.forward else road.a
			var leave: int = road.a if lane.forward else road.b
			ends[arrive] = ends.get(arrive, []) + [[segment, next_id + cells.size() - 1]]
			starts[leave] = starts.get(leave, []) + [[segment, next_id]]
			next_id += cells.size()
		# Lane changes: one cell on and one across, between lanes going the same way.
		for k in lanes.size() - 1:
			if lanes[k].forward != lanes[k + 1].forward:
				continue
			for i: int in lanes[k].cells.size() - 1:
				_connect(first_ids[k] + i, first_ids[k + 1] + i + 1, lorries)
				_connect(first_ids[k + 1] + i, first_ids[k] + i + 1, lorries)
	for node: int in ends:
		var dead_end := _net.degree(node) == 1
		for arriving: Array in ends[node]:
			for leaving: Array in starts.get(node, []):
				if leaving[0] != arriving[0] or dead_end:
					_connect(arriving[1], leaving[1], _lorries.has_point(arriving[1]) and _lorries.has_point(leaving[1]))


func _add_point(id: int, cell: Vector2i, lorries: bool) -> void:
	_all.add_point(id, Vector2(cell))
	if lorries:
		_lorries.add_point(id, Vector2(cell))
	_at[cell] = _at.get(cell, []) + [id]


func _connect(from: int, to: int, lorries: bool) -> void:
	_all.connect_points(from, to, false)
	if lorries:
		_lorries.connect_points(from, to, false)


## The cells strictly between `from` and `to`, stepping 45° then straight,
## so a vehicle crossing a junction moves one cell at a time.
static func _steps(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var at := from
	while true:
		at += (to - at).sign()
		if at == to:
			return found
		found.append(at)
	return found


static func _length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	return total
