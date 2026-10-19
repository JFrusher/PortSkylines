class_name Vehicle
extends RefCounted
## A lorry or terminal tractor. It holds one lane at a time (see Traffic) and
## moves into the next tile only once it holds that tile's lane. `state` is
## "drive" along `path`, "yard" queueing on the road for a machine at
## `target`, "handling" in the block's bay while a machine works for `timer`
## minutes, "gate" while a lorry is processed at a gate, "under_crane"
## (tractors, on the quay) or "no_route" waiting for
## the road or lane it needs. Under a crane and in a bay it holds no lane.

var id: int
var kind: String
var path: Array[Vector2i]
## Distance travelled along `path`, in tiles.
var t := 0.0
## `t` at the start of this tick, for drawing between ticks.
var prev_t := 0.0
## The lane it holds now; Traffic.NO_LANE while it is off the road.
var lane := Traffic.NO_LANE
## While crossing a junction, the lane just past it, held as it enters so it
## never stops inside the junction; otherwise Traffic.NO_LANE.
var ahead := Traffic.NO_LANE
## Ticks spent waiting for the next lane.
var waited := 0
var replanned := false
var state := "drive"
## The box it carries or has come for (0 for none), and whether it is on board.
var box := 0
var loaded := false
## The yard tile it delivers to or collects from.
var target := PortMap.NONE
## Where a tractor parks: the road behind its crane.
var home := PortMap.NONE
## Minutes left of handling or gate processing, and the block whose machine is doing it.
var timer := 0.0
var block := PortMap.NONE
## Calendar minute a lorry came in through a gate, or -1 before it has.
var gate_in := -1.0


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
	return {
		"id": id, "kind": kind, "path": path.duplicate(), "t": t, "prev_t": prev_t, "lane": lane, "ahead": ahead,
		"waited": waited, "replanned": replanned, "state": state, "box": box, "loaded": loaded,
		"target": target, "home": home, "timer": timer, "block": block, "gate_in": gate_in,
	}


static func from_dict(d: Dictionary) -> Vehicle:
	var route: Array[Vector2i] = []
	route.assign(d.path)
	var vehicle := Vehicle.new(d.id, d.kind, route)
	vehicle.t = d.t
	vehicle.prev_t = d.prev_t
	vehicle.lane = d.lane
	vehicle.ahead = d.ahead
	vehicle.waited = d.waited
	vehicle.replanned = d.replanned
	vehicle.state = d.state
	vehicle.box = d.box
	vehicle.loaded = d.loaded
	vehicle.target = d.target
	vehicle.home = d.home
	vehicle.timer = d.timer
	vehicle.block = d.block
	vehicle.gate_in = d.gate_in
	return vehicle
