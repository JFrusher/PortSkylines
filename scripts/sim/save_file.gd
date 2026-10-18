class_name SaveFile
extends RefCounted
## A save is the bytes "PSKY" then {"version", "sim"} written with store_var,
## with objects refused both ways, so a save file can never carry code. The
## magic bytes let junk be refused before Godot tries to decode it. Raising
## VERSION means adding a step to _migrate() and committing
## tests/fixtures/save_v<N>.bin.

const VERSION := 2
const MAGIC := "PSKY"


static func save(path: String, sim: PortSim) -> String:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Can't write %s: %s" % [path, error_string(FileAccess.get_open_error())]
	# Match store_var's length-prefixed format, with objects refused.
	var payload := var_to_bytes({"version": VERSION, "sim": sim.to_dict()})
	var bytes := MAGIC.to_ascii_buffer()
	bytes.resize(MAGIC.length() + 4)
	bytes.encode_u32(MAGIC.length(), payload.size())
	bytes.append_array(payload)
	var written := file.store_buffer(bytes)
	file.flush()
	var err := file.get_error()
	file.close()
	# close() returns no status. Read back after closing to catch buffered write
	# failures too, before the existing save can be replaced.
	if not written or err != OK or file.get_error() != OK or FileAccess.get_file_as_bytes(temporary) != bytes:
		DirAccess.remove_absolute(temporary)
		return "Can't write %s" % path
	err = DirAccess.rename_absolute(temporary, path)
	if err != OK:
		DirAccess.remove_absolute(temporary)
		return "Can't write %s: %s" % [path, error_string(err)]
	return ""


## {"sim": PortSim} on success, {"error": String} saying why not otherwise.
static func load_from(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Can't open %s: %s" % [path, error_string(FileAccess.get_open_error())]}
	if file.get_buffer(MAGIC.length()).get_string_from_ascii() != MAGIC:
		return {"error": "%s is not a Port Skylines save" % path}
	var data: Variant = file.get_var(false)
	if not (data is Dictionary and data.get("version") is int and data.get("sim") is Dictionary):
		return {"error": "%s is not a Port Skylines save" % path}
	if data.version > VERSION:
		return {"error": "%s is from a newer version of the game (save v%d, game v%d)" % [path, data.version, VERSION]}
	if data.version < 1:
		return {"error": "%s has an invalid save version %d" % [path, data.version]}
	data = _migrate(data)
	if not _valid_sim(data.get("sim")):
		return {"error": "%s is not a Port Skylines save" % path}
	return {"sim": PortSim.from_dict(data.sim)}


## Brings an older save up to VERSION one step at a time.
static func _migrate(data: Dictionary) -> Dictionary:
	if data.version == 1:
		data = _v1_to_v2(data)
	return data


## v2 (M2) gave ships classes and berths. Ships in a v1 save were mid-call in
## the old format, so they are dropped; the map, money and yards carry over.
static func _v1_to_v2(data: Dictionary) -> Dictionary:
	data.sim.ships = []
	data.sim.cranes = []
	# Lorries move to the v2 traffic model; lorries on the road are dropped
	# and any boxes they had claimed are free again.
	data.sim.erase("lorries")
	data.sim.vehicles = []
	data.sim.claimed = {}
	data.sim.next_vehicle = 1
	data.sim.gave_up = 0
	# Yard tiles held box counts; they become import boxes ready to collect.
	var stacks := {}
	var boxes := {}
	var next := 1
	for tile: Vector2i in data.sim.stacked:
		for i in int(data.sim.stacked[tile]):
			boxes[next] = {"kind": "import", "due": 0.0}
			if not stacks.has(tile):
				stacks[tile] = []
			stacks[tile].append(next)
			next += 1
	data.sim.erase("stacked")
	data.sim.yard = {"stacks": stacks, "reserved": {}, "role": {}, "gear": {}, "busy": {}}
	data.sim.boxes = boxes
	data.sim.next_box = next
	data.sim.tractors = 0
	data.sim.until_export = 0.0
	data.sim.turn_times = []
	data.sim.erase("status")
	data.sim.events = [{"minute": 0.0, "text": "Saved game updated: ships that were in port have sailed"}]
	data.sim.upkeep_paid = 0
	data.sim.ship_log = []
	data.sim.delivered_yesterday = 0
	data.sim.delivered_at_midnight = data.sim.delivered
	data.version = 2
	return data


## Check the entire payload before any typed deserialiser sees it.
# shortcut: entries inside yard, boxes, events and ship_log are not checked,
# only that they are dictionaries/arrays; check them if hand-edited saves matter.
static func _valid_sim(data: Variant) -> bool:
	if not data is Dictionary or not _has_fields(data, {
		"map": TYPE_DICTIONARY, "ticks": TYPE_INT, "rng_seed": TYPE_INT,
		"rng_state": TYPE_INT, "money": TYPE_INT, "delivered": TYPE_INT,
		"events": TYPE_ARRAY, "upkeep_paid": TYPE_INT, "ship_log": TYPE_ARRAY,
		"delivered_yesterday": TYPE_INT, "delivered_at_midnight": TYPE_INT,
		"ships": TYPE_ARRAY, "cranes": TYPE_ARRAY, "vehicles": TYPE_ARRAY,
		"yard": TYPE_DICTIONARY, "boxes": TYPE_DICTIONARY, "tractors": TYPE_INT,
		"gave_up": TYPE_INT, "turn_times": TYPE_ARRAY, "claimed": TYPE_DICTIONARY,
		"until_ship": TYPE_FLOAT, "until_lorry": TYPE_FLOAT, "until_export": TYPE_FLOAT,
		"next_vehicle": TYPE_INT, "next_box": TYPE_INT,
	}):
		return false
	var map: Dictionary = data.map
	if not _has_fields(map, {
		"size": TYPE_VECTOR2I, "sea_width": TYPE_INT, "entry": TYPE_VECTOR2I,
		"version": TYPE_INT, "tiles": TYPE_PACKED_BYTE_ARRAY,
	}):
		return false
	if map.size.x <= 0 or map.size.y <= 0 or map.tiles.size() != map.size.x * map.size.y:
		return false
	for tile: int in map.tiles:
		if tile not in PortMap.Tile.values():
			return false
	if not _has_fields(data.yard, {
		"stacks": TYPE_DICTIONARY, "reserved": TYPE_DICTIONARY, "role": TYPE_DICTIONARY,
		"gear": TYPE_DICTIONARY, "busy": TYPE_DICTIONARY,
	}):
		return false
	for ship: Variant in data.ships:
		if not ship is Dictionary or not _has_fields(ship, {
			"kind": TYPE_STRING, "cells": TYPE_ARRAY, "side": TYPE_VECTOR2I,
			"boxes": TYPE_INT, "exports": TYPE_INT, "state": TYPE_INT, "sail": TYPE_FLOAT,
			"prev_sail": TYPE_FLOAT, "moves": TYPE_INT, "berthed": TYPE_FLOAT,
		}) or not _all_cells(ship.cells, false):
			return false
	for crane: Variant in data.cranes:
		if not crane is Dictionary or not _has_fields(crane, {
			"cell": TYPE_VECTOR2I, "timer": TYPE_FLOAT, "tractor": TYPE_INT,
		}):
			return false
	for vehicle: Variant in data.vehicles:
		if not vehicle is Dictionary or not _has_fields(vehicle, {
			"id": TYPE_INT, "kind": TYPE_STRING, "path": TYPE_ARRAY, "t": TYPE_FLOAT,
			"prev_t": TYPE_FLOAT, "lane": TYPE_VECTOR3I, "ahead": TYPE_VECTOR3I,
			"waited": TYPE_INT, "replanned": TYPE_BOOL, "state": TYPE_STRING,
			"box": TYPE_INT, "loaded": TYPE_BOOL, "target": TYPE_VECTOR2I,
			"home": TYPE_VECTOR2I, "timer": TYPE_FLOAT, "block": TYPE_VECTOR2I,
			"gate_in": TYPE_FLOAT,
		}) or not _all_cells(vehicle.path, true):
			return false
	for cell: Variant in data.claimed:
		if not cell is Vector2i or not data.claimed[cell] is int:
			return false
	for id: Variant in data.boxes:
		if not id is int or not data.boxes[id] is Dictionary:
			return false
	return true


## True when `cells` holds only Vector2i, and some unless `may_be_empty`.
static func _all_cells(cells: Array, may_be_empty: bool) -> bool:
	if cells.is_empty() and not may_be_empty:
		return false
	return cells.all(func(cell: Variant) -> bool: return cell is Vector2i)


static func _has_fields(data: Dictionary, fields: Dictionary) -> bool:
	for key: String in fields:
		var value: Variant = data.get(key)
		if typeof(value) != fields[key] and not (fields[key] == TYPE_FLOAT and value is int):
			return false
		if fields[key] == TYPE_FLOAT and not is_finite(value):
			return false
	return true
