class_name Drive
extends RefCounted
## Every way the sim moves vehicles on the roads and areas, in one place:
## the rest of the sim names where a vehicle starts and where it heads (grid
## cells: a buffer's start, a slot, a gate, the site's exit) and asks where it
## is; how it gets there is Drive's business. (M10 moves it from the lane
## graph's cells to the lane network and continuous traffic, behind these
## same calls.)


## Puts `vehicle` on its first cell (its path's first) if that is free.
static func place(sim: PortSim, vehicle: Vehicle) -> bool:
	return sim.lane_traffic.place(vehicle)


## The cell `vehicle` is at.
static func here(_sim: PortSim, vehicle: Vehicle) -> Vector2i:
	return vehicle.path[int(vehicle.t)]


## Where `vehicle` is, in grid units, `alpha` of the way through this tick.
static func where(_sim: PortSim, vehicle: Vehicle, alpha := 1.0) -> Vector2:
	return vehicle.position(alpha)


## [where `vehicle` is, in cells (a cell's corner, as its route's cells
## are), the way it heads], `alpha` of the way through this tick, for drawing.
static func pose(_sim: PortSim, vehicle: Vehicle, alpha: float) -> Array[Vector2]:
	return path_pose(vehicle.path, lerpf(vehicle.prev_t, vehicle.t, alpha))


## Where along `path` a vehicle `at` cells in is drawn, as [position in grid
## cells, heading]. Through a cell where the path turns it follows a quarter
## circle between the middles of the cell's edges, so it never snaps.
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


## Sets `vehicle` driving from where it stands to `to`, in `state` once
## there. With no route yet it waits where it is and tries again each tick.
static func head(sim: PortSim, vehicle: Vehicle, to: Vector2i, state: String) -> void:
	var here_cell := here(sim, vehicle)
	var route := sim.lanes.route(here_cell, to, vehicle.kind == "lorry")
	var new_path: Array[Vector2i] = []
	if not route.is_empty():
		new_path.assign(route)
	else:
		new_path.append(here_cell)
	vehicle.path = new_path
	vehicle.t = 0.0
	vehicle.prev_t = 0.0
	vehicle.state = state if not route.is_empty() else "no_route:" + state
	vehicle.target = to


## Moves `vehicle` on for one tick at `speed` cells a second; true once it
## is where it was heading.
static func advance(sim: PortSim, vehicle: Vehicle, speed: float) -> bool:
	return sim.lane_traffic.advance(vehicle, speed)


## Seconds `vehicle` has been stuck.
static func waited(_sim: PortSim, vehicle: Vehicle) -> float:
	return vehicle.waited * SimClock.TICK_SECONDS


## Takes `vehicle` off the roads.
static func leave(sim: PortSim, vehicle: Vehicle) -> void:
	sim.lane_traffic.leave(vehicle)


## Whether there is a way for a lorry (`lorry`) or a tractor from `from` to `to`.
static func reaches(sim: PortSim, from: Vector2i, to: Vector2i, lorry: bool) -> bool:
	return not sim.lanes.route(from, to, lorry).is_empty()


## Which way traffic runs along area `id`: 1 from its start to its end, -1
## the other way, 0 when no road lane runs beside it.
static func flow(sim: PortSim, id: int) -> int:
	return sim.lanes.flow_of(id)


## A free lane cell at the site entry heading into the site, or NONE.
static func entry_cell(sim: PortSim) -> Vector2i:
	for cell in edge_cells(sim):
		if sim.lane_traffic.holder(cell) == 0 and sim.lanes.steps_at(cell).any(func(step: Vector2i) -> bool: return step.x < 0):
			return cell
	return Grid.NONE


## A lane cell at the site entry leaving the site, or NONE.
static func exit_cell(sim: PortSim) -> Vector2i:
	for cell in edge_cells(sim):
		var steps := sim.lanes.steps_at(cell)
		if not steps.is_empty() and not steps.any(func(step: Vector2i) -> bool: return step.x < 0):
			return cell
	return Grid.NONE


## Cells on the site's east edge near the entry, where the highway's lanes meet the roads.
static func edge_cells(sim: PortSim) -> Array[Vector2i]:
	var entry := sim.site_entry()
	var found: Array[Vector2i] = []
	for dy in range(-8, 9):
		found.append(entry + Vector2i(0, dy))
	return found


## Lane cells where rail track crosses: level crossings.
static func crossings(sim: PortSim) -> Array[Vector2i]:
	return sim.lanes.crossings()


## Books exactly crossing `cells` for train `id` (negative), if no vehicle
## is on them; else changes nothing and returns false.
static func rebook(sim: PortSim, id: int, cells: Array[Vector2i]) -> bool:
	return sim.lane_traffic.rebook(id, cells)


## Lets go of every crossing train `id` books.
static func release(sim: PortSim, id: int) -> void:
	sim.lane_traffic.release(id)


## What signals and signs live on, and what they ask about junctions.
static func junctions(sim: PortSim) -> Junctions:
	return sim.lane_traffic.junctions


## What knows the junctions' arms: Junctions takes it as its `lanes`.
static func junction_lanes(sim: PortSim) -> Object:
	return sim.lanes


## Junction `point`'s arms.
static func arms(sim: PortSim, point: Vector2i) -> Array:
	return sim.lanes.arms(point)


## The cells of arm `arm`'s approach to junction `point`, for drawing.
static func approach_cells(sim: PortSim, point: Vector2i, arm: Vector2i) -> Array:
	return sim.lanes.approach(point, arm)


## The junction (its grid point) whose box covers `cell`, or NONE.
static func junction_at(sim: PortSim, cell: Vector2i) -> Vector2i:
	return sim.lanes.box_of(cell)


## Lane cells vehicles wait in -> seconds, for drawing jams.
static func delays(sim: PortSim) -> Dictionary:
	return sim.lane_traffic.delays()


## One tick of the signals, before vehicles move.
static func signals(sim: PortSim) -> void:
	sim.lane_traffic.junctions.tick(sim.lanes, sim.lane_traffic)


## After vehicles move: every epoch the waiting settles into delays, and
## every route epoch routes start weighing them.
static func settle(sim: PortSim) -> void:
	if sim.clock.ticks % roundi(sim.rules.traffic.epoch_seconds / SimClock.TICK_SECONDS) == 0:
		sim.lane_traffic.settle(sim.rules.traffic.smoothing)
	if sim.clock.ticks % roundi(sim.rules.traffic.route_epoch_seconds / SimClock.TICK_SECONDS) == 0:
		weigh(sim)


## Routes from now on go round the cells vehicles wait in, by the delays last settled.
static func weigh(sim: PortSim) -> void:
	sim.lanes.set_delays(sim.lane_traffic.delays(), sim.rules.lorry_speed / Grid.CELL, AreaFlow.tractor_speed(sim))
