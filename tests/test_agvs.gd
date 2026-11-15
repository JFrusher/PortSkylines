extends SceneTree
## M11 AGVs: a terminal with a working AGV depot (in the AGV zone) moves its
## boxes between quay and yard on the depot's AGVs, never more out than it
## owns, and sends no tractor; a depot outside the zone stands idle and the
## terminal keeps its tractors.
## godot --headless --script res://tests/test_agvs.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_agvs_work_the_ship()
	_test_depot_outside_the_zone_is_idle()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The base port with its quay, road and yard painted into the AGV zone (if
## `zone`) and an AGV depot north of the road; the depot's id.
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
	sim.creative = false
	sim.ledger.cash = 10000000
	return sim.areas.list.keys().max()


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
