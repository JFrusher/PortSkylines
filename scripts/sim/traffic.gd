class_name Traffic
extends RefCounted
## Vehicles moving continuously on a LaneNetwork, as Cities: Skylines' do:
## each keeps the standstill gap plus a second of travel behind the vehicle
## ahead on its route, drives at the lower of its own top speed and its
## lane's limit (and a curve's), speeds up and brakes at the data's rates,
## and takes a junction's connection only once it has booked it, which it
## can while no connection crossing it is booked.

var network: LaneNetwork
var _rules: Dictionary
## Car id -> {"route": piece ids, "i": which of them it is on, "s": its
## front's distance along that piece (cells), "v": its speed (cells a
## second), "top": its own top speed (cells a second), "length": cells,
## "booked": the connection it has booked, or 0}.
var cars := {}
var _on := {}  # piece -> ids of the cars whose fronts are on it
var _booked := {}  # connection piece -> ids of the cars that have booked it
var _limits := {}  # piece -> cells a second, its road's and its curve's
## How many pieces ahead a car looks for a car or a stop.
const LOOK_AHEAD := 4


func _init(lanes: LaneNetwork, rules: Dictionary) -> void:
	network = lanes
	_rules = rules.traffic
	for id: int in network.pieces:
		_limits[id] = minf(network.pieces[id].kmh / 3.6 / Grid.CELL, _curve_limit(network.pieces[id].points))


## Puts car `id` at the start of `route` (piece ids), its whole length on
## the first piece, with a top speed of `metres_per_minute` and `metres`
## long; false when another car is too close to that start to fit.
func place(id: int, route: Array[int], metres_per_minute: float, metres: float) -> bool:
	var length := metres / Grid.CELL
	for other: int in _on.get(route[0], []):
		if cars[other].s - cars[other].length < length + _gap():
			return false
	cars[id] = {"route": route, "i": 0, "s": length, "v": 0.0, "top": metres_per_minute / 60.0 / Grid.CELL, "length": length, "booked": 0}
	_on.get_or_add(route[0], []).append(id)
	return true


## Takes car `id` off the network.
func remove(id: int) -> void:
	var car: Dictionary = cars[id]
	_on[car.route[car.i]].erase(id)
	if car.booked:
		_booked[car.booked].erase(id)
	cars.erase(id)


## Moves every car on for `seconds`, in order of id.
func tick(seconds: float) -> void:
	var ids := cars.keys()
	ids.sort()
	for id: int in ids:
		_move(id, seconds)


func _move(id: int, seconds: float) -> void:
	var car: Dictionary = cars[id]
	var piece: int = car.route[car.i]
	var left: float = network.pieces[piece].length - car.s
	var ahead := _ahead(id)
	var room: float = ahead.distance - (0.0 if ahead.end else _gap())
	# What's left of a closed gap is rounding, not room.
	room = room if room > 0.000001 else 0.0
	# Fast enough to keep a second's travel back, slow enough to stop in the room.
	var allowed := minf(room / _rules.headway_seconds, sqrt(2.0 * _decel() * room))
	var limit := minf(car.top, _limits[piece])
	if car.i + 1 < car.route.size():
		limit = minf(limit, sqrt(pow(minf(car.top, _limits[car.route[car.i + 1]]), 2) + 2.0 * _decel() * left))
	var v := minf(minf(car.v + _accel() * seconds, limit), allowed)
	car.v = v
	_advance(id, minf(v * seconds, room))


## How far car `id` may go before it reaches what's ahead along its route:
## {"distance": cells to the rear of the nearest car ahead, a connection it
## can't book yet, or its route's end, "end": true when that is its route's
## end, which it drives right up to}.
func _ahead(id: int) -> Dictionary:
	var car: Dictionary = cars[id]
	var distance: float = -car.s
	for k in range(car.i, mini(car.i + LOOK_AHEAD, car.route.size())):
		var piece: int = car.route[k]
		if k > car.i and network.pieces[piece].node != 0 and car.booked != piece and not _book(id, piece):
			return {"distance": distance, "end": false}
		var nearest := INF
		for other: int in _on.get(piece, []):
			var rear: float = cars[other].s - cars[other].length
			if other != id and (k > car.i or cars[other].s > car.s) and rear < nearest:
				nearest = rear
		if nearest < INF:
			return {"distance": distance + nearest, "end": false}
		distance += network.pieces[piece].length
		if k == car.route.size() - 1:
			return {"distance": distance, "end": true}
	return {"distance": distance, "end": false}


## Books connection `piece` for car `id` once it is near enough to need it
## and no connection crossing it is booked by another car; true if booked.
func _book(id: int, piece: int) -> bool:
	var car: Dictionary = cars[id]
	if car.booked != 0:
		return false
	for other: int in network.conflicts(piece):
		if _booked.get(other, []).any(func(c: int) -> bool: return c != id):
			return false
	car.booked = piece
	_booked.get_or_add(piece, []).append(id)
	return true


## Moves car `id` `distance` cells on along its route, onto the next pieces
## as it passes their starts; it lets its booked connection go once its
## whole length is clear of it.
func _advance(id: int, distance: float) -> void:
	var car: Dictionary = cars[id]
	car.s += distance
	while car.s > network.pieces[car.route[car.i]].length and car.i + 1 < car.route.size():
		_on[car.route[car.i]].erase(id)
		car.s -= network.pieces[car.route[car.i]].length
		car.i += 1
		_on.get_or_add(car.route[car.i], []).append(id)
	car.s = minf(car.s, network.pieces[car.route[car.i]].length)
	if car.booked != 0 and car.route[car.i] != car.booked and car.route.find(car.booked) < car.i and car.s >= car.length:
		_booked[car.booked].erase(id)
		car.booked = 0


## The fastest a vehicle may take `points`, by their tightest turn.
func _curve_limit(points: PackedVector2Array) -> float:
	var tightest := INF
	for i in range(1, points.size() - 1):
		var a := points[i - 1]
		var b := points[i]
		var c := points[i + 1]
		var cross := absf((b - a).cross(c - a))
		if cross > 0.000001:
			tightest = minf(tightest, a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * cross))
	return sqrt(_rules.lateral_accel / Grid.CELL * tightest) if tightest < INF else INF


func _gap() -> float:
	return _rules.standstill_gap_m / Grid.CELL


func _accel() -> float:
	return _rules.accel / Grid.CELL


func _decel() -> float:
	return _rules.decel / Grid.CELL
