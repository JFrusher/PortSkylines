class_name SaveFile
extends RefCounted
## A save is the bytes "PSKY" then {"version", "sim"} written with store_var,
## with objects refused both ways, so a save file can never carry code. The
## magic bytes let junk be refused before Godot tries to decode it. Raising
## VERSION means adding a step to _migrate() and committing
## tests/fixtures/save_v<N>.bin.

const VERSION := 1
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


## Brings an older save up to VERSION one step at a time. Empty until v2.
static func _migrate(data: Dictionary) -> Dictionary:
	return data


## Check the entire payload before any typed deserialiser sees it.
static func _valid_sim(data: Variant) -> bool:
	if not data is Dictionary or not _has_fields(data, {
		"map": TYPE_DICTIONARY, "ticks": TYPE_INT, "rng_seed": TYPE_INT,
		"rng_state": TYPE_INT, "money": TYPE_INT, "delivered": TYPE_INT,
		"status": TYPE_STRING, "ships": TYPE_ARRAY, "lorries": TYPE_ARRAY,
		"stacked": TYPE_DICTIONARY, "claimed": TYPE_DICTIONARY,
		"until_ship": TYPE_FLOAT, "until_lorry": TYPE_FLOAT,
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
	for ship: Variant in data.ships:
		if not ship is Dictionary or not _has_fields(ship, {
			"quay": TYPE_VECTOR2I, "berth": TYPE_VECTOR2I, "boxes": TYPE_INT,
			"state": TYPE_INT, "sail": TYPE_FLOAT, "prev_sail": TYPE_FLOAT,
			"crane": TYPE_FLOAT,
		}):
			return false
	for lorry: Variant in data.lorries:
		if not lorry is Dictionary or not _has_fields(lorry, {
			"path": TYPE_ARRAY, "yard": TYPE_VECTOR2I, "loaded": TYPE_BOOL,
			"t": TYPE_FLOAT, "prev_t": TYPE_FLOAT,
		}):
			return false
		if lorry.path.is_empty():
			return false
		for cell: Variant in lorry.path:
			if not cell is Vector2i:
				return false
	for counts: Dictionary in [data.stacked, data.claimed]:
		for cell: Variant in counts:
			if not cell is Vector2i or not counts[cell] is int:
				return false
	return true


static func _has_fields(data: Dictionary, fields: Dictionary) -> bool:
	for key: String in fields:
		var value: Variant = data.get(key)
		if typeof(value) != fields[key] and not (fields[key] == TYPE_FLOAT and value is int):
			return false
		if fields[key] == TYPE_FLOAT and not is_finite(value):
			return false
	return true
