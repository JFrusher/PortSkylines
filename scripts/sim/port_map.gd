class_name PortMap
extends RefCounted
## The tile grid and what may be built where. Knows nothing about money,
## ships or rendering.

enum Tile { LAND, WATER, ROAD, QUAY, YARD }

const NONE := Vector2i(-1, -1)
const SIDES := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var size: Vector2i
var sea_width: int
## Where lorries come from: a highway off the east edge of the map.
var entry: Vector2i
## Bumped on every change so views know to redraw.
var version := 0

var _tiles := PackedByteArray()
var _roads := AStarGrid2D.new()


func _init(map_size := Vector2i(64, 48), sea := 12) -> void:
	size = map_size
	sea_width = sea
	_tiles.resize(size.x * size.y)
	for i in _tiles.size():
		_tiles[i] = Tile.WATER if i % size.x < sea_width else Tile.LAND
	_roads.region = Rect2i(Vector2i.ZERO, size)
	_roads.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_roads.update()
	_roads.fill_solid_region(_roads.region)
	entry = Vector2i(size.x - 1, int(size.y / 2.0))
	place(Tile.ROAD, entry)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## The tile at `cell`, or -1 off the map.
func tile(cell: Vector2i) -> int:
	return _tiles[cell.x + cell.y * size.x] if in_bounds(cell) else -1


## Why `kind` can't be built on `cell`, or "" when it can.
func build_error(kind: int, cell: Vector2i) -> String:
	var here := tile(cell)
	if here == -1:
		return "Off the map"
	if here == Tile.WATER:
		return "Can't build on water"
	if here != Tile.LAND:
		return "Bulldoze first"
	if kind == Tile.QUAY and neighbor(cell, Tile.WATER) == NONE:
		return "A quay must face the water"
	return ""


func bulldoze_error(cell: Vector2i) -> String:
	if cell == entry:
		return "That's the highway"
	if tile(cell) in [-1, Tile.LAND, Tile.WATER]:
		return "Nothing to bulldoze"
	return ""


## Sets a tile without checking; callers check build_error/bulldoze_error first.
func place(kind: int, cell: Vector2i) -> void:
	_tiles[cell.x + cell.y * size.x] = kind
	_roads.set_point_solid(cell, kind != Tile.ROAD)
	version += 1


## The first side of `cell` holding `kind`, or NONE.
func neighbor(cell: Vector2i, kind: int) -> Vector2i:
	for side: Vector2i in SIDES:
		if tile(cell + side) == kind:
			return cell + side
	return NONE


## The road a building is entered from: itself if it is a road, else an adjacent one.
func access_road(cell: Vector2i) -> Vector2i:
	# shortcut: takes the first adjacent road even if a better one exists, fine until gates own access in M2.
	return cell if tile(cell) == Tile.ROAD else neighbor(cell, Tile.ROAD)


## Road route between two cells' access roads; empty when there is none.
func route(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var a := access_road(from)
	var b := access_road(to)
	if a == NONE or b == NONE:
		return []
	return _roads.get_id_path(a, b)


func cells_of(kind: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for i in _tiles.size():
		if _tiles[i] == kind:
			found.append(Vector2i(i % size.x, int(i / float(size.x))))
	return found


func to_dict() -> Dictionary:
	return {"size": size, "sea_width": sea_width, "entry": entry, "version": version, "tiles": _tiles.duplicate()}


static func from_dict(d: Dictionary) -> PortMap:
	var map := PortMap.new(d.size, d.sea_width)
	map.entry = d.entry
	map.version = d.version
	map._tiles = d.tiles.duplicate()
	map._roads.fill_solid_region(map._roads.region)
	for i in map._tiles.size():
		if map._tiles[i] == Tile.ROAD:
			map._roads.set_point_solid(Vector2i(i % map.size.x, int(i / float(map.size.x))), false)
	return map
