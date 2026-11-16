class_name Town
extends RefCounted
## The town next door (M11): just past the site's east edge, astride the
## highway as it comes in. Its mood (0 to 100) eases each game hour towards
## what the port gives it: jobs and the community fund raise it; noise from
## areas, ships at berth and lorries on the highway, and floodlights at
## night, lower it. A tree belt between a source and the town halves what
## reaches it, shore power silences a quay's ships, and a bypass takes the
## highway's lorries round the town. The mood changes nothing else: the town
## only shows it, and says so in the news.


## Where the town's middle is, in grid cells: past the site's east edge.
static func centre(sim: PortSim) -> Vector2:
	var offset: Array = sim.rules.town.offset_cells
	return Vector2(sim.site_entry()) + Vector2(offset[0], offset[1])


## What the port does to the town's mood now: {"jobs", "fund", "noise",
## "light"} as mood points (noise and light count against), and "target",
## the mood it eases towards.
static func parts(sim: PortSim) -> Dictionary:
	var rules: Dictionary = sim.rules.town
	var reach: float = rules.reach_m / Grid.CELL
	var town := centre(sim)
	var belts := _belts(sim)
	var night := _night(sim)
	var noise := 0.0
	var light := 0.0
	for id: int in sim.areas.list:
		var kind := sim.areas.kind_of(sim.areas.list[id])
		var near := reaching(sim, id, town, reach, belts)
		noise += rules.noise.get(kind, 0.0) * near
		if night:
			light += rules.light.get(kind, 0.0) * near
	for ship: PortSim.Ship in sim.ships:
		if ship.state == PortSim.Ship.State.WORKING and ship.apron in sim.areas.list and not sim.areas.list[ship.apron].settings.get("shore_power", false):
			var cells := sim.areas.cells(ship.apron)
			noise += rules.ship_noise * _falloff(Vector2(cells[cells.size() / 2]), town, reach)
	if not sim.town.bypass:
		noise += rules.lorry_noise * sim.vehicles.filter(func(vehicle: Vehicle) -> bool: return vehicle.kind == "lorry").size()
	var found := {
		"jobs": minf(jobs(sim) * rules.points_per_job, rules.max_job_points),
		"fund": minf(sim.town.fund / rules.fund_per_point, rules.max_fund_points),
		"noise": noise,
		"light": light,
	}
	found.target = clampf(rules.base_mood + found.jobs + found.fund - noise - light, 0.0, 100.0)
	return found


## How much of area `id`'s noise and light reaches the town: 1 at the town,
## 0 at `reach` cells, halved behind a tree belt among `belts`.
static func reaching(sim: PortSim, id: int, town: Vector2, reach: float, belts: Dictionary) -> float:
	var cells := sim.areas.cells(id)
	var middle := Vector2.ZERO
	for cell in cells:
		middle += Vector2(cell)
	middle /= cells.size()
	var near := _falloff(middle, town, reach)
	return near * sim.rules.town.belt_factor if near > 0.0 and _behind_belt(middle, town, belts) else near


## Each area's noise reaching the town, as a share of the loudest kind's at
## the town itself: the Town noise info view's colours.
static func noise_shares(sim: PortSim) -> Dictionary:
	var rules: Dictionary = sim.rules.town
	var loudest: float = rules.noise.values().max()
	var belts := _belts(sim)
	var found := {}
	for id: int in sim.areas.list:
		var noise: float = rules.noise.get(sim.areas.kind_of(sim.areas.list[id]), 0.0)
		if noise > 0.0:
			found[sim.areas.cells(id)] = noise * reaching(sim, id, centre(sim), rules.reach_m / Grid.CELL, belts) / loudest
	return found


## People working at the port: crane drivers, yard machine drivers, tractor
## drivers, mechanics, fire crews, inspectors and gate staff. AGVs need none.
static func jobs(sim: PortSim) -> int:
	var per: Dictionary = sim.rules.town.jobs
	var count: float = sim.cranes.size() * per.crane + sim.machines.list.size() * per.machine + sim.tractors * per.tractor
	for area: Dictionary in sim.areas.list.values():
		for key: String in ["mechanics", "engines", "inspectors"]:
			count += area.settings.get(key, 0) * per.person
	return roundi(count)


## Eases the mood an hour's step towards its target; says in the news when
## it turns sour or warm.
static func tick_hour(sim: PortSim) -> void:
	var rules: Dictionary = sim.rules.town
	sim.town.mood = lerpf(sim.town.mood, parts(sim).target, rules.ease_per_hour)
	var said := "sour" if sim.town.mood < rules.sour_below else "warm" if sim.town.mood > rules.warm_above else ""
	if said != "" and said != sim.town.said:
		sim._event(("%s's residents complain about the port's noise and lights" if said == "sour" else "%s welcomes the port and the jobs it brings") % rules.name)
	if said != "" or absf(sim.town.mood - 50.0) < 5.0:
		sim.town.said = said


## Pays the day's community fund.
static func pay_fund(sim: PortSim) -> void:
	if sim.town.fund > 0:
		sim.ledger.post("town", -sim.town.fund)


static func set_fund(sim: PortSim, per_day: Variant) -> String:
	if not per_day is int or per_day < 0 or per_day > sim.rules.town.max_fund:
		return "The community fund runs from $0 to $%d a day" % sim.rules.town.max_fund
	sim.town.fund = per_day
	return ""


static func buy_bypass(sim: PortSim) -> String:
	if sim.town.bypass:
		return "The bypass is built already"
	if not sim._afford(sim.rules.town.bypass_cost):
		return "Not enough money"
	sim.ledger.post("construction", -sim.rules.town.bypass_cost)
	sim.town.bypass = true
	return ""


static func buy_shore_power(sim: PortSim, apron: int) -> String:
	if apron not in sim.areas.list or sim.areas.kind_of(sim.areas.list[apron]) != "quay_apron":
		return "No quay apron there"
	if sim.areas.list[apron].settings.shore_power:
		return "This quay has shore power already"
	if not sim._afford(sim.rules.town.shore_power_cost):
		return "Not enough money"
	sim.ledger.post("equipment", -sim.rules.town.shore_power_cost)
	sim.areas.list[apron].settings.shore_power = true
	return ""


## 1 at the town, falling evenly to 0 at `reach` cells.
static func _falloff(from: Vector2, town: Vector2, reach: float) -> float:
	return maxf(0.0, 1.0 - from.distance_to(town) / reach)


static func _night(sim: PortSim) -> bool:
	var hour := fmod(sim.clock.calendar_minutes() / 60.0, 24.0)
	return hour < sim.rules.lighting.night_ends_hour or hour >= sim.rules.town.night_starts_hour


## The cells of every tree belt.
static func _belts(sim: PortSim) -> Dictionary:
	var found := {}
	for id: int in sim.areas.list:
		if sim.areas.kind_of(sim.areas.list[id]) == "tree_belt":
			for cell in sim.areas.cells(id):
				found[cell] = true
	return found


## Whether the straight line from `from` to the town crosses a tree belt.
static func _behind_belt(from: Vector2, town: Vector2, belts: Dictionary) -> bool:
	if belts.is_empty():
		return false
	var steps := ceili(from.distance_to(town))
	for i in steps:
		if Vector2i((from.lerp(town, float(i) / steps) + Vector2(0.5, 0.5)).floor()) in belts:
			return true
	return false
