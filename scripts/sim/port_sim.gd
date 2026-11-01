class_name PortSim
extends RefCounted
## The port. Ships call at berths. Quay cranes lift their imports onto
## terminal tractors, which carry them to import blocks where yard machines
## stack them; after their dwell, lorries from the highway collect them.
## Lorries also bring exports to export blocks; once a ship is discharged,
## tractors fetch exports to its cranes, which load them. Lines pay per crane
## move; boxes held past their free days pay storage. Changed only through
## apply(command) and tick().

## Every tunable number, from data/base/*.json; see Content.
var rules: Dictionary
var clock := SimClock.new()
## The only source of randomness in the sim, so a seed and a command log replay exactly.
var rng := RandomNumberGenerator.new()
## Every change of cash goes through it; see Ledger.
var ledger: Ledger
var money: int:
	get:
		return ledger.cash
## Boxes through the highway: imports out and exports in.
var delivered := 0
## Of those, the ones that left by train.
var by_rail := 0
## Dollars off each box carried by train, to shift lines' boxes onto rail.
var rail_discount := 0
## Today's reefer power: the peak kW and the kWh drawn so far, billed at midnight.
var power := {"peak_kw": 0.0, "kwh": 0.0}
## Shipping lines, their services and offers, and their reputation of the port.
var contracts: Contracts
## Loans and the bailout.
var finance: Finance
## Land tiles (rules.land.metres square) the port owns, as tile coordinates;
## roads and areas are built only on land it owns.
var land := {}
## The map the port is on, a key of rules.maps; its coast is areas.coast.
var map: String
## The ship lanes drawn on the water.
var ship_lanes: ShipLanes
## Anchorages on the water, where ships wait for a berth: id -> {"from",
## "to": opposite corner cells}.
var anchorages := {}
var _next_anchorage := 1
## Pilot stations and tug depots on the water: id -> {"cell", "pilots"} and
## id -> {"cell", "tugs"}, numbered together.
var pilot_stations := {}
var tug_depots := {}
var _next_station := 1
## Narrow lanes booked by ships: [{"segment", "from", "to" (calendar
## minutes), "ship" (its id)}], see Marine.clear.
var passages: Array[Dictionary] = []
var _next_ship := 1
## Metres dredged in each quay apron's pocket: apron -> metres.
var pocket_dredged := {}
## Bumped by every dredge, so ship routes are found again.
var dredge_version := 0
var _ship_routes := {}  # [kind, apron] -> lane ends in cells, see Marine.route
var _ship_routes_for := []
## STS cranes ordered and not yet delivered: {"cell", "due" (calendar minute)}.
var crane_orders: Array[Dictionary] = []
## TEU moved across the quay so far; milestones unlock content as it grows.
var teu_handled := 0
## This game year's calls so far: {"calls", "berth_hours", "moves", "turns", "turn_minutes"}.
var year := {}
## Closed years, oldest first: {"year", "port_hours", "moves_per_hour", "turn_minutes"}.
var scoreboard: Array[Dictionary] = []
## Creative mode: cash never limits building and there are no bailouts; the
## ledger still records everything.
var creative := false
## Things worth telling the player, newest last: {"minute", "text"}. A
## message repeated tick after tick is kept once.
var events: Array[Dictionary] = []
## The latest ships to sail: {"kind", "line", "moves", "hours", "cranes", "late"}, newest last.
var ship_log: Array[Dictionary] = []
## Boxes through the gate in the last full game day.
var delivered_yesterday := 0
var ships: Array[Ship] = []
var cranes: Array[Crane] = []
## Lorries and tractors on roads and areas, moved by the area flow. They
## come and go only through _add_vehicle and _drop_vehicle, which keep the
## indexes below; those aren't saved, and a load builds them again.
var vehicles: Array[Vehicle] = []
var _by_id := {}  # vehicle id -> Vehicle
var _tractors_on_road := 0
var _fetching := {}  # apron slot cell -> tractors fetching exports to it, oldest first
var _lorries_bound := {}  # area id -> lorries whose area it is
## Trains on the way to, at, or leaving the rail blocks; see RailFlow.
var trains: Array[Train] = []
var _next_train := 1
## Calendar minutes until each rail block's next train.
var _until_train := {}
## RailFlow.rail_blocks, kept for the area, road and rail versions in _rail_blocks_for; not saved.
var _rail_blocks := {}
var _rail_blocks_for := Vector3i(-1, -1, -1)
## The area flow's state: who holds each lane cell, each area's handover
## slots and queues, the yard machines and what each is carrying, and the
## boxes stacked in each yard block (area id -> AreaStacks).
var lane_traffic: LaneTraffic
var handovers: Handovers
var machines: Machines
var machine_jobs := {}
var area_stacks := {}
## The areas version yard machines were last fitted to; not saved, so a
## loaded port refits once, which adds nothing.
var _machines_fit_for := -1
func _dg_refusal() -> String:
	return "A dangerous-goods block stands %d m from other yard blocks" % Grid.metres(rules.special_boxes.dg_distance)


## The road a berth brings along its back.
const BERTH_ROAD := "terminal_1_1"
## How far past an apron's deepest reach a berth click looks for the water, in cells.
const BERTH_SEARCH := 30
## A pilot station or tug depot stands within this many cells of land, and
## at least MARINE_BASE_GAP cells from another.
const MARINE_BASE_SHORE := 10
const MARINE_BASE_GAP := 8
## The rules each kind of area takes, and what a new one starts with.
const AREA_SETTINGS := {
	"yard_block": {"role": "import", "gear": "reach_stacker", "lines": []},
	"quay_apron": {"lines": []},
	"gate": {"level": "manual", "slots_per_hour": 0},
}
const AREA_ROLES: Array[String] = ["import", "export", "empty", "reefer", "dangerous"]
## The most lorries a gate can book in an hour.
const MAX_SLOTS_PER_HOUR := 120
## The roads drawn on the 4 m grid, and the lanes routed over them.
var roads: RoadNet
## Rail track, a graph of its own: where it crosses a road straight across,
## the cells are level crossings, in both.
var rails: RoadNet
var lanes: LaneGraph
## The areas dragged along those roads.
var areas: Areas
## Every box in the port by id: {"kind": "import", "export" or "empty", "due": the
## calendar minute an import may leave, "teu": 1 or 2 (20 or 40 ft),
## "reefer": bool, "in": the calendar minute it was stacked, or -1, "line":
## the line that owns it, a key of rules.lines, or "" for an export not yet
## loaded, "rail": whether it is booked to leave by train, "place": the
## hinterland place it goes to or comes from, a key of rules.hinterland.places}. A box is always in exactly one place: on a vehicle or in a yard
## stack (boxes on ships are only counted).
var boxes := {}
## How many of `boxes` are exports; not saved, counted again on load.
var exports := 0
## Terminal tractors owned. Those not on the road are parked beside the quay.
var tractors := 0
## Lorries that gave up on a traffic jam and left; see AreaFlow.
var gave_up := 0
## Gate-in to gate-out minutes of the latest lorries, newest last.
var turn_times: Array[float] = []
## The same per terminal, by the terminal of the gate a lorry left by.
var terminal_turns := {}  # terminal -> [minutes], newest last
## Minutes the latest collected imports spent in the yard, newest last.
var dwell_times: Array[float] = []
## The player's storage terms: free days (0-3) and the fee per box per day after them.
var storage := {}
## Empties on their way back from the hinterland, soonest first: {"at": the
## calendar minute one comes, "line", "teu"}.
var returning: Array[Dictionary] = []
## Empties out with exporters being packed, soonest back first: {"at": the
## calendar minute each comes back full}.
var stuffing: Array[Dictionary] = []
## Lorries booked in at gates taking bookings: gate id -> {hour of the
## calendar: lorries booked}, for this hour and those ahead.
var bookings := {}

## Boxes a vehicle is already coming for.
var _claimed := {}
## Calendar minutes until the next import lorry and export lorry.
var _until_lorry := 0.0
var _until_export := 0.0
var _until_empty := 0.0
var _next_vehicle := 1
var _next_box := 1
var _delivered_at_midnight := 0
## Ships that have left, and the departures and road and area versions when
## anchored ships last looked for a berth. A berth frees only when one of
## these changes, so until then looking again would find nothing; a new
## arrival resets it to look once.
var _departures := 0
var _berths_seen := Vector2i(-1, -1)


func _init(seed_value := 0, game_rules := Content.base(), creative_mode := false) -> void:
	rules = game_rules
	creative = creative_mode
	roads = RoadNet.new(rules.road_types)
	roads.anchors = [site_entry_point()]
	rails = RoadNet.new(rail_types())
	rails.anchors = [site_rail_entry()]
	lanes = LaneGraph.new(roads)
	lanes.rails = rails
	map = rules.map
	areas = Areas.new(rules.area_types, roads, Coast.of(rules.maps[map], rules.site))
	lanes.areas = areas
	lane_traffic = LaneTraffic.new(lanes, Junctions.new(rules.traffic))
	handovers = Handovers.new(areas)
	machines = Machines.new(rules.yard_gear)
	ledger = Ledger.new(rules.ledger_categories, rules.start_money)
	contracts = Contracts.new(rules)
	finance = Finance.new(rules)
	year = _new_year()
	ship_lanes = ShipLanes.new(rules.water.lanes)
	var start: Dictionary = rules.land.start
	for x in range(start.x, start.x + start.width):
		for y in range(start.y, start.y + start.height):
			land[Vector2i(x, y)] = true
	storage = {"free_days": rules.storage.free_days, "fee": rules.storage.fee}
	rng.seed = seed_value
	_event("Place a berth on the coast, then draw a road from the highway to it and add a gate and a yard block along it")


class Ship:
	## ANCHORED: waiting for a berth, at an anchorage or (anchorage 0) out at
	## sea off the map; ANCHORING: sailing in to an anchorage.
	enum State { ARRIVING, WORKING, LEAVING, ANCHORED, ANCHORING }
	## Its class, a key of rules.ship_classes.
	var kind: String
	## Its line, a key of rules.lines.
	var line: String
	## The calendar minute its berth window closes; sailing later is late.
	var due: float
	## The quay apron it lies along (0 while anchored), and the cell along the
	## apron its length starts at.
	var apron := 0
	var from := 0
	## The berth its service calls at (0: any), and whether it takes another
	## berth when that one is busy.
	var berth := 0
	var any_berth := true
	## Import boxes still on board, and exports it still has room for.
	var boxes: int
	var exports: int
	## Room left for its line's empties, loaded after its exports.
	var empties := 0
	var state := State.ARRIVING
	## Its number, from the port's count of calls (0 for ships tests add by hand).
	var id := 0
	## Whether it calls light-loaded, with its class's light_share of its
	## load, sitting at its light draft, because no berth has water for its
	## full draft.
	var light := false
	## Whether it has clearance to sail its course (see Marine.clear), with a
	## pilot aboard and `tugs` tugs from depot `tug_depot` arriving at the
	## calendar minute `tugs_at`; it may not move before `hold_until`.
	var cleared := false
	var pilot := false
	var tugs := 0
	var tug_depot := 0
	var tugs_at := 0.0
	var hold_until := 0.0
	## The anchorage it waits at (0: none, out at sea) and its spot there, an
	## index into Marine.spots; and the calendar minute it arrived.
	var anchorage := 0
	var spot := -1
	var arrived := 0.0
	## Its course in cells, from the open sea along the lanes to alongside
	## its berth; set when it is given a berth.
	var path: Array[Vector2] = []
	## How far along `path`: 0 out at sea, 1 alongside the quay.
	var sail := 0.0
	## `sail` at the start of this tick, for drawing between ticks.
	var prev_sail := 0.0
	## Boxes moved so far, and the calendar minute it berthed (-1 before).
	var moves := 0
	var berthed := -1.0

	func _init(ship_kind: String, ship_line: String, window_end: float, imports: int, export_room: int) -> void:
		kind = ship_kind
		line = ship_line
		due = window_end
		boxes = imports
		exports = export_room
		state = State.ANCHORED

	func to_dict() -> Dictionary:
		return {"kind": kind, "line": line, "due": due, "boxes": boxes, "exports": exports, "empties": empties, "state": state, "id": id, "light": light, "cleared": cleared, "pilot": pilot, "tugs": tugs, "tug_depot": tug_depot, "tugs_at": tugs_at, "hold_until": hold_until, "anchorage": anchorage, "spot": spot, "arrived": arrived, "path": path.duplicate(), "sail": sail, "prev_sail": prev_sail, "moves": moves, "berthed": berthed, "apron": apron, "from": from, "berth": berth, "any_berth": any_berth}

	static func from_dict(d: Dictionary) -> Ship:
		var ship := Ship.new(d.kind, d.line, d.due, d.boxes, d.exports)
		ship.empties = d.empties
		ship.state = d.state
		ship.id = d.id
		ship.light = d.light
		ship.cleared = d.cleared
		ship.pilot = d.pilot
		ship.tugs = d.tugs
		ship.tug_depot = d.tug_depot
		ship.tugs_at = d.tugs_at
		ship.hold_until = d.hold_until
		ship.anchorage = d.anchorage
		ship.spot = d.spot
		ship.arrived = d.arrived
		ship.path.assign(d.path)
		ship.sail = d.sail
		ship.prev_sail = d.prev_sail
		ship.moves = d.moves
		ship.berthed = d.berthed
		ship.apron = d.apron
		ship.from = d.from
		ship.berth = d.berth
		ship.any_berth = d.any_berth
		return ship


## A ship-to-shore crane on a quay apron's rails. It works the ship lying
## along its place, one box per move, to or from the tractor beneath it.
class Crane:
	## The quay apron it stands on, and how many cells along it.
	var apron := 0
	var along := 0
	## Its kind, a key of rules.sts_cranes.
	var kind := ""
	## Calendar minutes into the current move.
	var timer := 0.0
	## The tractor sent to it (a vehicle id), or 0.
	var tractor := 0

	func _init(on: int, at: int, of_kind: String) -> void:
		apron = on
		along = at
		kind = of_kind

	func to_dict() -> Dictionary:
		return {"timer": timer, "tractor": tractor, "apron": apron, "along": along, "kind": kind}

	static func from_dict(d: Dictionary) -> Crane:
		var crane := Crane.new(d.apron, d.along, d.kind)
		crane.timer = d.timer
		crane.tractor = d.tractor
		return crane


## Everything the sim needs to carry on exactly where it was, in plain types.
func to_dict() -> Dictionary:
	return {
		"roads": roads.to_dict(),
		"rails": rails.to_dict(),
		"areas": areas.to_dict(),
		"map": map,
		"ticks": clock.ticks,
		"rng_seed": rng.seed,
		"rng_state": rng.state,
		"ledger": ledger.to_dict(),
		"contracts": contracts.to_dict(),
		"finance": finance.to_dict(),
		"land": land.duplicate(),
		"teu_handled": teu_handled,
		"year": year.duplicate(),
		"scoreboard": scoreboard.duplicate(true),
		"ship_lanes": ship_lanes.to_dict(),
		"anchorages": anchorages.duplicate(true),
		"pilot_stations": pilot_stations.duplicate(true),
		"tug_depots": tug_depots.duplicate(true),
		"next_station": _next_station,
		"passages": passages.duplicate(true),
		"next_ship": _next_ship,
		"next_anchorage": _next_anchorage,
		"pocket_dredged": pocket_dredged.duplicate(),
		"dredge_version": dredge_version,
		"crane_orders": crane_orders.duplicate(true),
		"creative": creative,
		"delivered": delivered,
		"by_rail": by_rail,
		"rail_discount": rail_discount,
		"power": power.duplicate(),
		"trains": trains.map(func(train: Train) -> Dictionary: return train.to_dict()),
		"next_train": _next_train,
		"until_train": _until_train.duplicate(),
		"events": events.duplicate(true),
		"ship_log": ship_log.duplicate(true),
		"delivered_yesterday": delivered_yesterday,
		"delivered_at_midnight": _delivered_at_midnight,
		"ships": ships.map(func(ship: Ship) -> Dictionary: return ship.to_dict()),
		"cranes": cranes.map(func(crane: Crane) -> Dictionary: return crane.to_dict()),
		"vehicles": vehicles.map(func(vehicle: Vehicle) -> Dictionary: return vehicle.to_dict()),
		"boxes": boxes.duplicate(true),
		"tractors": tractors,
		"gave_up": gave_up,
		"turn_times": turn_times.duplicate(),
		"terminal_turns": terminal_turns.duplicate(true),
		"dwell_times": dwell_times.duplicate(),
		"storage": storage.duplicate(),
		"claimed": _claimed.duplicate(),
		"until_lorry": _until_lorry,
		"until_export": _until_export,
		"until_empty": _until_empty,
		"returning": returning.duplicate(true),
		"stuffing": stuffing.duplicate(true),
		"bookings": bookings.duplicate(true),
		"next_vehicle": _next_vehicle,
		"next_box": _next_box,
		"lane_traffic": lane_traffic.to_dict(),
		"handovers": handovers.to_dict(),
		"machines": machines.to_dict(),
		"machine_jobs": machine_jobs.duplicate(true),
		"area_stacks": _area_stacks_dict(),
	}


func _area_stacks_dict() -> Dictionary:
	var found := {}
	for area: int in area_stacks:
		found[area] = area_stacks[area].to_dict()
	return found


static func from_dict(d: Dictionary) -> PortSim:
	var sim := PortSim.new()
	sim.roads = RoadNet.from_dict(d.roads, sim.rules.road_types)
	sim.roads.anchors = [sim.site_entry_point()]
	sim.rails = RoadNet.from_dict(d.rails, sim.rail_types())
	sim.rails.anchors = [sim.site_rail_entry()]
	sim.lanes = LaneGraph.new(sim.roads)
	sim.lanes.rails = sim.rails
	sim.map = d.map
	sim.areas = Areas.from_dict(d.areas, sim.rules.area_types, sim.roads, Coast.of(sim.rules.maps[sim.map], sim.rules.site))
	sim.lanes.areas = sim.areas
	sim.clock.ticks = d.ticks
	sim.rng.seed = d.rng_seed
	sim.rng.state = d.rng_state
	sim.ledger = Ledger.from_dict(d.ledger, sim.rules.ledger_categories)
	sim.contracts = Contracts.from_dict(d.contracts, sim.rules)
	sim.finance = Finance.from_dict(d.finance, sim.rules)
	sim.land = d.land.duplicate()
	sim.teu_handled = d.teu_handled
	sim.year = d.year.duplicate()
	sim.scoreboard.assign(d.scoreboard)
	sim.ship_lanes = ShipLanes.from_dict(d.ship_lanes, sim.rules.water.lanes)
	sim.anchorages = d.anchorages.duplicate(true)
	sim.pilot_stations = d.pilot_stations.duplicate(true)
	sim.tug_depots = d.tug_depots.duplicate(true)
	sim._next_station = d.next_station
	sim.passages.assign(d.passages.duplicate(true))
	sim._next_ship = d.next_ship
	sim._next_anchorage = d.next_anchorage
	sim.pocket_dredged = d.pocket_dredged.duplicate()
	sim.dredge_version = d.dredge_version
	sim.crane_orders.assign(d.crane_orders)
	sim.creative = d.creative
	sim.delivered = d.delivered
	sim.by_rail = d.by_rail
	sim.rail_discount = d.rail_discount
	sim.power = d.power.duplicate()
	for train: Dictionary in d.trains:
		sim.trains.append(Train.from_dict(train))
	sim._next_train = d.next_train
	sim._until_train = d.until_train.duplicate()
	sim.events.assign(d.events)
	sim.ship_log.assign(d.ship_log)
	sim.delivered_yesterday = d.delivered_yesterday
	sim._delivered_at_midnight = d.delivered_at_midnight
	for ship: Dictionary in d.ships:
		sim.ships.append(Ship.from_dict(ship))
	for crane: Dictionary in d.cranes:
		sim.cranes.append(Crane.from_dict(crane))
	sim.boxes = d.boxes.duplicate(true)
	sim.exports = sim.boxes.values().filter(func(box: Dictionary) -> bool: return box.kind == "export").size()
	sim.tractors = d.tractors
	sim.gave_up = d.gave_up
	sim.turn_times.assign(d.turn_times)
	sim.terminal_turns = d.terminal_turns.duplicate(true)
	sim.dwell_times.assign(d.dwell_times)
	sim.storage = d.storage.duplicate()
	sim._claimed = d.claimed.duplicate()
	sim._until_lorry = d.until_lorry
	sim._until_export = d.until_export
	sim._until_empty = d.until_empty
	sim.returning.assign(d.returning)
	sim.stuffing.assign(d.stuffing)
	sim.bookings = d.bookings.duplicate(true)
	sim._next_vehicle = d.next_vehicle
	sim._next_box = d.next_box
	for data: Dictionary in d.vehicles:
		sim._add_vehicle(Vehicle.from_dict(data))
	sim.lane_traffic = LaneTraffic.from_dict(d.lane_traffic, sim.lanes, sim.rules.traffic)
	sim._weigh_routes()
	sim.handovers = Handovers.from_dict(d.handovers, sim.areas)
	sim.machines = Machines.from_dict(d.machines, sim.rules.yard_gear)
	sim.machine_jobs = d.machine_jobs.duplicate(true)
	for area: int in d.area_stacks:
		sim.area_stacks[area] = AreaStacks.from_dict(d.area_stacks[area])
	return sim


## Identical for identical states; used by the replay and save tests.
func state_hash() -> int:
	return hash(var_to_bytes(to_dict()))


## The one way the player changes the sim. Applied between ticks, so a
## command log tagged with tick numbers replays exactly. Returns why it was
## refused, or "".
func apply(command: Dictionary) -> String:
	match command.get("op"):
		"place_sts":
			return place_sts(command.apron, command.along, command.kind)
		"buy_tractors":
			return buy_tractors(command.count)
		"accept_offer":
			return accept_offer(command.id, command.apron)
		"move_service":
			return move_service(command.id, command.apron)
		"set_any_berth":
			return contracts.set_any_berth(command.id, command.any_berth)
		"decline_offer":
			return contracts.decline(command.id)
		"cancel_service":
			return cancel_service(command.id)
		"set_storage":
			return set_storage(command.free_days, command.fee)
		"set_rail_discount":
			return set_rail_discount(command.dollars)
		"take_loan":
			var locked := lock_error("loans")
			return locked if locked else finance.take_loan(command.kind, clock.calendar_minutes(), ledger)
		"buy_land":
			return buy_land(command.tile)
		"dredge_lane":
			return dredge_lane(command.segment, command.metres)
		"dredge_berth":
			return dredge_berth(command.apron, command.metres)
		"build_ship_lane":
			return build_ship_lane(command.from, command.to, command.type)
		"remove_ship_lane":
			return remove_ship_lane(command.segment)
		"widen_ship_lane":
			return widen_ship_lane(command.segment)
		"build_anchorage":
			return build_anchorage(command.from, command.to)
		"remove_anchorage":
			return remove_anchorage(command.id)
		"build_pilot_station":
			return build_marine_base("pilot_station", command.cell)
		"build_tug_depot":
			return build_marine_base("tug_depot", command.cell)
		"hire_pilots":
			return add_marine_craft(command.station, command.count)
		"buy_tugs":
			return add_marine_craft(command.depot, command.count)
		"remove_marine_base":
			return remove_marine_base(command.id)
		"build_road":
			return build_road(command.from, command.to, command.type)
		"build_rail":
			return build_rail(command.from, command.to)
		"remove_rail":
			return remove_rail(command.segment)
		"remove_road":
			return remove_road(command.segment)
		"change_road":
			return change_road(command.segment, command.type)
		"set_signals":
			return lane_traffic.junctions.set_signals(lanes, command.point, command.on)
		"set_green":
			return lane_traffic.junctions.set_green(command.point, command.phase, command.seconds)
		"set_sign":
			return lane_traffic.junctions.set_sign(lanes, command.point, command.arm, command.sign)
		"build_area":
			return build_area(command.type, command.segment, command.side, command.from, command.to)
		"build_berth":
			return build_berth(command.kind, command.cell)
		"build_two_way_gate":
			return build_two_way_gate(command.type, command.segment, command.from, command.to)
		"remove_area":
			return remove_area(command.id)
		"remove_sts":
			return remove_sts(command.apron, command.along)
		"set_area":
			return set_area(command.id, command.settings)
		"paint_terminal":
			return areas.paint_cells(command.cells, command.terminal)
		"fill_terminal":
			var cells := areas.fill_cells(command.cell)
			return areas.paint_cells(cells, command.terminal) if not cells.is_empty() else "No road closes in this ground"
		"name_terminal":
			return areas.name_terminal(command.terminal, command.name)
		"colour_terminal":
			return areas.colour_terminal(command.terminal)
	return "Unknown command: %s" % command.get("op")


## Where the highway meets the site: the middle of its east edge. A road
## with a lane on this cell connects the port to the outside world.
func site_entry() -> Vector2i:
	var size := Grid.size(rules.site)
	return Vector2i(size.x - 1, size.y / 2)


## The grid point on the site's east edge where the highway's line meets it,
## at the top-left corner of the entry cell's east neighbour: a road drawn to
## it runs in line with the highway, with a lane on the entry cell.
func site_entry_point() -> Vector2i:
	return site_entry() + Vector2i(1, 0)


## Why a road can't be built, or "": as though segment `skip` weren't built.
func build_road_error(from: Vector2i, to: Vector2i, type: String, skip := 0) -> String:
	var err := roads.add_error(from, to, type, skip)
	if err == "" and roads.footprint(from, to, type).any(areas.is_water):
		err = "Roads can't be built on water"
	if err == "" and not roads.footprint(from, to, type).all(owns):
		err = "Buy this land first"
	if err == "":
		var built := {}
		for id: int in areas.list:
			for cell in areas.cells(id):
				built[cell] = true
		if roads.footprint(from, to, type).any(func(c: Vector2i) -> bool: return c in built):
			err = "Something is already built here"
	if err == "":
		err = _crossing_error(RoadNet.line(from, to), roads.footprint(from, to, type), rails.segments.keys().map(func(s: int) -> Array: return rails.cells(s)))
	if err == "" and not _afford(road_price(from, to, type)):
		err = "Not enough money"
	return err


func build_road(from: Vector2i, to: Vector2i, type: String) -> String:
	var err := build_road_error(from, to, type)
	if err == "":
		ledger.post("construction", -road_price(from, to, type))
		roads.add(from, to, type)
	return err


## Why `segment` can't become a road of `type` in its place, or "".
func change_road_error(segment: int, type: String) -> String:
	if segment not in roads.segments:
		return "No road there"
	var road: Dictionary = roads.segments[segment]
	if road.type == type:
		return "This road is already a %s" % rules.road_types[type].name
	return build_road_error(roads.nodes[road.a], roads.nodes[road.b], type, segment)


## Rebuilds `segment` as a road of `type` on the same line, at the new
## type's full price, as Cities: Skylines upgrades a road.
func change_road(segment: int, type: String) -> String:
	var err := change_road_error(segment, type)
	if err == "":
		var road: Dictionary = roads.segments[segment]
		ledger.post("construction", -road_price(roads.nodes[road.a], roads.nodes[road.b], type))
		roads.retype(segment, type)
	return err


func road_price(from: Vector2i, to: Vector2i, type: String) -> int:
	return RoadNet.length(from, to) * rules.road_types[type].cost_per_cell


## Where the highway's rail line meets the site, `entry_offset` cells south
## of the road entry on the east edge. Track reaching it joins the main line.
func site_rail_entry() -> Vector2i:
	return site_entry() + Vector2i(0, rules.rail.entry_offset)


## Rail track as RoadNet sees it: one lane, on the drawn line.
func rail_types() -> Dictionary:
	var track: Dictionary = rules.rail
	return {"track": {"name": track.name, "forward": 1, "backward": 0, "lorries": false, "cost_per_cell": track.cost_per_cell, "upkeep_per_cell": track.upkeep_per_cell}}


func build_rail_error(from: Vector2i, to: Vector2i) -> String:
	var err := lock_error("rmg")
	if err == "":
		err = rails.add_error(from, to, "track")
	if err == "" and RoadNet.line(from, to).any(areas.is_water):
		err = "Track can't be laid on water"
	if err == "" and not RoadNet.line(from, to).all(owns):
		err = "Buy this land first"
	if err == "":
		var track := RoadNet.line(from, to)
		for id: int in areas.list:
			if areas.cells(id).any(func(c: Vector2i) -> bool: return c in track):
				return "Something is already built here"
		var lanes_of := []
		for id: int in roads.segments:
			for lane in roads.lanes(id):
				lanes_of.append(lane.cells)
		err = _crossing_error(track, track, lanes_of)
	if err == "" and not _afford(RoadNet.length(from, to) * rules.rail.cost_per_cell):
		err = "Not enough money"
	return err


func build_rail(from: Vector2i, to: Vector2i) -> String:
	var err := build_rail_error(from, to)
	if err == "":
		ledger.post("construction", -RoadNet.length(from, to) * rules.rail.cost_per_cell)
		rails.add(from, to, "track")
	return err


func set_rail_discount(dollars: int) -> String:
	var locked := lock_error("rmg")
	if locked:
		return locked
	if dollars < 0 or dollars > rules.rail.discount.max:
		return "The rail discount runs from $0 to $%d a box" % rules.rail.discount.max
	rail_discount = dollars
	return ""


## The share of `line`'s boxes booked to rail where a rail block can take
## them: its own share, plus what the rail discount buys, capped.
func rail_share(line: String) -> float:
	var discount: Dictionary = rules.rail.discount
	return minf(rules.lines[line].rail_share + rail_discount * discount.share_per_dollar, maxf(discount.max_share, rules.lines[line].rail_share))


func remove_rail(segment: int) -> String:
	if segment not in rails.segments:
		return "No track there"
	rails.remove(segment)
	return ""


## Why something drawn along `line`, covering `cells`, can't share cells with
## the runs in `others` (each a straight run of cells), or "": road and rail
## meet only at level crossings, straight across.
static func _crossing_error(line: Array, cells: Array, others: Array) -> String:
	var mine := {}
	for cell: Vector2i in cells:
		mine[cell] = true
	var along: Vector2i = (line[-1] - line[0]).sign()
	for other: Array in others:
		if not other.any(func(c: Vector2i) -> bool: return c in mine):
			continue
		var theirs: Vector2i = (other[-1] - other[0]).sign()
		var straight := along.x * along.y == 0 and theirs.x * theirs.y == 0
		if not straight or along.x * theirs.x + along.y * theirs.y != 0:
			return "Road and track cross only straight across"
	return ""


func remove_road(segment: int) -> String:
	if segment not in roads.segments:
		return "No road there"
	roads.remove(segment)
	return ""


func build_area_error(type: String, segment: int, side: int, from: int, to: int) -> String:
	var err := areas.add_error(type, segment, side, from, to)
	if err == "" and rules.area_types[type].kind == "yard_block" and AreaFlow.near_yard(self, areas.cells_of(type, segment, side, from, to), 0, "dangerous") != 0:
		err = _dg_refusal()
	if err == "" and not areas.cells_of(type, segment, side, from, to).all(owns):
		err = "Buy this land first"
	if err == "":
		var track := {}
		for id: int in rails.segments:
			for cell in rails.cells(id):
				track[cell] = true
		if areas.cells_of(type, segment, side, from, to).any(func(c: Vector2i) -> bool: return c in track):
			err = "Something is already built here"
	if err == "" and not _afford(area_price(type, segment, side, from, to)):
		err = "Not enough money"
	return err


func build_area(type: String, segment: int, side: int, from: int, to: int) -> String:
	var err := build_area_error(type, segment, side, from, to)
	if err == "":
		var price := area_price(type, segment, side, from, to)
		areas.add(type, segment, side, from, to, AREA_SETTINGS.get(rules.area_types[type].kind, {}).duplicate(true))
		ledger.post("construction", -price, areas.list[areas.list.keys().max()].terminal)
	return err


## Why a gate of `type` can't be built on both sides of `segment` from
## `from` to `to`, or "".
func build_two_way_gate_error(type: String, segment: int, from: int, to: int) -> String:
	if type not in rules.area_types or rules.area_types[type].kind != "gate":
		return "Only gates are built on both sides of a road"
	for side: int in [1, -1]:
		var err := build_area_error(type, segment, side, from, to)
		if err:
			return err
	if not _afford(area_price(type, segment, 1, from, to) + area_price(type, segment, -1, from, to)):
		return "Not enough money"
	return ""


## Where a berth of `kind` clicked at `cell` goes: {"line": its road's two
## grid points, "out": the way its quay faces, "cells": its apron's cells},
## or {"error"}. It faces the nearest water in the four directions; its quay
## is one straight wall at the most seaward land along it, and the apron
## reaches back from it to the road, filling the water behind the wall. The
## road runs so its right side faces the water, as long as the apron, so a
## berth placed end to end with another shares its road's end.
func berth_plan(kind: String, cell: Vector2i) -> Dictionary:
	var length: int = rules.berths[kind].length
	var depth: int = rules.area_types.quay_apron.depth
	var reach: int = rules.area_types.quay_apron.max_depth + BERTH_SEARCH
	var out := Vector2i.ZERO
	var nearest := reach + 1
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var steps := _to_water(cell, d, reach)
		if steps < nearest:
			nearest = steps
			out = d
	if out == Vector2i.ZERO:
		return {"error": "Click the coast: there's no water within %d m" % Grid.metres(reach)}
	var along := Vector2i(out.y, -out.x)
	var first := cell - along * (length / 2)
	var quay := 0
	for k in length:
		var steps := _to_water(first + along * k, out, reach * 2)
		if steps > reach * 2:
			return {"error": "The water isn't straight out from the whole berth here"}
		quay = maxi(quay, steps)
	var line := first + out * (quay - depth - 2)
	var cells: Array[Vector2i] = []
	for k in length:
		for r in range(quay - depth, quay):
			cells.append(first + along * k + out * r)
	return {"line": [line, line + along * length] as Array[Vector2i], "out": out, "cells": cells}


## Steps from `cell` along `step` to the first water, or more than `limit`.
func _to_water(cell: Vector2i, step: Vector2i, limit: int) -> int:
	var steps := 0
	while steps <= limit and not areas.is_water(cell + step * steps):
		steps += 1
	return steps


func build_berth_error(kind: String, cell: Vector2i) -> String:
	if kind not in rules.berths:
		return "Unknown berth: %s" % kind
	var locked := lock_error(kind)
	if locked:
		return locked
	var plan := berth_plan(kind, cell)
	if plan.has("error"):
		return plan.error
	var line: Array[Vector2i] = plan.line
	var cells: Array[Vector2i] = plan.cells
	if not cells.all(owns):
		return "Buy this land first"
	var built := {}
	for id: int in areas.list:
		for c in areas.cells(id):
			built[c] = true
	for segment: int in roads.segments:
		var road: Dictionary = roads.segments[segment]
		for c in roads.footprint(roads.nodes[road.a], roads.nodes[road.b], road.type):
			built[c] = true
	if cells.any(func(c: Vector2i) -> bool: return c in built):
		return "Something is already built here"
	# A road meeting the berth's road part-way would split it under the apron.
	var step: Vector2i = (line[1] - line[0]).sign()
	if roads.footprint(line[0] + step, line[1] - step, BERTH_ROAD).any(func(c: Vector2i) -> bool: return c in built):
		return "A road already runs here: place the berth clear of it, it brings its own"
	var err := build_road_error(line[0], line[1], BERTH_ROAD)
	if err:
		return err
	var water := cells.filter(areas.is_water).size()
	if not _afford(road_price(line[0], line[1], BERTH_ROAD) + cells.size() * rules.area_types.quay_apron.cost_per_cell + water * rules.reclaim.cost_per_cell):
		return "Not enough money"
	return ""


## Places a berth of `kind` clicked at `cell` (see berth_plan): its road,
## then its apron along the road's water side.
func build_berth(kind: String, cell: Vector2i) -> String:
	var err := build_berth_error(kind, cell)
	if err:
		return err
	var line: Array[Vector2i] = berth_plan(kind, cell).line
	build_road(line[0], line[1], BERTH_ROAD)
	# The road runs so its right, side 1, faces the water.
	err = build_area("quay_apron", roads.segment_at((line[0] + line[1]) / 2), 1, 0, rules.berths[kind].length - 1)
	assert(err == "", "a berth's apron fits where its error check said: %s" % err)
	return ""


## A gate of `type` on each side of `segment` over the same stretch, in one
## terminal: lorries check in on the side they arrive by and out on the side
## they leave by, so none turns round to pass a gate.
func build_two_way_gate(type: String, segment: int, from: int, to: int) -> String:
	var err := build_two_way_gate_error(type, segment, from, to)
	if err == "":
		build_area(type, segment, 1, from, to)
		build_area(type, segment, -1, from, to)
	return err


## An area's cells at its type's price, plus the water a quay apron fills.
func area_price(type: String, segment: int, side: int, from: int, to: int) -> int:
	var cells := areas.cells_of(type, segment, side, from, to)
	return cells.size() * rules.area_types[type].cost_per_cell + cells.filter(areas.is_water).size() * rules.reclaim.cost_per_cell


## shortcut: changing gear is free; machines are bought per area in M5 step 17.
func set_area_error(id: int, settings: Dictionary) -> String:
	if id not in areas.list:
		return "No area there"
	var type: String = areas.list[id].type
	for key: String in settings:
		if key not in AREA_SETTINGS.get(areas.kind_of(areas.list[id]), {}):
			return "A %s has no %s setting" % [rules.area_types[type].name.to_lower(), key]
	if settings.has("slots_per_hour") and (not settings.slots_per_hour is int or settings.slots_per_hour < 0 or settings.slots_per_hour > MAX_SLOTS_PER_HOUR):
		return "Bookings run from 0 (none) to %d an hour" % MAX_SLOTS_PER_HOUR
	if settings.has("level"):
		if not rules.gate_levels.has(settings.level):
			return "Unknown gate level: %s" % settings.level
		var level_locked := lock_error(settings.level)
		if level_locked:
			return level_locked
	if settings.has("role") and settings.role not in AREA_ROLES:
		return "Unknown yard role: %s" % settings.role
	if settings.get("role") == "reefer" and lock_error("reefers"):
		return lock_error("reefers")
	if settings.get("role") == "dangerous" and AreaFlow.near_yard(self, areas.cells(id), id, "") != 0:
		return _dg_refusal()
	if settings.has("gear"):
		if not rules.yard_gear.has(settings.gear):
			return "Unknown yard gear: %s" % settings.gear
		var locked := lock_error(settings.gear)
		if locked:
			return locked
	var role: String = settings.get("role", areas.list[id].settings.get("role", ""))
	var gear: String = settings.get("gear", areas.list[id].settings.get("gear", ""))
	if gear != "" and rules.yard_gear[gear].empties_only and role != "empty":
		var name: String = rules.yard_gear[gear].name
		return "%s only work empty blocks" % (name[0].to_upper() + name.substr(1))
	if settings.has("lines"):
		if not settings.lines is Array or not settings.lines.all(func(line: Variant) -> bool: return line is String and rules.lines.has(line)):
			return "Line priority lists known shipping lines"
	return ""


## Sets some of area `id`'s rules: a yard block's role, gear and the lines it
## favours; a quay apron's lines.
func set_area(id: int, settings: Dictionary) -> String:
	var err := set_area_error(id, settings)
	if err == "":
		areas.list[id].settings.merge(settings.duplicate(true), true)
		areas.version += 1
	return err


func remove_area(id: int) -> String:
	if id not in areas.list:
		return "No area there"
	AreaFlow.remove(self, id)
	return ""


## Orders an STS crane of `kind` for apron `apron`, `along` cells along its rails.
func place_sts(apron: int, along: int, kind: String) -> String:
	if kind not in rules.sts_cranes:
		return "Unknown crane: %s" % kind
	var err := lock_error(kind)
	if err == "":
		err = AreaFlow.sts_error(self, apron, along, kind)
	var spec: Dictionary = rules.sts_cranes[kind]
	if err == "" and not _afford(spec.cost):
		err = "Not enough money"
	if err == "":
		ledger.post("equipment", -spec.cost, areas.list[apron].terminal)
		crane_orders.append({"apron": apron, "along": along, "kind": kind, "due": clock.calendar_minutes() + spec.lead_days * SimClock.MINUTES_PER_DAY})
		_deliver_cranes()
	return err


## Takes down the crane standing `along` cells into apron `apron`, leaving
## the apron. Not while it works a ship, so no tractor is left serving it.
func remove_sts(apron: int, along: int) -> String:
	var err := remove_sts_error(apron, along)
	if err == "":
		cranes.erase(cranes.filter(func(c: Crane) -> bool: return c.apron == apron and c.along == along)[0])
	return err


func remove_sts_error(apron: int, along: int) -> String:
	var found := cranes.filter(func(c: Crane) -> bool: return c.apron == apron and c.along == along)
	if found.is_empty():
		return "No crane there"
	if ships.any(func(s: Ship) -> bool: return s.apron == apron and s.state != Ship.State.ANCHORED and found[0] in AreaFlow.cranes_for(self, s)):
		return "Wait for the ship alongside to sail"
	return ""


## Puts up the cranes whose order is due. One whose quay has gone is refunded.
func _deliver_cranes() -> void:
	var now := clock.calendar_minutes()
	for order: Dictionary in crane_orders.duplicate():
		if order.due > now:
			continue
		crane_orders.erase(order)
		if order.apron in areas.list:
			cranes.append(Crane.new(order.apron, order.along, order.kind))
			_event("A new %s is up on %s" % [rules.sts_cranes[order.kind].name, areas.terminal_name(areas.list[order.apron].terminal)], areas.list[order.apron].start)
		else:
			ledger.post("equipment", rules.sts_cranes[order.kind].cost)
			_event("A crane arrived with no quay apron to stand on; it went back, refunded")


## The land tile holding grid cell `cell`.
func land_tile(cell: Vector2i) -> Vector2i:
	# Floored, so a cell off the site's top or left edge is off its tiles too.
	var metres: float = rules.land.metres
	return Vector2i(floori(cell.x * Grid.CELL / metres), floori(cell.y * Grid.CELL / metres))


func owns(cell: Vector2i) -> bool:
	return land.has(land_tile(cell))


## The milestones reached so far, as indices into the data's list in TEU order.
func milestones_reached() -> int:
	var reached := 0
	for milestone in milestones():
		if teu_handled >= milestone.teu:
			reached += 1
	return reached


## Whether the milestones reached unlock `name` (a key of some milestone's unlocks).
func unlocked(name: String) -> bool:
	var milestones := milestones()
	for i in milestones.size():
		if milestones[i].unlocks.has(name):
			return i < milestones_reached()
	return true


## Why `name` can't be used yet, or "".
func lock_error(name: String) -> String:
	var milestones := milestones()
	for i in milestones.size():
		if milestones[i].unlocks.has(name) and i >= milestones_reached():
			return "Unlocked at milestone %d: %d TEU across the quay" % [i + 1, milestones[i].teu]
	return ""


## rules.milestones in TEU order.
func milestones() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.assign(rules.milestones.values())
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.teu < b.teu)
	return list


## Counts a crane move of `box` for `line` in `terminal`: the line pays for
## it, and milestones may unlock.
func _moved(box: Dictionary, line: String, terminal: int) -> void:
	ledger.post("moves", move_price(box), terminal)
	ledger.count_move(line, terminal, move_price(box))
	var before := milestones_reached()
	teu_handled += box.teu
	if milestones_reached() > before:
		var milestone: Dictionary = milestones()[before]
		_event("Milestone %d: %d TEU across the quay. Unlocked: %s" % [before + 1, milestone.teu, ", ".join(milestone.unlocks.values())])


func buy_land_error(tile: Vector2i) -> String:
	var locked := lock_error("land")
	if locked:
		return locked
	var tiles := Vector2i(ceili(rules.site.width / float(rules.land.metres)), ceili(rules.site.height / float(rules.land.metres)))
	if tile.x < 0 or tile.y < 0 or tile.x >= tiles.x or tile.y >= tiles.y:
		return "Off the site"
	if land.has(tile):
		return "The port owns this land already"
	if not _afford(rules.land.price):
		return "Not enough money"
	return ""


func buy_land(tile: Vector2i) -> String:
	var err := buy_land_error(tile)
	if err == "":
		ledger.post("land", -rules.land.price)
		land[tile] = true
	return err


## Why a ship lane of `type` can't run from `from` to `to`, or "".
func build_ship_lane_error(from: Vector2i, to: Vector2i, type: String) -> String:
	var err := ship_lanes.add_error(from, to, type, areas.is_water)
	if err == "" and not _afford(ship_lane_price(from, to, type)):
		err = "Not enough money"
	return err


func build_ship_lane(from: Vector2i, to: Vector2i, type: String) -> String:
	var err := build_ship_lane_error(from, to, type)
	if err == "":
		ledger.post("construction", -ship_lane_price(from, to, type))
		ship_lanes.add(from, to, type, areas.is_water)
	return err


## A lane's price: the water it covers, at its type's price a cell.
func ship_lane_price(from: Vector2i, to: Vector2i, type: String) -> int:
	return ship_lanes.footprint(from, to, type).size() * rules.water.lanes[type].cost_per_cell


## Why an anchorage can't cover the rectangle from `from` to `to`, or "".
func build_anchorage_error(from: Vector2i, to: Vector2i) -> String:
	var cells := anchorage_cells(from, to)
	if not cells.all(areas.is_water):
		return "An anchorage needs open water all over it"
	if Marine.spots_in(self, from, to).is_empty():
		return "Too small for a ship: at least %d m each way" % Grid.metres(rules.water.anchorage.spacing)
	for id: int in anchorages:
		if Rect2i(anchorages[id].from, anchorages[id].to - anchorages[id].from + Vector2i.ONE).intersects(Rect2i(from.min(to), (to - from).abs() + Vector2i.ONE)):
			return "Anchorages can't overlap"
	if not _afford(cells.size() * rules.water.anchorage.cost_per_cell):
		return "Not enough money"
	return ""


func build_anchorage(from: Vector2i, to: Vector2i) -> String:
	var err := build_anchorage_error(from, to)
	if err == "":
		ledger.post("construction", -anchorage_cells(from, to).size() * rules.water.anchorage.cost_per_cell)
		anchorages[_next_anchorage] = {"from": from.min(to), "to": from.max(to)}
		_next_anchorage += 1
	return err


## Why a pilot station or tug depot (`kind`) can't stand at `cell`, or "":
## on open water, near enough the shore for its boats' crews, clear of
## another base.
func build_marine_base_error(kind: String, cell: Vector2i) -> String:
	if not areas.is_water(cell):
		return "Pilot stations and tug depots stand on the water"
	if not _near_land(cell, MARINE_BASE_SHORE):
		return "Place it near the shore, within %d m of land" % Grid.metres(MARINE_BASE_SHORE)
	if marine_base_at(cell, MARINE_BASE_GAP):
		return "Too close to another pilot station or tug depot"
	var cost: int = rules.water.pilots.station_cost if kind == "pilot_station" else rules.water.tugs.depot_cost
	if not _afford(cost):
		return "Not enough money"
	return ""


func build_marine_base(kind: String, cell: Vector2i) -> String:
	var err := build_marine_base_error(kind, cell)
	if err == "":
		var pilots := kind == "pilot_station"
		ledger.post("construction", -(rules.water.pilots.station_cost if pilots else rules.water.tugs.depot_cost))
		if pilots:
			pilot_stations[_next_station] = {"cell": cell, "pilots": 0}
		else:
			tug_depots[_next_station] = {"cell": cell, "tugs": 0}
		_next_station += 1
	return err


## Hires `count` pilots at station `id`, or buys `count` tugs at depot `id`.
func add_marine_craft(id: int, count: int) -> String:
	if count < 1:
		return "Add at least one"
	var pilots := id in pilot_stations
	if not pilots and id not in tug_depots:
		return "No pilot station or tug depot there"
	var cost: int = count * (rules.water.pilots.pilot_cost if pilots else rules.water.tugs.tug_cost)
	if not _afford(cost):
		return "Not enough money"
	ledger.post("equipment", -cost)
	if pilots:
		pilot_stations[id].pilots += count
	else:
		tug_depots[id].tugs += count
	return ""


## Takes out pilot station or tug depot `id`, once none of its pilots or tugs is out with a ship.
func remove_marine_base(id: int) -> String:
	if id not in pilot_stations and id not in tug_depots:
		return "No pilot station or tug depot there"
	if id in tug_depots and ships.any(func(s: Ship) -> bool: return s.tugs > 0 and s.tug_depot == id):
		return "Wait for its tugs to come back"
	if id in pilot_stations and Marine.free_pilots(self) < pilot_stations[id].pilots:
		return "Wait for its pilots to come back"
	pilot_stations.erase(id)
	tug_depots.erase(id)
	return ""


## Whether land lies within `reach` cells of `cell`, along or across.
func _near_land(cell: Vector2i, reach: int) -> bool:
	for dx: int in range(-reach, reach + 1):
		for dy: int in range(-reach, reach + 1):
			var near := cell + Vector2i(dx, dy)
			if areas.coast.inside(near) and not areas.is_water(near):
				return true
	return false


## The pilot station or tug depot within `reach` cells of `cell`, or 0.
func marine_base_at(cell: Vector2i, reach := 2) -> int:
	for bases: Dictionary in [pilot_stations, tug_depots]:
		for id: int in bases:
			var d: Vector2i = (bases[id].cell - cell).abs()
			if d.x <= reach and d.y <= reach:
				return id
	return 0


## The anchorage covering `cell`, or 0.
func anchorage_at(cell: Vector2i) -> int:
	for id: int in anchorages:
		if Rect2i(anchorages[id].from, anchorages[id].to - anchorages[id].from + Vector2i.ONE).has_point(cell):
			return id
	return 0


## The cells of the rectangle from `from` to `to`, both corners included.
func anchorage_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
		for y: int in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			cells.append(Vector2i(x, y))
	return cells


## Takes out anchorage `id`; ships waiting there wait out at sea instead.
func remove_anchorage(id: int) -> String:
	if id not in anchorages:
		return "No anchorage there"
	for ship: Ship in ships:
		if ship.anchorage == id:
			ship.anchorage = 0
			ship.spot = -1
			ship.state = Ship.State.ANCHORED
			ship.path.clear()
	anchorages.erase(id)
	return ""


## Why narrow ship lane `segment` can't be widened, or "".
func widen_ship_lane_error(segment: int) -> String:
	if segment not in ship_lanes.segments:
		return "No ship lane there"
	var lane: Dictionary = ship_lanes.segments[segment]
	if lane.type == "wide":
		return "This lane is wide already"
	var a: Vector2i = ship_lanes.nodes[lane.a]
	var b: Vector2i = ship_lanes.nodes[lane.b]
	if not ship_lanes.footprint(a, b, "wide").all(areas.is_water):
		return "A wide lane needs open water %d m across all along" % Grid.metres(rules.water.lanes.wide.half_width * 2 + 1)
	if not _afford(ship_lane_price(a, b, "wide")):
		return "Not enough money"
	return ""


## Rebuilds narrow ship lane `segment` as a wide one, at the wide lane's full
## price, keeping what was dredged.
func widen_ship_lane(segment: int) -> String:
	var err := widen_ship_lane_error(segment)
	if err == "":
		var lane: Dictionary = ship_lanes.segments[segment]
		ledger.post("construction", -ship_lane_price(ship_lanes.nodes[lane.a], ship_lanes.nodes[lane.b], "wide"))
		lane.type = "wide"
		ship_lanes.version += 1
	return err


## Takes out ship lane `segment`. Ships already on their way keep their course.
func remove_ship_lane(segment: int) -> String:
	if segment not in ship_lanes.segments:
		return "No ship lane there"
	ship_lanes.remove(segment)
	return ""


## Deepens ship lane `segment` by whole metres, at a price for every cell of
## water it covers, up to water.dredge.max_depth.
func dredge_lane(segment: int, metres: int) -> String:
	if segment not in ship_lanes.segments:
		return "No ship lane there"
	var lane: Dictionary = ship_lanes.segments[segment]
	var cells := ship_lanes.footprint(ship_lanes.nodes[lane.a], ship_lanes.nodes[lane.b], lane.type).size()
	var err := _dredge_error(ship_lanes.depth(segment, areas.coast), metres, cells)
	if err == "":
		ledger.post("dredging", -metres * cells * rules.water.dredge.cost_per_cell_metre)
		lane.dredged += metres
		dredge_version += 1
	return err


## Deepens quay apron `apron`'s pocket by whole metres, as dredge_lane.
func dredge_berth(apron: int, metres: int) -> String:
	if apron not in areas.list or areas.kind_of(areas.list[apron]) != "quay_apron":
		return "No quay apron there"
	var cells := Marine.pocket(self, apron).size()
	var depth := Marine.pocket_depth(self, apron)
	if depth == 0.0:
		return "Land or a quay blocks this berth's water"
	var err := _dredge_error(depth, metres, cells)
	if err == "":
		ledger.post("dredging", -metres * cells * rules.water.dredge.cost_per_cell_metre)
		pocket_dredged[apron] = pocket_dredged.get(apron, 0.0) + metres
		dredge_version += 1
	return err


func _dredge_error(depth: float, metres: int, cells: int) -> String:
	var locked := lock_error("dredging")
	if locked:
		return locked
	if metres < 1:
		return "Dredge at least a metre"
	if depth + metres > rules.water.dredge.max_depth:
		return "Dredging goes no deeper than %.0f m" % rules.water.dredge.max_depth
	if not _afford(metres * cells * rules.water.dredge.cost_per_cell_metre):
		return "Not enough money"
	return ""


## Every cell and metre dredged, in the lanes and the berth pockets: what
## maintenance is charged on.
func dredged_cell_metres() -> float:
	var total := 0.0
	for segment: int in ship_lanes.segments:
		var lane: Dictionary = ship_lanes.segments[segment]
		total += lane.dredged * ship_lanes.footprint(ship_lanes.nodes[lane.a], ship_lanes.nodes[lane.b], lane.type).size()
	for apron: int in pocket_dredged:
		if apron in areas.list:
			total += pocket_dredged[apron] * Marine.pocket(self, apron).size()
	return total


func buy_tractors(count: int) -> String:
	if count < 1:
		return "Buy at least one tractor"
	if not _afford(rules.tractor.cost * count):
		return "Not enough money"
	ledger.post("equipment", -rules.tractor.cost * count)
	tractors += count
	return ""


## Whether the port can pay `amount` now: always, in creative mode.
func _afford(amount: int) -> bool:
	return creative or money >= amount


func set_storage(free_days: int, fee: int) -> String:
	if free_days < 0 or free_days > 3:
		return "Free days run from 0 to 3"
	if fee < 0 or fee > rules.storage.max_fee:
		return "The storage fee runs from $0 to $%d a day" % rules.storage.max_fee
	storage = {"free_days": free_days, "fee": fee}
	return ""


## What a crane move of `box` earns from the line: by size, plus a reefer premium.
func move_price(box: Dictionary) -> int:
	var price: float = rules.move_price.per_20ft * (rules.move_price.forty_factor if box.teu == 2 else 1.0)
	if box.kind == "empty":
		price *= rules.empties.price_factor
	return roundi(price) + (rules.move_price.reefer_premium if box.reefer else 0)


func tick() -> void:
	clock.tick()
	if clock.ticks % SimClock.TICKS_PER_DAY == 0:
		_end_of_day()
	if not crane_orders.is_empty():
		_deliver_cranes()
	for service in contracts.due(clock.ticks % (SimClock.TICKS_PER_DAY * 7)):
		_call(service)
	if clock.ticks % roundi(rules.contracts.offer_check_minutes / SimClock.CALENDAR_MINUTES_PER_TICK) == 0:
		_offer_service()
		AreaFlow.fine_unplugged(self, clock.calendar_minutes())
	_draw_power()
	var berths_now := Vector2i(_departures, areas.version + roads.version)
	for ship: Ship in ships.duplicate():
		if ship.state == Ship.State.ANCHORED and berths_now == _berths_seen:
			Marine.wait(self, ship)
			continue
		_work(ship)
	_berths_seen = berths_now
	_until_lorry -= SimClock.CALENDAR_MINUTES_PER_TICK
	if _until_lorry <= 0.0 and AreaFlow.dispatch_import_lorry(self):
		_until_lorry = rules.lorry_interval_minutes
	_until_export -= SimClock.CALENDAR_MINUTES_PER_TICK
	if _until_export <= 0.0 and AreaFlow.dispatch_export_lorry(self):
		_until_export = rules.export_lorry_interval_minutes
	_until_empty -= SimClock.CALENDAR_MINUTES_PER_TICK
	if _until_empty <= 0.0 and AreaFlow.dispatch_empty_lorry(self):
		_until_empty = rules.lorry_interval_minutes
	lane_traffic.junctions.tick(lanes, lane_traffic)
	AreaFlow.tick(self)
	RailFlow.tick(self)
	if clock.ticks % roundi(rules.traffic.epoch_seconds / SimClock.TICK_SECONDS) == 0:
		lane_traffic.settle(rules.traffic.smoothing)
	if clock.ticks % roundi(rules.traffic.route_epoch_seconds / SimClock.TICK_SECONDS) == 0:
		_weigh_routes()


## What the port costs to keep each day: roads, areas, cranes, tractors,
## yard machines and land.
func daily_upkeep() -> int:
	# Roads and areas cost a fraction of a dollar a cell, so parts are summed before rounding.
	var total := 0.0
	for part: float in upkeep_parts().values():
		total += part
	return roundi(total)


## A day's upkeep by terminal: each terminal's areas, the gates' lanes, yard
## machines and the cranes on its aprons; 0 holds what the port shares,
## roads, track, tractors and land.
func upkeep_parts() -> Dictionary:
	var parts := {0: 0.0}
	for segment: int in roads.segments:
		var road: Dictionary = roads.segments[segment]
		parts[0] += RoadNet.length(roads.nodes[road.a], roads.nodes[road.b]) * rules.road_types[road.type].upkeep_per_cell
	for segment: int in rails.segments:
		parts[0] += RoadNet.length(rails.nodes[rails.segments[segment].a], rails.nodes[rails.segments[segment].b]) * rules.rail.upkeep_per_cell
	parts[0] += rules.upkeep.tractor * tractors + rules.land.upkeep * land.size()
	for segment: int in ship_lanes.segments:
		var lane: Dictionary = ship_lanes.segments[segment]
		parts[0] += ship_lanes.footprint(ship_lanes.nodes[lane.a], ship_lanes.nodes[lane.b], lane.type).size() * rules.water.lanes[lane.type].upkeep_per_cell
	for station: Dictionary in pilot_stations.values():
		parts[0] += station.pilots * rules.water.pilots.upkeep_per_pilot
	for depot: Dictionary in tug_depots.values():
		parts[0] += depot.tugs * rules.water.tugs.upkeep_per_tug
	var add := func(terminal: int, amount: float) -> void: parts[terminal] = parts.get(terminal, 0.0) + amount
	for id: int in areas.list:
		var area: Dictionary = areas.list[id]
		add.call(area.terminal, areas.cells(id).size() * rules.area_types[area.type].upkeep_per_cell)
		if areas.kind_of(area) == "gate":
			add.call(area.terminal, rules.gate_levels[area.settings.level].upkeep_per_lane * areas.layout(id).lanes.size())
	for machine: Dictionary in machines.list.values():
		add.call(areas.list[machine.area].terminal, rules.yard_gear[machine.gear].upkeep_per_machine)
	for crane in cranes:
		add.call(areas.list[crane.apron].terminal, rules.upkeep.sts_crane)
	return parts


## The numbers a terminal manager watches.
## TEU in yard block `id` and the most it holds, as (held, room). A tier
## holds one 40 ft box or two 20 ft boxes, so each stack slot is 2 TEU.
func block_fill(id: int) -> Vector2i:
	var room: int = areas.layout(id).stacks.size() * rules.yard_gear[areas.list[id].settings.gear].tiers * 2
	var held := 0
	if id in area_stacks:
		for box: int in area_stacks[id].boxes():
			held += boxes[box].teu
	return Vector2i(held, room)


func kpis() -> Dictionary:
	var last: Dictionary = ship_log[-1] if not ship_log.is_empty() else {}
	var fill := Vector2i.ZERO
	for area: int in area_stacks:
		if area in areas.list:
			fill += block_fill(area)
	return {
		"berth_moves_per_hour": last.moves / last.hours if last else 0.0,
		"crane_moves_per_hour": last.moves / last.hours / last.cranes if last else 0.0,
		"gate_turn_minutes": _average(turn_times),
		"yard_use": fill.x / float(fill.y) if fill.y else 0.0,
		"boxes_per_day": delivered_yesterday,
		"import_dwell_hours": _average(dwell_times) / 60.0,
		"upkeep_per_day": daily_upkeep(),
	}


## Terminal `terminal`'s own numbers: its last ship's berth and crane
## rates, its gate turn, its yard use, and yesterday's moves, income and its
## part of the upkeep.
func terminal_kpis(terminal: int) -> Dictionary:
	var calls := ship_log.filter(func(entry: Dictionary) -> bool: return entry.terminal == terminal)
	var last: Dictionary = calls[-1] if not calls.is_empty() else {}
	var fill := Vector2i.ZERO
	for area: int in area_stacks:
		if area in areas.list and areas.list[area].terminal == terminal:
			fill += block_fill(area)
	var yesterday: Array = ledger.days[-1].moves.terminals.get(terminal, [0, 0]) if not ledger.days.is_empty() else [0, 0]
	return {
		"berth_moves_per_hour": last.moves / last.hours if last else 0.0,
		"crane_moves_per_hour": last.moves / last.hours / last.cranes if last else 0.0,
		"gate_turn_minutes": terminal_turn_minutes(terminal),
		"yard_use": fill.x / float(fill.y) if fill.y else 0.0,
		"moves_yesterday": yesterday[0],
		"income_yesterday": yesterday[1],
		"upkeep_per_day": roundi(upkeep_parts().get(terminal, 0.0)),
	}


## The average lorry turn at `terminal`'s gates, in minutes, or 0 before any.
func terminal_turn_minutes(terminal: int) -> float:
	var turns: Array[float] = []
	turns.assign(terminal_turns.get(terminal, []))
	return _average(turns)


func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / values.size() if not values.is_empty() else 0.0


func last_event() -> String:
	return events[-1].text if not events.is_empty() else ""


## Logs `text`; `at` is the grid cell it happened at, which the HUD links to.
func _event(text: String, at := Grid.NONE) -> void:
	if last_event() == text:
		return
	var event := {"minute": clock.calendar_minutes(), "text": text}
	if at != Grid.NONE:
		event.at = at
	events.append(event)
	if events.size() > 50:
		events.pop_front()


func _end_of_day() -> void:
	# Each terminal's part rounded; the port's takes the rest, so the day's total is daily_upkeep().
	var upkeep := daily_upkeep()
	var parts := upkeep_parts()
	for terminal: int in parts:
		if terminal != 0:
			ledger.post("upkeep", -roundi(parts[terminal]), terminal)
			upkeep -= roundi(parts[terminal])
	ledger.post("upkeep", -upkeep)
	var bill := roundi(power.kwh * rules.reefers.price_per_kwh + power.peak_kw * rules.reefers.peak_charge_per_kw)
	if bill > 0:
		ledger.post("power", -bill)
	power = {"peak_kw": AreaFlow.plugged_reefers(self) * reefer_kw(), "kwh": 0.0}
	var dredged := dredged_cell_metres()
	if dredged > 0.0 and clock.game_day() % rules.water.dredge.maintenance_days == 0:
		ledger.post("dredging", -roundi(dredged * rules.water.dredge.maintenance_per_cell_metre))
	var due := _storage_due()
	for terminal: int in due:
		if due[terminal] * storage.fee > 0:
			ledger.post("storage", due[terminal] * storage.fee, terminal)
	for text in finance.end_of_day(clock.calendar_minutes(), ledger, contracts, not creative):
		_event(text)
	ledger.close_day(clock.game_day() - 1)
	if clock.game_day() % rules.year_days == 0:
		_end_of_year()
	delivered_yesterday = delivered - _delivered_at_midnight
	_delivered_at_midnight = delivered
	_event("Upkeep $%d, %d boxes through the gate" % [upkeep, delivered_yesterday])


## kW a plugged reefer draws today: more on the year's hot days.
func reefer_kw() -> float:
	var day: int = clock.game_day() % rules.year_days
	return rules.reefers.hot_kw if day >= rules.reefers.hot_from and day <= rules.reefers.hot_to else rules.reefers.kw


## Adds this tick's reefer draw to today's kWh and peak.
func _draw_power() -> void:
	var kw := AreaFlow.plugged_reefers(self) * reefer_kw()
	power.kwh += kw * SimClock.CALENDAR_MINUTES_PER_TICK / 60.0
	power.peak_kw = maxf(power.peak_kw, kw)


func _new_year() -> Dictionary:
	return {"calls": 0, "berth_hours": 0.0, "moves": 0, "turns": 0, "turn_minutes": 0.0}


## Closes the game year into the scoreboard and reports it against the year before.
func _end_of_year() -> void:
	var closed := {
		"year": scoreboard.size() + 1,
		"port_hours": year.berth_hours / year.calls if year.calls else 0.0,
		"moves_per_hour": year.moves / year.berth_hours if year.berth_hours > 0.0 else 0.0,
		"turn_minutes": year.turn_minutes / year.turns if year.turns else 0.0,
	}
	var text := "Year %d: %.1f h in port per call, %.1f moves an hour, %.0f min gate turn" % [closed.year, closed.port_hours, closed.moves_per_hour, closed.turn_minutes]
	if not scoreboard.is_empty():
		var last: Dictionary = scoreboard[-1]
		text += " (year before: %.1f h, %.1f, %.0f min)" % [last.port_hours, last.moves_per_hour, last.turn_minutes]
	scoreboard.append(closed)
	year = _new_year()
	_event(text)


## A service's ship arrives for its window. It berths at the first free
## stretch of a ready quay apron long enough, or waits at anchorage until one
## frees up. A ship no apron could ever take is missed.
func _call(service: Dictionary) -> void:
	var spec: Dictionary = rules.ship_classes[service.kind]
	var who := contracts.name_of(service.line)
	var why := ""
	if not AreaFlow.could_berth(self, service.kind):
		why = "no quay apron of %d m in a terminal with a gate and a road" % Grid.metres(AreaFlow.ship_cells(self, service.kind))
	elif not _could_berth(service.kind, true):
		why = "no ship lane from the open sea to a berth, %.1f m deep all the way, for its draft" % spec.light_draft
	if why != "":
		_event("%s's %s went elsewhere: %s" % [who, service.kind, why])
		_event_if(contracts.missed(service.line))
		return
	var due: float = clock.calendar_minutes() + service.window_hours * 60.0
	# With water only for its light draft, it calls light-loaded.
	var light := not _could_berth(service.kind)
	var share: float = spec.light_share if light else 1.0
	var ship := Ship.new(service.kind, service.line, due, roundi(spec.import_moves * share), roundi(spec.export_moves * share))
	ship.light = light
	ship.arrived = clock.calendar_minutes()
	ship.id = _next_ship
	_next_ship += 1
	ledger.post("port_dues", spec.port_dues)
	ship.berth = service.apron
	ship.any_berth = service.any_berth
	ship.empties = rules.empties.max_per_call if lock_error("empties") == "" else 0
	ships.append(ship)
	_berths_seen = Vector2i(-1, -1)  # the new ship has not looked yet
	_event("%s's %s has arrived" % [who, service.kind])


## Whether lines may offer a service of `kind` at berth `apron`: unlocked,
## a lane deep enough from the sea to it, the berth long enough and a crane
## on it that reaches across the ship.
func _could_offer(kind: String, apron: int) -> bool:
	return unlocked(kind) and Marine.reaches(self, kind, apron, 0, true) and AreaFlow.could_work_at(self, kind, apron)


## Whether some apron long enough for `kind` can be reached from the sea,
## busy or not, at its full draft or (`light`) its light draft.
func _could_berth(kind: String, light := false) -> bool:
	return AreaFlow.ready_aprons(self).any(func(apron: int) -> bool: return AreaFlow._length(self, apron) >= AreaFlow.ship_cells(self, kind) and Marine.reaches(self, kind, apron, 0, light))


## Lines may offer a new service for the berth with a crane that has the
## fewest services, while it has room for more.
func _offer_service() -> void:
	var now := clock.calendar_minutes()
	contracts.expire(now)
	var berths := AreaFlow.offer_berths(self)
	if berths.is_empty():
		return
	var apron := berths[0]
	for other in berths:
		if contracts.booked(other).size() < contracts.booked(apron).size():
			apron = other
	var offered := contracts.offer(rng, now, apron, func(kind: String) -> bool: return _could_offer(kind, apron), hinterland_demand())
	if not offered.is_empty():
		_event("%s offers a weekly %s service" % [contracts.name_of(offered.line), offered.kind])


## Why offer `id` can't be agreed with its calls at berth `apron`, or "".
func accept_offer_error(id: int, apron: int) -> String:
	var offer := contracts.offers.filter(func(o: Dictionary) -> bool: return o.id == id)
	if offer.is_empty():
		return "No such offer"
	return _berth_error(offer[0].kind, apron) if _berth_error(offer[0].kind, apron) else contracts.accept_error(id, apron)


func accept_offer(id: int, apron: int) -> String:
	var err := accept_offer_error(id, apron)
	return err if err else contracts.accept(id, apron)


## Why agreed service `id` can't move to berth `apron`, or "".
func move_service_error(id: int, apron: int) -> String:
	var service := contracts.services.filter(func(s: Dictionary) -> bool: return s.id == id)
	if service.is_empty():
		return "No such service"
	return _berth_error(service[0].kind, apron) if _berth_error(service[0].kind, apron) else contracts.move_error(id, apron)


func move_service(id: int, apron: int) -> String:
	var err := move_service_error(id, apron)
	return err if err else contracts.move(id, apron)


## Ends agreed service `id`; a ship already called for it still works.
func cancel_service(id: int) -> String:
	var done := contracts.cancel(id)
	_event_if(done[1])
	return done[0]


## Why a ship of `kind` can't call at berth `apron`, or "".
func _berth_error(kind: String, apron: int) -> String:
	if apron not in AreaFlow.ready_aprons(self):
		return "Not a working berth"
	if AreaFlow._length(self, apron) < AreaFlow.ship_cells(self, kind):
		return "This berth is too short for a %s" % kind
	return ""


func _event_if(text: String) -> void:
	if text != "":
		_event(text)


func _work(ship: Ship) -> void:
	ship.prev_sail = ship.sail
	match ship.state:
		Ship.State.ANCHORED:
			if not AreaFlow.berth(self, ship):
				Marine.wait(self, ship)
		Ship.State.ANCHORING:
			if not Marine.under_way(self, ship, 1):
				return
			if Marine.sail(self, ship, 1):
				Marine.release(ship)
				ship.state = Ship.State.ANCHORED
		Ship.State.ARRIVING:
			if not Marine.under_way(self, ship, 1):
				return
			if Marine.sail(self, ship, 1, Marine.berthing_limit(self, ship)):
				Marine.release(ship)
				ship.state = Ship.State.WORKING
				ship.berthed = clock.calendar_minutes()
				_event("A %s is unloading" % ship.kind, areas.list[ship.apron].start)
		Ship.State.WORKING:
			AreaFlow.work(self, ship)
		Ship.State.LEAVING:
			if not Marine.under_way(self, ship, -1):
				return
			ship.tugs = 0  # they have pushed it off the quay
			if Marine.sail(self, ship, -1):
				ships.erase(ship)
				_departures += 1


func _sail(ship: Ship, crane_count: int) -> void:
	ship.state = Ship.State.LEAVING
	var now := clock.calendar_minutes()
	var hours := (now - ship.berthed) / 60.0
	var late := maxf(now - ship.due, 0.0) / 60.0
	var terminal: int = areas.list[ship.apron].terminal
	ship_log.append({"kind": ship.kind, "line": ship.line, "terminal": terminal, "moves": ship.moves, "hours": hours, "cranes": crane_count, "late": late})
	if ship_log.size() > 10:
		ship_log.pop_front()
	year.calls += 1
	year.berth_hours += hours
	year.moves += ship.moves
	# Shippers dislike storage fees above the fair rate, and the line hears it.
	var fees: float = rules.storage.satisfaction_per_dollar * maxf(storage.fee - rules.storage.fair_fee, 0.0)
	_event_if(contracts.called(ship.line, late, ship.moves / hours if hours > 0.0 else 0.0, terminal_turn_minutes(terminal), fees))


func _new_box(kind: String, due: float, line: String) -> int:
	var id := _next_box
	_next_box += 1
	var teu := 2 if rng.randf() < rules.box_mix.forty_share else 1
	# No reefers before their milestone, so a new port isn't fined for plugs it can't have yet.
	var reefer: bool = rng.randf() < rules.box_mix.reefer_share and unlocked("reefers")
	var dg: bool = not reefer and rng.randf() < rules.box_mix.dg_share
	# shortcut: only imports rush, against their ship's window; rush exports when lines book them by deadline.
	var rush: bool = kind == "import" and rng.randf() < rules.box_mix.rush_share
	boxes[id] = {"kind": kind, "due": due, "teu": teu, "reefer": reefer, "dg": dg, "rush": rush, "in": -1.0, "line": line, "rail": false, "place": _pick_place()}
	exports += 1 if kind == "export" else 0
	return id


## A hinterland place, drawn by the data's shares, of those with a rail link
## when `rail_only`: an import's destination or an export's origin.
func _pick_place(rail_only := false) -> String:
	var places: Array = rules.hinterland.places.keys().filter(func(p: String) -> bool: return not rail_only or rules.hinterland.places[p].rail_km > 0.0)
	var total := 0.0
	for place: String in places:
		total += rules.hinterland.places[place].share
	var roll := rng.randf() * total
	for place: String in places:
		roll -= rules.hinterland.places[place].share
		if roll < 0.0:
			return place
	return places[-1]


## How busy the hinterland keeps lines, by milestones reached: it scales how
## often they offer services.
func hinterland_demand() -> float:
	var reached := milestones_reached()
	return milestones()[reached - 1].demand if reached > 0 else 1.0


## Whether box `id` can go by rail: its hinterland place has a rail link.
func by_rail_to(id: int) -> bool:
	return rules.hinterland.places[boxes[id].place].rail_km > 0.0


## Import `id` has left for the hinterland: once empties are unlocked, it
## comes back as an empty of its line and size return_days later, with the
## chance return_share; the rest go back to inland depots.
func _import_left(id: int) -> void:
	if lock_error("empties") == "" and rng.randf() < rules.empties.return_share:
		returning.append({"at": clock.calendar_minutes() + rules.empties.return_days * SimClock.MINUTES_PER_DAY, "line": boxes[id].line, "teu": boxes[id].teu})


## Empty `id`, stacked here, has left with an exporter, who brings it back
## full stuffing_hours later.
func _empty_collected(id: int) -> void:
	stuffing.append({"at": clock.calendar_minutes() + rules.empties.stuffing_hours * 60.0})


## A new empty box of `line` and `teu`, coming back from the hinterland.
func _new_empty(line: String, teu: int) -> int:
	var id := _next_box
	_next_box += 1
	boxes[id] = {"kind": "empty", "due": 0.0, "teu": teu, "reefer": false, "dg": false, "rush": false, "in": -1.0, "line": line, "rail": false, "place": _pick_place()}
	return id


## Routes from now on go round the lane cells vehicles wait in, by the delays
## LaneTraffic last settled.
func _weigh_routes() -> void:
	lanes.set_delays(lane_traffic.delays(), rules.lorry_speed / Grid.CELL, AreaFlow.tractor_speed(self))


## Takes box `id` out of the port: delivered, loaded aboard, or lost.
func _drop_box(id: int) -> void:
	exports -= 1 if boxes[id].kind == "export" else 0
	boxes.erase(id)


## Boxes in the yard past their free days.
func _storage_due() -> Dictionary:
	var now := clock.calendar_minutes()
	var count := {}  # terminal -> boxes
	for area: int in area_stacks:
		var terminal: int = areas.list[area].terminal if area in areas.list else 0
		for id: int in area_stacks[area].boxes():
			if boxes[id].in >= 0.0 and now - boxes[id].in > storage.free_days * SimClock.MINUTES_PER_DAY:
				count[terminal] = count.get(terminal, 0) + 1
	return count


## Higher storage fees make shippers collect imports sooner, down to a floor.
func _dwell_factor() -> float:
	return maxf(rules.storage.min_dwell_factor, 1.0 / (1.0 + storage.fee * rules.storage.dwell_per_dollar))


func _tractors_out() -> int:
	return _tractors_on_road


## Puts `vehicle` in the port's list and indexes.
func _add_vehicle(vehicle: Vehicle) -> void:
	vehicles.append(vehicle)
	_by_id[vehicle.id] = vehicle
	_tractors_on_road += 1 if vehicle.kind == "tractor" else 0
	_count_bound(vehicle, 1)
	if vehicle.home != Grid.NONE:
		if vehicle.home not in _fetching:
			_fetching[vehicle.home] = [] as Array[Vehicle]
		_fetching[vehicle.home].append(vehicle)


## Takes `vehicle` off the roads and out of the port.
func _drop_vehicle(vehicle: Vehicle) -> void:
	lane_traffic.leave(vehicle)
	vehicles.erase(vehicle)
	_by_id.erase(vehicle.id)
	_tractors_on_road -= 1 if vehicle.kind == "tractor" else 0
	_count_bound(vehicle, -1)
	if vehicle.home != Grid.NONE:
		_fetching[vehicle.home].erase(vehicle)


## Sends `vehicle` to area `area` (0 for none); the one way its area changes.
func _set_area(vehicle: Vehicle, area: int) -> void:
	_count_bound(vehicle, -1)
	vehicle.area = area
	_count_bound(vehicle, 1)


## How many lorries have area `area` as theirs.
func lorries_bound_for(area: int) -> int:
	return _lorries_bound.get(area, 0)


func _count_bound(vehicle: Vehicle, by: int) -> void:
	if vehicle.kind == "lorry" and vehicle.area != 0:
		_lorries_bound[vehicle.area] = _lorries_bound.get(vehicle.area, 0) + by


## The vehicle with id `id`, or null once it has left.
func vehicle_by_id(id: int) -> Vehicle:
	return _by_id.get(id)


## The tractors fetching exports to apron slot `home`, oldest first.
func fetching_to(home: Vector2i) -> Array[Vehicle]:
	return _fetching.get(home, [] as Array[Vehicle])
