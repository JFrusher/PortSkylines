class_name SaveFile
extends RefCounted
## A save is the bytes "PSKY" then {"version", "sim"} written with store_var,
## with objects refused both ways, so a save file can never carry code. The
## magic bytes let junk be refused before Godot tries to decode it. Raising
## VERSION means adding a step to _migrate() and committing
## tests/fixtures/save_v<N>.bin.

const VERSION := 7
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
		if not _valid_v1(data.sim):
			return {}
		data = _v1_to_v2(data)
	if data.version == 2:
		data = _v2_to_v3(data)
	if data.version == 3:
		data = _v3_to_v4(data)
	if data.version == 4:
		data = _v4_to_v5(data)
	if data.version == 5:
		data = _v5_to_v6(data)
	if data.version == 6:
		data = _v6_to_v7(data)
	return data


## v7 (M5) gives each area the player's rules, starting as a new area does.
static func _v6_to_v7(data: Dictionary) -> Dictionary:
	var starting := {"yard_block": {"role": "import", "gear": "reach_stacker", "lines": []}, "quay_apron": {"lines": []}}
	for area: Dictionary in data.sim.areas.list.values():
		area.settings = starting.get(area.type, {}).duplicate(true)
	data.version = 7
	return data


## v6 (M5) adds the areas dragged along roads; older ports have none.
static func _v5_to_v6(data: Dictionary) -> Dictionary:
	data.sim.areas = {"list": {}, "next_id": 1}
	data.version = 6
	return data


## v5 (M5) adds the roads drawn on the 4 m grid; older ports have none.
static func _v4_to_v5(data: Dictionary) -> Dictionary:
	if not data.get("sim") is Dictionary:
		return {}
	data.sim.roads = {"nodes": {}, "segments": {}, "next_node": 1, "next_segment": 1}
	data.version = 5
	return data


## v4 (M4) records each box's line, for its livery. Older boxes belong to no
## line and are drawn plain.
static func _v3_to_v4(data: Dictionary) -> Dictionary:
	if not (data.get("sim") is Dictionary and data.sim.get("boxes") is Dictionary and data.sim.boxes.values().all(func(b: Variant) -> bool: return b is Dictionary)):
		return {}
	for box: Dictionary in data.sim.boxes.values():
		box.line = ""
	data.version = 4
	return data


## v3 (M3) moved cash into the ledger, which also records upkeep, and ships
## into services agreed with shipping lines. Ships in port finish their call
## for the first line, due a day after the save; no services are agreed yet.
## Boxes become 20 ft dry boxes, and those in the yard start storage now.
## The channel starts at the new data's depth.
static func _v2_to_v3(data: Dictionary) -> Dictionary:
	if not (_has_fields(data.sim, {"money": TYPE_INT, "ticks": TYPE_INT, "ships": TYPE_ARRAY, "boxes": TYPE_DICTIONARY, "yard": TYPE_DICTIONARY, "events": TYPE_ARRAY, "map": TYPE_DICTIONARY, "delivered": TYPE_INT})
			and data.sim.map.get("size") is Vector2i
			and data.sim.ships.all(func(s: Variant) -> bool: return s is Dictionary)
			and data.sim.boxes.values().all(func(b: Variant) -> bool: return b is Dictionary)
			and data.sim.yard.get("stacks") is Dictionary
			and data.sim.yard.stacks.values().all(func(stack: Variant) -> bool: return stack is Array)):
		return {}
	data.sim.ledger = {"cash": data.sim.money, "opened": data.sim.money, "today": {}, "days": []}
	data.sim.erase("money")
	data.sim.erase("upkeep_paid")
	var rules := Content.base()
	data.sim.contracts = Contracts.new(rules).to_dict()
	data.sim.finance = Finance.new(rules).to_dict()
	# v2 maps had no land to buy: the port owns every tile its map covers.
	var land := {}
	var size: Vector2i = data.sim.map.size
	for x in ceili(size.x / float(rules.land.cells)):
		for y in ceili(size.y / float(rules.land.cells)):
			land[Vector2i(x, y)] = true
	data.sim.land = land
	data.sim.channel_depth = rules.channel.start_depth
	data.sim.crane_orders = []
	# Boxes through the gate stand in for TEU across the quay, so a v2 port
	# keeps roughly the progress it had.
	data.sim.teu_handled = data.sim.delivered
	data.sim.year = {"calls": 0, "berth_hours": 0.0, "moves": 0, "turns": 0, "turn_minutes": 0.0}
	data.sim.scoreboard = []
	data.sim.creative = false
	for ship: Dictionary in data.sim.ships:
		ship.line = rules.lines.keys()[0]
		ship.due = data.sim.ticks * SimClock.CALENDAR_MINUTES_PER_TICK + SimClock.MINUTES_PER_DAY
	data.sim.erase("until_ship")
	var now: float = data.sim.ticks * SimClock.CALENDAR_MINUTES_PER_TICK
	var in_yard := {}
	for stack: Variant in data.sim.yard.stacks.values():
		for id: Variant in stack:
			in_yard[id] = true
	for id: Variant in data.sim.boxes:
		data.sim.boxes[id].merge({"teu": 1, "reefer": false, "in": now if in_yard.has(id) else -1.0})
	data.sim.dwell_times = []
	data.sim.storage = {"free_days": rules.storage.free_days, "fee": rules.storage.fee}
	data.sim.events.append({"minute": data.sim.ticks * SimClock.CALENDAR_MINUTES_PER_TICK, "text": "Saved game updated: ships now come from contracts with shipping lines; accept their offers"})
	data.version = 3
	return data


## The v1 fields _v1_to_v2 reads. v1 yard tiles held at most 6 boxes.
static func _valid_v1(sim: Dictionary) -> bool:
	if not _has_fields(sim, {"stacked": TYPE_DICTIONARY, "delivered": TYPE_INT}):
		return false
	for tile: Variant in sim.stacked:
		var count: Variant = sim.stacked[tile]
		if not (tile is Vector2i and count is int and count >= 0 and count <= 6):
			return false
	return true


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
		"map": TYPE_DICTIONARY, "roads": TYPE_DICTIONARY, "areas": TYPE_DICTIONARY, "ticks": TYPE_INT, "rng_seed": TYPE_INT,
		"rng_state": TYPE_INT, "ledger": TYPE_DICTIONARY, "delivered": TYPE_INT,
		"events": TYPE_ARRAY, "ship_log": TYPE_ARRAY,
		"delivered_yesterday": TYPE_INT, "delivered_at_midnight": TYPE_INT,
		"ships": TYPE_ARRAY, "cranes": TYPE_ARRAY, "vehicles": TYPE_ARRAY,
		"yard": TYPE_DICTIONARY, "boxes": TYPE_DICTIONARY, "tractors": TYPE_INT,
		"gave_up": TYPE_INT, "turn_times": TYPE_ARRAY, "claimed": TYPE_DICTIONARY,
		"contracts": TYPE_DICTIONARY, "finance": TYPE_DICTIONARY, "creative": TYPE_BOOL, "land": TYPE_DICTIONARY, "channel_depth": TYPE_FLOAT, "crane_orders": TYPE_ARRAY, "teu_handled": TYPE_INT, "year": TYPE_DICTIONARY, "scoreboard": TYPE_ARRAY, "dwell_times": TYPE_ARRAY, "storage": TYPE_DICTIONARY, "until_lorry": TYPE_FLOAT, "until_export": TYPE_FLOAT,
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
	if not _has_fields(data.ledger, {
		"cash": TYPE_INT, "opened": TYPE_INT, "today": TYPE_DICTIONARY, "days": TYPE_ARRAY,
	}):
		return false
	if not _has_fields(data.storage, {"free_days": TYPE_INT, "fee": TYPE_INT}):
		return false
	if not _has_fields(data.year, {"calls": TYPE_INT, "berth_hours": TYPE_FLOAT, "moves": TYPE_INT, "turns": TYPE_INT, "turn_minutes": TYPE_FLOAT}):
		return false
	if not _has_fields(data.finance, {"loans": TYPE_ARRAY, "days_negative": TYPE_INT, "blocked_until": TYPE_FLOAT}):
		return false
	if not _has_fields(data.contracts, {
		"reputation": TYPE_DICTIONARY, "services": TYPE_ARRAY, "offers": TYPE_ARRAY, "next_id": TYPE_INT,
	}):
		return false
	if not _has_fields(data.yard, {
		"stacks": TYPE_DICTIONARY, "reserved": TYPE_DICTIONARY, "role": TYPE_DICTIONARY,
		"gear": TYPE_DICTIONARY, "busy": TYPE_DICTIONARY,
	}):
		return false
	for ship: Variant in data.ships:
		if not ship is Dictionary or not _has_fields(ship, {
			"kind": TYPE_STRING, "line": TYPE_STRING, "due": TYPE_FLOAT, "cells": TYPE_ARRAY,
			"side": TYPE_VECTOR2I, "boxes": TYPE_INT, "exports": TYPE_INT, "state": TYPE_INT,
			"sail": TYPE_FLOAT, "prev_sail": TYPE_FLOAT, "moves": TYPE_INT, "berthed": TYPE_FLOAT,
		}) or not _all_cells(ship.cells, ship.state == PortSim.Ship.State.ANCHORED):
			return false
	for tile: Variant in data.land:
		if not (tile is Vector2i and data.land[tile] is bool):
			return false
	for order: Variant in data.crane_orders:
		if not order is Dictionary or not _has_fields(order, {"cell": TYPE_VECTOR2I, "due": TYPE_FLOAT}):
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
	for id: Variant in data.claimed:
		if not (id is int and data.claimed[id] is bool and data.claimed[id]):
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
