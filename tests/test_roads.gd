extends SceneTree

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")
## Headless tests for roads and areas on the 4 m grid.
## godot --headless --script res://tests/test_roads.gd

var _failures := 0


func _initialize() -> void:
	_test_segments()
	_test_lanes()
	_test_junctions()
	_test_routes()
	_test_editing()
	_test_sim_commands()
	_test_areas()
	_test_area_tool()
	_test_yard_layout()
	_test_apron_and_gate_layouts()
	_test_area_settings()
	_test_terminals()
	_test_unconnected_areas()
	_test_roads_keep_apart()
	_test_handovers()
	_test_machine_jobs()
	_test_area_stacks()
	_test_driveways()
	_test_apron_berths()
	_test_discharge()
	_test_delivery()
	_test_exports()
	_test_crane_keeps_tractors_busy()
	_test_exports_wait_for_calls()
	_test_lorries_use_the_gate_on_their_side()
	_test_two_way_gate()
	_test_lorry_gives_up()
	_test_stuck_tractor_moves_on()
	_test_following_a_box()
	_test_lorries_come_for_the_longest_due_box()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _test_segments() -> void:
	var net := RoadNet.new(Content.base().road_types, Content.base().junctions)
	_expect(net.add(Vector2i(0, 0), Vector2i(5, 0), "terminal_1_1"), "", "a straight road is built")
	_expect(net.add(Vector2i(5, 0), Vector2i(8, 3), "terminal_1_1"), "", "a 45° road is built")
	_expect(net.add(Vector2i(0, 0), Vector2i(2, 5), "terminal_1_1"), "", "a road at any other angle is built too (M10 12c)")
	_expect(net.add(Vector2i(4, 4), Vector2i(4, 4), "terminal_1_1"), "A road needs a length", "a road has a length")
	_expect(net.nodes.size(), 4, "roads meeting at a point share its node")
	# Drawn east along grid line y = 0, its two lanes stand on rows -1 and 0,
	# a cell for each step between points 0 and 5.
	var ground := net.ground(1)
	ground.sort()
	_expect(ground, [Vector2i(0, -1), Vector2i(0, 0), Vector2i(1, -1), Vector2i(1, 0), Vector2i(2, -1), Vector2i(2, 0), Vector2i(3, -1), Vector2i(3, 0), Vector2i(4, -1), Vector2i(4, 0)] as Array[Vector2i], "a straight road stands on a cell a lane for each step along it")
	_expect(RoadNet.line(Vector2i(3, 3), Vector2i(3, 0)), [Vector2i(3, 3), Vector2i(3, 2), Vector2i(3, 1), Vector2i(3, 0)] as Array[Vector2i], "a line runs from its first end")


func _test_lanes() -> void:
	var net := RoadNet.new(Content.base().road_types, Content.base().junctions)
	_expect(net.add(Vector2i(0, 0), Vector2i(3, 0), "dirt_track"), "Unknown road type \"dirt_track\"", "unknown road types are refused")
	var lanes := RoadCurve.lanes(Content.base().road_types.terminal_2_2)
	_expect(lanes.map(func(l: Dictionary) -> bool: return l.forward), [false, false, true, true], "a 2+2 road: backward lanes on the left, forward on the right")
	_expect(RoadCurve.lanes(Content.base().road_types.one_way).all(func(l: Dictionary) -> bool: return l.forward), true, "a one-way road's lanes all run forward")
	_expect(Content.base().road_types.tractor_lane.lorries, false, "the tractor lane refuses lorries")


func _test_junctions() -> void:
	var net := RoadNet.new(Content.base().road_types, Content.base().junctions)
	net.add(Vector2i(0, 5), Vector2i(14, 5), "terminal_1_1")
	_expect(net.add(Vector2i(5, 0), Vector2i(5, 10), "terminal_1_1"), "", "a road may cross another")
	var crossing := _node(net, Vector2i(5, 5))
	_expect(net.degree(crossing), 4, "a crossing makes a 4-way node")
	_expect(net.segments.size(), 4, "both roads split at the crossing")
	_expect(net.add(Vector2i(7, 5), Vector2i(7, 9), "terminal_1_1"), "Too close to a junction: a road needs room between its junctions", "a T two cells from the crossing leaves no lane between them (M10 12c)")
	_expect(net.add(Vector2i(10, 5), Vector2i(10, 9), "terminal_1_1"), "", "a road may end on another")
	_expect(net.degree(_node(net, Vector2i(10, 5))), 3, "a T join makes a 3-way node")
	_expect(net.add(Vector2i(2, 5), Vector2i(4, 5), "terminal_1_1"), "A road already runs here", "a road can't run along another")
	_expect(net.add(Vector2i(14, 5), Vector2i(14, 0), "terminal_1_1"), "", "a road may start at another's end")
	_expect(net.degree(_node(net, Vector2i(14, 5))), 2, "a bend is a 2-way node")
	for cross: Array in [[Vector2i(0, 5), Vector2i(5, 0), Vector2(2.5, 2.5)], [Vector2i(0, 6), Vector2i(6, 0), Vector2(3, 3)]]:
		var diagonal := RoadNet.new(Content.base().road_types, Content.base().junctions)
		diagonal.add(Vector2i(0, 0), Vector2i(6, 6), "terminal_1_1")
		_expect(diagonal.add(cross[0], cross[1], "terminal_1_1"), "", "45° roads crossing at %s are built, on a grid point or between (M10 12c)" % cross[2])
		var at: Array = diagonal.nodes.keys().filter(func(n: int) -> bool: return diagonal.nodes[n].distance_to(cross[2]) < 0.01)
		_expect(diagonal.degree(at[0]) if not at.is_empty() else 0, 4, "and meet at a 4-way node at %s" % cross[2])
	var lengths := 0
	for id: int in net.segments:
		lengths += RoadNet.cells_long(net.curve(id).length)
	_expect(lengths, 14 + 10 + 4 + 5, "splitting keeps every cell of road")


## Routes on the lane network: round a bend, back by a dead end's turn
## back, forward only on a one-way road, lorries off a tractor lane, and
## across a grid of 2+2 roads. (A lane change on the way is step 9's.)
func _test_routes() -> void:
	var net := RoadNet.new(Content.base().road_types, Content.base().junctions)
	net.add(Vector2i(0, 0), Vector2i(10, 0), "terminal_1_1")
	net.add(Vector2i(10, 0), Vector2i(10, 10), "terminal_1_1")
	# Keeping right, the eastbound lane runs along y = 0.5 and the southbound down x = 9.5.
	var bend := _lane_route(net, Vector2(1, 0.5), Vector2(9.5, 9), true)
	_expect(bend.is_empty(), false, "a route runs round a bend")
	var back := _lane_route(net, Vector2(4, 0.5), Vector2(2, -0.5), true)
	_expect(back.is_empty(), false, "the other way is reached by the dead end's turn back")
	var one_way := RoadNet.new(Content.base().road_types, Content.base().junctions)
	one_way.add(Vector2i(0, 0), Vector2i(10, 0), "one_way")
	_expect(_lane_route(one_way, Vector2(1, 0.5), Vector2(9, 0.5), true).is_empty(), false, "a one-way road is driven forward")
	var one_way_lanes := LaneNetwork.new(one_way, Content.base().junctions).pieces.values()
	_expect(one_way_lanes.all(func(p: Dictionary) -> bool: return p.points[-1].x > p.points[0].x), true, "a one-way road's lanes all run east, the way it was drawn, so it can't be driven backwards")
	var tractors := RoadNet.new(Content.base().road_types, Content.base().junctions)
	tractors.add(Vector2i(0, 5), Vector2i(10, 5), "tractor_lane")
	_expect(_lane_route(tractors, Vector2(1, 5.5), Vector2(9, 5.5), true), [] as Array[int], "lorries can't use the tractor lane")
	_expect(_lane_route(tractors, Vector2(1, 5.5), Vector2(9, 5.5), false).is_empty(), false, "tractors can")
	var grid := RoadNet.new(Content.base().road_types, Content.base().junctions)
	for i in 3:
		grid.add(Vector2i(0, i * 10), Vector2i(30, i * 10), "terminal_2_2")
		grid.add(Vector2i(i * 10 + 5, -5), Vector2i(i * 10 + 5, 25), "terminal_2_2")
	_expect(_lane_route(grid, Vector2(1, 0.5), Vector2(29, 20.5), true).is_empty(), false, "a route runs across a road grid")


func _test_editing() -> void:
	_expect(RoadNet.snap(Vector2i(0, 0), Vector2i(10, 2)), Vector2i(10, 0), "a nearly level drag snaps straight")
	_expect(RoadNet.snap(Vector2i(0, 0), Vector2i(1, -9)), Vector2i(0, -9), "a nearly upright drag snaps straight")
	_expect(RoadNet.snap(Vector2i(0, 0), Vector2i(6, 4)), Vector2i(5, 5), "an in-between drag snaps to 45°")
	_expect(RoadNet.snap(Vector2i(0, 0), Vector2i(-4, 6)), Vector2i(-5, 5), "45° snapping keeps the drag's direction")
	# A road's lanes lie evenly either side of its line, so it covers the same
	# cells drawn either way, and they centre on the line.
	var types: Dictionary = Content.base().road_types
	var shapes := RoadNet.new(types, Content.base().junctions)
	for type: String in types:
		for ends: Array in [[Vector2(10, 70), Vector2(30, 70)], [Vector2(20, 60), Vector2(20, 80)], [Vector2(10, 60), Vector2(30, 80)]]:
			var there := shapes.footprint(ends[0], ends[1], type)
			var back := shapes.footprint(ends[1], ends[0], type)
			there.sort()
			back.sort()
			_expect(there, back, "a %s road from %s to %s covers the same cells drawn either way" % [type, ends[0], ends[1]])
			var middle := Vector2.ZERO
			for cell: Vector2i in there:
				middle += Vector2(cell) + Vector2(0.5, 0.5)
			middle /= there.size()
			_expect(middle.distance_to((ends[0] + ends[1]) / 2.0) < 0.001, true, "a %s road from %s to %s centres on its line (%s)" % [type, ends[0], ends[1], middle])
	# A two-way road covers the same cells whichever way it is dragged, so
	# pieces built from either end, or from either side of a road, line up.
	var cells_of := func(port: PortSim, segment: int) -> Array:
		var found := port.roads.ground(segment)
		found.sort()
		return found
	for type: String in ["terminal_1_1", "terminal_2_2"]:
		var east := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
		east.apply({"op": "build_road", "from": Vector2i(200, 90), "to": Vector2i(210, 90), "type": type})
		var west := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
		west.apply({"op": "build_road", "from": Vector2i(210, 90), "to": Vector2i(200, 90), "type": type})
		_expect(cells_of.call(west, 1), cells_of.call(east, 1), "a %s road covers the same cells dragged either way" % type)
		var columns := []
		for start: Vector2i in [Vector2i(205, 80), Vector2i(205, 100)]:
			var stubs := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
			stubs.apply({"op": "build_road", "from": Vector2i(200, 90), "to": Vector2i(210, 90), "type": type})
			stubs.apply({"op": "build_road", "from": start, "to": stubs.roads.snap_drag(Vector2(start), Vector2(205, 90), type).point, "type": type})
			var cols := {}
			for cell: Vector2i in stubs.roads.ground(3):
				cols[cell.x] = true
			columns.append(cols.keys())
			columns[-1].sort()
		_expect(columns[0], columns[1], "%s stubs snapped onto a road from either side line up" % type)
		# Drawn back to a road's free end, a road carries on that road's way.
		var on := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
		on.apply({"op": "build_road", "from": Vector2i(200, 90), "to": Vector2i(210, 90), "type": type})
		on.apply({"op": "build_road", "from": Vector2i(220, 90), "to": Vector2i(210, 90), "type": type})
		var in_line := {}
		for segment: int in on.roads.segments:
			for cell: Vector2i in on.roads.ground(segment):
				in_line[cell.y] = true
		_expect(in_line.size(), on.rules.road_types[type].forward + on.rules.road_types[type].backward, "a %s road drawn back to a road's end runs on in line" % type)
		var bend := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
		bend.apply({"op": "build_road", "from": Vector2i(200, 90), "to": Vector2i(210, 90), "type": type})
		bend.apply({"op": "build_road", "from": Vector2i(210, 80), "to": Vector2i(210, 90), "type": type})
		_expect(_lane_route(bend.roads, Vector2(201, 90.5), Vector2(210.5, 81), true).is_empty() or _lane_route(bend.roads, Vector2(209.5, 81), Vector2(201, 89.5), true).is_empty(), false, "a %s road drawn back to a road's end turns there both ways" % type)
	var one_way := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
	one_way.apply({"op": "build_road", "from": Vector2i(210, 90), "to": Vector2i(200, 90), "type": "one_way"})
	_expect(one_way.roads.nodes[one_way.roads.segments[1].a], Vector2(210, 90), "a one-way road runs the way it was dragged")
	_expect(RoadNet.length(Vector2i(0, 0), Vector2i(-5, 5)), 5, "a road's length is its run in cells")
	var net := RoadNet.new(Content.base().road_types, Content.base().junctions)
	net.add(Vector2i(0, 5), Vector2i(10, 5), "terminal_1_1")
	_expect(net.add_error(Vector2i(2, 5), Vector2i(4, 5), "terminal_1_1"), "A road already runs here", "add_error gives add's refusal")
	_expect(net.add_error(Vector2i(5, 0), Vector2i(5, 10), "terminal_1_1"), "", "add_error passes a road add would build")
	_expect(net.segments.size(), 1, "add_error changes nothing")
	net.add(Vector2i(5, 0), Vector2i(5, 10), "terminal_1_1")
	var copy := RoadNet.from_dict(net.to_dict(), net.types, net.junctions)
	_expect(copy.to_dict(), net.to_dict(), "roads round-trip through a dictionary")
	_expect(net.segment_at(Vector2i(8, 4)), net.segment_at(Vector2i(8, 5)), "both lanes of a road find its segment")
	_expect(net.segment_at(Vector2i(8, 7)), 0, "a cell off every road finds none")
	var version := net.version
	net.remove(net.segment_at(Vector2i(5, 1)))
	_expect(net.version > version, true, "removing a road bumps the version")
	_expect(net.nodes.values().has(Vector2(5, 0)), false, "a node left with no road goes")
	_expect(net.degree(_node(net, Vector2i(5, 5))), 3, "the crossing becomes a T")


func _test_sim_commands() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
	var money := sim.money
	var upkeep := sim.daily_upkeep()
	var cost: int = sim.rules.road_types.terminal_2_2.cost_per_cell
	_expect(sim.apply({"op": "build_road", "from": Vector2i(110, 10), "to": Vector2i(130, 10), "type": "terminal_2_2"}), "", "a road is built by command")
	_expect(money - sim.money, 20 * cost, "a road costs its length in cells")
	_expect(sim.daily_upkeep() - upkeep, roundi(20 * sim.rules.road_types.terminal_2_2.upkeep_per_cell), "roads add their upkeep")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(115, 10), "to": Vector2i(125, 10), "type": "terminal_1_1"}), "A road already runs here", "a refused road")
	_expect(money - sim.money, 20 * cost, "costs nothing")
	_expect(_lane_route(sim.roads, Vector2(111, 10.5), Vector2(129, 10.5), true).is_empty(), false, "the sim routes on its roads")
	var poor := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
	poor.ledger.post("construction", -poor.money)
	_expect(poor.apply({"op": "build_road", "from": Vector2i(110, 10), "to": Vector2i(130, 10), "type": "terminal_2_2"}), "Not enough money", "roads need the money")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(60, 40), "to": Vector2i(90, 40), "type": "terminal_1_1"}), "Roads can't be built on water", "a road can't run out into the sea")
	_expect(sim.apply({"op": "remove_road", "segment": 99}), "No road there", "removing a missing road is refused")
	_expect(sim.apply({"op": "remove_road", "segment": 1}), "", "a road is removed by command")
	_expect(sim.roads.segments.is_empty(), true, "and is gone")
	_test_change_road()


func _test_change_road() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
	sim.apply({"op": "build_road", "from": Vector2i(110, 10), "to": Vector2i(130, 10), "type": "terminal_1_1"})
	sim.apply({"op": "build_road", "from": Vector2i(120, 0), "to": Vector2i(120, 10), "type": "terminal_1_1"})
	var segment := sim.roads.segment_at(Vector2i(112, 10))
	var before := sim.state_hash()
	_expect(sim.change_road_error(segment, "terminal_2_2"), "", "a road can change to a wider type")
	_expect(sim.state_hash(), before, "checking a change changes nothing")
	_expect(sim.apply({"op": "change_road", "segment": segment, "type": "terminal_1_1"}), "This road is already a %s" % sim.rules.road_types.terminal_1_1.name, "a change to the same type is refused")
	_expect(sim.apply({"op": "change_road", "segment": 99, "type": "terminal_2_2"}), "No road there", "changing a missing road is refused")
	var money := sim.money
	_expect(sim.apply({"op": "change_road", "segment": segment, "type": "terminal_2_2"}), "", "a road changes type by command")
	_expect(sim.roads.segments[segment].type, "terminal_2_2", "it keeps its segment and takes the new type")
	_expect(money - sim.money, 10 * sim.rules.road_types.terminal_2_2.cost_per_cell, "and costs the new type's price for its length")
	_expect(sim.roads.footprint(Vector2i(110, 10), Vector2i(120, 10), "terminal_2_2").all(func(c: Vector2i) -> bool: return sim.roads.segment_at(c) != 0), true, "its lanes are the new type's")
	_expect(_lane_route(sim.roads, Vector2(111, 10.5), Vector2(119.5, 1), true).is_empty(), false, "the junction still joins")
	sim.apply({"op": "build_road", "from": Vector2i(140, 12), "to": Vector2i(160, 12), "type": "terminal_1_1"})
	sim.apply({"op": "build_road", "from": Vector2i(140, 10), "to": Vector2i(160, 10), "type": "terminal_1_1"})
	_expect(sim.apply({"op": "change_road", "segment": sim.roads.segment_at(Vector2i(150, 10)), "type": "terminal_2_2"}), "A road already runs here", "a change that would run into a road beside it is refused")


func _test_areas() -> void:
	var rules := RandomPort.strait()
	var net := RoadNet.new(rules.road_types, rules.junctions)
	var areas := Areas.new(rules.area_types, net, Coast.of(rules.maps[rules.map], rules.site))
	# Drawn south down grid line x = 86, so its right is west, towards the sea
	# (x < 75). The 1+1 lanes are x = 85 and 86.
	net.add(Vector2i(86, 100), Vector2i(86, 201), "terminal_1_1")
	var road := 1
	_expect(areas.add("quay_apron", road, 1, 0, 40), "", "an apron between the road and the sea is built")
	_expect(areas.cells(1).size(), 41 * rules.area_types.quay_apron.depth, "an area covers its length times its type's depth")
	_expect(areas.cells(1).all(func(c: Vector2i) -> bool: return c.x >= 75 and c.x <= 84), true, "an apron reaches from the road's edge to the water")
	_expect(areas.area_at(Vector2i(80, 120)), 1, "a cell finds its area")
	_expect(areas.add("yard_block", road, -1, 0, 30), "", "a yard block is built on the road's other side")
	_expect(areas.cells(2).all(func(c: Vector2i) -> bool: return c.x >= 87 and c.x < 87 + rules.area_types.yard_block.depth), true, "it starts just past the road's last lane")
	_expect(areas.add("depot", road, -1, 20, 40), "Something is already built here", "areas can't overlap")
	_expect(areas.add("yard_block", road, -1, 31, 35), "A yard block is at least 40 m long", "areas have a shortest length")
	_expect(areas.add("yard_block", 99, 1, 0, 20), "Areas are built along a road's edge", "an area needs a road")
	_expect(areas.add("yard_block", road, -1, 90, 120), "Areas are built along a road's edge", "an area stays along its road")
	_expect(areas.add("yard_block", road, 0, 50, 70), "Areas are built along a road's edge", "an area is on one side of its road")
	_expect(areas.add("garden", road, -1, 50, 70), "Unknown area type \"garden\"", "unknown area types are refused")
	net.add(Vector2i(86, 180), Vector2i(111, 180), "terminal_1_1")
	var south := net.segment_at(Vector2i(85, 190))
	# Its first cell is the junction, beside the new road's lanes on row 180.
	_expect(areas.add("yard_block", south, -1, 0, RoadNet.cells_long(net.curve(south).length) - 1), "Something is already built here", "an area can't reach into a joining road")
	_expect(areas.add("yard_block", south, -1, 1, RoadNet.cells_long(net.curve(south).length) - 1), "", "an area is built on a road's split end")
	var north := net.segment_at(Vector2i(85, 150))
	_expect(areas.add("depot", north, -1, 60, RoadNet.cells_long(net.curve(north).length) - 1), "Something is already built here", "an area can't cover a road")
	var inland := RoadNet.new(rules.road_types, rules.junctions)
	var inland_areas := Areas.new(rules.area_types, inland, Coast.of(rules.maps[rules.map], rules.site))
	inland.add(Vector2i(96, 100), Vector2i(96, 201), "terminal_1_1")
	_expect(inland_areas.add("quay_apron", 1, 1, 0, 40), "A quay apron reaches at most 64 m from its road to the water", "an apron must reach the water")
	var wide := RoadNet.new(rules.road_types, rules.junctions)
	var wide_areas := Areas.new(rules.area_types, wide, Coast.of(rules.maps[rules.map], rules.site))
	# The sea ends at x = 75 and the area starts at x = 89, so the apron is 15 rows deep.
	wide.add(Vector2i(91, 100), Vector2i(91, 201), "terminal_1_1")
	_expect(wide_areas.add("quay_apron", 1, 1, 0, 40), "", "an apron reaches out to the water from a road further in")
	_expect(wide_areas.depth_of(wide_areas.list[1]), 15, "it is as deep as the gap to the water")
	_expect(_grid(wide_areas, wide_areas.layout(1).edge).all(func(c: Vector2i) -> bool: return c.x == 75), true, "its quay edge is at the water")
	var coast := RoadNet.new(rules.road_types, rules.junctions)
	var coast_areas := Areas.new(rules.area_types, coast, Coast.of(rules.maps[rules.map], rules.site))
	coast.add(Vector2i(79, 100), Vector2i(79, 201), "terminal_1_1")
	_expect(coast_areas.add("yard_block", 1, 1, 0, 40), "Areas can't be built on water", "areas stay out of the sea")
	coast.add(Vector2i(596, 100), Vector2i(596, 201), "terminal_1_1")
	_expect(coast_areas.add("yard_block", 2, -1, 0, 40), "Areas must stay on the site", "areas stay on the site")


func _test_area_tool() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
	sim.apply({"op": "build_road", "from": Vector2i(101, 100), "to": Vector2i(101, 161), "type": "terminal_2_2"})
	# Drawn south down grid line x = 101: right is west. Forward lanes are x = 100 and 99,
	# backward 101 and 102 (left, east), so areas start at x = 98 to the west and x = 103 to the east.
	_expect(sim.areas.attach(Vector2i(97, 110), "yard_block"), {"segment": 1, "side": 1, "index": 10}, "a drag beside a road attaches to its edge")
	_expect(sim.areas.attach(Vector2i(92, 110), "yard_block"), {"segment": 1, "side": 1, "index": 10}, "anywhere within the area's depth attaches")
	_expect(sim.areas.attach(Vector2i(103, 125), "depot"), {"segment": 1, "side": -1, "index": 25}, "the other side attaches the other way")
	_expect(sim.areas.attach(Vector2i(102, 125), "depot"), {}, "a lane cell attaches nowhere")
	_expect(sim.areas.attach(Vector2i(80, 110), "yard_block"), {}, "a drag far from any road attaches nowhere")
	_expect(sim.areas.index_near(1, Vector2i(90, 140)), 40, "a drag's far end finds the nearest cell along the road")
	var money := sim.money
	var upkeep := sim.daily_upkeep()
	var block: Dictionary = sim.rules.area_types.yard_block
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": 1, "from": 10, "to": 29}), "", "a yard block is built by command")
	_expect(money - sim.money, 20 * block.depth * block.cost_per_cell, "an area costs its cells")
	_expect(sim.daily_upkeep() - upkeep, roundi(20 * block.depth * block.upkeep_per_cell), "areas add their upkeep")
	sim.apply({"op": "build_road", "from": Vector2i(101, 120), "to": Vector2i(121, 120), "type": "terminal_1_1"})
	_expect(sim.areas.cells(1).size(), 20 * block.depth, "a road joining later doesn't move the area")
	_expect(sim.apply({"op": "remove_area", "id": 7}), "No area there", "removing a missing area is refused")
	_expect(sim.apply({"op": "remove_area", "id": 1}), "", "an area is removed by command")
	var diagonal := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
	diagonal.apply({"op": "build_road", "from": Vector2i(100, 100), "to": Vector2i(130, 130), "type": "terminal_1_1"})
	_expect(diagonal.apply({"op": "build_area", "type": "depot", "segment": 1, "side": -1, "from": 0, "to": 10}), "", "an area is built along a 45° road")
	var rows := diagonal.areas.cells(1)
	_expect(rows.all(func(c: Vector2i) -> bool: return diagonal.roads.segment_at(c) == 0), true, "and takes its direction without covering it")


func _test_yard_layout() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
	sim.apply({"op": "build_road", "from": Vector2i(100, 100), "to": Vector2i(161, 100), "type": "terminal_1_1"})
	# Drawn east, right is south: the block starts on row 101 and runs 31 cells east.
	sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": 1, "from": 0, "to": 30})
	var depth: int = sim.rules.area_types.yard_block.depth
	var layout := sim.areas.layout(1)
	_expect(layout.buffer.size(), 31, "the buffer strip runs the block's whole length")
	_expect(_grid(sim.areas, layout.buffer).all(func(c: Vector2i) -> bool: return c.y == 101), true, "beside the road")
	_expect(layout.slots.size(), 5, "31 cells hold 10 bays of 3, so 5 handover slots of two bays")
	_expect(layout.slots.all(func(s: Array) -> bool: return s.size() == AreaLayout.SLOT and _grid(sim.areas, s).all(func(c: Vector2i) -> bool: return c.y == 102)), true, "each slot is two bays of the truck lane, one row in")
	_expect(layout.stacks.size(), 10 * (depth - 2), "a stack per bay in each row behind the truck lane")
	var used := {}
	var overlap := false
	for cells: Array in [layout.buffer] + layout.slots + layout.stacks.map(func(s: Dictionary) -> Array: return s.cells):
		for cell: Vector2i in _grid(sim.areas, cells):
			overlap = overlap or cell in used
			used[cell] = true
	_expect(overlap, false, "no cell is used twice")
	_expect(used.keys().all(func(c: Vector2i) -> bool: return c in sim.areas.cells(1)), true, "every part lies inside the block")
	_expect(sim.areas.layout(1), layout, "the same block lays out the same every time")


func _test_apron_and_gate_layouts() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	# Drawn south down grid line x = 86, lanes at x = 85 and 86, its right (west)
	# side reaches the sea: the apron covers x = 84 down to 75.
	sim.apply({"op": "build_road", "from": Vector2i(86, 100), "to": Vector2i(86, 161), "type": "terminal_1_1"})
	_expect(sim.apply({"op": "build_area", "type": "quay_apron", "segment": 1, "side": 1, "from": 0, "to": 29}), "", "an apron is built on the coast")
	var depth: int = sim.rules.area_types.quay_apron.depth
	var apron := sim.areas.layout(1)
	var on := func(part: Array, x: int) -> bool: return _grid(sim.areas, part).all(func(c: Vector2i) -> bool: return c.x == x)
	_expect(on.call(apron.buffer, 84), true, "the apron's buffer strip is beside the road")
	_expect(on.call(apron.rails[0], 83) and on.call(apron.rails[1], 76), true, "crane rails run landside and waterside")
	_expect(on.call(apron.edge, 75), true, "the quay edge is on the water")
	_expect(apron.lanes.size() == 1 and on.call(apron.lanes[0], 82), true, "a through lane runs beside the landside rail")
	_expect(apron.slots.size() == 5 and apron.slots.all(func(s: Array) -> bool: return on.call(s, 81)), true, "a two-bay handover slot in the working lane under the cranes")
	_expect(apron.hatches.size(), 30 * (depth - 6), "hatch covers lie between the working lane and the waterside rail")
	_expect(_covers_once(sim.areas, apron, sim.areas.cells(1)), true, "the apron's parts cover it with no cell used twice")
	_expect(sim.apply({"op": "build_area", "type": "gate", "segment": 1, "side": -1, "from": 0, "to": 14}), "", "a gate is built across the road")
	var gate_depth: int = sim.rules.area_types.gate.depth
	var gate := sim.areas.layout(2)
	_expect(gate.lanes.size(), gate_depth - 2, "a gate's lanes fill the rows between its buffer strip and kerb")
	_expect(gate.slots.size(), gate.lanes.size(), "one booth slot per lane")
	_expect(gate.slots.all(func(s: Array) -> bool: return _grid(sim.areas, s)[0].y == 104), true, "booths are two bays centred on the gate")
	_expect(gate.lanes.all(func(l: Array) -> bool: return l.size() == 15), true, "gate lanes run the gate's length")
	_expect(sim.apply({"op": "build_area", "type": "gate_small", "segment": 1, "side": -1, "from": 16, "to": 30}), "", "a small gate is built")
	_expect(sim.areas.layout(3).lanes.size(), 2, "a small gate has 2 lanes")
	_expect(sim.apply({"op": "build_area", "type": "gate_large", "segment": 1, "side": -1, "from": 32, "to": 46}), "", "a large gate is built")
	_expect(sim.areas.layout(4).lanes.size(), 6, "a large gate has 6 lanes, each with its booth")
	_expect(sim.areas.layout(4).slots.size(), 6, "so 6 lorries are checked at once")
	_expect(sim.areas.kind_of(sim.areas.list[4]), "gate", "every size is a gate")
	_expect(sim.areas.list[2].settings, {"level": "manual", "slots_per_hour": 0}, "a new gate has manual booths and takes no bookings")
	_expect(AreaFlow.gate_throughput(sim, 2), 4 * 60.0 / sim.rules.gate_levels.manual.minutes, "throughput is lanes times lorries a booth checks an hour")
	var upkeep := sim.daily_upkeep()
	sim.teu_handled = int(sim.rules.milestones.terminal.teu)
	sim._check_milestones()
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"level": "ocr"}}), "", "past the terminal milestone, a gate is upgraded in place to OCR")
	_expect(AreaFlow.gate_minutes(sim, 2), sim.rules.gate_levels.ocr.minutes, "an OCR portal checks a lorry faster")
	_expect(sim.daily_upkeep() - upkeep, 4 * sim.rules.gate_levels.ocr.upkeep_per_lane, "and costs upkeep per lane")
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"level": "teleporter"}}), "Unknown gate level: teleporter", "unknown levels are refused")
	_expect(sim.apply({"op": "set_area", "id": 1, "settings": {"level": "ocr"}}), "A quay apron has no level setting", "only gates have a level")
	var locked := AreaPort.terminal(30)
	_expect(locked.apply({"op": "set_area", "id": 2, "settings": {"level": "automated"}}), locked.lock_error("automated"), "automated gates wait for their milestone")


func _test_area_settings() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	sim.apply({"op": "build_road", "from": Vector2i(86, 100), "to": Vector2i(86, 161), "type": "terminal_1_1"})
	sim.apply({"op": "build_area", "type": "quay_apron", "segment": 1, "side": 1, "from": 0, "to": 29})
	sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": -1, "from": 0, "to": 29})
	sim.apply({"op": "build_area", "type": "gate", "segment": 1, "side": -1, "from": 35, "to": 50})
	_expect(sim.areas.list[2].settings, {"role": "import", "gear": "reach_stacker", "lines": []}, "a new yard block starts as an import block with reach stackers")
	var line: String = sim.rules.lines.keys()[0]
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"role": "export", "lines": [line]}}), "", "a yard block's role and lines are set")
	_expect(sim.areas.list[2].settings, {"role": "export", "gear": "reach_stacker", "lines": [line]}, "unset rules stay as they were")
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"role": "reefer"}}), "Unlocked at milestone 2: %d TEU across the quay" % sim.rules.milestones.terminal.teu, "reefer blocks wait for the terminal milestone")
	sim.teu_handled = int(sim.rules.milestones.terminal.teu)
	sim._check_milestones()
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"role": "reefer"}}), "", "then reefer is a yard role")
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"role": "transit"}}), "Unknown yard role: transit", "unknown roles are refused")
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"gear": "crane_on_legs"}}), "Unknown yard gear: crane_on_legs", "unknown gear is refused")
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"lines": ["Nobody Lines"]}}), "Line priority lists known shipping lines", "unknown lines are refused")
	_expect(sim.apply({"op": "set_area", "id": 1, "settings": {"role": "export"}}), "A quay apron has no role setting", "an apron takes no role")
	_expect(sim.apply({"op": "set_area", "id": 1, "settings": {"lines": [line]}}), "", "an apron favours lines")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"lines": [line]}}), "A gate has no lines setting", "a gate has no rules")
	_expect(sim.apply({"op": "set_area", "id": 9, "settings": {}}), "No area there", "a missing area is refused")
	var locked := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
	locked.apply({"op": "build_road", "from": Vector2i(101, 100), "to": Vector2i(101, 161), "type": "terminal_1_1"})
	locked.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": -1, "from": 0, "to": 15})
	_expect(locked.apply({"op": "set_area", "id": 1, "settings": {"gear": "rtg"}}), locked.lock_error("rtg"), "RTGs wait for their milestone")


func _test_terminals() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	sim.apply({"op": "build_road", "from": Vector2i(86, 100), "to": Vector2i(86, 201), "type": "terminal_1_1"})
	sim.apply({"op": "build_area", "type": "quay_apron", "segment": 1, "side": 1, "from": 0, "to": 29})
	_expect(sim.areas.list[1].terminal, 0, "an area on unpainted ground is in no terminal")
	sim.apply({"op": "paint_terminal", "cells": sim.areas.cells(1), "terminal": -1})
	_expect(sim.areas.list[1].terminal, 1, "painting it makes Terminal 1")
	_expect(sim.areas.terminal_error(1), "Terminal 1 needs a gate", "a terminal with only an apron can't take contracts")
	sim.apply({"op": "build_area", "type": "gate", "segment": 1, "side": -1, "from": 80, "to": 95})
	sim.apply({"op": "paint_terminal", "cells": sim.areas.cells(2), "terminal": -1})
	_expect(sim.areas.terminal_error(2), "Terminal 2 needs a quay apron", "a terminal needs an apron too")
	sim.apply({"op": "paint_terminal", "cells": sim.areas.cells(2), "terminal": 1})
	_expect(sim.areas.terminal_error(1), "", "painted into one terminal, a gate and an apron take contracts")
	_expect(sim.areas.terminals.has(2), false, "a terminal painted over entirely goes")


func _test_unconnected_areas() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	sim.apply({"op": "build_road", "from": Vector2i(101, 100), "to": Vector2i(101, 141), "type": "terminal_1_1"})
	sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": -1, "from": 0, "to": 29})
	sim.apply({"op": "paint_terminal", "cells": sim.areas.cells(1), "terminal": -1})
	_expect(sim.areas.idle_reason(1), "", "a yard block along its road works")
	var lines := Inspect.describe(sim, Inspect.pick(sim, sim.areas.cells(1)[5]))
	# 10 bays by 6 rows of stacks, 4 high with reach stackers; no machines before the first tick.
	_expect(lines, ["Yard block", "Terminal 1", "Terminal 1 needs a quay apron", "Import block, worked by reach stackers", "0 of 480 TEU (0%), 0 machines", "Working"] as Array[String], "inspecting an area shows its type, its terminal and what that lacks, its rules, its fill and state")
	_expect(sim.areas.along(1, sim.areas.cell_at(1, 7, 3)), 7, "a cell's place along an area, from any row")
	_expect(sim.areas.along(1, Vector2i(5, 5)), -1, "and none off it")
	sim.apply({"op": "remove_road", "segment": 1})
	_expect(sim.areas.idle_reason(1), "No road runs along this yard block", "with its road gone it does no work, and says why")
	_expect(Inspect.describe(sim, {"area": 1})[-1], "No road runs along this yard block", "the inspect panel shows why")
	sim.apply({"op": "build_road", "from": Vector2i(101, 120), "to": Vector2i(101, 161), "type": "terminal_1_1"})
	_expect(sim.areas.idle_reason(1), "", "a road along part of its front reconnects it")
	_expect(Inspect.describe(sim, {"area": 9}), [] as Array[String], "an area that went shows nothing")


## A road may meet or cross another, but its lanes may not lie over another
## road's lanes along the way, nor over an area.
func _test_roads_keep_apart() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	_expect(sim.apply({"op": "build_road", "from": Vector2i(100, 100), "to": Vector2i(141, 100), "type": "terminal_1_1"}), "", "a road")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(100, 101), "to": Vector2i(141, 101), "type": "terminal_1_1"}), "A road already runs here", "a road one row over would share a lane")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(100, 102), "to": Vector2i(141, 102), "type": "terminal_1_1"}), "", "a road whose lanes run beside it is built")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(121, 90), "to": Vector2i(121, 111), "type": "terminal_2_2"}), "Too close to a junction: a road needs room between its junctions", "a road crossing both is refused: its two junctions would leave it no lane between them (M10 12c)")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(131, 80), "to": Vector2i(131, 99), "type": "terminal_1_1"}), "", "and one ending on the first in a T")
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": sim.roads.segment_at(Vector2i(110, 100)), "side": -1, "from": 0, "to": 15}), "", "a yard block along the first road")
	var block := sim.areas.cells(1)
	_expect(sim.apply({"op": "build_road", "from": Vector2i(block[20].x + 1, 60), "to": Vector2i(block[20].x + 1, 97), "type": "terminal_1_1"}), "Something is already built here", "a road can't run over an area")
	# An area beside a tractor lane joins the all-vehicle graph only, with no error logged.
	_expect(sim.apply({"op": "build_road", "from": Vector2i(200, 100), "to": Vector2i(241, 100), "type": "tractor_lane"}), "", "a tractor lane")
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": sim.roads.segment_at(Vector2i(210, 100)), "side": -1, "from": 0, "to": 15}), "", "a yard block beside it")
	_expect(_route(sim, Vector3i(0, 200, 100), AreaFlow._stand(sim, 2, 0), false).is_empty(), false, "tractors route into it")


func _test_handovers() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	sim.apply({"op": "build_road", "from": Vector2i(101, 100), "to": Vector2i(101, 141), "type": "terminal_1_1"})
	# 12 cells: 4 bays, so 2 slots of two bays and room for 4 in the buffer strip.
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": -1, "from": 0, "to": 11}), "", "a 4-bay yard block is built")
	var block := 1
	var handovers := Handovers.new(sim.areas, AreaLayout.BAY)
	var got := []
	for id in range(1, 11):
		got.append(handovers.arrive(block, id))
	_expect(got, ["slot", "slot", "buffer", "buffer", "buffer", "buffer", "road", "road", "road", "road"], "vehicles take slots, then the buffer strip, then queue on the road")
	_expect(handovers.waiting(block), {"buffer": [3, 4, 5, 6], "road": [7, 8, 9, 10]}, "a full block shows a road queue")
	handovers.leave(block, 2)
	_expect(handovers.slot_of(block, 3), 1, "a freed slot goes to the first vehicle in the buffer")
	_expect(handovers.waiting(block), {"buffer": [4, 5, 6, 7], "road": [8, 9, 10]}, "and the first on the road moves into the buffer")
	# Vehicles dropped from the buffer (a lorry giving up) make room for the road queue.
	var dropping := Handovers.new(sim.areas, AreaLayout.BAY)
	for id in range(1, 11):
		dropping.arrive(block, id)
	for id: int in [3, 4, 5, 6]:
		dropping.drop(block, id)
	_expect(dropping.waiting(block), {"buffer": [7, 8, 9, 10], "road": []}, "the road queue moves up into a buffer emptied by drops")
	dropping.leave(block, 1)
	_expect([dropping.slot_of(block, 7), dropping.waiting(block)], [0, {"buffer": [8, 9, 10], "road": []}], "and a freed slot still goes to the first in line")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var holding := [1, 3]
	var next_id := 11
	var too_many := false
	var doubled := false
	for i in 300:
		if rng.randf() < 0.5:
			handovers.arrive(block, next_id)
			next_id += 1
		elif not holding.is_empty():
			handovers.leave(block, holding[rng.randi() % holding.size()])
		holding = range(1, next_id).filter(func(id: int) -> bool: return handovers.slot_of(block, id) >= 0)
		var slots := holding.map(func(id: int) -> int: return handovers.slot_of(block, id))
		doubled = doubled or slots.size() != Dictionary(slots.reduce(func(seen: Dictionary, s: int) -> Dictionary:
			seen[s] = true
			return seen, {})).size()
		too_many = too_many or holding.size() > 2
	_expect(doubled or too_many, false, "no slot ever holds two vehicles, and no more vehicles hold slots than there are slots")


func _test_machine_jobs() -> void:
	var gear: Dictionary = Content.base().yard_gear
	var machines := Machines.new(gear)
	_expect(machines.count_for("rtg", 25), 2, "an RTG per 10 bays")
	_expect(machines.count_for("reach_stacker", 2), 1, "every area gets at least one machine")
	var rtg := machines.add(1, "rtg", 0)
	machines.give(rtg, 3, 8)
	# Travel 3 bays, lift, travel 5 bays, set down: bays are 12 m.
	var seconds: float = 3 * 12 / gear.rtg.speed + gear.rtg.lift_seconds + 5 * 12 / gear.rtg.speed + gear.rtg.set_down_seconds
	var phases := []
	var ticks := 0
	while true:
		if phases.is_empty() or phases[-1] != machines.phase(rtg):
			phases.append(machines.phase(rtg))
		ticks += 1
		if not machines.tick().is_empty():
			break
	_expect(ticks, ceili(seconds / Machines.SECONDS_PER_TICK), "one move takes the data's time in game seconds (%.1f s)" % seconds)
	_expect(phases, ["travel", "lift", "travel", "set_down"], "in the phases travel, lift, travel and set down")
	_expect(machines.list[rtg].bay, 8, "the machine ends where it set the box down")
	_expect(machines.phase(rtg), "", "and is idle")
	var stacker := machines.add(1, "reach_stacker", 8)
	machines.give(stacker, 8, 8)
	var lift_only := 0
	while machines.tick().is_empty():
		lift_only += 1
	_expect(lift_only + 1, ceili((gear.reach_stacker.lift_seconds + gear.reach_stacker.set_down_seconds) / Machines.SECONDS_PER_TICK), "a move within one bay is just lift and set down")


func _test_area_stacks() -> void:
	var yard := AreaStacks.new(3, 4)
	yard.place_at(0, 1, 2)
	yard.place_at(0, 2, 2)
	yard.place_at(0, 3, 2)
	_expect(yard.above(1), 2, "a box under two others has two above it")
	_expect(yard.take(1), 2, "taking out a buried box costs a rehandle per box above it")
	_expect(yard.boxes().has(1), false, "and it is gone")
	_expect([yard.stacks[0], yard.boxes().size()], [[], 2], "the boxes moved off it now sit on other stacks")
	var mixed := AreaStacks.new(2, 3)
	mixed.place_at(0, 10, 1)
	_expect(mixed.fits(0, 2), false, "a 40 ft box never rests on a 20")
	_expect(mixed.fits(0, 1), true, "a 20 ft box goes beside a lone 20")
	mixed.place_at(0, 11, 1)
	_expect(mixed.stacks[0], [[10, 11]], "two 20s share a tier")
	_expect(mixed.place(12, 2), 1, "a 40 goes to the next stack that takes it")
	_expect(mixed.place(13, 1), 0, "a 20 goes onto the 20s' tier stack")
	_expect(mixed.take(10), 1, "a 20 under a box costs one rehandle")
	_expect(mixed.stacks[0], [[11]], "its partner stays put")
	var full := AreaStacks.new(1, 4)
	for id in range(1, 4):
		full.place_at(0, id, 2)
	_expect(full.take(1), -1, "with nowhere to move the boxes above, a buried box can't come out")
	var kept := AreaStacks.new(2, 4)
	kept.place_at(0, 20, 2)
	kept.place_at(0, 21, 2)
	var due := {20: 10.0, 21: 50.0}
	_expect(kept.housekeep(due), true, "in a quiet period a box burying one due out sooner is moved")
	_expect(kept.above(20), 0, "so the box due first is on top")
	_expect(kept.housekeep(due), false, "and then there is nothing to do")
	var sorted := AreaStacks.new(3, 4)
	var table := {1: {"kind": "import", "due": 30.0}, 2: {"kind": "export", "due": 0.0}, 3: {"kind": "import", "due": 10.0}, 4: {"kind": "import", "due": 30.0}, 5: {"kind": "export", "due": 0.0}}
	for id: int in [1, 2, 3, 4, 5]:
		sorted.place_at(0 if id < 4 else 1, id, 2)
	_expect([sorted.of_kind("import", table), sorted.of_kind("export", table)], [[3, 1, 4], [2, 5]], "boxes of a kind come soonest due first, ties in stacking order")
	sorted.take(1)
	_expect(sorted.of_kind("import", table), [3, 4], "and the order follows the stacks as they change")
	_expect(sorted.of_kind("reefer", table), [], "a kind with no boxes has none")


func _test_driveways() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	var entry := sim.site_entry()
	# A 1+1 road from the site entry west to the coast, along grid line y = 301.
	# Drawn west, its right is north: the westbound lane is row 300 and the
	# eastbound lane row 301, from the entry cell west to x = 86.
	sim.apply({"op": "build_road", "from": entry + Vector2i(1, 1), "to": Vector2i(86, entry.y + 1), "type": "terminal_1_1"})
	var road := sim.roads.segment_at(Vector2i(200, entry.y))
	sim.apply({"op": "build_area", "type": "yard_block", "segment": road, "side": -1, "from": 100, "to": 129})
	sim.apply({"op": "build_area", "type": "yard_block", "segment": road, "side": 1, "from": 100, "to": 129})
	var south: Dictionary = sim.areas.layout(1)
	var north: Dictionary = sim.areas.layout(2)
	var slot := AreaFlow._stand(sim, 1, 4)
	var inbound := _inbound(sim, entry)
	var there := _route(sim, inbound, slot, true)
	_expect(there.is_empty(), false, "a lorry routes from the site entry into a yard slot")
	_expect(there.any(func(piece: int) -> bool: return sim.network.pieces[piece].area == 1 and sim.network.pieces[piece].slot == LaneNetwork.NO_SLOT), true, "through the block's buffer strip")
	_expect(sim.network.pieces[there[-1]].points[-1].distance_to(sim.areas.centre(slot)) < 0.001, true, "to where a lorry stands in the slot")
	var back := _route(sim, slot, _outbound(sim, entry), true)
	_expect(back.is_empty(), false, "and from the slot back out to the site exit")
	var other := _route(sim, inbound, AreaFlow._stand(sim, 2, 2), true)
	_expect(other.is_empty(), false, "blocks on both sides of a road are reached, each with its own flow")
	var past := _route(sim, inbound, AreaFlow._stand(sim, 2, 4), true)
	_expect(past.any(func(piece: int) -> bool: return sim.network.pieces[piece].slot == Vector2i(2, 3)), false, "a slot is never driven through on the way to another")
	# Drawn south down grid line x = 86 to the corner, its right (west) side reaches the sea.
	sim.apply({"op": "build_road", "from": Vector2i(86, 200), "to": Vector2i(86, entry.y + 1), "type": "terminal_1_1"})
	var coast := sim.roads.segment_at(Vector2i(85, 250))
	_expect(sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 10, "to": 39}), "", "an apron is built on the coast")
	var apron: Dictionary = sim.areas.layout(sim.areas.list.keys()[-1])
	var under_crane := AreaFlow._stand(sim, sim.areas.list.keys()[-1], 1)
	_expect(_route(sim, inbound, under_crane, false).is_empty(), false, "a tractor routes under the cranes")
	_expect(_route(sim, inbound, under_crane, true), [] as Array[int], "a lorry can't drive onto an apron")


func _test_apron_berths() -> void:
	var sim := AreaPort.terminal(60)
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": 1, "along": 60}), "STS cranes stand on a quay apron's rails", "a crane off the apron's rails is refused")
	var short := AreaPort.terminal(61)
	_expect(short.apply({"op": "place_sts", "kind": "sts", "apron": 1, "along": 60}), "STS cranes stand on a quay apron's rails", "a crane past the last whole bay, with no slot under it, is refused")
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": 2, "along": 3}), "STS cranes stand on a quay apron's rails", "a crane on a gate is refused")
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": 1, "along": 20}), "", "a crane is ordered on the apron")
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": 1, "along": 24}), "Too close to another crane", "cranes keep their width apart")
	_expect(sim.cranes.size() == 1 and sim.cranes[0].apron == 1 and sim.cranes[0].along == 20, true, "and stands on the apron's rails at once")
	_expect(AreaFlow.offer_berths(sim), [1] as Array[int], "an apron with a crane in a ready terminal is a berth lines may offer for")
	var feeder := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], 0.0, 1, 0)
	_expect(AreaFlow.ship_cells(sim, "feeder"), 50, "a feeder needs 200 m of quay, 50 cells")
	_expect(AreaFlow.berth(sim, feeder), true, "a feeder berths along a 60-cell apron")
	_expect([feeder.apron, feeder.from], [1, 0], "at the apron's first free stretch")
	_expect(AreaFlow.cranes_for(sim, feeder).size(), 1, "the crane within its length works it")
	var panamax := PortSim.Ship.new("panamax", sim.rules.lines.keys()[0], 0.0, 1, 0)
	_expect(AreaFlow.berth(sim, panamax), false, "a ship too long for the apron waits at anchor")
	_expect(AreaFlow.could_berth(sim, "panamax"), false, "and no apron could ever take it")
	var lonely := AreaPort.terminal(60)
	lonely.apply({"op": "paint_terminal", "cells": lonely.areas.cells(2), "terminal": -1})
	_expect(AreaFlow.berth(lonely, PortSim.Ship.new("feeder", lonely.rules.lines.keys()[0], 0.0, 1, 0)), false, "an apron in a terminal without a gate takes no ships")


func _test_discharge() -> void:
	var sim := AreaPort.working_terminal(3)
	var ship := sim.ships[0]
	var crane_ticks := ceili(60.0 / (sim.rules.sts_cranes.sts.rate * sim.rules.crane_interference) / SimClock.CALENDAR_MINUTES_PER_TICK)
	var gear: Dictionary = sim.rules.yard_gear.reach_stacker
	var machine_ticks := ceili((gear.lift_seconds + gear.set_down_seconds) / Machines.SECONDS_PER_TICK)
	var first := -1
	var sailed := false
	for i in 6000:
		sim.tick()
		sailed = sailed or ship.state == PortSim.Ship.State.LEAVING
		if first < 0 and not sim.area_stacks[3].boxes().is_empty():
			first = i + 1
		if sim.area_stacks[3].boxes().size() == 3:
			break
	_expect(sim.area_stacks[3].boxes().size(), 3, "every box goes from the ship into the import block's stacks")
	_expect(first >= crane_ticks + machine_ticks, true, "a box takes at least a crane move and a machine's lift and set-down (%d >= %d ticks)" % [first, crane_ticks + machine_ticks])
	_expect(sailed, true, "the ship sails once its cranes are done")
	_expect(sim.area_stacks[3].boxes().all(func(b: int) -> bool: return sim.boxes[b].in >= 0.0), true, "stacked boxes start their storage clock")
	for i in 400:
		sim.tick()
	_expect(sim.vehicles.is_empty(), true, "tractors return to the pool once their box is stacked")
	_expect(sim.handovers.slots()[3].all(func(v: int) -> bool: return v == 0), true, "leaving every slot free")


func _test_delivery() -> void:
	var sim := AreaPort.working_terminal(2)
	# 40 ft boxes only, so the second is stacked on the first, not beside it.
	sim.rules = sim.rules.duplicate(true)
	sim.rules.box_mix.forty_share = 1.0
	for i in 6000:
		sim.tick()
		if sim.area_stacks[3].boxes().size() == 2:
			break
	var stacks: AreaStacks = sim.area_stacks[3]
	_expect(stacks.position_of(stacks.boxes()[0]) == stacks.position_of(stacks.boxes()[1]), true, "both boxes went on the first stack, one on the other")
	for box: int in stacks.boxes():
		sim.boxes[box].due = 0.0
	var delivered := sim.delivered
	var most_phases := 0
	for i in 20000:
		sim.tick()
		for job: Dictionary in sim.machines.list.values().map(func(m: Dictionary) -> Dictionary: return m.job):
			if not job.is_empty():
				most_phases = maxi(most_phases, job.phases.size())
		if sim.delivered == delivered + 2:
			break
	_expect(sim.delivered - delivered, 2, "lorries take both boxes out through the gate to the site exit")
	_expect(most_phases >= 6, true, "fetching the buried box first moves the one on top: a lift and a set-down more")
	_expect(sim.turn_times.size(), 2, "each lorry's gate turn is recorded")
	_expect(sim.turn_times.all(func(t: float) -> bool: return t >= 2 * sim.rules.gate_levels.manual.minutes), true, "a turn includes the gate time both ways")
	_expect(sim.dwell_times.size() >= 2, true, "dwell is recorded at pickup")
	_expect(stacks.boxes().is_empty() and sim._claimed.is_empty(), true, "the yard is empty and nothing is left claimed")
	for i in 600:
		sim.tick()
	_expect(sim.vehicles.is_empty(), true, "every vehicle has left")


func _test_exports() -> void:
	var sim := AreaPort.working_terminal(1, 2)
	var ship := sim.ships[0]
	var export_block: int = 4
	var stacked := 0
	for i in 40000:
		sim.tick()
		if export_block in sim.area_stacks:
			stacked = maxi(stacked, sim.area_stacks[export_block].boxes().size())
		if ship.state == PortSim.Ship.State.LEAVING:
			break
	_expect(stacked >= 1, true, "export lorries stack boxes in the export block")
	_expect(ship.exports, 0, "tractors fetch exports to the crane, which loads them all")
	_expect(ship.moves, 3, "the ship counts its import and both exports")
	_expect(ship.state, PortSim.Ship.State.LEAVING, "and sails fully loaded")


func _test_crane_keeps_tractors_busy() -> void:
	# One crane, four tractors, a ship taking 8 exports and bringing none.
	var sim := AreaPort.working_terminal(0, 8)
	var ship := sim.ships[0]
	var most := 0
	for i in 80000:
		sim.tick()
		most = maxi(most, sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "tractor" and v.home != Areas.NO_SPOT).size())
		if ship.state == PortSim.Ship.State.LEAVING:
			break
	_expect(most >= 2, true, "a loading crane has more than one tractor fetching exports at once (most %d)" % most)
	_expect(ship.exports, 0, "and loads them all")
	_expect(ship.state, PortSim.Ship.State.LEAVING, "then sails")


func _test_exports_wait_for_calls() -> void:
	var sim := AreaPort.terminal(60)
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 61, "to": 90})
	sim.apply({"op": "set_area", "id": 3, "settings": {"role": "export"}})
	for i in roundi(120 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	var exports := sim.boxes.values().filter(func(b: Dictionary) -> bool: return b.kind == "export").size()
	_expect(exports, 0, "with no call booked, no exports come in two hours")


func _test_lorries_use_the_gate_on_their_side() -> void:
	var sim := AreaPort.working_terminal(1)
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	# A second gate across the road from the first, on the eastbound side lorries leave by.
	_expect(sim.apply({"op": "build_area", "type": "gate", "segment": east, "side": 1, "from": 300, "to": 314}), "", "a gate is built on the outbound side")
	var south: int = sim.areas.list.keys().max()
	var out_gates := {}
	for i in 30000:
		sim.tick()
		for v: Vehicle in sim.vehicles:
			if v.kind == "lorry" and v.state == "at_gate" and v.loaded:
				out_gates[v.area] = true
		if sim.delivered == 1:
			break
	_expect(sim.delivered, 1, "the import leaves by lorry")
	_expect(out_gates.keys(), [south], "the lorry checks out at the gate on its way out, not the inbound one")


func _test_two_way_gate() -> void:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait()))
	var entry := sim.site_entry()
	sim.apply({"op": "build_road", "from": Vector2i(400, entry.y), "to": entry, "type": "terminal_1_1"})
	var money := sim.money
	_expect(sim.apply({"op": "build_two_way_gate", "type": "gate_small", "segment": 1, "from": 10, "to": 24}), "", "a two-way gate is built")
	var gates := sim.areas.list.keys()
	_expect(gates.size(), 2, "it is a gate on each side of the road")
	_expect(sim.areas.out_at(gates[0], 0).is_equal_approx(-sim.areas.out_at(gates[1], 0)), true, "facing opposite ways")
	_expect(sim.areas.list[gates[0]].terminal, sim.areas.list[gates[1]].terminal, "in one terminal")
	_expect(money - sim.money, 2 * sim.area_price("gate_small", 1, 1, 10, 24), "both sides are paid for")
	_expect(sim.apply({"op": "build_two_way_gate", "type": "yard_block", "segment": 1, "from": 30, "to": 50}), "Only gates are built on both sides of a road", "only gates are two-way")
	_expect(sim.apply({"op": "build_two_way_gate", "type": "gate", "segment": 1, "from": 20, "to": 34}), "Something is already built here", "neither side may overlap")
	_expect(sim.areas.list.size(), 2, "a refused two-way gate builds neither side")
	# Lorries take the gate they get through soonest: drive plus queue.
	var port := AreaPort.terminal(60)
	var east := port.roads.segment_at(Vector2i(200, port.site_entry().y))
	_expect(port.apply({"op": "build_area", "type": "gate", "segment": east, "side": -1, "from": 200, "to": 214}), "", "a second gate further in")
	var second: int = port.areas.list.keys().max()
	_expect(AreaFlow._gate_of(port, 1, Vector3i(0, port.site_entry().x, port.site_entry().y)), 2, "with no queues a lorry takes the nearest gate")
	for i in 20:
		var waiting := Vehicle.new(900 + i, "lorry", [Vector3i.ZERO] as Array[Vector3i])
		waiting.area = 2
		port._add_vehicle(waiting)
	_expect(AreaFlow._gate_of(port, 1, Vector3i(0, port.site_entry().x, port.site_entry().y)), second, "with 20 lorries bound for it, the next drives on to the other gate")


func _test_lorry_gives_up() -> void:
	var sim := AreaPort.terminal(30)
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 30, "to": 59})
	var box := sim._new_box("import", 0.0, "")
	AreaFlow._stacks(sim, 3).place(box, sim.boxes[box].teu)
	sim.boxes[box].in = 0.0
	# A parked tractor blocks the westbound lane between the entry and the gate.
	var blocker := Vehicle.new(999, "tractor", [Vector3i(0, 450, sim.site_entry().y - 1)] as Array[Vector3i])
	_expect(Drive.place(sim, blocker), true, "the blocker stands in the lane")
	# Another stands where the lorry would be moved on to, so it can't be.
	var in_the_way := Vehicle.new(998, "tractor", [AreaFlow._buffer_start(sim, 2)] as Array[Vector3i])
	_expect(Drive.place(sim, in_the_way), true, "a tractor stands at the gate's way in")
	_expect(AreaFlow.dispatch_import_lorry(sim), true, "a lorry is sent for the box due out")
	var lorry := sim.vehicles[0]
	var limit := roundi(sim.rules.give_up_seconds / SimClock.TICK_SECONDS) * 2
	for i in limit + 400:
		sim.tick()
	_expect(sim.vehicles.has(lorry), false, "stuck behind it for twice the give-up time, the lorry gives up and leaves")
	_expect(sim.gave_up, 1, "and is counted")
	var holders := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.box == box)
	_expect(not sim._claimed.has(box) or (holders.size() == 1 and holders[0] != lorry), true, "its box is freed for another lorry")
	_expect(sim.handovers.waiting(2), {"buffer": [], "road": []}, "and it holds no place at the gate")


## A tractor stuck behind one that never moves, for as long as a lorry would
## give up after, is moved on to where it was heading with its box, as
## Cities: Skylines despawns a stuck vehicle, but nothing is lost: it is
## counted, and the status says so.
func _test_stuck_tractor_moves_on() -> void:
	var sim := AreaPort.terminal(30)
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 30, "to": 59})
	var block: int = sim.areas.list.keys().max()
	var blocker := Vehicle.new(999, "tractor", [Vector3i(0, 450, sim.site_entry().y - 1)] as Array[Vector3i])
	_expect(Drive.place(sim, blocker), true, "a parked tractor stands in the westbound lane")
	var tractor := Vehicle.new(sim._next_vehicle, "tractor", [Drive.entry_cell(sim)] as Array[Vector3i])
	sim._next_vehicle += 1
	_expect(Drive.place(sim, tractor), true, "a tractor comes in at the site entry")
	tractor.box = sim._new_box("import", 0.0, "")
	tractor.loaded = true
	sim._add_vehicle(tractor)
	AreaFlow._go_to(sim, tractor, block)
	var box := tractor.box
	var limit := roundi(sim.rules.give_up_seconds / SimClock.TICK_SECONDS) * 2
	for i in limit + 400:
		sim.tick()
	_expect(tractor.state != "arriving", true, "stuck behind it past the give-up time, the tractor is moved on (%s)" % tractor.state)
	_expect(AreaFlow._stacks(sim, block).boxes().has(box), true, "and its box reaches the block's stacks")
	_expect(sim.moved_on, 1, "it is counted")
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.begins_with("A tractor stuck in traffic was moved on")), true, "and the status says so")


## A lorry comes for the box due longest, whichever block holds it, so no
## block's handover slots take every lorry while other blocks wait.
func _test_lorries_come_for_the_longest_due_box() -> void:
	var sim := AreaPort.working_terminal(0, 1)
	sim.apply({"op": "set_area", "id": 4, "settings": {"role": "import"}})
	var now := sim.clock.calendar_minutes()
	var boxes := {}
	for block: int in [3, 4]:
		var box := sim._new_box("import", now - (10.0 if block == 3 else 60.0), "")
		AreaFlow._stacks(sim, block).place(box, sim.boxes[box].teu)
		boxes[block] = box
	_expect(AreaFlow.dispatch_import_lorry(sim), true, "a lorry is sent")
	_expect(sim.vehicles[-1].box, boxes[4], "for the box due an hour ago in the second block, not the one due 10 minutes ago in the first")


## M5's exit chain: STS -> tractor -> RTG lane -> stack -> lorry -> gate.
func _test_following_a_box() -> void:
	# RandomPort.quick unlocks every milestone, RTGs among them.
	var sim := AreaPort.working_terminal(1, 0, RandomPort.quick())
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"gear": "rtg"}}), "", "the import block is worked by RTGs")
	var box := 0
	for i in 2000:
		sim.tick()
		var carried := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.loaded)
		if not carried.is_empty():
			box = carried[0].box
			break
	var tractor: Vehicle = sim.vehicles.filter(func(v: Vehicle) -> bool: return v.box == box)[0]
	_expect(AreaFlow.box_at(sim, Vector2i(Drive.where(sim, tractor).round())), box, "clicking the tractor under the crane picks its box")
	var at := AreaFlow.box_cell(sim, box)
	_expect(Vector2i(at.round()) in sim.areas.cells(1), true, "the box starts on the apron, under the crane")
	var seen := {}
	var lost := false
	var due_set := false
	for i in 30000:
		sim.tick()
		at = AreaFlow.box_cell(sim, box)
		if at == Vector2.INF:
			break
		var area := sim.areas.area_at(Vector2i(at.round()))
		if area:
			seen[sim.areas.list[area].type] = true
		if not due_set and sim.area_stacks[3].boxes().has(box):
			sim.boxes[box].due = 0.0
			due_set = true
	_expect(seen.has("yard_block") and seen.has("gate"), true, "it is followed through the yard block and the gate (%s)" % [seen.keys()])
	_expect(at, Vector2.INF, "until it leaves the port")
	var gears: Array = sim.machines.list.values().filter(func(m: Dictionary) -> bool: return m.area == 3).map(func(m: Dictionary) -> String: return m.gear)
	_expect(not gears.is_empty() and gears.all(func(g: String) -> bool: return g == "rtg"), true, "RTGs did the block's work (%s)" % [gears])


## The road spot at the site entry a vehicle can drive in from.
func _inbound(sim: PortSim, _entry: Vector2i) -> Vector3i:
	return Drive.entry_cell(sim)


## The road spot at the site entry a vehicle can drive out on.
func _outbound(sim: PortSim, _entry: Vector2i) -> Vector3i:
	return Drive.exit_cell(sim)


## The lane network's route over `roads` for a lorry (`lorry`) or a tractor
## from the lane nearest `from` to the one nearest `to`; [] when there is none.
func _lane_route(roads: RoadNet, from: Vector2, to: Vector2, lorry: bool) -> Array[int]:
	var network := LaneNetwork.new(roads, Content.base().junctions)
	var start: int = network.nearest(from, lorry)[0]
	var end: int = network.nearest(to, lorry)[0]
	if start == 0 or end == 0:
		return []
	return network.route(start, end, lorry)


## The lane network's route for a lorry (`lorry`) or a tractor from spot
## `from` to spot `to`, as Drive finds it; [] when there is none.
func _route(sim: PortSim, from: Vector3i, to: Vector3i, lorry: bool) -> Array[int]:
	Drive.flow(sim, 0)
	var start: int = sim.network.nearest(sim.areas.centre(from), lorry)[0]
	return Drive._best_route(sim, start, to, lorry)


## Whether `layout`'s parts, other than the lanes slots lie in, cover `cells`
## exactly once each.
func _covers_once(areas: Areas, layout: Dictionary, cells: Array[Vector2i]) -> bool:
	var used := {}
	var parts: Array = [layout.buffer, layout.edge, layout.hatches] + layout.rails + layout.lanes + layout.slots
	for part: Array in parts:
		for cell: Vector2i in _grid(areas, part):
			if cell in used:
				return false
			used[cell] = true
	return cells.all(func(c: Vector2i) -> bool: return c in used)


## The grid cells `spots`' middles lie in.
func _grid(areas: Areas, spots: Array) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for spot: Vector3i in spots:
		found.append(Vector2i(areas.centre(spot).floor()))
	return found


func _node(net: RoadNet, cell: Vector2i) -> int:
	return net.nodes.find_key(Vector2(cell))


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
