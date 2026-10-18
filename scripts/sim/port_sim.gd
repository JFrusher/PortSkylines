class_name PortSim
extends RefCounted
## Money and logistics. Ships bring boxes to quays, cranes stack them in the
## nearest yard reachable by road, and lorries from the highway collect them
## and pay a fee per box.

## Every tunable number, from data/base/*.json; see Content.
var rules: Dictionary
var map: PortMap
var clock := SimClock.new()
## The only source of randomness in the sim, so a seed and a command log replay exactly.
var rng := RandomNumberGenerator.new()
var money := 0
var delivered := 0
var status := "Run a road from the highway to the coast, then build a quay and a yard"
var ships: Array[Ship] = []
var cranes: Array[Crane] = []
var lorries: Array[Lorry] = []
## Boxes stacked on each yard tile.
var stacked := {}

## Boxes on each yard tile that a lorry is already coming for.
var _claimed := {}
## Calendar minutes until the next ship and the next lorry dispatch.
var _until_ship := 0.0
var _until_lorry := 0.0


func _init(seed_value := 0, game_rules := Content.base()) -> void:
	rules = game_rules
	map = PortMap.new(Vector2i(rules.map.width, rules.map.height), rules.map.sea_width)
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
	var boxes: int
	var state := State.ARRIVING
	## 0 out at sea, 1 alongside the quay.
	var sail := 0.0
	## `sail` at the start of this tick, for drawing between ticks.
	var prev_sail := 0.0
	func _init(ship_kind: String, along: Array[Vector2i], water_side: Vector2i, cargo: int) -> void:
		kind = ship_kind
		cells = along
		side = water_side
		boxes = cargo

	func to_dict() -> Dictionary:
		return {"kind": kind, "cells": cells.duplicate(), "side": side, "boxes": boxes, "state": state, "sail": sail, "prev_sail": prev_sail}

	static func from_dict(d: Dictionary) -> Ship:
		var along: Array[Vector2i] = []
		along.assign(d.cells)
		var ship := Ship.new(d.kind, along, d.side, d.boxes)
		ship.state = d.state
		ship.sail = d.sail
		ship.prev_sail = d.prev_sail
		return ship


## A ship-to-shore crane on a quay tile. It works any ship lying along its
## tile that its outreach can reach across.
class Crane:
	var cell: Vector2i
	## Calendar minutes into the current move.
	var timer := 0.0

	func _init(at: Vector2i) -> void:
		cell = at

	func to_dict() -> Dictionary:
		return {"cell": cell, "timer": timer}

	static func from_dict(d: Dictionary) -> Crane:
		var crane := Crane.new(d.cell)
		crane.timer = d.timer
		return crane


class Lorry:
	var path: Array[Vector2i]
	var yard: Vector2i
	var loaded := false
	## Distance travelled along `path`, in tiles.
	var t := 0.0
	## `t` at the start of this tick, for drawing between ticks.
	var prev_t := 0.0

	func _init(route: Array[Vector2i], to_yard: Vector2i) -> void:
		path = route
		yard = to_yard

	func to_dict() -> Dictionary:
		return {"path": path.duplicate(), "yard": yard, "loaded": loaded, "t": t, "prev_t": prev_t}

	static func from_dict(d: Dictionary) -> Lorry:
		var route: Array[Vector2i] = []
		route.assign(d.path)
		var lorry := Lorry.new(route, d.yard)
		lorry.loaded = d.loaded
		lorry.t = d.t
		lorry.prev_t = d.prev_t
		return lorry

	## Position in tile coordinates, `alpha` of the way from the last tick to this one.
	func position(alpha: float) -> Vector2:
		var at := lerpf(prev_t, t, alpha)
		var i := mini(int(at), path.size() - 1)
		var j := mini(i + 1, path.size() - 1)
		return Vector2(path[i]).lerp(Vector2(path[j]), clampf(at - i, 0.0, 1.0))


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
		"lorries": lorries.map(func(lorry: Lorry) -> Dictionary: return lorry.to_dict()),
		"stacked": stacked.duplicate(),
		"claimed": _claimed.duplicate(),
		"until_ship": _until_ship,
		"until_lorry": _until_lorry,
	}


static func from_dict(d: Dictionary) -> PortSim:
	var sim := PortSim.new()
	sim.map = PortMap.from_dict(d.map)
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
	for lorry: Dictionary in d.lorries:
		sim.lorries.append(Lorry.from_dict(lorry))
	sim.stacked = d.stacked.duplicate()
	sim._claimed = d.claimed.duplicate()
	sim._until_ship = d.until_ship
	sim._until_lorry = d.until_lorry
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


func _crane_at(cell: Vector2i) -> Crane:
	for crane in cranes:
		if crane.cell == cell:
			return crane
	return null


## Bulldozing a quay tile with a crane removes the crane first.
func bulldoze_error(cell: Vector2i) -> String:
	var crane := _crane_at(cell)
	if crane and _ship_at(cell):
		return "The crane is working a ship"
	if crane:
		return ""
	var err := map.bulldoze_error(cell)
	if err != "":
		return err
	if stacked.get(cell, 0) > 0:
		return "The yard still holds boxes"
	for ship in ships:
		if cell in ship.cells:
			return "A ship is alongside"
	for lorry in lorries:
		if cell in lorry.path:
			return "Lorries are using this road"
	return ""


func bulldoze(cell: Vector2i) -> String:
	var err := bulldoze_error(cell)
	var crane := _crane_at(cell)
	if err == "" and crane:
		cranes.erase(crane)
	elif err == "":
		map.place(PortMap.Tile.LAND, cell)
		stacked.erase(cell)
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
	if _until_lorry <= 0.0 and _dispatch_lorry():
		_until_lorry = rules.lorry_interval_minutes
	for lorry: Lorry in lorries.duplicate():
		_drive(lorry)


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
		ships.append(Ship.new(kind, span, berth.side, spec.import_moves))
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


func _work(ship: Ship) -> void:
	ship.prev_sail = ship.sail
	match ship.state:
		Ship.State.ARRIVING:
			ship.sail = minf(ship.sail + SimClock.TICK_SECONDS / rules.sail_seconds, 1.0)
			if ship.sail == 1.0:
				ship.state = Ship.State.WORKING
				status = "A ship is unloading"
		Ship.State.WORKING:
			var working := _cranes_for(ship)
			if working.is_empty():
				status = "A %s is waiting: no crane on its berth reaches %d rows" % [ship.kind, rules.ship_classes[ship.kind].outreach]
				return
			var move_minutes: float = 60.0 / (rules.sts_crane.rate * rules.crane_interference)
			for crane in working:
				if ship.boxes == 0:
					break
				crane.timer += SimClock.CALENDAR_MINUTES_PER_TICK
				if crane.timer < move_minutes:
					continue
				var yard := _nearest_yard_with_space(_apron(ship.cells))
				if yard == PortMap.NONE:
					crane.timer = move_minutes
					status = "A ship is waiting: no yard space reachable from its quay"
					continue
				crane.timer -= move_minutes
				# shortcut: the box jumps from crane to yard, add terminal tractors in M2.
				ship.boxes -= 1
				stacked[yard] = stacked.get(yard, 0) + 1
			if ship.boxes == 0:
				for crane in working:
					crane.timer = 0.0
				ship.state = Ship.State.LEAVING
		Ship.State.LEAVING:
			ship.sail -= SimClock.TICK_SECONDS / rules.sail_seconds
			if ship.sail <= 0.0:
				ships.erase(ship)


## The cranes along `ship` whose outreach reaches across it.
func _cranes_for(ship: Ship) -> Array[Crane]:
	var found: Array[Crane] = []
	for crane in cranes:
		if crane.cell in ship.cells and rules.sts_crane.outreach >= rules.ship_classes[ship.kind].outreach:
			found.append(crane)
	return found


func _nearest_yard_with_space(quay: Vector2i) -> Vector2i:
	var best := PortMap.NONE
	var best_length := 1 << 30
	for yard in map.cells_of(PortMap.Tile.YARD):
		if stacked.get(yard, 0) >= rules.yard_capacity:
			continue
		var path := map.route(quay, yard)
		if not path.is_empty() and path.size() < best_length:
			best = yard
			best_length = path.size()
	return best


func _dispatch_lorry() -> bool:
	for yard: Vector2i in stacked:
		if stacked[yard] <= _claimed.get(yard, 0):
			continue
		var path := map.route(map.entry, yard)
		if path.is_empty():
			continue
		_claimed[yard] = _claimed.get(yard, 0) + 1
		lorries.append(Lorry.new(path, yard))
		return true
	return false


func _drive(lorry: Lorry) -> void:
	# shortcut: lorries drive through each other, add cell reservation in M2.
	lorry.prev_t = lorry.t
	lorry.t += rules.lorry_speed * SimClock.TICK_SECONDS
	if lorry.t < lorry.path.size() - 1:
		return
	if lorry.loaded:
		lorries.erase(lorry)
		money += rules.fee_per_box
		delivered += 1
		return
	stacked[lorry.yard] -= 1
	_claimed[lorry.yard] -= 1
	lorry.loaded = true
	lorry.path.reverse()
	lorry.t = 0.0
	lorry.prev_t = 0.0
