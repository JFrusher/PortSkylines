class_name Machines
extends RefCounted
## Yard machines, each belonging to one area, working one job at a time. A
## job moves a box between two bays of the area in fixed phases, each with a
## time from the data: travel to the box, lift it, travel to its place, set
## it down. The sim owns the times; the view only animates the phase in progress.

## Machine id -> {"area", "gear", "bay": where it stands, "job": {} or
## {"phases": [{"kind", "seconds", "bay"}], "left": seconds left of the first phase}}.
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


## Gives idle machine `id` a job: fetch a box from bay `from`, put it at bay `to`.
func give(id: int, from: int, to: int) -> void:
	var machine: Dictionary = list[id]
	assert(machine.job.is_empty(), "machine %d is already working" % id)
	var gear: Dictionary = _gear[machine.gear]
	var phases := [
		{"kind": "travel", "seconds": _travel(gear, machine.bay, from), "bay": from},
		{"kind": "lift", "seconds": gear.lift_seconds, "bay": from},
		{"kind": "travel", "seconds": _travel(gear, from, to), "bay": to},
		{"kind": "set_down", "seconds": gear.set_down_seconds, "bay": to},
	]
	machine.job = {"phases": phases, "left": phases[0].seconds}


## Runs every machine for one tick. Returns the ids that finished a job.
func tick() -> Array[int]:
	var finished: Array[int] = []
	for id: int in list:
		var job: Dictionary = list[id].job
		if job.is_empty():
			continue
		var time := SimClock.TICK_SECONDS
		while time > 0.0 and not job.phases.is_empty():
			var spent := minf(time, job.left)
			job.left -= spent
			time -= spent
			if job.left <= 0.0:
				list[id].bay = job.phases.pop_front().bay
				if not job.phases.is_empty():
					job.left = job.phases[0].seconds
		if job.phases.is_empty():
			list[id].job = {}
			finished.append(id)
	return finished


## The phase machine `id` is in ("travel", "lift", "set_down"), or "" when idle.
func phase(id: int) -> String:
	var job: Dictionary = list[id].job
	return "" if job.is_empty() else job.phases[0].kind


static func _travel(gear: Dictionary, from: int, to: int) -> float:
	return absi(to - from) * AreaLayout.BAY * Grid.CELL / gear.speed
