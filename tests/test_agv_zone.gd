extends SceneTree
## M11 AGV zone: lanes painted into it are for AGVs alone, and service vans
## and fire engines; tractors and lorries keep out; painting it out opens
## them again.
## godot --headless --script res://tests/test_agv_zone.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_zone_keeps_to_agvs()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_zone_keeps_to_agvs() -> void:
	var sim := AreaPort.base()
	var apron := AreaFlow._buffer_start(sim, 1)
	var block := AreaFlow._buffer_start(sim, 3)
	var reach := func(who: String) -> bool: return Drive.reaches(sim, apron, block, who)
	_expect([reach.call("tractor"), reach.call("agv")], [true, false], "with no zone tractors drive quay to yard, AGVs can't")
	var cells: Array[Vector2i] = []
	for x in sim.areas._size.x:
		for y in sim.areas._size.y:
			cells.append(Vector2i(x, y))
	_expect(sim.apply({"op": "paint_agv_zone", "cells": cells, "on": true}), "", "the zone is painted")
	_expect([reach.call("agv"), reach.call("tractor"), reach.call("lorry"), reach.call("service")], [true, false, false, true], "in the zone only AGVs and service vehicles drive")
	_expect(Workshops.road(sim, sim.areas.centre(apron), sim.areas.centre(block)).is_empty(), false, "a van finds its way through")
	sim.apply({"op": "paint_agv_zone", "cells": cells, "on": false})
	_expect([reach.call("tractor"), reach.call("agv")], [true, false], "painted out, tractors drive again")
