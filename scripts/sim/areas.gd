class_name Areas
extends RefCounted
## The areas the player drags along road edges: a yard block, quay apron,
## gate or depot covers the cells beside one side of a road segment, from one
## cell along it to another, reaching back `depth` cells from the road's edge.
## An area never covers a road, another area, the sea or ground off the site.
## It keeps its own cells once built, so later road edits never move it.

## Area id -> {"type": a key of area_types, "start" and "end": the ends of
## its front row, beside the road, "out": one cell away from the road,
## "settings": the player's rules for it, checked by PortSim.set_area,
## "terminal": the terminal it belongs to}.
var list := {}
## Terminal id -> {"name"}. A terminal is a named group of areas: a new area
## joins the terminal of an area it touches, or starts its own. Roads belong
## to no terminal, so terminals can share them.
var terminals := {}
var types: Dictionary
## Bumped on every change, so the view knows to redraw.
var version := 0
var _roads: RoadNet
var _size: Vector2i
var _sea: int
var _next_id := 1
var _next_terminal := 1
## Every road lane cell, rebuilt when the roads change; layouts by area id,
## rebuilt when the areas change. Both are asked for many times a tick.
var _lane_cells := {}
var _lanes_for := -1
var _layouts := {}
var _layouts_for := -1


func _init(area_types: Dictionary, roads: RoadNet, site: Dictionary) -> void:
	types = area_types
	_roads = roads
	_size = Grid.size(site)
	_sea = Grid.cells(site.sea_width)


## Adds an area with `settings`; returns "" or why it can't be built.
func add(type: String, segment: int, side: int, from: int, to: int, settings := {}) -> String:
	var err := add_error(type, segment, side, from, to)
	if err == "":
		list[_next_id] = _placed(type, segment, side, from, to)
		list[_next_id].settings = settings.duplicate(true)
		var touching := _terminals_touching(_cells(list[_next_id]))
		list[_next_id].terminal = touching.min() if not touching.is_empty() else _new_terminal()
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
	var cells := cells_of(type, segment, side, from, to)
	var taken := _taken()
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y:
			return "Areas must stay on the site"
		if cell.x < _sea:
			return "Areas can't be built on water"
		if cell in taken:
			return "Something is already built here"
	if type == "quay_apron" and not _on_the_water(cells, segment, side):
		return "A quay apron runs along the water's edge"
	return ""


func remove(id: int) -> void:
	list.erase(id)
	_forget_empty_terminals()
	version += 1


## Moves area `id` into `terminal`, or into a new terminal when it is 0.
func set_terminal(id: int, terminal: int) -> String:
	if id not in list:
		return "No area there"
	if terminal != 0 and terminal not in terminals:
		return "No such terminal"
	list[id].terminal = terminal if terminal != 0 else _new_terminal()
	_forget_empty_terminals()
	version += 1
	return ""


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
	var area: Dictionary = list[id]
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
	return {"list": list.duplicate(true), "next_id": _next_id, "terminals": terminals.duplicate(true), "next_terminal": _next_terminal}


static func from_dict(d: Dictionary, area_types: Dictionary, roads: RoadNet, site: Dictionary) -> Areas:
	var areas := Areas.new(area_types, roads, site)
	areas.list = d.list.duplicate(true)
	areas._next_id = d.next_id
	areas.terminals = d.terminals.duplicate(true)
	areas._next_terminal = d.next_terminal
	return areas


## The terminals of areas sharing an edge with any of `cells`.
func _terminals_touching(cells: Array[Vector2i]) -> Array:
	var near := {}
	for cell in cells:
		for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			near[cell + side] = true
	var found := {}
	for id: int in list:
		if list[id].has("terminal") and _cells(list[id]).any(func(c: Vector2i) -> bool: return c in near):
			found[list[id].terminal] = true
	return found.keys()


func _new_terminal() -> int:
	terminals[_next_terminal] = {"name": "Terminal %d" % _next_terminal}
	_next_terminal += 1
	return _next_terminal - 1


func _forget_empty_terminals() -> void:
	for terminal: int in terminals.keys():
		if not list.values().any(func(a: Dictionary) -> bool: return a.terminal == terminal):
			terminals.erase(terminal)


## An area's own geometry beside `segment`, from index `from` to `to`.
func _placed(type: String, segment: int, side: int, from: int, to: int) -> Dictionary:
	var road: Dictionary = _roads.types[_roads.segments[segment].type]
	var along := _roads.cells(segment)
	var a: Vector2i = _roads.nodes[_roads.segments[segment].a]
	var b: Vector2i = _roads.nodes[_roads.segments[segment].b]
	var out := RoadNet.right_of(b - a) * side
	# Lanes reach `forward` cells to the right of the drawn line (counting it) and `backward` to the left.
	var edge: int = road.forward if side == 1 else road.backward + 1
	return {"type": type, "start": along[from] + out * edge, "end": along[to] + out * edge, "out": out}


## What `area` does, from its type: a gate of any size is a "gate".
func kind_of(area: Dictionary) -> String:
	return types[area.type].kind


## How many rows deep `area` is: its type's depth, except that a quay apron
## facing the sea reaches out to the water, up to its type's max_depth, so
## its road needn't be an exact distance from the water.
func depth_of(area: Dictionary) -> int:
	var type: Dictionary = types[area.type]
	if area.type == "quay_apron" and area.out == Vector2i(-1, 0):
		return clampi(area.start.x - _sea + 1, type.depth, type.max_depth)
	return type.depth


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


## Whether the far edge of an apron's cells, away from its road, meets the sea.
func _on_the_water(cells: Array[Vector2i], segment: int, side: int) -> bool:
	var outward: Vector2i = _placed("quay_apron", segment, side, 0, 0).out
	return cells.all(func(c: Vector2i) -> bool: return c + outward in cells or (c + outward).x < _sea)
