class_name Train
extends RefCounted
## A train from off the map to one rail block's siding and back, moved by
## RailFlow along `path`, its head `t` cells in. It stands with a wagon at each
## bay of the siding while the block's RMGs work it. `state` is "arriving",
## "working" or "leaving".

var id: int
## The rail block it serves.
var block: int
## Points a cell apart along the track from the rail entry to the siding's
## far end (RoadNet.path), in grid units.
var path: Array[Vector2]
## How far along `path` its head is, in cells, and that at the start of this
## tick, for drawing between ticks.
var t := 0.0
var prev_t := 0.0
var state := "arriving"
## The calendar minute it may leave its siding, set as it arrives there.
var depart := 0.0
## The box on each wagon, 0 for none; wagon 0 stands at the siding's first bay.
var wagons: Array[int] = []
## Wagons an RMG is working now, so no two jobs take one.
var busy: Array[int] = []


func _init(train_id: int, serves: int, route: Array[Vector2], wagon_count: int) -> void:
	id = train_id
	block = serves
	path = route
	for i in wagon_count:
		wagons.append(0)


## How many cells long it is: a wagon per bay, and a locomotive a bay long.
func length() -> int:
	return (wagons.size() + 1) * AreaLayout.BAY


## [where along `path` it is `at` cells in, its way there]: between the
## path's points, so it follows the track's curves.
func pose(at: float) -> Array[Vector2]:
	if path.size() < 2:
		return [path[0], Vector2.RIGHT]
	var i := clampi(floori(at), 0, path.size() - 2)
	return [path[i].lerp(path[i + 1], clampf(at - i, 0.0, 1.0)), (path[i + 1] - path[i]).normalized()]


## The grid cells its path runs over from point `from` to point `to`, in order.
func cells(from: int, to: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for i in range(from, to + 1):
		for n in (4 if i < to else 1):
			var cell := Vector2i(path[i].lerp(path[mini(i + 1, path.size() - 1)], n / 4.0).floor())
			if found.is_empty() or found[-1] != cell:
				found.append(cell)
	return found


func to_dict() -> Dictionary:
	return {"id": id, "block": block, "path": path.duplicate(), "t": t, "prev_t": prev_t, "state": state, "depart": depart, "wagons": wagons.duplicate(), "busy": busy.duplicate()}


static func from_dict(d: Dictionary) -> Train:
	var route: Array[Vector2] = []
	route.assign(d.path)
	var train := Train.new(d.id, d.block, route, 0)
	train.t = d.t
	train.prev_t = d.prev_t
	train.state = d.state
	train.depart = d.depart
	train.wagons.assign(d.wagons)
	train.busy.assign(d.busy)
	return train
