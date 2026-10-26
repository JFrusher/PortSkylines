class_name Train
extends RefCounted
## A train from off the map to one rail block's siding and back, moved by
## RailFlow along `path`, its head `t` cells in. It stands with a wagon at each
## bay of the siding while the block's RMGs work it. `state` is "arriving",
## "working" or "leaving".

var id: int
## The rail block it serves.
var block: int
## Track cells from the rail entry to the siding's far end.
var path: Array[Vector2i]
## How far along `path` its head is, in cells, and that at the start of this
## tick, for drawing between ticks.
var t := 0.0
var prev_t := 0.0
var state := "arriving"
## The box on each wagon, 0 for none; wagon 0 stands at the siding's first bay.
var wagons: Array[int] = []
## Wagons an RMG is working now, so no two jobs take one.
var busy: Array[int] = []


func _init(train_id: int, serves: int, route: Array[Vector2i], wagon_count: int) -> void:
	id = train_id
	block = serves
	path = route
	for i in wagon_count:
		wagons.append(0)


## How many cells long it is: a wagon per bay, and a locomotive a bay long.
func length() -> int:
	return (wagons.size() + 1) * AreaLayout.BAY


func to_dict() -> Dictionary:
	return {"id": id, "block": block, "path": path.duplicate(), "t": t, "prev_t": prev_t, "state": state, "wagons": wagons.duplicate(), "busy": busy.duplicate()}


static func from_dict(d: Dictionary) -> Train:
	var route: Array[Vector2i] = []
	route.assign(d.path)
	var train := Train.new(d.id, d.block, route, 0)
	train.t = d.t
	train.prev_t = d.prev_t
	train.state = d.state
	train.wagons.assign(d.wagons)
	train.busy.assign(d.busy)
	return train
