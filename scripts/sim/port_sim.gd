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
## Depth of the channel from the sea to the berths, in metres.
var channel_depth := 0.0
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
## The rules each kind of area takes, and what a new one starts with.
const AREA_SETTINGS := {
	"yard_block": {"role": "import", "gear": "reach_stacker", "lines": []},
	"quay_apron": {"lines": []},
	"gate": {"level": "manual"},
}
const AREA_ROLES: Array[String] = ["import", "export", "empty", "reefer", "dangerous"]
## The roads drawn on the 4 m grid, and the lanes routed over them.
var roads: RoadNet
## Rail track, a graph of its own: where it crosses a road straight across,
## the cells are level crossings, in both.
var rails: RoadNet
var lanes: LaneGraph
## The areas dragged along those roads.
var areas: Areas
## Every box in the port by id: {"kind": "import" or "export", "due": the
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
## Minutes the latest collected imports spent in the yard, newest last.
var dwell_times: Array[float] = []
## The player's storage terms: free days (0-3) and the fee per box per day after them.
var storage := {}

## Boxes a vehicle is already coming for.
var _claimed := {}
## Calendar minutes until the next import lorry and export lorry.
var _until_lorry := 0.0
var _until_export := 0.0
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
	areas = Areas.new(rules.area_types, roads, rules.site)
	lanes.areas = areas
	lane_traffic = LaneTraffic.new(lanes)
	handovers = Handovers.new(areas)
	machines = Machines.new(rules.yard_gear)
	ledger = Ledger.new(rules.ledger_categories, rules.start_money)
	contracts = Contracts.new(rules)
	finance = Finance.new(rules)
	year = _new_year()
	channel_depth = rules.channel.start_depth
	var start: Dictionary = rules.land.start
	for x in range(start.x, start.x + start.width):
		for y in range(start.y, start.y + start.height):
			land[Vector2i(x, y)] = true
	storage = {"free_days": rules.storage.free_days, "fee": rules.storage.fee}
	rng.seed = seed_value
	_event("Place a berth on the coast, then draw a road from the highway to it and add a gate and a yard block along it")


class Ship:
	## ANCHORED: waiting off the map for a berth.
	enum State { ARRIVING, WORKING, LEAVING, ANCHORED }
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
	var state := State.ARRIVING
	## 0 out at sea, 1 alongside the quay.
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
		return {"kind": kind, "line": line, "due": due, "boxes": boxes, "exports": exports, "state": state, "sail": sail, "prev_sail": prev_sail, "moves": moves, "berthed": berthed, "apron": apron, "from": from, "berth": berth, "any_berth": any_berth}

	static func from_dict(d: Dictionary) -> Ship:
		var ship := Ship.new(d.kind, d.line, d.due, d.boxes, d.exports)
		ship.state = d.state
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
		"channel_depth": channel_depth,
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
		"dwell_times": dwell_times.duplicate(),
		"storage": storage.duplicate(),
		"claimed": _claimed.duplicate(),
		"until_lorry": _until_lorry,
		"until_export": _until_export,
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
	sim.areas = Areas.from_dict(d.areas, sim.rules.area_types, sim.roads, sim.rules.site)
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
	sim.channel_depth = d.channel_depth
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
	sim.dwell_times.assign(d.dwell_times)
	sim.storage = d.storage.duplicate()
	sim._claimed = d.claimed.duplicate()
	sim._until_lorry = d.until_lorry
	sim._until_export = d.until_export
	sim._next_vehicle = d.next_vehicle
	sim._next_box = d.next_box
	for data: Dictionary in d.vehicles:
		sim._add_vehicle(Vehicle.from_dict(data))
	sim.lane_traffic = LaneTraffic.from_dict(d.lane_traffic, sim.lanes)
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
		"dredge":
			return dredge(command.metres)
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
		"build_area":
			return build_area(command.type, command.segment, command.side, command.from, command.to)
		"build_berth":
			return build_berth(command.kind, command.y)
		"build_two_way_gate":
			return build_two_way_gate(command.type, command.segment, command.from, command.to)
		"remove_area":
			return remove_area(command.id)
		"remove_sts":
			return remove_sts(command.apron, command.along)
		"set_area":
			return set_area(command.id, command.settings)
		"set_terminal":
			return areas.set_terminal(command.id, command.terminal)
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
		ledger.post("construction", -area_price(type, segment, side, from, to))
		areas.add(type, segment, side, from, to, AREA_SETTINGS.get(rules.area_types[type].kind, {}).duplicate(true))
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


## The road line, top to bottom, of a berth of `kind` centred on row `y`:
## grid points down the grid line one cell east of where its apron reaches
## the water exactly (its road's lanes lie either side), as long as the
## apron, so a berth placed end to end with another shares its road's end.
func berth_line(kind: String, y: int) -> Array[Vector2i]:
	var length: int = rules.berths[kind].length
	var x: int = Grid.cells(rules.site.sea_width) + rules.area_types.quay_apron.depth + 1
	var top := y - length / 2
	return [Vector2i(x, top), Vector2i(x, top + length)] as Array[Vector2i]


## The cells a berth of `kind` centred on row `y` would cover: its apron,
## from the water to its road.
func berth_cells(kind: String, y: int) -> Array[Vector2i]:
	var line := berth_line(kind, y)
	var found: Array[Vector2i] = []
	for row in range(line[0].y, line[1].y):
		for x in range(Grid.cells(rules.site.sea_width), line[0].x - 1):
			found.append(Vector2i(x, row))
	return found


func build_berth_error(kind: String, y: int) -> String:
	if kind not in rules.berths:
		return "Unknown berth: %s" % kind
	var locked := lock_error(kind)
	if locked:
		return locked
	var line := berth_line(kind, y)
	var cells := berth_cells(kind, y)
	if not cells.all(owns):
		return "Buy this land first"
	var built := {}
	for id: int in areas.list:
		for cell in areas.cells(id):
			built[cell] = true
	for segment: int in roads.segments:
		var road: Dictionary = roads.segments[segment]
		for cell in roads.footprint(roads.nodes[road.a], roads.nodes[road.b], road.type):
			built[cell] = true
	if cells.any(func(c: Vector2i) -> bool: return c in built):
		return "Something is already built here"
	# A road meeting the berth's road part-way would split it under the apron.
	if roads.footprint(line[0] + Vector2i(0, 1), line[1] - Vector2i(0, 1), BERTH_ROAD).any(func(c: Vector2i) -> bool: return c in built):
		return "A road already runs here: place the berth clear of it, it brings its own"
	var err := build_road_error(line[0], line[1], BERTH_ROAD)
	if err:
		return err
	if not _afford(road_price(line[0], line[1], BERTH_ROAD) + cells.size() * rules.area_types.quay_apron.cost_per_cell):
		return "Not enough money"
	return ""


## Places a berth of `kind` on the coast centred on row `y`: its road, then
## its apron along the road's sea side.
func build_berth(kind: String, y: int) -> String:
	var err := build_berth_error(kind, y)
	if err:
		return err
	var line := berth_line(kind, y)
	build_road(line[0], line[1], BERTH_ROAD)
	# The road runs south from line[0], so its right, side 1, faces the sea.
	err = build_area("quay_apron", roads.segment_at(Vector2i(line[0].x, y)), 1, 0, rules.berths[kind].length - 1)
	assert(err == "", "a berth's apron fits where its error check said: %s" % err)
	return ""


## A gate of `type` on each side of `segment` over the same stretch, in one
## terminal: lorries check in on the side they arrive by and out on the side
## they leave by, so none turns round to pass a gate.
func build_two_way_gate(type: String, segment: int, from: int, to: int) -> String:
	var err := build_two_way_gate_error(type, segment, from, to)
	if err == "":
		build_area(type, segment, 1, from, to)
		var first: int = areas.list.keys().max()
		build_area(type, segment, -1, from, to)
		areas.set_terminal(areas.list.keys().max(), areas.list[first].terminal)
	return err


func area_price(type: String, segment: int, side: int, from: int, to: int) -> int:
	return areas.cells_of(type, segment, side, from, to).size() * rules.area_types[type].cost_per_cell


## shortcut: changing gear is free; machines are bought per area in M5 step 17.
func set_area_error(id: int, settings: Dictionary) -> String:
	if id not in areas.list:
		return "No area there"
	var type: String = areas.list[id].type
	for key: String in settings:
		if key not in AREA_SETTINGS.get(areas.kind_of(areas.list[id]), {}):
			return "A %s has no %s setting" % [rules.area_types[type].name.to_lower(), key]
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
		ledger.post("equipment", -spec.cost)
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
			_event("A new %s is up on %s" % [rules.sts_cranes[order.kind].name, areas.terminals[areas.list[order.apron].terminal].name], areas.list[order.apron].start)
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
	ledger.post("moves", move_price(box))
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


## Deepens the channel by whole metres, up to rules.channel.max_depth.
func dredge(metres: int) -> String:
	var locked := lock_error("dredging")
	if locked:
		return locked
	if metres < 1:
		return "Dredge at least a metre"
	if channel_depth + metres > rules.channel.max_depth:
		return "The channel can't go below %.0f m" % rules.channel.max_depth
	if not _afford(metres * rules.channel.cost_per_metre):
		return "Not enough money"
	ledger.post("dredging", -metres * rules.channel.cost_per_metre)
	channel_depth += metres
	return ""


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
			continue
		_work(ship)
	_berths_seen = berths_now
	_until_lorry -= SimClock.CALENDAR_MINUTES_PER_TICK
	if _until_lorry <= 0.0 and AreaFlow.dispatch_import_lorry(self):
		_until_lorry = rules.lorry_interval_minutes
	_until_export -= SimClock.CALENDAR_MINUTES_PER_TICK
	if _until_export <= 0.0 and AreaFlow.dispatch_export_lorry(self):
		_until_export = rules.export_lorry_interval_minutes
	AreaFlow.tick(self)
	RailFlow.tick(self)


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
## Boxes in yard block `id` and the most it holds, as (held, room).
func block_fill(id: int) -> Vector2i:
	var room: int = areas.layout(id).stacks.size() * rules.yard_gear[areas.list[id].settings.gear].tiers
	return Vector2i(area_stacks[id].boxes().size() if id in area_stacks else 0, room)


func kpis() -> Dictionary:
	var last: Dictionary = ship_log[-1] if not ship_log.is_empty() else {}
	var capacity := 0
	var held := 0
	for area: int in area_stacks:
		if area in areas.list:
			var stacks: AreaStacks = area_stacks[area]
			capacity += stacks.stacks.size() * rules.yard_gear[areas.list[area].settings.gear].tiers
			held += stacks.boxes().size()
	return {
		"berth_moves_per_hour": last.moves / last.hours if last else 0.0,
		"crane_moves_per_hour": last.moves / last.hours / last.cranes if last else 0.0,
		"gate_turn_minutes": _average(turn_times),
		"yard_use": held / float(capacity) if capacity else 0.0,
		"boxes_per_day": delivered_yesterday,
		"import_dwell_hours": _average(dwell_times) / 60.0,
		"upkeep_per_day": daily_upkeep(),
	}


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
	var upkeep := daily_upkeep()
	ledger.post("upkeep", -upkeep)
	var bill := roundi(power.kwh * rules.reefers.price_per_kwh + power.peak_kw * rules.reefers.peak_charge_per_kw)
	if bill > 0:
		ledger.post("power", -bill)
	power = {"peak_kw": AreaFlow.plugged_reefers(self) * reefer_kw(), "kwh": 0.0}
	var dredged: float = channel_depth - rules.channel.start_depth
	if dredged > 0.0 and clock.game_day() % rules.channel.maintenance_days == 0:
		ledger.post("dredging", -roundi(dredged * rules.channel.maintenance_per_metre))
	var storage_paid: int = _storage_due() * storage.fee
	if storage_paid > 0:
		ledger.post("storage", storage_paid)
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
	if channel_depth < spec.draft:
		why = "it needs %.0f m of channel, the port has %.0f m" % [spec.draft, channel_depth]
	elif not _could_berth(service.kind):
		why = "no quay apron of %d m in a terminal with a gate and a road" % Grid.metres(AreaFlow.ship_cells(self, service.kind))
	if why != "":
		_event("%s's %s went elsewhere: %s" % [who, service.kind, why])
		_event_if(contracts.missed(service.line))
		return
	var due: float = clock.calendar_minutes() + service.window_hours * 60.0
	var ship := Ship.new(service.kind, service.line, due, spec.import_moves, spec.export_moves)
	ship.berth = service.apron
	ship.any_berth = service.any_berth
	ships.append(ship)
	_berths_seen = Vector2i(-1, -1)  # the new ship has not looked yet
	_event("%s's %s has arrived" % [who, service.kind])


## Whether the channel is deep enough for `kind` and some apron long enough, busy or not.
## Whether lines may offer a service of `kind` at berth `apron`: unlocked,
## the channel deep enough, the berth long enough and a crane on it that
## reaches across the ship.
func _could_offer(kind: String, apron: int) -> bool:
	return unlocked(kind) and channel_depth >= rules.ship_classes[kind].draft and AreaFlow.could_work_at(self, kind, apron)


func _could_berth(kind: String) -> bool:
	return channel_depth >= rules.ship_classes[kind].draft and AreaFlow.could_berth(self, kind)


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
			AreaFlow.berth(self, ship)
		Ship.State.ARRIVING:
			ship.sail = minf(ship.sail + SimClock.TICK_SECONDS / rules.sail_seconds, 1.0)
			if ship.sail == 1.0:
				ship.state = Ship.State.WORKING
				ship.berthed = clock.calendar_minutes()
				_event("A %s is unloading" % ship.kind, areas.list[ship.apron].start)
		Ship.State.WORKING:
			AreaFlow.work(self, ship)
		Ship.State.LEAVING:
			ship.sail -= SimClock.TICK_SECONDS / rules.sail_seconds
			if ship.sail <= 0.0:
				ships.erase(ship)
				_departures += 1


func _sail(ship: Ship, crane_count: int) -> void:
	ship.state = Ship.State.LEAVING
	var now := clock.calendar_minutes()
	var hours := (now - ship.berthed) / 60.0
	var late := maxf(now - ship.due, 0.0) / 60.0
	ship_log.append({"kind": ship.kind, "line": ship.line, "moves": ship.moves, "hours": hours, "cranes": crane_count, "late": late})
	if ship_log.size() > 10:
		ship_log.pop_front()
	year.calls += 1
	year.berth_hours += hours
	year.moves += ship.moves
	# Shippers dislike storage fees above the fair rate, and the line hears it.
	var fees: float = rules.storage.satisfaction_per_dollar * maxf(storage.fee - rules.storage.fair_fee, 0.0)
	_event_if(contracts.called(ship.line, late, ship.moves / hours if hours > 0.0 else 0.0, kpis().gate_turn_minutes, fees))


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


## Takes box `id` out of the port: delivered, loaded aboard, or lost.
func _drop_box(id: int) -> void:
	exports -= 1 if boxes[id].kind == "export" else 0
	boxes.erase(id)


## Boxes in the yard past their free days.
func _storage_due() -> int:
	var now := clock.calendar_minutes()
	var count := 0
	var stacked: Array = []
	for area: int in area_stacks:
		stacked.append_array(area_stacks[area].boxes())
	for id: int in stacked:
		if boxes[id].in >= 0.0 and now - boxes[id].in > storage.free_days * SimClock.MINUTES_PER_DAY:
			count += 1
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
