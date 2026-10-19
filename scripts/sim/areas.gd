class_name Areas
extends RefCounted
## The areas the player drags along road edges: a yard block, quay apron,
## gate or depot covers the cells beside one side of a road segment, from one
## cell along it to another, reaching back `depth` cells from the road's edge.
## An area never covers a road, another area, the sea or ground off the site.

## Area id -> {"type": a key of area_types, "segment": road segment id,
## "side": 1 for the segment's right, -1 for its left, "from" and "to": cell
## indices along the segment, from <= to}.
var list := {}
var types: Dictionary
var _roads: RoadNet
var _size: Vector2i
var _sea: int
var _next_id := 1


func _init(area_types: Dictionary, roads: RoadNet, site: Dictionary) -> void:
	types = area_types
	_roads = roads
	_size = Grid.size(site)
	_sea = Grid.cells(site.sea_width)


## Adds an area; returns "" or why it can't be built.
func add(type: String, segment: int, side: int, from: int, to: int) -> String:
	var err := add_error(type, segment, side, from, to)
	if err == "":
		list[_next_id] = {"type": type, "segment": segment, "side": side, "from": from, "to": to}
		_next_id += 1
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


## The cells `id` covers.
func cells(id: int) -> Array[Vector2i]:
	var area: Dictionary = list[id]
	return cells_of(area.type, area.segment, area.side, area.from, area.to)


## The area covering `cell`, or 0.
func area_at(cell: Vector2i) -> int:
	for id: int in list:
		if cell in cells(id):
			return id
	return 0


## The cells an area of `type` would cover beside `segment`: rows parallel to
## the road, starting just past its outermost lane on `side`.
func cells_of(type: String, segment: int, side: int, from: int, to: int) -> Array[Vector2i]:
	var road: Dictionary = _roads.types[_roads.segments[segment].type]
	var along := _roads.cells(segment)
	var a: Vector2i = _roads.nodes[_roads.segments[segment].a]
	var b: Vector2i = _roads.nodes[_roads.segments[segment].b]
	var across := RoadNet.right_of(b - a) * side
	# Lanes reach `forward` cells to the right of the drawn line (counting it) and `backward` to the left.
	var edge: int = road.forward if side == 1 else road.backward + 1
	var found: Array[Vector2i] = []
	for i in range(from, to + 1):
		for d: int in types[type].depth:
			found.append(along[i] + across * (edge + d))
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
	var a: Vector2i = _roads.nodes[_roads.segments[segment].a]
	var b: Vector2i = _roads.nodes[_roads.segments[segment].b]
	var outward := RoadNet.right_of(b - a) * side
	return cells.all(func(c: Vector2i) -> bool: return c + outward in cells or (c + outward).x < _sea)
