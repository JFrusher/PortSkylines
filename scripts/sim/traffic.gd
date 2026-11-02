class_name Traffic
extends RefCounted
## Vehicles moving continuously on a LaneNetwork, as Cities: Skylines' do:
## each keeps the standstill gap plus a second of travel behind the vehicle
## ahead on its route, drives at the lower of its own top speed and its
## lane's limit (and a curve's), speeds up and brakes at the data's rates,
## and takes a junction's connection only once it has booked it, which it
## can while no connection crossing it is booked.

var network: LaneNetwork
## Signals and priority signs, asked before a car books a connection.
var junctions: Junctions
var _rules: Dictionary
## Car id -> {"route": piece ids, "i": which of them it is on, "s": its
## front's distance along that piece (cells), "v": its speed (cells a
## second), "top": its own top speed (cells a second), "length": cells,
## "booked": the connection it has booked, or 0, "waited": seconds it has
## stood still}.
var cars := {}
var _on := {}  # piece -> ids of the cars whose fronts are on it
var _booked := {}  # connection piece -> ids of the cars that have booked it
var _limits := {}  # piece -> cells a second, its road's and its curve's
## Level crossings: cells rail track crosses -> the train id booking them,
## or 0; and where each piece runs into one: piece -> [[cell, distance]].
var _crossings := {}
var _crossing_on := {}
## Seconds a car passing each piece waits on it, smoothed over epochs, for
## routes to weigh (piece -> seconds); and this epoch so far: seconds cars
## stood on each piece, and cars that came onto it.
var _delays := {}
var _stuck := {}
var _entered := {}
## The least of a junction's approach, in cells, where a car giving way
## looks for traffic; a moving car is on it from give_way_seconds out.
const APPROACH := 3.0
## How many pieces ahead a car looks for a car or a stop.
const LOOK_AHEAD := 4


func _init(lanes: LaneNetwork, rules: Dictionary, junction_rules: Junctions) -> void:
	network = lanes
	junctions = junction_rules
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
	cars[id] = {"route": route, "i": 0, "s": length, "v": 0.0, "top": metres_per_minute / 60.0 / Grid.CELL, "length": length, "booked": 0, "waited": 0.0}
	_on.get_or_add(route[0], []).append(id)
	_entered[route[0]] = _entered.get(route[0], 0) + 1
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
	car.waited = car.waited + seconds if v == 0.0 else 0.0
	if v == 0.0:
		_stuck[piece] = _stuck.get(piece, 0.0) + seconds
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
		# A connection is booked only once the car is near enough to need it:
		# until then its stop line is just a far-off end of the room ahead.
		if k > car.i and network.pieces[piece].node != 0 and car.booked != piece and (distance > _booking_distance(car) or not _book(id, piece)):
			return {"distance": distance, "end": false}
		for crossing: Array in _crossing_on.get(piece, []):
			if _crossings[crossing[0]] != 0 and (k > car.i or crossing[1] > car.s):
				return {"distance": distance + crossing[1], "end": false}
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


## How near a stop line `car` must be to book the connection beyond it:
## its braking distance, the standstill gap and a cell more.
func _booking_distance(car: Dictionary) -> float:
	return car.v * car.v / (2.0 * _decel()) + _gap() + 1.0


## Books connection `piece` for car `id` once it is near enough to need it
## and no connection crossing it is booked by another car; true if booked.
func _book(id: int, piece: int) -> bool:
	var car: Dictionary = cars[id]
	if car.booked != 0:
		return false
	var arm := network.arm_of(car.route[car.i])
	if not arm.is_empty() and not junctions.may_enter(network, self, arm[0], arm[1], id, car.waited):
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
		_entered[car.route[car.i]] = _entered.get(car.route[car.i], 0) + 1
	car.s = minf(car.s, network.pieces[car.route[car.i]].length)
	if car.booked != 0 and car.route[car.i] != car.booked and car.route.find(car.booked) < car.i and car.s >= car.length:
		_booked[car.booked].erase(id)
		car.booked = 0


## Folds this epoch's waiting into each piece's delay: seconds stood on it
## per car that came onto it (all of them when none did), mixed in at
## `smoothing` (0 to 1); a piece nobody waited on eases back towards none.
func settle(smoothing: float) -> void:
	for piece: int in _delays.keys() + _stuck.keys():
		var seconds: float = _stuck.get(piece, 0.0) / maxi(_entered.get(piece, 0), 1)
		var mixed: float = lerpf(_delays.get(piece, 0.0), seconds, smoothing)
		if mixed < 0.01:
			_delays.erase(piece)
		else:
			_delays[piece] = mixed
	_stuck.clear()
	_entered.clear()


## Every piece with a delay -> its seconds.
func delays() -> Dictionary:
	return _delays


## Whether a car other than `except` has booked, or is on, a connection
## across junction `point`.
func box_busy(point: Vector2i, except: int) -> bool:
	var node := network.node_at(point)
	for id: int in cars:
		var car: Dictionary = cars[id]
		if id != except and (car.booked != 0 and network.pieces[car.booked].node == node or network.pieces[car.route[car.i]].node == node):
			return true
	return false


## Whether a car on arm `arm` will reach junction `point` within
## give_way_seconds, or stands within APPROACH cells of it: a car giving way
## waits for a gap that long, as in Cities: Skylines.
func approach_busy(point: Vector2i, arm: Vector2i) -> bool:
	for piece: int in network.approach(point, arm):
		for id: int in _on.get(piece, []):
			if network.pieces[piece].length - cars[id].s <= maxf(APPROACH, cars[id].v * _rules.give_way_seconds):
				return true
	return false


## The cells where rail track crosses lanes: level crossings, each free.
func set_crossings(cells: Array[Vector2i]) -> void:
	_crossings.clear()
	_crossing_on.clear()
	for cell in cells:
		_crossings[cell] = 0
	for piece: int in network.pieces:
		var points: PackedVector2Array = network.pieces[piece].points
		var along := 0.0
		var seen := {}
		for i in points.size():
			if i > 0:
				along += points[i - 1].distance_to(points[i])
			var cell := Vector2i(points[i].floor())
			if cell in _crossings and cell not in seen:
				seen[cell] = true
				# A cell runs half a cell either side of a lane's point in it.
				_crossing_on.get_or_add(piece, []).append([cell, maxf(0.0, along - 0.5)])


## Books exactly crossing `cells` for train `id` (a negative id), letting go
## of the rest it held, if no car is on any of them; else changes nothing.
func rebook(id: int, cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if _crossings.get(cell, 0) not in [0, id] or _car_on(cell):
			return false
	release(id)
	for cell in cells:
		_crossings[cell] = id
	return true


## Lets go of every crossing train `id` books.
func release(id: int) -> void:
	for cell: Vector2i in _crossings:
		if _crossings[cell] == id:
			_crossings[cell] = 0


## Whether any car's length lies over crossing `cell`.
func _car_on(cell: Vector2i) -> bool:
	for id: int in cars:
		var car: Dictionary = cars[id]
		for crossing: Array in _crossing_on.get(car.route[car.i], []):
			if crossing[0] == cell and crossing[1] <= car.s + 0.5 and crossing[1] + 1.5 >= car.s - car.length:
				return true
	return false


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
