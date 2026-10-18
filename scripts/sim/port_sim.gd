class_name PortSim
extends RefCounted
## Money and logistics. Ships bring boxes to quays, cranes stack them in the
## nearest yard reachable by road, and lorries from the highway collect them
## and pay a fee per box.

const COST := {PortMap.Tile.ROAD: 10, PortMap.Tile.QUAY: 200, PortMap.Tile.YARD: 50}
const START_MONEY := 5000
const FEE_PER_BOX := 120
const FIRST_SHIP_MINUTES := 10.0
const SHIP_INTERVAL_MINUTES := 45.0
const SHIP_BOXES := 12
const SAIL_SECONDS := 4.0
const CRANE_MINUTES := 2.0
const YARD_CAPACITY := 6
const LORRY_INTERVAL_MINUTES := 1.0
const LORRY_SPEED := 5.0  # tiles per vehicle second

var map := PortMap.new()
var clock := SimClock.new()
## The only source of randomness in the sim, so a seed and a command log replay exactly.
var rng := RandomNumberGenerator.new()
var money := START_MONEY
var delivered := 0
var status := "Run a road from the highway to the coast, then build a quay and a yard"
var ships: Array[Ship] = []
var lorries: Array[Lorry] = []
## Boxes stacked on each yard tile.
var stacked := {}

## Boxes on each yard tile that a lorry is already coming for.
var _claimed := {}
## Calendar minutes until the next ship and the next lorry dispatch.
var _until_ship := FIRST_SHIP_MINUTES
var _until_lorry := 0.0


func _init(seed_value := 0) -> void:
	rng.seed = seed_value


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

	## Position in tile coordinates, `alpha` of the way from the last tick to this one.
	func position(alpha: float) -> Vector2:
		var at := lerpf(prev_t, t, alpha)
		var i := mini(int(at), path.size() - 1)
		var j := mini(i + 1, path.size() - 1)
		return Vector2(path[i]).lerp(Vector2(path[j]), clampf(at - i, 0.0, 1.0))


func build_error(kind: int, cell: Vector2i) -> String:
	var err := map.build_error(kind, cell)
	if err == "" and money < COST[kind]:
		err = "Not enough money"
	return err


func build(kind: int, cell: Vector2i) -> String:
	var err := build_error(kind, cell)
	if err == "":
		money -= COST[kind]
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
		_until_ship = SHIP_INTERVAL_MINUTES
		_call_ship()
	for ship: Ship in ships.duplicate():
		_work(ship)
	_until_lorry -= SimClock.CALENDAR_MINUTES_PER_TICK
	if _until_lorry <= 0.0 and _dispatch_lorry():
		_until_lorry = LORRY_INTERVAL_MINUTES
	for lorry: Lorry in lorries.duplicate():
		_drive(lorry)


func _call_ship() -> void:
	for quay in map.cells_of(PortMap.Tile.QUAY):
		var berth := map.neighbor(quay, PortMap.Tile.WATER)
		if _occupied(quay, berth) or map.route(map.entry, quay).is_empty():
			continue
		ships.append(Ship.new(quay, berth, SHIP_BOXES))
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
			ship.sail = minf(ship.sail + SimClock.TICK_SECONDS / SAIL_SECONDS, 1.0)
			if ship.sail == 1.0:
				ship.state = Ship.State.WORKING
				status = "A ship is unloading"
		Ship.State.WORKING:
			ship.crane += SimClock.CALENDAR_MINUTES_PER_TICK
			if ship.crane < CRANE_MINUTES:
				return
			var yard := _nearest_yard_with_space(ship.quay)
			if yard == PortMap.NONE:
				ship.crane = CRANE_MINUTES
				status = "A ship is waiting: no yard space reachable from its quay"
				return
			ship.crane -= CRANE_MINUTES
			# shortcut: the box jumps from crane to yard, add terminal tractors in M2.
			ship.boxes -= 1
			stacked[yard] = stacked.get(yard, 0) + 1
			if ship.boxes == 0:
				ship.state = Ship.State.LEAVING
		Ship.State.LEAVING:
			ship.sail -= SimClock.TICK_SECONDS / SAIL_SECONDS
			if ship.sail <= 0.0:
				ships.erase(ship)


func _nearest_yard_with_space(quay: Vector2i) -> Vector2i:
	var best := PortMap.NONE
	var best_length := 1 << 30
	for yard in map.cells_of(PortMap.Tile.YARD):
		if stacked.get(yard, 0) >= YARD_CAPACITY:
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
	lorry.t += LORRY_SPEED * SimClock.TICK_SECONDS
	if lorry.t < lorry.path.size() - 1:
		return
	if lorry.loaded:
		lorries.erase(lorry)
		money += FEE_PER_BOX
		delivered += 1
		return
	stacked[lorry.yard] -= 1
	_claimed[lorry.yard] -= 1
	lorry.loaded = true
	lorry.path.reverse()
	lorry.t = 0.0
	lorry.prev_t = 0.0
