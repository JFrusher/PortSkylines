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

## Blocks are kept up to date tile by tile as the map changes, so a change
## costs the size of the blocks it touches, not of the whole yard.
var _anchor_of := {}  # yard tile -> its block's anchor
var _blocks := {}  # anchor -> the block's tiles, in no set order
var _in_order := {}  # anchors whose tile list is in map order
var _anchors: Array[Vector2i] = []  # in map order; rebuilt when empty
var _anchors_known := false


func _init(port_map: PortMap, game_rules: Dictionary) -> void:
	map = port_map
	rules = game_rules
	map.tile_changed.connect(_on_tile_changed)
	for cell in map.cells_of(PortMap.Tile.YARD):
		_add_tile(cell)


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
	return _anchor_of.get(cell, PortMap.NONE)


## The tiles of the block holding `cell`, in map order.
func block(cell: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var block_anchor: Vector2i = _anchor_of.get(cell, PortMap.NONE)
	if block_anchor == PortMap.NONE:
		return found
	if not _in_order.has(block_anchor):
		_blocks[block_anchor].sort_custom(_before)
		_in_order[block_anchor] = true
	found.assign(_blocks[block_anchor])
	return found


## Every block's anchor, in map order.
func anchors() -> Array[Vector2i]:
	if not _anchors_known:
		_anchors.assign(_blocks.keys())
		_anchors.sort_custom(_before)
		_anchors_known = true
	return _anchors.duplicate()


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


func _on_tile_changed(cell: Vector2i, was: int, now: int) -> void:
	if was == PortMap.Tile.YARD:
		_remove_tile(cell)
	if now == PortMap.Tile.YARD:
		_add_tile(cell)


## Joins `cell` to the blocks beside it; the merged block's anchor is its first tile.
func _add_tile(cell: Vector2i) -> void:
	var joined: Array[Vector2i] = []
	for side: Vector2i in PortMap.SIDES:
		var next: Vector2i = _anchor_of.get(cell + side, PortMap.NONE)
		if next != PortMap.NONE and next not in joined:
			joined.append(next)
	var merged := cell
	for other in joined:
		if _before(other, merged):
			merged = other
	var tiles: Array = _blocks.get(merged, [])
	for other in joined:
		if other == merged:
			continue
		for tile: Vector2i in _blocks[other]:
			_anchor_of[tile] = merged
			tiles.append(tile)
		_blocks.erase(other)
		_in_order.erase(other)
	tiles.append(cell)
	_anchor_of[cell] = merged
	_blocks[merged] = tiles
	_in_order.erase(merged)
	_anchors_known = false


## Takes `cell` out of its block and splits what is left into its connected parts.
func _remove_tile(cell: Vector2i) -> void:
	var old: Vector2i = _anchor_of[cell]
	var rest: Array = _blocks[old]
	_blocks.erase(old)
	_in_order.erase(old)
	for tile: Vector2i in rest:
		_anchor_of.erase(tile)
	rest.erase(cell)
	rest.sort_custom(_before)
	# Flooding from each unclaimed tile in map order makes that tile its part's anchor.
	for start: Vector2i in rest:
		if start in _anchor_of:
			continue
		var tiles: Array = [start]
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
	_anchors_known = false


## Map order: by row, then by column.
static func _before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
