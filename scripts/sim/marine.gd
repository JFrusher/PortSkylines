class_name Marine
extends RefCounted
## Ships on the water: the pocket off each quay where a ship lies alongside,
## routes along the ship lanes from the open sea to a berth, deep enough for
## a ship's draft, and sailing them. A lane reaches a berth when one of its
## ends lies in the berth's pocket; it reaches the open sea when one of its
## ends is on the site's edge.


## The water a ship lies in off quay apron `apron`: `water.pocket` rows out
## from its quay, all along it.
static func pocket(sim: PortSim, apron: int) -> Array[Vector2i]:
	var area: Dictionary = sim.areas.list[apron]
	var depth := sim.areas.depth_of(area)
	var cells: Array[Vector2i] = []
	for cell in RoadNet.line(area.start, area.end):
		for k: int in sim.rules.water.pocket:
			cells.append(cell + area.out * (depth + k))
	return cells


## How deep `apron`'s pocket is: its shallowest water plus what is dredged
## there, or 0 when land or another quay lies in it.
static func pocket_depth(sim: PortSim, apron: int) -> float:
	var shallowest := INF
	for cell in pocket(sim, apron):
		if not sim.areas.is_water(cell):
			return 0.0
		shallowest = minf(shallowest, sim.areas.coast.depth(cell))
	return shallowest + sim.pocket_dredged.get(apron, 0.0)


## Lane ends on the site's edge, where ships come in from the open sea.
static func sea_nodes(sim: PortSim) -> Array[int]:
	var size := sim.areas.coast.size
	var found: Array[int] = []
	for node: int in sim.ship_lanes.nodes:
		var cell: Vector2i = sim.ship_lanes.nodes[node]
		if cell.x <= 0 or cell.y <= 0 or cell.x >= size.x - 1 or cell.y >= size.y - 1:
			found.append(node)
	return found


## The lane ends in `apron`'s pocket.
static func berth_nodes(sim: PortSim, apron: int) -> Array[int]:
	var cells := pocket(sim, apron)
	var found: Array[int] = []
	for node: int in sim.ship_lanes.nodes:
		if sim.ship_lanes.nodes[node] in cells:
			found.append(node)
	return found


## The way in to `apron` for a ship of `kind`, from the open sea or (with
## `anchorage`) from that anchorage, as lane ends in cells, first to last;
## [] when no lane deep enough for its draft reaches the berth, or the
## pocket is too shallow. Kept until the lanes, the areas, the anchorages
## or the dredging change.
static func route(sim: PortSim, kind: String, apron: int, anchorage := 0, light := false) -> Array[Vector2]:
	var key := [kind, apron, anchorage, light]
	if key not in _routes(sim):
		var none: Array[Vector2] = []
		var deep_enough: bool = apron in sim.areas.list and pocket_depth(sim, apron) >= draft(sim, kind, light)
		sim._ship_routes[key] = _find(sim, draft(sim, kind, light), _starts(sim, anchorage), berth_nodes(sim, apron)) if deep_enough else none
	return sim._ship_routes[key]


## How deep a ship of `kind` sits: its draft, or its light draft when it
## calls light-loaded.
static func draft(sim: PortSim, kind: String, light := false) -> float:
	return sim.rules.ship_classes[kind].light_draft if light else sim.rules.ship_classes[kind].draft


## The way from the open sea to anchorage `id` for a ship of `kind`, as route.
static func route_to_anchorage(sim: PortSim, kind: String, id: int, light := false) -> Array[Vector2]:
	var key := [kind, "anchorage", id, light]
	if key not in _routes(sim):
		sim._ship_routes[key] = _find(sim, draft(sim, kind, light), sea_nodes(sim), anchorage_nodes(sim, id))
	return sim._ship_routes[key]


## The route cache, emptied once lanes, areas, anchorages or dredging change.
static func _routes(sim: PortSim) -> Dictionary:
	var stamp := [sim.ship_lanes.version, sim.areas.version, sim.dredge_version, sim.anchorages.keys()]
	if sim._ship_routes_for != stamp:
		sim._ship_routes.clear()
		sim._ship_routes_for = stamp
	return sim._ship_routes


static func _starts(sim: PortSim, anchorage: int) -> Array[int]:
	return anchorage_nodes(sim, anchorage) if anchorage else sea_nodes(sim)


## Lane ends from `starts` to `ends` through lanes at least `deep` metres, in cells.
static func _find(sim: PortSim, deep: float, starts: Array[int], ends: Array[int]) -> Array[Vector2]:
	var coast := sim.areas.coast
	var nodes := sim.ship_lanes.route(starts, ends, func(segment: int) -> bool: return sim.ship_lanes.depth(segment, coast) >= deep)
	var points: Array[Vector2] = []
	for node in nodes:
		points.append(Vector2(sim.ship_lanes.nodes[node]) + Vector2(0.5, 0.5))
	return points


## Whether a ship of `kind` (light-loaded or not) can reach `apron` from
## the open sea, or from `anchorage` when it waits there.
static func reaches(sim: PortSim, kind: String, apron: int, anchorage := 0, light := false) -> bool:
	return not route(sim, kind, apron, anchorage, light).is_empty()


## Where ships lie in the rectangle from `from` to `to`, in cells: one every
## water.anchorage.spacing cells each way.
static func spots_in(sim: PortSim, from: Vector2i, to: Vector2i) -> Array[Vector2]:
	var spacing: int = sim.rules.water.anchorage.spacing
	var low := from.min(to)
	var fits := ((to - from).abs() + Vector2i.ONE) / spacing
	var found: Array[Vector2] = []
	for i: int in fits.x:
		for j: int in fits.y:
			found.append(Vector2(low) + (Vector2(i, j) + Vector2(0.5, 0.5)) * spacing)
	return found


static func spots(sim: PortSim, id: int) -> Array[Vector2]:
	return spots_in(sim, sim.anchorages[id].from, sim.anchorages[id].to)


## The lane ends inside anchorage `id`.
static func anchorage_nodes(sim: PortSim, id: int) -> Array[int]:
	var rect := Rect2i(sim.anchorages[id].from, sim.anchorages[id].to - sim.anchorages[id].from + Vector2i.ONE)
	var found: Array[int] = []
	for node: int in sim.ship_lanes.nodes:
		if rect.has_point(sim.ship_lanes.nodes[node]):
			found.append(node)
	return found


## The first spot at anchorage `id` no ship holds, or -1.
static func free_spot(sim: PortSim, id: int) -> int:
	var held := sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.anchorage == id).map(func(s: PortSim.Ship) -> int: return s.spot)
	for i in spots(sim, id).size():
		if i not in held:
			return i
	return -1


## A ship that found no berth: one out at sea sails in to the first
## anchorage with a free spot it can reach, else, once it has waited
## water.max_wait_hours since it arrived, goes elsewhere and its line counts
## a missed call. One at an anchorage just waits.
static func wait(sim: PortSim, ship: PortSim.Ship) -> void:
	if ship.anchorage:
		return
	for id: int in sim.anchorages:
		var spot := free_spot(sim, id)
		var way := route_to_anchorage(sim, ship.kind, id, ship.light)
		if spot >= 0 and not way.is_empty():
			ship.anchorage = id
			ship.spot = spot
			ship.path = way.duplicate()
			ship.path.append(spots(sim, id)[spot])
			ship.sail = 0.0
			ship.prev_sail = 0.0
			ship.state = PortSim.Ship.State.ANCHORING
			sim._event("A %s waits at anchor for a berth" % ship.kind)
			return
	if sim.clock.calendar_minutes() - ship.arrived > sim.rules.water.max_wait_hours * 60.0:
		sim.ships.erase(ship)
		sim._event("%s's %s went elsewhere: no berth for it, and no room at anchor to wait" % [sim.contracts.name_of(ship.line), ship.kind])
		sim._event_if(sim.contracts.missed(ship.line))


## Where `ship` lies alongside its apron, in cells: the middle of its length
## along the quay, half its pocket out from the quay.
static func alongside(sim: PortSim, ship: PortSim.Ship) -> Vector2:
	var area: Dictionary = sim.areas.list[ship.apron]
	var along := Vector2((area.end - area.start).sign())
	var span := AreaFlow.ship_cells(sim, ship.kind)
	var quay := Vector2(area.start) + along * (ship.from + (span - 1) / 2.0) + Vector2(area.out) * sim.areas.depth_of(area)
	return quay + Vector2(area.out) * (sim.rules.water.pocket / 2.0) + Vector2(0.5, 0.5)


## Sets `ship`'s course to its berth: from its spot at anchor if it waits
## at one, in along the lanes, then alongside.
static func set_course(sim: PortSim, ship: PortSim.Ship) -> void:
	ship.path.clear()
	if ship.anchorage:
		ship.path.append(spots(sim, ship.anchorage)[ship.spot])
	ship.path.append_array(route(sim, ship.kind, ship.apron, ship.anchorage, ship.light))
	ship.path.append(alongside(sim, ship))
	ship.anchorage = 0
	ship.spot = -1
	release(ship)
	ship.sail = 0.0
	ship.prev_sail = 0.0


## Moves `ship` a tick along its course, in (`way` 1) or out (`way` -1),
## going in no further than the fraction `limit`; true once it is alongside
## or back out at sea.
static func sail(sim: PortSim, ship: PortSim.Ship, way: int, limit := 1.0) -> bool:
	var step: float = sim.rules.water.ship_speed / Grid.CELL * SimClock.CALENDAR_MINUTES_PER_TICK
	ship.sail = clampf(ship.sail + way * step / maxf(_length(ship.path), step), 0.0, limit)
	return ship.sail == (1.0 if way == 1 else 0.0)


static func _length(path: Array[Vector2]) -> float:
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


## How far in `ship` may sail now: all the way, or only to the end of the
## lanes while the tugs it waits for are still on their way.
static func berthing_limit(sim: PortSim, ship: PortSim.Ship) -> float:
	if ship.tugs == 0 or sim.clock.calendar_minutes() >= ship.tugs_at:
		return 1.0
	return _length(ship.path.slice(0, -1)) / maxf(_length(ship.path), 0.0001)


## Whether `ship`, leaving, has sailed out of its berth's pocket onto the
## lanes, so the next ship may have the berth.
static func clear_of_berth(sim: PortSim, ship: PortSim.Ship) -> bool:
	return ship.state == PortSim.Ship.State.LEAVING and ship.cleared and ship.path.size() > 1 and ship.sail < _length(ship.path.slice(0, -1)) / maxf(_length(ship.path), 0.0001)


## Pilots on the port's stations not aboard a ship.
static func free_pilots(sim: PortSim) -> int:
	var total := 0
	for station: Dictionary in sim.pilot_stations.values():
		total += station.pilots
	return total - sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.pilot).size()


## Depot `id`'s tugs not out with a ship.
static func free_tugs(sim: PortSim, id: int) -> int:
	var out := 0
	for ship: PortSim.Ship in sim.ships:
		if ship.tug_depot == id:
			out += ship.tugs
	return sim.tug_depots[id].tugs - out


## Whether `ship` may move along its course this tick, in (`way` 1) or out
## (-1): once it has clearance (asked for until it gets it) and its pilot
## has boarded and, going out, its tugs have come.
static func under_way(sim: PortSim, ship: PortSim.Ship, way: int) -> bool:
	if not ship.cleared:
		var why := clear(sim, ship, way)
		if why:
			sim._event("A %s %s waits: %s" % [ship.kind, "coming in" if way == 1 else "leaving", why])
			return false
	return sim.clock.calendar_minutes() >= ship.hold_until


## Gives `ship` clearance to sail its course in (`way` 1) or out (-1), or
## says why not: a pilot from the station nearest where it sets off, if its
## class takes one, boarding when the pilot boat gets there; tugs from the
## depot nearest its berth with enough free, if its class needs them,
## meeting it at the berth (not when it sails in to anchor); and a booking
## of every narrow lane on its way
## for the minutes it is in it, clear of every other ship's booking by
## water.slot_margin_minutes. Nothing is taken unless all of it is free.
static func clear(sim: PortSim, ship: PortSim.Ship, way: int) -> String:
	var spec: Dictionary = sim.rules.ship_classes[ship.kind]
	var now := sim.clock.calendar_minutes()
	var start := ship.path[0] if way == 1 else ship.path[-1]
	var berth := ship.path[-1]
	var sets_off := now
	if spec.pilot:
		if sim.pilot_stations.is_empty():
			return "a %s needs a pilot: build a pilot station (Water)" % ship.kind
		if free_pilots(sim) == 0:
			return "no pilot free"
		sets_off += _nearest(sim.pilot_stations, start) * Grid.CELL / sim.rules.water.pilots.boat_speed
	var depot := 0
	var tugs_at := 0.0
	if spec.tugs > 0 and ship.state != PortSim.Ship.State.ANCHORING:
		var near := INF
		for id: int in sim.tug_depots:
			var far: float = Vector2(sim.tug_depots[id].cell).distance_to(berth)
			if free_tugs(sim, id) >= spec.tugs and far < near:
				near = far
				depot = id
		if depot == 0:
			return "it needs %d tugs free at one depot%s" % [spec.tugs, "" if not sim.tug_depots.is_empty() else ": build a tug depot (Water)"]
		tugs_at = now + near * Grid.CELL / sim.rules.water.tugs.speed
		if way == -1:
			sets_off = maxf(sets_off, tugs_at)
	sim.passages = sim.passages.filter(func(p: Dictionary) -> bool: return p.to >= now)
	var windows := _windows(sim, ship, way, sets_off)
	var margin: float = sim.rules.water.slot_margin_minutes
	for w in windows:
		for p: Dictionary in sim.passages:
			if p.segment == w.segment and p.ship != ship.id and w.from < p.to + margin and p.from < w.to + margin:
				return "no slot free through a narrow lane"
	if spec.pilot:
		sim.ledger.post("pilotage", sim.rules.water.pilots.fee)
	ship.pilot = spec.pilot
	ship.tugs = spec.tugs if depot else 0
	ship.tug_depot = depot
	ship.tugs_at = tugs_at
	ship.hold_until = sets_off
	for w in windows:
		w.ship = ship.id
		sim.passages.append(w)
	ship.cleared = true
	return ""


## Cells from `point` to the nearest of `bases` (id -> {"cell"}).
static func _nearest(bases: Dictionary, point: Vector2) -> float:
	var near := INF
	for base: Dictionary in bases.values():
		near = minf(near, Vector2(base.cell).distance_to(point))
	return near


## The narrow lanes `ship` passes on its course (in or out), each with the
## calendar minutes it is in it when it sets off at `sets_off`.
static func _windows(sim: PortSim, ship: PortSim.Ship, way: int, sets_off: float) -> Array[Dictionary]:
	var points := ship.path.duplicate()
	if way == -1:
		points.reverse()
	var per_cell: float = Grid.CELL / sim.rules.water.ship_speed
	var found: Array[Dictionary] = []
	var at := 0.0
	for i in range(1, points.size()):
		var leg: float = points[i - 1].distance_to(points[i])
		var segment := sim.ship_lanes.between(_node_at(sim, points[i - 1]), _node_at(sim, points[i]))
		if segment and sim.ship_lanes.segments[segment].type == "narrow":
			found.append({"segment": segment, "from": sets_off + at * per_cell, "to": sets_off + (at + leg) * per_cell})
		at += leg
	return found


## The lane end at `point` (a cell's middle), or 0.
static func _node_at(sim: PortSim, point: Vector2) -> int:
	var cell := Vector2i(point.floor())
	for node: int in sim.ship_lanes.nodes:
		if sim.ship_lanes.nodes[node] == cell:
			return node
	return 0


## Lets `ship`'s pilot and tugs go: it is alongside, or has a new course to clear.
static func release(ship: PortSim.Ship) -> void:
	ship.cleared = false
	ship.pilot = false
	ship.tugs = 0
	ship.tug_depot = 0


## The point a fraction `t` of the way along `path`, in cells.
static func point_along(path: Array[Vector2], t: float) -> Vector2:
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var left := t * length
	for i in range(1, path.size()):
		var leg := path[i - 1].distance_to(path[i])
		if left <= leg or i == path.size() - 1:
			return path[i - 1].lerp(path[i], clampf(left / maxf(leg, 0.0001), 0.0, 1.0))
		left -= leg
	return path[0]
