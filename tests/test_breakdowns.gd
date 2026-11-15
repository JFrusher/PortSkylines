extends SceneTree
## M11 breakdowns: with breakdowns on, working quay cranes and yard gear
## break down on average every mtbf_hours of work, and a broken one does no
## work; with them off nothing breaks, and the storms planned are the same.
## godot --headless --script res://tests/test_breakdowns.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_the_rate_matches_the_data()
	_test_off_breaks_nothing_and_moves_no_storm()
	_test_broken_equipment_does_no_work()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_the_rate_matches_the_data() -> void:
	var sim := AreaPort.base()
	sim.apply({"op": "set_event_kind", "kind": "breakdowns", "on": true})
	var ticks := 400000
	var breaks := 0
	for i in ticks:
		if sim.event_plan.breaks(2.0):
			breaks += 1
	var expected := ticks * SimClock.CALENDAR_MINUTES_PER_TICK / 120.0
	_expect(absf(breaks - expected) < expected * 0.1, true, "%d breakdowns in %d working ticks at 2 hours between, against %.0f" % [breaks, ticks, expected])


func _test_off_breaks_nothing_and_moves_no_storm() -> void:
	var off := AreaPort.base()
	var on := AreaPort.base()
	on.apply({"op": "set_event_kind", "kind": "breakdowns", "on": true})
	var broke := false
	for i in 2000:
		broke = broke or off.event_plan.breaks(0.01)
		on.event_plan.breaks(0.01)
	_expect(broke, false, "breakdowns off: nothing breaks")
	for sim: PortSim in [off, on]:
		sim.event_plan.tick(sim)
	_expect(on.event_plan.list, off.event_plan.list, "the same storms either way")


## A port whose quay cranes, then whose yard gear, fail every few minutes
## (one at a time, so the other keeps boxes coming): they break, and none
## that is broken moves on with its work.
func _test_broken_equipment_does_no_work() -> void:
	for fragile: String in ["sts_cranes", "yard_gear"]:
		var sim := AreaPort.base()
		sim.apply({"op": "set_event_kind", "kind": "breakdowns", "on": true})
		for kind: String in sim.rules[fragile]:
			sim.rules[fragile][kind].mtbf_hours = 0.2
		var worked_broken := false
		for i in roundi(8 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
			var timers := sim.cranes.map(func(c: PortSim.Crane) -> Array: return [c.broken, c.timer])
			var jobs := {}
			for id: int in sim.machines.list:
				jobs[id] = [sim.machines.list[id].broken, sim.machines.list[id].job.duplicate(true)]
			sim.tick()
			for k in sim.cranes.size():
				if timers[k][0] and sim.cranes[k].timer != timers[k][1]:
					worked_broken = true
			for id: int in jobs:
				if id in sim.machines.list and jobs[id][0] and sim.machines.list[id].job != jobs[id][1]:
					worked_broken = true
		var broken := sim.cranes.any(func(c: PortSim.Crane) -> bool: return c.broken) if fragile == "sts_cranes" else sim.machines.list.values().any(func(m: Dictionary) -> bool: return m.broken)
		_expect(broken, true, "%s break down" % fragile)
		_expect(worked_broken, false, "nothing broken works (%s fragile)" % fragile)
		_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.ends_with("broke down")), true, "the event list says so")
