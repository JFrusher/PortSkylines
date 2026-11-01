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
static func route(sim: PortSim, kind: String, apron: int, anchorage := 0) -> Array[Vector2]:
	var key := [kind, apron, anchorage]
	if key not in _routes(sim):
		var none: Array[Vector2] = []
		var deep_enough: bool = apron in sim.areas.list and pocket_depth(sim, apron) >= sim.rules.ship_classes[kind].draft
		sim._ship_routes[key] = _find(sim, kind, _starts(sim, anchorage), berth_nodes(sim, apron)) if deep_enough else none
	return sim._ship_routes[key]


## The way from the open sea to anchorage `id` for a ship of `kind`, as route.
static func route_to_anchorage(sim: PortSim, kind: String, id: int) -> Array[Vector2]:
	var key := [kind, "anchorage", id]
	if key not in _routes(sim):
		sim._ship_routes[key] = _find(sim, kind, sea_nodes(sim), anchorage_nodes(sim, id))
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


## Lane ends from `starts` to `ends` through lanes deep enough for `kind`, in cells.
static func _find(sim: PortSim, kind: String, starts: Array[int], ends: Array[int]) -> Array[Vector2]:
	var draft: float = sim.rules.ship_classes[kind].draft
	var coast := sim.areas.coast
	var nodes := sim.ship_lanes.route(starts, ends, func(segment: int) -> bool: return sim.ship_lanes.depth(segment, coast) >= draft)
	var points: Array[Vector2] = []
	for node in nodes:
		points.append(Vector2(sim.ship_lanes.nodes[node]) + Vector2(0.5, 0.5))
	return points


## Whether a ship of `kind` can reach `apron` from the open sea, or from
## `anchorage` when it waits there.
static func reaches(sim: PortSim, kind: String, apron: int, anchorage := 0) -> bool:
	return not route(sim, kind, apron, anchorage).is_empty()


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
		var way := route_to_anchorage(sim, ship.kind, id)
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
	ship.path.append_array(route(sim, ship.kind, ship.apron, ship.anchorage))
	ship.path.append(alongside(sim, ship))
	ship.anchorage = 0
	ship.spot = -1
	ship.sail = 0.0
	ship.prev_sail = 0.0


## Moves `ship` a tick along its course, in (`way` 1) or out (`way` -1);
## true once it is alongside or back out at sea.
static func sail(sim: PortSim, ship: PortSim.Ship, way: int) -> bool:
	var length := 0.0
	for i in range(1, ship.path.size()):
		length += ship.path[i - 1].distance_to(ship.path[i])
	var step: float = sim.rules.water.ship_speed / Grid.CELL * SimClock.CALENDAR_MINUTES_PER_TICK
	ship.sail = clampf(ship.sail + way * step / maxf(length, step), 0.0, 1.0)
	return ship.sail == (1.0 if way == 1 else 0.0)


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
