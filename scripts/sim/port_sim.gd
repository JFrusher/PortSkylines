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
var map: PortMap
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
## Shipping lines, their services and offers, and their reputation of the port.
var contracts: Contracts
## Loans and the bailout.
var finance: Finance
## Land tiles (rules.land.cells square) the port owns, as tile coordinates.
var land := {}
## Depth of the channel from the sea to the berths, in metres.
var channel_depth := 0.0
## STS cranes ordered and not yet delivered: {"cell", "due" (calendar minute)}.
var crane_orders: Array[Dictionary] = []
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
var vehicles: Array[Vehicle] = []
var traffic := Traffic.new()
var yard: Yard
## Every box in the port by id: {"kind": "import" or "export", "due": the
## calendar minute an import may leave, "teu": 1 or 2 (20 or 40 ft),
## "reefer": bool, "in": the calendar minute it was stacked, or -1}. A box
## is always in exactly one place: on a vehicle or in a yard stack (boxes on
## ships are only counted).
var boxes := {}
## Terminal tractors owned. Those not on the road are parked beside the quay.
var tractors := 0
## Lorries that gave up on a traffic jam and left; see _unstick.
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
## Ships that have left, and the map version and departures when anchored
## ships last looked for a berth. A berth frees only when one of these
## changes, so until then looking again would find nothing; a new arrival
## resets it to look once.
var _departures := 0
var _berths_seen := Vector2i(-1, -1)


func _init(seed_value := 0, game_rules := Content.base(), creative_mode := false) -> void:
	rules = game_rules
	creative = creative_mode
	map = PortMap.new(Vector2i(rules.map.width, rules.map.height), rules.map.sea_width)
	yard = Yard.new(map, rules)
	ledger = Ledger.new(rules.ledger_categories, rules.start_money)
	contracts = Contracts.new(rules)
	finance = Finance.new(rules)
	channel_depth = rules.channel.start_depth
	var start: Dictionary = rules.land.start
	for x in range(start.x, start.x + start.width):
		for y in range(start.y, start.y + start.height):
			land[Vector2i(x, y)] = true
	storage = {"free_days": rules.storage.free_days, "fee": rules.storage.fee}
	rng.seed = seed_value
	_event("Run a road from the highway to the coast through a gate, then build a quay, cranes, tractors and a yard")


func cost(kind: int) -> int:
	return rules.build_cost[PortMap.Tile.keys()[kind].to_lower()]


class Ship:
	## ANCHORED: waiting off the map for a berth.
	enum State { ARRIVING, WORKING, LEAVING, ANCHORED }
	## Its class, a key of rules.ship_classes.
	var kind: String
	## Its line, a key of rules.lines.
	var line: String
	## The calendar minute its berth window closes; sailing later is late.
	var due: float
	## The quay tiles it lies along, in order; empty while anchored.
	var cells: Array[Vector2i]
	## The step from those quay tiles to the water the ship is in.
	var side: Vector2i
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
		return {"kind": kind, "line": line, "due": due, "cells": cells.duplicate(), "side": side, "boxes": boxes, "exports": exports, "state": state, "sail": sail, "prev_sail": prev_sail, "moves": moves, "berthed": berthed}

	static func from_dict(d: Dictionary) -> Ship:
		var ship := Ship.new(d.kind, d.line, d.due, d.boxes, d.exports)
		ship.cells.assign(d.cells)
		ship.side = d.side
		ship.state = d.state
		ship.sail = d.sail
		ship.prev_sail = d.prev_sail
		ship.moves = d.moves
		ship.berthed = d.berthed
		return ship


## A ship-to-shore crane on a quay tile. It works any ship lying along its
## tile that its outreach can reach across, one box per move, to or from the
## tractor beneath it.
class Crane:
	var cell: Vector2i
	## Calendar minutes into the current move.
	var timer := 0.0
	## The tractor sent to it (a vehicle id), or 0.
	var tractor := 0

	func _init(at: Vector2i) -> void:
		cell = at

	func to_dict() -> Dictionary:
		return {"cell": cell, "timer": timer, "tractor": tractor}

	static func from_dict(d: Dictionary) -> Crane:
		var crane := Crane.new(d.cell)
		crane.timer = d.timer
		crane.tractor = d.tractor
		return crane


## Everything the sim needs to carry on exactly where it was, in plain types.
func to_dict() -> Dictionary:
	return {
		"map": map.to_dict(),
		"ticks": clock.ticks,
		"rng_seed": rng.seed,
		"rng_state": rng.state,
		"ledger": ledger.to_dict(),
		"contracts": contracts.to_dict(),
		"finance": finance.to_dict(),
		"land": land.duplicate(),
		"channel_depth": channel_depth,
		"crane_orders": crane_orders.duplicate(true),
		"creative": creative,
		"delivered": delivered,
		"events": events.duplicate(true),
		"ship_log": ship_log.duplicate(true),
		"delivered_yesterday": delivered_yesterday,
		"delivered_at_midnight": _delivered_at_midnight,
		"ships": ships.map(func(ship: Ship) -> Dictionary: return ship.to_dict()),
		"cranes": cranes.map(func(crane: Crane) -> Dictionary: return crane.to_dict()),
		"vehicles": vehicles.map(func(vehicle: Vehicle) -> Dictionary: return vehicle.to_dict()),
		"yard": yard.to_dict(),
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
	}


static func from_dict(d: Dictionary) -> PortSim:
	var sim := PortSim.new()
	sim.map = PortMap.from_dict(d.map)
	sim.yard = Yard.from_dict(d.yard, sim.map, sim.rules)
	sim.clock.ticks = d.ticks
	sim.rng.seed = d.rng_seed
	sim.rng.state = d.rng_state
	sim.ledger = Ledger.from_dict(d.ledger, sim.rules.ledger_categories)
	sim.contracts = Contracts.from_dict(d.contracts, sim.rules)
	sim.finance = Finance.from_dict(d.finance, sim.rules)
	sim.land = d.land.duplicate()
	sim.channel_depth = d.channel_depth
	sim.crane_orders.assign(d.crane_orders)
	sim.creative = d.creative
	sim.delivered = d.delivered
	sim.events.assign(d.events)
	sim.ship_log.assign(d.ship_log)
	sim.delivered_yesterday = d.delivered_yesterday
	sim._delivered_at_midnight = d.delivered_at_midnight
	for ship: Dictionary in d.ships:
		sim.ships.append(Ship.from_dict(ship))
	for crane: Dictionary in d.cranes:
		sim.cranes.append(Crane.from_dict(crane))
	for data: Dictionary in d.vehicles:
		var vehicle := Vehicle.from_dict(data)
		sim.vehicles.append(vehicle)
		for held: Vector3i in [vehicle.lane, vehicle.ahead]:
			if held != Traffic.NO_LANE:
				sim.traffic.claim(held, vehicle.id)
	sim.boxes = d.boxes.duplicate(true)
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
	return sim


## Identical for identical states; used by the replay and save tests.
func state_hash() -> int:
	return hash(var_to_bytes(to_dict()))


## The one way the player changes the sim. Applied between ticks, so a
## command log tagged with tick numbers replays exactly. Returns why it was
## refused, or "".
func apply(command: Dictionary) -> String:
	match command.get("op"):
		"build":
			return build(command.kind, command.cell)
		"bulldoze":
			return bulldoze(command.cell)
		"place_crane":
			return place_crane(command.cell)
		"buy_tractors":
			return buy_tractors(command.count)
		"set_yard":
			return set_yard(command.cell, command.settings)
		"accept_offer":
			return contracts.accept(command.id)
		"decline_offer":
			return contracts.decline(command.id)
		"set_storage":
			return set_storage(command.free_days, command.fee)
		"take_loan":
			return finance.take_loan(command.kind, clock.calendar_minutes(), ledger)
		"buy_land":
			return buy_land(command.tile)
		"dredge":
			return dredge(command.metres)
	return "Unknown command: %s" % command.get("op")


func build_error(kind: int, cell: Vector2i) -> String:
	var err := map.build_error(kind, cell)
	if err == "" and not owns(cell):
		err = "Buy this land first"
	if err == "" and not _afford(_price(kind, cell)):
		err = "Not enough money"
	return err


func build(kind: int, cell: Vector2i) -> String:
	var err := build_error(kind, cell)
	if err == "":
		ledger.post("construction", -_price(kind, cell))
		var settings_from := _joined_block(kind, cell)
		if settings_from != PortMap.NONE:
			yard.role[cell] = yard.role_of(settings_from)
			yard.gear[cell] = yard.gear_of(settings_from)
		map.place(kind, cell)
	return err


## The tile's build cost, plus the per-tile gear cost of a yard block it joins.
func _price(kind: int, cell: Vector2i) -> int:
	var settings_from := _joined_block(kind, cell)
	if settings_from == PortMap.NONE:
		return cost(kind)
	return cost(kind) + rules.yard_gear[yard.gear_of(settings_from)].cost_per_tile


## The anchor of the yard block a new yard tile at `cell` joins, or NONE. The
## tile takes that block's settings, whichever tile anchors it afterwards.
func _joined_block(kind: int, cell: Vector2i) -> Vector2i:
	if kind != PortMap.Tile.YARD:
		return PortMap.NONE
	var next := map.neighbor(cell, PortMap.Tile.YARD)
	return PortMap.NONE if next == PortMap.NONE else yard.anchor(next)


func crane_error(cell: Vector2i) -> String:
	if map.tile(cell) != PortMap.Tile.QUAY:
		return "Cranes stand on quay tiles"
	if _crane_at(cell) or crane_orders.any(func(o: Dictionary) -> bool: return o.cell == cell):
		return "There is a crane here already"
	if not _afford(rules.sts_crane.cost):
		return "Not enough money"
	return ""


## Orders an STS crane for the quay tile `cell`. It is paid now and stands
## there after rules.sts_crane.lead_days.
func place_crane(cell: Vector2i) -> String:
	var err := crane_error(cell)
	if err == "":
		ledger.post("equipment", -rules.sts_crane.cost)
		crane_orders.append({"cell": cell, "due": clock.calendar_minutes() + rules.sts_crane.lead_days * SimClock.MINUTES_PER_DAY})
		_deliver_cranes()
	return err


## Puts up the cranes whose order is due. One whose quay has gone is refunded.
func _deliver_cranes() -> void:
	var now := clock.calendar_minutes()
	for order: Dictionary in crane_orders.duplicate():
		if order.due > now:
			continue
		crane_orders.erase(order)
		if map.tile(order.cell) == PortMap.Tile.QUAY and not _crane_at(order.cell):
			cranes.append(Crane.new(order.cell))
			_event("A new STS crane is up at %s" % order.cell)
		else:
			ledger.post("equipment", rules.sts_crane.cost)
			_event("A crane arrived with no quay at %s to stand on; it went back, refunded" % order.cell)


## The land tile holding map cell `cell`.
func land_tile(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x / rules.land.cells, cell.y / rules.land.cells)


func owns(cell: Vector2i) -> bool:
	return land.has(land_tile(cell))


func buy_land_error(tile: Vector2i) -> String:
	var tiles: Vector2i = (map.size + Vector2i.ONE * (rules.land.cells - 1)) / rules.land.cells
	if tile.x < 0 or tile.y < 0 or tile.x >= tiles.x or tile.y >= tiles.y:
		return "Off the map"
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


func set_yard_error(cell: Vector2i, settings: Dictionary) -> String:
	var err := yard.settings_error(cell, settings)
	if err == "" and settings.has("gear") and not _afford(yard.gear_cost(cell, settings.gear)):
		err = "Not enough money"
	return err


## Sets the role ("import"/"export") and/or gear of the yard block at `cell`.
func set_yard(cell: Vector2i, settings: Dictionary) -> String:
	var err := set_yard_error(cell, settings)
	if err == "":
		if settings.has("gear"):
			ledger.post("equipment", -yard.gear_cost(cell, settings.gear))
		yard.apply_settings(cell, settings)
	return err


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


## Bulldozing a quay tile with a crane removes the crane first.
func bulldoze_error(cell: Vector2i) -> String:
	var crane := _crane_at(cell)
	if crane and (_ship_at(cell) or crane.tractor != 0):
		return "The crane is working a ship"
	if crane:
		return ""
	var err := map.bulldoze_error(cell)
	if err != "":
		return err
	if yard.count(cell) > 0 or yard.reserved.get(cell, 0) > 0:
		return "The yard still holds boxes"
	if _ship_at(cell):
		return "A ship is alongside"
	for vehicle in vehicles:
		if cell in vehicle.path or cell == vehicle.target:
			return "Vehicles are using this road"
	return ""


func bulldoze(cell: Vector2i) -> String:
	var err := bulldoze_error(cell)
	var crane := _crane_at(cell)
	if err == "" and crane:
		cranes.erase(crane)
	elif err == "":
		map.place(PortMap.Tile.LAND, cell)
		yard.forget_tile(cell)
	return err


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
	var berths_now := Vector2i(map.version, _departures)
	for ship: Ship in ships.duplicate():
		if ship.state == Ship.State.ANCHORED and berths_now == _berths_seen:
			continue
		_work(ship)
	_berths_seen = berths_now
	_until_lorry -= SimClock.CALENDAR_MINUTES_PER_TICK
	if _until_lorry <= 0.0 and _dispatch_import_lorry():
		_until_lorry = rules.lorry_interval_minutes
	_until_export -= SimClock.CALENDAR_MINUTES_PER_TICK
	if _until_export <= 0.0 and _dispatch_export_lorry():
		_until_export = rules.export_lorry_interval_minutes
	for vehicle: Vehicle in vehicles.duplicate():
		if vehicle.kind == "lorry":
			_drive_lorry(vehicle)
		else:
			_drive_tractor(vehicle)


## What the port costs to keep each day: tiles, cranes, tractors and yard machines.
func daily_upkeep() -> int:
	var total := 0
	for name: String in rules.upkeep:
		if name in rules.build_cost:
			total += rules.upkeep[name] * map.cells_of(PortMap.Tile[name.to_upper()]).size()
	total += rules.upkeep.sts_crane * cranes.size() + rules.upkeep.tractor * tractors + rules.land.upkeep * land.size()
	for block_anchor in yard.anchors():
		total += rules.yard_gear[yard.gear_of(block_anchor)].upkeep_per_machine * yard.machines(block_anchor)
	return total


## The numbers a terminal manager watches.
func kpis() -> Dictionary:
	var last: Dictionary = ship_log[-1] if not ship_log.is_empty() else {}
	var capacity := 0
	var held := 0
	for tile in map.cells_of(PortMap.Tile.YARD):
		capacity += yard.capacity(tile)
		held += yard.count(tile)
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


func _event(text: String) -> void:
	if last_event() == text:
		return
	events.append({"minute": clock.calendar_minutes(), "text": text})
	if events.size() > 50:
		events.pop_front()


func _end_of_day() -> void:
	var upkeep := daily_upkeep()
	ledger.post("upkeep", -upkeep)
	var dredged: float = channel_depth - rules.channel.start_depth
	if dredged > 0.0 and clock.game_day() % rules.channel.maintenance_days == 0:
		ledger.post("dredging", -roundi(dredged * rules.channel.maintenance_per_metre))
	var storage_paid: int = _storage_due() * storage.fee
	if storage_paid > 0:
		ledger.post("storage", storage_paid)
	for text in finance.end_of_day(clock.calendar_minutes(), ledger, contracts, not creative):
		_event(text)
	ledger.close_day(clock.game_day() - 1)
	delivered_yesterday = delivered - _delivered_at_midnight
	_delivered_at_midnight = delivered
	_event("Day %d: upkeep $%d, %d boxes through the gate" % [clock.game_day(), upkeep, delivered_yesterday])


## A service's ship arrives for its window. It berths at the first free
## stretch of quay long enough with a road to the highway, or waits at
## anchorage until one frees up. A ship no berth could ever take is missed.
func _call(service: Dictionary) -> void:
	var spec: Dictionary = rules.ship_classes[service.kind]
	var who := contracts.name_of(service.line)
	var why := ""
	if channel_depth < spec.draft:
		why = "it needs %.0f m of channel, the port has %.0f m" % [spec.draft, channel_depth]
	elif not _could_berth(service.kind):
		why = "no berth of %d quay tiles with a road to the highway" % spec.length
	if why != "":
		_event("%s's %s went elsewhere: %s" % [who, service.kind, why])
		_event_if(contracts.missed(service.line))
		return
	var due: float = clock.calendar_minutes() + service.window_hours * 60.0
	ships.append(Ship.new(service.kind, service.line, due, spec.import_moves, spec.export_moves))
	_berths_seen = Vector2i(-1, -1)  # the new ship has not looked yet
	_event("%s's %s has arrived" % [who, service.kind])


## Moves an anchored ship to a free stretch of berth; false if there is none yet.
func _berth(ship: Ship) -> bool:
	var length: int = rules.ship_classes[ship.kind].length
	for berth: Dictionary in map.berths():
		var cells: Array[Vector2i] = berth.cells
		# Any free stretch of the run will do; a berth can grow at either end.
		for start in range(cells.size() - length + 1):
			var span := cells.slice(start, start + length)
			if span.any(_ship_at) or _apron(span) == PortMap.NONE:
				continue
			ship.cells = span
			ship.side = berth.side
			ship.state = Ship.State.ARRIVING
			return true
	return false


## Whether some berth is long enough for `kind`, busy or not.
func _could_berth(kind: String) -> bool:
	var spec: Dictionary = rules.ship_classes[kind]
	if channel_depth < spec.draft:
		return false
	for berth: Dictionary in map.berths():
		if berth.cells.size() >= spec.length and _apron(berth.cells) != PortMap.NONE:
			return true
	return false


## Lines may offer a new service while the port has berths for it.
func _offer_service() -> void:
	var now := clock.calendar_minutes()
	contracts.expire(now)
	var berths := map.berths().filter(func(b: Dictionary) -> bool: return _apron(b.cells) != PortMap.NONE).size()
	var offered := contracts.offer(rng, now, berths, _could_berth)
	if not offered.is_empty():
		_event("%s offers a weekly %s service" % [contracts.name_of(offered.line), offered.kind])


func _event_if(text: String) -> void:
	if text != "":
		_event(text)


## The first quay tile in `cells` with a road route to the highway, or NONE.
func _apron(cells: Array[Vector2i]) -> Vector2i:
	for cell in cells:
		if not map.route(map.entry, cell).is_empty():
			return cell
	return PortMap.NONE


func _ship_at(quay: Vector2i) -> bool:
	for ship in ships:
		if quay in ship.cells:
			return true
	return false


func _crane_at(cell: Vector2i) -> Crane:
	for crane in cranes:
		if crane.cell == cell:
			return crane
	return null


func _work(ship: Ship) -> void:
	ship.prev_sail = ship.sail
	match ship.state:
		Ship.State.ANCHORED:
			_berth(ship)
		Ship.State.ARRIVING:
			ship.sail = minf(ship.sail + SimClock.TICK_SECONDS / rules.sail_seconds, 1.0)
			if ship.sail == 1.0:
				ship.state = Ship.State.WORKING
				ship.berthed = clock.calendar_minutes()
				_event("A %s is unloading" % ship.kind)
		Ship.State.WORKING:
			var working := _cranes_for(ship)
			if working.is_empty():
				_event("A %s is waiting: no crane on its berth reaches %d rows" % [ship.kind, rules.ship_classes[ship.kind].outreach])
				return
			var move_minutes: float = 60.0 / (rules.sts_crane.rate * rules.crane_interference)
			for crane in working:
				if ship.boxes > 0:
					_discharge(crane, ship, move_minutes)
				else:
					_load(crane, ship, move_minutes)
			if ship.boxes == 0 and working.all(func(c: Crane) -> bool: return c.tractor == 0):
				if ship.exports == 0:
					_sail(ship, working.size())
					_event("A %s is sailing, fully loaded" % ship.kind)
				elif _export_for(map.access_road(working[0].cell)).is_empty():
					_sail(ship, working.size())
					_event("A %s sailed %d exports short: none ready in the yard" % [ship.kind, ship.exports])
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
	# Shippers dislike storage fees above the fair rate, and the line hears it.
	var fees: float = rules.storage.satisfaction_per_dollar * maxf(storage.fee - rules.storage.fair_fee, 0.0)
	_event_if(contracts.called(ship.line, late, ship.moves / hours if hours > 0.0 else 0.0, kpis().gate_turn_minutes, fees))


## One crane's tick discharging: it needs a tractor sent under it, works its
## move while the tractor comes, and lowers the box once the tractor is there.
func _discharge(crane: Crane, ship: Ship, move_minutes: float) -> void:
	if crane.tractor == 0 and not _send_tractor(crane):
		return
	crane.timer = minf(crane.timer + SimClock.CALENDAR_MINUTES_PER_TICK, move_minutes)
	var tractor := _vehicle(crane.tractor)
	if crane.timer < move_minutes or tractor.state != "under_crane":
		return
	crane.timer = 0.0
	crane.tractor = 0
	var id := _new_box("import", clock.calendar_minutes() + rules.import_dwell_minutes * _dwell_factor())
	ship.boxes -= 1
	ship.moves += 1
	ledger.post("moves", move_price(boxes[id]))
	tractor.box = id
	tractor.loaded = true
	_head_for(tractor, yard.entrance(tractor.target))
	if ship.boxes == 0:
		_release_idle_tractors(ship)


## One crane's tick loading: it sends a tractor to fetch an export while the
## ship has room for more than are already on their way, then lifts the box
## aboard once the tractor is back beneath it.
func _load(crane: Crane, ship: Ship, move_minutes: float) -> void:
	if crane.tractor == 0:
		var fetching := _cranes_for(ship).filter(func(c: Crane) -> bool: return c.tractor != 0).size()
		if ship.exports > fetching:
			_send_fetcher(crane)
		return
	var tractor := _vehicle(crane.tractor)
	if tractor.state != "under_crane":
		return
	crane.timer += SimClock.CALENDAR_MINUTES_PER_TICK
	if crane.timer < move_minutes:
		return
	crane.timer = 0.0
	crane.tractor = 0
	ledger.post("moves", move_price(boxes[tractor.box]))
	boxes.erase(tractor.box)
	ship.exports -= 1
	ship.moves += 1
	_leave(tractor)


func _new_box(kind: String, due: float) -> int:
	var id := _next_box
	_next_box += 1
	var teu := 2 if rng.randf() < rules.box_mix.forty_share else 1
	boxes[id] = {"kind": kind, "due": due, "teu": teu, "reefer": rng.randf() < rules.box_mix.reefer_share, "in": -1.0}
	return id


## Puts `box` into the yard at `tile` and starts its storage clock.
func _stack(tile: Vector2i, box: int) -> void:
	yard.add(tile, box)
	boxes[box].in = clock.calendar_minutes()


## Boxes in the yard past their free days.
func _storage_due() -> int:
	var now := clock.calendar_minutes()
	var count := 0
	for tile: Vector2i in yard.stacks:
		for id: int in yard.stacks[tile]:
			if boxes[id].in >= 0.0 and now - boxes[id].in > storage.free_days * SimClock.MINUTES_PER_DAY:
				count += 1
	return count


## Higher storage fees make shippers collect imports sooner, down to a floor.
func _dwell_factor() -> float:
	return maxf(rules.storage.min_dwell_factor, 1.0 / (1.0 + storage.fee * rules.storage.dwell_per_dollar))


## Sends a parked tractor under `crane`, off the road on the quay, with an
## import yard tile reserved for the box it will take. False, with the
## reason in the events, when that can't happen yet.
func _send_tractor(crane: Crane) -> bool:
	var home := _tractor_home(crane)
	if home == PortMap.NONE:
		return false
	var tile := _yard_tile_for("import", home)
	if tile == PortMap.NONE:
		_event("A ship is waiting: no import yard space reachable from its quay")
		return false
	var path: Array[Vector2i] = [home]
	var tractor := Vehicle.new(_next_vehicle, "tractor", path)
	_next_vehicle += 1
	tractor.state = "under_crane"
	tractor.home = home
	tractor.target = tile
	yard.reserve(tile, 1)
	vehicles.append(tractor)
	crane.tractor = tractor.id
	return true


## Sends a parked tractor from behind `crane` to fetch the nearest export.
func _send_fetcher(crane: Crane) -> void:
	var home := _tractor_home(crane)
	if home == PortMap.NONE:
		return
	var found := _export_for(home)
	if found.is_empty():
		return
	var path := map.route(home, yard.entrance(found.tile))
	var tractor := Vehicle.new(_next_vehicle, "tractor", path)
	tractor.lane = Traffic.lane(map, path, 0)
	if not traffic.claim(tractor.lane, tractor.id):
		return
	_next_vehicle += 1
	tractor.home = home
	tractor.target = found.tile
	tractor.box = found.box
	_claimed[found.box] = true
	vehicles.append(tractor)
	crane.tractor = tractor.id


## The road behind `crane` if a tractor is free to park there, else NONE
## with the reason in the events.
func _tractor_home(crane: Crane) -> Vector2i:
	if _tractors_out() >= tractors:
		_event("A crane is waiting for a free tractor")
		return PortMap.NONE
	var home := map.access_road(crane.cell)
	if home == PortMap.NONE:
		_event("A crane has no road behind it for tractors")
	return home


## The nearest unclaimed export by road from `from`: {"box", "tile"}, or {}.
func _export_for(from: Vector2i) -> Dictionary:
	var best := {}
	var best_length := 1 << 30
	for block_anchor in yard.anchors():
		if yard.role_of(block_anchor) != "export":
			continue
		var way_in := yard.entrance(block_anchor)
		var path := map.route(from, way_in) if way_in != PortMap.NONE else ([] as Array[Vector2i])
		if path.is_empty() or path.size() >= best_length:
			continue
		for tile in yard.block(block_anchor):
			for id: int in yard.stacks.get(tile, []):
				if id not in _claimed and boxes[id].kind == "export":
					best = {"box": id, "tile": tile}
					best_length = path.size()
					break
			if best_length == path.size():
				break
	return best


## Tractors sent under `ship`'s cranes for imports that never came go back to park.
func _release_idle_tractors(ship: Ship) -> void:
	for crane in _cranes_for(ship):
		var tractor := _vehicle(crane.tractor)
		if tractor and tractor.state == "under_crane" and not tractor.loaded:
			yard.reserve(tractor.target, -1)
			_leave(tractor)
			crane.tractor = 0
			crane.timer = 0.0


func _tractors_out() -> int:
	return vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "tractor").size()


func _vehicle(id: int) -> Vehicle:
	for vehicle in vehicles:
		if vehicle.id == id:
			return vehicle
	return null


## The cranes along `ship` whose outreach reaches across it.
func _cranes_for(ship: Ship) -> Array[Crane]:
	var found: Array[Crane] = []
	for crane in cranes:
		if crane.cell in ship.cells and rules.sts_crane.outreach >= rules.ship_classes[ship.kind].outreach:
			found.append(crane)
	return found


## The roomiest tile of the nearest yard block with `role` and room, by road
## from `from`, or NONE.
func _yard_tile_for(role: String, from: Vector2i) -> Vector2i:
	var best := PortMap.NONE
	var best_length := 1 << 30
	for block_anchor in yard.anchors():
		if yard.role_of(block_anchor) != role:
			continue
		var tile := yard.roomiest(block_anchor)
		var way_in := yard.entrance(block_anchor)
		if tile == PortMap.NONE or way_in == PortMap.NONE:
			continue
		var path := map.route(from, way_in)
		if not path.is_empty() and path.size() < best_length:
			best = tile
			best_length = path.size()
	return best


## Sends a lorry from the highway for an import box whose dwell is over.
func _dispatch_import_lorry() -> bool:
	var now := clock.calendar_minutes()
	var gated := not map.cells_of(PortMap.Tile.GATE).is_empty()
	for tile: Vector2i in yard.stacks:
		var way_in := yard.entrance(tile)
		# A block lorries can't reach must not hold up the others.
		if gated and (way_in == PortMap.NONE or _route_via_gate(map.entry, way_in).is_empty()):
			continue
		for id: int in yard.stacks[tile]:
			if id in _claimed or boxes[id].kind != "import" or boxes[id].due > now:
				continue
			var lorry := _new_lorry(way_in)
			if lorry == null:
				return false
			lorry.box = id
			lorry.target = tile
			_claimed[id] = true
			return true
	return false


## Sends a lorry from the highway with an export box for the nearest export
## block with room.
func _dispatch_export_lorry() -> bool:
	var tile := _yard_tile_for("export", map.entry)
	if tile == PortMap.NONE:
		return false
	var lorry := _new_lorry(yard.entrance(tile))
	if lorry == null:
		return false
	lorry.box = _new_box("export", 0.0)
	lorry.loaded = true
	lorry.target = tile
	yard.reserve(tile, 1)
	return true


## A lorry at the highway heading for `to` through a gate, or null when
## there is no such road or the highway's lane is taken this tick.
func _new_lorry(to: Vector2i) -> Vehicle:
	if map.cells_of(PortMap.Tile.GATE).is_empty():
		_event("Lorries can't come in: build a gate on the road from the highway")
		return null
	var path := _route_via_gate(map.entry, to)
	if path.is_empty():
		return null
	var lorry := Vehicle.new(_next_vehicle, "lorry", path)
	lorry.lane = Traffic.lane(map, path, 0)
	if not traffic.claim(lorry.lane, lorry.id):
		return null
	_next_vehicle += 1
	vehicles.append(lorry)
	return lorry


## Import lorries drive to their box's block, wait for a machine to load it,
## drive back to the highway and pay. Export lorries drive their box to its
## block, are paid once a machine has stacked it, and drive back empty.
func _drive_lorry(lorry: Vehicle) -> void:
	match lorry.state:
		"drive":
			if not _advance(lorry, rules.lorry_speed):
				_unstick(lorry)
			elif lorry.box == 0:
				_leave(lorry)
			elif lorry.loaded and boxes[lorry.box].kind == "import":
				boxes.erase(lorry.box)
				_leave(lorry)
				delivered += 1
			else:
				lorry.state = "yard"
		"yard":
			_start_handling(lorry)
		"handling":
			if not _handled(lorry):
				return
			if lorry.loaded:
				yard.reserve(lorry.target, -1)
				_stack(lorry.target, lorry.box)
				lorry.box = 0
				lorry.loaded = false
				delivered += 1
			else:
				dwell_times.append(clock.calendar_minutes() - boxes[lorry.box].in)
				if dwell_times.size() > 50:
					dwell_times.pop_front()
				yard.take(lorry.target, lorry.box)
				_claimed.erase(lorry.box)
				lorry.loaded = true
			_head_for(lorry, map.entry)
		"gate":
			lorry.timer -= SimClock.CALENDAR_MINUTES_PER_TICK
			if lorry.timer <= 0.0:
				lorry.state = "drive"
		"no_route":
			_head_for(lorry, map.entry)


## The cheapest road route from `from` to `to` through a gate, counting each
## lorry still to cross that gate the same way (a gate has a lane each way)
## as rules.gate_minutes of driving, so lorries spread over parallel gates.
## Empty when no gate connects them.
func _route_via_gate(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_cost := INF
	for gate in map.cells_of(PortMap.Tile.GATE):
		var there := map.route(from, gate)
		var on := map.route(gate, to) if to != PortMap.NONE else ([] as Array[Vector2i])
		if there.is_empty() or on.is_empty():
			continue
		var route := there + on.slice(1)
		var queue := _queue_at(gate, Traffic.lane(map, route, there.size() - 1))
		var cost: float = route.size() + queue * rules.gate_minutes * rules.lorry_speed
		if cost < best_cost:
			best_cost = cost
			best = route
	return best


## Lorries that have yet to cross `gate` in `lane`.
func _queue_at(gate: Vector2i, lane: Vector3i) -> int:
	var count := 0
	for vehicle in vehicles:
		if vehicle.kind != "lorry":
			continue
		for k in range(int(vehicle.t), vehicle.path.size()):
			if vehicle.path[k] == gate and Traffic.lane(map, vehicle.path, k) == lane:
				count += 1
				break
	return count


## Tractors carry imports from under a crane to a block, and fetch exports
## from a block back to under a crane, waiting for a machine at the block.
func _drive_tractor(tractor: Vehicle) -> void:
	match tractor.state:
		"drive":
			if not _advance(tractor, rules.tractor.speed):
				_unstick(tractor)
			elif tractor.box == 0:
				_leave(tractor)
			elif tractor.loaded and boxes[tractor.box].kind == "export":
				traffic.release(tractor.lane, tractor.id)
				tractor.lane = Traffic.NO_LANE
				tractor.state = "under_crane"
			else:
				tractor.state = "yard"
		"yard":
			_start_handling(tractor)
		"handling":
			if not _handled(tractor):
				return
			if tractor.loaded:
				yard.reserve(tractor.target, -1)
				_stack(tractor.target, tractor.box)
				tractor.box = 0
				tractor.loaded = false
			else:
				yard.take(tractor.target, tractor.box)
				_claimed.erase(tractor.box)
				tractor.loaded = true
			_head_for(tractor, tractor.home)
		"no_route":
			var going := yard.entrance(tractor.target) if (tractor.loaded and boxes[tractor.box].kind == "import") else tractor.home
			_head_for(tractor, going)


## Starts a machine of the vehicle's target block working for it, if one is
## free. The vehicle pulls off the road into the block's bay, so the queue
## behind it and traffic the other way can move.
func _start_handling(vehicle: Vehicle) -> void:
	var block_anchor := yard.anchor(vehicle.target)
	if not yard.machine_free(block_anchor):
		return
	traffic.release(vehicle.lane, vehicle.id)
	vehicle.lane = Traffic.NO_LANE
	yard.busy[block_anchor] = yard.busy.get(block_anchor, 0) + 1
	vehicle.block = block_anchor
	vehicle.timer = yard.handling_minutes(vehicle.target)
	vehicle.state = "handling"


## Counts down the machine's work; true, with the machine freed, once done.
func _handled(vehicle: Vehicle) -> bool:
	vehicle.timer -= SimClock.CALENDAR_MINUTES_PER_TICK
	if vehicle.timer > 0.0:
		return false
	yard.busy[vehicle.block] -= 1
	if yard.busy[vehicle.block] == 0:
		yard.busy.erase(vehicle.block)
	return true


## Points `vehicle` along the road from where it stands to `to`'s access road.
## With no such road, or its first lane taken, it waits in "no_route" and
## tries again next tick.
func _head_for(vehicle: Vehicle, to: Vector2i) -> void:
	var here := vehicle.path[int(vehicle.t)]
	var path: Array[Vector2i] = []
	if vehicle.kind == "lorry":
		path = _route_via_gate(here, to)
	elif to != PortMap.NONE:
		path = map.route(here, to)
	if path.is_empty() or not _move_to_lane(vehicle, Traffic.lane(map, path, 0)):
		vehicle.state = "no_route"
		return
	vehicle.path = path
	vehicle.t = 0.0
	vehicle.prev_t = 0.0
	vehicle.waited = 0
	vehicle.replanned = false
	vehicle.state = "drive"


## Moves `vehicle` up to one tile along its path at `speed` tiles per vehicle
## second, entering the next tile only once it holds that tile's lane.
## Returns whether it is at the end of its path.
func _advance(vehicle: Vehicle, speed: float) -> bool:
	vehicle.prev_t = vehicle.t
	if vehicle.at_end():
		return true
	var i := int(vehicle.t)
	var target := minf(vehicle.t + speed * SimClock.TICK_SECONDS, i + 1.99)
	if int(target) > i:
		if not _enter(vehicle, i + 1):
			vehicle.t = maxf(vehicle.t, minf(target, i + 0.95))
			vehicle.waited += 1
			return false
		vehicle.waited = 0
		if vehicle.kind == "lorry" and map.tile(vehicle.path[i + 1]) == PortMap.Tile.GATE:
			vehicle.t = i + 1
			_at_gate(vehicle)
			return false
	vehicle.t = minf(target, vehicle.path.size() - 1)
	return vehicle.at_end()


## A lorry entering a gate stops to be processed. Coming in it starts its
## turn-time clock; going out it records the turn time.
func _at_gate(lorry: Vehicle) -> void:
	lorry.state = "gate"
	lorry.timer = rules.gate_minutes
	var now := clock.calendar_minutes()
	if lorry.gate_in < 0.0:
		lorry.gate_in = now
		return
	turn_times.append(now - lorry.gate_in)
	if turn_times.size() > 50:
		turn_times.pop_front()
	lorry.gate_in = -1.0


## The safety valve for jams: after give_up_seconds a vehicle tries a route
## around the tile it is waiting for; after twice that, a lorry gives up and
## leaves with whatever it carries, paying nothing. Tractors keep waiting.
func _unstick(vehicle: Vehicle) -> void:
	var limit := roundi(rules.give_up_seconds / SimClock.TICK_SECONDS)
	if vehicle.waited >= limit and not vehicle.replanned:
		vehicle.replanned = true
		var i := int(vehicle.t)
		var around := map.route_avoiding(vehicle.path[i], vehicle.path[-1], vehicle.path[i + 1])
		if not around.is_empty():
			vehicle.path = around
			vehicle.t = 0.0
			vehicle.prev_t = 0.0
	# shortcut: a lorry's way round ignores gates, so it may skip one; rare, revisit with cost routing in M6.
	elif vehicle.waited >= limit * 2 and vehicle.kind == "lorry":
		if vehicle.loaded:
			if boxes[vehicle.box].kind == "export":
				yard.reserve(vehicle.target, -1)
			boxes.erase(vehicle.box)
		elif vehicle.box != 0:
			_claimed.erase(vehicle.box)
		_leave(vehicle)
		gave_up += 1
		_event("A lorry gave up on a traffic jam and left")


## Moves `vehicle` into the lane of `path[i]`. Don't block the box: it enters
## a junction only if it can also take the lane just past it, so it never
## stands in a junction blocking crossing traffic.
func _enter(vehicle: Vehicle, i: int) -> bool:
	var next := Traffic.lane(map, vehicle.path, i)
	if next == vehicle.ahead:
		vehicle.ahead = Traffic.NO_LANE
		return _move_to_lane(vehicle, next)
	if vehicle.ahead != Traffic.NO_LANE:
		# The map changed under it, so the lane it booked past the junction
		# is not its next lane any more: let that booking go.
		traffic.release(vehicle.ahead, vehicle.id)
		vehicle.ahead = Traffic.NO_LANE
	if next.z != Traffic.JUNCTION or i + 1 >= vehicle.path.size():
		# shortcut: a path that ends in a junction stops in it; fine while yard entrances and homes rarely sit on junctions.
		return _move_to_lane(vehicle, next)
	var after := Traffic.lane(map, vehicle.path, i + 1)
	if not traffic.claim(after, vehicle.id):
		return false
	if not _move_to_lane(vehicle, next):
		traffic.release(after, vehicle.id)
		return false
	vehicle.ahead = after
	return true


## Takes `lane` for `vehicle` and lets go of the one it held. At a junction
## both can be the same shared lane, which must then stay held.
func _move_to_lane(vehicle: Vehicle, lane: Vector3i) -> bool:
	if lane == vehicle.lane:
		return true
	if not traffic.claim(lane, vehicle.id):
		return false
	traffic.release(vehicle.lane, vehicle.id)
	vehicle.lane = lane
	return true


func _leave(vehicle: Vehicle) -> void:
	traffic.release(vehicle.lane, vehicle.id)
	traffic.release(vehicle.ahead, vehicle.id)
	vehicles.erase(vehicle)
