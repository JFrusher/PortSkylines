extends SceneTree
## M11 transfer blocks: laid across their road from the AGV zone back to a
## road behind, they take imports from AGVs at the front and hand them to
## lorries at the back, each end its own slots and queue; twin ASCs, one
## at each end, work them.
## godot --headless --script res://tests/test_transfer_block.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_placed_to_the_back_road()
	_test_agvs_front_lorries_back()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _paint(sim: PortSim, rect: Rect2i) -> void:
	var cells: Array[Vector2i] = []
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			cells.append(Vector2i(x, y))
	sim.apply({"op": "paint_agv_zone", "cells": cells, "on": true})


## The base port as an AGV terminal: its import block gone, a road behind
## the east road joined to it beyond the zone, a transfer block between the
## two, the quay, the front road and the block's front painted into the AGV
## zone, and an AGV depot with six AGVs; the transfer block's id.
func _terminal(sim: PortSim) -> int:
	sim.creative = true
	_expect(sim.apply({"op": "remove_area", "id": 3}), "", "the import block goes")
	sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(200, 300), "to": Vector2i(200, 270)})
	sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(200, 270), "to": Vector2i(130, 270)})
	var east := sim.roads.segment_at(Vector2i(150, 300))
	_expect(sim.apply({"op": "build_area", "type": "transfer_block", "segment": east, "side": -1, "from": 55, "to": 66}), "", "a transfer block back to the road behind")
	var block: int = sim.areas.list.keys().max()
	_paint(sim, Rect2i(74, 195, 17, 112))  # the quay
	_paint(sim, Rect2i(74, 288, 103, 19))  # the front road
	_paint(sim, Rect2i(141, 275, 12, 13))  # the block, all but its back rows
	_expect(AreaFlow.agv_unreachable(sim, block), false, "no AGV terminal yet, nothing to warn of")
	_expect(sim.apply({"op": "build_area", "type": "agv_depot", "segment": east, "side": -1, "from": 30, "to": 40}), "", "an AGV depot")
	_expect(AreaFlow.agv_unreachable(sim, block), true, "with nowhere in the zone to turn, AGVs can't reach it")
	# AGVs need somewhere in the zone to turn: a dead end off the front road.
	sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(170, 300), "to": Vector2i(170, 316)})
	_paint(sim, Rect2i(160, 300, 20, 20))
	_expect(AreaFlow.agv_unreachable(sim, block), false, "with a dead end to turn in, they can")
	_expect(sim.apply({"op": "buy_agvs", "area": sim.areas.list.keys().max(), "count": 6}), "", "six AGVs")
	sim.creative = false
	sim.ledger.cash = 10000000
	return block


func _test_placed_to_the_back_road() -> void:
	var sim := AreaPort.base()
	sim.creative = true
	var east := sim.roads.segment_at(Vector2i(150, 300))
	_expect(sim.areas.add_error("transfer_block", east, -1, 55, 66).begins_with("A transfer block runs back to a road"), true, "with no road behind it can't be built")
	var block := _terminal(AreaPort.base())
	_expect(block != 0, true, "with one it can")
	var placed := AreaPort.base()
	block = _terminal(placed)
	_expect(placed.areas.list[block].depth, 28, "it reaches back to the road behind")
	_expect(placed.apply({"op": "set_area", "id": block, "settings": {"gear": "rtg"}}).is_empty(), false, "its gear is its ASCs")
	_expect(placed.apply({"op": "set_area", "id": 4, "settings": {"gear": "asc"}}).is_empty(), false, "ASCs work transfer blocks only")


func _test_agvs_front_lorries_back() -> void:
	var sim := AreaPort.base()
	var block := _terminal(sim)
	var doors := {}  # [kind, door] seen at a slot of the block
	var worked := {}  # its machines that had a job
	var most := 0
	for i in roundi(4 * 24 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for vehicle: Vehicle in sim.vehicles:
			# Handed over, not just given a slot: the machine has it.
			if vehicle.area == block and vehicle.state in ["handling", "handled"]:
				doors[[vehicle.kind, signi(AreaFlow._door(sim, vehicle))]] = true
		for id: int in sim.machines.list:
			if sim.machines.list[id].area == block and not sim.machines.list[id].job.is_empty():
				worked[id] = true
		most = maxi(most, sim.area_stacks[block].count() if block in sim.area_stacks else 0)
	_expect(most > 0, true, "AGVs stack imports in it (%d at most)" % most)
	_expect(doors.has(["agv", 1]) and not doors.has(["agv", -1]), true, "AGVs hand over at the front only %s" % [doors.keys()])
	_expect(doors.has(["lorry", -1]) and not doors.has(["lorry", 1]), true, "lorries at the back only %s" % [doors.keys()])
	_expect(worked.size(), 2, "both ASCs work")
