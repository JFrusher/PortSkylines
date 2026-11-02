class_name Drive
extends RefCounted
## Every way the sim moves vehicles on the roads and areas, in one place:
## the rest of the sim names where a vehicle starts and where it heads (spots,
## Vector3i(area, k, r): a buffer's start, a slot, a gate; area 0 a road
## cell, such as the site's exit) and asks where it is; how it gets there is
## Drive's business. Vehicles are cars on the lane network (M10), moving
## continuously in its Traffic; a spot is the piece that ends at its middle.
## The network is built from the roads, areas and track, and built again
## when they change, every car put back where it was.

## Real seconds a tick: traffic drives in real seconds and metres, and a
## sim second is a calendar minute.
const STEP := SimClock.CALENDAR_MINUTES_PER_TICK * 60.0


## Puts `vehicle` on the lane nearest its first spot's middle (its path's
## first), if there is room.
static func place(sim: PortSim, vehicle: Vehicle) -> bool:
	_refresh(sim)
	var near := sim.network.nearest(sim.areas.centre(vehicle.path[0]), vehicle.kind == "lorry")
	if near[0] == 0 or not sim.traffic.fits(near[0], near[1], _length(sim, vehicle)):
		return false
	var route: Array[int] = [near[0]]
	sim.traffic.place_at(vehicle.id, route, near[1], _top(sim, vehicle), _length(sim, vehicle))
	return true


## The spot `vehicle` stands at, or last stood at before setting off.
static func here(_sim: PortSim, vehicle: Vehicle) -> Vector3i:
	return vehicle.path[0]


## Where `vehicle` is, in cells (a cell's corner, as its cells are).
static func where(sim: PortSim, vehicle: Vehicle, _alpha := 1.0) -> Vector2:
	return pose(sim, vehicle, 1.0)[0]


## [where `vehicle` is, in cells (a cell's corner), the way it heads], for drawing.
static func pose(sim: PortSim, vehicle: Vehicle, _alpha: float) -> Array[Vector2]:
	_refresh(sim)
	if vehicle.id not in sim.traffic.cars:
		return [sim.areas.centre(vehicle.path[0]) - Vector2(0.5, 0.5), Vector2.ZERO]
	var at := sim.traffic.pose(vehicle.id)
	return [at[0] - Vector2(0.5, 0.5), at[1]]


## Where along `path` (cells) something `at` cells in is drawn, as [position
## in grid cells, heading]. Through a cell where the path turns it follows a
## quarter circle between the middles of the cell's edges, so it never
## snaps. Trains still run on cells.
static func path_pose(path: Array[Vector2i], at: float) -> Array[Vector2]:
	var i := clampi(int(at), 0, path.size() - 1)
	var f := at - i
	if path.size() < 2:
		return [Vector2(path[0]), Vector2.ZERO]
	if i >= path.size() - 1:
		return [Vector2(path[-1]), Vector2(path[-1] - path[-2])]
	var corner := i + 1 if f >= 0.5 else i
	if corner > 0 and corner < path.size() - 1:
		var d_in := Vector2(path[corner] - path[corner - 1])
		var d_out := Vector2(path[corner + 1] - path[corner])
		if d_in != d_out and d_in != -d_out:
			var u := (f - 0.5 if corner == i + 1 else f + 0.5) * PI / 2
			var centre := Vector2(path[corner]) + (d_out - d_in) * 0.5
			return [centre + 0.5 * (d_in * sin(u) - d_out * cos(u)), d_in * cos(u) + d_out * sin(u)]
	return [Vector2(path[i]).lerp(Vector2(path[i + 1]), f), Vector2(path[i + 1] - path[i])]


## Sets `vehicle` driving from where it is to `to`, in `state` once there.
## With no route yet it waits where it is and tries again each tick.
static func head(sim: PortSim, vehicle: Vehicle, to: Vector3i, state: String) -> void:
	_refresh(sim)
	vehicle.target = to
	var route := _route_to(sim, vehicle, to)
	if route.is_empty():
		vehicle.state = "no_route:" + state
		return
	sim.traffic.reroute(vehicle.id, route)
	vehicle.state = state


## Whether `vehicle` is where it was heading; the traffic moves every car
## once a tick (signals), so this only asks.
static func advance(sim: PortSim, vehicle: Vehicle, _speed: float) -> bool:
	_refresh(sim)
	if not sim.traffic.arrived(vehicle.id):
		return false
	vehicle.path = [vehicle.target] as Array[Vector3i]
	return true


## Sim seconds `vehicle` has stood still.
static func waited(sim: PortSim, vehicle: Vehicle) -> float:
	return sim.traffic.cars[vehicle.id].waited / 60.0 if vehicle.id in sim.traffic.cars else 0.0


## Takes `vehicle` off the roads.
static func leave(sim: PortSim, vehicle: Vehicle) -> void:
	if sim.traffic and vehicle.id in sim.traffic.cars:
		sim.traffic.remove(vehicle.id)


## Whether there is a way for a lorry (`lorry`) or a tractor from spot `from` to spot `to`.
static func reaches(sim: PortSim, from: Vector3i, to: Vector3i, lorry: bool) -> bool:
	_refresh(sim)
	var start: int = sim.network.nearest(sim.areas.centre(from), lorry)[0]
	if start == 0:
		return false
	var key := [start, to, lorry]
	if key not in sim._reach:
		_best_route(sim, start, to, lorry)
	return sim._reach[key]


## Which way traffic runs along area `id`: 1 from its start to its end, -1
## the other way, 0 when no road lane runs beside it.
static func flow(sim: PortSim, id: int) -> int:
	_refresh(sim)
	return sim.network.flows.get(id, 0)


## A road spot at the site entry heading into the site with room for a
## lorry to stand, or NO_SPOT.
static func entry_cell(sim: PortSim) -> Vector3i:
	_refresh(sim)
	for cell in edge_cells(sim):
		var piece := _lane_ending(sim, cell, true)
		if piece != 0 and sim.traffic.fits(piece, sim.network.pieces[piece].length, sim.rules.traffic.lorry_m / Grid.CELL):
			return Vector3i(0, cell.x, cell.y)
	return Areas.NO_SPOT


## A road spot at the site entry leaving the site, or NO_SPOT.
static func exit_cell(sim: PortSim) -> Vector3i:
	_refresh(sim)
	for cell in edge_cells(sim):
		if _lane_ending(sim, cell, false) != 0:
			return Vector3i(0, cell.x, cell.y)
	return Areas.NO_SPOT


## Cells on the site's east edge near the entry, where the highway's lanes meet the roads.
static func edge_cells(sim: PortSim) -> Array[Vector2i]:
	var entry := sim.site_entry()
	var found: Array[Vector2i] = []
	for dy in range(-8, 9):
		found.append(entry + Vector2i(0, dy))
	return found


## Lane cells where rail track crosses: level crossings, worked out each
## time the network is built.
static func crossings(sim: PortSim) -> Array[Vector2i]:
	_refresh(sim)
	return sim._crossing_cells


## Books exactly crossing `cells` for train `id` (negative), if no car is on
## them; else changes nothing and returns false.
static func rebook(sim: PortSim, id: int, cells: Array[Vector2i]) -> bool:
	_refresh(sim)
	return sim.traffic.rebook(id, cells)


## Lets go of every crossing train `id` books.
static func release(sim: PortSim, id: int) -> void:
	_refresh(sim)
	sim.traffic.release(id)


## What signals and signs live on.
static func junctions(sim: PortSim) -> Junctions:
	return sim.junctions


## What knows the junctions' arms: Junctions takes it as its `lanes`.
static func junction_lanes(sim: PortSim) -> Object:
	_refresh(sim)
	return sim.network


## Junction `point`'s arms.
static func arms(sim: PortSim, point: Vector2i) -> Array:
	_refresh(sim)
	return sim.network.arms(point)


## The cells of the last stretch of arm `arm`'s lanes into junction `point`,
## for drawing.
static func approach_cells(sim: PortSim, point: Vector2i, arm: Vector2i) -> Array:
	_refresh(sim)
	var found := {}
	for piece: int in sim.network.approach(point, arm):
		var points: PackedVector2Array = sim.network.pieces[piece].points
		for i in range(maxi(0, points.size() - 7), points.size()):
			found[Vector2i(points[i].floor())] = true
	return found.keys()


## The junction (its grid point) one of whose connections crosses `cell`, or NONE.
static func junction_at(sim: PortSim, cell: Vector2i) -> Vector2i:
	_refresh(sim)
	for id: int in sim.network.pieces:
		var piece: Dictionary = sim.network.pieces[id]
		if piece.node != 0 and piece.points.size() > 0 and Array(piece.points).any(func(p: Vector2) -> bool: return Vector2i(p.floor()) == cell):
			return sim.roads.nodes[piece.node]
	return Grid.NONE


## Lane cells vehicles wait in -> seconds, for drawing jams.
static func delays(sim: PortSim) -> Dictionary:
	_refresh(sim)
	var found := {}
	var pieces: Dictionary = sim.traffic.delays()
	for piece: int in pieces:
		for point: Vector2 in sim.network.pieces[piece].points:
			var cell := Vector2i(point.floor())
			found[cell] = maxf(found.get(cell, 0.0), pieces[piece])
	return found


## One tick, before the area flow: signals, then every car moves on.
static func signals(sim: PortSim) -> void:
	_refresh(sim)
	sim.junctions.tick(sim.network, sim.traffic)
	sim.traffic.tick(STEP)


## After the area flow: every epoch the waiting settles into delays, and
## every route epoch routes start weighing them.
static func settle(sim: PortSim) -> void:
	if sim.clock.ticks % roundi(sim.rules.traffic.epoch_seconds / SimClock.TICK_SECONDS) == 0:
		sim.traffic.settle(sim.rules.traffic.smoothing)
	if sim.clock.ticks % roundi(sim.rules.traffic.route_epoch_seconds / SimClock.TICK_SECONDS) == 0:
		weigh(sim)


## Routes from now on go round the pieces cars wait on, by the delays last settled.
static func weigh(sim: PortSim) -> void:
	_refresh(sim)
	sim._delays = sim.traffic.delays().duplicate()


## The traffic as saved: every car where it is and how fast, what it has
## booked, and the delays routes weigh. The network isn't saved: a loaded
## game builds the same one from the same roads, areas and track.
static func to_dict(sim: PortSim) -> Dictionary:
	_refresh(sim)
	return {"pieces": sim.network.pieces.size(), "traffic": sim.traffic.to_dict(), "weighed": sim._delays.duplicate()}


## Builds the lane network and its traffic again when the roads, areas or
## track have changed, putting every car back at the cell it is in (or
## stood at) and sending it on to where it was heading; or, first thing in a
## loaded game, puts back the traffic it saved.
static func _refresh(sim: PortSim) -> void:
	var now := Vector3i(sim.roads.version, sim.areas.version, sim.rails.version)
	if now == sim._drive_for and sim.traffic != null:
		return
	var old := sim.traffic
	sim._drive_for = now
	sim.network = LaneNetwork.new(sim.roads, sim.rules.junctions)
	sim.network.add_driveways(sim.areas, sim.rules.traffic.area_kmh)
	for cell in edge_cells(sim):
		sim.network.split_at(Vector2(cell) + Vector2(0.5, 0.5))
	sim.traffic = Traffic.new(sim.network, sim.rules, sim.junctions)
	sim._crossing_cells = _level_crossings(sim)
	sim.traffic.set_crossings(sim._crossing_cells)
	sim._delays.clear()
	sim._reach.clear()
	if not sim._loaded_traffic.is_empty():
		assert(sim._loaded_traffic.pieces == sim.network.pieces.size(), "a loaded game builds the network it saved")
		sim.traffic.restore(sim._loaded_traffic.traffic)
		sim._delays = sim._loaded_traffic.weighed.duplicate()
		sim._loaded_traffic = {}
		return
	for vehicle: Vehicle in sim.vehicles:
		# Where its car was; only a vehicle with no car yet goes by its spot.
		var at: Vector2 = old.pose(vehicle.id)[0] if old != null and vehicle.id in old.cars else sim.areas.centre(vehicle.path[0])
		var near := sim.network.nearest(at, vehicle.kind == "lorry")
		assert(near[0] != 0, "a vehicle stands on the lanes")
		var route: Array[int] = [near[0]]
		sim.traffic.place_at(vehicle.id, route, near[1], _top(sim, vehicle), _length(sim, vehicle))
		if vehicle.target != Areas.NO_SPOT and vehicle.state.trim_prefix("no_route:") in ["arriving", "to_slot", "returning", "leaving", "to_crane"]:
			var state := vehicle.state.trim_prefix("no_route:")
			head(sim, vehicle, vehicle.target, state)
	if old != null:
		for cell: Vector2i in old._crossings:
			if old._crossings[cell] != 0:
				sim.traffic._crossings[cell] = old._crossings[cell]


## The track's cells that a road lane runs through, track segment by
## segment.
static func _level_crossings(sim: PortSim) -> Array[Vector2i]:
	var lane_cells := {}
	for id: int in sim.network.pieces:
		if sim.network.pieces[id].segment != 0:
			for point: Vector2 in sim.network.pieces[id].points:
				lane_cells[Vector2i(point.floor())] = true
	var found: Array[Vector2i] = []
	for id: int in sim.rails.segments:
		for cell in sim.rails.cells(id):
			if cell in lane_cells:
				found.append(cell)
	return found


## The route for `vehicle` from the piece it is on to the piece ending at
## `to`, the best of those that end there; [] when there is none.
static func _route_to(sim: PortSim, vehicle: Vehicle, to: Vector3i) -> Array[int]:
	if vehicle.id not in sim.traffic.cars:
		return []
	var car: Dictionary = sim.traffic.cars[vehicle.id]
	return _best_route(sim, car.route[car.i], to, vehicle.kind == "lorry")


## The best route from piece `start` to `to`'s middle for a lorry (`lorry`)
## or a tractor, by length and delay; [] when there is none. Whether there
## is one is kept in sim._reach until the network is built again, so a way
## that isn't there is searched for once, not every tick.
static func _best_route(sim: PortSim, start: int, to: Vector3i, lorry: bool) -> Array[int]:
	var key := [start, to, lorry]
	if not sim._reach.get(key, true):
		return []
	var speed: float = (sim.rules.lorry_speed if lorry else sim.rules.tractor.speed) / 60.0 / Grid.CELL  # m a minute -> cells a second
	var ends: Array[int] = []
	for end in sim.network.ending_at(sim.areas.centre(to)):
		if not lorry or sim.network.pieces[end].lorries:
			ends.append(end)
	var route: Array[int] = []
	if not ends.is_empty():
		route = sim.network.route_to_any(start, ends, lorry, sim._delays, speed)
	sim._reach[key] = not route.is_empty()
	return route


## The road lane piece ending at `cell`'s middle heading into the site
## (`inward`, west) or out of it, or 0.
static func _lane_ending(sim: PortSim, cell: Vector2i, inward: bool) -> int:
	for id in sim.network.ending_at(Vector2(cell) + Vector2(0.5, 0.5)):
		var piece: Dictionary = sim.network.pieces[id]
		if piece.segment != 0 and piece.points.size() >= 2 and ((piece.points[-1].x < piece.points[-2].x) == inward):
			return id
	return 0


## `vehicle`'s top speed, cells a second.
static func _top(sim: PortSim, vehicle: Vehicle) -> float:
	return (sim.rules.lorry_speed if vehicle.kind == "lorry" else sim.rules.tractor.speed) / 60.0 / Grid.CELL


## `vehicle`'s length, cells.
static func _length(sim: PortSim, vehicle: Vehicle) -> float:
	return (sim.rules.traffic.lorry_m if vehicle.kind == "lorry" else sim.rules.traffic.tractor_m) / Grid.CELL
