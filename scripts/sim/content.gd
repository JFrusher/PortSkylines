class_name Content
extends RefCounted
## Tunable numbers, read from the JSON files in data/base/. SCHEMA lists every
## key the game uses and its type; a missing, unknown or mistyped key is an
## error naming the file and key, so bad data never reaches the sim.

const BASE_DIR := "res://data/base"
const SCHEMA := {
	# The site for roads and areas, in metres, each a whole number of Grid cells.
	"site": {"width": TYPE_INT, "height": TYPE_INT, "sea_width": TYPE_INT},
	"start_money": TYPE_INT,
	# What a line pays per crane move: by box size, plus a reefer premium.
	"move_price": {"per_20ft": TYPE_INT, "forty_factor": TYPE_FLOAT, "reefer_premium": TYPE_INT},
	# Shares of 40 ft boxes and reefers among all boxes.
	"box_mix": {"forty_share": TYPE_FLOAT, "reefer_share": TYPE_FLOAT},
	# Starting storage terms, the fee cap, how fees shorten import dwell, and
	# how shippers (and so lines) feel about fees above the fair rate.
	"storage": {"free_days": TYPE_INT, "fee": TYPE_INT, "max_fee": TYPE_INT, "dwell_per_dollar": TYPE_FLOAT, "min_dwell_factor": TYPE_FLOAT, "fair_fee": TYPE_INT, "satisfaction_per_dollar": TYPE_FLOAT},
	"gate_levels": {"*": {"name": TYPE_STRING, "minutes": TYPE_FLOAT, "upkeep_per_lane": TYPE_INT}},
	"export_lead_hours": TYPE_FLOAT,
	"upkeep": {"sts_crane": TYPE_INT, "tractor": TYPE_INT},
	"sail_seconds": TYPE_FLOAT,
	"lorry_interval_minutes": TYPE_FLOAT,
	"export_lorry_interval_minutes": TYPE_FLOAT,
	"import_dwell_minutes": TYPE_FLOAT,
	# Metres a vehicle second, which is one game minute; the tractor's too.
	"lorry_speed": TYPE_FLOAT,
	"give_up_seconds": TYPE_FLOAT,
	# Every way cash can move, with the label the ledger panel shows.
	"ledger_categories": {"*": TYPE_STRING},
	# Loans the port can take, up to max_loans at once, paid back daily.
	"loans": {"*": {"amount": TYPE_INT, "yearly_rate": TYPE_FLOAT, "days": TYPE_INT}},
	"max_loans": TYPE_INT,
	# Milestones on TEU moved across the quay; each unlocks named content
	# (a ship class, a yard gear, "loans", "land", "dredging", "ledger" or
	# "contracts"), shown to the player with the given description.
	"milestones": {"*": {"teu": TYPE_INT, "unlocks": {"*": TYPE_STRING}}},
	# A game year, for the year-end scoreboard.
	"year_days": TYPE_INT,
	# After `days` midnights below zero the debt is cleared, every line's
	# reputation changes by `reputation`, and no loans for `no_loans_days`.
	"bailout": {"days": TYPE_INT, "reputation": TYPE_FLOAT, "no_loans_days": TYPE_INT},
	# "*" means any key, each holding the record that follows.
	# Length in metres, draft in metres, outreach in box rows.
	"ship_classes": {"*": {"length": TYPE_INT, "draft": TYPE_FLOAT, "outreach": TYPE_INT, "import_moves": TYPE_INT, "export_moves": TYPE_INT, "window_hours": TYPE_FLOAT}},
	# Fictional shipping lines: the classes they sail (relative weights) and how
	# strongly their reputation of the port moves.
	"lines": {"*": {"name": TYPE_STRING, "livery": TYPE_STRING, "classes": {"*": TYPE_FLOAT}, "sensitivity": TYPE_FLOAT}},
	"contracts": {"offer_check_minutes": TYPE_FLOAT, "offer_chance": TYPE_FLOAT, "max_offers": TYPE_INT, "offer_days": TYPE_FLOAT, "max_services_per_berth": TYPE_INT},
	"reputation": {
		"start": TYPE_FLOAT, "offer_above": TYPE_FLOAT, "cancel_below": TYPE_FLOAT, "on_time": TYPE_FLOAT,
		"late_per_hour": TYPE_FLOAT, "moves_per_hour_target": TYPE_FLOAT, "per_move_per_hour": TYPE_FLOAT,
		"turn_target_minutes": TYPE_FLOAT, "per_turn_minute": TYPE_FLOAT, "missed": TYPE_FLOAT,
	},
	# shortcut: one channel depth serves every berth; give each berth its own route and depth when ports get several channels.
	"channel": {"start_depth": TYPE_FLOAT, "max_depth": TYPE_FLOAT, "cost_per_metre": TYPE_INT, "maintenance_per_metre": TYPE_INT, "maintenance_days": TYPE_INT},
	# The site is split into square land tiles `metres` across; the port owns
	# the `start` block of tiles and buys the rest at `price`, paying `upkeep` a day each.
	"land": {"metres": TYPE_INT, "price": TYPE_INT, "upkeep": TYPE_INT, "start": {"x": TYPE_INT, "y": TYPE_INT, "width": TYPE_INT, "height": TYPE_INT}},
	# An STS crane: its price, moves an hour, outreach in box rows, days from
	# order to standing, and width along the quay in metres.
	"sts_crane": {"cost": TYPE_INT, "rate": TYPE_FLOAT, "outreach": TYPE_INT, "lead_days": TYPE_FLOAT, "width": TYPE_INT, "max_fetchers": TYPE_INT},
	"crane_interference": TYPE_FLOAT,
	"tractor": {"cost": TYPE_INT, "speed": TYPE_FLOAT},
	# Roads the player draws: lanes each way along the drawn direction, whether
	# lorries may use it (tractors and AGVs always may), and cost and daily upkeep per 4 m cell.
	"road_types": {"*": {"name": TYPE_STRING, "forward": TYPE_INT, "backward": TYPE_INT, "lorries": TYPE_BOOL, "cost_per_cell": TYPE_INT, "upkeep_per_cell": TYPE_FLOAT}},
	# Areas dragged along a road edge: how deep they reach from the road and
	# their shortest length, in 4 m cells, and cost and daily upkeep per cell.
	"area_types": {"*": {"name": TYPE_STRING, "kind": TYPE_STRING, "depth": TYPE_INT, "max_depth": TYPE_INT, "min_length": TYPE_INT, "cost_per_cell": TYPE_INT, "upkeep_per_cell": TYPE_FLOAT}},
	# Yard machines on areas: travel speed in m/s, seconds to lift and to set
	# down a box, one machine per so many bays of an area, and how high they stack.
	"yard_gear": {"*": {"upkeep_per_machine": TYPE_INT, "speed": TYPE_FLOAT, "lift_seconds": TYPE_FLOAT, "set_down_seconds": TYPE_FLOAT, "bays_per_machine": TYPE_INT, "tiers": TYPE_INT}},
}

## What an area type does; several types may share a kind, as gates of different sizes do.
const AREA_KINDS := ["yard_block", "quay_apron", "gate", "depot"]

# Keys the sim divides by or repeats on; zero or less would hang or spin it.
const POSITIVE := ["width", "tiers", "lift_seconds", "set_down_seconds", "bays_per_machine", "depth", "min_length", "year_days", "metres", "maintenance_days", "amount", "days", "per_20ft", "forty_factor", "min_dwell_factor", "offer_check_minutes", "window_hours", "sensitivity", "sail_seconds", "lorry_interval_minutes", "export_lorry_interval_minutes", "lorry_speed", "give_up_seconds", "length", "rate", "crane_interference", "speed", "minutes"]

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
	return _cross_check(rules)


## Checks that need more than one key: the site is whole grid cells, and
## every line sails known ship classes.
static func _cross_check(rules: Dictionary) -> Dictionary:
	for key: String in rules.site:
		if rules.site[key] <= 0 or rules.site[key] % Grid.CELL != 0:
			return {"error": "site.%s: must be a positive multiple of %d m" % [key, Grid.CELL]}
	for kind: String in rules.road_types:
		var road: Dictionary = rules.road_types[kind]
		if road.forward < 0 or road.backward < 0 or road.forward + road.backward == 0 or road.forward < road.backward:
			return {"error": "road_types.%s: needs lanes, with at least as many forward as backward" % kind}
	for kind: String in rules.area_types:
		if rules.area_types[kind].max_depth < rules.area_types[kind].depth:
			return {"error": "area_types.%s: max_depth must be at least depth" % kind}
		if rules.area_types[kind].kind not in AREA_KINDS:
			return {"error": "area_types.%s.kind: must be one of %s" % [kind, AREA_KINDS]}
	for line: String in rules.lines:
		for kind: String in rules.lines[line].classes:
			if not rules.ship_classes.has(kind):
				return {"error": "lines.%s.classes: unknown ship class \"%s\"" % [line, kind]}
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
	if want == TYPE_BOOL:
		return "" if got is bool else "%s: must be true or false" % where
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
