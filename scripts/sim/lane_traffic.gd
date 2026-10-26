class_name LaneTraffic
extends RefCounted
## Who holds each cell of the lane graph, and vehicles moving along their
## routes. A 4 m cell is one lane, so a vehicle enters a cell only once it
## holds it, and no two vehicles are ever in one cell. Junction cells are
## shared by crossing traffic, so a vehicle books every junction cell ahead
## and the first cell past them before it enters: it never stops in a junction.

var _lanes: LaneGraph
var _holders := {}  # cell -> vehicle id
var _held := {}  # vehicle id -> cells it holds


func _init(lanes: LaneGraph) -> void:
	_lanes = lanes


## Puts `vehicle` at the start of its route, if that cell is free.
func place(vehicle: Vehicle) -> bool:
	return _take(vehicle.id, [vehicle.path[0]])


## Moves `vehicle` up to `speed` cells a second for one tick, entering each
## cell on the way in turn and stopping short of the first it can't take.
## True once it is at the end of its route.
func advance(vehicle: Vehicle, speed: float) -> bool:
	vehicle.prev_t = vehicle.t
	if vehicle.at_end():
		return true
	var target := minf(vehicle.t + speed * SimClock.TICK_SECONDS, vehicle.path.size() - 1)
	var start := int(vehicle.t)
	while int(target) > int(vehicle.t):
		var i := int(vehicle.t)
		if not _enter(vehicle, i + 1):
			vehicle.t = maxf(vehicle.t, i + 0.95)
			# Waiting counts only ticks it entered no cell at all.
			vehicle.waited = vehicle.waited + 1 if i == start else 0
			return false
		vehicle.t = i + 1
	vehicle.waited = 0
	vehicle.t = target
	return vehicle.at_end()


## Lets go of every cell `vehicle` holds.
func leave(vehicle: Vehicle) -> void:
	for cell: Vector2i in _held.get(vehicle.id, []):
		_holders.erase(cell)
	_held.erase(vehicle.id)


func to_dict() -> Dictionary:
	return _held.duplicate(true)


static func from_dict(d: Dictionary, lanes: LaneGraph) -> LaneTraffic:
	var traffic := LaneTraffic.new(lanes)
	for id: int in d:
		traffic._held[id] = d[id].duplicate()
		for cell: Vector2i in d[id]:
			traffic._holders[cell] = id
	return traffic


## The cells vehicle `id` holds.
func held_by(id: int) -> Array:
	return _held.get(id, [])


func holder(cell: Vector2i) -> int:
	return _holders.get(cell, 0)


## Takes path[i] for `vehicle`, and if it is a junction cell, every junction
## cell after it and the first cell past them too; then lets go of every other
## cell, including ones its route passes again later, so a route that comes
## back the same way never holds a cell it has left.
func _enter(vehicle: Vehicle, i: int) -> bool:
	var want: Array[Vector2i] = [vehicle.path[i]]
	var j := i
	while _lanes.is_junction(vehicle.path[j]) and j + 1 < vehicle.path.size():
		j += 1
		want.append(vehicle.path[j])
	if not _take(vehicle.id, want):
		return false
	var keep := {}
	for cell in want:
		keep[cell] = true
	var held: Array = _held[vehicle.id]
	for cell: Vector2i in held.duplicate():
		if cell not in keep:
			_holders.erase(cell)
			held.erase(cell)
	return true


## Takes all of `cells` for `id` if each is free or already theirs, else none.
func _take(id: int, cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if _holders.get(cell, id) != id:
			return false
	var held: Array = _held.get(id, [])
	for cell in cells:
		if cell not in held:
			held.append(cell)
		_holders[cell] = id
	_held[id] = held
	return true
