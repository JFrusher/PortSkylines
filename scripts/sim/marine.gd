class_name Marine
extends RefCounted
## Ships on the water: the pocket off each quay where a ship lies alongside,
## routes along the ship lanes from the open sea to a berth, deep enough for
## a ship's draft, and sailing them. A lane reaches a berth when one of its
## ends lies in the berth's pocket; it reaches the open sea when one of its
## ends is on the site's edge.

## How far apart, in cells, a ship's course has points along a lane.
const SAIL_STEP := 2.0
## Cells of water left between a turning ship's hull and its quay.
const TURN_MARGIN := 2.0
## Degrees off its quay a ship's last lane may run and the ship still come
## straight in sideways, with no need to turn off the berth.
const PARALLEL_DEGREES := 45.0


## The water a ship lies in off quay apron `apron`: `water.pocket` rows out
## from its quay, all along it.
static func pocket(sim: PortSim, apron: int) -> Array[Vector2i]:
	if sim._pockets_for != sim.areas.version:
		sim._pockets.clear()
		sim._pockets_for = sim.areas.version
	if apron not in sim._pockets:
		var depth := sim.areas.depth_of(sim.areas.list[apron])
		var cells: Array[Vector2i] = []
		for k: int in sim.areas.list[apron].columns:
			for j: int in sim.rules.water.pocket:
				cells.append(Vector2i(sim.areas.point(apron, k, depth + j).floor()))
		sim._pockets[apron] = cells
	return sim._pockets[apron]


## How many cells `apron`'s pocket holds, as pocket() lists them: a row of
## water.pocket cells out from each of its columns.
static func pocket_size(sim: PortSim, apron: int) -> int:
	return sim.areas.list[apron].columns * sim.rules.water.pocket


## How deep `apron`'s pocket is: its shallowest water plus what is dredged
## there, or 0 when land or another quay lies in it.
static func pocket_depth(sim: PortSim, apron: int) -> float:
	var shallowest := INF
	for cell in pocket(sim, apron):
		if not sim.areas.is_water(cell):
			return 0.0
		shallowest = minf(shallowest, sim.areas.coast.depth(cell))
	return shallowest + sim.pocket_dredged.get(apron, 0.0)


## Lane ends on the site's edge where ships come in: in a river's inland
## end (`inland`, for barges), or in the open sea.
static func edge_nodes(sim: PortSim, inland: bool) -> Array[int]:
	var coast := sim.areas.coast
	var found: Array[int] = []
	for node: int in sim.ship_lanes.nodes:
		var cell: Vector2i = sim.ship_lanes.nodes[node]
		var edge := cell.x <= 0 or cell.y <= 0 or cell.x >= coast.size.x - 1 or cell.y >= coast.size.y - 1
		if edge and coast.is_inland_end(cell) == inland:
			found.append(node)
	return found


## The lane ends a ship of `kind` comes in and goes out by.
static func ways_in(sim: PortSim, kind: String) -> Array[int]:
	return edge_nodes(sim, sim.rules.ship_classes[kind].inland)


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
## [] when no lane deep enough for its draft reaches the berth, the pocket
## is too shallow, the berth isn't for its kind (barge or not), or the ship
## must turn off the berth and nowhere along it has the water to. Kept until the lanes, the areas, the anchorages
## or the dredging change.
static func route(sim: PortSim, kind: String, apron: int, anchorage := 0, light := false) -> Array[Vector2]:
	var key := [kind, apron, anchorage, light]
	if key not in _routes(sim):
		var none: Array[Vector2] = []
		# A barge berth takes only barges, and a barge only a barge berth.
		var deep := draft(sim, kind, light) - _tide_allowance(sim)
		var fits: bool = apron in sim.areas.list and sim.areas.list[apron].settings.barge == sim.rules.ship_classes[kind].inland and pocket_depth(sim, apron) >= deep
		var lanes := _find(sim, kind, deep, _starts(sim, kind, anchorage), berth_nodes(sim, apron)) if fits else none
		sim._ship_routes[key] = lanes if lanes.is_empty() or room_at(sim, kind, apron, lanes) else none
	return sim._ship_routes[key]


## How deep a ship of `kind` sits: its draft, or its light draft when it
## calls light-loaded.
static func draft(sim: PortSim, kind: String, light := false) -> float:
	return sim.rules.ship_classes[kind].light_draft if light else sim.rules.ship_classes[kind].draft


## The way from the open sea to anchorage `id` for a ship of `kind`, as route.
static func route_to_anchorage(sim: PortSim, kind: String, id: int, light := false) -> Array[Vector2]:
	var key := [kind, "anchorage", id, light]
	if key not in _routes(sim):
		sim._ship_routes[key] = _find(sim, kind, draft(sim, kind, light) - _tide_allowance(sim), ways_in(sim, kind), anchorage_nodes(sim, id))
	return sim._ship_routes[key]


## The route cache, emptied once lanes, areas, anchorages, dredging or the
## tides' switch change.
static func _routes(sim: PortSim) -> Dictionary:
	var stamp := [sim.ship_lanes.version, sim.areas.version, sim.dredge_version, sim.anchorages.keys(), sim.event_plan.on.tides]
	if sim._ship_routes_for != stamp:
		sim._ship_routes.clear()
		sim._ship_routes_for = stamp
	return sim._ship_routes


static func _starts(sim: PortSim, kind: String, anchorage: int) -> Array[int]:
	return anchorage_nodes(sim, anchorage) if anchorage else ways_in(sim, kind)


## The way from `starts` to `ends` through lanes a ship of `kind` may sail
## at least `deep` metres deep, in cells: each lane end's middle, and between
## them points SAIL_STEP cells apart along the lane, so a ship follows its
## curves.
static func _find(sim: PortSim, kind: String, deep: float, starts: Array[int], ends: Array[int]) -> Array[Vector2]:
	var coast := sim.areas.coast
	var inland: bool = sim.rules.ship_classes[kind].inland
	var lanes: Dictionary = sim.rules.water.lanes
	var usable := func(segment: int) -> bool: return sim.ship_lanes.depth(segment, coast) >= deep and (inland or not lanes[sim.ship_lanes.segments[segment].type].barges_only)
	var nodes := sim.ship_lanes.route(starts, ends, usable)
	var points: Array[Vector2] = []
	for i in nodes.size():
		if i > 0:
			var segment := sim.ship_lanes.between(nodes[i - 1], nodes[i])
			var line := sim.ship_lanes.curve(segment)
			var forward: bool = sim.ship_lanes.segments[segment].a == nodes[i - 1]
			var steps := ceili(line.length / SAIL_STEP)
			for n in range(1, steps):
				points.append(line.point_at(line.length * (n if forward else steps - n) / steps))
		points.append(Vector2(sim.ship_lanes.nodes[nodes[i]]) + Vector2(0.5, 0.5))
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
	var span := AreaFlow.ship_cells(sim, ship.kind)
	return sim.areas.point(ship.apron, ship.from + (span - 1) / 2.0, sim.areas.depth_of(area) + sim.rules.water.pocket / 2.0)


## Where a ship of `kind` berthing at `from` along `apron` turns to lie
## along its quay, in cells: of the spots along the quay line half its
## length and TURN_MARGIN out with open water all round for its hull to
## swing, the nearest off its berth (off it, if there is room there);
## Vector2.INF if there is none from a ship length before the quay to one
## past it. Kept with the routes, until the lanes, areas, anchorages or
## dredging change.
static func swing_point(sim: PortSim, kind: String, apron: int, from: int) -> Vector2:
	var key := [kind, apron, from, "swing"]
	if key not in _routes(sim):
		var span := AreaFlow.ship_cells(sim, kind)
		var middle := from + (span - 1) / 2.0
		var out := _turn_out(sim, kind, apron)
		var found := Vector2.INF
		var step := maxi(2, span / 8)
		for d: int in range(0, sim.areas.list[apron].columns + 2 * span, step):
			for k: float in [middle - d, middle + d]:
				if found == Vector2.INF and k >= -span and k <= sim.areas.list[apron].columns + span and _open_circle(sim, _off_quay(sim, apron, k, out), span / 2.0):
					found = _off_quay(sim, apron, k, out)
			if found != Vector2.INF:
				break
		sim._ship_routes[key] = found
	return sim._ship_routes[key]


## Off `from`'s berth on `apron` as far out as a ship of `kind` turns, in cells.
static func off_berth(sim: PortSim, kind: String, apron: int, from: int) -> Vector2:
	return _off_quay(sim, apron, from + (AreaFlow.ship_cells(sim, kind) - 1) / 2.0, _turn_out(sim, kind, apron))


static func _turn_out(sim: PortSim, kind: String, apron: int) -> float:
	return sim.areas.depth_of(sim.areas.list[apron]) + AreaFlow.ship_cells(sim, kind) / 2.0 + TURN_MARGIN


## The point `r` rows out from `apron`'s road, `k` columns along it; past
## its ends the quay line runs on straight.
static func _off_quay(sim: PortSim, apron: int, k: float, r: float) -> Vector2:
	var inside := clampf(k, 0.0, sim.areas.list[apron].columns - 1.0)
	return sim.areas.point(apron, inside, r) + sim.areas.heading(apron, inside) * (k - inside)


## Whether every cell within `radius` of `centre` is water: its rim cell by
## cell, its inside every 4 cells, and every breakwater cell; off the map
## the water runs on as at the map's edge, open sea beyond a sea edge.
# shortcut: land under 4 cells across lying wholly inside, other than a breakwater, can hide; check every inside cell if that turns up.
static func _open_circle(sim: PortSim, centre: Vector2, radius: float) -> bool:
	var edge := sim.areas.coast.size - Vector2i.ONE
	var water := func(p: Vector2) -> bool: return sim.areas.is_water(Vector2i(p.floor()).clamp(Vector2i.ZERO, edge))
	var rim := ceili(TAU * radius)
	for i: int in rim:
		if not water.call(centre + Vector2.from_angle(TAU * i / rim) * radius):
			return false
	for dx: int in range(-floori(radius), floori(radius) + 1, 4):
		for dy: int in range(-floori(radius), floori(radius) + 1, 4):
			if dx * dx + dy * dy <= radius * radius and not water.call(centre + Vector2(dx, dy)):
				return false
	for wall: Dictionary in sim.areas.breakwaters.values():
		for cell: Vector2i in Areas.breakwater_cells(wall.from, wall.to):
			if (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(centre) <= radius:
				return false
	return true


## Whether a ship of `kind` coming in along `lanes` must turn to lie along
## `apron`'s quay: over its last half length its lane runs more than
## PARALLEL_DEGREES off the quay.
static func turns(sim: PortSim, kind: String, apron: int, lanes: Array[Vector2]) -> bool:
	if lanes.size() < 2:
		return false
	var back := lanes.size() - 2
	while back > 0 and lanes[back].distance_to(lanes[-1]) < AreaFlow.ship_cells(sim, kind) / 2.0:
		back -= 1
	var side := sim.areas.out_at(apron, sim.areas.list[apron].columns / 2.0)
	return absf((lanes[-1] - lanes[back]).normalized().dot(side)) > sin(deg_to_rad(PARALLEL_DEGREES))


## Whether a ship of `kind` coming in along `lanes` may berth on `apron`:
## straight in, or with somewhere along the quay to turn.
static func room_at(sim: PortSim, kind: String, apron: int, lanes: Array[Vector2]) -> bool:
	return not turns(sim, kind, apron, lanes) or swing_point(sim, kind, apron, 0) != Vector2.INF


## Sets `ship`'s course to its berth: from its spot at anchor if it waits
## at one, in along the lanes, then pushed in sideways alongside. One whose
## last lane runs across the quay leaves the lanes at their point nearest
## where it turns (see swing_point), turns, and sails along the quay to off
## its berth first.
static func set_course(sim: PortSim, ship: PortSim.Ship) -> void:
	ship.path.clear()
	if ship.anchorage:
		ship.path.append(spots(sim, ship.anchorage)[ship.spot])
	var lanes := route(sim, ship.kind, ship.apron, ship.anchorage, ship.light)
	if turns(sim, ship.kind, ship.apron, lanes):
		var swing := swing_point(sim, ship.kind, ship.apron, ship.from)
		# It keeps to its lanes as far as the point on them nearest where it
		# turns, short of the lane's end in the pocket, then sails along the
		# quay to off its berth if it turned elsewhere.
		var leave := 0
		for i: int in lanes.size() - 1:
			if lanes[i].distance_to(swing) < lanes[leave].distance_to(swing):
				leave = i
		ship.path.append_array(lanes.slice(0, leave + 1))
		ship.path.append(swing)
		var off := off_berth(sim, ship.kind, ship.apron, ship.from)
		if off.distance_to(swing) > 0.5:
			ship.path.append(off)
	else:
		ship.path.append_array(lanes)
	ship.path.append(alongside(sim, ship))
	ship.anchorage = 0
	ship.spot = -1
	release(sim, ship)
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


## Pilots home at their stations with their boats, free to take a ship.
static func free_pilots(sim: PortSim) -> int:
	var total := 0
	for id: int in sim.pilot_stations:
		total += sim.boats.ready_at(id).size()
	return total


## Depot `id`'s tugs home and free.
static func free_tugs(sim: PortSim, id: int) -> int:
	return sim.boats.ready_at(id).size()


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
	# The nearest free pilot boat sails out to where the ship sets off.
	var pilot_boat := 0
	var pilot_way: Array[Vector2] = []
	if spec.pilot:
		if sim.pilot_stations.is_empty():
			return "a %s needs a pilot: build a pilot station (Water)" % ship.kind
		var near := INF
		for id: int in sim.pilot_stations:
			for boat: int in sim.boats.ready_at(id):
				var far: float = sim.boats.list[boat].at.distance_to(start)
				if far < near:
					near = far
					pilot_boat = boat
		if pilot_boat == 0:
			return "no pilot free"
		pilot_way = sim.boats.way(sim.areas, sim.boats.list[pilot_boat].at, start)
		if pilot_way.is_empty():
			return "no way by water from a pilot station to it"
		sets_off += Boats.length(sim.boats.list[pilot_boat].at, pilot_way) * Grid.CELL / sim.rules.water.pilots.boat_speed
	# Tugs from the depot nearest its berth meet it off the berth coming in,
	# or alongside going out.
	var depot := 0
	var tugs_at := 0.0
	var tug_way: Array[Vector2] = []
	if spec.tugs > 0 and ship.state != PortSim.Ship.State.ANCHORING:
		var near := INF
		for id: int in sim.tug_depots:
			var far: float = Vector2(sim.tug_depots[id].cell).distance_to(berth)
			if free_tugs(sim, id) >= spec.tugs and far < near:
				near = far
				depot = id
		if depot == 0:
			return "it needs %d tugs free at one depot%s" % [spec.tugs, "" if not sim.tug_depots.is_empty() else ": build a tug depot (Water)"]
		var meet: Vector2 = ship.path[-2] if way == 1 else ship.path[-1]
		var from: Vector2 = sim.boats.list[sim.boats.ready_at(depot)[0]].at
		tug_way = sim.boats.way(sim.areas, from, meet)
		if tug_way.is_empty():
			return "no way by water from a tug depot to it"
		tugs_at = now + Boats.length(from, tug_way) * Grid.CELL / sim.rules.water.tugs.speed
		if way == -1:
			sets_off = maxf(sets_off, tugs_at)
	# A ship whose draft needs the tide sets off only when the water stays high
	# enough all its passage.
	var short := draft(sim, ship.kind, ship.light) - shallowest(sim, ship)
	if short > 0.0:
		var passage: float = _length(ship.path) * Grid.CELL / sim.rules.water.ship_speed
		for k in 11:
			if tide(sim, sets_off + passage * k / 10.0) < short:
				return "it waits for high water: it needs %.1f m more than the channel has" % short
	sim.passages = sim.passages.filter(func(p: Dictionary) -> bool: return p.to >= now)
	var windows := _windows(sim, ship, way, sets_off)
	var margin: float = sim.rules.water.slot_margin_minutes
	for w in windows:
		for p: Dictionary in sim.passages:
			if p.segment == w.segment and p.ship != ship.id and w.from < p.to + margin and p.from < w.to + margin:
				return "no slot free through a narrow lane"
	if spec.pilot:
		sim.ledger.post("pilotage", sim.rules.water.pilots.fee)
	if pilot_boat:
		sim.boats.send(pilot_boat, pilot_way, "out", ship.id)
	if depot:
		for boat: int in sim.boats.ready_at(depot).slice(0, spec.tugs):
			sim.boats.send(boat, tug_way.duplicate(), "out", ship.id)
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


## The tide's height above chart depth at calendar minute `minute`, in
## metres: rising and falling twice a day through water.tides.range; 0 with
## tides switched off.
static func tide(sim: PortSim, minute: float) -> float:
	if not sim.event_plan.on.tides:
		return 0.0
	var tides: Dictionary = sim.rules.water.tides
	return tides.range / 2.0 * cos(TAU * minute / (tides.period_hours * 60.0))


## How much shallower than its draft a ship's way may be, waiting for high
## water: half the tide's range, or nothing with tides off.
static func _tide_allowance(sim: PortSim) -> float:
	return sim.rules.water.tides.range / 2.0 if sim.event_plan.on.tides else 0.0


## The shallowest water on `ship`'s course in metres at chart depth: the
## lanes it sails (between the lane ends it passes, each at its middle, and
## on into its berth's pocket where it turns off short of that lane's end)
## and, bound for a berth, the pocket. Kept with the routes.
static func shallowest(sim: PortSim, ship: PortSim.Ship) -> float:
	var key := ["shallowest", ship.path.duplicate(), ship.apron]
	if key not in _routes(sim):
		var node_at := {}  # a lane end's middle -> the lane end
		for node: int in sim.ship_lanes.nodes:
			node_at[Vector2(sim.ship_lanes.nodes[node]) + Vector2(0.5, 0.5)] = node
		var least := INF
		var last := 0
		for point: Vector2 in ship.path:
			var node: int = node_at.get(point, 0)
			if node == 0:
				continue
			if last:
				least = minf(least, sim.ship_lanes.depth(sim.ship_lanes.between(last, node), sim.areas.coast))
			last = node
		if ship.apron != 0:
			least = minf(least, pocket_depth(sim, ship.apron))
			for end: int in berth_nodes(sim, ship.apron):
				var segment := sim.ship_lanes.between(last, end) if last else 0
				if segment:
					least = minf(least, sim.ship_lanes.depth(segment, sim.areas.coast))
		sim._ship_routes[key] = least
	return sim._ship_routes[key]


## Cells from `point` to the nearest of `bases` (id -> {"cell"}).
static func _nearest(bases: Dictionary, point: Vector2) -> float:
	var near := INF
	for base: Dictionary in bases.values():
		near = minf(near, Vector2(base.cell).distance_to(point))
	return near


## The narrow lanes `ship` passes on its course (in or out), each with the
## calendar minutes it is in it when it sets off at `sets_off`: every leg of
## its course whose middle lies on a narrow lane's line, those in a row on
## one lane joined. A course may leave the lanes short of their end (to
## turn off its berth), so legs, not lane ends, say where it is.
static func _windows(sim: PortSim, ship: PortSim.Ship, way: int, sets_off: float) -> Array[Dictionary]:
	var points := ship.path.duplicate()
	if way == -1:
		points.reverse()
	var narrow := {}  # line cell -> its narrow lane
	for segment: int in sim.ship_lanes.segments:
		if not sim.rules.water.lanes[sim.ship_lanes.segments[segment].type].two_way:
			for cell: Vector2i in sim.ship_lanes.cells(segment):
				narrow[cell] = segment
	var per_cell: float = Grid.CELL / sim.rules.water.ship_speed
	var found: Array[Dictionary] = []
	var at := 0.0
	for i in range(1, points.size()):
		var leg: float = points[i - 1].distance_to(points[i])
		var segment: int = narrow.get(Vector2i(((points[i - 1] + points[i]) / 2.0).floor()), 0)
		if segment:
			if not found.is_empty() and found[-1].segment == segment and is_equal_approx(found[-1].to, sets_off + at * per_cell):
				found[-1].to = sets_off + (at + leg) * per_cell
			else:
				found.append({"segment": segment, "from": sets_off + at * per_cell, "to": sets_off + (at + leg) * per_cell})
		at += leg
	return found


## Lets `ship`'s pilot and tugs go: it is alongside, at anchor or out at
## sea, or has a new course to clear. Its tugs sail home and its pilot boat
## comes to take its pilot off.
static func release(sim: PortSim, ship: PortSim.Ship) -> void:
	sim.boats.release(sim, ship.id, point_along(ship.path, ship.sail))
	ship.cleared = false
	ship.pilot = false
	ship.tugs = 0
	ship.tug_depot = 0


## The way `ship`'s bow points a fraction `sail` along its course: along its
## way, swinging round on the leg to where it turns to lie along the quay
## (the way it then sails, so never further round than it must), then along
## the quay while it sails to off its berth and its tugs push it in
## sideways. Going out it does the same backwards.
static func bow(sim: PortSim, ship: PortSim.Ship, sail: float) -> Vector2:
	var path := ship.path
	var quay := Vector2.DOWN
	var turn := path.size() - 2  # the leg (by its end point) it swings round on
	if ship.apron != 0:
		var side := sim.areas.out_at(ship.apron, ship.from + (AreaFlow.ship_cells(sim, ship.kind) - 1) / 2.0)
		quay = Vector2(-side.y, side.x)
		if path.size() >= 3 and quay.dot(path[-2] - path[-3]) < 0.0:
			quay = -quay
		# Legs along the quay before it is pushed in come after the turn.
		while turn > 1 and absf((path[turn] - path[turn - 1]).normalized().dot(side)) < sin(deg_to_rad(10.0)):
			turn -= 1
	if path.size() < 2:
		return quay
	var left := sail * _length(path)
	for i in range(1, path.size()):
		var leg := path[i - 1].distance_to(path[i])
		if left <= leg or i == path.size() - 1:
			var way := (path[i] - path[i - 1]).normalized() * (1.0 if ship.state == PortSim.Ship.State.ARRIVING else -1.0)
			if ship.apron == 0 or path.size() < 3 or i < turn:
				return way
			if i > turn:
				return quay
			return way.slerp(quay, clampf(left / maxf(leg, 0.0001), 0.0, 1.0))
		left -= leg
	return quay


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
