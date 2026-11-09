class_name RoadNet
extends RefCounted
## The roads the player draws, or the rail track: nodes anywhere, in grid
## units (point (x, y) is the top-left corner of cell (x, y)), joined by
## quadratic curves (RoadCurve). In the sim a road is the quads its lanes
## cover (shape) and the cells under them (ground).
##
## A road's lanes lie evenly either side of its line, as in Cities: Skylines,
## so which way it was drawn never moves it. Track is laid through cell
## middles (M10 step 19).

## Node id -> where it is, in grid units.
var nodes := {}
## Segment id -> {"a": node id, "b": node id, "type": a key of road_types,
## "control": its curve's control point, at its middle while it is straight}.
var segments := {}
## The data's road types: lanes each way, whether lorries may use them, costs.
var types: Dictionary
## The data's junction rules: the least angle roads part by (min_angle) and
## how far a junction cuts its roads back (see RoadJunction.shape).
var junctions: Dictionary
## Bumped on every change, so the lane graph knows to rebuild.
var version := 0
var _next_node := 1
var _next_segment := 1
## How many curves a roundabout's ring is made of.
const RING_PIECES := 8
## How near, in degrees, a drag's way must come to a 15° step to snap to it.
const ANGLE_SNAP := 5.0
## How near, in cells, a drag's end must come to a guide line to snap onto it.
const GUIDE_SNAP := 1.0
## How near, in cells, a drawn road's ends must come to a road to snap onto it.
const SNAP_CELLS := 3
## How far a guide runs on from a road's end, in cells.
const GUIDE_CELLS := 60
## Cells a drag snaps onto as onto a road's end, though no road is there yet:
## where the highway meets the site.
var anchors: Array[Vector2] = []
var _next_cells := {}  # cell -> cells a step on along a segment, for path()
var _shapes := {}  # segment -> [what it is laid from, its AreaShape, its ground as cell -> true]
var _next_for := -1


func _init(road_types: Dictionary, junction_rules: Dictionary) -> void:
	types = road_types
	junctions = junction_rules
	var parities := {}
	for type: Dictionary in types.values():
		parities[(type.forward + type.backward) % 2] = true
	assert(parities.size() <= 1, "a net's road types are all even-width or all odd-width")


## Adds a straight road of `type` from `from` to `to`. Its forward lanes run
## from `from` to `to` on the drawn line and to its right; backward lanes lie
## to its left. An end within a road's half width of its end or line joins
## it there, and where it crosses another road both split at the crossing
## point, so junctions form by themselves. Returns "" or why it can't be built.
func add(from: Vector2, to: Vector2, type: String, control := Vector2.INF) -> String:
	var err := add_error(from, to, type, 0, control)
	if err != "":
		return err
	_place(_plan(from, to, type, 0, control), type)
	return ""


## Adds a roundabout of `type` round `centre`, `radius` cells out: a ring of
## RING_PIECES curves, each a piece of the circle, running anticlockwise as
## seen from above (with y down, the way angles fall), so traffic on it keeps
## right; "" or why it can't be built, when nothing of it is.
func add_ring(centre: Vector2, radius: float, type: String) -> String:
	var err := ring_error(centre, radius, type)
	if err == "":
		for piece: Array in ring_pieces(centre, radius):
			add(piece[0], piece[2], type, piece[1])
	return err


## Why add_ring would refuse this ring, or "": its pieces tried on a copy.
func ring_error(centre: Vector2, radius: float, type: String) -> String:
	if type not in types or not types[type].ring:
		return "Roundabouts are built of roundabout road"
	var trial := RoadNet.from_dict(to_dict(), types, junctions)
	for piece: Array in ring_pieces(centre, radius):
		var err := trial.add(piece[0], piece[2], type, piece[1])
		if err != "":
			return err
	return ""


## [start, control, end] of each piece of a ring round `centre`, `radius`
## cells out, in order round it; each end is the next one's start exactly.
static func ring_pieces(centre: Vector2, radius: float) -> Array:
	var step := TAU / RING_PIECES
	var at := func(k: int) -> Vector2: return centre + Vector2.from_angle(-step * (k % RING_PIECES)) * radius
	var found := []
	for k in RING_PIECES:
		found.append([at.call(k), centre + Vector2.from_angle(-step * (k + 0.5)) * radius / cos(step / 2.0), at.call(k + 1)])
	return found


## Builds what _plan laid out: splits the roads it meets, then its pieces.
## Returns the nodes its pieces end at.
func _place(plan: Dictionary, type: String) -> Array[int]:
	for point: Vector2 in plan.splits:
		_split_through(point)
	var ends: Array[int] = []
	for piece: Array in plan.pieces:
		segments[_next_segment] = {"a": _node_near(piece[0]), "b": _node_near(piece[2]), "type": type, "control": piece[1]}
		ends.append_array([segments[_next_segment].a, segments[_next_segment].b])
		_next_segment += 1
	version += 1
	return ends


## Why a road from `from` to `to` of `type` (or, with `skip`, segment
## `skip` as `type`) would leave a road at the nodes it touches shorter than
## the junctions at its ends cut it back, so it has no lane left; or "".
func _room_error(from: Vector2, to: Vector2, type: String, skip: int, control: Vector2) -> String:
	var trial := RoadNet.from_dict(to_dict(), types, junctions)
	var touched: Array[int] = []
	if skip:
		trial.segments[skip].type = type
		touched.assign([segments[skip].a, segments[skip].b])
	else:
		touched = trial._place(trial._plan(from, to, type, 0, control), type)
	var trims := LaneNetwork._trims(LaneNetwork._arms(trial), junctions)
	for id: int in trial.segments:
		var road: Dictionary = trial.segments[id]
		if (road.a in touched or road.b in touched) and trial.curve(id).length < trims[[id, "a"]] + trims[[id, "b"]] - 0.001:
			return "Too close to a junction: a road needs room between its junctions"
	return ""




## Why `add` would refuse this road, or "": as though `skip` weren't built,
## so a segment can be checked as another type in its own place.
func add_error(from: Vector2, to: Vector2, type: String, skip := 0, control := Vector2.INF) -> String:
	var found: Variant = _plan(from, to, type, skip, control)
	if found is String:
		return found
	# Track has no lanes for traffic, so no junction cuts it back.
	return "" if _track() else _room_error(from, to, type, skip, control)


## Where a road of `type` from `from` to `to`, curving through `control`
## (INF: straight), would run and meet the roads built (as though `skip`
## weren't): {"pieces": [start, control, end] of each piece of it between
## the roads it meets, in order from `from`, "splits": the points where a
## road it meets splits}; or why it can't be built.
func _plan(from: Vector2, to: Vector2, type: String, skip := 0, control := Vector2.INF) -> Variant:
	if type not in types:
		return "Unknown road type \"%s\"" % type
	var meets: Array[Dictionary] = []  # {"point", "node": the node there or 0, "segment": the road split there or 0}
	var ends: Array[Vector2] = [from, to]
	for e in 2:
		var joined := _join(ends[e], skip)
		if not joined.is_empty():
			ends[e] = joined.point
			meets.append(joined)
	if ends[0].distance_to(ends[1]) < 1.0:
		return "A road needs a length"
	var mine := RoadCurve.new(ends[0], (ends[0] + ends[1]) / 2.0 if control == Vector2.INF else control, ends[1])
	var half: float = (types[type].forward + types[type].backward) / 2.0
	if mine.min_radius() < types[type].min_radius_cells:
		return "Too tight a curve: a %s turns no tighter than %d m" % [types[type].name.to_lower(), Grid.metres(types[type].min_radius_cells)]
	var bounds := Rect2(mine.a, Vector2.ZERO).expand(mine.b).expand(mine.c).grow(half + 1.0)
	var near: Array[int] = []  # the roads near enough to cross or overlap it
	for id: int in segments:
		if id != skip and _hull(id).intersects(bounds):
			near.append(id)
	var line := mine.offset_points(0.0)
	var crossings: Array[float] = []  # distances along it
	for id in near:
		var theirs := curve(id).offset_points(0.0)
		for i in range(1, line.size()):
			for j in range(1, theirs.size()):
				var hit: Variant = Geometry2D.segment_intersects_segment(line[i - 1], line[i], theirs[j - 1], theirs[j])
				if hit == null or meets.any(func(m: Dictionary) -> bool: return m.point.distance_to(hit) < 0.01) or hit.distance_to(ends[0]) < 0.01 or hit.distance_to(ends[1]) < 0.01:
					continue
				var at := _node_close(hit)
				var point: Vector2 = nodes[at] if at else hit
				meets.append({"point": point, "node": at, "segment": 0 if at else id})
				crossings.append(mine.nearest(point))
	crossings.sort()
	# Lanes overlap only near where roads meet: as far from it as two roads
	# that wide overlap at the angle they meet at, and a cell more. One along
	# another meets it at under a degree, which the angles below refuse.
	for meet in meets:
		var way := mine.direction_at(mine.nearest(meet.point))
		var sharpest := 90.0
		for arm in _arms_at(meet, skip):
			var apart := absf(rad_to_deg(arm.angle_to(way)))
			sharpest = minf(sharpest, minf(apart, 180.0 - apart))
		meet.reach = (half + _widest(meet, skip)) / sin(deg_to_rad(maxf(sharpest, 1.0))) + 1.0
	var laid := _shape_of(mine, types[type])
	for id in near:
		for theirs: Dictionary in shape(id).cells:
			for cell: Dictionary in laid.cells:
				if cell.centre.distance_to(theirs.centre) < 1.5 and not meets.any(func(m: Dictionary) -> bool: return m.point.distance_to(cell.centre) < m.reach) and Areas.overlap(PackedVector2Array(cell.corners), PackedVector2Array(theirs.corners)):
					return "A road already runs here"
	for meet: Dictionary in meets:
		var arms: Array[Vector2] = _arms_at(meet, skip)
		var d := mine.nearest(meet.point)
		if meet.point.distance_to(ends[0]) > 0.01:
			arms.append(-mine.direction_at(d))
		if meet.point.distance_to(ends[1]) > 0.01:
			arms.append(mine.direction_at(d))
		for i in arms.size():
			for j in range(i + 1, arms.size()):
				var apart := rad_to_deg(arms[i].angle_to(arms[j]))
				if absf(apart) < 1.0:
					return "A road already runs here"
				if absf(apart) < junctions.min_angle - 0.001:
					return "Roads meet at %d°; a junction needs at least %d°" % [roundi(absf(apart)), roundi(junctions.min_angle)]
	# Its pieces between the points it meets roads at, each its part of the curve.
	var cuts: Array[float] = [0.0]
	cuts.append_array(crossings)
	cuts.append(mine.length)
	var pieces: Array = []
	for i in cuts.size() - 1:
		var t0 := mine.t_at(cuts[i])
		var t1 := mine.t_at(cuts[i + 1])
		var start: Vector2 = ends[0] if i == 0 else meets.filter(func(m: Dictionary) -> bool: return m.point.distance_to(mine.point_at(cuts[i])) < 0.05)[0].point
		var stop: Vector2 = ends[1] if i == cuts.size() - 2 else meets.filter(func(m: Dictionary) -> bool: return m.point.distance_to(mine.point_at(cuts[i + 1])) < 0.05)[0].point
		pieces.append([start, (start + stop) / 2.0 if control == Vector2.INF else mine.control_between(t0, t1), stop])
	return {"pieces": pieces, "splits": meets.filter(func(m: Dictionary) -> bool: return m.segment != 0).map(func(m: Dictionary) -> Vector2: return m.point)}


## Where a road's end at `point` joins the roads built (but `skip`): a node
## within the half width of a road there, else the nearest point on a road's
## line within its half width: {"point", "node", "segment": the road split
## there or 0}; {} when none is that near.
func _join(point: Vector2, skip: int) -> Dictionary:
	var best := {}
	var nearest := INF
	for node: int in nodes:
		var reach := 0.0
		for id: int in segments:
			if id != skip and node in [segments[id].a, segments[id].b]:
				reach = maxf(reach, _half(id))
		if nodes[node].distance_to(point) <= reach and nodes[node].distance_to(point) < nearest:
			nearest = nodes[node].distance_to(point)
			best = {"point": nodes[node], "node": node, "segment": 0}
	if not best.is_empty():
		return best
	for id: int in segments:
		if id == skip:
			continue
		var along := curve(id)
		var on := along.point_at(along.nearest(point))
		# A point on the line already stays put, not moved by the search's rounding.
		on = point if on.distance_to(point) < 0.01 else on
		if on.distance_to(point) <= _half(id) and on.distance_to(point) < nearest:
			nearest = on.distance_to(point)
			best = {"point": on, "node": 0, "segment": id}
	return best


## The ways out of meeting `meet` along the roads built there (but `skip`).
func _arms_at(meet: Dictionary, skip: int) -> Array[Vector2]:
	var found: Array[Vector2] = []
	if meet.segment:
		var along := curve(meet.segment)
		var tangent := along.direction_at(along.nearest(meet.point))
		found.append_array([tangent, -tangent])
		return found
	for id: int in segments:
		if id == skip:
			continue
		if segments[id].a == meet.node:
			found.append(curve(id).direction_at(0.0))
		if segments[id].b == meet.node:
			found.append(-curve(id).direction_at(curve(id).length))
	return found


## The box `segment` lies in, its lanes included: its curve keeps within
## the triangle of its ends and control point.
func _hull(segment: int) -> Rect2:
	var road: Dictionary = segments[segment]
	return Rect2(nodes[road.a], Vector2.ZERO).expand(nodes[road.b]).expand(road.control).grow(_half(segment))


## Half the width of the widest road built at meeting `meet` (but `skip`).
func _widest(meet: Dictionary, skip: int) -> float:
	if meet.segment:
		return _half(meet.segment)
	var widest := 0.0
	for id: int in segments:
		if id != skip and meet.node in [segments[id].a, segments[id].b]:
			widest = maxf(widest, _half(id))
	return widest


## Half of `segment`'s width, in cells.
func _half(segment: int) -> float:
	var road: Dictionary = types[segments[segment].type]
	return (road.forward + road.backward) / 2.0


## The node within a hundredth of a cell of `point`, or 0.
func _node_close(point: Vector2) -> int:
	for id: int in nodes:
		if nodes[id].distance_to(point) < 0.01:
			return id
	return 0


## The node at `point`, made if there is none within a hundredth of a cell.
func _node_near(point: Vector2) -> int:
	var found := _node_close(point)
	if found:
		return found
	nodes[_next_node] = point
	_next_node += 1
	return _next_node - 1


## Splits the road whose line runs through `point` there, unless one ends
## there: it keeps its a end, and a new one of the same type runs on to its b
## end; each half is its piece of the curve, so the line doesn't move.
func _split_through(point: Vector2) -> void:
	if _node_close(point):
		return
	for id: int in segments.keys():
		var along := curve(id)
		var d := along.nearest(point)
		if along.point_at(d).distance_to(point) > 0.01:
			continue
		var t := along.t_at(d)
		var first := along.a.lerp(along.c, t)
		var second := along.c.lerp(along.b, t)
		# A straight road's halves are straight: each control at its middle.
		if along.c.is_equal_approx((along.a + along.b) / 2.0):
			first = (along.a + point) / 2.0
			second = (point + along.b) / 2.0
		var middle := _node_near(point)
		var road: Dictionary = segments[id]
		segments[_next_segment] = {"a": middle, "b": road.b, "type": road.type, "control": second}
		_next_segment += 1
		road.b = middle
		road.control = first
		return


## Makes `segment` a road of `type` on the same line, the same way round,
## keeping its id. The caller checks add_error with `skip` set to it first.
func retype(segment: int, type: String) -> void:
	segments[segment].type = type
	version += 1


## Takes `segment` out, and any node left with no road.
func remove(segment: int) -> void:
	var road: Dictionary = segments[segment]
	segments.erase(segment)
	for node: int in [road.a, road.b]:
		if degree(node) == 0:
			nodes.erase(node)
	version += 1


## The segment standing on `cell` (its ground), or 0.
func segment_at(cell: Vector2i) -> int:
	for id: int in segments:
		if cell in _laid(id)[2]:
			return id
	return 0


## `segment`'s lanes as quads along its curve, as an area's cells are laid
## (AreaShape): half its lanes either side of its line, in columns a cell
## long, or a little less so a whole number of them run its length.
func shape(segment: int) -> AreaShape:
	return _laid(segment)[1]


## The grid cells `segment` stands on (see _ground_of).
func ground(segment: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	found.assign(_laid(segment)[2].keys())
	return found


## [what `segment` is laid from, its shape, its ground], laid again only when it changes.
func _laid(segment: int) -> Array:
	var road: Dictionary = segments[segment]
	var key := [nodes[road.a], road.control, nodes[road.b], road.type]
	if segment not in _shapes or _shapes[segment][0] != key:
		var shape := _shape_of(curve(segment), types[road.type])
		_shapes[segment] = [key, shape, _ground_of(curve(segment), shape)]
	return _shapes[segment]


## The cells a road with `shape` along `curve` stands on, as a set: a
## road's, those under its quads' middles; track's, those its line runs
## through, as track runs through cell middles and its quads' middles fall
## on cell edges.
func _ground_of(curve: RoadCurve, shape: AreaShape) -> Dictionary:
	var under := {}
	if _track():
		var steps := maxi(1, ceili(curve.length / 0.25))
		for n in steps + 1:
			under[Vector2i(curve.point_at(curve.length * n / steps).floor())] = true
		return under
	for cell: Dictionary in shape.cells:
		under[Vector2i(cell.centre.floor())] = true
	return under


## A road of type `road` laid along `curve` (see shape).
static func _shape_of(curve: RoadCurve, road: Dictionary) -> AreaShape:
	var columns := cells_long(curve.length)
	var width: int = road.forward + road.backward
	return AreaShape.along(curve, 1, 0.0, columns, -width / 2.0, width, curve.length / columns)


## Whether this net is rail track (its one type is a single lane one way).
func _track() -> bool:
	return types.has("track")


## `segment`'s line as a curve, in grid units.
func curve(segment: int) -> RoadCurve:
	var road: Dictionary = segments[segment]
	return RoadCurve.new(nodes[road.a], road.control, nodes[road.b])


## How many cells a road `length` long is counted as, for its price and
## upkeep: one per cell of its shape's columns (see shape).
static func cells_long(length: float) -> int:
	return ceili(length - 0.001)


## A road's length in cells from `from` to `to`, which costs are counted in:
## the cells along it between two grid points, or along it from cell to cell.
static func length(from: Vector2i, to: Vector2i) -> int:
	var d := (to - from).abs()
	return maxi(d.x, d.y)


## `to` moved onto the nearest straight or 45° line from `from`, as the draw tool snaps.
static func snap(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	if absi(d.x) > 2 * absi(d.y):
		return from + Vector2i(d.x, 0)
	if absi(d.y) > 2 * absi(d.x):
		return from + Vector2i(0, d.y)
	var run := roundi((absi(d.x) + absi(d.y)) / 2.0)
	return from + d.sign() * run


## Where a drag from `from` toward `to` for a road of `type` ends, as Cities:
## Skylines snaps it: onto a road near `to` (snap_point); else onto a guide
## line within GUIDE_SNAP of it, on from a road's end or parallel to a
## nearby straight road at the gap where both roads' lanes just clear; else
## its way snaps to the nearest 15° step from east or from the road it
## starts on, within ANGLE_SNAP, and its length to whole cells. {"point",
## "guides": [from, to] of each guide line it lies on, to draw}.
func snap_drag(from: Vector2, to: Vector2, type: String) -> Dictionary:
	var onto := snap_point(to, from)
	if onto != to:
		return {"point": onto, "guides": []}
	var found := {}
	var nearest := GUIDE_SNAP
	for line: Array in _guide_lines(from, to, type):
		var along: float = (to - line[0]).dot(line[1])
		if along < line[2] or along > line[3]:
			continue
		var on: Vector2 = line[0] + line[1] * along
		if on.distance_to(to) <= nearest:
			nearest = on.distance_to(to)
			found = {"point": on, "guides": [[line[0], on]]}
	if not found.is_empty():
		return found
	var way := to - from
	if way.length() < 0.5:
		return {"point": to, "guides": []}
	var steps: Array[float] = [0.0]
	for id: int in segments:
		var along := curve(id)
		var at := along.nearest(from)
		if along.point_at(at).distance_to(from) < 0.01:
			steps.append(along.direction_at(at).angle())
	var angle := way.angle()
	var closest := deg_to_rad(ANGLE_SNAP)
	for step in steps:
		for k in 24:
			var snapped := step + deg_to_rad(15.0 * k)
			if absf(angle_difference(way.angle(), snapped)) <= closest:
				closest = absf(angle_difference(way.angle(), snapped))
				angle = snapped
	return {"point": from + Vector2.from_angle(angle) * maxf(1.0, roundf(way.length())), "guides": []}


## The guide lines a drag from `from` for a road of `type` can snap onto
## near `to`: [origin, unit way, least and most distance along it]. Each
## road's dead end leads on along its way GUIDE_CELLS; each straight road
## near `to` has a line either side, parallel to it at the gap where both
## roads' lanes just clear, along its length and GUIDE_CELLS beyond.
func _guide_lines(from: Vector2, to: Vector2, type: String) -> Array:
	var half: float = (types[type].forward + types[type].backward) / 2.0
	var found := []
	for id: int in segments:
		var road: Dictionary = segments[id]
		var along := curve(id)
		for end: String in ["a", "b"]:
			if degree(road[end]) == 1 and nodes[road[end]] != from:
				var out := -along.direction_at(0.0) if end == "a" else along.direction_at(along.length)
				found.append([nodes[road[end]], out, 1.0, float(GUIDE_CELLS)])
		if road.control.is_equal_approx((nodes[road.a] + nodes[road.b]) / 2.0) and _hull(id).grow(half + GUIDE_SNAP + _half(id)).has_point(to):
			var way := along.direction_at(0.0)
			for side: int in [1, -1]:
				found.append([nodes[road.a] + along.right_at(0.0) * (_half(id) + half) * side, way, -float(GUIDE_CELLS), along.length + GUIDE_CELLS])
	return found


## Where a road drag's end at `near` snaps onto the roads, as Cities:
## Skylines snaps: a road's end, a junction or an anchor within SNAP_CELLS
## before any other point, else the nearest point on a road's line that
## close; roads through `from` (the drag's start) don't count, so a drag
## never snaps back along its own road; else `near` itself.
func snap_point(near: Vector2, from := Vector2.INF) -> Vector2:
	var best := near
	var best_score := INF
	for id: int in segments:
		if not _hull(id).grow(SNAP_CELLS).has_point(near):
			continue
		var along := curve(id)
		if from != Vector2.INF and along.point_at(along.nearest(from)).distance_to(from) < 0.01:
			continue
		for node: int in [segments[id].a, segments[id].b]:
			var d: float = nodes[node].distance_to(near)
			if d <= SNAP_CELLS and d - SNAP_CELLS * 2 < best_score:
				best = nodes[node]
				best_score = d - SNAP_CELLS * 2
		var on := along.point_at(along.nearest(near))
		if on.distance_to(near) <= SNAP_CELLS and on.distance_to(near) < best_score:
			best = on
			best_score = on.distance_to(near)
	for anchor in anchors:
		var d := Vector2(anchor).distance_to(near)
		if d <= SNAP_CELLS and d - SNAP_CELLS * 2 < best_score:
			best = Vector2(anchor)
			best_score = d - SNAP_CELLS * 2
	return best


## Where a road drag starts: on the nearest road within SNAP_CELLS of `cell`,
## a junction or road end before any other point, as Cities: Skylines snaps;
## else on a guide (see guide_start); else `cell` itself.
func snap_start(cell: Vector2i) -> Vector2i:
	return _snap_onto(cell, Grid.NONE, guide_start(cell).point)


## Where a drag from `from` towards `to` ends: on the nearest road within
## SNAP_CELLS of `to` snapped straight or to 45° that a road from `from`
## reaches, a junction or road end first; otherwise `to` snapped. Measured
## from the snapped end, not the mouse, so a release off to the side of the
## line still joins the road the line meets. Roads `from` is on don't count,
## so a drag never snaps back along its own road. With no road that close,
## it ends on a guide (see guide_end).
func snap_end(from: Vector2i, to: Vector2i) -> Vector2i:
	return _snap_onto(snap(from, to), from, guide_end(from, to).point)


## The guides a drag can line up with, as Cities: Skylines draws them: from
## each road end that no road carries on straight from, the road's line run
## on GUIDE_CELLS. Each is {"at": the end, "dir": its step outward}.
func guides() -> Array[Dictionary]:
	var out := {}  # node -> the steps outward of its segments
	for id: int in segments:
		var a := grid_point(segments[id].a)
		var b := grid_point(segments[id].b)
		out.get_or_add(a, []).append((b - a).sign())
		out.get_or_add(b, []).append((a - b).sign())
	var found: Array[Dictionary] = []
	for at: Vector2i in out:
		for step: Vector2i in out[at]:
			if -step not in out[at]:
				found.append({"at": at, "dir": -step})
	return found


## Whether `point` lies on `guide`, past its end and within GUIDE_CELLS.
static func on_guide(guide: Dictionary, point: Vector2i) -> bool:
	var t := length(guide.at, point)
	return t >= 1 and t <= GUIDE_CELLS and guide.at + guide.dir * t == point


## Where a drag from `from` towards `to`, snapped straight or to 45°, meets a
## guide within SNAP_CELLS of its snapped end, nearest first: {"point", "guides":
## the guides there}; the snapped end and no guides when none is that close.
## Guides from `from` itself don't count.
func guide_end(from: Vector2i, to: Vector2i) -> Dictionary:
	var end := snap(from, to)
	var best := {"point": end, "guides": []}
	var step := (end - from).sign()
	var run := length(from, end)
	var near := SNAP_CELLS + 1
	var all := guides().filter(func(g: Dictionary) -> bool: return g.at != from)
	for s in range(maxi(1, run - SNAP_CELLS), run + SNAP_CELLS + 1):
		var point := from + step * s
		var on := all.filter(func(g: Dictionary) -> bool: return on_guide(g, point))
		if step != Vector2i.ZERO and not on.is_empty() and absi(s - run) < near:
			best = {"point": point, "guides": on}
			near = absi(s - run)
	return best


## Where a drag starting near `cell` lines up with guides within SNAP_CELLS:
## where two cross before any other point, then the nearest; {"point",
## "guides"} as guide_end, `cell` and no guides when none is that close.
func guide_start(cell: Vector2i) -> Dictionary:
	var best := {"point": cell, "guides": []}
	var best_score := INF
	var all := guides()
	for dx in range(-SNAP_CELLS, SNAP_CELLS + 1):
		for dy in range(-SNAP_CELLS, SNAP_CELLS + 1):
			var point := cell + Vector2i(dx, dy)
			var on := all.filter(func(g: Dictionary) -> bool: return on_guide(g, point))
			var score := Vector2(dx, dy).length() - (SNAP_CELLS * 2 if on.size() > 1 else 0)
			if not on.is_empty() and score < best_score:
				best = {"point": point, "guides": on}
				best_score = score
	return best


## Whether a drag from `from` (NONE for a start) at `cell` would snap onto a road.
func snaps(cell: Vector2i, from := Grid.NONE) -> bool:
	return _snap_onto(cell if from == Grid.NONE else snap(from, cell), from, Grid.NONE) != Grid.NONE


## The road cell nearest `near` within SNAP_CELLS, nodes first, reachable
## from `from` unless that is NONE; else `otherwise`.
## shortcut: scans every road cell each call, fine for hundreds of segments; index cells by chunk if drawing slows on big ports.
func _snap_onto(near: Vector2i, from: Vector2i, otherwise: Vector2i) -> Vector2i:
	var best := otherwise
	var best_score := INF
	for id: int in segments:
		var road := points(id)
		if from in road:
			continue
		var ends := [road[0], road[-1]]
		for cell in road:
			var d := maxi(absi(cell.x - near.x), absi(cell.y - near.y))
			if d > SNAP_CELLS or (from != Grid.NONE and snap(from, cell) != cell):
				continue
			var score := Vector2(cell - near).length() - (SNAP_CELLS * 2 if cell in ends else 0)
			if score < best_score:
				best = cell
				best_score = score
	for anchor in anchors:
		var cell := Vector2i(anchor)
		var d := maxi(absi(cell.x - near.x), absi(cell.y - near.y))
		if cell == from or d > SNAP_CELLS or (from != Grid.NONE and snap(from, cell) != cell):
			continue
		var score := Vector2(cell - near).length() - SNAP_CELLS * 2
		if score < best_score:
			best = cell
			best_score = score
	return best


## The cells a train runs through from cell `from` to cell `to` along the
## track, both ends included and in order. Fewest cells first; [] when no
## track joins them.
func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var start := _on_line(Vector2(from) + Vector2(0.5, 0.5))
	var goal := _on_line(Vector2(to) + Vector2(0.5, 0.5))
	if start.is_empty() or goal.is_empty():
		return [] as Array[Vector2i]
	# Each state: a piece run one way, arriving at its far end. Search by cells run.
	var best := {}  # [segment, forward] -> distance run to its far end
	var came := {}  # [segment, forward] -> the state before, or [] for the first
	var open: Array = []  # [distance, segment, forward]
	for forward: bool in [true, false]:
		var along := curve(start[0])
		var run: float = along.length - start[1] if forward else start[1]
		best[[start[0], forward]] = run
		came[[start[0], forward]] = []
		open.append([run, start[0], forward])
	var found := []
	while not open.is_empty():
		open.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		var at: Array = open.pop_front()
		var state := [at[1], at[2]]
		if at[0] > best[state] + 0.001:
			continue
		if at[1] == goal[0] and (state == [start[0], at[2]] and (goal[1] - start[1]) * (1.0 if at[2] else -1.0) >= 0.0 or state != [start[0], at[2]]):
			found = state
			break
		var road: Dictionary = segments[at[1]]
		var node: int = road.b if at[2] else road.a
		for next: int in segments:
			for forward: bool in [true, false]:
				var next_road: Dictionary = segments[next]
				if (next_road.a if forward else next_road.b) != node or (next == at[1] and forward != at[2]):
					continue
				var run: float = at[0] + curve(next).length
				if run < best.get([next, forward], INF) - 0.001:
					best[[next, forward]] = run
					came[[next, forward]] = state
					open.append([run, next, forward])
	if found.is_empty():
		return [] as Array[Vector2i]
	# Back from the goal's piece to the start's, then the cells along each.
	var chain := [found]
	while not came[chain[0]].is_empty():
		chain.push_front(came[chain[0]])
	var cells: Array[Vector2i] = []
	for k in chain.size():
		var piece: int = chain[k][0]
		var forward: bool = chain[k][1]
		var along := curve(piece)
		var from_d: float = start[1] if k == 0 else (0.0 if forward else along.length)
		var to_d: float = goal[1] if k == chain.size() - 1 else (along.length if forward else 0.0)
		var steps := maxi(1, ceili(absf(to_d - from_d) / 0.25))
		for n in steps + 1:
			var cell := Vector2i(along.point_at(lerpf(from_d, to_d, float(n) / steps)).floor())
			if cells.is_empty() or cells[-1] != cell:
				cells.append(cell)
	return cells


## [the track piece through `point`, how far along it], within half a cell; [] when none.
func _on_line(point: Vector2) -> Array:
	for id: int in segments:
		var along := curve(id)
		var d := along.nearest(point)
		if along.point_at(d).distance_to(point) < 0.5:
			return [id, d]
	return []


## Moves node `change.node` to `change.to` (the straight roads at it stay
## straight, curves keep their control points), or road `change.segment`'s
## control point to `change.control`. Returns the roads it reshapes.
func move(change: Dictionary) -> Array[int]:
	var moved: Array[int] = []
	if change.has("node"):
		var straight := {}
		for id: int in segments:
			var road: Dictionary = segments[id]
			if change.node in [road.a, road.b]:
				moved.append(id)
				straight[id] = road.control.is_equal_approx((nodes[road.a] + nodes[road.b]) / 2.0)
		nodes[change.node] = change.to
		for id in moved:
			if straight[id]:
				segments[id].control = (nodes[segments[id].a] + nodes[segments[id].b]) / 2.0
	else:
		segments[change.segment].control = change.control
		moved.append(change.segment)
	version += 1
	return moved


## Puts the net back as `d` (to_dict) has it, in place, for those holding it.
func restore(d: Dictionary) -> void:
	nodes = d.nodes.duplicate()
	segments = d.segments.duplicate(true)
	_next_node = d.next_node
	_next_segment = d.next_segment
	version += 1


func to_dict() -> Dictionary:
	return {"nodes": nodes.duplicate(), "segments": segments.duplicate(true), "next_node": _next_node, "next_segment": _next_segment}


static func from_dict(d: Dictionary, road_types: Dictionary, junction_rules: Dictionary) -> RoadNet:
	var net := RoadNet.new(road_types, junction_rules)
	net.nodes = d.nodes.duplicate()
	net.segments = d.segments.duplicate(true)
	net._next_node = d.next_node
	net._next_segment = d.next_segment
	return net


## How many segments end at `node`: 2 on a bend, 3 at a T, 4 at a crossing.
func degree(node: int) -> int:
	return segments.values().filter(func(s: Dictionary) -> bool: return s.a == node or s.b == node).size()


## The grid points (or cells, for odd-width types) `segment`'s line runs
## through, from its a end to its b end.
func points(segment: int) -> Array[Vector2i]:
	return line(grid_point(segments[segment].a), grid_point(segments[segment].b))


## The cells just right of `segment`'s line from its a end to its b end: the
## row areas beside it measure from. For odd-width types, the line's cells.
func cells(segment: int) -> Array[Vector2i]:
	var a := grid_point(segments[segment].a)
	var b := grid_point(segments[segment].b)
	return _row(a, b, types[segments[segment].type], 0)


## `segment`'s lanes from left to right across its drawn direction, each
## {"cells": in driving order, "forward": true if it runs from a to b}.
func lanes(segment: int) -> Array[Dictionary]:
	return _lanes(grid_point(segments[segment].a), grid_point(segments[segment].b), types[segments[segment].type])


## The ground (see ground) a road of `type` from `from` to `to`, curving
## through `control` (INF: straight), would stand on.
func footprint(from: Vector2, to: Vector2, type: String, control := Vector2.INF) -> Array[Vector2i]:
	var along := RoadCurve.straight(from, to) if control == Vector2.INF else RoadCurve.new(from, control, to)
	var found: Array[Vector2i] = []
	found.assign(_ground_of(along, _shape_of(along, types[type])).keys())
	return found


## Lanes left to right across the way from `a` to `b`: the first `backward`
## run from b to a, the rest from a to b. They lie evenly either side of the
## line, lane k (0-based) in the row k - lanes / 2 to its right, so drawn
## either way a road covers the same cells.
static func _lanes(a: Vector2i, b: Vector2i, road: Dictionary) -> Array[Dictionary]:
	var width: int = road.forward + road.backward
	var found: Array[Dictionary] = []
	for k in width:
		var forward: bool = k >= road.backward
		var cells := _row(a, b, road, k - width / 2)
		if not forward:
			cells.reverse()
		found.append({"cells": cells, "forward": forward})
	return found


## The cells from `a` to `b` in row `row` right of the line (negative: left).
## Rows sit half a cell either side of a line along grid lines, so one
## between points a and b has a cell per step; a line through cell middles
## has its rows a whole cell apart and covers both end cells. A 45° line
## through grid points also runs through cell middles, so its even rows
## can't sit evenly either side: they step straight across, half a cell
## south of the line, whichever way it was drawn.
static func _row(a: Vector2i, b: Vector2i, road: Dictionary, row: int) -> Array[Vector2i]:
	var d := (b - a).sign()
	var across := right_of(b - a)
	var found: Array[Vector2i] = []
	if (road.forward + road.backward) % 2 == 1:
		for cell in line(a, b):
			found.append(cell + across * row)
		return found
	for t in length(a, b):
		var middle := Vector2(a) + Vector2(d) * (t + 0.5) + Vector2(across) * (row + 0.5)
		found.append(Vector2i(middle.floor()))
	return found


## One cell to the right of travel along `d`. On a 45° road that is a step
## straight across, so neighbouring lanes touch with no gap row between them.
static func right_of(d: Vector2i) -> Vector2i:
	var step := d.sign()
	if step.x == 0 or step.y == 0:
		return Vector2i(-step.y, step.x)
	return Vector2i(0, step.x)


## The cells from `from` to `to` inclusive, along a straight or 45° line.
static func line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var d := to - from
	var step := d.sign()
	var found: Array[Vector2i] = []
	for i in maxi(absi(d.x), absi(d.y)) + 1:
		found.append(from + step * i)
	return found


## Node `node`'s grid point (or cell, for odd-width types).
# shortcut: nodes sit on the grid until roads meet at any angle (M10 12c); what counts cells reads this until 12b gives roads shapes.
func grid_point(node: int) -> Vector2i:
	assert(nodes[node] == nodes[node].round(), "node %d is on the grid" % node)
	return Vector2i(nodes[node])
