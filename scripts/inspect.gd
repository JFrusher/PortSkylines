class_name Inspect
extends RefCounted
## What the inspect tool shows: the thing under a clicked cell and its state,
## read from the sim. Reads PortSim, never changes it.

const STATES := {
	"drive": "Driving", "yard": "Queueing for a yard machine", "handling": "Being handled in the yard",
	"gate": "At the gate", "under_crane": "Under a crane", "no_route": "Waiting for a road",
	"arriving": "Driving to its area", "queued": "Waiting for a handover slot", "to_slot": "Driving to its handover slot",
	"handled": "Being handled in the yard", "at_gate": "At the gate", "returning": "Driving out of the yard",
	"leaving": "Leaving the port", "to_crane": "Bringing an export to its crane",
}
const SHIP_STATES := ["Arriving", "Working", "Leaving", "At anchor"]


## The vehicle, ship or crane at `cell`, else an area at `grid_cell` on the
## 4 m grid as {"area": id}, else the cell itself.
static func pick(sim: PortSim, cell: Vector2i, grid_cell: Vector2i) -> Variant:
	for vehicle in sim.vehicles:
		if Vector2i(vehicle.position(1.0).round()) == cell:
			return vehicle
	for vehicle in sim.area_vehicles:
		if Vector2i(vehicle.position(1.0).round()) == grid_cell:
			return vehicle
	for ship in sim.ships:
		if ship.apron and grid_cell in _ship_water(sim, ship):
			return ship
	for crane in sim.cranes:
		if crane.apron and grid_cell in _crane_cells(sim, crane):
			return crane
	for ship in sim.ships:
		for quay in ship.cells:
			if quay + ship.side == cell:
				return ship
	for crane in sim.cranes:
		if crane.cell == cell:
			return crane
	var area := sim.areas.area_at(grid_cell)
	if area:
		return {"area": area}
	return cell


## A title then lines of state for `thing` from `pick`, or [] once it is gone.
static func describe(sim: PortSim, thing: Variant) -> Array[String]:
	if thing is Vehicle:
		return _vehicle(sim, thing) if thing in sim.vehicles or thing in sim.area_vehicles else []
	if thing is PortSim.Ship:
		return _ship(sim, thing) if thing in sim.ships else []
	if thing is PortSim.Crane:
		return _crane(sim, thing) if thing in sim.cranes else []
	if thing is Dictionary:
		return _area(sim, thing.area) if thing.area in sim.areas.list else []
	return _cell(sim, thing)


## The water an apron ship lies in: its length of the quay edge, out to its beam.
static func _ship_water(sim: PortSim, ship: PortSim.Ship) -> Array[Vector2i]:
	var area: Dictionary = sim.areas.list[ship.apron]
	var along: Vector2i = (area.end - area.start).sign()
	var depth: int = sim.rules.area_types.quay_apron.depth
	var found: Array[Vector2i] = []
	for k in range(ship.from, ship.from + AreaFlow.ship_cells(sim, ship.kind)):
		for beam in range(depth, depth + 8):
			found.append(area.start + along * k + area.out * beam)
	return found


## The cells an apron crane stands across, between its rails.
static func _crane_cells(sim: PortSim, crane: PortSim.Crane) -> Array[Vector2i]:
	var area: Dictionary = sim.areas.list[crane.apron]
	var along: Vector2i = (area.end - area.start).sign()
	var found: Array[Vector2i] = []
	for row in range(1, sim.rules.area_types.quay_apron.depth - 1):
		found.append(area.start + along * crane.along + area.out * row)
	return found


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


static func _area(sim: PortSim, id: int) -> Array[String]:
	var area: Dictionary = sim.areas.list[id]
	var lines: Array[String] = [sim.rules.area_types[area.type].name, sim.areas.terminals[area.terminal].name]
	var unready := sim.areas.terminal_error(area.terminal)
	if unready:
		lines.append(unready)
	var settings: Dictionary = area.settings
	if settings.has("role"):
		lines.append("%s block, %s" % [settings.role.capitalize(), settings.gear.replace("_", " ")])
	if settings.has("lines") and not settings.lines.is_empty():
		lines.append("Favours " + ", ".join(settings.lines.map(func(line: String) -> String: return sim.contracts.name_of(line))))
	var idle := sim.areas.idle_reason(id)
	lines.append(idle if idle else "Working")
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
