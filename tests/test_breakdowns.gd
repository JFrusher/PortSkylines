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
	_test_a_workshop_mends_what_breaks()
	_test_one_workshop_serves_the_port()
	_test_preventive_maintenance()
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


## The base port with a workshop along the east road and
## `mechanics` mechanics, and its quay cranes all broken.
func _workshop_port(mechanics: int) -> PortSim:
	var sim := AreaPort.base()
	sim.creative = true
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_expect(sim.apply({"op": "build_area", "type": "workshop", "segment": east, "side": 1, "from": 62, "to": 70}), "", "a workshop along the east road")
	var workshop: int = sim.areas.list.keys().max()
	_expect(sim.areas.list[workshop].terminal, sim.areas.list[1].terminal, "in the terminal")
	if mechanics > 0:
		_expect(sim.apply({"op": "hire_mechanics", "area": workshop, "count": mechanics}), "", "with %d mechanics" % mechanics)
	for crane: PortSim.Crane in sim.cranes:
		crane.broken = true
	return sim


## Calendar minutes until every quay crane is mended, or -1 after `hours`.
func _until_mended(sim: PortSim, hours: float) -> float:
	var start := sim.clock.calendar_minutes()
	for i in roundi(hours * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if sim.cranes.all(func(c: PortSim.Crane) -> bool: return not c.broken):
			return sim.clock.calendar_minutes() - start
	return -1.0


func _test_a_workshop_mends_what_breaks() -> void:
	var none := _workshop_port(0)
	_expect(none.cranes.size() >= 2, true, "two quay cranes to break")
	_expect(_until_mended(none, 6.0), -1.0, "with no mechanics the cranes stay broken")
	var one := _until_mended(_workshop_port(1), 12.0)
	var two := _until_mended(_workshop_port(2), 12.0)
	var most: float = none.rules.events.breakdowns.repair_hours_max * 60.0
	_expect(one > 0.0 and two > 0.0, true, "mechanics mend them (one: %.0f min, two: %.0f min)" % [one, two])
	_expect(two < one, true, "two mechanics mend two cranes sooner than one")
	_expect(two <= most + 60.0, true, "each within its repair and the drive (%.0f min)" % two)


## A workshop's mechanics mend what breaks anywhere in the port, not only
## in its own terminal.
func _test_one_workshop_serves_the_port() -> void:
	var sim := _workshop_port(1)
	var workshop: int = sim.areas.list.keys().max()
	sim.creative = true
	_expect(sim.apply({"op": "paint_terminal", "cells": sim.areas.cells(workshop), "terminal": -1}), "", "the workshop is painted into a terminal of its own")
	sim.creative = false
	_expect(sim.areas.list[workshop].terminal != sim.areas.list[1].terminal, true, "away from the cranes' terminal")
	_expect(_until_mended(sim, 12.0) > 0.0, true, "and its mechanic still mends the cranes")


## Serviced equipment fails serviced_mtbf_factor times less often; once it
## has worked service_every_hours a mechanic comes, takes it out of work for
## its service, and its hours start again.
func _test_preventive_maintenance() -> void:
	var sim := _workshop_port(1)
	for crane: PortSim.Crane in sim.cranes:
		crane.broken = false
	var factor: float = sim.rules.events.breakdowns.serviced_mtbf_factor
	_expect(sim.apply({"op": "set_serviced", "kind": "reach_stacker", "on": true}), "", "reach stackers serviced")
	_expect(sim.apply({"op": "set_serviced", "kind": "teapot", "on": true}), "No such equipment", "only real equipment")
	_expect(is_equal_approx(Events.mtbf(sim.rules, "yard_gear", "reach_stacker", sim.serviced), sim.rules.yard_gear.reach_stacker.mtbf_hours * factor), true, "serviced, it fails %.0f times less often" % factor)
	_expect(is_equal_approx(Events.mtbf(sim.rules, "yard_gear", "rtg", sim.serviced), sim.rules.yard_gear.rtg.mtbf_hours), true, "unserviced gear as before")
	while sim.machines.list.is_empty():
		sim.tick()
	var machine: Dictionary = sim.machines.list.values()[0]
	machine.worked = sim.rules.events.breakdowns.service_every_hours * 60.0
	var out_of_work := false
	for i in roundi(4 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		out_of_work = out_of_work or machine.broken
		if sim.events.any(func(e: Dictionary) -> bool: return e.text.ends_with("is serviced")):
			break
	_expect(out_of_work, true, "it is out of work while serviced")
	_expect(machine.broken, false, "and back at work after")
	_expect(machine.worked < 60.0, true, "its hours start again (%.0f min)" % machine.worked)
