class_name Areas
extends RefCounted
## The areas the player drags along road edges: a yard block, quay apron,
## gate or depot covers the cells beside one side of a road segment, from one
## cell along it to another, reaching back `depth` cells from the road's edge.
## An area never covers a road, another area, water or ground off the site,
## except a quay apron, which fills the water behind its straight quay.
## It keeps its own cells once built, so later road edits never move it.

## Area id -> {"type": a key of area_types, "start" and "end": the ends of
## its front row, beside the road, "out": one cell away from the road,
## "settings": the player's rules for it, checked by PortSim.set_area,
## "terminal": the terminal it belongs to}; a quay apron also has "depth",
## the rows from its road to its quay, fixed when it is built. Its shape
## (M10) is laid from "curve" ([a, control, b] in grid units) on "side",
## "columns" cells along it from "from" cells, starting "edge" cells off it.
var list := {}
## Terminal id -> {"name", "colour": an index into TERMINAL_COLOURS}. The
## player paints terminals on the map: each area belongs to the terminal
## holding most of its painted cells, or to none (0), and then it is idle.
## Roads belong to no terminal, so terminals can share them.
var terminals := {}
## Painted cells: cell -> terminal id.
var paint := {}
## Water filled in to make land behind quay walls: cell -> true. It stays
## land when its apron is taken out.
var filled := {}
## Breakwaters: id -> {"from", "to"}, walls two cells thick on the water;
## their cells, kept as they change: cell -> id.
var breakwaters := {}
var _breakwater_cells := {}
var _next_breakwater := 1
## The site's land and water before any of it was filled.
var coast: Coast
## How many cells each terminal has painted, kept as they are painted, so a
## brush stroke needn't count them all again; not saved, counted on load.
var _counts := {}  # terminal -> cells
## How many colours a terminal's colour index runs through.
const TERMINAL_COLOURS := 8
## The most cells a fill paints; more means no road closes the ground in.
const FILL_LIMIT := 20000
var types: Dictionary
## Bumped on every change, so the view knows to redraw.
var version := 0
var _roads: RoadNet
var _size: Vector2i
var _next_id := 1
var _next_terminal := 1
## Every road lane cell, rebuilt when the roads change; layouts by area id,
## rebuilt when the areas change. Both are asked for many times a tick.
var _lane_cells := {}
var _lanes_for := -1
var _idle := {}  # area id -> its idle reason, for the road and area versions in _idle_for
var _gates := {}  # terminal -> its working gates, for the same versions
var _idle_for := Vector2i(-1, -1)
var _layouts := {}
var _layouts_for := -1
## Each area's shape, by what it was laid from: id -> [from, AreaShape].
var _shapes := {}
## Each area's ground (cells), kept like _layouts.
var _cells_of := {}
var _cells_for := -1
## No spot: a vehicle's target or home before it has one.
const NO_SPOT := Vector3i(0, -1, -1)
## Each area's cells' quads by the grid cells their bounds cover: cell ->
## [[area id, quad]], for the version in _quads_for.
var _quads := {}
var _quads_for := -1
var _quads_of := {}  # area id -> [the shape its quads were filed from, the cells they're filed under]
## Each area's cells' middles (centre), kept with _layouts.
var _centres := {}


func _init(area_types: Dictionary, roads: RoadNet, site_coast: Coast) -> void:
	types = area_types
	_roads = roads
	coast = site_coast
	_size = coast.size


## Whether `cell` is open water now: on the coast's water, not filled in
## and no breakwater.
func is_water(cell: Vector2i) -> bool:
	return coast.is_water(cell) and cell not in filled and cell not in _breakwater_cells


## Fills `cells` of water to make land, as behind a quay wall.
func fill(cells: Array[Vector2i]) -> void:
	for cell in cells:
		filled[cell] = true
	version += 1


## The cells of a breakwater from `from` to `to`: its line and the cells
## beside it, two thick, so a 45° wall has no gaps.
static func breakwater_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var step := (to - from).sign()
	var beside := Vector2i(-step.y, step.x) if step.x == 0 or step.y == 0 else Vector2i(step.x, 0)
	var cells: Array[Vector2i] = []
	for cell in RoadNet.line(from, to):
		cells.append(cell)
		cells.append(cell + beside)
	return cells


## Why a breakwater can't run from `from` to `to`, or "".
func breakwater_error(from: Vector2i, to: Vector2i) -> String:
	var d := to - from
	if d == Vector2i.ZERO:
		return "A breakwater needs a length"
	if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
		return "Breakwaters run straight or at 45°"
	if not breakwater_cells(from, to).all(is_water):
		return "A breakwater stands on open water"
	return ""


func add_breakwater(from: Vector2i, to: Vector2i) -> int:
	breakwaters[_next_breakwater] = {"from": from, "to": to}
	for cell in breakwater_cells(from, to):
		_breakwater_cells[cell] = _next_breakwater
	_next_breakwater += 1
	version += 1
	return _next_breakwater - 1


func remove_breakwater(id: int) -> void:
	for cell in breakwater_cells(breakwaters[id].from, breakwaters[id].to):
		_breakwater_cells.erase(cell)
	breakwaters.erase(id)
	version += 1


## The breakwater on `cell`, or 0.
func breakwater_at(cell: Vector2i) -> int:
	return _breakwater_cells.get(cell, 0)


## Adds an area with `settings`; returns "" or why it can't be built.
func add(type: String, segment: int, side: int, from: int, to: int, settings := {}) -> String:
	var err := add_error(type, segment, side, from, to)
	if err == "":
		list[_next_id] = _placed(type, segment, side, from, to)
		list[_next_id].settings = settings.duplicate(true)
		list[_next_id].terminal = _terminal_of(_cells(list[_next_id]))
		for cell in _cells(list[_next_id]):
			if is_water(cell):
				filled[cell] = true
		_next_id += 1
		version += 1
	return err


func add_error(type: String, segment: int, side: int, from: int, to: int) -> String:
	if type not in types:
		return "Unknown area type \"%s\"" % type
	if segment not in _roads.segments or side not in [1, -1]:
		return "Areas are built along a road's edge"
	if from < 0 or to >= _columns(segment) or from > to:
		return "Areas are built along a road's edge"
	if to - from + 1 < types[type].min_length:
		return "A %s is at least %d m long" % [types[type].name.to_lower(), Grid.metres(types[type].min_length)]
	var placed := _placed(type, segment, side, from, to)
	if types[type].kind == "quay_apron" and placed.depth > types[type].max_depth:
		return "A quay apron reaches at most %d m from its road to the water" % Grid.metres(types[type].max_depth)
	for cell in _cells(placed):
		if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y:
			return "Areas must stay on the site"
		if is_water(cell) and types[type].kind != "quay_apron":
			return "Areas can't be built on water"
	# Blocked where its cells' quads overlap a road's lane quads, a breakwater's cells or another area's cells.
	var lanes := _lane_quads()
	var depth: int = placed.depth if types[type].kind == "quay_apron" else types[type].depth
	var curve := RoadCurve.new(placed.curve[0], placed.curve[1], placed.curve[2])
	for cell: Dictionary in AreaShape.along(curve, placed.side, placed.from, placed.columns, placed.edge, depth).cells:
		var quad := PackedVector2Array(cell.corners)
		if area_over(quad) != 0 or _grid_under(quad).any(func(under: Vector2i) -> bool: return (under in _breakwater_cells and overlap(quad, square(under))) or lanes.get(under, []).any(func(lane: PackedVector2Array) -> bool: return overlap(quad, lane))):
			return "Something is already built here"
	if types[type].kind == "quay_apron" and not _on_the_water(placed):
		return "A quay apron's quay must face open water along its whole length"
	return ""


## Lays area `id` again along road `segment`, over the same columns, as
## after the road is moved; "" or why it no longer fits there, when it is
## left as it was.
func refit(id: int, segment: int) -> String:
	var area: Dictionary = list[id]
	var from := int(area.from)
	list.erase(id)
	var err := add_error(area.type, segment, area.side, from, from + area.columns - 1)
	list[id] = area
	if err == "":
		var placed := _placed(area.type, segment, area.side, from, from + area.columns - 1)
		placed.settings = area.settings
		placed.terminal = area.terminal
		list[id] = placed
	version += 1
	return err


func remove(id: int) -> void:
	list.erase(id)
	version += 1


## Paints `cells` as `terminal`: an existing one, -1 for a new one, or 0 to
## erase. Cells off the site are left out. Areas move to the terminal now
## holding most of their cells, and a terminal left with no cells goes.
func paint_cells(cells: Array, terminal: int) -> String:
	if terminal > 0 and terminal not in terminals:
		return "No such terminal"
	if terminal == -1:
		terminal = _new_terminal()
	var touched := Rect2i()
	for cell: Vector2i in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y:
			continue
		var was: int = paint.get(cell, 0)
		if was:
			_counts[was] -= 1
		if terminal == 0:
			paint.erase(cell)
		else:
			paint[cell] = terminal
			_counts[terminal] = _counts.get(terminal, 0) + 1
		touched = Rect2i(cell, Vector2i.ONE) if touched.size == Vector2i.ZERO else touched.expand(cell).expand(cell + Vector2i.ONE)
	_repaint(touched)
	return ""


## The cells a fill from `start` paints: those reached from it in steps along
## and across, stopping at road lanes, the sea and the site's edge; [] when
## `start` is on a road or more than FILL_LIMIT cells are reached.
func fill_cells(start: Vector2i) -> Array[Vector2i]:
	var lanes := {}
	for segment: int in _roads.segments:
		for cell in _roads.ground(segment):
			lanes[cell] = true
	var found: Array[Vector2i] = []
	var seen := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_back()
		if cell in lanes or cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y or is_water(cell):
			continue
		found.append(cell)
		if found.size() > FILL_LIMIT:
			return [] as Array[Vector2i]
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if cell + step not in seen:
				seen[cell + step] = true
				todo.append(cell + step)
	return found


func name_terminal(terminal: int, name: String) -> String:
	if terminal not in terminals:
		return "No such terminal"
	if name.strip_edges() == "":
		return "A terminal needs a name"
	terminals[terminal].name = name.strip_edges()
	version += 1
	return ""


## Moves `terminal`'s colour on to the next.
func colour_terminal(terminal: int) -> String:
	if terminal not in terminals:
		return "No such terminal"
	terminals[terminal].colour = (terminals[terminal].colour + 1) % TERMINAL_COLOURS
	version += 1
	return ""


## `terminal`'s name, or "no terminal" for an area on unpainted ground (0).
func terminal_name(terminal: int) -> String:
	return terminals[terminal].name if terminal else "no terminal"


## Why `terminal` can't take contracts yet, or "": it needs a gate for lorries
## and a quay apron for ships.
func terminal_error(terminal: int) -> String:
	var kinds := list.values().filter(func(a: Dictionary) -> bool: return a.terminal == terminal).map(func(a: Dictionary) -> String: return kind_of(a))
	if "quay_apron" not in kinds:
		return "%s needs a quay apron" % terminals[terminal].name
	if "gate" not in kinds:
		return "%s needs a gate" % terminals[terminal].name
	return ""


## The cells `id` covers.
func cells(id: int) -> Array[Vector2i]:
	if _cells_for != version:
		_cells_for = version
		_cells_of.clear()
	if id not in _cells_of:
		_cells_of[id] = _cells(list[id])
	return _cells_of[id]


## Area `id`'s shape: its own cells, laid along its curve.
func shape(id: int) -> AreaShape:
	var area: Dictionary = list[id]
	# Kept by what it is laid from, so an unchanged area isn't laid out again.
	var from_what := [area.curve, area.side, area.from, area.columns, area.edge, depth_of(area)]
	if id not in _shapes or _shapes[id][0] != from_what:
		_shapes[id] = [from_what, AreaShape.along(curve(id), area.side, area.from, area.columns, area.edge, depth_of(area))]
	return _shapes[id][1]


## The point `k` columns along area `id` and `r` rows out (whole numbers
## are cell (k, r)'s middle), and the way its rows run there, along its curve.
func point(id: int, k: float, r: float) -> Vector2:
	return _point_of(list[id], k, r)


## point() for an area's dictionary, built or not.
static func _point_of(area: Dictionary, k: float, r: float) -> Vector2:
	var along := RoadCurve.new(area.curve[0], area.curve[1], area.curve[2])
	return along.point_at(area.from + k + 0.5) + along.right_at(area.from + k + 0.5) * (area.edge + r + 0.5) * area.side


## The way area `id`'s rows run `k` columns along it (its curve's way).
func heading(id: int, k: float) -> Vector2:
	return curve(id).direction_at(list[id].from + k + 0.5)


## Area `id`'s road curve, along which its cells lie.
func curve(id: int) -> RoadCurve:
	var area: Dictionary = list[id]
	return RoadCurve.new(area.curve[0], area.curve[1], area.curve[2])


## Why area `id` does no work, or "": a road must still run along its front,
## since vehicles reach it from there. The box flow sends nothing to an area
## with a reason.
func idle_reason(id: int) -> String:
	var now := Vector2i(_roads.version, version)
	_keep_for(now)
	if id not in _idle:
		_idle[id] = _idle_reason(id)
	return _idle[id]


## The gates of `terminal` that work: those with a road along their front.
func working_gates(terminal: int) -> Array[int]:
	_keep_for(Vector2i(_roads.version, version))
	if terminal not in _gates:
		var found: Array[int] = []
		for id: int in list:
			if kind_of(list[id]) == "gate" and list[id].terminal == terminal and idle_reason(id) == "":
				found.append(id)
		_gates[terminal] = found
	return _gates[terminal]


## Forgets idle reasons and working gates kept for other road and area versions.
func _keep_for(now: Vector2i) -> void:
	if _idle_for != now:
		_idle_for = now
		_idle.clear()
		_gates.clear()


func _idle_reason(id: int) -> String:
	var area: Dictionary = list[id]
	if area.terminal == 0:
		return "Paint this %s into a terminal on the map (Map, key 6)" % types[area.type].name.to_lower()
	return "" if road_beside(id) else "No road runs along this %s" % types[area.type].name.to_lower()


## Whether a road's lane runs beside any of area `id`'s first row.
func road_beside(id: int) -> bool:
	if _lanes_for != _roads.version:
		_lanes_for = _roads.version
		_lane_cells.clear()
		for segment: int in _roads.segments:
			for cell in _roads.ground(segment):
				_lane_cells[cell] = true
	return range(list[id].columns).any(func(k: int) -> bool: return Vector2i(point(id, k, -1.0).floor()) in _lane_cells)


## What `id` holds, laid out by AreaLayout for its type on its own cells,
## each cell named as a spot: Vector3i(id, k, r).
func layout(id: int) -> Dictionary:
	if _layouts_for != version:
		_layouts_for = version
		_layouts.clear()
		_centres.clear()
	if id not in _layouts:
		var area: Dictionary = list[id]
		var present := {}
		for cell: Dictionary in shape(id).cells:
			present[Vector2i(cell.k, cell.r)] = true
		_layouts[id] = _as_spots(id, AreaLayout.local(kind_of(area), area.columns, depth_of(area), present))
	return _layouts[id]


## `part` (a layout or any part of one) with every local cell Vector2i(k, r)
## named as the spot Vector3i(`id`, k, r).
static func _as_spots(id: int, part: Variant) -> Variant:
	if part is Vector2i:
		return Vector3i(id, part.x, part.y)
	if part is Dictionary:
		var found := {}
		for key: Variant in part:
			found[key] = _as_spots(id, part[key])
		return found
	if part is Array:
		var found := []
		for item: Variant in part:
			found.append(_as_spots(id, item))
		return found
	return part


## Where spot `spot` is: the middle of area spot.x's cell (k, r) =
## (spot.y, spot.z), or, for area 0, of road grid cell (spot.y, spot.z).
func centre(spot: Vector3i) -> Vector2:
	if spot.x == 0:
		return Vector2(spot.y, spot.z) + Vector2(0.5, 0.5)
	if _layouts_for != version:
		layout(spot.x)
	if spot.x not in _centres:
		var found := {}
		for cell: Dictionary in shape(spot.x).cells:
			found[Vector2i(cell.k, cell.r)] = cell.centre
		_centres[spot.x] = found
	return _centres[spot.x][Vector2i(spot.y, spot.z)]


## The area (other than `except`) one of whose cells overlaps `quad` with
## any area, or 0: edges that only touch don't count.
func area_over(quad: PackedVector2Array, except := 0) -> int:
	if _quads_for != version:
		_quads_for = version
		# Only areas gone, new or laid out again are filed afresh.
		for id: int in _quads_of.keys():
			if id not in list or _quads_of[id][0] != shape(id):
				for under: Vector2i in _quads_of[id][1]:
					_quads[under] = _quads[under].filter(func(found: Array) -> bool: return found[0] != id)
				_quads_of.erase(id)
		for id: int in list:
			if id not in _quads_of:
				var filed: Array[Vector2i] = []
				for cell: Dictionary in shape(id).cells:
					var corners := PackedVector2Array(cell.corners)
					for under in _grid_under(corners):
						_quads.get_or_add(under, []).append([id, corners])
						filed.append(under)
				_quads_of[id] = [shape(id), filed]
	for under in _grid_under(quad):
		for found: Array in _quads.get(under, []):
			if found[0] != except and overlap(quad, found[1]):
				return found[0]
	return 0


## Whether quads `a` and `b` overlap with any area, not just at an edge.
static func overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for part: PackedVector2Array in Geometry2D.intersect_polygons(a, b):
		# Measured from its first corner: whole grid coordinates' cross products lose a sliver's area to rounding.
		var twice := 0.0
		for i in range(1, part.size() - 1):
			twice += (part[i] - part[0]).cross(part[i + 1] - part[0])
		if absf(twice) > 0.02:
			return true
	return false


## A grid cell's square.
static func square(cell: Vector2i) -> PackedVector2Array:
	var at := Vector2(cell)
	return PackedVector2Array([at, at + Vector2(1, 0), at + Vector2(1, 1), at + Vector2(0, 1)])


## The grid cells `quad`'s bounds cover.
static func _grid_under(quad: PackedVector2Array) -> Array[Vector2i]:
	var low := quad[0]
	var high := quad[0]
	for corner in quad:
		low = low.min(corner)
		high = high.max(corner)
	var found: Array[Vector2i] = []
	for x in range(floori(low.x), ceili(high.x)):
		for y in range(floori(low.y), ceili(high.y)):
			found.append(Vector2i(x, y))
	return found


## The spot whose middle lies in grid cell `cell`: an area's cell there,
## else the road cell itself.
func spot_in(cell: Vector2i) -> Vector3i:
	var id := area_at(cell)
	if id != 0:
		for found: Dictionary in shape(id).cells:
			if Vector2i(found.centre.floor()) == cell:
				return Vector3i(id, found.k, found.r)
	return Vector3i(0, cell.x, cell.y)


## The area covering `cell`, or 0.
func area_at(cell: Vector2i) -> int:
	for id: int in list:
		if cell in cells(id):
			return id
	return 0


## How many cells along area `id` `cell` lies, or -1 when it is not in it.
func along(id: int, cell: Vector2i) -> int:
	var spot := spot_in(cell)
	return spot.y if spot.x == id else -1


## The cells an area of `type` would cover beside `segment`: rows parallel to
## the road, starting just past its outermost lane on `side`.
func cells_of(type: String, segment: int, side: int, from: int, to: int) -> Array[Vector2i]:
	return _cells(_placed(type, segment, side, from, to))


## Where a drag starting on `cell` attaches: {"segment", "side", "index"} of
## the road edge an area would grow from, or {} if no road edge is in reach.
func attach(cell: Vector2i, type: String) -> Dictionary:
	for segment: int in _roads.segments:
		for side: int in [1, -1]:
			var front := _placed(type, segment, side, 0, _columns(segment) - 1)
			var curve := RoadCurve.new(front.curve[0], front.curve[1], front.curve[2])
			for found: Dictionary in AreaShape.along(curve, side, 0.0, front.columns, front.edge, types[type].max_depth).cells:
				if Vector2i(found.centre.floor()) == cell:
					return {"segment": segment, "side": side, "index": found.k}
	return {}


## The index along `segment` nearest to `cell`, for the far end of a drag.
func index_near(segment: int, cell: Vector2i) -> int:
	return clampi(floori(_roads.curve(segment).nearest(Vector2(cell) + Vector2(0.5, 0.5))), 0, _columns(segment) - 1)


## How many cells along `segment` an area can take: one per whole cell of its curve.
func _columns(segment: int) -> int:
	return floori(_roads.curve(segment).length + 0.001)


func to_dict() -> Dictionary:
	return {"list": list.duplicate(true), "next_id": _next_id, "terminals": terminals.duplicate(true), "next_terminal": _next_terminal, "paint": paint.duplicate(), "filled": filled.duplicate(), "breakwaters": breakwaters.duplicate(true), "next_breakwater": _next_breakwater}


static func from_dict(d: Dictionary, area_types: Dictionary, roads: RoadNet, site_coast: Coast) -> Areas:
	var areas := Areas.new(area_types, roads, site_coast)
	areas.filled = d.filled.duplicate()
	areas._next_breakwater = d.next_breakwater
	for id: int in d.breakwaters:
		areas.breakwaters[id] = d.breakwaters[id].duplicate()
		for cell in breakwater_cells(d.breakwaters[id].from, d.breakwaters[id].to):
			areas._breakwater_cells[cell] = id
	areas.list = d.list.duplicate(true)
	areas._next_id = d.next_id
	areas.terminals = d.terminals.duplicate(true)
	areas._next_terminal = d.next_terminal
	areas.paint = d.paint.duplicate()
	for terminal: int in areas.paint.values():
		areas._counts[terminal] = areas._counts.get(terminal, 0) + 1
	return areas


## The terminal holding most of `cells`, the lowest id on a tie; 0 when none
## of them is painted.
func _terminal_of(cells: Array[Vector2i]) -> int:
	var counts := {}
	for cell in cells:
		if cell in paint:
			counts[paint[cell]] = counts.get(paint[cell], 0) + 1
	var best := 0
	for terminal: int in counts:
		if best == 0 or counts[terminal] > counts[best] or (counts[terminal] == counts[best] and terminal < best):
			best = terminal
	return best


## After painting within `touched`: the areas over it to the terminal now
## holding most of them, and terminals with no painted cell left gone.
func _repaint(touched: Rect2i) -> void:
	for terminal: int in terminals.keys():
		if _counts.get(terminal, 0) == 0:
			terminals.erase(terminal)
			_counts.erase(terminal)
	for id: int in list:
		if _bounds(list[id]).intersects(touched):
			list[id].terminal = _terminal_of(_cells(list[id]))
	version += 1


## The cells `area` spans, from its corners.
func _bounds(area: Dictionary) -> Rect2i:
	var cells := _cells(area)
	var rect := Rect2i(cells[0], Vector2i.ONE)
	for cell in cells:
		rect = rect.expand(cell).expand(cell + Vector2i.ONE)
	return rect


func _new_terminal() -> int:
	terminals[_next_terminal] = {"name": "Terminal %d" % _next_terminal, "colour": (_next_terminal - 1) % TERMINAL_COLOURS}
	_next_terminal += 1
	return _next_terminal - 1


## An area's own geometry beside `segment`, from index `from` to `to`.
func _placed(type: String, segment: int, side: int, from: int, to: int) -> Dictionary:
	var road: Dictionary = _roads.types[_roads.segments[segment].type]
	var curve := _roads.curve(segment)
	# Column k is k cells along the curve; rows start where the road's lanes end.
	var placed := {"type": type, "curve": [curve.a, curve.c, curve.b], "side": side, "from": float(from), "columns": to - from + 1, "edge": (road.forward + road.backward) / 2.0}
	# Its front's first and last grid cells and its way out, for quay aprons and berths, which stay on grid roads until berths turn (M10 step 21).
	placed.start = Vector2i(_point_of(placed, 0.0, 0.0).floor())
	placed.end = Vector2i(_point_of(placed, placed.columns - 1.0, 0.0).floor())
	placed.out = Vector2i((curve.right_at(from + 0.5) * side).round())
	if types[type].kind == "quay_apron":
		placed.depth = _reach(placed)
	return placed


## How many rows a quay apron placed as `placed` takes to reach the water: at
## least its type's depth, out to the row beyond the furthest land along
## it, so its quay is one straight wall and the water behind it is filled.
## More than max_depth when the water is further off than that.
func _reach(placed: Dictionary) -> int:
	var type: Dictionary = types[placed.type]
	var rows: int = type.depth
	for cell in RoadNet.line(placed.start, placed.end):
		var d := 0
		while d <= type.max_depth and not is_water(cell + placed.out * d):
			d += 1
		rows = maxi(rows, d)
	return rows


## What `area` does, from its type: a gate of any size is a "gate".
func kind_of(area: Dictionary) -> String:
	return types[area.type].kind


## How many rows deep `area` is: its type's depth, except that a quay apron
## reaches out to the water (see _reach), so its road needn't be an exact
## distance from the water.
func depth_of(area: Dictionary) -> int:
	return area.depth if kind_of(area) == "quay_apron" else types[area.type].depth


## The ground `area` stands on: the grid cells its own cells' middles lie
## in, column by column, for water, land, paint and upkeep (M10 6d).
func _cells(area: Dictionary) -> Array[Vector2i]:
	var seen := {}
	var found: Array[Vector2i] = []
	var curve := RoadCurve.new(area.curve[0], area.curve[1], area.curve[2])
	for cell: Dictionary in AreaShape.along(curve, area.side, area.from, area.columns, area.edge, depth_of(area)).cells:
		var under := Vector2i(cell.centre.floor())
		if under not in seen:
			seen[under] = true
			found.append(under)
	return found


## Grid cells already taken: every road lane and breakwater (areas are
## checked by their cells' quads, area_over).
## Every road's lane quads by the grid cells their bounds cover: cell -> [quad].
func _lane_quads() -> Dictionary:
	var found := {}
	for id: int in _roads.segments:
		for cell: Dictionary in _roads.shape(id).cells:
			var quad := PackedVector2Array(cell.corners)
			for under in _grid_under(quad):
				found.get_or_add(under, []).append(quad)
	return found


## Whether the row just past an apron's quay is water all along it.
func _on_the_water(placed: Dictionary) -> bool:
	return RoadNet.line(placed.start, placed.end).all(func(c: Vector2i) -> bool: return is_water(c + placed.out * placed.depth))
