class_name Boats
extends RefCounted
## The port's pilot boats and tugs, on the water. Each pilot hired has a
## boat: it takes its pilot out to a ship where it sets off, sails home, and
## fetches the pilot off once the ship is alongside, at anchor or out at
## sea; the pilot is free again only once its boat is home with it. Tugs sail
## out to meet a ship, stay with it while it berths or unberths, then sail
## home. Boats cross open water straight, steering round land.

## Cells between the middles of the coarse grid boats steer round land on.
const STEP := 4

## Boat id -> {"kind": "pilot", "tug" or a service it sees to ("bunkers",
## "provisions", "waste"), "base": its station, depot or services jetty,
## "at": where it is, "path": the points it still has to sail through (in
## cells), "ship": the ship it serves or 0, "job": one of
## "home": at its base, ready (a pilot boat with its pilot aboard);
## "out": sailing to meet its ship;
## "with": a tug with its ship, moving with it;
## "back": sailing home (a pilot boat whose `ship` is set left its pilot aboard);
## "ashore": a pilot boat at its base while its pilot is aboard `ship`;
## "fetch": a pilot boat sailing to take its pilot off}.
var list := {}
var _next := 1
var _grid: AStarGrid2D
var _grid_version := -1


## Adds a boat of `kind` at its base `base` standing at `cell`.
func add(kind: String, base: int, cell: Vector2i) -> void:
	list[_next] = {"kind": kind, "base": base, "at": _middle(cell), "path": [] as Array[Vector2], "ship": 0, "job": "home"}
	_next += 1


## Boats of base `base`.
func of(base: int) -> Array[int]:
	var found: Array[int] = []
	for id: int in list:
		if list[id].base == base:
			found.append(id)
	return found


## Boats of base `base` home and ready.
func ready_at(base: int) -> Array[int]:
	return of(base).filter(func(id: int) -> bool: return list[id].job == "home")


## Takes base `base`'s boats out of the port.
func remove_base(base: int) -> void:
	for id: int in of(base):
		list.erase(id)


## The points from `from` to `to` (without `from`) over water: straight when
## the water between is open, else round the land on a coarse grid; empty
## when no way by water joins them.
func way(areas: Areas, from: Vector2, to: Vector2) -> Array[Vector2]:
	if _open(areas, from, to):
		return [to] as Array[Vector2]
	_refresh(areas)
	var a := _nearest_open(_coarse(from))
	var b := _nearest_open(_coarse(to))
	if a == Vector2i(-1, -1) or b == Vector2i(-1, -1):
		return [] as Array[Vector2]
	var cells := _grid.get_id_path(a, b)
	if cells.is_empty():
		return [] as Array[Vector2]
	var points: Array[Vector2] = [from]
	for cell: Vector2i in cells:
		points.append(Vector2(cell * STEP) + Vector2.ONE * STEP / 2.0)
	points.append(to)
	# Pull the string: from each point, on to the furthest it can see.
	var pulled: Array[Vector2] = []
	var i := 0
	while i < points.size() - 1:
		var j := points.size() - 1
		while j > i + 1 and not _open(areas, points[i], points[j]):
			j -= 1
		pulled.append(points[j])
		i = j
	return pulled


## Cells along `path` from `from`.
static func length(from: Vector2, path: Array[Vector2]) -> float:
	var total := 0.0
	var at := from
	for point: Vector2 in path:
		total += at.distance_to(point)
		at = point
	return total


## Sets boat `id` sailing `path` to do `job` for ship `ship`.
func send(id: int, path: Array[Vector2], job: String, ship: int) -> void:
	assert(not path.is_empty(), "a boat is sent somewhere")
	list[id].path = path
	list[id].job = job
	list[id].ship = ship


## Sends boat `id` home to `base_cell`, `ship` the one its pilot stays aboard or 0.
func go_home(areas: Areas, id: int, base_cell: Vector2i, ship: int) -> void:
	var path := way(areas, list[id].at, _middle(base_cell))
	assert(not path.is_empty(), "a boat that sailed out can sail home")
	send(id, path, "back", ship)


## Moves every boat a tick: along its path at its speed, or with its ship.
func tick(sim: PortSim) -> void:
	for id: int in list:
		var boat: Dictionary = list[id]
		if boat.job == "with":
			var ship := _ship(sim, boat.ship)
			assert(ship != null, "a tug with a ship has its ship")
			boat.at = Marine.point_along(ship.path, ship.sail)
			continue
		if boat.path.is_empty():
			continue
		var speed := Boats.speed(sim, boat.kind)
		var left := speed / Grid.CELL * SimClock.CALENDAR_MINUTES_PER_TICK
		while left > 0.0 and not boat.path.is_empty():
			var to: Vector2 = boat.path[0]
			var gap: float = boat.at.distance_to(to)
			if gap <= left:
				boat.at = to
				boat.path.pop_front()
				left -= gap
			else:
				boat.at += (to - boat.at) / gap * left
				left = 0.0
		if boat.path.is_empty():
			_arrive(sim, id)


## Boat `id`, at the end of its path, takes up what comes next: a tug
## stays with its ship; a pilot boat leaves its pilot aboard, or takes them
## off, and sails home; one home again rests there.
func _arrive(sim: PortSim, id: int) -> void:
	var boat: Dictionary = list[id]
	match boat.job:
		"out":
			if boat.kind == "tug":
				boat.job = "with"
			else:
				go_home(sim.areas, id, sim.marine_base_cell(boat.base), boat.ship)
		"fetch":
			go_home(sim.areas, id, sim.marine_base_cell(boat.base), 0)
		"back":
			boat.job = "ashore" if boat.ship else "home"


## Lets ship `ship_id`'s boats go: its tugs sail home; its pilot boat takes
## its pilot off at `at` (where the ship is now) and sails home, or, if it
## had not yet put the pilot aboard, sails home with them.
func release(sim: PortSim, ship_id: int, at: Vector2) -> void:
	for id: int in list:
		var boat: Dictionary = list[id]
		if boat.ship != ship_id:
			continue
		if boat.kind == "tug":
			go_home(sim.areas, id, sim.marine_base_cell(boat.base), 0)
		elif boat.job == "out":
			go_home(sim.areas, id, sim.marine_base_cell(boat.base), 0)
		elif boat.job in ["back", "ashore"]:
			var path := way(sim.areas, boat.at, at)
			assert(not path.is_empty(), "a pilot boat reaches its ship")
			send(id, path, "fetch", ship_id)


## Lets ship `ship_id`'s tugs go home: it is off the quay.
func release_tugs(sim: PortSim, ship_id: int) -> void:
	for id: int in list:
		var boat: Dictionary = list[id]
		if boat.ship == ship_id and boat.kind == "tug":
			go_home(sim.areas, id, sim.marine_base_cell(boat.base), 0)


func to_dict() -> Dictionary:
	return {"list": list.duplicate(true), "next": _next}


static func from_dict(d: Dictionary) -> Boats:
	var boats := Boats.new()
	for id: int in d.list:
		var boat: Dictionary = d.list[id].duplicate(true)
		var path: Array[Vector2] = []
		path.assign(boat.path)
		boat.path = path
		boats.list[id] = boat
	boats._next = d.next
	return boats


## Metres a minute a boat of `kind` sails.
static func speed(sim: PortSim, kind: String) -> float:
	if kind == "pilot":
		return sim.rules.water.pilots.boat_speed
	if kind == "tug":
		return sim.rules.water.tugs.speed
	return sim.rules.water.services.boats[kind].speed


static func _ship(sim: PortSim, id: int) -> PortSim.Ship:
	for ship: PortSim.Ship in sim.ships:
		if ship.id == id:
			return ship
	return null


static func _middle(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


## Whether the water is open all the way from `a` to `b`.
static func _open(areas: Areas, a: Vector2, b: Vector2) -> bool:
	var steps := ceili(a.distance_to(b) * 2.0)
	for k: int in steps + 1:
		if not areas.is_water(Vector2i(a.lerp(b, float(k) / maxi(steps, 1)).floor())):
			return false
	return true


func _refresh(areas: Areas) -> void:
	if _grid_version == areas.version:
		return
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(Vector2i.ZERO, (areas.coast.size + Vector2i.ONE * (STEP - 1)) / STEP)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for x: int in _grid.region.size.x:
		for y: int in _grid.region.size.y:
			_grid.set_point_solid(Vector2i(x, y), not areas.is_water(Vector2i(x, y) * STEP + Vector2i.ONE * (STEP / 2)))
	_grid_version = areas.version


static func _coarse(point: Vector2) -> Vector2i:
	return Vector2i(point.floor()) / STEP


## The open coarse cell nearest `cell`, within a few, or (-1, -1).
func _nearest_open(cell: Vector2i) -> Vector2i:
	for r: int in 4:
		for dx: int in range(-r, r + 1):
			for dy: int in range(-r, r + 1):
				var near := cell + Vector2i(dx, dy)
				if _grid.is_in_boundsv(near) and not _grid.is_point_solid(near):
					return near
	return Vector2i(-1, -1)
