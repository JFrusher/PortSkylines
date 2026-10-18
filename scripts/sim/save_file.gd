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
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Can't write %s: %s" % [path, error_string(FileAccess.get_open_error())]
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_var({"version": VERSION, "sim": sim.to_dict()}, false)
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
	return {"sim": PortSim.from_dict(_migrate(data).sim)}


## Brings an older save up to VERSION one step at a time. Empty until v2.
static func _migrate(data: Dictionary) -> Dictionary:
	return data
