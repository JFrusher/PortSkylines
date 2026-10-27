class_name RoadNet
extends RefCounted
## The roads the player draws: nodes on the 4 m grid joined by straight
## segments at 0°, 45° or 90°. Corners are drawn as arcs by the view; in the
## sim a road is the cells its lanes cover.
##
## A road's lanes lie evenly either side of its line, as in Cities: Skylines,
## so which way it was drawn never moves it. Every road type has an even
## number of lanes, so its line runs along grid lines, between cells: a node
## is a grid point, the corner where four cells meet, and point (x, y) is the
## top-left corner of cell (x, y). Rail track has one lane, so its line runs
## through cell middles and a node is a cell. A net's types are all one or
## the other.

## Node id -> its grid point (even-width types) or cell (odd-width).
var nodes := {}
## Segment id -> {"a": node id, "b": node id, "type": a key of road_types}.
var segments := {}
## The data's road types: lanes each way, whether lorries may use them, costs.
var types: Dictionary
## Bumped on every change, so the lane graph knows to rebuild.
var version := 0
var _next_node := 1
var _next_segment := 1
## How near, in cells, a drawn road's ends must come to a road to snap onto it.
const SNAP_CELLS := 3
## Cells a drag snaps onto as onto a road's end, though no road is there yet:
## where the highway meets the site.
var anchors: Array[Vector2i] = []
var _next_cells := {}  # cell -> cells a step on along a segment, for path()
var _next_for := -1


func _init(road_types: Dictionary) -> void:
	types = road_types
	var parities := {}
	for type: Dictionary in types.values():
		parities[(type.forward + type.backward) % 2] = true
	assert(parities.size() <= 1, "a net's road types are all even-width or all odd-width")


## Adds a straight road of `type` from `from` to `to`. Its forward lanes run
## from `from` to `to` on the drawn line and to its right; backward lanes lie
## to its left. Where it meets or crosses another road, both split at a shared
## node, so junctions form by themselves. Returns "" or why it can't be built.
func add(from: Vector2i, to: Vector2i, type: String) -> String:
	var found: Variant = _meets(from, to, type)
	if found is String:
		return found
	var meets: Dictionary = found
	for cell: Vector2i in meets:
		_split(meets[cell], cell)
	var stops: Array[Vector2i] = [from]
	for cell: Vector2i in line(from, to).slice(1, -1):
		if cell in meets:
			stops.append(cell)
	stops.append(to)
	for i in stops.size() - 1:
		segments[_next_segment] = {"a": _node_at(stops[i]), "b": _node_at(stops[i + 1]), "type": type}
		_next_segment += 1
	version += 1
	return ""


## Why `add` would refuse this road, or "": as though `skip` weren't built,
## so a segment can be checked as another type in its own place.
func add_error(from: Vector2i, to: Vector2i, type: String, skip := 0) -> String:
	var found: Variant = _meets(from, to, type, skip)
	return found if found is String else ""


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


## The segment whose lanes cover `cell`, or 0.
func segment_at(cell: Vector2i) -> int:
	for id: int in segments:
		for lane in lanes(id):
			if cell in lane.cells:
				return id
	return 0


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


## Where a road drag starts: on the nearest road within SNAP_CELLS of `cell`,
## a junction or road end before any other point, as Cities: Skylines snaps;
## `cell` itself when no road is that close.
func snap_start(cell: Vector2i) -> Vector2i:
	return _snap_onto(cell, Grid.NONE, cell)


## Where a drag from `from` towards `to` ends: on the nearest road within
## SNAP_CELLS of `to` snapped straight or to 45° that a road from `from`
## reaches, a junction or road end first; otherwise `to` snapped. Measured
## from the snapped end, not the mouse, so a release off to the side of the
## line still joins the road the line meets. Roads `from` is on don't count,
## so a drag never snaps back along its own road.
func snap_end(from: Vector2i, to: Vector2i) -> Vector2i:
	return _snap_onto(snap(from, to), from, snap(from, to))


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
	for cell in anchors:
		var d := maxi(absi(cell.x - near.x), absi(cell.y - near.y))
		if cell == from or d > SNAP_CELLS or (from != Grid.NONE and snap(from, cell) != cell):
			continue
		var score := Vector2(cell - near).length() - SNAP_CELLS * 2
		if score < best_score:
			best = cell
			best_score = score
	return best


## The cells from `from` to `to` along the segments, both ends included,
## fewest cells first; [] when no segments join them.
func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if _next_for != version:
		_next_for = version
		_next_cells.clear()
		for id: int in segments:
			var run := points(id)
			for i in run.size() - 1:
				_next_cells[run[i]] = _next_cells.get(run[i], []) + [run[i + 1]]
				_next_cells[run[i + 1]] = _next_cells.get(run[i + 1], []) + [run[i]]
	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size() and to not in came:
		var cell := queue[head]
		head += 1
		for next: Vector2i in _next_cells.get(cell, []):
			if next not in came:
				came[next] = cell
				queue.append(next)
	var found: Array[Vector2i] = []
	if to not in came or from not in _next_cells:
		return found
	var at := to
	while at != from:
		found.push_front(at)
		at = came[at]
	found.push_front(from)
	return found


func to_dict() -> Dictionary:
	return {"nodes": nodes.duplicate(), "segments": segments.duplicate(true), "next_node": _next_node, "next_segment": _next_segment}


static func from_dict(d: Dictionary, road_types: Dictionary) -> RoadNet:
	var net := RoadNet.new(road_types)
	net.nodes = d.nodes.duplicate()
	net.segments = d.segments.duplicate(true)
	net._next_node = d.next_node
	net._next_segment = d.next_segment
	return net


## Where a road from `from` to `to` meets the roads already built, as cell ->
## the segment it splits; or why it can't be built. Segment `skip` counts as
## not built.
func _meets(from: Vector2i, to: Vector2i, type: String, skip := 0) -> Variant:
	if type not in types:
		return "Unknown road type \"%s\"" % type
	var d := to - from
	if d == Vector2i.ZERO:
		return "A road needs a length"
	if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
		return "Roads run straight or at 45°"
	var drawn := line(from, to)
	var on_drawn := {}
	for cell in drawn:
		on_drawn[cell] = true
	var meets := {}
	for id: int in segments:
		if id == skip:
			continue
		var shared := points(id).filter(func(c: Vector2i) -> bool: return c in on_drawn)
		if shared.size() > 1:
			return "A road already runs here"
		if shared.size() == 1:
			meets[shared[0]] = id
		elif _crosses_between_cells(drawn, id):
			return "Roads must cross at a grid point, not between two"
	# Lanes may overlap only where roads meet, within a road's width of it; a
	# cell further where either road runs at 45°, as its lanes sit half a cell
	# off its line.
	var width: int = types[type].forward + types[type].backward
	var mine := footprint(from, to, type)
	for id: int in segments:
		if id == skip:
			continue
		var road: Dictionary = types[segments[id].type]
		var theirs_d: Vector2i = nodes[segments[id].b] - nodes[segments[id].a]
		var reach := maxi(width, road.forward + road.backward) + (1 if d.x * d.y != 0 or theirs_d.x * theirs_d.y != 0 else 0)
		var theirs := {}
		for lane in lanes(id):
			for cell: Vector2i in lane.cells:
				theirs[cell] = true
		for cell in mine:
			if cell in theirs and not meets.keys().any(func(m: Vector2i) -> bool: return maxi(absi(m.x - cell.x), absi(m.y - cell.y)) < reach):
				return "A road already runs here"
	return meets


## How many segments end at `node`: 2 on a bend, 3 at a T, 4 at a crossing.
func degree(node: int) -> int:
	return segments.values().filter(func(s: Dictionary) -> bool: return s.a == node or s.b == node).size()


## Whether a 45° step of `drawn` passes between two cells of `segment` that
## are themselves a 45° step across it, so the roads cross with no cell in common.
func _crosses_between_cells(drawn: Array[Vector2i], segment: int) -> bool:
	var other := {}
	for cell in points(segment):
		other[cell] = true
	for i in drawn.size() - 1:
		var p := drawn[i]
		var q := drawn[i + 1]
		if p.x != q.x and p.y != q.y and Vector2i(p.x, q.y) in other and Vector2i(q.x, p.y) in other:
			return true
	return false


## Splits `segment` at `cell` unless it already ends there: it keeps its a
## end, and a new segment of the same type runs on from `cell` to the b end.
func _split(segment: int, cell: Vector2i) -> void:
	var road: Dictionary = segments[segment]
	if nodes[road.a] == cell or nodes[road.b] == cell:
		return
	var middle := _node_at(cell)
	segments[_next_segment] = {"a": middle, "b": road.b, "type": road.type}
	_next_segment += 1
	road.b = middle


## The grid points (or cells, for odd-width types) `segment`'s line runs
## through, from its a end to its b end.
func points(segment: int) -> Array[Vector2i]:
	return line(nodes[segments[segment].a], nodes[segments[segment].b])


## The cells just right of `segment`'s line from its a end to its b end: the
## row areas beside it measure from. For odd-width types, the line's cells.
func cells(segment: int) -> Array[Vector2i]:
	var a: Vector2i = nodes[segments[segment].a]
	var b: Vector2i = nodes[segments[segment].b]
	return _row(a, b, types[segments[segment].type], 0)


## `segment`'s lanes from left to right across its drawn direction, each
## {"cells": in driving order, "forward": true if it runs from a to b}.
func lanes(segment: int) -> Array[Dictionary]:
	return _lanes(nodes[segments[segment].a], nodes[segments[segment].b], types[segments[segment].type])


## Every lane cell a road of `type` from `from` to `to` would cover.
func footprint(from: Vector2i, to: Vector2i, type: String) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for lane in _lanes(from, to, types[type]):
		found.append_array(lane.cells)
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


func _node_at(cell: Vector2i) -> int:
	for id: int in nodes:
		if nodes[id] == cell:
			return id
	nodes[_next_node] = cell
	_next_node += 1
	return _next_node - 1
