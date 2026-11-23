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
	_test_racks_take_imports()
	_test_racks_stage_exports()
	_test_agvs_fetch_exports_without_racks()
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
func _terminal(sim: PortSim, keep_import_block := false) -> int:
	sim.creative = true
	sim.milestones_passed = 4  # the hub unlocks ASCs and AGVs
	if not keep_import_block:
		_expect(sim.apply({"op": "remove_area", "id": 3}), "", "the import block goes")
	sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(200, 300), "to": Vector2i(200, 270)})
	sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(200, 270), "to": Vector2i(130, 270)})
	var east := sim.roads.segment_at(Vector2i(150, 300))
	_expect(sim.apply({"op": "build_area", "type": "transfer_block", "segment": east, "side": -1, "from": 55, "to": 66}), "", "a transfer block back to the road behind")
	var block: int = sim.areas.list.keys().max()
	_paint(sim, Rect2i(74, 195, 17, 112))  # the quay
	_paint(sim, Rect2i(74, 288, 60, 19))  # the front road, short of the block
	_paint(sim, Rect2i(141, 275, 12, 13))  # the block, all but its back rows
	_expect(AreaFlow.agv_unreachable(sim, block), false, "no AGV terminal yet, nothing to warn of")
	_expect(sim.apply({"op": "build_area", "type": "agv_depot", "segment": east, "side": -1, "from": 30, "to": 40}), "", "an AGV depot")
	_expect(AreaFlow.agv_unreachable(sim, block), true, "with the zone stopping short of the block, AGVs can't reach it")
	_paint(sim, Rect2i(134, 288, 43, 19))  # the rest of the front road
	_expect(AreaFlow.agv_unreachable(sim, block), false, "with the zone joined up, they can, turning out across the road")
	_expect(sim.apply({"op": "buy_agvs", "area": sim.areas.list.keys().max(), "count": 6}), "", "six AGVs")
	sim.creative = false
	sim.ledger.cash = 10000000
	return block


func _test_placed_to_the_back_road() -> void:
	var sim := AreaPort.base()
	sim.creative = true
	sim.milestones_passed = 4  # the hub unlocks ASCs and AGVs
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


## With racks, AGVs set imports on them and go; the ASCs stack them later,
## and no box is lost on the way.
func _test_racks_take_imports() -> void:
	var sim := AreaPort.base()
	var block := _terminal(sim)
	_expect(sim.apply({"op": "buy_racks", "area": block}), "", "racks bought")
	_expect(sim.apply({"op": "buy_racks", "area": block}).is_empty(), false, "only once")
	var racked := 0
	var lost := false
	for i in roundi(30 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for rack: Dictionary in sim.racks[block].values():
			racked += 1 if rack.state == "in" else 0
			lost = lost or rack.box not in sim.boxes
	_expect(racked > 0, true, "AGVs set imports on the racks")
	_expect(lost, false, "every box on a rack is still in the port")
	_expect(sim.area_stacks[block].count() > 0, true, "and the ASCs stack them")


## A transfer block taking exports, with racks: export lorries bring them in
## at the back; for each export an AGV is sent for, an ASC stages it on a
## rack and the AGV takes it from there to the ship.
func _test_racks_stage_exports() -> void:
	var sim := AreaPort.base()
	var block := _terminal(sim, true)
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"role": "export"}}), "", "it takes exports")
	_expect(sim.apply({"op": "buy_racks", "area": block}), "", "racks bought")
	var staged := false
	var taken := false
	for i in roundi(4 * 24 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		var ready := {}
		for rack: Dictionary in sim.racks[block].values():
			if rack.state == "ready":
				ready[rack.box] = true
		staged = staged or not ready.is_empty()
		sim.tick()
		for vehicle: Vehicle in sim.vehicles:
			taken = taken or (vehicle.kind == "agv" and vehicle.loaded and vehicle.box in ready and vehicle.state == "to_crane")
		if taken:
			break
	_expect(staged, true, "an ASC stages an export on a rack")
	_expect(taken, true, "and an AGV takes it from there to the ship")


## With no racks an AGV collects an export from the ASC at the block's front
## and takes it to the ship, as a tractor would; it is never sent out
## through a gate like a lorry, which an AGV can't reach.
func _test_agvs_fetch_exports_without_racks() -> void:
	var sim := AreaPort.base()
	var block := _terminal(sim, true)
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"role": "export"}}), "", "it takes exports, with no racks")
	var to_crane := false
	var to_gate := false
	for i in roundi(4 * 24 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.kind != "agv" or not vehicle.loaded:
				continue
			to_crane = to_crane or (vehicle.state == "to_crane" and sim.boxes[vehicle.box].kind == "export")
			to_gate = to_gate or (vehicle.area in sim.areas.list and sim.areas.kind_of(sim.areas.list[vehicle.area]) == "gate")
		if to_crane:
			break
	_expect(to_crane, true, "an AGV takes an export from the ASC to the ship")
	_expect(to_gate, false, "and none is sent to a gate")
