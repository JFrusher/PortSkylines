class_name Inspect
extends RefCounted
## What the inspect tool shows: the thing under a clicked cell and its state,
## read from the sim. Reads PortSim, never changes it.

const STATES := {
	"drive": "Driving", "yard": "Queueing for a yard machine", "handling": "Being handled in the yard",
	"gate": "At the gate", "under_crane": "Under a crane", "no_route": "Waiting for a road",
}
const SHIP_STATES := ["Arriving", "Working", "Leaving", "At anchor"]


## The vehicle, ship or crane at `cell`, else the cell itself.
static func pick(sim: PortSim, cell: Vector2i) -> Variant:
	for vehicle in sim.vehicles:
		if Vector2i(vehicle.position(1.0).round()) == cell:
			return vehicle
	for ship in sim.ships:
		for quay in ship.cells:
			if quay + ship.side == cell:
				return ship
	for crane in sim.cranes:
		if crane.cell == cell:
			return crane
	return cell


## A title then lines of state for `thing` from `pick`, or [] once it is gone.
static func describe(sim: PortSim, thing: Variant) -> Array[String]:
	if thing is Vehicle:
		return _vehicle(sim, thing) if thing in sim.vehicles else []
	if thing is PortSim.Ship:
		return _ship(sim, thing) if thing in sim.ships else []
	if thing is PortSim.Crane:
		return _crane(sim, thing) if thing in sim.cranes else []
	return _cell(sim, thing)


static func _vehicle(sim: PortSim, vehicle: Vehicle) -> Array[String]:
	var lines: Array[String] = ["%s %d" % [vehicle.kind.capitalize(), vehicle.id], STATES.get(vehicle.state, vehicle.state)]
	if vehicle.loaded:
		var box: Dictionary = sim.boxes[vehicle.box]
		lines.append("Carrying a %s %s box%s" % ["40 ft" if box.teu == 2 else "20 ft", box.kind, ", reefer" if box.reefer else ""])
	else:
		lines.append("Empty")
	return lines


static func _ship(sim: PortSim, ship: PortSim.Ship) -> Array[String]:
	var lines: Array[String] = ["%s %s" % [sim.contracts.name_of(ship.line), ship.kind], SHIP_STATES[ship.state]]
	lines.append("%d imports aboard, room for %d exports" % [ship.boxes, ship.exports])
	lines.append("%d moves so far" % ship.moves)
	var late := sim.clock.calendar_minutes() - ship.due
	lines.append("Window closes in %.1f h" % (-late / 60.0) if late < 0.0 else "%.1f h past its window" % (late / 60.0))
	return lines


static func _crane(sim: PortSim, crane: PortSim.Crane) -> Array[String]:
	var lines: Array[String] = ["STS crane", "Idle" if crane.tractor == 0 else "Working with tractor %d" % crane.tractor]
	lines.append("%d moves an hour, %d rows outreach" % [sim.rules.sts_crane.rate, sim.rules.sts_crane.outreach])
	return lines


static func _cell(sim: PortSim, cell: Vector2i) -> Array[String]:
	if not sim.map.in_bounds(cell):
		return []
	var kind := sim.map.tile(cell)
	var lines: Array[String] = [PortMap.Tile.keys()[kind].capitalize()]
	if kind == PortMap.Tile.YARD:
		var yard := sim.yard
		lines.append("%s block, %s" % [yard.role_of(cell).capitalize(), yard.gear_of(cell).replace("_", " ")])
		lines.append("%d of %d boxes stacked here" % [yard.count(cell), yard.capacity(cell)])
		var anchor := yard.anchor(cell)
		lines.append("%d of %d machines busy" % [yard.busy.get(anchor, 0), yard.machines(anchor)])
	if not sim.owns(cell) and kind != PortMap.Tile.WATER:
		lines.append("Land the port does not own")
	return lines
