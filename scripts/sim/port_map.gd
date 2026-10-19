class_name PortMap
extends RefCounted
## The tile grid and what may be built where. Knows nothing about money,
## ships or rendering.

## Values are stored in saves: add new kinds at the end.
enum Tile { LAND, WATER, ROAD, QUAY, YARD, GATE }

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
## Tile indices per kind, kept sorted so cells_of() returns map order, the
## same order a full scan gives, without scanning.
var _index := {}
## Routes already found, keyed by their two road ends; cleared on any change.
var _route_cache := {}


func _init(map_size: Vector2i, sea: int) -> void:
	size = map_size
	sea_width = sea
	_tiles.resize(size.x * size.y)
	for i in _tiles.size():
		_tiles[i] = Tile.WATER if i % size.x < sea_width else Tile.LAND
	_rebuild_index()
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
	var i := cell.x + cell.y * size.x
	var old: PackedInt32Array = _index[_tiles[i]]
	old.remove_at(old.bsearch(i))
	var new: PackedInt32Array = _index[kind]
	new.insert(new.bsearch(i), i)
	_tiles[i] = kind
	_roads.set_point_solid(cell, not is_road(kind))
	_route_cache.clear()
	version += 1


## The first side of `cell` holding `kind`, or NONE.
func neighbor(cell: Vector2i, kind: int) -> Vector2i:
	for side: Vector2i in SIDES:
		if tile(cell + side) == kind:
			return cell + side
	return NONE


## Straight runs of quay tiles with water along one side: the places a ship can
## lie. Each is {"cells": quay tiles in order along the run, "side": the step
## from a quay tile to the water}.
func berths() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen := {}
	for cell in cells_of(Tile.QUAY):
		var water := neighbor(cell, Tile.WATER)
		if cell in seen or water == NONE:
			continue
		var side := water - cell
		var along := Vector2i(absi(side.y), absi(side.x))
		var start := cell
		while _berth_continues(start - along, side):
			start -= along
		var cells: Array[Vector2i] = []
		var at := start
		while _berth_continues(at, side):
			cells.append(at)
			seen[at] = true
			at += along
		found.append({"cells": cells, "side": side})
	return found


func _berth_continues(cell: Vector2i, side: Vector2i) -> bool:
	return tile(cell) == Tile.QUAY and tile(cell + side) == Tile.WATER


## Tiles vehicles drive on: roads, and gates, which lorries must also stop at.
static func is_road(kind: int) -> bool:
	return kind == Tile.ROAD or kind == Tile.GATE


## The road a building is entered from: itself if it is a road or gate, else an adjacent road.
func access_road(cell: Vector2i) -> Vector2i:
	# shortcut: takes the first adjacent road even if a better one exists, fine until buildings get set entrances.
	if is_road(tile(cell)):
		return cell
	for side: Vector2i in SIDES:
		if is_road(tile(cell + side)):
			return cell + side
	return NONE


## Road route between two cells' access roads; empty when there is none.
func route(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var a := access_road(from)
	var b := access_road(to)
	if a == NONE or b == NONE:
		return []
	var key := Vector4i(a.x, a.y, b.x, b.y)
	if key not in _route_cache:
		_route_cache[key] = _roads.get_id_path(a, b)
	var path: Array[Vector2i] = _route_cache[key]
	return path.duplicate()


## A road route from road tile `from` to `to`'s access road that does not pass
## through `blocked`; empty when there is none.
func route_avoiding(from: Vector2i, to: Vector2i, blocked: Vector2i) -> Array[Vector2i]:
	var b := access_road(to)
	if b == NONE or from == blocked or b == blocked:
		return []
	var was_solid := _roads.is_point_solid(blocked)
	_roads.set_point_solid(blocked, true)
	var path := _roads.get_id_path(from, b)
	_roads.set_point_solid(blocked, was_solid)
	return path


func cells_of(kind: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for i: int in _index[kind]:
		found.append(Vector2i(i % size.x, int(i / float(size.x))))
	return found


func _rebuild_index() -> void:
	_index = {}
	for kind: int in Tile.values():
		_index[kind] = PackedInt32Array()
	for i in _tiles.size():
		_index[_tiles[i]].append(i)


func to_dict() -> Dictionary:
	return {"size": size, "sea_width": sea_width, "entry": entry, "version": version, "tiles": _tiles.duplicate()}


static func from_dict(d: Dictionary) -> PortMap:
	var map := PortMap.new(d.size, d.sea_width)
	map.entry = d.entry
	map.version = d.version
	map._tiles = d.tiles.duplicate()
	map._rebuild_index()
	map._roads.fill_solid_region(map._roads.region)
	for i in map._tiles.size():
		if is_road(map._tiles[i]):
			map._roads.set_point_solid(Vector2i(i % map.size.x, int(i / float(map.size.x))), false)
	return map
