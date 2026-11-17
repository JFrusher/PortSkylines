extends SceneTree
## M11 events: planned a season ahead from their own seeded random numbers,
## the same for the same seed; each forecast its lead time ahead; a kind
## switched off forecasts nothing and leaves the game's chances as they were.
## godot --headless --script res://tests/test_events.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_same_seed_same_plan()
	_test_forecast_lead_time()
	_test_off_forecasts_nothing_and_shifts_nothing()
	_test_the_plan_is_saved()
	_test_wind()
	_test_storm_stops_cranes()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _plan(seed_value: int) -> Array:
	var sim := PortSim.new(seed_value, Content.base())
	sim.event_plan.tick(sim)
	return sim.event_plan.list.map(func(e: Dictionary) -> Array: return [e.kind, e.from, e.to, e.peak])


func _test_same_seed_same_plan() -> void:
	_expect(_plan(7), _plan(7), "the same seed plans the same storms")
	_expect(_plan(7) != _plan(8), true, "another seed plans others")
	_expect(_plan(7).is_empty(), false, "a season has its storms")


## The first storm is forecast within a tick of its lead time before it.
func _test_forecast_lead_time() -> void:
	var sim := AreaPort.base()
	sim.event_plan.tick(sim)
	var storm: Dictionary = sim.event_plan.list[0]
	var lead: float = sim.rules.events.storms.lead_hours * 60.0
	sim.clock.ticks = maxi(0, floori((storm.from - lead) / SimClock.CALENDAR_MINUTES_PER_TICK) - 5)
	var at := -1.0
	for i in 20:
		sim.tick()
		if storm.forecast:
			at = sim.clock.calendar_minutes()
			break
	_expect(at >= storm.from - lead and at < storm.from - lead + SimClock.CALENDAR_MINUTES_PER_TICK * 1.5, true, "forecast at %.2f for a storm at %.2f, %.0f minutes ahead" % [at, storm.from, lead])
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.begins_with("Storm forecast")), true, "and the forecast is in the event list")


## With storms off a game forecasts none, and every other chance in it
## comes out the same as with them on.
func _test_off_forecasts_nothing_and_shifts_nothing() -> void:
	var on := AreaPort.base()
	var off := AreaPort.base()
	_expect(off.apply({"op": "set_event_kind", "kind": "storms", "on": false}), "", "storms switched off")
	_expect(off.apply({"op": "set_event_kind", "kind": "meteors", "on": false}), "No such event", "only known kinds")
	for sim: PortSim in [on, off]:
		sim.event_plan.tick(sim)
		var storm: Dictionary = sim.event_plan.list[0]
		sim.clock.ticks = floori(storm.from / SimClock.CALENDAR_MINUTES_PER_TICK)
		for i in 10:
			sim.tick()
	_expect(off.events.any(func(e: Dictionary) -> bool: return e.text.begins_with("Storm forecast")), false, "storms off: no forecast")
	_expect(off.event_plan.under_way("storms", off.clock.calendar_minutes()), [] as Array[Dictionary], "and none under way")
	_expect(on.event_plan.under_way("storms", on.clock.calendar_minutes()).size(), 1, "storms on: the storm is under way")
	_expect(off.rng.state, on.rng.state, "the game's own chances are untouched")


func _test_the_plan_is_saved() -> void:
	var sim := AreaPort.base()
	sim.apply({"op": "set_event_kind", "kind": "tides", "on": true})
	sim.tick()
	var loaded := PortSim.from_dict(sim.to_dict())
	_expect(loaded.event_plan.to_dict(), sim.event_plan.to_dict(), "the plan and its switches load as saved")


## Calm wind swings with the day, strongest mid-afternoon; a storm lifts it
## to its peak gust halfway through and lets it down again; with storms off
## the wind stays calm through it.
func _test_wind() -> void:
	var sim := AreaPort.base()
	var calm: Dictionary = sim.rules.events.wind
	_expect(is_equal_approx(sim.event_plan.wind(sim.rules, 15 * 60.0), calm.mean_kmh + calm.daily_swing_kmh), true, "strongest at 15:00")
	_expect(is_equal_approx(sim.event_plan.wind(sim.rules, 3 * 60.0), calm.mean_kmh - calm.daily_swing_kmh), true, "calmest at 03:00")
	sim.event_plan.tick(sim)
	var storm: Dictionary = sim.event_plan.list[0]
	var middle: float = (storm.from + storm.to) / 2.0
	_expect(is_equal_approx(sim.event_plan.wind(sim.rules, middle), storm.peak), true, "a storm peaks halfway through (%.1f against %.1f)" % [sim.event_plan.wind(sim.rules, middle), storm.peak])
	_expect(sim.event_plan.wind(sim.rules, storm.to + 1.0) <= calm.mean_kmh + calm.daily_swing_kmh, true, "and is calm again after")
	sim.apply({"op": "set_event_kind", "kind": "storms", "on": false})
	_expect(sim.event_plan.wind(sim.rules, middle) <= calm.mean_kmh + calm.daily_swing_kmh, true, "storms off: calm through it")


## The storm exit criterion: a storm gusting to 100 km/h stops yard gear
## from 65 km/h and quay cranes from 80, says so, and frees them after.
func _test_storm_stops_cranes() -> void:
	var sim := AreaPort.base()
	sim.event_plan.tick(sim)
	sim.event_plan.list.clear()
	var start := sim.clock.calendar_minutes() + 60.0
	sim.event_plan.list.append({"kind": "storms", "from": start, "to": start + 600.0, "peak": 100.0, "forecast": true})
	var yard_stopped := false
	var quay_stopped := false
	var worked_over_limit := false
	for i in roundi(700.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		var before := {}
		for id: int in sim.machines.list:
			before[id] = sim.machines.list[id].job.duplicate(true)
		var timers := sim.cranes.map(func(c: PortSim.Crane) -> float: return c.timer)
		sim.tick()
		var wind := sim.event_plan.wind(sim.rules, sim.clock.calendar_minutes())
		for id: int in sim.machines.list:
			var gear: String = sim.machines.list[id].gear
			if wind >= sim.rules.yard_gear[gear].wind_limit_kmh and not before.get(id, {}).is_empty() and sim.machines.list[id].job != before[id]:
				worked_over_limit = true
		for k in sim.cranes.size():
			if wind >= sim.rules.sts_cranes[sim.cranes[k].kind].wind_limit_kmh and sim.cranes[k].timer != timers[k]:
				worked_over_limit = true
		yard_stopped = yard_stopped or sim.events.any(func(e: Dictionary) -> bool: return e.text.ends_with("yard gear stopped"))
		quay_stopped = quay_stopped or sim.events.any(func(e: Dictionary) -> bool: return e.text.ends_with("quay cranes stopped"))
	_expect(yard_stopped and quay_stopped, true, "the event list says the wind stopped yard gear and quay cranes")
	_expect(worked_over_limit, false, "nothing works over its wind limit")
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.ends_with("quay cranes back at work")), true, "and says when they are back at work")
