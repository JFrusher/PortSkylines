class_name Events
extends RefCounted
## Events that disrupt the port (M11): planned a season ahead from their own
## seeded random numbers, so switching a kind on or off never shifts the
## rest of the game's chances; each forecast its lead time before it comes;
## each kind switched on or off per game. Storms are the first kind, and
## tides are switched here too though they are not planned.

## Kind -> whether it is on in this game.
var on := {}
## Planned events, soonest first: {"kind", "from", "to" (calendar minutes),
## "peak" (a storm's strongest gust, km/h), "forecast" (announced yet)}.
var list: Array[Dictionary] = []
## The calendar minute events are planned up to.
var planned_to := 0.0
var _rng := RandomNumberGenerator.new()


static func create(rules: Dictionary, seed_value: int) -> Events:
	var events := Events.new()
	events.on = rules.events.defaults.duplicate()
	events._rng.seed = hash([seed_value, "events"])
	return events


## Plans the seasons that start before `now` plus the longest lead time,
## announces each switched-on event its lead time ahead, and forgets the
## ones that are over.
func tick(sim: PortSim) -> void:
	var now := sim.clock.calendar_minutes()
	var season: float = sim.rules.events.season_days * 1440.0
	var storms: Dictionary = sim.rules.events.storms
	while planned_to <= now + storms.lead_hours * 60.0:
		_plan_storms(storms, planned_to, season)
		planned_to += season
	for event: Dictionary in list:
		if not event.forecast and on[event.kind] and now >= event.from - storms.lead_hours * 60.0:
			event.forecast = true
			sim._event("Storm forecast: gusts up to %d km/h from day %d %02d:00, for %d hours" % [roundi(event.peak), int(event.from / 1440.0), int(event.from / 60.0) % 24, roundi((event.to - event.from) / 60.0)])
	list = list.filter(func(e: Dictionary) -> bool: return e.to >= now)


## The switched-on events of `kind` under way at calendar minute `now`.
func under_way(kind: String, now: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if on[kind]:
		for event: Dictionary in list:
			if event.kind == kind and event.from <= now and now < event.to:
				found.append(event)
	return found


## Switches `kind` on or off for this game.
func set_kind(kind: String, value: bool) -> String:
	if kind not in on:
		return "No such event"
	on[kind] = value
	return ""


func _plan_storms(storms: Dictionary, from: float, season: float) -> void:
	# On average per_season storms: the whole part, and one more by chance.
	var count := floori(storms.per_season + _rng.randf())
	var planned: Array[Dictionary] = []
	for i in count:
		var start := from + _rng.randf() * season
		var hours := _rng.randf_range(storms.hours_min, storms.hours_max)
		planned.append({"kind": "storms", "from": start, "to": start + hours * 60.0, "peak": _rng.randf_range(storms.peak_min_kmh, storms.peak_max_kmh), "forecast": false})
	list.append_array(planned)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.from < b.from)


func to_dict() -> Dictionary:
	return {"on": on.duplicate(), "list": list.duplicate(true), "planned_to": planned_to, "rng_seed": _rng.seed, "rng_state": _rng.state}


static func from_dict(d: Dictionary) -> Events:
	var events := Events.new()
	events.on = d.on.duplicate()
	events.list.assign(d.list.duplicate(true))
	events.planned_to = d.planned_to
	events._rng.seed = d.rng_seed
	events._rng.state = d.rng_state
	return events
