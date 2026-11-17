extends SceneTree
## M11 AGVs: a terminal with a working AGV depot (in the AGV zone) moves its
## boxes between quay and yard on the depot's AGVs, never more out than it
## owns, and sends no tractor; a depot outside the zone stands idle and the
## terminal keeps its tractors. Batteries: an AGV runs down as it works,
## drives home to its depot once low, and charges there on a charger.
## AGVs near a mechanic's van driving in the zone stand until it has passed.
## godot --headless --script res://tests/test_agvs.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_agvs_work_the_ship()
	_test_depot_outside_the_zone_is_idle()
	_test_batteries_run_down_and_charge()
	_test_safety_stop_for_a_mechanic()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The base port with its quay, road and yard painted into the AGV zone (if
## `zone`), with a dead end in it to turn in, and an AGV depot north of the
## road; the depot's id.
func _depot(sim: PortSim, zone: bool) -> int:
	sim.creative = true
	if zone:
		var cells: Array[Vector2i] = []
		for x in range(75, 150):
			for y in range(200, 310):
				cells.append(Vector2i(x, y))
		_expect(sim.apply({"op": "paint_agv_zone", "cells": cells, "on": true}), "", "the zone is painted")
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_expect(sim.apply({"op": "build_area", "type": "agv_depot", "segment": east, "side": -1, "from": 30, "to": 40}), "", "an AGV depot")
	var depot: int = sim.areas.list.keys().max()
	var unturned := AreaFlow.agv_unreachable(sim, depot)
	if zone:
		# A dead end in the zone past the yard's way out, where AGVs turn to reach the depot.
		sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(148, 300), "to": Vector2i(148, 284)})
		_expect([unturned, AreaFlow.agv_unreachable(sim, depot)], [true, false], "AGVs reach their depot from the yard only with somewhere to turn")
	sim.creative = false
	sim.ledger.cash = 10000000
	return depot


func _test_agvs_work_the_ship() -> void:
	var sim := AreaPort.base()
	var depot := _depot(sim, true)
	_expect(sim.areas.idle_reason(depot), "", "the depot in the zone works")
	_expect(sim.apply({"op": "buy_agvs", "area": depot, "count": 4}), "", "four AGVs bought")
	var kinds := {}
	var most := 0
	var moves := 0
	for i in roundi(24 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		var agvs := 0
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.kind != "lorry":
				kinds[vehicle.kind] = true
			agvs += 1 if vehicle.kind == "agv" else 0
		most = maxi(most, agvs)
		for ship: PortSim.Ship in sim.ships:
			moves = maxi(moves, ship.moves)
	_expect(kinds.keys(), ["agv"], "only AGVs move boxes on the quay")
	_expect(most > 0 and most <= 4, true, "never more AGVs out than owned (%d)" % most)
	_expect(moves > 0, true, "the ship is worked (%d moves)" % moves)


func _test_depot_outside_the_zone_is_idle() -> void:
	var sim := AreaPort.base()
	var depot := _depot(sim, false)
	_expect(sim.areas.idle_reason(depot) != "", true, "a depot outside the zone stands idle")
	_expect(AreaFlow.agv_depots(sim, sim.areas.list[depot].terminal), [] as Array[int], "so its terminal has no AGV depot")
	_expect(sim.apply({"op": "set_area", "id": depot, "settings": {"agvs": 9}}).is_empty(), false, "AGVs can't be set for free")


## With a one-hour battery: AGVs run low and drive home; with no charger
## they stay flat and the ship stops being worked; with chargers they
## charge and go out again. AGVs at home and out always add up to those owned.
func _test_batteries_run_down_and_charge() -> void:
	var sim := AreaPort.base()
	sim.rules.agv.battery_hours = 1.0
	var depot := _depot(sim, true)
	sim.apply({"op": "buy_agvs", "area": depot, "count": 4})
	var home_low := false
	var drove_home := false
	var counted := true
	for i in roundi(6 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for vehicle: Vehicle in sim.vehicles:
			drove_home = drove_home or vehicle.state.trim_prefix("no_route:") == "to_charge"
		home_low = home_low or sim.agv_home[depot].any(func(c: float) -> bool: return c < sim.rules.agv.low_share)
		counted = counted and sim.agv_home[depot].size() + sim._agvs_out.get(depot, 0) == 4
	_expect(drove_home, true, "low AGVs drive home")
	_expect(home_low, true, "and come home low")
	_expect(counted, true, "AGVs at home and out add up to those owned")
	_expect(AreaFlow._free_agv_depot(sim, 1), 0, "with no charger, none is fit to go out")
	_expect(sim.apply({"op": "buy_chargers", "area": depot, "count": 2}), "", "two chargers bought")
	_expect(sim.apply({"op": "buy_chargers", "area": depot, "count": 7}).is_empty(), false, "a depot holds at most eight")
	var out_again := false
	for i in roundi(4 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		out_again = out_again or sim._agvs_out.get(depot, 0) > 0
	_expect(out_again, true, "charged, they go out again")


## A quay crane breaks down in an AGV terminal with a workshop: the
## mechanic's van drives into the zone to it, and the AGVs near it stop
## where they are while it is close.
func _test_safety_stop_for_a_mechanic() -> void:
	var sim := AreaPort.base()
	var depot := _depot(sim, true)
	sim.apply({"op": "buy_agvs", "area": depot, "count": 6})
	sim.creative = true
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_expect(sim.apply({"op": "build_area", "type": "workshop", "segment": east, "side": 1, "from": 92, "to": 100}), "", "a workshop")
	_expect(sim.apply({"op": "hire_mechanics", "area": sim.areas.list.keys().max(), "count": 1}), "", "with a mechanic")
	sim.creative = false
	for i in roundi(6 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if sim.vehicles.any(func(v: Vehicle) -> bool: return v.kind == "agv" and v.state == "under_crane"):
			break
	sim.cranes[0].broken = true
	var held := false
	var moved := false
	for i in roundi(2 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		var before := {}
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.kind == "agv":
				before[vehicle.id] = Drive.where(sim, vehicle)
		sim.tick()
		for id: int in sim.traffic.held:
			held = true
			var vehicle: Vehicle = sim._by_id.get(id)
			moved = moved or (vehicle != null and id in before and Drive.where(sim, vehicle).distance_to(before[id]) > 0.001)
	_expect(held, true, "AGVs near the van stop")
	_expect(moved, false, "and stand still while they do")
