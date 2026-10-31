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
## Rail track, which joins nothing: its level crossings are junction cells,
## so no vehicle ever stops on one.
var rails: RoadNet
var _version := []
var _all := AStar2D.new()
var _lorries := AStar2D.new()
var _at := {}  # cell -> point ids of lane cells there
var _junction := {}  # cells where routes from different roads meet or cross
## Junctions of three or more roads, by their grid point: the cells of the
## box, and each arm's approach (the last APPROACH_CELLS cells of its lanes
## before the box), by the arm's way out from the junction.
var _box_of := {}  # junction cell -> its junction's point
var _boxes := {}  # point -> {cell: true}
var _approaches := {}  # point -> {arm Vector2i: [cells]}
var _arm_at := {}  # approach cell -> [point, arm]
## How many cells before a junction's box count as its approach, where a
## vehicle giving way looks for traffic.
const APPROACH_CELLS := 3
var _flows := {}  # area id -> 1 or -1, the way traffic runs along it
var _routes := [{}, {}]  # [for all vehicles, for lorries]: Vector4i(from, to) -> route; cleared with the graph
## What a route weighs each cell by: the delays set_delays was last given,
## and the speeds, in cells a second, that turn them into cells of driving.
var _delays := {}
var _speeds := Vector2(1.0, 1.0)  # (all vehicles, lorries)
## Points inside areas, by area: driveways, buffers and slots. They stay
## disabled but for the areas a search starts or ends in, so no route takes an
## area's buffer strip as a way round a jammed road beside it.
var _area_points := {}  # area id -> [point ids], its slots' left out
var _area_of := {}  # point id -> area id
## The same for handover slots, one level down: a slot runs beside its
## area's buffer or lane, so it stays disabled but for the slots a search
## starts or ends in, or routes would cut through slots others stand in.
var _slot_points := {}  # Vector2i(area id, slot) -> [point ids]
var _slot_of := {}  # point id -> Vector2i(area id, slot)
## The cells _weigh last weighed for a delay, to set back when it clears.
var _weighed := {}  # cell -> true


func _init(net: RoadNet) -> void:
	_net = net


## Whether `cell` is in a junction: crossing traffic shares it, so a vehicle
## books through it to the cell beyond before entering.
func is_junction(cell: Vector2i) -> bool:
	_refresh()
	return cell in _junction


## Lane cells where rail track crosses: level crossings.
func crossings() -> Array[Vector2i]:
	_refresh()
	var found: Array[Vector2i] = []
	if rails == null:
		return found
	for id: int in rails.segments:
		for cell in rails.cells(id):
			if cell in _at:
				found.append(cell)
	return found


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
## no lane route exists. Junctions are crossed one cell at a time. Kept until
## the graph changes, since vehicles mostly drive between the same slots,
## gates and buffers (43% of an endgame hour's routes were asked before); a
## kept route is read-only, as vehicles share it.
# shortcut: kept routes grow with the distinct pairs asked until the graph changes (about 4,000 an endgame hour, ~18 MB); bound them if memory shows.
func route(from: Vector2i, to: Vector2i, lorry: bool) -> Array[Vector2i]:
	_refresh()
	var kept: Dictionary = _routes[int(lorry)]
	var key := Vector4i(from.x, from.y, to.x, to.y)
	if key not in kept:
		var found := _search(from, to, lorry)
		found.make_read_only()
		kept[key] = found
	return kept[key]


## Routes from here on weigh each cell by `delays` (cell -> seconds a vehicle
## waits in it, from LaneTraffic): entering it costs its length plus the
## cells a vehicle could drive in that time, at `all_speed` cells a second on
## the graph for every vehicle and `lorry_speed` on the lorries' graph, so
## routes go round a jam that costs more than the way round. Kept routes go.
func set_delays(delays: Dictionary, lorry_speed: float, all_speed: float) -> void:
	_refresh()
	_delays = delays.duplicate()
	_speeds = Vector2(all_speed, lorry_speed)
	_weigh()
	for kept: Dictionary in _routes:
		kept.clear()


## Weighs each cell's points by _delays: 1 where a cell flows, plus the
## cells its delay is worth. Only cells with a delay now or last time change.
func _weigh() -> void:
	for cell: Vector2i in _weighed.keys() + _delays.keys():
		var delay: float = _delays.get(cell, 0.0)
		for id: int in _at.get(cell, []):
			_all.set_point_weight_scale(id, 1.0 + delay * _speeds.x)
			if _lorries.has_point(id):
				_lorries.set_point_weight_scale(id, 1.0 + delay * _speeds.y)
	_weighed.clear()
	for cell: Vector2i in _delays:
		_weighed[cell] = true


## Enables or disables points `ids` in both graphs.
func _enable(ids: Array, on: bool) -> void:
	for id: int in ids:
		_all.set_point_disabled(id, not on)
		if _lorries.has_point(id):
			_lorries.set_point_disabled(id, not on)


## The point lists a search from `from` to `to` may use besides roads: the
## areas and the slots those two cells are in (a slot's area too).
func _ends(from: Vector2i, to: Vector2i) -> Array[Array]:
	var found: Array[Array] = []
	for cell: Vector2i in [from, to]:
		for id: int in _at.get(cell, []):
			if id in _slot_of:
				found.append(_slot_points[_slot_of[id]])
				found.append(_area_points[_slot_of[id].x])
			elif id in _area_of:
				found.append(_area_points[_area_of[id]])
	return found


func _search(from: Vector2i, to: Vector2i, lorry: bool) -> Array[Vector2i]:
	var ends := _ends(from, to)
	for ids: Array in ends:
		_enable(ids, true)
	var cells := _find(from, to, lorry)
	for ids: Array in ends:
		_enable(ids, false)
	return cells


func _find(from: Vector2i, to: Vector2i, lorry: bool) -> Array[Vector2i]:
	var graph := _lorries if lorry else _all
	var best := PackedInt64Array()
	var best_cost := INF
	for start: int in _at.get(from, []):
		for goal: int in _at.get(to, []):
			if not graph.has_point(start) or not graph.has_point(goal):
				continue
			var ids := graph.get_id_path(start, goal)
			var cost := _cost(graph, ids)
			if not ids.is_empty() and cost < best_cost:
				best = ids
				best_cost = cost
	var cells: Array[Vector2i] = []
	for id in best:
		var cell := Vector2i(graph.get_point_position(id))
		if not cells.is_empty():
			if cell == cells[-1]:
				continue
			cells.append_array(_steps(cells[-1], cell))
		cells.append(cell)
	return cells


func _refresh() -> void:
	var now := [_net.version, areas.version if areas else -1, rails.version if rails else -1]
	if now != _version:
		_version = now
		_rebuild()


func _rebuild() -> void:
	_all.clear()
	_lorries.clear()
	_at.clear()
	_junction.clear()
	_box_of.clear()
	_boxes.clear()
	_approaches.clear()
	_arm_at.clear()
	_flows.clear()
	_area_points.clear()
	_area_of.clear()
	_slot_points.clear()
	_slot_of.clear()
	for kept: Dictionary in _routes:
		kept.clear()
	var ends := {}  # node -> [segment, first point, cells] of lanes arriving there
	var starts := {}  # node -> [segment, first point, cells] of lanes leaving there
	var covers := {}  # cell -> {segment: true} for each segment with a lane there
	var next_id := 0
	var changes: Array[Vector2i] = []  # lane-change edges (from point, to point), dropped where they reach into a junction
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
				covers[cells[i]] = covers.get(cells[i], {})
				covers[cells[i]][segment] = true
			var arrive: int = road.b if lane.forward else road.a
			var leave: int = road.a if lane.forward else road.b
			ends[arrive] = ends.get(arrive, []) + [[segment, next_id, cells]]
			starts[leave] = starts.get(leave, []) + [[segment, next_id, cells]]
			next_id += cells.size()
		# Lane changes: one cell on and one across, between lanes going the same way.
		for k in lanes.size() - 1:
			if lanes[k].forward != lanes[k + 1].forward:
				continue
			for i: int in lanes[k].cells.size() - 1:
				_connect(first_ids[k] + i, first_ids[k + 1] + i + 1, lorries)
				_connect(first_ids[k + 1] + i, first_ids[k] + i + 1, lorries)
				changes.append_array([Vector2i(first_ids[k] + i, first_ids[k + 1] + i + 1), Vector2i(first_ids[k + 1] + i, first_ids[k] + i + 1)])
	for node: int in ends:
		# Traffic turns back at dead ends and junctions, never on a bend.
		var turns_back := _net.degree(node) != 2
		var junction := _net.degree(node) >= 3
		for arriving: Array in ends[node]:
			for leaving: Array in starts.get(node, []):
				if leaving[0] == arriving[0] and not turns_back:
					continue
				if junction and not _lane_may(arriving, leaving, ends[node], starts.get(node, [])):
					continue
				var turn := _turn(arriving, leaving)
				_connect(turn[0], turn[1], _lorries.has_point(turn[0]) and _lorries.has_point(turn[1]))
				if _net.degree(node) >= 3:
					var from := Vector2i(_all.get_point_position(turn[0]))
					var to := Vector2i(_all.get_point_position(turn[1]))
					for cell: Vector2i in [from, to] + _steps(from, to):
						_junction[cell] = true
						_box_of[cell] = _net.nodes[node]
						_boxes.get_or_add(_net.nodes[node], {})[cell] = true
	# Where roads meeting at a junction overlap, crossing traffic shares the
	# cell, so it is a junction cell too and nobody stops in the box.
	for cell: Vector2i in covers:
		var meeting: Array = covers[cell].keys()
		for k in meeting.size():
			for m in range(k + 1, meeting.size()):
				if _meet_at_junction(meeting[k], meeting[m]):
					_junction[cell] = true
	for cell in crossings():
		_junction[cell] = true
	for node: int in ends:
		if _net.degree(node) < 3:
			continue
		var at: Vector2i = _net.nodes[node]
		for arriving: Array in ends[node]:
			var arm := Vector2i((-_heading(arriving[2])).round()).sign()
			var before: Array = arriving[2].filter(func(c: Vector2i) -> bool: return c not in _junction)
			for cell: Vector2i in before.slice(maxi(before.size() - APPROACH_CELLS, 0)):
				_approaches.get_or_add(at, {}).get_or_add(arm, []).append(cell)
				_arm_at[cell] = [at, arm]
	# No lane changes into a junction: a vehicle is in the lane its turn needs before the box.
	for change: Vector2i in changes:
		if Vector2i(_all.get_point_position(change.y)) in _junction:
			_all.disconnect_points(change.x, change.y, false)
			if _lorries.has_point(change.x) and _lorries.has_point(change.y):
				_lorries.disconnect_points(change.x, change.y, false)
	if areas:
		for id: int in areas.list:
			next_id = _add_area(id, next_id)
	for area: int in _area_points:
		_enable(_area_points[area], false)
	for slot: Vector2i in _slot_points:
		_enable(_slot_points[slot], false)
	_weighed.clear()
	_weigh()


## The [from, to] points a turn from lane `arriving` onto lane `leaving` joins,
## each [segment, first point, cells]: the first cell where the two lanes
## cross, so a turning vehicle never drives on past it and back; else the
## arriving lane's last cell to the leaving lane's first.
func _turn(arriving: Array, leaving: Array) -> Array:
	var into: Array = arriving[2]
	var out: Array = leaving[2]
	for i in into.size():
		var j := out.find(into[i])
		if j >= 0:
			return [arriving[1] + i, leaving[1] + j]
	return [arriving[1] + into.size() - 1, leaving[1]]


## Whether a vehicle in `arriving` may take `leaving` at a junction, by the
## turn rules: with one lane its way, any turn; with more, the leftmost lane
## turns left or back, the rightmost turns right, and straight on is for the
## lanes between, for both of two lanes, and for an outer lane when no road
## turns its way. `ends` and `starts` are every lane arriving at and leaving
## the junction, each [segment, first point, cells].
func _lane_may(arriving: Array, leaving: Array, ends: Array, starts: Array) -> bool:
	var mine: Array = ends.filter(func(lane: Array) -> bool: return lane[0] == arriving[0])
	if mine.size() == 1:
		return true
	var heading := _heading(arriving[2])
	var left := Vector2(RoadNet.right_of(Vector2i(heading.round())) * -1)
	# Lanes from the driver's left to right, by where each ends across the road.
	mine.sort_custom(func(a: Array, b: Array) -> bool: return Vector2(a[2][-1]).dot(left) > Vector2(b[2][-1]).dot(left))
	var i := mine.find(arriving)
	var last := mine.size() - 1
	var kinds := {}
	for lane: Array in starts:
		kinds[_kind(heading, lane, arriving[0])] = true
	match _kind(heading, leaving, arriving[0]):
		"left", "back":
			return i == 0
		"right":
			return i == last
		_:
			return (i > 0 and i < last) or last == 1 or (i == 0 and "left" not in kinds) or (i == last and "right" not in kinds)


## Which way a vehicle heading `heading` goes onto `leaving`: "back" onto the
## road it came by (`from`), else "left", "right" or "straight" by the angle.
static func _kind(heading: Vector2, leaving: Array, from: int) -> String:
	if leaving[0] == from:
		return "back"
	var angle := heading.angle_to(_heading(leaving[2]))
	if absf(angle) < PI / 3.0:
		return "straight"
	# y grows south, so a negative angle turns to the driver's left.
	return "left" if angle < 0.0 else "right"


## The way along `cells`, from its first cell to its last.
static func _heading(cells: Array) -> Vector2:
	return Vector2(cells[-1] - cells[0]).normalized()


## The junction (its grid point) whose box holds `cell`, or Grid.NONE.
func box_of(cell: Vector2i) -> Vector2i:
	_refresh()
	return _box_of.get(cell, Grid.NONE)


## The cells of junction `point`'s box.
func box(point: Vector2i) -> Array:
	_refresh()
	return _boxes.get(point, {}).keys()


## Junction `point`'s arms, each the way out from it along a road, sorted so
## they come in the same order every time; [] when it is no junction.
func arms(point: Vector2i) -> Array:
	_refresh()
	var found: Array = _approaches.get(point, {}).keys()
	found.sort()
	return found


## The approach cells of arm `arm` at junction `point`.
func approach(point: Vector2i, arm: Vector2i) -> Array:
	_refresh()
	return _approaches.get(point, {}).get(arm, [])


## [junction point, arm] of an approach cell, or [] for any other cell.
func arm_at(cell: Vector2i) -> Array:
	_refresh()
	return _arm_at.get(cell, [])


## Whether segments `s` and `t` end at one node that is a junction.
func _meet_at_junction(s: int, t: int) -> bool:
	var a: Dictionary = _net.segments[s]
	var b: Dictionary = _net.segments[t]
	for node: int in [a.a, a.b]:
		if node in [b.a, b.b] and _net.degree(node) >= 3:
			return true
	return false


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
			_area_points.get_or_add(id, []).append(next[0])
			_area_of[next[0]] = id
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
	if areas.kind_of(area) in ["quay_apron", "gate"]:
		# Drive-through lanes: out from the buffer down the area's first column,
		# along each lane, and back to the buffer up its last column.
		var lane_rows: Array = [2] if area.type == "quay_apron" else range(1, areas.depth_of(area) - 1)
		for row in range(1, lane_rows[-1] + 1):
			_connect(point.call(cell.call(row - 1, 0)), point.call(cell.call(row, 0)), lorries)
			_connect(point.call(cell.call(row, length - 1)), point.call(cell.call(row - 1, length - 1)), lorries)
		for row: int in lane_rows:
			for k in range(1, length):
				_connect(point.call(cell.call(row, k - 1)), point.call(cell.call(row, k)), lorries)
	if areas.kind_of(area) in ["yard_block", "quay_apron", "parking"]:
		# Each slot is entered sideways from the lane beside it (a block's or
		# park's buffer, an apron's through lane) and left sideways back into
		# it, so a parked vehicle never blocks the way to another slot.
		var lane := 2 if area.type == "quay_apron" else 0
		for s: int in layout.slots.size():
			var slot: Array = layout.slots[s]
			var ks := range(length).filter(func(k: int) -> bool: return cell.call(lane + 1, k) in slot)
			for k: int in ks:
				var p: int = point.call(cell.call(lane + 1, k))
				_area_points[id].erase(p)
				_area_of.erase(p)
				_slot_points.get_or_add(Vector2i(id, s), []).append(p)
				_slot_of[p] = Vector2i(id, s)
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


## What A* weighs route `ids` at on `graph`: each step's length times the
## weight of the point it enters.
static func _cost(graph: AStar2D, ids: PackedInt64Array) -> float:
	var total := 0.0
	for i in range(1, ids.size()):
		total += graph.get_point_position(ids[i - 1]).distance_to(graph.get_point_position(ids[i])) * graph.get_point_weight_scale(ids[i])
	return total

