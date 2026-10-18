class_name Vehicle
extends RefCounted
## A lorry or terminal tractor driving a road path. It holds one lane at a
## time (see Traffic) and moves into the next tile only once it holds that
## tile's lane.

var id: int
var kind: String
var path: Array[Vector2i]
## Distance travelled along `path`, in tiles.
var t := 0.0
## `t` at the start of this tick, for drawing between ticks.
var prev_t := 0.0
## The lane it holds now.
var lane: Vector3i
## Ticks spent waiting for the next lane.
var waited := 0
var replanned := false
## Lorry job: the yard tile it collects from, and whether it has the box.
var yard := PortMap.NONE
var loaded := false


func _init(vehicle_id: int, vehicle_kind: String, route: Array[Vector2i]) -> void:
	id = vehicle_id
	kind = vehicle_kind
	path = route


## Position in tile coordinates, `alpha` of the way from the last tick to this one.
func position(alpha: float) -> Vector2:
	var at := lerpf(prev_t, t, alpha)
	var i := mini(int(at), path.size() - 1)
	var j := mini(i + 1, path.size() - 1)
	return Vector2(path[i]).lerp(Vector2(path[j]), clampf(at - i, 0.0, 1.0))


func at_end() -> bool:
	return t >= path.size() - 1


func to_dict() -> Dictionary:
	return {"id": id, "kind": kind, "path": path.duplicate(), "t": t, "prev_t": prev_t, "lane": lane, "waited": waited, "replanned": replanned, "yard": yard, "loaded": loaded}


static func from_dict(d: Dictionary) -> Vehicle:
	var route: Array[Vector2i] = []
	route.assign(d.path)
	var vehicle := Vehicle.new(d.id, d.kind, route)
	vehicle.t = d.t
	vehicle.prev_t = d.prev_t
	vehicle.lane = d.lane
	vehicle.waited = d.waited
	vehicle.replanned = d.replanned
	vehicle.yard = d.yard
	vehicle.loaded = d.loaded
	return vehicle
