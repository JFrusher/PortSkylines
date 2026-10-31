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
## the rows from its road to its quay, fixed when it is built.
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


func _init(area_types: Dictionary, roads: RoadNet, site_coast: Coast) -> void:
	types = area_types
	_roads = roads
	coast = site_coast
	_size = coast.size


## Whether `cell` is water now: on the coast's water and not filled in.
func is_water(cell: Vector2i) -> bool:
	return coast.is_water(cell) and cell not in filled


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
	var along := _roads.cells(segment)
	if from < 0 or to >= along.size() or from > to:
		return "Areas are built along a road's edge"
	if to - from + 1 < types[type].min_length:
		return "A %s is at least %d m long" % [types[type].name.to_lower(), Grid.metres(types[type].min_length)]
	var placed := _placed(type, segment, side, from, to)
	if types[type].kind == "quay_apron" and placed.depth > types[type].max_depth:
		return "A quay apron reaches at most %d m from its road to the water" % Grid.metres(types[type].max_depth)
	var cells := _cells(placed)
	var taken := _taken()
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y:
			return "Areas must stay on the site"
		if is_water(cell) and types[type].kind != "quay_apron":
			return "Areas can't be built on water"
		if cell in taken:
			return "Something is already built here"
	if types[type].kind == "quay_apron" and not _on_the_water(placed):
		return "A quay apron's quay must face open water along its whole length"
	return ""


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
		for lane in _roads.lanes(segment):
			for cell: Vector2i in lane.cells:
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
	return _cells(list[id])


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
	if _lanes_for != _roads.version:
		_lanes_for = _roads.version
		_lane_cells.clear()
		for segment: int in _roads.segments:
			for lane in _roads.lanes(segment):
				for cell: Vector2i in lane.cells:
					_lane_cells[cell] = true
	var lanes := _lane_cells
	for cell in RoadNet.line(area.start, area.end):
		if cell - area.out in lanes:
			return ""
	return "No road runs along this %s" % types[area.type].name.to_lower()


## What `id` holds, laid out by AreaLayout for its type.
func layout(id: int) -> Dictionary:
	if _layouts_for != version:
		_layouts_for = version
		_layouts.clear()
	if id not in _layouts:
		var area: Dictionary = list[id]
		match kind_of(area):
			"yard_block":
				_layouts[id] = AreaLayout.yard_block(area, depth_of(area))
			"quay_apron":
				_layouts[id] = AreaLayout.quay_apron(area, depth_of(area))
			"gate":
				_layouts[id] = AreaLayout.gate(area, depth_of(area))
			"parking":
				_layouts[id] = AreaLayout.parking(area)
			_:
				_layouts[id] = {}
	return _layouts[id]


## The area covering `cell`, or 0.
func area_at(cell: Vector2i) -> int:
	for id: int in list:
		if cell in cells(id):
			return id
	return 0


## How many cells along area `id` `cell` lies, or -1 when it is not in it.
func along(id: int, cell: Vector2i) -> int:
	var area: Dictionary = list[id]
	var front := RoadNet.line(area.start, area.end)
	for k in front.size():
		for d in depth_of(area):
			if front[k] + area.out * d == cell:
				return k
	return -1


## The cells an area of `type` would cover beside `segment`: rows parallel to
## the road, starting just past its outermost lane on `side`.
func cells_of(type: String, segment: int, side: int, from: int, to: int) -> Array[Vector2i]:
	return _cells(_placed(type, segment, side, from, to))


## Where a drag starting on `cell` attaches: {"segment", "side", "index"} of
## the road edge an area would grow from, or {} if no road edge is in reach.
func attach(cell: Vector2i, type: String) -> Dictionary:
	for segment: int in _roads.segments:
		var along := _roads.cells(segment)
		for side: int in [1, -1]:
			var front := _placed(type, segment, side, 0, along.size() - 1)
			for d: int in types[type].max_depth:
				for i in along.size():
					if front.start + _step(front) * i + front.out * d == cell:
						return {"segment": segment, "side": side, "index": i}
	return {}


## The index along `segment` nearest to `cell`, for the far end of a drag.
func index_near(segment: int, cell: Vector2i) -> int:
	var along := _roads.cells(segment)
	var best := 0
	for i in along.size():
		if Vector2(along[i]).distance_to(Vector2(cell)) < Vector2(along[best]).distance_to(Vector2(cell)):
			best = i
	return best


func to_dict() -> Dictionary:
	return {"list": list.duplicate(true), "next_id": _next_id, "terminals": terminals.duplicate(true), "next_terminal": _next_terminal, "paint": paint.duplicate(), "filled": filled.duplicate()}


static func from_dict(d: Dictionary, area_types: Dictionary, roads: RoadNet, site_coast: Coast) -> Areas:
	var areas := Areas.new(area_types, roads, site_coast)
	areas.filled = d.filled.duplicate()
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
	var back: Vector2i = area.out * (depth_of(area) - 1)
	var rect := Rect2i(area.start, Vector2i.ONE)
	for corner: Vector2i in [area.end, area.start + back, area.end + back]:
		rect = rect.expand(corner).expand(corner + Vector2i.ONE)
	return rect


func _new_terminal() -> int:
	terminals[_next_terminal] = {"name": "Terminal %d" % _next_terminal, "colour": (_next_terminal - 1) % TERMINAL_COLOURS}
	_next_terminal += 1
	return _next_terminal - 1


## An area's own geometry beside `segment`, from index `from` to `to`.
func _placed(type: String, segment: int, side: int, from: int, to: int) -> Dictionary:
	var road: Dictionary = _roads.types[_roads.segments[segment].type]
	var along := _roads.cells(segment)
	var a: Vector2i = _roads.nodes[_roads.segments[segment].a]
	var b: Vector2i = _roads.nodes[_roads.segments[segment].b]
	var out := RoadNet.right_of(b - a) * side
	# `along` is the row just right of the line; the lanes fill half the road's
	# width each side of it, so the first free row right is that half on, and
	# left one more.
	var half: int = (road.forward + road.backward) / 2
	var edge: int = half if side == 1 else half + 1
	var placed := {"type": type, "start": along[from] + out * edge, "end": along[to] + out * edge, "out": out}
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


static func _step(area: Dictionary) -> Vector2i:
	return (area.end - area.start).sign()


func _cells(area: Dictionary) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for cell in RoadNet.line(area.start, area.end):
		for d in depth_of(area):
			found.append(cell + area.out * d)
	return found


## Cells already taken: every road lane and every area.
func _taken() -> Dictionary:
	var taken := {}
	for id: int in _roads.segments:
		for lane in _roads.lanes(id):
			for cell: Vector2i in lane.cells:
				taken[cell] = true
	for id: int in list:
		for cell in cells(id):
			taken[cell] = true
	return taken


## Whether the row just past an apron's quay is water all along it.
func _on_the_water(placed: Dictionary) -> bool:
	return RoadNet.line(placed.start, placed.end).all(func(c: Vector2i) -> bool: return is_water(c + placed.out * placed.depth))
