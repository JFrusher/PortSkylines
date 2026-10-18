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
	data.sim.status = "Saved game updated: ships that were in port have sailed"
	data.version = 2
	return data
