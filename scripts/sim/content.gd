class_name Content
extends RefCounted
## Tunable numbers, read from the JSON files in data/base/. SCHEMA lists every
## key the game uses and its type; a missing, unknown or mistyped key is an
## error naming the file and key, so bad data never reaches the sim.

const BASE_DIR := "res://data/base"
const SCHEMA := {
	"map": {"width": TYPE_INT, "height": TYPE_INT, "sea_width": TYPE_INT},
	"start_money": TYPE_INT,
	"fee_per_box": TYPE_INT,
	"build_cost": {"road": TYPE_INT, "quay": TYPE_INT, "yard": TYPE_INT, "gate": TYPE_INT},
	"gate_minutes": TYPE_FLOAT,
	"upkeep": {"road": TYPE_INT, "quay": TYPE_INT, "yard": TYPE_INT, "gate": TYPE_INT, "sts_crane": TYPE_INT, "tractor": TYPE_INT},
	"first_ship_minutes": TYPE_FLOAT,
	"ship_interval_minutes": TYPE_FLOAT,
	"sail_seconds": TYPE_FLOAT,
	"lorry_interval_minutes": TYPE_FLOAT,
	"export_lorry_interval_minutes": TYPE_FLOAT,
	"import_dwell_minutes": TYPE_FLOAT,
	"lorry_speed": TYPE_FLOAT,
	"give_up_seconds": TYPE_FLOAT,
	# Every way cash can move, with the label the ledger panel shows.
	"ledger_categories": {"*": TYPE_STRING},
	# "*" means any key, each holding the record that follows.
	"ship_classes": {"*": {"length": TYPE_INT, "draft": TYPE_FLOAT, "outreach": TYPE_INT, "import_moves": TYPE_INT, "export_moves": TYPE_INT, "weight": TYPE_FLOAT}},
	"water_depth": TYPE_FLOAT,
	"sts_crane": {"cost": TYPE_INT, "rate": TYPE_FLOAT, "outreach": TYPE_INT},
	"crane_interference": TYPE_FLOAT,
	"tractor": {"cost": TYPE_INT, "speed": TYPE_FLOAT},
	"yard_gear": {"*": {"capacity": TYPE_INT, "handling_minutes": TYPE_FLOAT, "tiles_per_machine": TYPE_INT, "cost_per_tile": TYPE_INT, "upkeep_per_machine": TYPE_INT}},
}

# Keys the sim divides by or repeats on; zero or less would hang or spin it.
const POSITIVE := ["ship_interval_minutes", "sail_seconds", "lorry_interval_minutes", "export_lorry_interval_minutes", "lorry_speed", "give_up_seconds", "length", "rate", "crane_interference", "speed", "capacity", "handling_minutes", "tiles_per_machine"]

static var _base := {}


## The base game's rules. Bad base data is a bug, so it stops the game.
static func base() -> Dictionary:
	if _base.is_empty():
		var result := load_dir(BASE_DIR)
		if result.has("error"):
			push_error(result.error)
			assert(false, "Bad base game data, see the error above")
		_base = result.rules
	return _base


## {"rules": Dictionary} from every .json file in `dir`, or {"error": String}.
static func load_dir(dir: String) -> Dictionary:
	var rules := {}
	var source := {}
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".json"))
	files.sort()
	for file: String in files:
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(dir.path_join(file))) != OK:
			return {"error": "%s line %d: %s" % [file, json.get_error_line(), json.get_error_message()]}
		if not json.data is Dictionary:
			return {"error": "%s must hold one JSON object" % file}
		for key: String in json.data:
			if rules.has(key):
				return {"error": "%s: \"%s\" is already set in %s" % [file, key, source[key]]}
			rules[key] = json.data[key]
			source[key] = file
	for key: String in SCHEMA:
		if not rules.has(key):
			return {"error": "%s: missing \"%s\"" % [dir, key]}
	for key: String in rules:
		var err := _check(rules, key, SCHEMA.get(key), "%s: %s" % [source[key], key])
		if err:
			return {"error": err}
	return {"rules": rules}


## Checks `parent[key]` against `want` (a TYPE_* or a nested schema), turning
## whole JSON numbers into ints where the schema says int.
static func _check(parent: Dictionary, key: String, want: Variant, where: String) -> String:
	var got: Variant = parent[key]
	if want == null:
		return "%s: unknown key" % where
	if want is Dictionary:
		if not got is Dictionary:
			return "%s: must be an object" % where
		if want.has("*"):
			if got.is_empty():
				return "%s: must list at least one entry" % where
			for sub: String in got:
				var err := _check(got, sub, want["*"], "%s.%s" % [where, sub])
				if err:
					return err
			return ""
		for sub: String in want:
			if not got.has(sub):
				return "%s: missing \"%s\"" % [where, sub]
		for sub: String in got:
			var err := _check(got, sub, want.get(sub), "%s.%s" % [where, sub])
			if err:
				return err
		return ""
	if want == TYPE_STRING:
		return "" if got is String else "%s: must be text" % where
	if not (got is float or got is int):
		return "%s: must be a number" % where
	if want == TYPE_INT:
		if got != floorf(got):
			return "%s: must be a whole number" % where
		parent[key] = int(got)
	else:
		parent[key] = float(got)
	if key in POSITIVE and got <= 0:
		return "%s: must be greater than zero" % where
	return ""
