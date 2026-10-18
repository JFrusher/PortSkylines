class_name PortSim
extends RefCounted
## The port. Ships call at berths. Quay cranes lift their imports onto
## terminal tractors, which carry them to import blocks where yard machines
## stack them; after their dwell, lorries from the highway collect them.
## Lorries also bring exports to export blocks; once a ship is discharged,
## tractors fetch exports to its cranes, which load them. Lorries pay a fee
## per box in or out. Changed only through apply(command) and tick().

## Every tunable number, from data/base/*.json; see Content.
var rules: Dictionary
var map: PortMap
var clock := SimClock.new()
## The only source of randomness in the sim, so a seed and a command log replay exactly.
var rng := RandomNumberGenerator.new()
var money := 0
## Boxes through the highway: imports out and exports in.
var delivered := 0
var status := "Run a road from the highway to the coast, then build a quay, cranes, tractors and a yard"
var ships: Array[Ship] = []
var cranes: Array[Crane] = []
var vehicles: Array[Vehicle] = []
var traffic := Traffic.new()
var yard: Yard
## Every box in the port by id: {"kind": "import" or "export", "due": the
## calendar minute an import may leave}. A box is always in exactly one
## place: on a vehicle or in a yard stack (boxes on ships are only counted).
var boxes := {}
## Terminal tractors owned. Those not on the road are parked beside the quay.
var tractors := 0
## Lorries that gave up on a traffic jam and left; see _unstick.
var gave_up := 0

## Boxes a vehicle is already coming for.
var _claimed := {}
## Calendar minutes until the next ship, import lorry and export lorry.
var _until_ship := 0.0
var _until_lorry := 0.0
var _until_export := 0.0
var _next_vehicle := 1
var _next_box := 1


func _init(seed_value := 0, game_rules := Content.base()) -> void:
	rules = game_rules
	map = PortMap.new(Vector2i(rules.map.width, rules.map.height), rules.map.sea_width)
	yard = Yard.new(map, rules)
	money = rules.start_money
	_until_ship = rules.first_ship_minutes
	rng.seed = seed_value


func cost(kind: int) -> int:
	return rules.build_cost[PortMap.Tile.keys()[kind].to_lower()]


class Ship:
	enum State { ARRIVING, WORKING, LEAVING }
	## Its class, a key of rules.ship_classes.
	var kind: String
	## The quay tiles it lies along, in order.
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

	func _init(ship_kind: String, along: Array[Vector2i], water_side: Vector2i, imports: int, export_room: int) -> void:
		kind = ship_kind
		cells = along
		side = water_side
		boxes = imports
		exports = export_room

	func to_dict() -> Dictionary:
		return {"kind": kind, "cells": cells.duplicate(), "side": side, "boxes": boxes, "exports": exports, "state": state, "sail": sail, "prev_sail": prev_sail}

	static func from_dict(d: Dictionary) -> Ship:
		var along: Array[Vector2i] = []
		along.assign(d.cells)
		var ship := Ship.new(d.kind, along, d.side, d.boxes, d.exports)
		ship.state = d.state
		ship.sail = d.sail
		ship.prev_sail = d.prev_sail
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
		"money": money,
		"delivered": delivered,
		"status": status,
		"ships": ships.map(func(ship: Ship) -> Dictionary: return ship.to_dict()),
		"cranes": cranes.map(func(crane: Crane) -> Dictionary: return crane.to_dict()),
		"vehicles": vehicles.map(func(vehicle: Vehicle) -> Dictionary: return vehicle.to_dict()),
		"yard": yard.to_dict(),
		"boxes": boxes.duplicate(true),
		"tractors": tractors,
		"gave_up": gave_up,
		"claimed": _claimed.duplicate(),
		"until_ship": _until_ship,
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
	sim.money = d.money
	sim.delivered = d.delivered
	sim.status = d.status
	for ship: Dictionary in d.ships:
		sim.ships.append(Ship.from_dict(ship))
	for crane: Dictionary in d.cranes:
		sim.cranes.append(Crane.from_dict(crane))
	for data: Dictionary in d.vehicles:
		var vehicle := Vehicle.from_dict(data)
		sim.vehicles.append(vehicle)
		if vehicle.lane != Traffic.NO_LANE:
			sim.traffic.claim(vehicle.lane, vehicle.id)
	sim.boxes = d.boxes.duplicate(true)
	sim.tractors = d.tractors
	sim.gave_up = d.gave_up
	sim._claimed = d.claimed.duplicate()
	sim._until_ship = d.until_ship
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
	return "Unknown command: %s" % command.get("op")


func build_error(kind: int, cell: Vector2i) -> String:
	var err := map.build_error(kind, cell)
	if err == "" and money < cost(kind):
		err = "Not enough money"
	return err


func build(kind: int, cell: Vector2i) -> String:
	var err := build_error(kind, cell)
	if err == "":
		money -= cost(kind)
		map.place(kind, cell)
	return err


func crane_error(cell: Vector2i) -> String:
	if map.tile(cell) != PortMap.Tile.QUAY:
		return "Cranes stand on quay tiles"
	if _crane_at(cell):
		return "There is a crane here already"
	if money < rules.sts_crane.cost:
		return "Not enough money"
	return ""


func place_crane(cell: Vector2i) -> String:
	var err := crane_error(cell)
	if err == "":
		money -= rules.sts_crane.cost
		cranes.append(Crane.new(cell))
	return err


func buy_tractors(count: int) -> String:
	if count < 1:
		return "Buy at least one tractor"
	if money < rules.tractor.cost * count:
		return "Not enough money"
	money -= rules.tractor.cost * count
	tractors += count
	return ""


func set_yard_error(cell: Vector2i, settings: Dictionary) -> String:
	var err := yard.settings_error(cell, settings)
	if err == "" and settings.has("gear") and money < yard.gear_cost(cell, settings.gear):
		err = "Not enough money"
	return err


## Sets the role ("import"/"export") and/or gear of the yard block at `cell`.
func set_yard(cell: Vector2i, settings: Dictionary) -> String:
	var err := set_yard_error(cell, settings)
	if err == "":
		if settings.has("gear"):
			money -= yard.gear_cost(cell, settings.gear)
		yard.apply_settings(cell, settings)
	return err


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
	_until_ship -= SimClock.CALENDAR_MINUTES_PER_TICK
	if _until_ship <= 0.0:
		_until_ship = rules.ship_interval_minutes
		_call_ship()
	for ship: Ship in ships.duplicate():
		_work(ship)
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


## A ship of a random class (weighted by the data) calls at the first free
## berth long and deep enough with a road to the highway, or goes elsewhere.
func _call_ship() -> void:
	var kind := _pick_ship_kind()
	var spec: Dictionary = rules.ship_classes[kind]
	if rules.water_depth < spec.draft:
		status = "A %s went elsewhere: it needs %.0f m of water, the port has %.0f m" % [kind, spec.draft, rules.water_depth]
		return
	for berth: Dictionary in map.berths():
		var cells: Array[Vector2i] = berth.cells
		if cells.size() < spec.length or _ship_at(cells[0]):
			continue
		var span := cells.slice(0, spec.length)
		if _apron(span) == PortMap.NONE:
			continue
		ships.append(Ship.new(kind, span, berth.side, spec.import_moves, spec.export_moves))
		status = "A %s is coming in" % kind
		return
	status = "A %s went elsewhere: no free berth of %d quay tiles with a road to the highway" % [kind, spec.length]


func _pick_ship_kind() -> String:
	var total := 0.0
	for kind: String in rules.ship_classes:
		total += rules.ship_classes[kind].weight
	var pick := rng.randf() * total
	for kind: String in rules.ship_classes:
		pick -= rules.ship_classes[kind].weight
		if pick < 0.0:
			return kind
	return rules.ship_classes.keys()[-1]


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
		Ship.State.ARRIVING:
			ship.sail = minf(ship.sail + SimClock.TICK_SECONDS / rules.sail_seconds, 1.0)
			if ship.sail == 1.0:
				ship.state = Ship.State.WORKING
				status = "A %s is unloading" % ship.kind
		Ship.State.WORKING:
			var working := _cranes_for(ship)
			if working.is_empty():
				status = "A %s is waiting: no crane on its berth reaches %d rows" % [ship.kind, rules.ship_classes[ship.kind].outreach]
				return
			var move_minutes: float = 60.0 / (rules.sts_crane.rate * rules.crane_interference)
			for crane in working:
				if ship.boxes > 0:
					_discharge(crane, ship, move_minutes)
				else:
					_load(crane, ship, move_minutes)
			if ship.boxes == 0 and working.all(func(c: Crane) -> bool: return c.tractor == 0):
				if ship.exports == 0:
					ship.state = Ship.State.LEAVING
					status = "A %s is sailing, fully loaded" % ship.kind
				elif _export_for(map.access_road(working[0].cell)).is_empty():
					ship.state = Ship.State.LEAVING
					status = "A %s sailed %d exports short: none ready in the yard" % [ship.kind, ship.exports]
		Ship.State.LEAVING:
			ship.sail -= SimClock.TICK_SECONDS / rules.sail_seconds
			if ship.sail <= 0.0:
				ships.erase(ship)


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
	var id := _new_box("import", clock.calendar_minutes() + rules.import_dwell_minutes)
	ship.boxes -= 1
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
	boxes.erase(tractor.box)
	ship.exports -= 1
	_leave(tractor)


func _new_box(kind: String, due: float) -> int:
	var id := _next_box
	_next_box += 1
	boxes[id] = {"kind": kind, "due": due}
	return id


## Sends a parked tractor under `crane`, off the road on the quay, with an
## import yard tile reserved for the box it will take. False, with the
## reason in the status, when that can't happen yet.
func _send_tractor(crane: Crane) -> bool:
	var home := _tractor_home(crane)
	if home == PortMap.NONE:
		return false
	var tile := _yard_tile_for("import", home)
	if tile == PortMap.NONE:
		status = "A ship is waiting: no import yard space reachable from its quay"
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
## with the reason in the status.
func _tractor_home(crane: Crane) -> Vector2i:
	if _tractors_out() >= tractors:
		status = "A crane is waiting for a free tractor"
		return PortMap.NONE
	var home := map.access_road(crane.cell)
	if home == PortMap.NONE:
		status = "A crane has no road behind it for tractors"
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
	for tile: Vector2i in yard.stacks:
		for id: int in yard.stacks[tile]:
			if id in _claimed or boxes[id].kind != "import" or boxes[id].due > now:
				continue
			var lorry := _new_lorry(yard.entrance(tile))
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


## A lorry at the highway heading for `to`, or null when there is no road or
## the highway's lane is taken this tick.
func _new_lorry(to: Vector2i) -> Vehicle:
	var path := map.route(map.entry, to) if to != PortMap.NONE else ([] as Array[Vector2i])
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
				_paid()
			else:
				lorry.state = "yard"
		"yard":
			_start_handling(lorry)
		"handling":
			if not _handled(lorry):
				return
			if lorry.loaded:
				yard.reserve(lorry.target, -1)
				yard.add(lorry.target, lorry.box)
				lorry.box = 0
				lorry.loaded = false
				_paid()
			else:
				yard.take(lorry.target, lorry.box)
				_claimed.erase(lorry.box)
				lorry.loaded = true
			_head_for(lorry, map.entry)
		"no_route":
			_head_for(lorry, map.entry)


func _paid() -> void:
	money += rules.fee_per_box
	delivered += 1


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
				yard.add(tractor.target, tractor.box)
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
	var path := map.route(here, to) if to != PortMap.NONE else ([] as Array[Vector2i])
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
		if not _move_to_lane(vehicle, Traffic.lane(map, vehicle.path, i + 1)):
			vehicle.t = maxf(vehicle.t, minf(target, i + 0.95))
			vehicle.waited += 1
			return false
		vehicle.waited = 0
	vehicle.t = minf(target, vehicle.path.size() - 1)
	return vehicle.at_end()


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
	elif vehicle.waited >= limit * 2 and vehicle.kind == "lorry":
		if vehicle.loaded:
			if boxes[vehicle.box].kind == "export":
				yard.reserve(vehicle.target, -1)
			boxes.erase(vehicle.box)
		elif vehicle.box != 0:
			_claimed.erase(vehicle.box)
		_leave(vehicle)
		gave_up += 1
		status = "A lorry gave up on a traffic jam and left"


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
	vehicles.erase(vehicle)
