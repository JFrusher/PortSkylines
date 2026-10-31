class_name LaneTraffic
extends RefCounted
## Who holds each cell of the lane graph, and vehicles moving along their
## routes. A 4 m cell is one lane, so a vehicle enters a cell only once it
## holds it, and no two vehicles are ever in one cell. Junction cells are
## shared by crossing traffic, so a vehicle books every junction cell ahead
## and the first cell past them before it enters: it never stops in a junction.

var _lanes: LaneGraph
## Signals and signs, asked before a vehicle goes into a junction's box.
var junctions: Junctions
var _holders := {}  # cell -> vehicle id
var _held := {}  # vehicle id -> cells it holds
## Seconds a vehicle passing each cell waits in it, smoothed over epochs; a
## cell with none is free-flowing. Saved, as routes will weigh by it.
var _delays := {}  # cell -> seconds
## This epoch so far: ticks vehicles waited in each cell, and vehicles that entered it.
var _stuck := {}  # cell -> ticks
var _entered := {}  # cell -> vehicles


func _init(lanes: LaneGraph, junction_rules: Junctions) -> void:
	_lanes = lanes
	junctions = junction_rules


## Puts `vehicle` at the start of its route, if that cell is free.
func place(vehicle: Vehicle) -> bool:
	return _take(vehicle.id, [vehicle.path[0]])


## Moves `vehicle` up to `speed` cells a second for one tick, entering each
## cell on the way in turn and stopping short of the first it can't take.
## True once it is at the end of its route.
func advance(vehicle: Vehicle, speed: float) -> bool:
	vehicle.prev_t = vehicle.t
	if vehicle.at_end():
		return true
	var target := minf(vehicle.t + speed * SimClock.TICK_SECONDS, vehicle.path.size() - 1)
	var start := int(vehicle.t)
	while int(target) > int(vehicle.t):
		var i := int(vehicle.t)
		if not _enter(vehicle, i + 1):
			vehicle.t = maxf(vehicle.t, i + 0.95)
			# Waiting counts only ticks it entered no cell at all.
			vehicle.waited = vehicle.waited + 1 if i == start else 0
			if i == start:
				_stuck[vehicle.path[i]] = _stuck.get(vehicle.path[i], 0) + 1
			return false
		_entered[vehicle.path[i + 1]] = _entered.get(vehicle.path[i + 1], 0) + 1
		vehicle.t = i + 1
	vehicle.waited = 0
	vehicle.t = target
	return vehicle.at_end()


## Folds this epoch's waiting into each cell's delay: the seconds waited in
## it per vehicle that entered it (all of them when none got in), mixed in at
## `smoothing` (0 to 1); a cell nobody waited in eases back towards none.
func settle(smoothing: float) -> void:
	for cell: Vector2i in _delays.keys() + _stuck.keys():
		var seconds: float = _stuck.get(cell, 0) * SimClock.TICK_SECONDS / maxi(_entered.get(cell, 0), 1)
		var mixed: float = lerpf(_delays.get(cell, 0.0), seconds, smoothing)
		if mixed < 0.01:
			_delays.erase(cell)
		else:
			_delays[cell] = mixed
	_stuck.clear()
	_entered.clear()


## Seconds a vehicle passing `cell` waits in it, smoothed; 0 when it flows.
func delay(cell: Vector2i) -> float:
	return _delays.get(cell, 0.0)


## Every cell with a delay -> its seconds.
func delays() -> Dictionary:
	return _delays


## Lets go of every cell `vehicle` holds.
func leave(vehicle: Vehicle) -> void:
	release(vehicle.id)


## Books all of `cells` for `id` if each is free or already theirs, else
## none: a train takes a level crossing this way.
func book(id: int, cells: Array[Vector2i]) -> bool:
	return _take(id, cells)


## Books exactly `cells` for `id`, letting go of the rest it holds, if each
## is free or already theirs; else changes nothing and returns false. A
## moving train keeps the level crossings under and ahead of it this way.
func rebook(id: int, cells: Array[Vector2i]) -> bool:
	if not _take(id, cells):
		return false
	var keep := {}
	for cell in cells:
		keep[cell] = true
	var held: Array = _held[id]
	for cell: Vector2i in held.duplicate():
		if cell not in keep:
			_holders.erase(cell)
			held.erase(cell)
	return true


## Lets go of every cell `id` holds.
func release(id: int) -> void:
	for cell: Vector2i in _held.get(id, []):
		_holders.erase(cell)
	_held.erase(id)


func to_dict() -> Dictionary:
	return {"held": _held.duplicate(true), "delays": _delays.duplicate(), "stuck": _stuck.duplicate(), "entered": _entered.duplicate(), "junctions": junctions.to_dict()}


static func from_dict(d: Dictionary, lanes: LaneGraph, rules: Dictionary) -> LaneTraffic:
	var traffic := LaneTraffic.new(lanes, Junctions.from_dict(d.junctions, rules))
	for id: int in d.held:
		traffic._held[id] = d.held[id].duplicate()
		for cell: Vector2i in d.held[id]:
			traffic._holders[cell] = id
	traffic._delays = d.delays.duplicate()
	traffic._stuck = d.stuck.duplicate()
	traffic._entered = d.entered.duplicate()
	return traffic


## The cells vehicle `id` holds.
func held_by(id: int) -> Array:
	return _held.get(id, [])


func holder(cell: Vector2i) -> int:
	return _holders.get(cell, 0)


## Takes path[i] for `vehicle`, and if it is a junction cell, every junction
## cell after it and the first cell past them too; then lets go of every other
## cell, including ones its route passes again later, so a route that comes
## back the same way never holds a cell it has left.
func _enter(vehicle: Vehicle, i: int) -> bool:
	# Most vehicles in a queue find the next cell taken: say so before building the list.
	var cell := vehicle.path[i]
	if _holders.get(cell, vehicle.id) != vehicle.id:
		return false
	# Going from a junction's approach into its box: the signals and signs there say whether it may.
	var arm := _lanes.arm_at(vehicle.path[i - 1])
	if not arm.is_empty() and _lanes.box_of(cell) == arm[0] and not junctions.may_enter(_lanes, self, arm[0], arm[1], vehicle):
		return false
	# Most cells are plain lane: hold just this one, as the general case below would.
	if not _lanes.is_junction(cell):
		var mine: Array = _held[vehicle.id]
		for other: Vector2i in mine:
			if other != cell:
				_holders.erase(other)
		mine.clear()
		mine.append(cell)
		_holders[cell] = vehicle.id
		return true
	var want: Array[Vector2i] = [cell]
	var j := i
	while _lanes.is_junction(vehicle.path[j]) and j + 1 < vehicle.path.size():
		j += 1
		want.append(vehicle.path[j])
	if not _take(vehicle.id, want):
		return false
	var keep := {}
	for wanted in want:
		keep[wanted] = true
	var held: Array = _held[vehicle.id]
	for other: Vector2i in held.duplicate():
		if other not in keep:
			_holders.erase(other)
			held.erase(other)
	return true


## Takes all of `cells` for `id` if each is free or already theirs, else none.
func _take(id: int, cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if _holders.get(cell, id) != id:
			return false
	var held: Array = _held.get(id, [])
	for cell in cells:
		if cell not in held:
			held.append(cell)
		_holders[cell] = id
	_held[id] = held
	return true
