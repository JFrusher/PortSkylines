class_name SaveFile
extends RefCounted
## A save is the bytes "PSKY" then {"version", "sim"} written with store_var,
## with objects refused both ways, so a save file can never carry code. The
## magic bytes let junk be refused before Godot tries to decode it. Raising
## VERSION means adding a step to _migrate() and committing
## tests/fixtures/save_v<N>.bin.

const VERSION := 32
## The first save on a map's natural coastline. Older saves were built on a
## straight sea strip that no map keeps, so they are refused, as the
## developer chose for the coastline (and before it for painted terminals).
const FIRST := 26
## Every field Vehicle.from_dict reads.
const VEHICLE_FIELDS := {
	"id": TYPE_INT, "kind": TYPE_STRING, "path": TYPE_ARRAY, "t": TYPE_FLOAT,
	"prev_t": TYPE_FLOAT, "waited": TYPE_INT, "state": TYPE_STRING,
	"box": TYPE_INT, "loaded": TYPE_BOOL, "target": TYPE_VECTOR2I,
	"home": TYPE_VECTOR2I, "timer": TYPE_FLOAT, "gate_in": TYPE_FLOAT, "booked": TYPE_FLOAT,
	"area": TYPE_INT, "slot": TYPE_INT,
}
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
	if data.version < FIRST:
		return {"error": "%s was saved before the natural coastline (save v%d) and can't be loaded; start a new game" % [path, data.version]}
	data = _migrate(data)
	if not _valid_sim(data.get("sim")):
		return {"error": "%s is not a Port Skylines save" % path}
	return {"sim": PortSim.from_dict(data.sim)}


## Brings an older save up to VERSION one step at a time.
static func _migrate(data: Dictionary) -> Dictionary:
	if data.version < 27:
		data = _migrate_v27(data)
	if data.version < 28:
		data = _migrate_v28(data)
	if data.version < 29:
		data = _migrate_v29(data)
	if data.version < 30:
		data = _migrate_v30(data)
	if data.version < 31:
		data = _migrate_v31(data)
	if data.version < 32:
		data = _migrate_v32(data)
	return data


## v32 counts milestones passed (they stay passed) and objectives met. An
## older port keeps the milestones its TEU reached, in order.
static func _migrate_v32(data: Dictionary) -> Dictionary:
	var sim: Dictionary = data.sim
	var thresholds: Array = Content.base().milestones.values().map(func(m: Dictionary) -> int: return m.teu)
	sim.milestones_passed = thresholds.filter(func(teu: int) -> bool: return sim.teu_handled >= teu).size()
	sim.objectives_done = {}
	sim.on_time_calls = {}
	data.version = 32
	return data


## v31 moves boxes between terminals; older boxes stay where they are.
static func _migrate_v31(data: Dictionary) -> Dictionary:
	data.sim.transfers = []
	for box: Dictionary in data.sim.boxes.values():
		box.from = 0
		box.to = 0
	data.version = 31
	return data


## v30 lets ships call light-loaded; older ships carry their full load.
static func _migrate_v30(data: Dictionary) -> Dictionary:
	for ship: Dictionary in data.sim.ships:
		ship.light = false
	data.version = 30
	return data


## v29 has pilot stations, tug depots and narrow-lane bookings; an older
## port has none, and its ships have no clearance yet.
static func _migrate_v29(data: Dictionary) -> Dictionary:
	var sim: Dictionary = data.sim
	sim.pilot_stations = {}
	sim.tug_depots = {}
	sim.next_station = 1
	sim.passages = []
	sim.next_ship = 1
	for ship: Dictionary in sim.ships:
		ship.merge({"id": 0, "cleared": false, "pilot": false, "tugs": 0, "tug_depot": 0, "tugs_at": 0.0, "hold_until": 0.0})
	data.version = 29
	return data


## v28 has anchorages, where ships wait for a berth; an older port has none,
## and its waiting ships wait out at sea from the moment it loads.
static func _migrate_v28(data: Dictionary) -> Dictionary:
	var sim: Dictionary = data.sim
	sim.anchorages = {}
	sim.next_anchorage = 1
	for ship: Dictionary in sim.ships:
		ship.anchorage = 0
		ship.spot = -1
		ship.arrived = sim.ticks * SimClock.CALENDAR_MINUTES_PER_TICK
	data.version = 28
	return data


## v27 has ship lanes and dredging by lane and berth in place of one channel
## depth. An older port has no lanes yet, so no ship reaches it until the
## player draws them; ships under way keep going with no course.
static func _migrate_v27(data: Dictionary) -> Dictionary:
	var sim: Dictionary = data.sim
	sim.erase("channel_depth")
	sim.ship_lanes = {"nodes": {}, "segments": {}, "next_node": 1, "next_segment": 1}
	sim.pocket_dredged = {}
	sim.dredge_version = 0
	for ship: Dictionary in sim.ships:
		ship.path = []
	data.version = 27
	return data


## Check the entire payload before any typed deserialiser sees it.
# shortcut: entries inside boxes, events and ship_log are not checked,
# only that they are dictionaries/arrays; check them if hand-edited saves matter.
static func _valid_sim(data: Variant) -> bool:
	if not data is Dictionary or not _has_fields(data, {
		"roads": TYPE_DICTIONARY, "rails": TYPE_DICTIONARY, "by_rail": TYPE_INT, "rail_discount": TYPE_INT, "power": TYPE_DICTIONARY, "trains": TYPE_ARRAY, "next_train": TYPE_INT, "until_train": TYPE_DICTIONARY, "areas": TYPE_DICTIONARY, "ticks": TYPE_INT, "rng_seed": TYPE_INT,
		"rng_state": TYPE_INT, "ledger": TYPE_DICTIONARY, "delivered": TYPE_INT,
		"events": TYPE_ARRAY, "ship_log": TYPE_ARRAY,
		"delivered_yesterday": TYPE_INT, "delivered_at_midnight": TYPE_INT,
		"ships": TYPE_ARRAY, "cranes": TYPE_ARRAY, "vehicles": TYPE_ARRAY,
		"boxes": TYPE_DICTIONARY, "tractors": TYPE_INT,
		"gave_up": TYPE_INT, "turn_times": TYPE_ARRAY, "terminal_turns": TYPE_DICTIONARY, "claimed": TYPE_DICTIONARY,
		"contracts": TYPE_DICTIONARY, "finance": TYPE_DICTIONARY, "creative": TYPE_BOOL, "land": TYPE_DICTIONARY, "ship_lanes": TYPE_DICTIONARY, "anchorages": TYPE_DICTIONARY, "next_anchorage": TYPE_INT, "pilot_stations": TYPE_DICTIONARY, "tug_depots": TYPE_DICTIONARY, "next_station": TYPE_INT, "passages": TYPE_ARRAY, "next_ship": TYPE_INT, "pocket_dredged": TYPE_DICTIONARY, "dredge_version": TYPE_INT, "crane_orders": TYPE_ARRAY, "teu_handled": TYPE_INT, "year": TYPE_DICTIONARY, "scoreboard": TYPE_ARRAY, "dwell_times": TYPE_ARRAY, "storage": TYPE_DICTIONARY, "until_lorry": TYPE_FLOAT, "until_export": TYPE_FLOAT, "until_empty": TYPE_FLOAT, "returning": TYPE_ARRAY, "stuffing": TYPE_ARRAY, "transfers": TYPE_ARRAY, "milestones_passed": TYPE_INT, "objectives_done": TYPE_DICTIONARY, "on_time_calls": TYPE_DICTIONARY, "bookings": TYPE_DICTIONARY,
		"next_vehicle": TYPE_INT, "next_box": TYPE_INT,
		"lane_traffic": TYPE_DICTIONARY, "handovers": TYPE_DICTIONARY, "machines": TYPE_DICTIONARY, "map": TYPE_STRING,
		"machine_jobs": TYPE_DICTIONARY, "area_stacks": TYPE_DICTIONARY,
	}):
		return false
	if not _has_fields(data.ledger, {
		"cash": TYPE_INT, "opened": TYPE_INT, "today": TYPE_DICTIONARY, "terminals": TYPE_DICTIONARY, "moves": TYPE_DICTIONARY, "days": TYPE_ARRAY,
	}):
		return false
	if not _has_fields(data.storage, {"free_days": TYPE_INT, "fee": TYPE_INT}):
		return false
	if not _has_fields(data.power, {"peak_kw": TYPE_FLOAT, "kwh": TYPE_FLOAT}):
		return false
	if not _has_fields(data.year, {"calls": TYPE_INT, "berth_hours": TYPE_FLOAT, "moves": TYPE_INT, "turns": TYPE_INT, "turn_minutes": TYPE_FLOAT}):
		return false
	if not _has_fields(data.finance, {"loans": TYPE_ARRAY, "days_negative": TYPE_INT, "blocked_until": TYPE_FLOAT}):
		return false
	if not _has_fields(data.contracts, {
		"reputation": TYPE_DICTIONARY, "services": TYPE_ARRAY, "offers": TYPE_ARRAY, "next_id": TYPE_INT,
	}):
		return false
	# Roads and areas first: ships and cranes are checked against the aprons.
	if data.map not in Content.base().maps:
		return false
	if not _valid_ship_lanes(data.ship_lanes):
		return false
	if not data.anchorages.keys().all(func(id: Variant) -> bool: return id is int and data.anchorages[id] is Dictionary and _has_fields(data.anchorages[id], {"from": TYPE_VECTOR2I, "to": TYPE_VECTOR2I})):
		return false
	for bases: Array in [[data.pilot_stations, "pilots"], [data.tug_depots, "tugs"]]:
		if not bases[0].keys().all(func(id: Variant) -> bool: return id is int and bases[0][id] is Dictionary and _has_fields(bases[0][id], {"cell": TYPE_VECTOR2I, bases[1]: TYPE_INT})):
			return false
	if not data.passages.all(func(p: Variant) -> bool: return p is Dictionary and _has_fields(p, {"segment": TYPE_INT, "from": TYPE_FLOAT, "to": TYPE_FLOAT, "ship": TYPE_INT})):
		return false
	if not data.pocket_dredged.keys().all(func(apron: Variant) -> bool: return apron is int and data.pocket_dredged[apron] is float):
		return false
	if not (_valid_roads(data.roads, Content.base().road_types) and _valid_roads(data.rails, {"track": true}) and _valid_areas(data.areas)):
		return false
	for train: Variant in data.trains:
		if not train is Dictionary or not _has_fields(train, {
			"id": TYPE_INT, "block": TYPE_INT, "path": TYPE_ARRAY, "t": TYPE_FLOAT, "prev_t": TYPE_FLOAT,
			"state": TYPE_STRING, "depart": TYPE_FLOAT, "wagons": TYPE_ARRAY, "busy": TYPE_ARRAY,
		}):
			return false
		if train.block not in data.areas.list or train.path.is_empty() or not train.path.all(func(c: Variant) -> bool: return c is Vector2i):
			return false
	for ship: Variant in data.ships:
		if not ship is Dictionary or not _has_fields(ship, {
			"kind": TYPE_STRING, "line": TYPE_STRING, "due": TYPE_FLOAT,
			"boxes": TYPE_INT, "exports": TYPE_INT, "empties": TYPE_INT, "state": TYPE_INT,
			"id": TYPE_INT, "light": TYPE_BOOL, "cleared": TYPE_BOOL, "pilot": TYPE_BOOL, "tugs": TYPE_INT, "tug_depot": TYPE_INT, "tugs_at": TYPE_FLOAT, "hold_until": TYPE_FLOAT,
			"anchorage": TYPE_INT, "spot": TYPE_INT, "arrived": TYPE_FLOAT, "path": TYPE_ARRAY, "sail": TYPE_FLOAT, "prev_sail": TYPE_FLOAT, "moves": TYPE_INT, "berthed": TYPE_FLOAT,
			"apron": TYPE_INT, "from": TYPE_INT, "berth": TYPE_INT, "any_berth": TYPE_BOOL,
		}):
			return false
		if (ship.apron == 0) != (ship.state in [PortSim.Ship.State.ANCHORED, PortSim.Ship.State.ANCHORING]) or (ship.anchorage != 0 and ship.anchorage not in data.anchorages) or not ship.path.all(func(p: Variant) -> bool: return p is Vector2):
			return false
		if ship.apron != 0 and not (ship.apron in data.areas.list and data.areas.list[ship.apron].type == "quay_apron"):
			return false
	for tile: Variant in data.land:
		if not (tile is Vector2i and data.land[tile] is bool):
			return false
	for order: Variant in data.crane_orders:
		if not order is Dictionary or not _has_fields(order, {"apron": TYPE_INT, "along": TYPE_INT, "kind": TYPE_STRING, "due": TYPE_FLOAT}) or order.kind not in Content.base().sts_cranes:
			return false
	for crane: Variant in data.cranes:
		if not crane is Dictionary or not _has_fields(crane, {
			"timer": TYPE_FLOAT, "tractor": TYPE_INT, "apron": TYPE_INT, "along": TYPE_INT, "kind": TYPE_STRING,
		}) or crane.kind not in Content.base().sts_cranes or not (crane.apron in data.areas.list and data.areas.list[crane.apron].type == "quay_apron"):
			return false
	if not _valid_area_flow(data):
		return false
	for id: Variant in data.claimed:
		if not (id is int and data.claimed[id] is bool and data.claimed[id]):
			return false
	for id: Variant in data.boxes:
		if not id is int or not data.boxes[id] is Dictionary:
			return false
	return true


## The area flow's state: vehicles, cells held by known vehicles, slots and
## machines at known areas, stacks of known boxes.
static func _valid_area_flow(data: Dictionary) -> bool:
	var ids := {}
	for vehicle: Variant in data.vehicles:
		if not vehicle is Dictionary or not _has_fields(vehicle, VEHICLE_FIELDS) or not _all_cells(vehicle.path, false):
			return false
		ids[vehicle.id] = true
	# Trains hold level crossings under their id negated.
	for train: Dictionary in data.trains:
		ids[-train.id] = true
	if not _has_fields(data.lane_traffic, {"held": TYPE_DICTIONARY, "delays": TYPE_DICTIONARY, "stuck": TYPE_DICTIONARY, "entered": TYPE_DICTIONARY, "junctions": TYPE_DICTIONARY}):
		return false
	if not _has_fields(data.lane_traffic.junctions, {"signals": TYPE_DICTIONARY, "signs": TYPE_DICTIONARY}):
		return false
	for point: Variant in data.lane_traffic.junctions.signals:
		var at: Variant = data.lane_traffic.junctions.signals[point]
		if not (point is Vector2i and at is Dictionary and _has_fields(at, {"green": TYPE_ARRAY, "phase": TYPE_INT, "left": TYPE_FLOAT})):
			return false
	for point: Variant in data.lane_traffic.junctions.signs:
		var arms: Variant = data.lane_traffic.junctions.signs[point]
		if not (point is Vector2i and arms is Dictionary and arms.keys().all(func(arm: Variant) -> bool: return arm is Vector2i) and arms.values().all(func(sign: Variant) -> bool: return sign in ["give_way", "stop"])):
			return false
	for id: Variant in data.lane_traffic.held:
		if not (id in ids and data.lane_traffic.held[id] is Array and _all_cells(data.lane_traffic.held[id], true)):
			return false
	for counts: String in ["delays", "stuck", "entered"]:
		var by_cell: Dictionary = data.lane_traffic[counts]
		if not by_cell.keys().all(func(cell: Variant) -> bool: return cell is Vector2i) or not by_cell.values().all(func(n: Variant) -> bool: return n is int or n is float):
			return false
	for area: Variant in data.handovers:
		var at: Variant = data.handovers[area]
		if not (area in data.areas.list and at is Dictionary and _has_fields(at, {"slots": TYPE_ARRAY, "buffer": TYPE_ARRAY, "road": TYPE_ARRAY})):
			return false
	if not _has_fields(data.machines, {"list": TYPE_DICTIONARY, "next_id": TYPE_INT}):
		return false
	for machine: Variant in data.machines.list.values():
		if not (machine is Dictionary and _has_fields(machine, {"area": TYPE_INT, "gear": TYPE_STRING, "bay": TYPE_INT, "job": TYPE_DICTIONARY}) and machine.gear in Content.base().yard_gear):
			return false
	for machine: Variant in data.machine_jobs:
		var job: Variant = data.machine_jobs[machine]
		if not (machine in data.machines.list and job is Dictionary and _has_fields(job, {"position": TYPE_INT})):
			return false
		if not (_has_fields(job, {"vehicle": TYPE_INT}) or _has_fields(job, {"train": TYPE_INT, "wagon": TYPE_INT})):
			return false
	for area: Variant in data.area_stacks:
		var stacks: Variant = data.area_stacks[area]
		if not (area in data.areas.list and stacks is Dictionary and _has_fields(stacks, {"stacks": TYPE_ARRAY, "tiers": TYPE_INT, "teu": TYPE_DICTIONARY, "where": TYPE_DICTIONARY})):
			return false
		if not stacks.where.keys().all(func(box: Variant) -> bool: return box in data.boxes):
			return false
	return true


## Roads: nodes on cells, and segments joining two known nodes with a known road type.
static func _valid_roads(roads: Dictionary, types: Dictionary) -> bool:
	if not _has_fields(roads, {"nodes": TYPE_DICTIONARY, "segments": TYPE_DICTIONARY, "next_node": TYPE_INT, "next_segment": TYPE_INT}):
		return false
	if not roads.nodes.keys().all(func(id: Variant) -> bool: return id is int and roads.nodes[id] is Vector2i):
		return false
	return roads.segments.keys().all(func(id: Variant) -> bool:
		var road: Variant = roads.segments[id]
		return id is int and road is Dictionary and _has_fields(road, {"a": TYPE_INT, "b": TYPE_INT, "type": TYPE_STRING}) and road.a in roads.nodes and road.b in roads.nodes and road.type in types)


## Areas: each of a known type, placed on cells, with rules, in a known terminal.
static func _valid_areas(areas: Dictionary) -> bool:
	if not _has_fields(areas, {"list": TYPE_DICTIONARY, "next_id": TYPE_INT, "terminals": TYPE_DICTIONARY, "next_terminal": TYPE_INT, "paint": TYPE_DICTIONARY, "filled": TYPE_DICTIONARY}):
		return false
	if not areas.filled.keys().all(func(cell: Variant) -> bool: return cell is Vector2i):
		return false
	if not areas.terminals.keys().all(func(id: Variant) -> bool: return id is int and areas.terminals[id] is Dictionary and _has_fields(areas.terminals[id], {"name": TYPE_STRING, "colour": TYPE_INT})):
		return false
	if not areas.paint.keys().all(func(cell: Variant) -> bool: return cell is Vector2i and areas.paint[cell] in areas.terminals):
		return false
	var types: Dictionary = Content.base().area_types
	var levels: Dictionary = Content.base().gate_levels
	return areas.list.keys().all(func(id: Variant) -> bool:
		var area: Variant = areas.list[id]
		if not (id is int and area is Dictionary and _has_fields(area, {"type": TYPE_STRING, "start": TYPE_VECTOR2I, "end": TYPE_VECTOR2I, "out": TYPE_VECTOR2I, "settings": TYPE_DICTIONARY, "terminal": TYPE_INT}) and area.type in types and (area.terminal == 0 or area.terminal in areas.terminals)):
			return false
		if types[area.type].kind == "quay_apron" and not area.get("depth") is int:
			return false
		return types[area.type].kind != "gate" or area.settings.get("level") in levels)


static func _valid_ship_lanes(lanes: Dictionary) -> bool:
	if not _has_fields(lanes, {"nodes": TYPE_DICTIONARY, "segments": TYPE_DICTIONARY, "next_node": TYPE_INT, "next_segment": TYPE_INT}):
		return false
	if not lanes.nodes.keys().all(func(id: Variant) -> bool: return id is int and lanes.nodes[id] is Vector2i):
		return false
	var types: Dictionary = Content.base().water.lanes
	return lanes.segments.keys().all(func(id: Variant) -> bool:
		var lane: Variant = lanes.segments[id]
		return id is int and lane is Dictionary and _has_fields(lane, {"a": TYPE_INT, "b": TYPE_INT, "type": TYPE_STRING, "dredged": TYPE_FLOAT}) and lane.a in lanes.nodes and lane.b in lanes.nodes and lane.type in types)


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
