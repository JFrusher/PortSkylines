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
## "booked": the connections it has booked and isn't yet clear of (two when
## junctions are closer than it is long), "waited": seconds it has
## stood still}.
var cars := {}
## The cars whose vehicles may need attention after a tick: on their route's
## last piece, waited due_after seconds or more, or placed or rerouted since
## the tick. Any other is on its way, with nothing for its vehicle to do.
var due := {}
var due_after := 0.0
var _on := {}  # piece -> ids of the cars whose fronts are on it, rearmost first
var _booked := {}  # connection piece -> ids of the cars that have booked it
var _limits := {}  # piece -> cells a second, its road's and its curve's
var _before := {}  # piece -> the pieces leading onto it
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
		for after: int in network.pieces[id].next:
			_before.get_or_add(after, []).append(id)


## Puts car `id` at the start of `route` (piece ids), its whole length on
## the first piece, with a top speed of `metres_per_minute` and `metres`
## long; false when another car is too close to that start to fit.
func place(id: int, route: Array[int], metres_per_minute: float, metres: float) -> bool:
	var length := metres / Grid.CELL
	for other: int in _on.get(route[0], []):
		if cars[other].s - cars[other].length < length + _gap():
			return false
	cars[id] = {"route": route, "i": 0, "s": length, "v": 0.0, "top": metres_per_minute / 60.0 / Grid.CELL, "length": length, "booked": [], "waited": 0.0}
	due[id] = true
	_put(route[0], id)
	_entered[route[0]] = _entered.get(route[0], 0) + 1
	return true


## Whether a car `length` cells long fits with its front `s` cells along
## `piece`: no car's length, on it or the pieces either side, lies within
## the standstill gap of it.
func fits(piece: int, s: float, length: float) -> bool:
	# Cars keep their order on a piece and never overlap, so only the nearest
	# ones can be in the way: on `piece`, those from the front back until one
	# is clear behind; on the pieces after it, the rearmost; before it, the frontmost.
	var on: Array = _on.get(piece, [])
	for j in range(on.size() - 1, -1, -1):
		var car: Dictionary = cars[on[j]]
		if car.s <= s - length - _gap():
			break
		if car.s - car.length < s + _gap():
			return false
	var near := []  # [car id, where its piece starts in `piece`'s distances]
	for after: int in network.pieces[piece].next:
		if not _on.get(after, []).is_empty():
			near.append([_on[after][0], network.pieces[piece].length])
	for before: int in _before.get(piece, []):
		if not _on.get(before, []).is_empty():
			near.append([_on[before][-1], -network.pieces[before].length])
	for found: Array in near:
		var car: Dictionary = cars[found[0]]
		var front: float = found[1] + car.s
		if front > s - length - _gap() and front - car.length < s + _gap():
			return false
	return true


## Puts car `id` on `route` (piece ids) with its front `s` cells along the
## first piece, `top` cells a second at most and `length` cells long.
func place_at(id: int, route: Array[int], s: float, top: float, length: float) -> void:
	cars[id] = {"route": route, "i": 0, "s": s, "v": 0.0, "top": top, "length": length, "booked": [], "waited": 0.0}
	due[id] = true
	_put(route[0], id)
	_entered[route[0]] = _entered.get(route[0], 0) + 1


## Gives car `id` a new route from the piece it is on (`route`'s first),
## keeping where it is on it and the pieces it has driven, which its rear
## may still be on; it lets go of the connections it booked ahead that the
## new route doesn't take.
func reroute(id: int, route: Array[int]) -> void:
	var car: Dictionary = cars[id]
	due[id] = true
	assert(route[0] == car.route[car.i], "a new route starts where the car is")
	for piece: int in car.booked.duplicate():
		if car.route.find(piece) >= car.i and piece not in route:
			_booked[piece].erase(id)
			car.booked.erase(piece)
	var first: int = car.i
	var back: float = car.s
	while first > 0 and back < car.length:
		first -= 1
		back += network.pieces[car.route[first]].length
	for piece: int in car.booked.duplicate():
		if car.route.find(piece) < first:
			_booked[piece].erase(id)
			car.booked.erase(piece)
	car.route = car.route.slice(first, car.i) + route
	car.behind = []
	car.i -= first


## Whether car `id` is at the end of its route.
func arrived(id: int) -> bool:
	var car: Dictionary = cars[id]
	return car.i == car.route.size() - 1 and car.s >= network.pieces[car.route[-1]].length - 0.001


## [where car `id`'s front is, the way it heads], in grid units.
func pose(id: int) -> Array[Vector2]:
	var car: Dictionary = cars[id]
	return network.point_along(car.route[car.i], car.s)


## Everything the traffic holds, for a save: the cars, who is on and has
## booked each piece, the crossings' bookings and the waiting so far.
func to_dict() -> Dictionary:
	return {"cars": cars.duplicate(true), "on": _on.duplicate(true), "booked": _booked.duplicate(true), "crossings": _crossings.duplicate(), "delays": _delays.duplicate(), "stuck": _stuck.duplicate(), "entered": _entered.duplicate()}


## Puts back what to_dict saved, on the same network.
func restore(d: Dictionary) -> void:
	cars = d.cars.duplicate(true)
	for id: int in cars:
		due[id] = true
	_on = d.on.duplicate(true)
	_booked = d.booked.duplicate(true)
	for cell: Vector2i in d.crossings:
		_crossings[cell] = d.crossings[cell]
	_delays = d.delays.duplicate()
	_stuck = d.stuck.duplicate()
	_entered = d.entered.duplicate()


## Takes car `id` off the network.
func remove(id: int) -> void:
	var car: Dictionary = cars[id]
	_on[car.route[car.i]].erase(id)
	for piece: int in car.booked:
		_booked[piece].erase(id)
	cars.erase(id)


## Moves every car on for `seconds`, in order of id.
func tick(seconds: float) -> void:
	due.clear()
	var ids := cars.keys()
	ids.sort()
	for id: int in ids:
		_move(id, seconds)


func _move(id: int, seconds: float) -> void:
	var car: Dictionary = cars[id]
	var piece: int = car.route[car.i]
	# At its route's end it stands, as the look ahead would find: nothing is in front of it.
	if car.i == car.route.size() - 1 and car.s >= network.pieces[piece].length:
		car.v = 0.0
		car.waited += seconds
		_stuck[piece] = _stuck.get(piece, 0.0) + seconds
		due[id] = true
		return
	# Stopped behind a car that hasn't moved since, it stays stopped: the look
	# ahead would find that car just as near again.
	var behind: Array = car.get("behind", [])
	if not behind.is_empty() and behind[0] in cars and cars[behind[0]].route[cars[behind[0]].i] == behind[1] and cars[behind[0]].s == behind[2]:
		car.waited += seconds
		_stuck[piece] = _stuck.get(piece, 0.0) + seconds
		if car.waited >= due_after:
			due[id] = true
		return
	car.behind = []
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
	if v == 0.0 and room == 0.0 and ahead.get("car", 0) != 0:
		var other: Dictionary = cars[ahead.car]
		car.behind = [ahead.car, other.route[other.i], other.s]
	_advance(id, minf(v * seconds, room))
	if car.waited >= due_after or car.i == car.route.size() - 1:
		due[id] = true


## How far car `id` may go before it reaches what's ahead along its route:
## {"distance": cells to the rear of the nearest car ahead, a connection it
## can't book yet, or its route's end, "end": true when that is its route's
## end, which it drives right up to}. Where it would wait for a car ahead
## over a level crossing, it waits short of the crossing instead.
func _ahead(id: int) -> Dictionary:
	var car: Dictionary = cars[id]
	var found := _obstacle(id)
	var stand: float = found.distance - (0.0 if found.end else _gap())
	var crossing: float = found.crossing
	if not found.end and crossing < found.distance and stand - car.length < crossing + 1.0:
		return {"distance": crossing, "end": false}
	return found


## _ahead's obstacle, and "crossing": cells to the first free level crossing
## on the way to it (INF with none).
func _obstacle(id: int) -> Dictionary:
	var car: Dictionary = cars[id]
	var distance: float = -car.s
	var crossing := INF
	for k in range(car.i, mini(car.i + LOOK_AHEAD, car.route.size())):
		var piece: int = car.route[k]
		# A connection is booked only once the car is near enough to need it:
		# until then its stop line is just a far-off end of the room ahead.
		if k > car.i and network.pieces[piece].node != 0 and piece not in car.booked and (distance > _booking_distance(car) or not _book(id, piece)):
			return {"distance": distance, "end": false, "crossing": crossing}
		# The nearer of the car ahead and a crossing a train has booked stops it.
		# Cars keep their order along a piece, so the one ahead is the next.
		var nearest := INF
		var blocker := 0
		var on: Array = _on.get(piece, [])
		if k > car.i:
			if not on.is_empty():
				nearest = cars[on[0]].s - cars[on[0]].length
				blocker = on[0]
		else:
			for j in range(on.find(id) + 1, on.size()):
				if cars[on[j]].s > car.s:
					nearest = cars[on[j]].s - cars[on[j]].length
					blocker = on[j]
					break
		for at: Array in _crossing_on.get(piece, []):
			if (k > car.i or at[1] > car.s) and at[1] < nearest:
				if _crossings[at[0]] != 0:
					nearest = at[1]
					blocker = 0
				else:
					crossing = minf(crossing, distance + at[1])
		if nearest < INF:
			return {"distance": distance + nearest, "end": false, "crossing": crossing, "car": blocker}
		distance += network.pieces[piece].length
		if k == car.route.size() - 1:
			return {"distance": distance, "end": true, "crossing": crossing}
	return {"distance": distance, "end": false, "crossing": crossing}


## How near a stop line `car` must be to book the connection beyond it:
## its braking distance, the standstill gap and a cell more.
func _booking_distance(car: Dictionary) -> float:
	return car.v * car.v / (2.0 * _decel()) + _gap() + 1.0


## Books connection `piece` for car `id` once it is near enough to need it,
## its junction lets it in from the arm before it, no connection crossing it
## is booked by another car, and past it there is room to stand clear of
## the box, so no car ever stops in a junction (Cities: Skylines' "don't
## block the box"); true if booked.
func _book(id: int, piece: int) -> bool:
	var car: Dictionary = cars[id]
	if _room_past(car, car.route.find(piece), car.length + _gap()) < car.length + _gap():
		return false
	var arm := network.arm_of(car.route[car.route.find(piece) - 1])
	if not arm.is_empty() and not junctions.may_enter(network, self, arm[0], arm[1], id, car.waited):
		return false
	for other: int in network.conflicts(piece):
		if _booked.get(other, []).any(func(c: int) -> bool: return c != id):
			return false
	car.booked.append(piece)
	_booked.get_or_add(piece, []).append(id)
	return true


## How far past the end of `car`'s route piece `at` the nearest car ahead's
## rear is, in cells, looking as many pieces on as it takes to see `need`
## cells; INF when its route ends first, as it may stand there.
func _room_past(car: Dictionary, at: int, need: float) -> float:
	var distance := 0.0
	for k in range(at + 1, car.route.size()):
		var on: Array = _on.get(car.route[k], [])
		if not on.is_empty():
			return distance + cars[on[0]].s - cars[on[0]].length
		distance += network.pieces[car.route[k]].length
		if distance >= need:
			return distance
	return INF


## Puts car `id` on `piece`'s list, keeping it rearmost first.
func _put(piece: int, id: int) -> void:
	var on: Array = _on.get_or_add(piece, [])
	var at := 0
	while at < on.size() and cars[on[at]].s < cars[id].s:
		at += 1
	on.insert(at, id)


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
		_put(car.route[car.i], id)
		_entered[car.route[car.i]] = _entered.get(car.route[car.i], 0) + 1
	car.s = minf(car.s, network.pieces[car.route[car.i]].length)
	for piece: int in car.booked.duplicate() if not car.booked.is_empty() else []:
		if _clear_of(car, piece):
			_booked[piece].erase(id)
			car.booked.erase(piece)


## Whether `car`'s rear is past the end of `piece`, a piece of its route it
## has passed.
func _clear_of(car: Dictionary, piece: int) -> bool:
	var at: int = car.route.find(piece)
	if at < 0 or at >= car.i:
		return false
	var past: float = car.s
	for k in range(at + 1, car.i):
		past += network.pieces[car.route[k]].length
	return past >= car.length


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
		if id != except and (car.booked.any(func(piece: int) -> bool: return network.pieces[piece].node == node) or network.pieces[car.route[car.i]].node == node):
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
			if crossing[0] == cell and crossing[1] < car.s and crossing[1] + 1.0 > car.s - car.length:
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
