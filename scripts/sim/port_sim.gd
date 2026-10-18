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
	var quay: Vector2i
	## The water tile the ship lies on.
	var berth: Vector2i
	var boxes: int
	var state := State.ARRIVING
	## 0 out at sea, 1 alongside the quay.
	var sail := 0.0
	## `sail` at the start of this tick, for drawing between ticks.
	var prev_sail := 0.0
	## Calendar minutes into the current crane move.
	var crane := 0.0

	func _init(at_quay: Vector2i, at_berth: Vector2i, cargo: int) -> void:
		quay = at_quay
		berth = at_berth
		boxes = cargo

	func to_dict() -> Dictionary:
		return {"quay": quay, "berth": berth, "boxes": boxes, "state": state, "sail": sail, "prev_sail": prev_sail, "crane": crane}

	static func from_dict(d: Dictionary) -> Ship:
		var ship := Ship.new(d.quay, d.berth, d.boxes)
		ship.state = d.state
		ship.sail = d.sail
		ship.prev_sail = d.prev_sail
		ship.crane = d.crane
		return ship


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


func bulldoze_error(cell: Vector2i) -> String:
	var err := map.bulldoze_error(cell)
	if err != "":
		return err
	if stacked.get(cell, 0) > 0:
		return "The yard still holds boxes"
	for ship in ships:
		if ship.quay == cell:
			return "A ship is alongside"
	for lorry in lorries:
		if cell in lorry.path:
			return "Lorries are using this road"
	return ""


func bulldoze(cell: Vector2i) -> String:
	var err := bulldoze_error(cell)
	if err == "":
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


func _call_ship() -> void:
	for quay in map.cells_of(PortMap.Tile.QUAY):
		var berth := map.neighbor(quay, PortMap.Tile.WATER)
		if _occupied(quay, berth) or map.route(map.entry, quay).is_empty():
			continue
		ships.append(Ship.new(quay, berth, rules.ship_boxes))
		status = "A ship is coming in"
		return
	status = "A ship went elsewhere: no free quay with a road to the highway"


func _occupied(quay: Vector2i, berth: Vector2i) -> bool:
	for ship in ships:
		if ship.quay == quay or ship.berth == berth:
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
			ship.crane += SimClock.CALENDAR_MINUTES_PER_TICK
			if ship.crane < rules.crane_minutes:
				return
			var yard := _nearest_yard_with_space(ship.quay)
			if yard == PortMap.NONE:
				ship.crane = rules.crane_minutes
				status = "A ship is waiting: no yard space reachable from its quay"
				return
			ship.crane -= rules.crane_minutes
			# shortcut: the box jumps from crane to yard, add terminal tractors in M2.
			ship.boxes -= 1
			stacked[yard] = stacked.get(yard, 0) + 1
			if ship.boxes == 0:
				ship.state = Ship.State.LEAVING
		Ship.State.LEAVING:
			ship.sail -= SimClock.TICK_SECONDS / rules.sail_seconds
			if ship.sail <= 0.0:
				ships.erase(ship)


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
