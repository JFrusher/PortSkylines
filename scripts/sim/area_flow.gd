class_name AreaFlow
extends RefCounted
## The port's work on roads and areas: ships berth along quay aprons, STS
## cranes stand on their rails, and boxes move by slots and machine jobs. It
## runs beside the tile flow in PortSim until M5 step 22 removes that. Its
## functions take the sim, whose state they work on, so nothing refers back.

## shortcut: ship lengths are in 25 m tiles until M5 step 22 moves them to metres.
const TILE_METRES := 25

## How many cells of quay a ship of `kind` needs.
static func ship_cells(sim: PortSim, kind: String) -> int:
	return ceili(sim.rules.ship_classes[kind].length * TILE_METRES / float(Grid.CELL))


## Aprons that can take ships: in a terminal with a gate, and with a road.
static func ready_aprons(sim: PortSim) -> Array[int]:
	var found: Array[int] = []
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type == "quay_apron" and sim.areas.terminal_error(area.terminal) == "" and sim.areas.idle_reason(id) == "":
			found.append(id)
	return found


## Moves an anchored ship to a free stretch of a ready apron; false if none yet.
static func berth(sim: PortSim, ship: PortSim.Ship) -> bool:
	var span := ship_cells(sim, ship.kind)
	for apron in ready_aprons(sim):
		for from in range(_length(sim, apron) - span + 1):
			if sim.ships.any(func(other: PortSim.Ship) -> bool: return other.apron == apron and other.from < from + span and from < other.from + ship_cells(sim, other.kind)):
				continue
			ship.apron = apron
			ship.from = from
			ship.state = PortSim.Ship.State.ARRIVING
			return true
	return false


## Whether some ready apron is long enough for `kind`, busy or not.
static func could_berth(sim: PortSim, kind: String) -> bool:
	return ready_aprons(sim).any(func(apron: int) -> bool: return _length(sim, apron) >= ship_cells(sim, kind))


## Ready aprons with a crane on them: berths lines may offer services for.
static func offer_berths(sim: PortSim) -> int:
	return ready_aprons(sim).filter(func(apron: int) -> bool: return sim.cranes.any(func(c: PortSim.Crane) -> bool: return c.apron == apron)).size()


## The cranes on `ship`'s apron within its length.
static func cranes_for(sim: PortSim, ship: PortSim.Ship) -> Array[PortSim.Crane]:
	var span := ship_cells(sim, ship.kind)
	var found: Array[PortSim.Crane] = []
	for crane in sim.cranes:
		if crane.apron == ship.apron and crane.along >= ship.from and crane.along < ship.from + span:
			found.append(crane)
	return found


## Why an STS crane can't stand `along` cells into apron `apron`, or "".
static func sts_error(sim: PortSim, apron: int, along: int) -> String:
	if apron not in sim.areas.list or sim.areas.list[apron].type != "quay_apron":
		return "STS cranes stand on a quay apron's rails"
	if along < 0 or along >= _length(sim, apron):
		return "STS cranes stand on a quay apron's rails"
	var room := ceili(sim.rules.sts_crane.width / float(Grid.CELL))
	var near := func(a: int, k: int) -> bool: return a == apron and absi(k - along) < room
	if sim.cranes.any(func(c: PortSim.Crane) -> bool: return near.call(c.apron, c.along)) or sim.crane_orders.any(func(o: Dictionary) -> bool: return o.has("apron") and near.call(o.apron, o.along)):
		return "Too close to another crane"
	return ""


static func _length(sim: PortSim, apron: int) -> int:
	var area: Dictionary = sim.areas.list[apron]
	return RoadNet.length(area.start, area.end) + 1
