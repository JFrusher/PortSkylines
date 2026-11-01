class_name Vehicle
extends RefCounted
## A lorry or terminal tractor on roads and areas, moved by AreaFlow along
## `path`, a cell at a time once LaneTraffic gives it the cell. `state` says
## what it is doing (see Inspect.STATES).

var id: int
var kind: String
var path: Array[Vector2i]
## Distance travelled along `path`, in cells.
var t := 0.0
## `t` at the start of this tick, for drawing between ticks.
var prev_t := 0.0
## Ticks spent waiting for the next cell.
var waited := 0
var state := ""
## The box it carries or has come for (0 for none), and whether it is on board.
var box := 0
var loaded := false
## The cell it is driving to, and where a tractor fetching an export brings it back to.
var target := Grid.NONE
var home := Grid.NONE
## Minutes left at a gate booth.
var timer := 0.0
## Calendar minute a lorry came in through a gate, or -1 before it has.
var gate_in := -1.0
## Calendar minute of the hour a lorry is booked in at its gate, or -1 when
## the gate takes no bookings; it is checked in no sooner.
var booked := -1.0
## The area it is going to or working at, and the handover slot it holds
## there (-1 for none).
var area := 0
var slot := -1
## The straddle block a straddle carrier belongs to, or 0 for anything
## else: a carrier is a tractor that never counts against the pool.
var straddle := 0


func _init(vehicle_id: int, vehicle_kind: String, route: Array[Vector2i]) -> void:
	id = vehicle_id
	kind = vehicle_kind
	path = route


## Position in grid cells, `alpha` of the way from the last tick to this one.
func position(alpha: float) -> Vector2:
	var at := lerpf(prev_t, t, alpha)
	var i := mini(int(at), path.size() - 1)
	var j := mini(i + 1, path.size() - 1)
	return Vector2(path[i]).lerp(Vector2(path[j]), clampf(at - i, 0.0, 1.0))


func at_end() -> bool:
	return t >= path.size() - 1


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "path": path.duplicate(), "t": t, "prev_t": prev_t, "waited": waited,
		"state": state, "box": box, "loaded": loaded, "target": target, "home": home, "timer": timer,
		"gate_in": gate_in, "booked": booked, "area": area, "slot": slot, "straddle": straddle,
	}


static func from_dict(d: Dictionary) -> Vehicle:
	var route: Array[Vector2i] = []
	route.assign(d.path)
	var vehicle := Vehicle.new(d.id, d.kind, route)
	vehicle.t = d.t
	vehicle.prev_t = d.prev_t
	vehicle.waited = d.waited
	vehicle.state = d.state
	vehicle.box = d.box
	vehicle.loaded = d.loaded
	vehicle.target = d.target
	vehicle.home = d.home
	vehicle.timer = d.timer
	vehicle.gate_in = d.gate_in
	vehicle.straddle = d.straddle
	vehicle.booked = d.booked
	vehicle.area = d.area
	vehicle.slot = d.slot
	return vehicle
