extends SceneTree
## M9 step D: barges come and go only by a river's inland end, where it
## leaves the site; every other ship only by the open sea. Step E: a barge
## berth takes only barges and a barge only a barge berth; imports booked to
## barge leave only by barge, and what barges land goes out as exports.
## godot --headless --script res://tests/test_barges.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_barges_come_by_the_river()
	_test_barges_unlock_at_the_terminal()
	_test_only_barges_sail_a_river_channel()
	_test_a_barge_berth_takes_only_barges()
	_test_barge_boxes_leave_only_by_barge()
	_test_no_barge_no_booking()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The strait with a river 12 m deep in from the north edge at x = 300
## cells, turning west at y = 300 to the sea, and an anchorage in the sea
## off its mouth.
func _river_port() -> PortSim:
	var rules := RandomPort.quick()
	rules.maps.strait.rivers = [{"points": [[1202, 0], [1202, 1202], [0, 1202]], "width": 120, "depth": 12}]
	var sim := PortSim.new(0, rules, true)
	_expect(sim.apply({"op": "build_anchorage", "from": Vector2i(20, 275), "to": Vector2i(70, 325)}), "", "an anchorage off the river's mouth")
	return sim


func _test_barges_come_by_the_river() -> void:
	var sim := _river_port()
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(0, 300), "to": Vector2i(50, 300), "type": "narrow"}), "", "a lane in from the sea to the anchorage")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(50, 300), "to": Vector2i(300, 300), "type": "narrow"}), "", "and on up the river to its turn")
	_expect(Marine.route_to_anchorage(sim, "barge", 1), [] as Array[Vector2], "with no lane down the river a barge can't come")
	_expect(Marine.route_to_anchorage(sim, "feeder", 1)[0], Vector2(0.5, 300.5), "a feeder comes in from the sea")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(300, 0), "to": Vector2i(300, 300), "type": "narrow"}), "", "a lane down the river")
	_expect(Marine.route_to_anchorage(sim, "barge", 1)[0], Vector2(300.5, 0.5), "a barge comes down the river from its inland end")
	_expect(Marine.route_to_anchorage(sim, "feeder", 1)[0], Vector2(0.5, 300.5), "a feeder still comes from the sea, though the river is deep enough")
	_expect(Marine.edge_nodes(sim, false).size(), 1, "the river's end isn't open sea")


func _test_barges_unlock_at_the_terminal() -> void:
	var sim := PortSim.new(0, RandomPort.strait())
	_expect(sim.lock_error("barge"), "Unlocked at milestone 2: %d TEU across the quay" % sim.milestones()[1].teu, "barges come with milestone 2")


## Where a ship lies at `apron`: its pocket's middle, as AreaPort.add_lane.
func _berth_point(sim: PortSim, apron: int) -> Vector2i:
	var area: Dictionary = sim.areas.list[apron]
	var cells := RoadNet.line(area.start, area.end)
	return cells[cells.size() / 2] + area.out * (sim.areas.depth_of(area) + sim.rules.water.pocket / 2)


## A barge berth at row 400 and a feeder berth at row 520 on the strait's
## coast, with lanes from the river and the sea to both: only a barge has a
## way to the barge berth, and only a feeder to the feeder berth.
func _test_a_barge_berth_takes_only_barges() -> void:
	var sim := AreaPort.owned(_river_port())
	var aprons := {}
	for berth: Array in [["barge", 400], ["feeder", 520]]:
		_expect(sim.apply({"op": "build_berth", "kind": berth[0], "cell": Vector2i(83, berth[1])}), "", "a %s berth is built" % berth[0])
		aprons[berth[0]] = sim.areas.list.keys().max()
	_expect(sim.areas.list[aprons.barge].settings.barge, true, "the barge berth is marked as one")
	_expect(sim.areas.list[aprons.feeder].settings.barge, false, "the feeder berth isn't")
	# Down the river, out to sea, then south past both berths, with a lane in to each.
	var lanes := [[Vector2i(300, 0), Vector2i(300, 300)], [Vector2i(300, 300), Vector2i(50, 300)], [Vector2i(0, 300), Vector2i(50, 300)], [Vector2i(50, 300), Vector2i(50, 400)], [Vector2i(50, 400), Vector2i(50, 520)]]
	for kind: String in ["barge", "feeder"]:
		var point := _berth_point(sim, aprons[kind])
		lanes.append([Vector2i(50, point.y), point])
	for lane: Array in lanes:
		_expect(sim.apply({"op": "build_ship_lane", "from": lane[0], "to": lane[1], "type": "narrow"}), "", "a lane from %s to %s" % lane)
	_expect(Marine.reaches(sim, "barge", aprons.barge), true, "a barge reaches the barge berth")
	_expect(Marine.reaches(sim, "feeder", aprons.barge), false, "a feeder never takes the barge berth")
	_expect(Marine.reaches(sim, "feeder", aprons.feeder), true, "a feeder reaches its berth")
	_expect(Marine.reaches(sim, "barge", aprons.feeder), false, "a barge never takes a feeder berth")


## With Riverline's barges calling, Aurora books every import bound for a
## place on the river to barge (and none while no barge calls): none
## of them leaves by lorry; a barge alongside loads them and only them, and
## what it lands goes to the export block.
func _test_barge_boxes_leave_only_by_barge() -> void:
	var rules := RandomPort.quick()
	rules.lines.aurora.barge_share = 1.0
	var sim := AreaPort.base(rules, "")
	var exports := AreaPort.add_export_block(sim)
	# Riverline's barges call at the terminal's berth.
	sim.contracts.services.append({"id": 900, "line": "riverline", "kind": "barge", "start": 9000, "window_hours": 8.0, "moves": 0, "apron": 1, "any_berth": true, "asked": 9000})
	var big := PortSim.Ship.new("panamax", "aurora", sim.clock.calendar_minutes() + 6000.0, 60, 0)
	sim.ships.append(big)
	_expect(AreaFlow.berth(sim, big), true, "the Panamax berths")
	big.state = PortSim.Ship.State.WORKING
	big.sail = 1.0
	big.berthed = sim.clock.calendar_minutes()
	var on_lorry := 0
	for i in roundi(8 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.kind == "lorry" and vehicle.box in sim.boxes and sim.boxes[vehicle.box].barge:
				on_lorry += 1
	var booked := sim.boxes.keys().filter(func(id: int) -> bool: return sim.boxes[id].barge)
	_expect(booked.size() > 5, true, "imports for the river's places are booked to barge (%d)" % booked.size())
	_expect(booked.all(func(id: int) -> bool: return sim.by_barge_to(id)), true, "only boxes for places the river reaches")
	_expect(on_lorry, 0, "no lorry takes a barge box")
	# A barge alongside, with 10 boxes to land and room for every booked box.
	var barge := PortSim.Ship.new("barge", "riverline", sim.clock.calendar_minutes() + 6000.0, 10, booked.size())
	barge.apron = 1
	barge.from = 0
	barge.state = PortSim.Ship.State.WORKING
	barge.sail = 1.0
	barge.berthed = sim.clock.calendar_minutes()
	sim.ships.append(barge)
	for i in roundi(4 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if barge.boxes == 0 and barge.exports == 0:
			break
	# It has room for exactly the booked boxes, so loading any other leaves one behind.
	_expect(booked.filter(func(id: int) -> bool: return id in sim.boxes), [], "the barge loads every barge box, and only those")
	var landed := AreaFlow._stacks(sim, exports).of_kind("export", sim.boxes).filter(func(id: int) -> bool: return sim.boxes[id].line == "riverline")
	_expect(landed.size(), 10, "what the barge lands waits in the export block")
	_expect(landed.all(func(id: int) -> bool: return sim.by_barge_to(id)), true, "from places on the river")


## The same port with no barge service: nothing is booked to barge.
func _test_no_barge_no_booking() -> void:
	var rules := RandomPort.quick()
	rules.lines.aurora.barge_share = 1.0
	var sim := AreaPort.base(rules, "")
	var big := PortSim.Ship.new("panamax", "aurora", sim.clock.calendar_minutes() + 6000.0, 30, 0)
	sim.ships.append(big)
	_expect(AreaFlow.berth(sim, big), true, "the Panamax berths")
	big.state = PortSim.Ship.State.WORKING
	big.sail = 1.0
	big.berthed = sim.clock.calendar_minutes()
	for i in roundi(2 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(sim.boxes.size() > 10, true, "boxes are landed (%d)" % sim.boxes.size())
	_expect(sim.boxes.values().filter(func(b: Dictionary) -> bool: return b.barge), [], "with no barge calling, none is booked to one")


## A river channel in from the sea is deep and wide enough for a feeder,
## but only barges sail one.
func _test_only_barges_sail_a_river_channel() -> void:
	var sim := _river_port()
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(0, 300), "to": Vector2i(50, 300), "type": "river"}), "", "a river channel in from the sea")
	_expect(Marine.route_to_anchorage(sim, "feeder", 1), [] as Array[Vector2], "a feeder never sails a river channel")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(0, 310), "to": Vector2i(50, 310), "type": "narrow"}), "", "a narrow channel beside it")
	_expect(Marine.route_to_anchorage(sim, "feeder", 1).is_empty(), false, "a feeder takes the narrow one")
