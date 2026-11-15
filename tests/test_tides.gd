extends SceneTree
## M11 tides: with tides on the water rises and falls twice a day; a ship
## whose draft needs more water than its channel has at chart depth is
## cleared only when the tide stays high enough all its passage, waiting at
## anchor or at sea. With tides off it can't come in at all.
## godot --headless --script res://tests/test_tides.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_the_tide_rises_and_falls()
	_test_a_deep_ship_comes_in_on_high_water()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_the_tide_rises_and_falls() -> void:
	var sim := AreaPort.base(RandomPort.quick(), "")
	_expect(Marine.tide(sim, 0.0), 0.0, "tides off: no tide")
	sim.apply({"op": "set_event_kind", "kind": "tides", "on": true})
	var half: float = sim.rules.water.tides.range / 2.0
	var period: float = sim.rules.water.tides.period_hours * 60.0
	_expect(is_equal_approx(Marine.tide(sim, 0.0), half), true, "high water at the start")
	_expect(is_equal_approx(Marine.tide(sim, period / 2.0), -half), true, "low water half a tide later")
	_expect(is_equal_approx(Marine.tide(sim, period), half), true, "high again a tide later")


## A feeder whose draft is 1 m more than its channel at chart depth.
func _test_a_deep_ship_comes_in_on_high_water() -> void:
	var sim := AreaPort.base(RandomPort.quick(), "")
	var probe := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], 6000.0, 0, 0)
	probe.id = 900
	sim.ships.append(probe)
	_expect(AreaFlow.berth(sim, probe), true, "a feeder can be given a course")
	var least := Marine.shallowest(sim, probe)
	sim.ships.erase(probe)
	sim.rules.ship_classes.feeder.draft = least + 1.0
	sim.rules.ship_classes.feeder.light_draft = least + 1.0
	sim._ship_routes.clear()
	var apron: int = probe.apron
	_expect(Marine.reaches(sim, "feeder", apron), false, "tides off: too deep to come in")
	sim.apply({"op": "set_event_kind", "kind": "tides", "on": true})
	_expect(Marine.reaches(sim, "feeder", apron), true, "tides on: it can, on the tide")
	# Start at low water, so it must wait.
	var period: float = sim.rules.water.tides.period_hours * 60.0
	sim.clock.ticks = roundi(period / 2.0 / SimClock.CALENDAR_MINUTES_PER_TICK)
	var ship := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 6000.0, 0, 0)
	ship.id = 901
	sim.ships.append(ship)
	var waited := false
	var set_off := -1.0
	for i in roundi(period / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if ship.state == PortSim.Ship.State.ARRIVING and not ship.cleared:
			waited = true
		if ship.state == PortSim.Ship.State.ARRIVING and ship.sail > 0.0 and set_off < 0.0:
			set_off = sim.clock.calendar_minutes()
		if ship.state == PortSim.Ship.State.WORKING:
			break
	_expect(waited, true, "at low water it waits")
	_expect(set_off >= 0.0 and Marine.tide(sim, set_off) >= 1.0, true, "it sets off on water 1 m up or more (%.2f m)" % Marine.tide(sim, set_off))
	_expect(ship.state, PortSim.Ship.State.WORKING, "and comes alongside on it")
