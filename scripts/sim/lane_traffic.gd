class_name LaneTraffic
extends RefCounted
## Who holds each cell of the lane graph, and vehicles moving along their
## routes. A 4 m cell is one lane, so a vehicle enters a cell only once it
## holds it, and no two vehicles are ever in one cell. Junction cells are
## shared by crossing traffic, so a vehicle books every junction cell ahead
## and the first cell past them before it enters: it never stops in a junction.
## The cells and the moves are kept natively, in LaneCells
## (native/src/lane_cells.cpp): this loop runs for every moving vehicle a tick.

var _lanes: LaneGraph
var cells := LaneCells.new()


func _init(lanes: LaneGraph) -> void:
	_lanes = lanes


## Puts `vehicle` at the start of its route, if that cell is free.
func place(vehicle: Vehicle) -> bool:
	return cells.take(vehicle.id, [vehicle.path[0]])


## Moves `vehicle` up to `speed` cells a second for one tick, entering each
## cell on the way in turn and stopping short of the first it can't take.
## Entering a cell takes it, and if it is a junction cell every junction cell
## after it and the first cell past them too, then lets go of every other cell,
## including ones its route passes again later, so a route that comes back the
## same way never holds a cell it has left. True once it is at the end of its route.
func advance(vehicle: Vehicle, speed: float) -> bool:
	vehicle.prev_t = vehicle.t
	if vehicle.at_end():
		return true
	var moved := cells.advance(vehicle.id, vehicle.path, vehicle.t, speed * SimClock.TICK_SECONDS, vehicle.waited, _lanes.junctions())
	vehicle.t = moved[0]
	vehicle.waited = int(moved[1])
	return moved[2] > 0.0


## Lets go of every cell `vehicle` holds.
func leave(vehicle: Vehicle) -> void:
	release(vehicle.id)


## Books all of `wanted` for `id` if each is free or already theirs, else
## none: a train takes a level crossing this way.
func book(id: int, wanted: Array[Vector2i]) -> bool:
	return cells.take(id, wanted)


## Books exactly `wanted` for `id`, letting go of the rest it holds, if each
## is free or already theirs; else changes nothing and returns false. A
## moving train keeps the level crossings under and ahead of it this way.
func rebook(id: int, wanted: Array[Vector2i]) -> bool:
	return cells.rebook(id, wanted)


## Lets go of every cell `id` holds.
func release(id: int) -> void:
	cells.release(id)


func to_dict() -> Dictionary:
	return cells.to_dict()


static func from_dict(d: Dictionary, lanes: LaneGraph) -> LaneTraffic:
	var traffic := LaneTraffic.new(lanes)
	traffic.cells.load(d)
	return traffic


## The cells vehicle `id` holds.
func held_by(id: int) -> Array:
	return cells.held_by(id)


func holder(cell: Vector2i) -> int:
	return cells.holder(cell)
