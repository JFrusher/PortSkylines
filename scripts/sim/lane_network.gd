class_name LaneNetwork
extends RefCounted
## The lanes vehicles drive, built from a RoadNet's curves: each lane is a
## piece along its road's curve, cut back where a junction's shape needs
## room; connection pieces join the lanes across a junction under M7's turn
## rules, each lane on round a bend, and each lane back into the other way at
## a dead end. Routes run over pieces.

## Piece id -> {"points": PackedVector2Array in grid units, in driving order;
## "length": cells; "segment": its road, or 0 for a connection; "lane": its
## lane's index across the road, or -1; "next": the piece ids it leads into;
## "lorries": whether lorries may use it; "node": the node a connection
## crosses (minus its road's segment for a lane change), or 0; "kmh": its speed limit, a connection's the lower of the
## two roads it joins; "area": the area it is inside, or 0; "slot":
## Vector2i(area, slot) of the handover slot it is in, or (-1, -1)}.
var pieces := {}
## Connection piece -> the connection pieces at its node that cross it or
## come within CLEAR cells of it: a vehicle may take one only while none of
## its conflicts is in use.
var _conflicts := {}
const NO_SLOT := Vector2i(-1, -1)
## Junctions of three or more roads, by their grid point: each arm (the way
## out along a road, rounded to a grid step, as today's) -> the lane pieces
## arriving by it. Signals and signs are kept by these.
var _junctions := {}
var _arm_of := {}  # arriving lane piece -> [junction point, arm]
var _node_at := {}  # junction point -> node
## How near, in cells, two connections may pass without conflicting: two
## lanes side by side, a cell apart, don't.
const CLEAR := 0.9
var _next_id := 1
## Piece ids by where they end (_key), built on first use and dropped when
## a piece is added or split.
var _ends := {}
## Each piece's segments by the cell their start is in: cell ->
## [[piece, index of the segment's end point, distance along to its start]],
## built on first use and kept up to date as pieces are added and split;
## with the cells they span.
var _cells := {}
var _span := Rect2i()
var _filed := {}  # piece -> the cells its segments are filed under in _cells
## The longest a segment between two of a piece's points may be, in cells:
## lanes are sampled every half cell, and an area's pieces step diagonally.
const SEGMENT := 1.5
## Roads within this many degrees of straight on carry on through a node of
## two with no junction between them.
const STRAIGHT_ON := 10.0


## `arrows`: the junctions' lane arrows (Junctions.arrows), point -> arm ->
## lane -> its turns.
func _init(net: RoadNet, rules: Dictionary, arrows := {}) -> void:
	var arms_at := _arms(net)
	var trims := _trims(arms_at, rules)
	var lane_pieces := {}  # [segment, lane] -> its last piece
	var lane_starts := {}  # [segment, lane] -> its first piece
	for segment: int in net.segments:
		var curve := net.curve(segment)
		var road: Dictionary = net.types[net.segments[segment].type]
		var start: float = trims[[segment, "a"]]
		var stop: float = curve.length - trims[[segment, "b"]]
		assert(stop >= start - 0.001, "segment %d is longer than its junctions cut it back" % segment)
		var lanes := RoadCurve.lanes(road)
		# A lane beside one running the same way is cut either side of a
		# stretch at the road's middle where vehicles change lane; a road
		# without room for the longest vehicle clear of it at either end has none.
		var middle := (start + stop) / 2.0
		var change: float = rules.lane_change_cells
		var cuts: Array = [start, middle - change / 2.0, middle + change / 2.0, stop] if stop - start >= change + 2.0 * rules.lane_change_clear_cells else [start, stop]
		var parts := {}  # lane -> its pieces in driving order
		for k in lanes.size():
			var same := func(j: int) -> bool: return j >= 0 and j < lanes.size() and lanes[j].forward == lanes[k].forward
			var at: Array = cuts if same.call(k - 1) or same.call(k + 1) else [start, stop]
			var made: Array[int] = []
			for c in range(1, at.size()):
				var points := _along(curve, lanes[k].offset, at[c - 1], at[c])
				if not lanes[k].forward:
					points.reverse()
				made.append(_add(points, segment, k, road.lorries, 0, road.speed_kmh))
			if not lanes[k].forward:
				made.reverse()
			for c in range(1, made.size()):
				pieces[made[c - 1]].next.append(made[c])
			parts[k] = made
			lane_starts[[segment, k]] = made[0]
			lane_pieces[[segment, k]] = made[-1]
		for k in range(1, lanes.size()):
			if lanes[k].forward == lanes[k - 1].forward and parts[k].size() == 3:
				_change(parts[k - 1], parts[k], -segment)
				_change(parts[k], parts[k - 1], -segment)
	for node: int in arms_at:
		if arms_at[node].size() < 3:
			continue
		var point: Vector2 = net.nodes[node]
		_node_at[point] = node
		for arm: Dictionary in arms_at[node]:
			var way := arm_key(arm.direction)
			var lanes := RoadCurve.lanes(arm.road)
			for k in lanes.size():
				if not lanes[k].forward:
					var piece: int = lane_pieces[[arm.segment, _segment_lane(arm, k)]]
					_junctions.get_or_add(point, {}).get_or_add(way, []).append(piece)
					_arm_of[piece] = [point, way]
	for node: int in arms_at:
		var arms: Array[Dictionary] = arms_at[node]
		var pairs: Array = []
		if arms.size() == 1:
			pairs = _turn_back(arms[0])
		elif arms.size() == 2:
			pairs = _carry_on(arms)
		else:
			for link: Dictionary in RoadJunction.connections(arms, rules, arrows.get(net.nodes[node], {})):
				pairs.append([link.from, link.to])
		for pair: Array in pairs:
			var into: Dictionary = arms[pair[0][0]]
			var out: Dictionary = arms[pair[1][0]]
			_join(lane_pieces[[into.segment, _segment_lane(into, pair[0][1])]], lane_starts[[out.segment, _segment_lane(out, pair[1][1])]], node, arms.size() == 1)
	_find_conflicts()


## Junction `point`'s arms, sorted so they come in the same order every
## time; [] when it is no junction.
func arms(point: Vector2) -> Array:
	var found: Array = _junctions.get(point, {}).keys()
	found.sort()
	return found


## The lane pieces arriving at junction `point` by arm `arm`.
func approach(point: Vector2, arm: Vector2i) -> Array:
	return _junctions.get(point, {}).get(arm, [])


## The key an arm of a junction is kept by: its way out along its road, a
## unit vector times 1000 rounded, so arms any angle apart differ and the
## two ways of a straight road through a junction are each other's opposite.
static func arm_key(direction: Vector2) -> Vector2i:
	return Vector2i((direction.normalized() * 1000.0).round())


## [junction point, arm] of a lane piece arriving at a junction, or [].
func arm_of(piece: int) -> Array:
	return _arm_of.get(piece, [])


## The node at junction `point`, or 0.
func node_at(point: Vector2) -> int:
	return _node_at.get(point, 0)


## The connection pieces that conflict with connection `piece`.
func conflicts(piece: int) -> Array:
	return _conflicts.get(piece, [])


## The pieces along a route from piece `from` to piece `to`, both included,
## shortest by length; [] when there is none. It goes inside an area only if
## it starts or ends in it, and into a handover slot only as its start or end,
## so no route cuts through a buffer or a slot someone stands in. A lorry's
## (`lorry`) keeps to pieces lorries may use; every route weighs a piece by
## its length plus the cells its delay in `delays` (piece -> seconds) is
## worth at `speed` cells a second, so it goes round a jam that costs more.
func route(from: int, to: int, lorry := false, delays := {}, speed := 1.0) -> Array[int]:
	return route_to_any(from, [to] as Array[int], lorry, delays, speed)


## route()'s way to whichever of `ends` is nearest by its weighing.
func route_to_any(from: int, ends: Array[int], lorry := false, delays := {}, speed := 1.0) -> Array[int]:
	var areas := [pieces[from].area]
	var slots := [pieces[from].slot]
	for end in ends:
		areas.append(pieces[end].area)
		slots.append(pieces[end].slot)
	var cost := {from: 0.0}
	var came := {}
	var heap: Array = [[0.0, from]]
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var at: int = top[1]
		if at in ends:
			var found: Array[int] = [at]
			while found[0] != from:
				found.push_front(came[found[0]])
			return found
		if top[0] > cost[at]:
			continue
		for next: int in pieces[at].next:
			if next not in ends and (pieces[next].area != 0 and pieces[next].area not in areas or pieces[next].slot != NO_SLOT and pieces[next].slot not in slots):
				continue
			if lorry and not pieces[next].lorries:
				continue
			var through: float = cost[at] + pieces[next].length + delays.get(next, 0.0) * speed
			if through < cost.get(next, INF):
				cost[next] = through
				came[next] = at
				_push(heap, [through, next])
	return []


## Which way traffic runs along each area with driveways: area id -> 1 from
## its first column to its last, -1 the other way: the way of the road lane
## beside its front.
var flows := {}


## Every area's driveways (M10 6c-2b), from its layout on its own cells:
## each lane row (the buffer strip, an apron's through lane, a gate's lanes)
## a lane along its cells' middles in driving order; each slot entered
## sideways from the lane beside it, run along to its last cell, where a
## vehicle stands, and left sideways one cell on; an apron's and a gate's
## lanes reached down its first column and left up its last; and the road
## lane beside the buffer's first and last cells split for a way in and out.
func add_driveways(areas: Areas, kmh: float) -> void:
	var made: Array[int] = []
	var leaving := {}
	var ids := areas.list.keys()
	ids.sort()
	for id: int in ids:
		if areas.kind_of(areas.list[id]) in ["yard_block", "quay_apron", "gate", "parking"]:
			_add_driveway(id, areas, kmh, made, leaving)
	_link(made, leaving)


func _add_driveway(id: int, areas: Areas, kmh: float, made: Array[int], leaving: Dictionary) -> void:
	var area: Dictionary = areas.list[id]
	var kind := areas.kind_of(area)
	var layout: Dictionary = _local(areas.layout(id))
	if layout.buffer.size() < 2:
		return
	var curve := areas.curve(id)
	var centre := {}
	for cell: Dictionary in areas.shape(id).cells:
		centre[Vector2i(cell.k, cell.r)] = cell.centre
	var out := func(k: int) -> Vector2: return curve.right_at(area.from + k + 0.5) * area.side
	# The road lane beside the buffer's middle sets the way traffic runs.
	var middle: Vector2i = layout.buffer[layout.buffer.size() / 2]
	var beside := nearest(centre[middle] - out.call(middle.x), false)
	if beside[0] == 0 or pieces[beside[0]].segment == 0:
		return
	var flow := 1 if point_along(beside[0], beside[1])[1].dot(curve.direction_at(area.from + middle.x + 0.5)) > 0.0 else -1
	flows[id] = flow
	var lorries: bool = area.type != "quay_apron"
	var order := func(cells: Array) -> Array: return cells.duplicate() if flow > 0 else _reversed(cells)
	var rows := {0: order.call(layout.buffer)}  # lane row -> its cells in driving order
	var links: Array = []  # [from cell, to cell, slot]
	if kind == "quay_apron":
		rows[2] = order.call(layout.lanes[0])
	elif kind == "gate":
		for lane: Array in layout.lanes:
			rows[lane[0].y] = order.call(lane)
	var deepest: int = rows.keys().max()
	if deepest > 0:
		var first: int = rows[0][0].x
		var last: int = rows[0][-1].x
		for r in range(1, deepest + 1):
			links.append([Vector2i(first, r - 1), Vector2i(first, r), LaneNetwork.NO_SLOT])
			links.append([Vector2i(last, r), Vector2i(last, r - 1), LaneNetwork.NO_SLOT])
	var stops := {}  # lane row -> columns a lane is cut at
	for r: int in rows:
		stops[r] = {rows[r][0].x: true, rows[r][-1].x: true}
	for link: Array in links:
		for end: Vector2i in [link[0], link[1]]:
			if end.y in rows:
				stops[end.y][end.x] = true
	var slot_runs: Array = []
	if kind in ["yard_block", "parking", "quay_apron"]:
		var lane_row := 2 if kind == "quay_apron" else 0
		for s: int in layout.slots.size():
			var ks: Array = order.call(layout.slots[s])
			var columns: Array = rows[lane_row].map(func(c: Vector2i) -> int: return c.x)
			# Round a bend the lane may lack the cell beside a slot's ends: no way in, no slot.
			if ks[0].x not in columns or ks[-1].x not in columns:
				continue
			var into: Vector2i = Vector2i(ks[0].x, lane_row)
			var back: Vector2i = rows[lane_row][mini(columns.find(ks[-1].x) + 1, columns.size() - 1)]
			links.append([into, ks[0], Vector2i(id, s)])
			links.append([ks[-1], back, Vector2i(id, s)])
			slot_runs.append([ks, Vector2i(id, s)])
			stops[lane_row][into.x] = true
			stops[lane_row][back.x] = true
	elif kind == "gate":
		for slot: Array in layout.slots:
			var ks: Array = order.call(slot)
			stops[ks[0].y][ks[-1].x] = true
	# The lanes, cut where a link leaves or joins.
	for r: int in rows:
		var run: Array[Vector2] = []
		for cell: Vector2i in rows[r]:
			run.append(centre[cell])
			if cell.x in stops[r] and run.size() > 1:
				made.append(_area_piece(run, id, LaneNetwork.NO_SLOT, lorries, kmh))
				run = [centre[cell]]
	for slot_run: Array in slot_runs:
		var run: Array[Vector2] = []
		for cell: Vector2i in slot_run[0]:
			run.append(centre[cell])
		if run.size() > 1:
			made.append(_area_piece(run, id, slot_run[1], lorries, kmh))
	for link: Array in links:
		made.append(_area_piece([centre[link[0]], centre[link[1]]] as Array[Vector2], id, link[2], lorries, kmh))
	# In from the road beside the first buffer cell, out beside the last.
	var first_cell: Vector2i = rows[0][0]
	var last_cell: Vector2i = rows[0][-1]
	var way_in := _road_point(centre[first_cell] - out.call(first_cell.x))
	var way_out := _road_point(centre[last_cell] - out.call(last_cell.x))
	if way_in != Vector2.INF:
		made.append(_area_piece([way_in, centre[first_cell]] as Array[Vector2], id, LaneNetwork.NO_SLOT, lorries, kmh))
	if way_out != Vector2.INF:
		var exit := _area_piece([centre[last_cell], way_out] as Array[Vector2], id, LaneNetwork.NO_SLOT, lorries, kmh)
		made.append(exit)
		leaving[exit] = true


## The point on the road lane nearest `position`, its lane split there, or
## INF when no road lane is within a cell and a half.
func _road_point(position: Vector2) -> Vector2:
	var near := nearest(position, false)
	if near[0] == 0 or pieces[near[0]].segment == 0:
		return Vector2.INF
	var at: Vector2 = point_along(near[0], near[1])[0]
	if at.distance_to(position) > 1.5:
		return Vector2.INF
	split_at(at)
	return at


## An area piece through `points`, filled in to at most half a cell apart.
func _area_piece(points: Array[Vector2], area: int, slot: Vector2i, lorries: bool, kmh: float) -> int:
	var filled := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		var steps := maxi(1, ceili(points[i - 1].distance_to(points[i]) / 0.5))
		for n in range(1, steps + 1):
			filled.append(points[i - 1].lerp(points[i], float(n) / steps))
	var id := _add(filled, 0, -1, lorries, 0, kmh)
	pieces[id].area = area
	pieces[id].slot = slot
	return id


## `part` of a layout with its spots Vector3i(area, k, r) as the area's own
## cells Vector2i(k, r).
static func _local(part: Variant) -> Variant:
	if part is Vector3i:
		return Vector2i(part.y, part.z)
	if part is Dictionary:
		var found := {}
		for key: Variant in part:
			found[key] = _local(part[key])
		return found
	if part is Array:
		return part.map(func(item: Variant) -> Variant: return _local(item))
	return part


static func _reversed(cells: Array) -> Array:
	var found := cells.duplicate()
	found.reverse()
	return found


## Joins the pieces in `made` to every piece ending where each starts, and
## those in `leaving` on to the road lanes starting where they end.
func _link(made: Array[int], leaving: Dictionary) -> void:
	var ends := {}
	var road_starts := {}
	for id: int in pieces:
		ends.get_or_add(_key(pieces[id].points[-1]), []).append(id)
		if pieces[id].segment != 0:
			road_starts.get_or_add(_key(pieces[id].points[0]), []).append(id)
	for id in made:
		for before: int in ends.get(_key(pieces[id].points[0]), []):
			if before != id and id not in pieces[before].next:
				pieces[before].next.append(id)
		if id in leaving:
			pieces[id].next.append_array(road_starts.get(_key(pieces[id].points[-1]), []))


## `position` as a key two pieces meeting there share.
static func _key(position: Vector2) -> Vector2i:
	return Vector2i((position * 1000.0).round())


## The piece ending at `position` on a road's lane, splitting the lane's
## piece there if none ends there yet; 0 when no lane runs through it.
func split_at(position: Vector2) -> int:
	for id: int in pieces:
		if pieces[id].segment != 0 and pieces[id].points[-1].distance_to(position) < 0.001:
			return id
	for id: int in pieces.keys():
		var piece: Dictionary = pieces[id]
		if piece.segment == 0:
			continue
		var points: PackedVector2Array = piece.points
		for i in range(1, points.size()):
			if Geometry2D.get_closest_point_to_segment(position, points[i - 1], points[i]).distance_to(position) > 0.001:
				continue
			var before := points.slice(0, i)
			var after := points.slice(i)
			if before[-1].distance_to(position) > 0.001:
				before.append(position)
			if after[0].distance_to(position) > 0.001:
				after.insert(0, position)
			var rest := _add(after, piece.segment, piece.lane, piece.lorries, 0, piece.kmh)
			pieces[rest].next = piece.next
			if not _cells.is_empty():
				_unindex(id)
			piece.points = before
			_ends.clear()
			if not _cells.is_empty():
				_index(id)
			piece.length -= pieces[rest].length
			piece.next = [rest] as Array[int]
			return id
	return 0


## [the point `s` cells along piece `id`, the way it heads there].
func point_along(id: int, s: float) -> Array[Vector2]:
	var points: PackedVector2Array = pieces[id].points
	var left := s
	for i in range(1, points.size()):
		var step := points[i - 1].distance_to(points[i])
		if left <= step or i == points.size() - 1:
			var f := clampf(left / step, 0.0, 1.0) if step > 0.0 else 0.0
			return [points[i - 1].lerp(points[i], f), (points[i] - points[i - 1]).normalized()]
		left -= step
	return [points[-1], Vector2.ZERO]


## [the piece a lorry (`lorry`) or a tractor may use nearest `position`,
## how far along it that nearest point is], or [0, 0.0] with none. Of pieces
## meeting there it takes a road lane over a connection, then the one that
## ends there, so every way on is open.
func nearest(position: Vector2, lorry: bool) -> Array:
	if _cells.is_empty():
		_index_cells()
	var best := [0, 0.0]
	var closest := INF
	var centre := Vector2i(position.floor())
	# Rings of cells outwards, until no segment starting further out could be nearer.
	var furthest := maxi(maxi(absi(centre.x - _span.position.x), absi(centre.x - _span.end.x)), maxi(absi(centre.y - _span.position.y), absi(centre.y - _span.end.y)))
	var r := 0
	while closest + SEGMENT + 1.0 > r and r <= furthest:
		for cell in _ring(centre, r):
			for entry: Array in _cells.get(cell, []):
				var id: int = entry[0]
				if lorry and not pieces[id].lorries:
					continue
				var points: PackedVector2Array = pieces[id].points
				var at := Geometry2D.get_closest_point_to_segment(position, points[entry[1] - 1], points[entry[1]])
				var s: float = entry[2] + points[entry[1] - 1].distance_to(at)
				# On a tie a road lane beats a connection (a lane change ends on a lane), then the one ending there.
				var lane := int(pieces[id].segment != 0) - int(best[0] != 0 and pieces[best[0]].segment != 0)
				if at.distance_to(position) < closest - 0.001 or (at.distance_to(position) < closest + 0.001 and (lane > 0 or (lane == 0 and s > best[1]))):
					closest = minf(closest, at.distance_to(position))
					best = [id, minf(s, pieces[id].length)]
		r += 1
	return best


## Files every piece's segments under the cell its start is in.
func _index_cells() -> void:
	_span = Rect2i(Vector2i(pieces.values()[0].points[0].floor()), Vector2i.ONE)
	for id: int in pieces:
		_index(id)


## Files piece `id`'s segments under the cells their starts are in.
func _index(id: int) -> void:
	var points: PackedVector2Array = pieces[id].points
	var along := 0.0
	var filed: Array[Vector2i] = []
	for i in range(1, points.size()):
		assert(points[i - 1].distance_to(points[i]) <= SEGMENT + 0.01, "piece %d's points are at most SEGMENT apart" % id)
		var cell := Vector2i(points[i - 1].floor())
		_cells.get_or_add(cell, []).append([id, i, along])
		filed.append(cell)
		_span = _span.expand(cell)
		along += points[i - 1].distance_to(points[i])
	_filed[id] = filed


## Takes piece `id`'s segments out of the cells they are filed under.
func _unindex(id: int) -> void:
	for cell: Vector2i in _filed.get(id, []):
		_cells[cell] = _cells[cell].filter(func(entry: Array) -> bool: return entry[0] != id)
	_filed.erase(id)


## The cells `r` steps out from `centre`, round a square.
static func _ring(centre: Vector2i, r: int) -> Array[Vector2i]:
	if r == 0:
		return [centre]
	var found: Array[Vector2i] = []
	for d in range(-r, r + 1):
		found.append(centre + Vector2i(d, -r))
		found.append(centre + Vector2i(d, r))
	for d in range(-r + 1, r):
		found.append(centre + Vector2i(-r, d))
		found.append(centre + Vector2i(r, d))
	return found


## The pieces that end at `position`.
func ending_at(position: Vector2) -> Array[int]:
	if _ends.is_empty():
		for id: int in pieces:
			_ends.get_or_add(_key(pieces[id].points[-1]), [] as Array[int]).append(id)
	return _ends.get(_key(position), [] as Array[int])


## How far a vehicle at the end of a route's first piece drives to the end
## of its last, in cells: every piece but the one it starts on.
func length(route: Array[int]) -> float:
	var total := 0.0
	for id: int in route.slice(1):
		total += pieces[id].length
	return total


## Each node's arms: {"segment", "end": "a" or "b", "direction": unit vector
## away from the node, "road": its type as drawn away from the node}.
static func _arms(net: RoadNet) -> Dictionary:
	var found := {}
	for segment: int in net.segments:
		var road: Dictionary = net.segments[segment]
		var curve := net.curve(segment)
		var type: Dictionary = net.types[road.type]
		found.get_or_add(road.a, [] as Array[Dictionary]).append({"segment": segment, "end": "a", "direction": curve.direction_at(0.0), "road": type})
		var flipped := type.duplicate()
		flipped.forward = type.backward
		flipped.backward = type.forward
		found.get_or_add(road.b, [] as Array[Dictionary]).append({"segment": segment, "end": "b", "direction": -curve.direction_at(curve.length), "road": flipped})
	return found


## How far each road end is cut back from its node: [segment, end] -> cells.
## A junction of three or more, or a bend, is shaped; a road carrying straight
## on or ending is not cut back.
static func _trims(arms_at: Dictionary, rules: Dictionary) -> Dictionary:
	var found := {}
	for node: int in arms_at:
		var arms: Array[Dictionary] = arms_at[node]
		var trims: Array = []
		trims.resize(arms.size())
		trims.fill(0.0)
		var straight: bool = arms.size() == 2 and absf(arms[0].direction.angle_to(arms[1].direction)) >= deg_to_rad(180.0 - STRAIGHT_ON)
		if arms.size() >= 2 and not straight:
			var shape := RoadJunction.shape(RoadJunction.footprints(arms), rules)
			assert(not shape.has("error"), "roads at node %d part by the junctions' minimum angle" % node)
			trims = shape.trims
		for i in arms.size():
			found[[arms[i].segment, arms[i].end]] = trims[i]
	return found


## Which segment lane is arm lane `k` of `arm`: the same at a road's a end;
## mirrored across the road at its b end, which looks back along it.
static func _segment_lane(arm: Dictionary, k: int) -> int:
	return k if arm.end == "a" else arm.road.forward + arm.road.backward - 1 - k


## At a dead end, every lane coming in turns back into every lane going out.
static func _turn_back(arm: Dictionary) -> Array:
	var lanes := RoadCurve.lanes(arm.road)
	var pairs: Array = []
	for i in lanes.size():
		for j in lanes.size():
			if not lanes[i].forward and lanes[j].forward:
				pairs.append([[0, i], [0, j]])
	return pairs


## Round a bend of two roads, each lane coming in carries on into the lane
## going out that is as far from the middle: left to right, in order; where
## one road has more lanes, its extra ones join the other's outermost.
static func _carry_on(arms: Array[Dictionary]) -> Array:
	var pairs: Array = []
	for i in 2:
		var lanes := RoadCurve.lanes(arms[i].road)
		var out := RoadCurve.lanes(arms[1 - i].road)
		# Coming in, the lane nearest the middle is the driver's left; going out, likewise.
		var inbound := range(lanes.size()).filter(func(k: int) -> bool: return not lanes[k].forward)
		inbound.sort_custom(func(a: int, b: int) -> bool: return lanes[a].offset > lanes[b].offset)
		var outbound := range(out.size()).filter(func(k: int) -> bool: return out[k].forward)
		outbound.sort_custom(func(a: int, b: int) -> bool: return out[a].offset < out[b].offset)
		# Where the count changes, the outermost lane fans out into the extra
		# lanes, or they merge into it, so every lane has a way in and on.
		for n in maxi(inbound.size(), outbound.size()) if not (inbound.is_empty() or outbound.is_empty()) else 0:
			pairs.append([[i, inbound[mini(n, inbound.size() - 1)]], [1 - i, outbound[mini(n, outbound.size() - 1)]]])
	return pairs


## Joins piece `into` to piece `out` across node `node`: straight on where
## they meet, else along a connection curve from one's end to the other's
## start, its control point where their lines cross (beyond the road's end
## for a turn back at a dead end).
func _join(into: int, out: int, node: int, dead_end: bool) -> void:
	var start: Vector2 = pieces[into].points[-1]
	var end: Vector2 = pieces[out].points[0]
	if start.distance_to(end) < 0.001:
		pieces[into].next.append(out)
		return
	var heading := _direction(pieces[into].points, true)
	var away := _direction(pieces[out].points, false)
	var control := (start + end) / 2.0 + heading * start.distance_to(end) if dead_end else RoadJunction._control(start, heading, end, away)
	var curve := RoadCurve.new(start, control, end)
	var id := _add(_along(curve, 0.0, 0.0, curve.length), 0, -1, pieces[into].lorries and pieces[out].lorries, node, minf(pieces[into].kmh, pieces[out].kmh))
	pieces[into].next.append(id)
	pieces[id].next.append(out)


## A lane change from lane `from`'s first piece to lane `to`'s last (each
## cut in three), straight across the stretch between: a connection at
## `node`, a road's own (minus its segment), booked as a junction's are.
func _change(from: Array[int], to: Array[int], node: int) -> void:
	var start: Vector2 = pieces[from[0]].points[-1]
	var end: Vector2 = pieces[to[2]].points[0]
	var curve := RoadCurve.new(start, (start + end) / 2.0, end)
	var id := _add(_along(curve, 0.0, 0.0, curve.length), 0, -1, pieces[from[0]].lorries, node, pieces[from[0]].kmh)
	pieces[from[0]].next.append(id)
	pieces[id].next.append(to[2])


func _add(points: PackedVector2Array, segment: int, lane: int, lorries: bool, node: int, kmh: float) -> int:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	_ends.clear()
	pieces[_next_id] = {"points": points, "length": total, "segment": segment, "lane": lane, "next": [] as Array[int], "lorries": lorries, "node": node, "kmh": kmh, "area": 0, "slot": NO_SLOT}
	_next_id += 1
	# Kept up to date once built, rather than built again for each piece added.
	if not _cells.is_empty():
		_index(_next_id - 1)
	return _next_id - 1


## Pairs every two connections at a node that cross or pass within CLEAR.
func _find_conflicts() -> void:
	var at := {}  # node -> its connection pieces
	for id: int in pieces:
		if pieces[id].node != 0:
			at.get_or_add(pieces[id].node, []).append(id)
	for node: int in at:
		var links: Array = at[node]
		var near := _near_pairs(links)
		for i in links.size():
			for j in range(i + 1, links.size()):
				if Vector2i(i, j) in near:
					_conflicts.get_or_add(links[i], []).append(links[j])
					_conflicts.get_or_add(links[j], []).append(links[i])


## The pairs of `links` (by index, lower first) whose polylines cross or
## pass within CLEAR cells of each other. Each segment is filed by the cell
## its start is in, cells wide enough that two segments that near (each at
## most SEGMENT long) start in the same cell or neighbouring ones, so only
## those are measured.
func _near_pairs(links: Array) -> Dictionary:
	var size := CLEAR + 2.0 * SEGMENT
	var filed := {}  # cell -> [link index, index of the segment's end point]
	for k in links.size():
		var points: PackedVector2Array = pieces[links[k]].points
		for i in range(1, points.size()):
			filed.get_or_add(Vector2i((points[i - 1] / size).floor()), []).append([k, i])
	var found := {}
	for cell: Vector2i in filed:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for a: Array in filed[cell]:
					for b: Array in filed.get(cell + Vector2i(dx, dy), []):
						if a[0] >= b[0] or Vector2i(a[0], b[0]) in found:
							continue
						var one: PackedVector2Array = pieces[links[a[0]]].points
						var two: PackedVector2Array = pieces[links[b[0]]].points
						var closest := Geometry2D.get_closest_points_between_segments(one[a[1] - 1], one[a[1]], two[b[1] - 1], two[b[1]])
						if closest[0].distance_to(closest[1]) < CLEAR:
							found[Vector2i(a[0], b[0])] = true
	return found


## Points along `curve` offset `offset` cells right, from `start` to `stop`
## cells along it, about every half cell and at both ends.
static func _along(curve: RoadCurve, offset: float, start: float, stop: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	# shortcut: a stub shorter than its junctions' trims runs start > stop; sampled by its span all the same. Cap trims on short segments if such stubs drive oddly.
	var count := maxi(1, ceili(absf(stop - start) / 0.5))
	for i in count + 1:
		var d := lerpf(start, stop, float(i) / count)
		points.append(curve.point_at(d) + curve.right_at(d) * offset)
	return points


## The way a piece's points head at their end (`at_end`) or start.
static func _direction(points: PackedVector2Array, at_end: bool) -> Vector2:
	return (points[-1] - points[-2]).normalized() if at_end else (points[1] - points[0]).normalized()


## A binary heap of [cost, piece] on an array, cheapest first.
static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0 and heap[(i - 1) / 2][0] > heap[i][0]:
		var parent := (i - 1) / 2
		var swap: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var smallest := i
		for child: int in [2 * i + 1, 2 * i + 2]:
			if child < heap.size() and heap[child][0] < heap[smallest][0]:
				smallest = child
		if smallest == i:
			return top
		var swap: Array = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = swap
		i = smallest
	return top
