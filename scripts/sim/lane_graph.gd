class_name LaneGraph
extends RefCounted
## Routes over the lanes of a RoadNet: each lane cell is a point, joined one
## way to the next cell in its driving direction, across to the next cell of a
## neighbouring lane going the same way, and at nodes to the lanes leading on.
## Areas join it too: traffic in an area runs the way of the road lane beside
## its front. Lorries route on a graph without the roads and areas they may not use.

var _net: RoadNet
## The areas whose driveways join the graph; set once the sim has them.
var areas: Areas
var _version := []
var _all := AStar2D.new()
var _lorries := AStar2D.new()
var _at := {}  # cell -> point ids of lane cells there
var _junction := {}  # cells where routes from different roads meet or cross
var _flows := {}  # area id -> 1 or -1, the way traffic runs along it


func _init(net: RoadNet) -> void:
	_net = net


## Whether `cell` is in a junction: crossing traffic shares it, so a vehicle
## books through it to the cell beyond before entering.
func is_junction(cell: Vector2i) -> bool:
	_refresh()
	return cell in _junction


## The steps traffic may take out of `cell`, one per lane leading on.
func steps_at(cell: Vector2i) -> Array[Vector2i]:
	_refresh()
	var found: Array[Vector2i] = []
	for point: int in _at.get(cell, []):
		for next: int in _all.get_point_connections(point):
			found.append(Vector2i(_all.get_point_position(next)) - cell)
	return found


## Which way traffic runs along area `id`: 1 from its start to its end, -1
## the other way, 0 when no road lane runs beside it.
func flow_of(id: int) -> int:
	_refresh()
	return _flows.get(id, 0)


## The cells from `from` to `to` along lanes, both ends included, or [] when
## no lane route exists. Junctions are crossed one cell at a time.
func route(from: Vector2i, to: Vector2i, lorry: bool) -> Array[Vector2i]:
	_refresh()
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


func _refresh() -> void:
	var now := [_net.version, areas.version if areas else -1]
	if now != _version:
		_version = now
		_rebuild()


func _rebuild() -> void:
	_all.clear()
	_lorries.clear()
	_at.clear()
	_junction.clear()
	_flows.clear()
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
					if _net.degree(node) >= 3:
						var from := Vector2i(_all.get_point_position(arriving[1]))
						var to := Vector2i(_all.get_point_position(leaving[1]))
						for cell: Vector2i in [from, to] + _steps(from, to):
							_junction[cell] = true
	if areas:
		for id: int in areas.list:
			next_id = _add_area(id, next_id)


## Adds area `id`'s driveways from point id `next_id` on; returns the next free
## id. An area with no road lane along its front adds none.
func _add_area(id: int, next_id: int) -> int:
	var area: Dictionary = areas.list[id]
	var along: Vector2i = (area.end - area.start).sign()
	var length := RoadNet.length(area.start, area.end) + 1
	var flow := _flow(area, along, length)
	if flow == 0:
		return next_id
	_flows[id] = flow
	var lorries: bool = area.type != "quay_apron"
	var layout := areas.layout(id)
	var at := {}  # cell -> this area's point there
	# The k-th cell along in driving order, in row `row`.
	var cell := func(row: int, k: int) -> Vector2i:
		return area.start + along * (k if flow > 0 else length - 1 - k) + area.out * row
	# Lambdas copy captured locals, so the next id lives in an array they share.
	var next := [next_id]
	var point := func(c: Vector2i) -> int:
		if c not in at:
			at[c] = next[0]
			_add_point(next[0], c, lorries)
			next[0] += 1
		return at[c]
	# The buffer strip, in from the road at its first cell and out at its last.
	for k in length:
		point.call(cell.call(0, k))
		if k > 0:
			_connect(at[cell.call(0, k - 1)], at[cell.call(0, k)], lorries)
	for road_point: int in _at.get(cell.call(0, 0) - area.out, []):
		if not at.values().has(road_point):
			_connect(road_point, at[cell.call(0, 0)], lorries and _lorries.has_point(road_point))
	for road_point: int in _at.get(cell.call(0, length - 1) - area.out, []):
		if not at.values().has(road_point):
			_connect(at[cell.call(0, length - 1)], road_point, lorries and _lorries.has_point(road_point))
	if area.type in ["quay_apron", "gate"]:
		# Drive-through lanes: out from the buffer down the area's first column,
		# along each lane, and back to the buffer up its last column.
		var lane_rows: Array = [2] if area.type == "quay_apron" else range(1, areas.types.gate.depth - 1)
		for row in range(1, lane_rows[-1] + 1):
			_connect(point.call(cell.call(row - 1, 0)), point.call(cell.call(row, 0)), lorries)
			_connect(point.call(cell.call(row, length - 1)), point.call(cell.call(row - 1, length - 1)), lorries)
		for row: int in lane_rows:
			for k in range(1, length):
				_connect(point.call(cell.call(row, k - 1)), point.call(cell.call(row, k)), lorries)
	if area.type in ["yard_block", "quay_apron"]:
		# Each slot is entered sideways from the lane beside it (a block's
		# buffer, an apron's through lane) and left sideways back into it, so a
		# parked vehicle never blocks the way to another slot.
		var lane := 0 if area.type == "yard_block" else 2
		for slot: Array in layout.slots:
			var ks := range(length).filter(func(k: int) -> bool: return cell.call(lane + 1, k) in slot)
			for k: int in ks:
				point.call(cell.call(lane + 1, k))
				if k > ks[0]:
					_connect(at[cell.call(lane + 1, k - 1)], at[cell.call(lane + 1, k)], lorries)
			_connect(at[cell.call(lane, ks[0])], at[cell.call(lane + 1, ks[0])], lorries)
			_connect(at[cell.call(lane + 1, ks[-1])], at[cell.call(lane, mini(ks[-1] + 1, length - 1))], lorries)
	return next[0]


## Which way traffic runs in `area`: 1 along `along`, -1 against it, the way
## of the road lane beside its front; 0 when no road lane runs there.
func _flow(area: Dictionary, along: Vector2i, length: int) -> int:
	for k in length:
		var beside: Vector2i = area.start + along * k - area.out
		for road_point: int in _at.get(beside, []):
			for next: int in _all.get_point_connections(road_point):
				var step := Vector2i(_all.get_point_position(next)) - beside
				if step == along:
					return 1
				if step == -along:
					return -1
	return 0


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
