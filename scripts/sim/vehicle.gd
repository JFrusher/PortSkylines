class_name Vehicle
extends RefCounted
## A lorry or terminal tractor on roads and areas, sent about by AreaFlow
## and driven by Drive, whose car on the lane network it is. `state` says
## what it is doing (see Inspect.STATES).

var id: int
var kind: String
## The spot it started from or last arrived at, alone; Drive puts its car
## there when the lane network is built.
var path: Array[Vector3i]
var state := ""
## The box it carries or has come for (0 for none), and whether it is on board.
var box := 0
var loaded := false
## The cell it is driving to, and where a tractor fetching an export brings it back to.
var target := Areas.NO_SPOT
var home := Areas.NO_SPOT
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
## Distance travelled along `path`, in cells.
var t := 0.0
## `t` at the start of this tick, for drawing between ticks.
var prev_t := 0.0
## Ticks spent waiting for the next cell.
var waited := 0


func _init(vehicle_id: int, vehicle_kind: String, route: Array[Vector3i]) -> void:
	id = vehicle_id
	kind = vehicle_kind
	path = route


## Position in grid cells, `alpha` of the way from the last tick to this one.
## Through a cell where the path turns it follows the quarter circle between
## the middles of that cell's edges, so a lorry waiting in a corner never
## points diagonally across it.
func position(alpha: float) -> Vector2:
	var at := lerpf(prev_t, t, alpha)
	var i := clampi(int(at), 0, path.size() - 1)
	var f := at - i
	if path.size() < 2:
		return Vector2(path[0].x, path[0].y)
	if i >= path.size() - 1:
		return Vector2(path[-1].x, path[-1].y)
	var corner := i + 1 if f >= 0.5 else i
	if corner > 0 and corner < path.size() - 1:
		var d_in := Vector2(path[corner].x - path[corner - 1].x, path[corner].y - path[corner - 1].y)
		var d_out := Vector2(path[corner + 1].x - path[corner].x, path[corner + 1].y - path[corner].y)
		if d_in != d_out and d_in != -d_out:
			var u := (f - 0.5 if corner == i + 1 else f + 0.5) * PI / 2
			var centre := Vector2(path[corner].x, path[corner].y) + (d_out - d_in) * 0.5
			return centre + 0.5 * (d_in * sin(u) - d_out * cos(u))
	return Vector2(path[i].x, path[i].y).lerp(Vector2(path[i + 1].x, path[i + 1].y), clampf(f, 0.0, 1.0))


func at_end() -> bool:
	return t >= path.size() - 1


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "path": path.duplicate(),
		"state": state, "box": box, "loaded": loaded, "target": target, "home": home, "timer": timer,
		"gate_in": gate_in, "booked": booked, "area": area, "slot": slot, "straddle": straddle,
		"t": t, "prev_t": prev_t, "waited": waited,
	}


static func from_dict(d: Dictionary) -> Vehicle:
	var route: Array[Vector3i] = []
	route.assign(d.path)
	var vehicle := Vehicle.new(d.id, d.kind, route)
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