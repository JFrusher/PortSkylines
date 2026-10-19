class_name Machines
extends RefCounted
## Yard machines, each belonging to one area, working one job at a time. A
## job moves a box between two bays of the area in fixed phases, each with a
## time from the data in game seconds: travel to the box, lift it, travel to
## its place, set it down. The sim owns the times; the view only animates the
## phase in progress.

## Game seconds in one tick: machines work on the calendar clock, like cranes.
const SECONDS_PER_TICK := SimClock.CALENDAR_MINUTES_PER_TICK * 60.0

## Machine id -> {"area", "gear", "bay": where it stands, "job": {} or
## {"phases": [{"kind", "seconds", "bay"}], "left": seconds left of the first
## phase, "carrying": whether a box is on its spreader, for drawing}}.
var list := {}
var _gear: Dictionary
var _next_id := 1


func _init(yard_gear: Dictionary) -> void:
	_gear = yard_gear


## How many machines of `gear` an area of `bays` bays gets: one per
## bays_per_machine, and at least one.
func count_for(gear: String, bays: int) -> int:
	return maxi(1, bays / _gear[gear].bays_per_machine)


## Adds a machine of `gear` to `area`, standing at bay `bay`.
func add(area: int, gear: String, bay: int) -> int:
	list[_next_id] = {"area": area, "gear": gear, "bay": bay, "job": {}}
	_next_id += 1
	return _next_id - 1


## Gives idle machine `id` a job: fetch a box from bay `from`, put it at bay
## `to`, first moving `rehandles` boxes off it, each a lift and a set-down.
func give(id: int, from: int, to: int, rehandles := 0) -> void:
	var machine: Dictionary = list[id]
	assert(machine.job.is_empty(), "machine %d is already working" % id)
	var gear: Dictionary = _gear[machine.gear]
	var phases := [{"kind": "travel", "seconds": _travel(gear, machine.bay, from), "bay": from}]
	for i in rehandles:
		phases.append({"kind": "lift", "seconds": gear.lift_seconds, "bay": from})
		phases.append({"kind": "set_down", "seconds": gear.set_down_seconds, "bay": from})
	phases.append_array([
		{"kind": "lift", "seconds": gear.lift_seconds, "bay": from},
		{"kind": "travel", "seconds": _travel(gear, from, to), "bay": to},
		{"kind": "set_down", "seconds": gear.set_down_seconds, "bay": to},
	])
	machine.job = {"phases": phases, "left": phases[0].seconds, "carrying": false}


## Runs every machine for one tick. Returns the ids that finished a job.
func tick() -> Array[int]:
	var finished: Array[int] = []
	for id: int in list:
		var job: Dictionary = list[id].job
		if job.is_empty():
			continue
		var time := SECONDS_PER_TICK
		while time > 0.0 and not job.phases.is_empty():
			var spent := minf(time, job.left)
			job.left -= spent
			time -= spent
			if job.left <= 0.0:
				var done: Dictionary = job.phases.pop_front()
				list[id].bay = done.bay
				if done.kind in ["lift", "set_down"]:
					job.carrying = done.kind == "lift"
				if not job.phases.is_empty():
					job.left = job.phases[0].seconds
		if job.phases.is_empty():
			list[id].job = {}
			finished.append(id)
	return finished


## Where machine `id` stands along its area, in bays: between two bays while
## it travels.
func position(id: int) -> float:
	var machine: Dictionary = list[id]
	if machine.job.is_empty() or machine.job.phases[0].kind != "travel":
		return machine.bay
	var phase: Dictionary = machine.job.phases[0]
	var done: float = 1.0 - machine.job.left / phase.seconds if phase.seconds > 0.0 else 1.0
	return lerpf(machine.bay, phase.bay, done)


## How high machine `id`'s spreader is, 0 at the ground to 1 at the top:
## rising as it lifts, held up while carrying, lowering as it sets down.
func spreader(id: int) -> float:
	var job: Dictionary = list[id].job
	if job.is_empty():
		return 1.0
	var phase: Dictionary = job.phases[0]
	var done: float = 1.0 - job.left / phase.seconds if phase.seconds > 0.0 else 1.0
	match phase.kind:
		"lift":
			return done
		"set_down":
			return 1.0 - done
	return 1.0


## The phase machine `id` is in ("travel", "lift", "set_down"), or "" when idle.
func phase(id: int) -> String:
	var job: Dictionary = list[id].job
	return "" if job.is_empty() else job.phases[0].kind


func to_dict() -> Dictionary:
	return {"list": list.duplicate(true), "next_id": _next_id}


static func from_dict(d: Dictionary, yard_gear: Dictionary) -> Machines:
	var machines := Machines.new(yard_gear)
	machines.list = d.list.duplicate(true)
	machines._next_id = d.next_id
	return machines


static func _travel(gear: Dictionary, from: int, to: int) -> float:
	return absi(to - from) * AreaLayout.BAY * Grid.CELL / gear.speed
