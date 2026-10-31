class_name ShipLanes
extends RefCounted
## The ship lanes the player draws on the water: segments between grid
## points, straight or at 45° like roads, meeting only at their ends. A
## segment covers half_width cells either side of its line, all of it water.
## Its depth is the shallowest water along its line plus what has been
## dredged there. Ships route along lanes deep enough for their draft, from
## a lane end on the site's edge (the open sea) to their berth.

## Lane type -> {"name", "half_width", "cost_per_cell", "upkeep_per_cell"},
## from rules.water.lanes.
var types: Dictionary
## Node id -> grid point.
var nodes := {}
## Segment id -> {"a", "b": node ids, "type", "dredged": metres}.
var segments := {}
## Bumped by every change, so routes are found again.
var version := 0
var _next_node := 1
var _next_segment := 1


func _init(lane_types: Dictionary) -> void:
	types = lane_types


## The cells along `segment`'s line, from a to b.
func cells(segment: int) -> Array[Vector2i]:
	return RoadNet.line(nodes[segments[segment].a], nodes[segments[segment].b])


## The cells a lane of `type` from `from` to `to` covers: its line and
## half_width cells either side, across the line.
func footprint(from: Vector2i, to: Vector2i, type: String) -> Array[Vector2i]:
	var step := (to - from).sign()
	var across := Vector2i(-step.y, step.x)
	var half: int = types[type].half_width
	var found: Array[Vector2i] = []
	for cell in RoadNet.line(from, to):
		for k in range(-half, half + 1):
			found.append(cell + across * k)
			# A 45° line's cells touch only at corners; fill the gaps beside them.
			if step.x != 0 and step.y != 0:
				found.append(cell + across * k + Vector2i(step.x, 0))
	return found


## Why a lane of `type` can't run from `from` to `to`, or "": `is_water`
## says whether a cell is open water.
func add_error(from: Vector2i, to: Vector2i, type: String, is_water: Callable) -> String:
	if type not in types:
		return "Unknown lane type \"%s\"" % type
	var d := to - from
	if d == Vector2i.ZERO:
		return "A lane needs a length"
	if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
		return "Lanes run straight or at 45°"
	if not footprint(from, to, type).all(is_water):
		return "A lane needs open water all along it, %d m wide" % Grid.metres(types[type].half_width * 2 + 1)
	var line := RoadNet.line(from, to)
	for segment: int in segments:
		var other := cells(segment)
		for cell in line:
			if cell in other and cell not in [from, to]:
				return "Lanes meet only at their ends"
	return ""


## Adds a lane of `type` from `from` to `to`, joining nodes it ends on and
## splitting a lane its end lands on part-way. Returns "" or why not.
func add(from: Vector2i, to: Vector2i, type: String, is_water: Callable) -> String:
	var err := add_error(from, to, type, is_water)
	if err:
		return err
	var a := _node_at(from)
	var b := _node_at(to)
	segments[_next_segment] = {"a": a, "b": b, "type": type, "dredged": 0.0}
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
			var cost: float = best[here] + RoadNet.length(nodes[here], nodes[next])
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
		var old: Dictionary = segments[through]
		segments[through] = {"a": old.a, "b": node, "type": old.type, "dredged": old.dredged}
		segments[_next_segment] = {"a": node, "b": old.b, "type": old.type, "dredged": old.dredged}
		_next_segment += 1
	return node
