class_name Content
extends RefCounted
## Tunable numbers, read from the JSON files in data/base/. SCHEMA lists every
## key the game uses and its type; a missing, unknown or mistyped key is an
## error naming the file and key, so bad data never reaches the sim.

const BASE_DIR := "res://data/base"
const SCHEMA := {
	# The site for roads and areas, in metres, each a whole number of Grid cells.
	"site": {"width": TYPE_INT, "height": TYPE_INT},
	# The coast a new game is played on, a key of maps. Each map is in metres
	# on the site: the mainland's outline and each island as a polygon of
	# [x, y] points, rivers as lines of points with a width and a depth that
	# carve water through the land, and the sea's depth: shore metres beside
	# land, per_metre more for each metre out, up to max.
	"map": TYPE_STRING,
	"maps": {"*": {"name": TYPE_STRING, "land": TYPE_ARRAY, "islands": TYPE_ARRAY, "rivers": TYPE_ARRAY, "depth": {"shore": TYPE_FLOAT, "per_metre": TYPE_FLOAT, "max": TYPE_FLOAT}}},
	# Of the imports a line lands at one terminal while it also calls at
	# another, `share` leave on its ship there, moved by road between the
	# terminals at cost_per_box, an internal move.
	"transfers": {"share": TYPE_FLOAT, "cost_per_box": TYPE_INT},
	# Filling water to make land behind a quay wall, per 4 m cell.
	"reclaim": {"cost_per_cell": TYPE_INT},
	"start_money": TYPE_INT,
	# What a line pays per crane move: by box size, plus a reefer premium.
	"move_price": {"per_20ft": TYPE_INT, "forty_factor": TYPE_FLOAT, "reefer_premium": TYPE_INT},
	# Shares of 40 ft boxes, reefers, rush imports and dangerous goods among
	# all boxes. A rush import discharged after its ship's window closed costs
	# rush_fine; dangerous goods stack only in dangerous-goods blocks, which
	# keep dg_distance cells clear of every other yard block.
	"box_mix": {"forty_share": TYPE_FLOAT, "reefer_share": TYPE_FLOAT, "rush_share": TYPE_FLOAT, "dg_share": TYPE_FLOAT},
	"special_boxes": {"rush_fine": TYPE_INT, "dg_distance": TYPE_INT},
	# Reefers are plugged in reefer blocks. One stacked anywhere else past
	# plug_minutes costs its line's fine. Each plugged box draws kw, hot_kw on
	# the hot days of the year (hot_from to hot_to inclusive), billed daily per
	# kWh plus a charge on the day's peak kW.
	"reefers": {"plug_minutes": TYPE_FLOAT, "fine": TYPE_INT, "kw": TYPE_FLOAT, "hot_kw": TYPE_FLOAT, "hot_from": TYPE_INT, "hot_to": TYPE_INT, "price_per_kwh": TYPE_FLOAT, "peak_charge_per_kw": TYPE_FLOAT},
	# Starting storage terms, the fee cap, how fees shorten import dwell, and
	# how shippers (and so lines) feel about fees above the fair rate.
	"storage": {"free_days": TYPE_INT, "fee": TYPE_INT, "max_fee": TYPE_INT, "dwell_per_dollar": TYPE_FLOAT, "min_dwell_factor": TYPE_FLOAT, "fair_fee": TYPE_INT, "satisfaction_per_dollar": TYPE_FLOAT},
	"gate_levels": {"*": {"name": TYPE_STRING, "minutes": TYPE_FLOAT, "upkeep_per_lane": TYPE_INT}},
	"export_lead_hours": TYPE_FLOAT,
	"upkeep": {"sts_crane": TYPE_INT, "tractor": TYPE_INT, "agv": TYPE_INT},
	# How long vehicles wait in each lane cell is folded in every epoch_seconds
	# of vehicle time, mixed in at `smoothing` (0 to 1); routes take up the
	# delays every route_epoch_seconds, dropping every kept route.
	# Signals: each phase is green signal_green_seconds by default, which the
	# player sets between min and max; a stop sign stands stop_seconds.
	# Continuous traffic (M10): vehicles keep standstill_gap_m plus
	# headway_seconds of travel behind the one ahead, speed up and brake at
	# accel and decel (m/s²), take a curve no faster than lateral_accel (m/s²)
	# allows, and are lorry_m and tractor_m long; one stuck stuck_minutes is
	# moved on to where it was heading.
	"traffic": {"epoch_seconds": TYPE_FLOAT, "smoothing": TYPE_FLOAT, "route_epoch_seconds": TYPE_FLOAT, "signal_green_seconds": TYPE_FLOAT, "min_green_seconds": TYPE_FLOAT, "max_green_seconds": TYPE_FLOAT, "stop_seconds": TYPE_FLOAT,
		"standstill_gap_m": TYPE_FLOAT, "headway_seconds": TYPE_FLOAT, "accel": TYPE_FLOAT, "decel": TYPE_FLOAT, "lateral_accel": TYPE_FLOAT, "lorry_m": TYPE_FLOAT, "tractor_m": TYPE_FLOAT, "area_kmh": TYPE_FLOAT, "give_way_seconds": TYPE_FLOAT, "stuck_minutes": TYPE_FLOAT},
	# Empties: return_share of imports come back as empties return_days after
	# leaving, the rest going to inland depots; one
	# turned away for want of room costs its line `refused` reputation; one
	# taken out by an exporter comes back full stuffing_hours later. Ships take
	# up to max_per_call of their line's empties above `keep`, each earning
	# price_factor of a move.
	"empties": {"return_share": TYPE_FLOAT, "return_days": TYPE_FLOAT, "refused": TYPE_FLOAT, "stuffing_hours": TYPE_FLOAT, "keep": TYPE_INT, "max_per_call": TYPE_INT, "price_factor": TYPE_FLOAT},
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
	# Customs (M11): each line's customs_share of its imports is flagged when
	# landed. With a gate scanner in the terminal only inspect_share_after_scan
	# of those need inspecting; they go to a customs block, whose inspectors
	# (inspector_cost, upkeep_per_inspector a day) each inspect one for
	# inspect_hours_min to inspect_hours_max. With no customs block a flagged
	# box waits no_shed_hours where it stacks. A flagged box never leaves until
	# cleared.
	"customs": {"inspect_share_after_scan": TYPE_FLOAT, "inspect_hours_min": TYPE_FLOAT, "inspect_hours_max": TYPE_FLOAT, "no_shed_hours": TYPE_FLOAT, "scanner_cost": TYPE_INT, "inspector_cost": TYPE_INT, "upkeep_per_inspector": TYPE_INT},
	# Events (M11): planned a season of season_days ahead from their own seeded
	# random numbers, each kind on or off per game (`defaults` for a new one).
	# Wind blows at mean_kmh, daily_swing_kmh stronger mid-afternoon and that
	# much calmer before dawn. With breakdowns on, working equipment fails on
	# average every mtbf_hours of work (in its own data), repairs taking
	# repair_hours_min to repair_hours_max by a mechanic hired at a workshop
	# for mechanic_cost (upkeep_per_mechanic a day), whose van drives the
	# roads at van_speed metres a minute. Equipment the player has serviced
	# (by kind) is taken out for service_hours every service_every_hours of
	# work, and fails serviced_mtbf_factor times less often. With fires on,
	# per_week break out (ship_share of them on ships at berth, a yard block
	# by or with dangerous goods dg_factor times likelier); one no crew has
	# reached after grace_minutes burns boxes_per_hour (each box_value and
	# reputation_per_box), a ship ship_reputation_per_hour; a crew puts it out
	# in fight_hours. Fire engines (engine_cost, upkeep_per_engine) drive from
	# fire stations at engine_speed metres a minute. Storms: per_season on average, each lasting hours_min to hours_max with
	# gusts peaking at peak_min_kmh to peak_max_kmh, forecast lead_hours ahead.
	"events": {"season_days": TYPE_FLOAT, "defaults": {"*": TYPE_BOOL}, "wind": {"mean_kmh": TYPE_FLOAT, "daily_swing_kmh": TYPE_FLOAT}, "fires": {"per_week": TYPE_FLOAT, "dg_factor": TYPE_FLOAT, "ship_share": TYPE_FLOAT, "grace_minutes": TYPE_FLOAT, "boxes_per_hour": TYPE_FLOAT, "box_value": TYPE_INT, "reputation_per_box": TYPE_FLOAT, "ship_reputation_per_hour": TYPE_FLOAT, "fight_hours": TYPE_FLOAT, "engine_cost": TYPE_INT, "upkeep_per_engine": TYPE_INT, "engine_speed": TYPE_FLOAT}, "breakdowns": {"repair_hours_min": TYPE_FLOAT, "repair_hours_max": TYPE_FLOAT, "mechanic_cost": TYPE_INT, "upkeep_per_mechanic": TYPE_INT, "van_speed": TYPE_FLOAT, "service_every_hours": TYPE_FLOAT, "service_hours": TYPE_FLOAT, "serviced_mtbf_factor": TYPE_FLOAT}, "storms": {"per_season": TYPE_FLOAT, "hours_min": TYPE_FLOAT, "hours_max": TYPE_FLOAT, "lead_hours": TYPE_FLOAT, "peak_min_kmh": TYPE_FLOAT, "peak_max_kmh": TYPE_FLOAT}},
	# Milestones on TEU moved across the quay; each unlocks named content
	# (a ship class, a yard gear, "loans", "land", "dredging", "ledger" or
	# "contracts"), shown to the player with the given description.
	# demand: how busy the hinterland keeps lines once the milestone is reached,
	# scaling how often they offer services (1 before the first). A milestone
	# also needs the lines' average reputation, the share of the last calls
	# that sailed on time, and the berth moves an hour those calls averaged,
	# each at least its value; once reached it stays reached.
	"milestones": {"*": {"teu": TYPE_INT, "demand": TYPE_FLOAT, "reputation": TYPE_FLOAT, "on_time": TYPE_FLOAT, "productivity": TYPE_FLOAT, "unlocks": {"*": TYPE_STRING}}},
	# Goals between milestones, each open once `after` milestones are reached
	# and paying cash and reputation with every line once, when met: kind
	# on_time_calls (`count` calls of `class` sailed on time), day_moves
	# (`count` crane moves in one day) or working_terminals (`count` of them).
	"objectives": {"*": {"text": TYPE_STRING, "after": TYPE_INT, "kind": TYPE_STRING, "class": TYPE_STRING, "count": TYPE_INT, "cash": TYPE_INT, "reputation": TYPE_FLOAT}},
	# A game year, for the year-end scoreboard.
	"year_days": TYPE_INT,
	# After `days` midnights below zero the debt is cleared, every line's
	# reputation changes by `reputation`, and no loans for `no_loans_days`.
	"bailout": {"days": TYPE_INT, "reputation": TYPE_FLOAT, "no_loans_days": TYPE_INT},
	# "*" means any key, each holding the record that follows.
	# Length in metres, draft in metres, outreach in box rows. Each service
	# (bunkers, provisions, waste) a ship of the class wants with `chance` when
	# it calls, paying `fee` for `minutes` of a service boat's work. An inland ship
	# (a barge) comes and goes only by a river's inland end, where it leaves
	# the site; every other ship only by the open sea.
	"ship_classes": {"*": {"length": TYPE_INT, "draft": TYPE_FLOAT, "light_draft": TYPE_FLOAT, "light_share": TYPE_FLOAT, "outreach": TYPE_INT, "import_moves": TYPE_INT, "export_moves": TYPE_INT, "window_hours": TYPE_FLOAT, "pilot": TYPE_BOOL, "tugs": TYPE_INT, "port_dues": TYPE_INT, "inland": TYPE_BOOL, "services": {"*": {"chance": TYPE_FLOAT, "fee": TYPE_INT, "minutes": TYPE_FLOAT}}}},
	# Fictional shipping lines: the classes they sail (relative weights) and how
	# strongly their reputation of the port moves.
	# rail_share: of a line's imports, the share booked to leave by train when
	# the terminal has a rail block. barge_share: of its big ships' imports for
	# a place the river reaches, the share booked to leave by barge.
	"lines": {"*": {"name": TYPE_STRING, "livery": TYPE_STRING, "stripe": TYPE_STRING, "classes": {"*": TYPE_FLOAT}, "sensitivity": TYPE_FLOAT, "rail_share": TYPE_FLOAT, "barge_share": TYPE_FLOAT, "tranship_share": TYPE_FLOAT, "connection_hours": TYPE_FLOAT, "customs_share": TYPE_FLOAT}},
	# Transhipment: a line's tranship_share of the boxes its big ships land
	# leave on its next feeder within connection_hours, and the same share of
	# its feeders' boxes on its next big ship; each such move pays the move
	# price times price_factor. A box not loaded within the window costs
	# missed_fine and missed_reputation with its line (times its sensitivity),
	# and waits a further connection_hours for the next ship.
	"transhipment": {"price_factor": TYPE_FLOAT, "missed_fine": TYPE_INT, "missed_reputation": TYPE_FLOAT},
	"contracts": {"offer_check_minutes": TYPE_FLOAT, "offer_chance": TYPE_FLOAT, "max_offers": TYPE_INT, "offer_days": TYPE_FLOAT, "max_services_per_berth": TYPE_INT, "flex_hours": TYPE_INT},
	"reputation": {
		"start": TYPE_FLOAT, "offer_above": TYPE_FLOAT, "cancel_below": TYPE_FLOAT, "on_time": TYPE_FLOAT,
		"late_per_hour": TYPE_FLOAT, "moves_per_hour_target": TYPE_FLOAT, "per_move_per_hour": TYPE_FLOAT,
		"turn_target_minutes": TYPE_FLOAT, "per_turn_minute": TYPE_FLOAT, "missed": TYPE_FLOAT, "port_cancels": TYPE_FLOAT,
	},
	# Ships sail ship_speed metres a minute along ship lanes drawn on the
	# water: a lane takes one ship at a time unless it is two_way, and only
	# barges sail a barges_only one (a river channel); each covers half_width
	# cells either side of its line, and bends no tighter than min_radius_cells. A ship lies in its
	# berth's pocket, `pocket` cells out from the quay. Lanes and pockets are
	# as deep as their shallowest water plus what is dredged there, at most
	# dredge.max_depth; dredging costs per cell and metre, then maintenance
	# per cell and metre every maintenance_days. Ships wait for a berth at
	# anchorages, one every `spacing` cells each way; a ship with no room at
	# one waits out at sea max_wait_hours, then goes elsewhere. Classes with
	# a pilot take one from a pilot station for each passage, its boat coming
	# out at boat_speed metres a minute; classes with tugs wait for that many
	# from a tug depot, sailing at speed metres a minute, to berth and
	# unberth. A ship books each narrow lane it passes, slot_margin_minutes
	# clear of the next ship's booking. Breakwaters are walls on the water,
	# at a price and upkeep per cell, that no lane crosses. As port authority the port charges
	# each call its class's port_dues, and each piloted passage pilots.fee.
	"water": {"ship_speed": TYPE_FLOAT, "lanes": {"*": {"name": TYPE_STRING, "min_radius_cells": TYPE_FLOAT, "half_width": TYPE_INT, "cost_per_cell": TYPE_INT, "upkeep_per_cell": TYPE_FLOAT, "two_way": TYPE_BOOL, "barges_only": TYPE_BOOL}}, "pocket": TYPE_INT,
		"anchorage": {"cost_per_cell": TYPE_INT, "spacing": TYPE_INT}, "max_wait_hours": TYPE_FLOAT,
		"pilots": {"station_cost": TYPE_INT, "pilot_cost": TYPE_INT, "upkeep_per_pilot": TYPE_INT, "boat_speed": TYPE_FLOAT, "fee": TYPE_INT},
		"tugs": {"depot_cost": TYPE_INT, "tug_cost": TYPE_INT, "upkeep_per_tug": TYPE_INT, "speed": TYPE_FLOAT}, "slot_margin_minutes": TYPE_FLOAT,
		"fireboats": {"cost": TYPE_INT, "upkeep": TYPE_INT, "speed": TYPE_FLOAT},
		"tides": {"range": TYPE_FLOAT, "period_hours": TYPE_FLOAT},
		"services": {"jetty_cost": TYPE_INT, "unserved_reputation": TYPE_FLOAT, "boats": {"*": {"name": TYPE_STRING, "cost": TYPE_INT, "upkeep": TYPE_INT, "speed": TYPE_FLOAT}}},
		"breakwater": {"cost_per_cell": TYPE_INT, "upkeep_per_cell": TYPE_FLOAT},
		"dredge": {"max_depth": TYPE_FLOAT, "cost_per_cell_metre": TYPE_INT, "maintenance_per_cell_metre": TYPE_INT, "maintenance_days": TYPE_INT}},
	# The site is split into square land tiles `metres` across; the port owns
	# the `start` block of tiles and buys the rest at `price`, paying `upkeep` a day each.
	"land": {"metres": TYPE_INT, "price": TYPE_INT, "upkeep": TYPE_INT, "start": {"x": TYPE_INT, "y": TYPE_INT, "width": TYPE_INT, "height": TYPE_INT}},
	# An STS crane: its price, moves an hour, outreach in box rows, days from
	# order to standing, and width along the quay in metres.
	"sts_cranes": {"*": {"name": TYPE_STRING, "wind_limit_kmh": TYPE_FLOAT, "mtbf_hours": TYPE_FLOAT, "cost": TYPE_INT, "rate": TYPE_FLOAT, "outreach": TYPE_INT, "lead_days": TYPE_FLOAT, "width": TYPE_INT, "max_fetchers": TYPE_INT}},
	"crane_interference": TYPE_FLOAT,
	"tractor": {"cost": TYPE_INT, "speed": TYPE_FLOAT},
	# How boxes look (M11): own_share of a line's boxes in its livery (stripe_share
	# of those with its stripe), the rest leased in a lessor colour; reefers
	# white; each faded and darkened up to weathering, rust_share of them rusty.
	# Floodlights through the night (M11): a flat cost per terminal, paid as night ends.
	"lighting": {"per_terminal_night": TYPE_INT, "night_ends_hour": TYPE_FLOAT},
	# The town next door (M11, see Town): where it sits past the entry, how far
	# the port reaches it, its mood's base and pace, noise and light by area
	# kind, jobs by kind of worker, and what its fixes cost.
	"town": {"name": TYPE_STRING, "offset_cells": TYPE_ARRAY, "reach_m": TYPE_FLOAT, "base_mood": TYPE_FLOAT, "ease_per_hour": TYPE_FLOAT, "sour_below": TYPE_FLOAT, "warm_above": TYPE_FLOAT, "night_starts_hour": TYPE_FLOAT, "noise": {"*": TYPE_FLOAT}, "light": {"*": TYPE_FLOAT}, "ship_noise": TYPE_FLOAT, "lorry_noise": TYPE_FLOAT, "belt_factor": TYPE_FLOAT, "jobs": {"crane": TYPE_FLOAT, "machine": TYPE_FLOAT, "tractor": TYPE_FLOAT, "person": TYPE_FLOAT}, "points_per_job": TYPE_FLOAT, "max_job_points": TYPE_FLOAT, "fund_per_point": TYPE_FLOAT, "max_fund_points": TYPE_FLOAT, "max_fund": TYPE_INT, "bypass_cost": TYPE_INT, "shore_power_cost": TYPE_INT, "houses": TYPE_INT, "houses_per_job": TYPE_FLOAT},
	# Scenarios (M11, see Scenario): a set game's map, days, start money, rule
	# changes ({"path": "a.b.c", "value"}), goals and kept conditions
	# ({"kind", "count"}), and the last day each medal is won by.
	"scenarios": {"*": {"name": TYPE_STRING, "blurb": TYPE_STRING, "map": TYPE_STRING, "days": TYPE_FLOAT, "start_money": TYPE_FLOAT, "patch": TYPE_ARRAY, "goals": TYPE_ARRAY, "keep": TYPE_ARRAY, "medals": {"gold": TYPE_FLOAT, "silver": TYPE_FLOAT}}},
	"box_look": {"own_share": TYPE_FLOAT, "stripe_share": TYPE_FLOAT, "weathering": TYPE_FLOAT, "rust_share": TYPE_FLOAT, "reefer": TYPE_STRING, "rust": TYPE_STRING, "placard": TYPE_STRING, "lessors": TYPE_ARRAY},
	# An AGV (M11): bought at an AGV depot, driverless, so dear to buy and cheap to keep.
	"agv": {"cost": TYPE_INT, "speed": TYPE_FLOAT, "battery_hours": TYPE_FLOAT, "charge_hours": TYPE_FLOAT, "low_share": TYPE_FLOAT, "charger_cost": TYPE_INT, "max_chargers": TYPE_INT, "rack_cost": TYPE_INT, "safety_cells": TYPE_FLOAT},
	# Roads the player draws: lanes each way along the drawn direction, whether
	# lorries may use it (tractors and AGVs always may), and cost and daily upkeep per 4 m cell.
	# Roads meeting at a node must part by at least min_angle degrees; each is
	# trimmed back to clear its neighbours' edges, plus corner_cells. Lanes
	# beside one running the same way change over lane_change_cells at a
	# road's middle, where it leaves lane_change_clear_cells each side (the
	# longest vehicle and its standstill gap) clear of the next stop line.
	"junctions": {"min_angle": TYPE_FLOAT, "corner_cells": TYPE_FLOAT, "lane_change_cells": TYPE_FLOAT, "lane_change_clear_cells": TYPE_FLOAT},
	# The tightest a road of the type may curve, at its line, is min_radius_cells.
	# A ring type is the roundabout tool's: one-way round a centre, the roads joining it giving way.
	"road_types": {"*": {"name": TYPE_STRING, "forward": TYPE_INT, "backward": TYPE_INT, "lorries": TYPE_BOOL, "cost_per_cell": TYPE_INT, "upkeep_per_cell": TYPE_FLOAT, "speed_kmh": TYPE_FLOAT, "ring": TYPE_BOOL, "min_radius_cells": TYPE_FLOAT}},
	# Areas dragged along a road edge: how deep they reach from the road and
	# their shortest length, in 4 m cells, and cost and daily upkeep per cell.
	"area_types": {"*": {"name": TYPE_STRING, "kind": TYPE_STRING, "depth": TYPE_INT, "max_depth": TYPE_INT, "min_length": TYPE_INT, "cost_per_cell": TYPE_INT, "upkeep_per_cell": TYPE_FLOAT}},
	# Rail track the player draws, a graph of its own beside the roads: cost and
	# daily upkeep per 4 m cell, and how many cells south of the highway the
	# main line meets the site's east edge.
	# Trains: wagons, one box each; minutes between trains to each rail block;
	# minutes one waits at its siding for imports falling due unless its wagons
	# fill first; metres a vehicle second. The rail discount the player may offer per box
	# by train, up to `max` dollars, adds share_per_dollar to every line's
	# rail_share, up to max_share.
	# Each dollar of the port's barge discount books share_per_dollar more of
	# every line's boxes for places up the river onto barges, up to max_share.
	"barge": {"discount": {"max": TYPE_INT, "share_per_dollar": TYPE_FLOAT, "max_share": TYPE_FLOAT}},
	"rail": {"name": TYPE_STRING, "cost_per_cell": TYPE_INT, "upkeep_per_cell": TYPE_FLOAT, "min_radius_cells": TYPE_FLOAT, "entry_offset": TYPE_INT, "train": {"wagons": TYPE_INT, "interval_minutes": TYPE_FLOAT, "dwell_minutes": TYPE_FLOAT, "speed": TYPE_FLOAT}, "discount": {"max": TYPE_INT, "share_per_dollar": TYPE_FLOAT, "max_share": TYPE_FLOAT}},
	# Off-map places boxes come from and go to: each box's share, and its
	# distance by road, rail and barge up the river (0 for no link).
	"hinterland": {"places": {"*": {"name": TYPE_STRING, "share": TYPE_FLOAT, "road_km": TYPE_FLOAT, "rail_km": TYPE_FLOAT, "barge_km": TYPE_FLOAT}}},
	# Berths the player places on the coast: a quay apron `length` cells long
	# with its road along its back, and STS crane spots evenly along it. A
	# berth's key is also what milestones unlock it by (its ship class's name).
	"berths": {"*": {"name": TYPE_STRING, "length": TYPE_INT, "crane_spots": TYPE_INT}},
	# Yard machines on areas: travel speed in m/s, seconds to lift and to set
	# down a box, one machine per so many bays of an area, and how high they stack.
	# An automated gear (ASC) is bought at cost_per_machine when a block takes it, and ramps up after (automation).
	"yard_gear": {"*": {"name": TYPE_STRING, "wind_limit_kmh": TYPE_FLOAT, "mtbf_hours": TYPE_FLOAT, "upkeep_per_machine": TYPE_INT, "speed": TYPE_FLOAT, "lift_seconds": TYPE_FLOAT, "set_down_seconds": TYPE_FLOAT, "bays_per_machine": TYPE_INT, "tiers": TYPE_INT, "empties_only": TYPE_BOOL, "carries": TYPE_BOOL, "automated": TYPE_BOOL, "cost_per_machine": TYPE_INT}},
	# A newly automated block's machines work at a pace from ramp_up, [days
	# since it was automated, pace] points in day order (1 is its gear's own
	# times), between points in a straight line, the last held. Each automated
	# block's IT systems cost it_upkeep_per_block a day.
	"automation": {"ramp_up": TYPE_ARRAY, "it_upkeep_per_block": TYPE_INT},
	# Port-wide policies the player switches on: each costs cost_per_day while
	# on and sets the sim parameters in effects (keys of POLICY_EFFECTS); no
	# two policies set the same one.
	"policies": {"*": {"name": TYPE_STRING, "text": TYPE_STRING, "cost_per_day": TYPE_INT, "effects": {"*": TYPE_FLOAT}}},
}

## Every sim parameter a policy may set (see PortSim.policy_value).
const POLICY_EFFECTS := ["gate_open_from", "gate_open_to", "gate_upkeep_factor", "quay_work_from", "quay_work_to", "labour_upkeep_factor", "appointment_share", "dual_cycling"]

## What an area type does; several types may share a kind, as gates of different sizes do.
const AREA_KINDS := ["yard_block", "quay_apron", "gate", "depot", "parking", "workshop", "fire_station", "agv_depot", "transfer_block", "tree_belt"]

# Keys the sim divides by or repeats on; zero or less would hang or spin it.
const POSITIVE := ["min_radius_cells", "width", "tiers", "lift_seconds", "set_down_seconds", "bays_per_machine", "depth", "min_length", "year_days", "metres", "maintenance_days", "amount", "days", "per_20ft", "forty_factor", "min_dwell_factor", "offer_check_minutes", "window_hours", "sensitivity", "ship_speed", "half_width", "pocket", "spacing", "max_wait_hours", "boat_speed", "lorry_interval_minutes", "export_lorry_interval_minutes", "lorry_speed", "give_up_seconds", "length", "crane_spots", "demand", "wagons", "interval_minutes", "rate", "crane_interference", "speed", "minutes"]

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


## A copy of `rules` on a site of `site`'s size, its maps drawn to scale:
## a save keeps the site it was made on (the game's grew in M11).
static func on_site(rules: Dictionary, site: Dictionary) -> Dictionary:
	var copy := rules.duplicate(true)
	var scale: float = site.width / rules.site.width
	var scaled := func(points: Array) -> Array: return points.map(func(p: Array) -> Array: return [p[0] * scale, p[1] * scale])
	copy.site = site.duplicate()
	for map: Dictionary in copy.maps.values():
		map.land = scaled.call(map.land)
		map.islands = map.islands.map(func(island: Array) -> Array: return scaled.call(island))
		for river: Dictionary in map.rivers:
			river.points = scaled.call(river.points)
	return copy


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
	if rules.site.width % rules.land.metres != 0 or rules.site.height % rules.land.metres != 0:
		return {"error": "land.metres: land tiles must divide the site exactly"}
	if rules.map not in rules.maps:
		return {"error": "map: unknown map \"%s\"" % rules.map}
	for key: String in rules.maps:
		var err := _map_error(rules.maps[key], rules.site)
		if err:
			return {"error": "maps.%s.%s" % [key, err]}
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
	for key: String in rules.scenarios:
		var err := _scenario_error(rules, rules.scenarios[key])
		if err:
			return {"error": "scenarios.%s.%s" % [key, err]}
	var shares := 0.0
	for place: Dictionary in rules.hinterland.places.values():
		shares += place.share
	if not is_equal_approx(shares, 1.0):
		return {"error": "hinterland.places: shares must add up to 1"}
	var ramp: Array = rules.automation.ramp_up
	if ramp.is_empty() or not ramp.all(func(p: Variant) -> bool: return p is Array and p.size() == 2 and p.all(func(v: Variant) -> bool: return (v is float or v is int) and v >= 0) and p[1] > 0):
		return {"error": "automation.ramp_up: [days, pace] points, pace above zero"}
	for i in range(1, ramp.size()):
		if ramp[i][0] <= ramp[i - 1][0]:
			return {"error": "automation.ramp_up: days must rise"}
	if policies_error(rules.policies):
		return {"error": policies_error(rules.policies)}
	return {"rules": rules}


## Why `policies` can't all stand, or "": each sets only parameters the sim
## reads, and none sets one another does, so switching one changes exactly its own.
static func policies_error(policies: Dictionary) -> String:
	var set_by := {}
	for policy: String in policies:
		for key: String in policies[policy].effects:
			if key not in POLICY_EFFECTS:
				return "policies.%s.effects: the sim reads no \"%s\"" % [policy, key]
			if key in set_by:
				return "policies.%s.effects: \"%s\" is already set by %s" % [policy, key, set_by[key]]
			set_by[key] = policy
	return ""


## Why `scenario` won't play under `rules`, or "": its map is known, every
## patched path is a rule already, every goal and kept condition a known
## kind, and its medals fall within its days.
static func _scenario_error(rules: Dictionary, scenario: Dictionary) -> String:
	if scenario.map not in rules.maps and not (scenario.map.begins_with(MapGen.PREFIX) and scenario.map.trim_prefix(MapGen.PREFIX).is_valid_int()):
		return "map: unknown map \"%s\"" % scenario.map
	for change: Variant in scenario.patch:
		if not (change is Dictionary and change.get("path") is String and change.has("value")):
			return "patch: each change needs a path and a value"
		var at: Variant = rules
		for part: String in change.path.split("."):
			if not (at is Dictionary and at.has(part)):
				return "patch: no rule %s" % change.path
			at = at[part]
		if typeof(at) != typeof(change.value):
			return "patch: %s must stay the same type" % change.path
	for goal: Variant in scenario.goals + scenario.keep:
		if not (goal is Dictionary and goal.get("kind") in Scenario.GOALS and goal.get("count") is float):
			return "goals: each needs a kind (one of %s) and a count" % [Scenario.GOALS]
	if scenario.goals.is_empty():
		return "goals: needs at least one"
	if not (scenario.medals.gold <= scenario.medals.silver and scenario.medals.silver <= scenario.days):
		return "medals: gold by silver by the last day"
	return ""


## Why `map` isn't a coast on `site`, or "": polygons of at least three
## points, rivers of at least two, every point an [x, y] pair on the site,
## and land where the highway comes in on the east edge.
static func _map_error(map: Dictionary, site: Dictionary) -> String:
	var shapes: Array = [["land", map.land]]
	for island: Variant in map.islands:
		shapes.append(["islands", island])
	for shape: Array in shapes:
		if not shape[1] is Array or shape[1].size() < 3:
			return "%s: a polygon needs at least 3 points" % shape[0]
		for point: Variant in shape[1]:
			if not _on_site(point, site):
				return "%s: %s is not an [x, y] point on the site" % [shape[0], point]
	for river: Variant in map.rivers:
		if not (river is Dictionary and river.get("points") is Array and river.points.size() >= 2 and river.get("width") is float and river.get("depth") is float and river.width > 0.0 and river.depth > 0.0):
			return "rivers: each needs points (at least 2), a width and a depth above zero"
		for point: Variant in river.points:
			if not _on_site(point, site):
				return "rivers: %s is not an [x, y] point on the site" % [point]
	var size := Grid.size(site)
	var coast := Coast.of(map, site)
	if coast.is_water(Vector2i(size.x - 1, size.y / 2)):
		return "land: the highway's entry on the east edge must be land"
	return ""


static func _on_site(point: Variant, site: Dictionary) -> bool:
	return point is Array and point.size() == 2 and point.all(func(v: Variant) -> bool: return v is float or v is int) and point[0] >= 0 and point[1] >= 0 and point[0] <= site.width and point[1] <= site.height


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
	if want == TYPE_ARRAY:
		return "" if got is Array else "%s: must be a list" % where
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
