class_name Workshops
extends RefCounted
## Workshops and their mechanics (M11). Each mechanic hired at a workshop
## has a van. A van sets out for the nearest broken quay crane or yard
## machine in its workshop's terminal, drives the road there at van speed,
## repairs it for a while, then drives back. Vans keep to the roads but
## stay out of the traffic: they never queue or block.

## Van id -> {"workshop": its area, "job": "home", "out" (driving to its
## repair), "fixing" (until the calendar minute "until") or "back", "fix":
## what it repairs, ["crane", apron, along] or ["machine", id], "at" and
## "path" (points still to drive, in cells), "until"}.
var vans := {}
var _next := 1


## Hires `count` mechanics, each with a van, at workshop `area`.
func hire(sim: PortSim, area: int, count: int) -> String:
	if count < 1:
		return "Hire at least one"
	if area not in sim.areas.list or sim.areas.kind_of(sim.areas.list[area]) != "workshop":
		return "No workshop there"
	var cost: int = count * sim.rules.events.breakdowns.mechanic_cost
	if not sim._afford(cost):
		return "Not enough money"
	sim.ledger.post("equipment", -cost)
	sim.areas.list[area].settings.mechanics += count
	for i in count:
		vans[_next] = {"workshop": area, "job": "home", "fix": [], "at": _door(sim, area), "path": [] as Array[Vector2], "until": 0.0}
		_next += 1
	return ""


## A tick: vans of workshops that are gone go with them; vans drive, finish
## repairs and come home; free vans set out for what is broken.
func tick(sim: PortSim) -> void:
	for id: int in vans.keys():
		if vans[id].workshop not in sim.areas.list:
			vans.erase(id)
	var now := sim.clock.calendar_minutes()
	var busy := {}
	for id: int in vans:
		var van: Dictionary = vans[id]
		if van.job in ["out", "back"]:
			_drive(sim, van)
			if van.path.is_empty():
				if van.job == "out":
					van.job = "fixing"
					van.until = now + sim.event_plan.repair_hours(sim.rules) * 60.0
				else:
					van.job = "home"
		elif van.job == "fixing" and now >= van.until:
			_mend(sim, van.fix)
			van.path = _road(sim, van.at, _door(sim, van.workshop))
			van.job = "back"
		if van.job in ["out", "fixing"]:
			busy[van.fix] = true
	for fix: Array in _broken(sim):
		if fix in busy:
			continue
		var at := _where(sim, fix)
		var terminal: int = _terminal(sim, fix)
		var best := 0
		for id: int in vans:
			var van: Dictionary = vans[id]
			if van.job == "home" and sim.areas.list[van.workshop].terminal == terminal and terminal != 0 and (best == 0 or van.at.distance_to(at) < vans[best].at.distance_to(at)):
				best = id
		if best == 0:
			continue
		var path := _road(sim, vans[best].at, at)
		if path.is_empty():
			continue
		vans[best].path = path
		vans[best].fix = fix
		vans[best].job = "out"


## Moves `van` a tick along its path at van speed.
func _drive(sim: PortSim, van: Dictionary) -> void:
	var left: float = sim.rules.events.breakdowns.van_speed / Grid.CELL * SimClock.CALENDAR_MINUTES_PER_TICK
	while left > 0.0 and not van.path.is_empty():
		var to: Vector2 = van.path[0]
		var gap: float = van.at.distance_to(to)
		if gap <= left:
			van.at = to
			van.path.pop_front()
			left -= gap
		else:
			van.at += (to - van.at) / gap * left
			left = 0.0


## Everything broken: ["crane", apron, along] and ["machine", id].
static func _broken(sim: PortSim) -> Array[Array]:
	var found: Array[Array] = []
	for crane: PortSim.Crane in sim.cranes:
		if crane.broken:
			found.append(["crane", crane.apron, crane.along])
	for id: int in sim.machines.list:
		if sim.machines.list[id].broken:
			found.append(["machine", id])
	return found


static func _mend(sim: PortSim, fix: Array) -> void:
	if fix[0] == "crane":
		for crane: PortSim.Crane in sim.cranes:
			if crane.apron == fix[1] and crane.along == fix[2] and crane.broken:
				crane.broken = false
				sim._event("A %s is repaired" % sim.rules.sts_cranes[crane.kind].name, sim.areas.cell_at(crane.apron, crane.along, 0))
	elif fix[1] in sim.machines.list and sim.machines.list[fix[1]].broken:
		sim.machines.list[fix[1]].broken = false
		sim._event("A %s is repaired" % sim.rules.yard_gear[sim.machines.list[fix[1]].gear].name)


## Where a van parks to repair `fix`, in cells: at the road edge of its area
## beside it.
static func _where(sim: PortSim, fix: Array) -> Vector2:
	if fix[0] == "crane":
		return sim.areas.point(fix[1], fix[2], 0)
	var machine: Dictionary = sim.machines.list[fix[1]]
	return sim.areas.point(machine.area, mini(machine.bay * AreaLayout.BAY, sim.areas.list[machine.area].columns - 1), 0)


static func _terminal(sim: PortSim, fix: Array) -> int:
	var area: int = fix[1] if fix[0] == "crane" else sim.machines.list[fix[1]].area
	return sim.areas.list[area].terminal if area in sim.areas.list else 0


## The middle of workshop `area`'s road edge, where its vans live.
static func _door(sim: PortSim, area: int) -> Vector2:
	return sim.areas.point(area, sim.areas.list[area].columns / 2.0, 0)


## The way by road lanes from `from` to `to`, in cells: the points of the
## lanes between the lanes nearest each; empty when no road joins them.
static func _road(sim: PortSim, from: Vector2, to: Vector2) -> Array[Vector2]:
	Drive._refresh(sim)
	var start: Array = sim.network.nearest(from, false)
	var end: Array = sim.network.nearest(to, false)
	var path: Array[Vector2] = []
	if start[0] == 0 or end[0] == 0:
		return path
	var pieces := sim.network.route(start[0], end[0])
	if pieces.is_empty():
		return path
	for piece: int in pieces:
		for point: Vector2 in sim.network.pieces[piece].points:
			path.append(point)
	path.append(to)
	return path


func to_dict() -> Dictionary:
	return {"vans": vans.duplicate(true), "next": _next}


static func from_dict(d: Dictionary) -> Workshops:
	var workshops := Workshops.new()
	for id: int in d.vans:
		var van: Dictionary = d.vans[id].duplicate(true)
		var path: Array[Vector2] = []
		path.assign(van.path)
		van.path = path
		workshops.vans[id] = van
	workshops._next = d.next
	return workshops
