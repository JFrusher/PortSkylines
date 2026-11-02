class_name Inspect
extends RefCounted
## What the inspect tool shows: the thing under a clicked cell and its state,
## read from the sim. Reads PortSim, never changes it.

const STATES := {
	"arriving": "Driving to its area", "queued": "Waiting for a handover slot", "to_slot": "Driving to its handover slot",
	"handling": "Waiting for a yard machine", "handled": "Being handled in the yard", "under_crane": "Under a crane", "at_gate": "At the gate", "returning": "Driving out of the yard",
	"leaving": "Leaving the port", "to_crane": "Bringing an export to its crane",
}
const SHIP_STATES := ["Arriving", "Working", "Leaving", "At anchor"]
const TRAIN_STATES := {"arriving": "Coming in to its siding", "working": "At its siding, being worked", "leaving": "Leaving the port"}


## The vehicle, train, ship or crane at grid cell `cell`, else a junction
## as {"junction"}, an area as {"area": id} or a ship lane as {"lane":
## segment} there, else null.
static func pick(sim: PortSim, cell: Vector2i) -> Variant:
	for vehicle in sim.vehicles:
		if Vector2i(Drive.where(sim, vehicle).round()) == cell:
			return vehicle
	for train: Train in sim.trains:
		var head := int(train.t)
		if cell in train.path.slice(maxi(head - train.length(), 0), head + 1):
			return train
	for ship in sim.ships:
		if ship.apron and cell in _ship_water(sim, ship):
			return ship
	for crane in sim.cranes:
		if cell in _crane_cells(sim, crane):
			return crane
	var junction := Drive.junction_at(sim, cell)
	if junction != Grid.NONE:
		return {"junction": junction}
	var area := sim.areas.area_at(cell)
	if area:
		return {"area": area}
	if sim.areas.breakwater_at(cell):
		return {"breakwater": sim.areas.breakwater_at(cell)}
	if sim.marine_base_at(cell):
		return {"base": sim.marine_base_at(cell)}
	if sim.anchorage_at(cell):
		return {"anchorage": sim.anchorage_at(cell)}
	var lane := lane_at(sim, cell)
	return {"lane": lane} if lane else null


## The ship lane whose water covers `cell`, or 0.
static func lane_at(sim: PortSim, cell: Vector2i) -> int:
	for segment: int in sim.ship_lanes.segments:
		var lane: Dictionary = sim.ship_lanes.segments[segment]
		if cell in sim.ship_lanes.footprint(sim.ship_lanes.nodes[lane.a], sim.ship_lanes.nodes[lane.b], lane.type):
			return segment
	return 0


## A title then lines of state for `thing` from `pick`, or [] once it is gone.
static func describe(sim: PortSim, thing: Variant) -> Array[String]:
	# A typed empty array: `x if found else []` gives an untyped [], which a
	# caller's Array[String] refuses once the thing inspected has gone.
	var nothing: Array[String] = []
	if thing is Vehicle:
		return _vehicle(sim, thing) if thing in sim.vehicles else nothing
	if thing is Train:
		return _train(sim, thing) if thing in sim.trains else nothing
	if thing is PortSim.Ship:
		return _ship(sim, thing) if thing in sim.ships else nothing
	if thing is PortSim.Crane:
		return _crane(sim, thing) if thing in sim.cranes else nothing
	if thing is Dictionary and thing.has("breakwater"):
		if thing.breakwater not in sim.areas.breakwaters:
			return nothing
		var wall: Dictionary = sim.areas.breakwaters[thing.breakwater]
		return ["Breakwater", "%d m long, 8 m thick" % Grid.metres(RoadNet.length(wall.from, wall.to) + 1), "No ship lane crosses it"] as Array[String]
	if thing is Dictionary and thing.has("base"):
		if thing.base in sim.pilot_stations:
			return ["Pilot station", "%d pilots, %d out with ships" % [sim.pilot_stations[thing.base].pilots, sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.pilot).size()], "Panamaxes and bigger take a pilot in and out"] as Array[String]
		if thing.base in sim.tug_depots:
			var depot: Dictionary = sim.tug_depots[thing.base]
			return ["Tug depot", "%d tugs, %d out with ships" % [depot.tugs, depot.tugs - Marine.free_tugs(sim, thing.base)], "Panamaxes and bigger need tugs to berth and unberth"] as Array[String]
		return nothing
	if thing is Dictionary and thing.has("anchorage"):
		return _anchorage(sim, thing.anchorage) if thing.anchorage in sim.anchorages else nothing
	if thing is Dictionary and thing.has("lane"):
		return _lane(sim, thing.lane) if thing.lane in sim.ship_lanes.segments else nothing
	if thing is Dictionary and thing.has("junction"):
		return _junction(sim, thing.junction) if not Drive.arms(sim, thing.junction).is_empty() else nothing
	if thing is Dictionary:
		return _area(sim, thing.area) if thing.area in sim.areas.list else nothing
	return nothing


## The name of the arm leaving a junction towards `arm`: "north", "south-east"...
static func arm_name(arm: Vector2i) -> String:
	var parts: Array[String] = []
	if arm.y != 0:
		parts.append("north" if arm.y < 0 else "south")
	if arm.x != 0:
		parts.append("west" if arm.x < 0 else "east")
	return "-".join(parts)


static func _junction(sim: PortSim, point: Vector2i) -> Array[String]:
	var junctions := Drive.junctions(sim)
	var lines: Array[String] = ["Junction of %d roads" % Drive.arms(sim, point).size()]
	if point in junctions.signals:
		var at: Dictionary = junctions.signals[point]
		var phases := junctions.phases(sim.lanes, point)
		for i in phases.size():
			var arms: Array = phases[i].map(func(arm: Vector2i) -> String: return arm_name(arm))
			var now := ", green now (%d s left)" % ceili(at.left) if i == at.phase and at.left > 0.0 else ""
			lines.append("Phase %d, %s: %d s green%s" % [i + 1, " and ".join(arms), roundi(at.green[i]), now])
	else:
		lines.append("No signals")
	var signs: Dictionary = junctions.signs.get(point, {})
	for arm: Vector2i in Drive.arms(sim, point):
		if arm in signs:
			lines.append("From the %s: %s" % [arm_name(arm), "give way" if signs[arm] == "give_way" else "stop"])
	return lines


static func _train(sim: PortSim, train: Train) -> Array[String]:
	var loaded := train.wagons.filter(func(box: int) -> bool: return box != 0)
	var exports := loaded.filter(func(box: int) -> bool: return sim.boxes[box].kind == "export").size()
	return [
		"Train %d" % train.id,
		TRAIN_STATES[train.state],
		"For %s" % sim.rules.area_types[sim.areas.list[train.block].type].name.to_lower() if train.block in sim.areas.list else "",
		"%d of %d wagons loaded: %d imports out, %d exports in" % [loaded.size(), train.wagons.size(), loaded.size() - exports, exports],
	] as Array[String]


## The water an apron ship lies in: its length of the quay edge, out to its beam.
static func _ship_water(sim: PortSim, ship: PortSim.Ship) -> Array[Vector2i]:
	var area: Dictionary = sim.areas.list[ship.apron]
	var along: Vector2i = (area.end - area.start).sign()
	var depth := sim.areas.depth_of(area)
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
	for row in range(1, sim.areas.depth_of(area) - 1):
		found.append(area.start + along * crane.along + area.out * row)
	return found


static func _vehicle(sim: PortSim, vehicle: Vehicle) -> Array[String]:
	var doing: String = "Waiting for a road" if vehicle.state.begins_with("no_route:") else STATES.get(vehicle.state, vehicle.state)
	var lines: Array[String] = ["%s %d" % [vehicle.kind.capitalize(), vehicle.id], doing]
	if vehicle.loaded:
		var box: Dictionary = sim.boxes[vehicle.box]
		lines.append("Carrying a %s %s box%s" % ["40 ft" if box.teu == 2 else "20 ft", box.kind, ", reefer" if box.reefer else ", dangerous goods" if box.dg else ""])
		if box.rush:
			lines.append("Rush: fined if its ship sails late")
		var place: Dictionary = sim.rules.hinterland.places[box.place]
		lines.append("%s %s, %.0f km by road%s" % ["To" if box.kind == "import" else "From", place.name, place.road_km, ", %.0f by rail" % place.rail_km if place.rail_km > 0.0 else ""])
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


static func _lane(sim: PortSim, segment: int) -> Array[String]:
	var lane: Dictionary = sim.ship_lanes.segments[segment]
	var spec: Dictionary = sim.rules.water.lanes[lane.type]
	var lines: Array[String] = [spec.name]
	lines.append("%.1f m deep at its shallowest%s" % [sim.ship_lanes.depth(segment, sim.areas.coast), ", %.0f m of it dredged" % lane.dredged if lane.dredged > 0.0 else ""])
	lines.append("%d m long, %d m wide, %s" % [Grid.metres(RoadNet.length(sim.ship_lanes.nodes[lane.a], sim.ship_lanes.nodes[lane.b])), Grid.metres(spec.half_width * 2 + 1), "ships pass both ways" if spec.two_way else "one ship at a time"] + ("; barges only" if spec.barges_only else ""))
	var drafts: Array = sim.rules.ship_classes.keys().filter(func(kind: String) -> bool: return sim.ship_lanes.depth(segment, sim.areas.coast) >= sim.rules.ship_classes[kind].draft)
	lines.append("Deep enough for %s" % (", ".join(drafts) if not drafts.is_empty() else "no ship yet"))
	return lines


static func _anchorage(sim: PortSim, id: int) -> Array[String]:
	var waiting := sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.anchorage == id)
	var lines: Array[String] = ["Anchorage", "%d of %d spots taken" % [waiting.size(), Marine.spots(sim, id).size()]]
	if Marine.anchorage_nodes(sim, id).is_empty():
		lines.append("No ship lane ends in it yet, so no ship can reach it")
	for ship: PortSim.Ship in waiting:
		lines.append("%s %s, waiting %.1f h" % [sim.contracts.name_of(ship.line), ship.kind, (sim.clock.calendar_minutes() - ship.arrived) / 60.0])
	return lines


static func _crane(sim: PortSim, crane: PortSim.Crane) -> Array[String]:
	var spec: Dictionary = sim.rules.sts_cranes[crane.kind]
	var lines: Array[String] = [spec.name, "Idle" if crane.tractor == 0 else "Working with tractor %d" % crane.tractor]
	lines.append("%d moves an hour, %d rows outreach" % [spec.rate, spec.outreach])
	return lines


## A yard block's TEU against its room, and its machines.
static func _yard_fill(sim: PortSim, id: int) -> String:
	var fill := sim.block_fill(id)
	var machines := sim.machines.list.values().filter(func(m: Dictionary) -> bool: return m.area == id).size()
	return "%d of %d TEU (%d%%), %d machine%s" % [fill.x, fill.y, roundi(100.0 * fill.x / maxi(fill.y, 1)), machines, "" if machines == 1 else "s"]


## A quay apron's size, the ships it fits, its cranes and the ship alongside.
static func _apron(sim: PortSim, id: int) -> Array[String]:
	var area: Dictionary = sim.areas.list[id]
	var length := RoadNet.length(area.start, area.end) + 1
	var fits: Array = sim.rules.ship_classes.keys().filter(func(kind: String) -> bool: return AreaFlow.ship_cells(sim, kind) <= length)
	var lines: Array[String] = ["%d m long, %d m deep: berths %s" % [Grid.metres(length), Grid.metres(sim.areas.depth_of(area)), ", ".join(fits) if not fits.is_empty() else "no ship yet"]]
	var cranes := sim.cranes.filter(func(c: PortSim.Crane) -> bool: return c.apron == id).size()
	lines.append("%d STS crane%s" % [cranes, "" if cranes == 1 else "s"])
	var pocket := Marine.pocket_depth(sim, id)
	lines.append("Its water: %s" % ("%.1f m deep%s" % [pocket, ", %.0f m dredged" % sim.pocket_dredged[id] if sim.pocket_dredged.get(id, 0.0) > 0.0 else ""] if pocket > 0.0 else "blocked by land or a quay"))
	var reach: Array = sim.rules.ship_classes.keys().filter(func(kind: String) -> bool: return Marine.reaches(sim, kind, id))
	lines.append("Ships reach it from the sea: %s" % (", ".join(reach) if not reach.is_empty() else "none yet; draw a ship lane from the open sea into its water (Water)"))
	for ship: PortSim.Ship in sim.ships:
		if ship.apron == id:
			lines.append("Alongside: %s %s, %s" % [sim.contracts.name_of(ship.line), ship.kind, SHIP_STATES[ship.state].to_lower()])
	return lines


static func _area(sim: PortSim, id: int) -> Array[String]:
	var area: Dictionary = sim.areas.list[id]
	var lines: Array[String] = [sim.rules.area_types[area.type].name, "In no terminal" if area.terminal == 0 else sim.areas.terminal_name(area.terminal)]
	var unready := sim.areas.terminal_error(area.terminal) if area.terminal else ""
	if unready:
		lines.append(unready)
	var settings: Dictionary = area.settings
	if settings.has("role"):
		lines.append("%s block, worked by %s" % [settings.role.capitalize(), sim.rules.yard_gear[settings.gear].name])
		if settings.gear == "rmg":
			var wagons := AreaFlow.siding(sim, id).size() / AreaLayout.BAY
			lines.append("Siding for %d wagons" % wagons if wagons else "No siding: draw track along its back edge")
		lines.append(_yard_fill(sim, id))
	if area.type == "quay_apron":
		lines.append_array(_apron(sim, id))
	if settings.has("level"):
		lines.append("%s, %d lanes: %.1f min a lorry, %d lorries an hour" % [sim.rules.gate_levels[settings.level].name, sim.areas.layout(id).lanes.size(), AreaFlow.gate_minutes(sim, id), roundi(AreaFlow.gate_throughput(sim, id))])
		var waiting := sim.handovers.waiting(id)
		lines.append("%d lorries queuing" % (waiting.buffer.size() + waiting.road.size()))
		lines.append("Bookings: %d an hour" % settings.slots_per_hour if settings.slots_per_hour > 0 else "No bookings: lorries come in as they arrive")
	if settings.has("lines") and not settings.lines.is_empty():
		lines.append("Favours " + ", ".join(settings.lines.map(func(line: String) -> String: return sim.contracts.name_of(line))))
	var idle := sim.areas.idle_reason(id)
	lines.append(idle if idle else "Working")
	return lines
