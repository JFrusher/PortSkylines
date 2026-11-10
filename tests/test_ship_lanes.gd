extends SceneTree
## M8 step D: ships sail along ship lanes drawn on the water, from the open
## sea to their berth, only through lanes and pockets as deep as their draft.
## godot --headless --script res://tests/test_ship_lanes.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_lanes_are_drawn_on_water()
	_test_no_lane_no_ships()
	_test_ships_keep_to_deep_lanes()
	_test_ships_sail_the_lanes()
	_test_breakwaters_and_islands()
	_test_lanes_curve()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_lanes_are_drawn_on_water() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(0, 100), "to": Vector2i(40, 100), "type": "narrow"}), "", "a lane is drawn on the water")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(40, 100), "to": Vector2i(80, 100), "type": "narrow"}).begins_with("A lane needs open water"), true, "but not onto land")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(10, 220), "to": Vector2i(40, 232), "type": "narrow"}), "", "lanes run at any angle (M10 step 20)")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(20, 80), "to": Vector2i(20, 120), "type": "narrow"}), "Lanes meet only at their ends", "a lane can't cross another part-way")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(20, 140), "to": Vector2i(20, 100), "type": "narrow"}), "", "a lane may end on another")
	_expect(sim.ship_lanes.segments.size(), 4, "which splits it in two (with the lane at an angle, four)")
	_expect(sim.ship_lanes.at(sim.ship_lanes.segments[4].b).size(), 3, "and joins all three at one node")


## A port whose only lane is taken out gets no ships, and says why.
func _test_no_lane_no_ships() -> void:
	var sim := AreaPort.base()
	_expect(sim.apply({"op": "remove_ship_lane", "segment": sim.ship_lanes.segments.keys()[0]}), "", "the lane is taken out")
	for i in roundi(60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(sim.ships.size(), 0, "no ship calls at a berth no lane reaches")
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.contains("no ship lane from the open sea")), true, "the line says why")


## In 11 m of water a Panamax (13 m) uses only lanes dredged to 13 m: of the
## direct lane's seaward half and a dredged dog-leg joining it half-way, it
## takes the dog-leg.
func _test_ships_keep_to_deep_lanes() -> void:
	var sim := AreaPort.base(RandomPort.water(RandomPort.quick(), 11.0), "")
	var direct: int = sim.ship_lanes.segments.keys()[0]
	var row: int = sim.ship_lanes.nodes[sim.ship_lanes.segments[direct].b].y
	var bend := Vector2i(10, row + 30)
	sim.creative = true
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(0, bend.y), "to": bend, "type": "narrow"}), "", "a lane in from the sea further south")
	_expect(sim.apply({"op": "build_ship_lane", "from": bend, "to": Vector2i(40, row), "type": "narrow"}), "", "and up at 45° onto the direct lane, half-way")
	_expect(Marine.reaches(sim, "panamax", 1), false, "no lane is deep enough for a Panamax yet")
	sim.apply({"op": "dredge_berth", "apron": 1, "metres": 2})
	for segment: int in sim.ship_lanes.segments:
		if segment != direct:
			_expect(sim.apply({"op": "dredge_lane", "segment": segment, "metres": 2}), "", "the dog-leg is dredged to 13 m")
	var route := Marine.route(sim, "panamax", 1)
	_expect(route.has(Vector2(bend) + Vector2(0.5, 0.5)), true, "a Panamax goes round by the dredged dog-leg")
	_expect(Marine.route(sim, "feeder", 1).has(Vector2(bend) + Vector2(0.5, 0.5)), false, "a feeder (10 m) takes the short way, straight in")


## A ship sails from the open sea to alongside along its lane: every point
## of its way lies in a lane or in its berth's pocket, and it lies alongside
## at the end.
func _test_ships_sail_the_lanes() -> void:
	var sim := AreaPort.base()
	var water := {}
	for segment: int in sim.ship_lanes.segments:
		var lane: Dictionary = sim.ship_lanes.segments[segment]
		for cell in sim.ship_lanes.area(segment):
			water[cell] = true
	for cell in Marine.pocket(sim, 1):
		water[cell] = true
	var off := []
	var berthed := false
	for i in roundi(120.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for ship: PortSim.Ship in sim.ships:
			if ship.state == PortSim.Ship.State.ARRIVING:
				var at := Vector2i(Marine.point_along(ship.path, ship.sail).floor())
				if at not in water:
					off.append(at)
			berthed = berthed or ship.state == PortSim.Ship.State.WORKING
	_expect(berthed, true, "a ship sails in and berths")
	_expect(off, [], "every point of its way in lies on a lane or in the pocket")


## M8 step N: no lane crosses a breakwater or an island; a breakwater isn't
## built over a lane.
func _test_breakwaters_and_islands() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	_expect(sim.apply({"op": "build_breakwater", "from": Vector2i(30, 100), "to": Vector2i(30, 160)}), "", "a breakwater across the water")
	_expect(sim.areas.is_water(Vector2i(30, 120)), false, "its cells are no longer open water")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(0, 130), "to": Vector2i(60, 130), "type": "narrow"}).begins_with("A lane needs open water"), true, "a lane can't cross it")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(0, 200), "to": Vector2i(60, 200), "type": "narrow"}), "", "a lane clear of it is built")
	_expect(sim.apply({"op": "build_breakwater", "from": Vector2i(40, 180), "to": Vector2i(40, 220)}), "A ship lane runs here", "a breakwater can't go over a lane")
	_expect(sim.apply({"op": "build_breakwater", "from": Vector2i(30, 300), "to": Vector2i(37, 304)}), "Breakwaters run straight or at 45°", "breakwaters run straight or at 45°")
	_expect(sim.apply({"op": "remove_breakwater", "id": sim.areas.breakwater_at(Vector2i(30, 120))}), "", "a breakwater is taken out")
	_expect(sim.areas.is_water(Vector2i(30, 120)), true, "leaving open water")
	var estuary := PortSim.new(0, Content.base(), true)
	var island := Vector2i(50, 340)
	_expect(estuary.areas.is_water(island), false, "the estuary has an island off the coast at %s" % island)
	_expect(estuary.apply({"op": "build_ship_lane", "from": Vector2i(0, island.y), "to": Vector2i(island.x + 40, island.y), "type": "narrow"}).begins_with("A lane needs open water"), true, "a lane can't cross an island")


## M10 step 20: a lane may curve, no tighter than its type's
## min_radius_cells; a ship's way along it follows the curve, a lane split
## part-way keeps its curve in both pieces, and a narrow curved lane is
## booked once, for the whole time a ship is in it.
func _test_lanes_curve() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	var straight := sim.ship_lanes.footprint(Vector2i(10, 100), Vector2i(30, 100), "narrow")
	straight.sort()
	var rows: Array[Vector2i] = []
	for x in range(10, 31):
		for y in range(90, 111):
			rows.append(Vector2i(x, y))
	_expect(straight, rows, "a straight lane covers its cells and half_width rows either side, as before")
	var tight: float = sim.rules.water.lanes.narrow.min_radius_cells
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(10, 200), "to": Vector2i(50, 240), "type": "narrow", "control": Vector2(50.5, 200.5)}), "Too tight a bend: a narrow channel turns no tighter than %d m" % roundi(tight * Grid.CELL), "a bend tighter than the data allows is refused")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(10, 300), "to": Vector2i(10, 420), "type": "narrow", "control": Vector2(40.5, 360.5)}), "", "a gentle bend is built")
	var lane: int = sim.ship_lanes.segments.keys()[-1]
	var line := sim.ship_lanes.curve(lane)
	_expect(line.min_radius() >= tight, true, "it bends no tighter than %d cells (%.0f)" % [tight, line.min_radius()])
	_expect(sim.ship_lanes.area(lane).size() > 0 and sim.ship_lanes.cells(lane).all(func(c: Vector2i) -> bool: return Vector2(c).distance_to(line.point_at(line.nearest(Vector2(c) + Vector2(0.5, 0.5)))) < 1.5), true, "its line's cells run along the curve")
	# Split part-way by a lane ending on it: both pieces keep to the old curve.
	var apex := Vector2i(line.point_at(line.length / 2.0).floor())
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(0, apex.y), "to": apex, "type": "narrow"}), "", "a lane ending on it part-way")
	var pieces := sim.ship_lanes.segments.keys().filter(func(id: int) -> bool: return sim.ship_lanes.segments[id].type == "narrow" and id != sim.ship_lanes.segments.keys()[-1] and sim.ship_lanes.curve(id).length > 20.0)
	_expect(pieces.size(), 2, "splits it in two")
	var kept := true
	for id: int in pieces:
		var piece := sim.ship_lanes.curve(id)
		for k in 11:
			var p := piece.point_at(piece.length * k / 10.0)
			kept = kept and line.point_at(line.nearest(p)).distance_to(p) < 0.75
	_expect(kept, true, "and each piece keeps to the old curve")
	# A ship's way along the curve follows it, and books the narrow lane once.
	var ship := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], 0.0, 0, 0)
	ship.id = 99
	var ends: Array[int] = [sim.ship_lanes.segments[pieces[0]].a]
	var to: Array[int] = [sim.ship_lanes.segments[pieces[0]].b]
	var way := Marine._find(sim, "feeder", 0.0, ends, to)
	var piece := sim.ship_lanes.curve(pieces[0])
	_expect(way.size() > 3 and way.all(func(p: Vector2) -> bool: return piece.point_at(piece.nearest(p)).distance_to(p) < 0.01), true, "a ship's way lies on the curve (%d points)" % way.size())
	ship.path = way
	var windows := Marine._windows(sim, ship, 1, 0.0)
	_expect(windows.size(), 1, "it books the narrow lane once")
	if windows.size() == 1:
		_expect(is_equal_approx(windows[0].to - windows[0].from, Marine._length(way) * Grid.CELL / sim.rules.water.ship_speed), true, "for the whole time it sails along it")
