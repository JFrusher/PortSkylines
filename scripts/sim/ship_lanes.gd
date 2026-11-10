class_name ShipLanes
extends RefCounted
## The ship lanes the player draws on the water: segments between cells,
## through the cells' middles, straight at any angle or curved (a quadratic
## curve, RoadCurve) no tighter than their type's min_radius_cells, meeting
## only at their ends. A segment covers half_width cells either side of its
## line, all of it water.
## Its depth is the shallowest water along its line plus what has been
## dredged there. Ships route along lanes deep enough for their draft, from
## a lane end on the site's edge (the open sea) to their berth.

## Lane type -> {"name", "min_radius_cells", "half_width", "cost_per_cell",
## "upkeep_per_cell", ...}, from rules.water.lanes.
var types: Dictionary
## Node id -> its cell.
var nodes := {}
## Segment id -> {"a", "b": node ids, "type", "dredged": metres, "control":
## its curve's control point in grid units, at its middle while straight}.
var segments := {}
## Bumped by every change, so routes are found again.
var version := 0
var _next_node := 1
var _next_segment := 1
## Segment id -> [what it is laid from, its line's cells, the cells it covers].
var _laid := {}


func _init(lane_types: Dictionary) -> void:
	types = lane_types


## `segment`'s line as a curve, in grid units.
func curve(segment: int) -> RoadCurve:
	var lane: Dictionary = segments[segment]
	return RoadCurve.new(Vector2(nodes[lane.a]) + Vector2(0.5, 0.5), lane.control, Vector2(nodes[lane.b]) + Vector2(0.5, 0.5))


## The line of a lane from cell `from` to cell `to` through their middles,
## curving through `control` (INF: straight).
static func line_of(from: Vector2i, to: Vector2i, control := Vector2.INF) -> RoadCurve:
	var a := Vector2(from) + Vector2(0.5, 0.5)
	var b := Vector2(to) + Vector2(0.5, 0.5)
	return RoadCurve.straight(a, b) if control == Vector2.INF else RoadCurve.new(a, control, b)


## The cells along `segment`'s line, from a to b.
func cells(segment: int) -> Array[Vector2i]:
	return _laid_of(segment)[1]


## The cells `segment` covers (see footprint).
func area(segment: int) -> Array[Vector2i]:
	return _laid_of(segment)[2]


## [key, line cells, covered cells] of `segment`, laid again only when it changes.
func _laid_of(segment: int) -> Array:
	var lane: Dictionary = segments[segment]
	var key := [nodes[lane.a], lane.control, nodes[lane.b], lane.type]
	if segment not in _laid or _laid[segment][0] != key:
		_laid[segment] = [key, _line_cells(curve(segment)), _band(curve(segment), types[lane.type].half_width)]
	return _laid[segment]


## The cells a lane of `type` from cell `from` to cell `to`, curving through
## `control`, covers: its line and half_width cells either side, across it.
func footprint(from: Vector2i, to: Vector2i, type: String, control := Vector2.INF) -> Array[Vector2i]:
	return _band(line_of(from, to, control), types[type].half_width)


## The cells `line` runs through, in order.
static func _line_cells(line: RoadCurve) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var steps := maxi(1, ceili(line.length / 0.25))
	for n in steps + 1:
		var cell := Vector2i(line.point_at(line.length * n / steps).floor())
		if found.is_empty() or found[-1] != cell:
			found.append(cell)
	return found


## The cells within `half` cells of `line`, square across at its ends: on a
## straight line along the grid, its cells and `half` rows either side.
static func _band(line: RoadCurve, half: int) -> Array[Vector2i]:
	var under := {}
	var steps := maxi(1, ceili(line.length / 0.5))
	for n in steps + 1:
		var d := line.length * n / steps
		var at := line.point_at(d)
		var across := line.right_at(d)
		for k in range(-2 * half, 2 * half + 1):
			under[Vector2i((at + across * (k / 2.0)).floor())] = true
	var found: Array[Vector2i] = []
	found.assign(under.keys())
	return found


## Why a lane of `type` can't run from `from` to `to`, curving through
## `control` (INF: straight), or "": `is_water` says whether a cell is open
## water.
func add_error(from: Vector2i, to: Vector2i, type: String, is_water: Callable, control := Vector2.INF) -> String:
	if type not in types:
		return "Unknown lane type \"%s\"" % type
	if from == to:
		return "A lane needs a length"
	var line := line_of(from, to, control)
	if line.min_radius() < types[type].min_radius_cells:
		return "Too tight a bend: a %s turns no tighter than %d m" % [types[type].name.to_lower(), roundi(types[type].min_radius_cells * Grid.CELL)]
	if not _band(line, types[type].half_width).all(is_water):
		return "A lane needs open water all along it, %d m wide" % Grid.metres(types[type].half_width * 2 + 1)
	var mine := _line_cells(line)
	for segment: int in segments:
		var other := cells(segment)
		for cell in mine:
			if cell in other and cell not in [from, to]:
				return "Lanes meet only at their ends"
	return ""


## Adds a lane of `type` from `from` to `to`, curving through `control`
## (INF: straight), joining nodes it ends on and splitting a lane its end
## lands on part-way. Returns "" or why not.
func add(from: Vector2i, to: Vector2i, type: String, is_water: Callable, control := Vector2.INF) -> String:
	var err := add_error(from, to, type, is_water, control)
	if err:
		return err
	var line := line_of(from, to, control)
	var a := _node_at(from)
	var b := _node_at(to)
	segments[_next_segment] = {"a": a, "b": b, "type": type, "dredged": 0.0, "control": line.c}
	_next_segment += 1
	version += 1
	return ""


## Takes out `segment`, and any node left with no lane.
func remove(segment: int) -> void:
	var gone: Dictionary = segments[segment]
	segments.erase(segment)
	for node: int in [gone.a, gone.b]:
		if not segments.values().any(func(s: Dictionary) -> bool: return node in [s.a, s.b]):
			nodes.erase(node)
	version += 1


## The lane whose line runs through `cell`, or 0.
func segment_at(cell: Vector2i) -> int:
	for segment: int in segments:
		if cell in cells(segment):
			return segment
	return 0


## The segments meeting at `node`.
func at(node: int) -> Array[int]:
	var found: Array[int] = []
	for segment: int in segments:
		if node in [segments[segment].a, segments[segment].b]:
			found.append(segment)
	return found


## `segment`'s depth: the shallowest water along its line on `coast`, plus
## what is dredged there.
func depth(segment: int, coast: Coast) -> float:
	var shallowest := INF
	for cell in cells(segment):
		shallowest = minf(shallowest, coast.depth(cell))
	return shallowest + segments[segment].dredged


## The cheapest way along lanes from any node in `starts` to any node in
## `ends`, through segments `may_use` accepts: node ids, first to last, or []
## when there is none. Ties go to the lower node id, so routes replay.
func route(starts: Array[int], ends: Array[int], may_use: Callable) -> Array[int]:
	var best := {}
	var came := {}
	var todo: Array[int] = []
	for node in starts:
		best[node] = 0.0
		todo.append(node)
	while not todo.is_empty():
		var here := todo[0]
		for node in todo:
			if best[node] < best[here] or (best[node] == best[here] and node < here):
				here = node
		todo.erase(here)
		if here in ends:
			var path: Array[int] = [here]
			while path[0] in came:
				path.push_front(came[path[0]])
			return path
		for segment in at(here):
			if not may_use.call(segment):
				continue
			var next: int = segments[segment].b if segments[segment].a == here else segments[segment].a
			var cost: float = best[here] + curve(segment).length
			if next not in best or cost < best[next]:
				best[next] = cost
				came[next] = here
				if next not in todo:
					todo.append(next)
	return [] as Array[int]


## The segment joining nodes `a` and `b`, or 0.
func between(a: int, b: int) -> int:
	for segment: int in segments:
		var s: Dictionary = segments[segment]
		if (s.a == a and s.b == b) or (s.a == b and s.b == a):
			return segment
	return 0


func to_dict() -> Dictionary:
	return {"nodes": nodes.duplicate(), "segments": segments.duplicate(true), "next_node": _next_node, "next_segment": _next_segment}


static func from_dict(d: Dictionary, lane_types: Dictionary) -> ShipLanes:
	var lanes := ShipLanes.new(lane_types)
	lanes.nodes = d.nodes.duplicate()
	lanes.segments = d.segments.duplicate(true)
	lanes._next_node = d.next_node
	lanes._next_segment = d.next_segment
	return lanes


## The node at `cell`, splitting a lane whose line runs through it, or a new one.
func _node_at(cell: Vector2i) -> int:
	for node: int in nodes:
		if nodes[node] == cell:
			return node
	var node := _next_node
	_next_node += 1
	nodes[node] = cell
	var through := segment_at(cell)
	if through:
		# Each piece keeps its part of the curve, split where it passes nearest the cell's middle.
		var old: Dictionary = segments[through]
		var line := curve(through)
		var t := line.t_at(line.nearest(Vector2(cell) + Vector2(0.5, 0.5)))
		segments[through] = {"a": old.a, "b": node, "type": old.type, "dredged": old.dredged, "control": line.control_between(0.0, t)}
		segments[_next_segment] = {"a": node, "b": old.b, "type": old.type, "dredged": old.dredged, "control": line.control_between(t, 1.0)}
		_next_segment += 1
	return node
