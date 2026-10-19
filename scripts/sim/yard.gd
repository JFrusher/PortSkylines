class_name Yard
extends RefCounted
## The container yard: the boxes stacked on each yard tile, what each block of
## yard tiles is for and which gear works it, and how many of a block's
## machines are busy. A block is a connected group of yard tiles; its anchor
## is its first tile in map order.

var map: PortMap
var rules: Dictionary
## Box ids stacked on each yard tile.
var stacks := {}
## Boxes a vehicle on its way has promised to each tile.
var reserved := {}
## Per-tile settings, set a whole block at a time: "import" or "export", and a
## key of rules.yard_gear. Tiles without one use the defaults.
var role := {}
var gear := {}
## Machines at work in each block, by anchor.
var busy := {}

var _blocks_version := -1
var _anchor_of := {}
var _blocks := {}


func _init(port_map: PortMap, game_rules: Dictionary) -> void:
	map = port_map
	rules = game_rules


func role_of(cell: Vector2i) -> String:
	return role.get(cell, "import")


func gear_of(cell: Vector2i) -> String:
	return gear.get(cell, "reach_stacker")


func count(cell: Vector2i) -> int:
	return stacks.get(cell, []).size()


func capacity(cell: Vector2i) -> int:
	return rules.yard_gear[gear_of(cell)].capacity


func space(cell: Vector2i) -> int:
	return capacity(cell) - count(cell) - reserved.get(cell, 0)


func anchor(cell: Vector2i) -> Vector2i:
	_refresh_blocks()
	return _anchor_of.get(cell, PortMap.NONE)


func block(cell: Vector2i) -> Array[Vector2i]:
	_refresh_blocks()
	var found: Array[Vector2i] = []
	found.assign(_blocks.get(_anchor_of.get(cell), []))
	return found


func anchors() -> Array[Vector2i]:
	_refresh_blocks()
	var found: Array[Vector2i] = []
	found.assign(_blocks.keys())
	return found


## The block's way in: its first tile with a road beside it, or NONE.
## Vehicles drive here; the block's machines reach every tile from it.
func entrance(cell: Vector2i) -> Vector2i:
	for tile in block(cell):
		if map.access_road(tile) != PortMap.NONE:
			return tile
	return PortMap.NONE


## Machines a block has: one per tiles_per_machine tiles of its gear, at least one.
func machines(block_anchor: Vector2i) -> int:
	var spec: Dictionary = rules.yard_gear[gear_of(block_anchor)]
	return ceili(block(block_anchor).size() / float(spec.tiles_per_machine))


func machine_free(block_anchor: Vector2i) -> bool:
	return busy.get(block_anchor, 0) < machines(block_anchor)


func handling_minutes(cell: Vector2i) -> float:
	return rules.yard_gear[gear_of(cell)].handling_minutes


## The tile in the block with the most room, or NONE when it is full.
func roomiest(block_anchor: Vector2i) -> Vector2i:
	var best := PortMap.NONE
	for cell in block(block_anchor):
		if space(cell) > 0 and (best == PortMap.NONE or space(cell) > space(best)):
			best = cell
	return best


## Why the block at `cell` can't take `settings` ("role" and/or "gear"), or "".
func settings_error(cell: Vector2i, settings: Dictionary) -> String:
	if map.tile(cell) != PortMap.Tile.YARD:
		return "That is not a yard"
	if settings.has("role") and settings.role not in ["import", "export"]:
		return "Unknown yard role: %s" % settings.role
	if settings.has("gear"):
		if not rules.yard_gear.has(settings.gear):
			return "Unknown yard gear: %s" % settings.gear
		var new_capacity: int = rules.yard_gear[settings.gear].capacity
		for tile in block(cell):
			if count(tile) + reserved.get(tile, 0) > new_capacity:
				return "Too many boxes here for %s" % settings.gear.replace("_", " ")
	return ""


## Price of switching the block at `cell` to `gear_key`.
func gear_cost(cell: Vector2i, gear_key: String) -> int:
	if gear_of(cell) == gear_key:
		return 0
	return rules.yard_gear[gear_key].cost_per_tile * block(cell).size()


func apply_settings(cell: Vector2i, settings: Dictionary) -> void:
	for tile in block(cell):
		if settings.has("role"):
			role[tile] = settings.role
		if settings.has("gear"):
			gear[tile] = settings.gear


func add(cell: Vector2i, box: int) -> void:
	if not stacks.has(cell):
		stacks[cell] = []
	stacks[cell].append(box)


func take(cell: Vector2i, box: int) -> void:
	stacks[cell].erase(box)
	if stacks[cell].is_empty():
		stacks.erase(cell)


func reserve(cell: Vector2i, amount: int) -> void:
	reserved[cell] = reserved.get(cell, 0) + amount
	if reserved[cell] == 0:
		reserved.erase(cell)


func forget_tile(cell: Vector2i) -> void:
	role.erase(cell)
	gear.erase(cell)


func to_dict() -> Dictionary:
	return {"stacks": stacks.duplicate(true), "reserved": reserved.duplicate(), "role": role.duplicate(), "gear": gear.duplicate(), "busy": busy.duplicate()}


static func from_dict(d: Dictionary, port_map: PortMap, game_rules: Dictionary) -> Yard:
	var yard := Yard.new(port_map, game_rules)
	yard.stacks = d.stacks.duplicate(true)
	yard.reserved = d.reserved.duplicate()
	yard.role = d.role.duplicate()
	yard.gear = d.gear.duplicate()
	yard.busy = d.busy.duplicate()
	return yard


## Rebuilds the blocks by flood fill when the map has changed.
func _refresh_blocks() -> void:
	if _blocks_version == map.version:
		return
	_blocks_version = map.version
	_anchor_of = {}
	_blocks = {}
	for start in map.cells_of(PortMap.Tile.YARD):
		if start in _anchor_of:
			continue
		var tiles: Array[Vector2i] = [start]
		_anchor_of[start] = start
		var i := 0
		while i < tiles.size():
			for side: Vector2i in PortMap.SIDES:
				var next: Vector2i = tiles[i] + side
				if map.tile(next) == PortMap.Tile.YARD and next not in _anchor_of:
					_anchor_of[next] = start
					tiles.append(next)
			i += 1
		_blocks[start] = tiles
