class_name Fires
extends RefCounted
## Fires (M11). With fires switched on they break out now and then, from
## their own seeded chances: on a ship at berth, or in a yard block holding
## boxes, one with or beside dangerous goods likelier. The crew that can get
## there soonest goes: a fire engine from a fire station by road, or for a
## ship a fireboat from a tug depot by water. A fire no crew has reached
## after a grace burns boxes (or a ship's line's patience); once a crew is
## there it is out in fight_hours. A burning block's machines and a burning
## ship's cranes stop.

## Fire id -> {"target": ["block", area] or ["ship", ship id], "at": where
## it burns (cells), "started", "out_at" (0 until a crew is there), "crew":
## ["engine", id], ["fireboat", boat id] or []}.
var list := {}
## Engine id -> {"station": its fire station, "job": "home", "out",
## "fighting" or "back", "fire": the fire it goes to or 0, "at", "path"}.
var engines := {}
var _next := 1


## Buys `count` fire engines at fire station `area`.
func buy_engines(sim: PortSim, area: int, count: int) -> String:
	if count < 1:
		return "Buy at least one"
	if area not in sim.areas.list or sim.areas.kind_of(sim.areas.list[area]) != "fire_station":
		return "No fire station there"
	var cost: int = count * sim.rules.events.fires.engine_cost
	if not sim._afford(cost):
		return "Not enough money"
	sim.ledger.post("equipment", -cost)
	sim.areas.list[area].settings.engines += count
	for i in count:
		engines[_next] = {"station": area, "job": "home", "fire": 0, "at": Workshops.door(sim, area), "path": [] as Array[Vector2]}
		_next += 1
	return ""


## Whether yard block `area` is burning.
func block_burning(area: int) -> bool:
	return list.values().any(func(f: Dictionary) -> bool: return f.target == ["block", area])


## Whether the ship with id `ship` is burning.
func ship_burning(ship: int) -> bool:
	return list.values().any(func(f: Dictionary) -> bool: return f.target == ["ship", ship])


func tick(sim: PortSim) -> void:
	var rules: Dictionary = sim.rules.events.fires
	var now := sim.clock.calendar_minutes()
	for id: int in engines.keys():
		if engines[id].station not in sim.areas.list:
			engines.erase(id)
	if sim.event_plan.on.fires and sim.event_plan.fire_rng.randf() < rules.per_week * SimClock.CALENDAR_MINUTES_PER_TICK / (7.0 * 1440.0):
		_break_out(sim)
	for id: int in list.keys():
		var fire: Dictionary = list[id]
		if not _target_here(sim, fire.target):
			_out(sim, id)
			continue
		if fire.crew.is_empty():
			_send_crew(sim, id)
		elif fire.out_at == 0.0 and _crew_there(sim, fire.crew):
			fire.out_at = now + rules.fight_hours * 60.0
		if fire.out_at == 0.0 and now - fire.started > rules.grace_minutes:
			_burn(sim, fire)
		if fire.out_at > 0.0 and now >= fire.out_at:
			sim._event("The fire is out")
			_out(sim, id)
	for engine: Dictionary in engines.values():
		if engine.job in ["out", "back"]:
			Workshops.drive(engine, rules.engine_speed)
			if engine.path.is_empty():
				engine.job = "fighting" if engine.job == "out" else "home"


## Sets a fire: on a working ship (ship_share of fires, while one is
## alongside) or in a yard block holding boxes, by weight, dangerous goods
## and their neighbours dg_factor times likelier.
func _break_out(sim: PortSim) -> void:
	var rng := sim.event_plan.fire_rng
	var rules: Dictionary = sim.rules.events.fires
	var working := sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.state == PortSim.Ship.State.WORKING)
	var target: Array = []
	var at := Vector2.ZERO
	if not working.is_empty() and rng.randf() < rules.ship_share:
		var ship: PortSim.Ship = working[rng.randi() % working.size()]
		target = ["ship", ship.id]
		at = Marine.alongside(sim, ship)
	else:
		var weights := {}
		var total := 0.0
		for area: int in sim.area_stacks:
			if area in sim.areas.list and sim.area_stacks[area].count() > 0:
				var dangerous := AreaFlow.is_dangerous(sim.areas.list[area]) or AreaFlow.near(sim, sim.areas.cells(area), area, AreaFlow.is_dangerous) != 0
				weights[area] = rules.dg_factor if dangerous else 1.0
				total += weights[area]
		if total == 0.0:
			return
		var pick := rng.randf() * total
		for area: int in weights:
			pick -= weights[area]
			if pick <= 0.0:
				target = ["block", area]
				at = sim.areas.point(area, sim.areas.list[area].columns / 2.0, 0)
				break
	if target.is_empty():
		return
	list[_next] = {"target": target, "at": at, "started": sim.clock.calendar_minutes(), "out_at": 0.0, "crew": []}
	_next += 1
	sim._event("Fire! %s is burning" % ("A ship at berth" if target[0] == "ship" else "A yard block"), Vector2i(at.floor()))


## Sends the crew that can reach fire `id` soonest: a free engine by road,
## or for a ship a free fireboat by water.
func _send_crew(sim: PortSim, id: int) -> void:
	var fire: Dictionary = list[id]
	var best: Array = []
	var best_minutes := INF
	var best_path: Array[Vector2] = []
	for e: int in engines:
		if engines[e].job != "home":
			continue
		var path := Workshops.road(sim, engines[e].at, fire.at)
		var minutes: float = Boats.length(engines[e].at, path) * Grid.CELL / sim.rules.events.fires.engine_speed if not path.is_empty() else INF
		if minutes < best_minutes:
			best = ["engine", e]
			best_minutes = minutes
			best_path = path
	if fire.target[0] == "ship":
		for depot: int in sim.tug_depots:
			for b: int in sim.boats.ready_at(depot):
				if sim.boats.list[b].kind != "fireboat":
					continue
				var path := sim.boats.way(sim.areas, sim.boats.list[b].at, fire.at)
				var minutes: float = Boats.length(sim.boats.list[b].at, path) * Grid.CELL / sim.rules.water.fireboats.speed if not path.is_empty() else INF
				if minutes < best_minutes:
					best = ["fireboat", b]
					best_minutes = minutes
					best_path = path
	if best.is_empty():
		return
	fire.crew = best
	if best[0] == "engine":
		var engine: Dictionary = engines[best[1]]
		engine.path = best_path
		engine.job = "out"
		engine.fire = id
	else:
		sim.boats.send(best[1], best_path, "out", id)


func _crew_there(sim: PortSim, crew: Array) -> bool:
	if crew[0] == "engine":
		return crew[1] in engines and engines[crew[1]].job == "fighting"
	return crew[1] in sim.boats.list and sim.boats.list[crew[1]].job == "fight"


## A tick's losses to a fire no crew has reached: a yard block's boxes,
## boxes_per_hour of them off the tops of its stacks (none spoken for), each
## box_value and reputation_per_box with its line; a ship's line's patience,
## ship_reputation_per_hour.
func _burn(sim: PortSim, fire: Dictionary) -> void:
	var rules: Dictionary = sim.rules.events.fires
	var rng := sim.event_plan.fire_rng
	if fire.target[0] == "ship":
		for ship: PortSim.Ship in sim.ships:
			if ship.id == fire.target[1]:
				sim._event_if(sim.contracts.penalise(ship.line, -rules.ship_reputation_per_hour * SimClock.CALENDAR_MINUTES_PER_TICK / 60.0))
		return
	if rng.randf() >= rules.boxes_per_hour * SimClock.CALENDAR_MINUTES_PER_TICK / 60.0:
		return
	var stacks: AreaStacks = sim.area_stacks[fire.target[1]]
	for box: int in stacks.boxes():
		if box not in sim._claimed and stacks.above(box) == 0:
			stacks.take(box)
			sim.ledger.post("fire_losses", -rules.box_value)
			if sim.boxes[box].line in sim.rules.lines:
				sim._event_if(sim.contracts.penalise(sim.boxes[box].line, -rules.reputation_per_box))
			sim._drop_box(box)
			return


## Whether a fire's target is still in port: its block, or its ship.
static func _target_here(sim: PortSim, target: Array) -> bool:
	if target[0] == "block":
		return target[1] in sim.areas.list and target[1] in sim.area_stacks
	return sim.ships.any(func(s: PortSim.Ship) -> bool: return s.id == target[1])


## Puts fire `id` out and sends its crew home.
func _out(sim: PortSim, id: int) -> void:
	var crew: Array = list[id].crew
	list.erase(id)
	if crew.is_empty():
		return
	if crew[0] == "engine" and crew[1] in engines:
		var engine: Dictionary = engines[crew[1]]
		engine.path = Workshops.road(sim, engine.at, Workshops.door(sim, engine.station))
		engine.job = "back" if not engine.path.is_empty() else "home"
		engine.fire = 0
	elif crew[0] == "fireboat" and crew[1] in sim.boats.list:
		sim.boats.go_home(sim.areas, crew[1], sim.marine_base_cell(sim.boats.list[crew[1]].base), 0)


func to_dict() -> Dictionary:
	return {"list": list.duplicate(true), "engines": engines.duplicate(true), "next": _next}


static func from_dict(d: Dictionary) -> Fires:
	var fires := Fires.new()
	fires.list = d.list.duplicate(true)
	for id: int in d.engines:
		var engine: Dictionary = d.engines[id].duplicate(true)
		var path: Array[Vector2] = []
		path.assign(engine.path)
		engine.path = path
		fires.engines[id] = engine
	fires._next = d.next
	return fires
