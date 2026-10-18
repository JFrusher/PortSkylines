class_name PortSim
extends RefCounted
## Money and logistics. Ships bring boxes to quays, cranes stack them in the
## nearest yard reachable by road, and lorries from the highway collect them
## and pay a fee per box.

const COST := {PortMap.Tile.ROAD: 10, PortMap.Tile.QUAY: 200, PortMap.Tile.YARD: 50}
const START_MONEY := 5000
const FEE_PER_BOX := 120
const FIRST_SHIP := 10.0
const SHIP_INTERVAL := 45.0
const SHIP_BOXES := 12
const SAIL_SECONDS := 4.0
const CRANE_SECONDS := 2.0
const YARD_CAPACITY := 6
const LORRY_INTERVAL := 1.0
const LORRY_SPEED := 5.0  # tiles per second

var map := PortMap.new()
var money := START_MONEY
var delivered := 0
var status := "Run a road from the highway to the coast, then build a quay and a yard"
var ships: Array[Ship] = []
var lorries: Array[Lorry] = []
## Boxes stacked on each yard tile.
var stacked := {}

## Boxes on each yard tile that a lorry is already coming for.
var _claimed := {}
var _until_ship := FIRST_SHIP
var _until_lorry := 0.0


class Ship:
	enum State { ARRIVING, WORKING, LEAVING }
	var quay: Vector2i
	## The water tile the ship lies on.
	var berth: Vector2i
	var boxes: int
	var state := State.ARRIVING
	## 0 out at sea, 1 alongside the quay.
	var sail := 0.0
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

	func _init(route: Array[Vector2i], to_yard: Vector2i) -> void:
		path = route
		yard = to_yard

	## Position in tile coordinates, between two path cells.
	func position() -> Vector2:
		var i := mini(int(t), path.size() - 1)
		var j := mini(i + 1, path.size() - 1)
		return Vector2(path[i]).lerp(Vector2(path[j]), clampf(t - i, 0.0, 1.0))


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


func step(dt: float) -> void:
	_until_ship -= dt
	if _until_ship <= 0.0:
		_until_ship = SHIP_INTERVAL
		_call_ship()
	for ship in ships.duplicate():
		_work(ship, dt)
	_until_lorry -= dt
	if _until_lorry <= 0.0 and _dispatch_lorry():
		_until_lorry = LORRY_INTERVAL
	for lorry in lorries.duplicate():
		_drive(lorry, dt)


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


func _work(ship: Ship, dt: float) -> void:
	match ship.state:
		Ship.State.ARRIVING:
			ship.sail = minf(ship.sail + dt / SAIL_SECONDS, 1.0)
			if ship.sail == 1.0:
				ship.state = Ship.State.WORKING
				status = "A ship is unloading"
		Ship.State.WORKING:
			ship.crane += dt
			if ship.crane < CRANE_SECONDS:
				return
			var yard := _nearest_yard_with_space(ship.quay)
			if yard == PortMap.NONE:
				ship.crane = CRANE_SECONDS
				status = "A ship is waiting: no yard space reachable from its quay"
				return
			ship.crane -= CRANE_SECONDS
			ship.boxes -= 1
			stacked[yard] = stacked.get(yard, 0) + 1
			if ship.boxes == 0:
				ship.state = Ship.State.LEAVING
		Ship.State.LEAVING:
			ship.sail -= dt / SAIL_SECONDS
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


func _drive(lorry: Lorry, dt: float) -> void:
	lorry.t += LORRY_SPEED * dt
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
