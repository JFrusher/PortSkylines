extends SceneTree
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
	_test_handovers()
	_test_machine_jobs()
	_test_area_stacks()
	_test_driveways()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _test_segments() -> void:
	var net := RoadNet.new(Content.base().road_types)
	_expect(net.add(Vector2i(0, 0), Vector2i(5, 0), "terminal_1_1"), "", "a straight road is built")
	_expect(net.add(Vector2i(5, 0), Vector2i(8, 3), "terminal_1_1"), "", "a 45° road is built")
	_expect(net.add(Vector2i(0, 0), Vector2i(2, 5), "terminal_1_1"), "Roads run straight or at 45°", "other angles are refused")
	_expect(net.add(Vector2i(4, 4), Vector2i(4, 4), "terminal_1_1"), "A road needs a length", "a road has a length")
	_expect(net.nodes.size(), 3, "roads meeting at a cell share its node")
	_expect(net.cells(1), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)] as Array[Vector2i], "a straight road covers each cell along it")
	var diagonal := net.cells(2)
	_expect(diagonal.size(), 4, "a 45° road of 3 cells' run covers 4 cells")
	var connected := true
	for i in diagonal.size() - 1:
		connected = connected and (diagonal[i + 1] - diagonal[i]).abs() == Vector2i.ONE
	_expect(connected, true, "a 45° road is a connected diagonal run")
	_expect(RoadNet.line(Vector2i(3, 3), Vector2i(3, 0)), [Vector2i(3, 3), Vector2i(3, 2), Vector2i(3, 1), Vector2i(3, 0)] as Array[Vector2i], "a line runs from its first end")


func _test_lanes() -> void:
	var net := RoadNet.new(Content.base().road_types)
	_expect(net.add(Vector2i(0, 0), Vector2i(3, 0), "dirt_track"), "Unknown road type \"dirt_track\"", "unknown road types are refused")
	net.add(Vector2i(0, 5), Vector2i(3, 5), "terminal_2_2")
	var lanes := net.lanes(1)
	_expect(lanes.size(), 4, "a 2+2 road has 4 lanes")
	_expect(lanes.map(func(l: Dictionary) -> bool: return l.forward), [false, false, true, true], "backward lanes on the left, forward on the right")
	# Drawn eastward, right is south (+y): forward lanes on rows 5 and 6, backward on 3 and 4.
	_expect(lanes.map(func(l: Dictionary) -> int: return l.cells[0].y), [3, 4, 5, 6], "lanes sit side by side, the drawn line being the first forward lane")
	_expect(lanes[0].cells[0], Vector2i(3, 3), "a backward lane is listed in driving order, from b to a")
	net.add(Vector2i(10, 10), Vector2i(13, 7), "one_way")
	var one_way := net.lanes(2)
	_expect(one_way.all(func(l: Dictionary) -> bool: return l.forward), true, "a one-way road's lanes all run forward")
	var touching := true
	var first: Array = one_way[0].cells
	var second: Array = one_way[1].cells
	for i: int in first.size():
		touching = touching and (second[i] - first[i]).abs() in [Vector2i(1, 0), Vector2i(0, 1)]
	_expect(touching, true, "45° lanes touch side by side, with no gap row")
	_expect(Content.base().road_types.tractor_lane.lorries, false, "the tractor lane refuses lorries")
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var right := RoadNet.right_of(d)
		_expect(Vector2(right).dot(Vector2(-d.y, d.x)) > 0, true, "right_of %s is on the right" % d)


func _test_junctions() -> void:
	var net := RoadNet.new(Content.base().road_types)
	net.add(Vector2i(0, 5), Vector2i(10, 5), "terminal_1_1")
	_expect(net.add(Vector2i(5, 0), Vector2i(5, 10), "terminal_1_1"), "", "a road may cross another")
	var crossing := _node(net, Vector2i(5, 5))
	_expect(net.degree(crossing), 4, "a crossing makes a 4-way node")
	_expect(net.segments.size(), 4, "both roads split at the crossing")
	_expect(net.add(Vector2i(8, 5), Vector2i(8, 9), "terminal_1_1"), "", "a road may end on another")
	_expect(net.degree(_node(net, Vector2i(8, 5))), 3, "a T join makes a 3-way node")
	_expect(net.add(Vector2i(2, 5), Vector2i(4, 5), "terminal_1_1"), "A road already runs here", "a road can't run along another")
	_expect(net.add(Vector2i(10, 5), Vector2i(10, 0), "terminal_1_1"), "", "a road may start at another's end")
	_expect(net.degree(_node(net, Vector2i(10, 5))), 2, "a bend is a 2-way node")
	var diagonal := RoadNet.new(Content.base().road_types)
	diagonal.add(Vector2i(0, 0), Vector2i(6, 6), "terminal_1_1")
	_expect(diagonal.add(Vector2i(0, 5), Vector2i(5, 0), "terminal_1_1"), "Roads must cross at a cell, not between two", "45° roads that miss each other's cells are refused")
	_expect(diagonal.add(Vector2i(0, 6), Vector2i(6, 0), "terminal_1_1"), "", "45° roads crossing at a cell are built")
	_expect(diagonal.degree(_node(diagonal, Vector2i(3, 3))), 4, "45° roads crossing at a cell make a 4-way node")
	var lengths := 0
	for id: int in net.segments:
		lengths += net.cells(id).size() - 1
	_expect(lengths, 10 + 10 + 4 + 5, "splitting keeps every cell of road")


func _test_routes() -> void:
	var net := RoadNet.new(Content.base().road_types)
	var lanes := LaneGraph.new(net)
	net.add(Vector2i(0, 0), Vector2i(10, 0), "terminal_1_1")
	net.add(Vector2i(10, 0), Vector2i(10, 10), "terminal_1_1")
	var bend := lanes.route(Vector2i(0, 0), Vector2i(10, 10), true)
	_expect(bend.size(), 21, "round a bend the route is the cells along both roads")
	_expect(_steps_are_single(bend), true, "a route moves one cell at a time")
	var back := lanes.route(Vector2i(4, 0), Vector2i(2, -1), true)
	_expect(not back.is_empty(), true, "the other way is reached by the dead end's U-turn")
	_expect(back.has(Vector2i(10, 10)) or back.has(Vector2i(11, 10)), true, "the U-turn is at the dead end")
	var one_way := RoadNet.new(Content.base().road_types)
	var one_way_lanes := LaneGraph.new(one_way)
	one_way.add(Vector2i(0, 0), Vector2i(10, 0), "one_way")
	_expect(one_way_lanes.route(Vector2i(0, 0), Vector2i(10, 0), true).size(), 11, "a one-way road is driven forward")
	_expect(one_way_lanes.route(Vector2i(10, 0), Vector2i(0, 0), true), [] as Array[Vector2i], "a one-way road can't be driven backwards")
	_expect(one_way_lanes.route(Vector2i(0, 0), Vector2i(10, 1), true).size(), 11, "a lane change costs no extra cells")
	var tractors := RoadNet.new(Content.base().road_types)
	var tractor_lanes := LaneGraph.new(tractors)
	tractors.add(Vector2i(0, 5), Vector2i(10, 5), "tractor_lane")
	_expect(tractor_lanes.route(Vector2i(0, 5), Vector2i(10, 5), true), [] as Array[Vector2i], "lorries can't use the tractor lane")
	_expect(tractor_lanes.route(Vector2i(0, 5), Vector2i(10, 5), false).size(), 11, "tractors can")
	var grid := RoadNet.new(Content.base().road_types)
	var grid_lanes := LaneGraph.new(grid)
	for i in 3:
		grid.add(Vector2i(0, i * 10), Vector2i(30, i * 10), "terminal_2_2")
		grid.add(Vector2i(i * 10 + 5, -5), Vector2i(i * 10 + 5, 25), "terminal_2_2")
	var across := grid_lanes.route(Vector2i(0, 0), Vector2i(25, 20), true)
	_expect(_steps_are_single(across), true, "junction crossings move one cell at a time")
	# East along row 0's eastbound lane to column 25, then down its southbound lane.
	_expect(across.size() - 1, 25 + 20, "a route across a road grid is the shortest by hand")


func _test_editing() -> void:
	_expect(RoadNet.snap(Vector2i(0, 0), Vector2i(10, 2)), Vector2i(10, 0), "a nearly level drag snaps straight")
	_expect(RoadNet.snap(Vector2i(0, 0), Vector2i(1, -9)), Vector2i(0, -9), "a nearly upright drag snaps straight")
	_expect(RoadNet.snap(Vector2i(0, 0), Vector2i(6, 4)), Vector2i(5, 5), "an in-between drag snaps to 45°")
	_expect(RoadNet.snap(Vector2i(0, 0), Vector2i(-4, 6)), Vector2i(-5, 5), "45° snapping keeps the drag's direction")
	_expect(RoadNet.length(Vector2i(0, 0), Vector2i(-5, 5)), 5, "a road's length is its run in cells")
	var net := RoadNet.new(Content.base().road_types)
	net.add(Vector2i(0, 5), Vector2i(10, 5), "terminal_1_1")
	_expect(net.add_error(Vector2i(2, 5), Vector2i(4, 5), "terminal_1_1"), "A road already runs here", "add_error gives add's refusal")
	_expect(net.add_error(Vector2i(5, 0), Vector2i(5, 10), "terminal_1_1"), "", "add_error passes a road add would build")
	_expect(net.segments.size(), 1, "add_error changes nothing")
	net.add(Vector2i(5, 0), Vector2i(5, 10), "terminal_1_1")
	var copy := RoadNet.from_dict(net.to_dict(), net.types)
	_expect(copy.to_dict(), net.to_dict(), "roads round-trip through a dictionary")
	_expect(net.segment_at(Vector2i(8, 4)), net.segment_at(Vector2i(8, 5)), "both lanes of a road find its segment")
	_expect(net.segment_at(Vector2i(8, 7)), 0, "a cell off every road finds none")
	var version := net.version
	net.remove(net.segment_at(Vector2i(5, 1)))
	_expect(net.version > version, true, "removing a road bumps the version")
	_expect(net.nodes.values().has(Vector2i(5, 0)), false, "a node left with no road goes")
	_expect(net.degree(_node(net, Vector2i(5, 5))), 3, "the crossing becomes a T")


func _test_sim_commands() -> void:
	var sim := PortSim.new()
	var money := sim.money
	var upkeep := sim.daily_upkeep()
	var cost: int = sim.rules.road_types.terminal_2_2.cost_per_cell
	_expect(sim.apply({"op": "build_road", "from": Vector2i(10, 10), "to": Vector2i(30, 10), "type": "terminal_2_2"}), "", "a road is built by command")
	_expect(money - sim.money, 20 * cost, "a road costs its length in cells")
	_expect(sim.daily_upkeep() - upkeep, 20 * sim.rules.road_types.terminal_2_2.upkeep_per_cell, "roads add their upkeep")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(15, 10), "to": Vector2i(25, 10), "type": "terminal_1_1"}), "A road already runs here", "a refused road")
	_expect(money - sim.money, 20 * cost, "costs nothing")
	_expect(sim.lanes.route(Vector2i(10, 10), Vector2i(30, 10), true).size(), 21, "the sim routes on its roads")
	var poor := PortSim.new()
	poor.ledger.post("construction", -poor.money)
	_expect(poor.apply({"op": "build_road", "from": Vector2i(10, 10), "to": Vector2i(30, 10), "type": "terminal_2_2"}), "Not enough money", "roads need the money")
	_expect(sim.apply({"op": "remove_road", "segment": 99}), "No road there", "removing a missing road is refused")
	_expect(sim.apply({"op": "remove_road", "segment": 1}), "", "a road is removed by command")
	_expect(sim.roads.segments.is_empty(), true, "and is gone")


func _test_areas() -> void:
	var rules := Content.base()
	var net := RoadNet.new(rules.road_types)
	var areas := Areas.new(rules.area_types, net, rules.site)
	# Drawn south, so its right is west, towards the sea (x < 75). The 1+1 lanes are x = 85 and 86.
	net.add(Vector2i(85, 100), Vector2i(85, 200), "terminal_1_1")
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
	net.add(Vector2i(85, 180), Vector2i(110, 180), "terminal_1_1")
	var south := net.segment_at(Vector2i(85, 190))
	# Its first cell is the junction, beside the new road's lanes on row 180.
	_expect(areas.add("yard_block", south, -1, 0, net.cells(south).size() - 1), "Something is already built here", "an area can't reach into a joining road")
	_expect(areas.add("yard_block", south, -1, 1, net.cells(south).size() - 1), "", "an area is built on a road's split end")
	var north := net.segment_at(Vector2i(85, 150))
	_expect(areas.add("depot", north, -1, 60, net.cells(north).size() - 1), "Something is already built here", "an area can't cover a road")
	var inland := RoadNet.new(rules.road_types)
	var inland_areas := Areas.new(rules.area_types, inland, rules.site)
	inland.add(Vector2i(90, 100), Vector2i(90, 200), "terminal_1_1")
	_expect(inland_areas.add("quay_apron", 1, 1, 0, 40), "A quay apron runs along the water's edge", "an apron must reach the water")
	var coast := RoadNet.new(rules.road_types)
	var coast_areas := Areas.new(rules.area_types, coast, rules.site)
	coast.add(Vector2i(78, 100), Vector2i(78, 200), "terminal_1_1")
	_expect(coast_areas.add("yard_block", 1, 1, 0, 40), "Areas can't be built on water", "areas stay out of the sea")
	coast.add(Vector2i(595, 100), Vector2i(595, 200), "terminal_1_1")
	_expect(coast_areas.add("yard_block", 2, -1, 0, 40), "Areas must stay on the site", "areas stay on the site")


func _test_area_tool() -> void:
	var sim := PortSim.new()
	sim.apply({"op": "build_road", "from": Vector2i(100, 100), "to": Vector2i(100, 160), "type": "terminal_2_2"})
	# Drawn south: right is west. Forward lanes are x = 100 and 99, backward 101 and 102 (left, east),
	# so areas start at x = 98 to the west and x = 103 to the east.
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
	_expect(sim.daily_upkeep() - upkeep, 20 * block.depth * block.upkeep_per_cell, "areas add their upkeep")
	sim.apply({"op": "build_road", "from": Vector2i(100, 120), "to": Vector2i(120, 120), "type": "terminal_1_1"})
	_expect(sim.areas.cells(1).size(), 20 * block.depth, "a road joining later doesn't move the area")
	_expect(sim.apply({"op": "remove_area", "id": 7}), "No area there", "removing a missing area is refused")
	_expect(sim.apply({"op": "remove_area", "id": 1}), "", "an area is removed by command")
	var diagonal := PortSim.new()
	diagonal.apply({"op": "build_road", "from": Vector2i(100, 100), "to": Vector2i(130, 130), "type": "terminal_1_1"})
	_expect(diagonal.apply({"op": "build_area", "type": "depot", "segment": 1, "side": -1, "from": 0, "to": 10}), "", "an area is built along a 45° road")
	var rows := diagonal.areas.cells(1)
	_expect(rows.all(func(c: Vector2i) -> bool: return diagonal.roads.segment_at(c) == 0), true, "and takes its direction without covering it")


func _test_yard_layout() -> void:
	var sim := PortSim.new()
	sim.apply({"op": "build_road", "from": Vector2i(100, 100), "to": Vector2i(160, 100), "type": "terminal_1_1"})
	# Drawn east, right is south: the block starts on row 101 and runs 31 cells east.
	sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": 1, "from": 0, "to": 30})
	var depth: int = sim.rules.area_types.yard_block.depth
	var layout := sim.areas.layout(1)
	_expect(layout.buffer.size(), 31, "the buffer strip runs the block's whole length")
	_expect(layout.buffer.all(func(c: Vector2i) -> bool: return c.y == 101), true, "beside the road")
	_expect(layout.slots.size(), 10, "31 cells hold 10 bays of 3, so 10 handover slots")
	_expect(layout.slots.all(func(s: Array) -> bool: return s.size() == AreaLayout.BAY and s.all(func(c: Vector2i) -> bool: return c.y == 102)), true, "each slot is a bay of the truck lane, one row in")
	_expect(layout.stacks.size(), 10 * (depth - 2), "a stack per bay in each row behind the truck lane")
	var used := {}
	var overlap := false
	for cells: Array in [layout.buffer] + layout.slots + layout.stacks.map(func(s: Dictionary) -> Array: return s.cells):
		for cell: Vector2i in cells:
			overlap = overlap or cell in used
			used[cell] = true
	_expect(overlap, false, "no cell is used twice")
	_expect(used.keys().all(func(c: Vector2i) -> bool: return c in sim.areas.cells(1)), true, "every part lies inside the block")
	_expect(sim.areas.layout(1), layout, "the same block lays out the same every time")


func _test_apron_and_gate_layouts() -> void:
	var sim := PortSim.new(0, Content.base(), true)
	# Drawn south at x = 85, its right (west) side reaches the sea: the apron covers x = 84 down to 75.
	sim.apply({"op": "build_road", "from": Vector2i(85, 100), "to": Vector2i(85, 160), "type": "terminal_1_1"})
	_expect(sim.apply({"op": "build_area", "type": "quay_apron", "segment": 1, "side": 1, "from": 0, "to": 29}), "", "an apron is built on the coast")
	var depth: int = sim.rules.area_types.quay_apron.depth
	var apron := sim.areas.layout(1)
	_expect(apron.buffer.all(func(c: Vector2i) -> bool: return c.x == 84), true, "the apron's buffer strip is beside the road")
	_expect(apron.rails[0].all(func(c: Vector2i) -> bool: return c.x == 83) and apron.rails[1].all(func(c: Vector2i) -> bool: return c.x == 76), true, "crane rails run landside and waterside")
	_expect(apron.edge.all(func(c: Vector2i) -> bool: return c.x == 75), true, "the quay edge is on the water")
	_expect(apron.slots.size(), 10 * (depth - 4), "a handover slot per bay in each tractor lane between the rails")
	_expect(_covers_once(apron, sim.areas.cells(1)), true, "the apron's parts cover it with no cell used twice")
	_expect(sim.apply({"op": "build_area", "type": "gate", "segment": 1, "side": -1, "from": 0, "to": 14}), "", "a gate is built across the road")
	var gate_depth: int = sim.rules.area_types.gate.depth
	var gate := sim.areas.layout(2)
	_expect(gate.lanes.size(), gate_depth - 2, "a gate's lanes fill the rows between its buffer strip and kerb")
	_expect(gate.slots.size(), gate.lanes.size(), "one booth slot per lane")
	_expect(gate.slots.all(func(s: Array) -> bool: return s[0].y == 106), true, "booths sit at the gate's middle bay")
	_expect(gate.lanes.all(func(l: Array) -> bool: return l.size() == 15), true, "gate lanes run the gate's length")


func _test_area_settings() -> void:
	var sim := PortSim.new(0, Content.base(), true)
	sim.apply({"op": "build_road", "from": Vector2i(85, 100), "to": Vector2i(85, 160), "type": "terminal_1_1"})
	sim.apply({"op": "build_area", "type": "quay_apron", "segment": 1, "side": 1, "from": 0, "to": 29})
	sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": -1, "from": 0, "to": 29})
	sim.apply({"op": "build_area", "type": "gate", "segment": 1, "side": -1, "from": 35, "to": 50})
	_expect(sim.areas.list[2].settings, {"role": "import", "gear": "reach_stacker", "lines": []}, "a new yard block starts as an import block with reach stackers")
	var line: String = sim.rules.lines.keys()[0]
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"role": "export", "lines": [line]}}), "", "a yard block's role and lines are set")
	_expect(sim.areas.list[2].settings, {"role": "export", "gear": "reach_stacker", "lines": [line]}, "unset rules stay as they were")
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"role": "reefer"}}), "", "reefer is a yard role")
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"role": "transit"}}), "Unknown yard role: transit", "unknown roles are refused")
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"gear": "crane_on_legs"}}), "Unknown yard gear: crane_on_legs", "unknown gear is refused")
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"lines": ["Nobody Lines"]}}), "Line priority lists known shipping lines", "unknown lines are refused")
	_expect(sim.apply({"op": "set_area", "id": 1, "settings": {"role": "export"}}), "A quay apron has no role setting", "an apron takes no role")
	_expect(sim.apply({"op": "set_area", "id": 1, "settings": {"lines": [line]}}), "", "an apron favours lines")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"lines": [line]}}), "A gate has no lines setting", "a gate has no rules")
	_expect(sim.apply({"op": "set_area", "id": 9, "settings": {}}), "No area there", "a missing area is refused")
	var locked := PortSim.new()
	locked.apply({"op": "build_road", "from": Vector2i(100, 100), "to": Vector2i(100, 160), "type": "terminal_1_1"})
	locked.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": -1, "from": 0, "to": 15})
	_expect(locked.apply({"op": "set_area", "id": 1, "settings": {"gear": "rtg"}}), locked.lock_error("rtg"), "RTGs wait for their milestone")


func _test_terminals() -> void:
	var sim := PortSim.new(0, Content.base(), true)
	sim.apply({"op": "build_road", "from": Vector2i(85, 100), "to": Vector2i(85, 200), "type": "terminal_1_1"})
	sim.apply({"op": "build_area", "type": "quay_apron", "segment": 1, "side": 1, "from": 0, "to": 29})
	_expect(sim.areas.list[1].terminal, 1, "the first area starts Terminal 1")
	_expect(sim.areas.terminal_error(1), "Terminal 1 needs a gate", "a terminal with only an apron can't take contracts")
	sim.apply({"op": "build_area", "type": "quay_apron", "segment": 1, "side": 1, "from": 30, "to": 59})
	_expect(sim.areas.list[2].terminal, 1, "an area touching another joins its terminal")
	sim.apply({"op": "build_area", "type": "gate", "segment": 1, "side": -1, "from": 80, "to": 95})
	_expect(sim.areas.list[3].terminal, 2, "an area touching none starts its own terminal")
	_expect(sim.areas.terminal_error(2), "Terminal 2 needs a quay apron", "a terminal needs an apron too")
	_expect(sim.apply({"op": "set_terminal", "id": 3, "terminal": 1}), "", "an area is moved to another terminal")
	_expect(sim.areas.terminal_error(1), "", "a terminal with a gate and an apron takes contracts")
	_expect(sim.areas.terminals.has(2), false, "a terminal left with no areas goes")
	_expect(sim.apply({"op": "set_terminal", "id": 3, "terminal": 0}), "", "an area is split off into a new terminal")
	_expect(sim.areas.list[3].terminal, 3, "which gets the next number")
	_expect(sim.apply({"op": "set_terminal", "id": 3, "terminal": 7}), "No such terminal", "a missing terminal is refused")
	sim.apply({"op": "remove_area", "id": 3})
	_expect(sim.areas.terminals.keys(), [1], "removing a terminal's last area removes the terminal")


func _test_unconnected_areas() -> void:
	var sim := PortSim.new(0, Content.base(), true)
	sim.apply({"op": "build_road", "from": Vector2i(100, 100), "to": Vector2i(100, 140), "type": "terminal_1_1"})
	sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": -1, "from": 0, "to": 29})
	_expect(sim.areas.idle_reason(1), "", "a yard block along its road works")
	var lines := Inspect.describe(sim, Inspect.pick(sim, PortMap.NONE, sim.areas.cells(1)[5]))
	_expect(lines, ["Yard block", "Terminal 1", "Import block, reach stacker", "Working"] as Array[String], "inspecting an area shows its type, terminal, rules and state")
	sim.apply({"op": "remove_road", "segment": 1})
	_expect(sim.areas.idle_reason(1), "No road runs along this yard block", "with its road gone it does no work, and says why")
	_expect(Inspect.describe(sim, {"area": 1})[-1], "No road runs along this yard block", "the inspect panel shows why")
	sim.apply({"op": "build_road", "from": Vector2i(100, 120), "to": Vector2i(100, 160), "type": "terminal_1_1"})
	_expect(sim.areas.idle_reason(1), "", "a road along part of its front reconnects it")
	_expect(Inspect.describe(sim, {"area": 9}), [] as Array[String], "an area that went shows nothing")


func _test_handovers() -> void:
	var sim := PortSim.new(0, Content.base(), true)
	sim.apply({"op": "build_road", "from": Vector2i(100, 100), "to": Vector2i(100, 140), "type": "terminal_1_1"})
	# 12 cells: 4 bays, so 4 slots and room for 4 in the buffer strip.
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": -1, "from": 0, "to": 11}), "", "a 4-bay yard block is built")
	var block := 1
	var handovers := Handovers.new(sim.areas)
	var got := []
	for id in range(1, 11):
		got.append(handovers.arrive(block, id))
	_expect(got, ["slot", "slot", "slot", "slot", "buffer", "buffer", "buffer", "buffer", "road", "road"], "vehicles take slots, then the buffer strip, then queue on the road")
	_expect(handovers.waiting(block), {"buffer": [5, 6, 7, 8], "road": [9, 10]}, "a full block shows a road queue")
	handovers.leave(block, 2)
	_expect(handovers.slot_of(block, 5), 1, "a freed slot goes to the first vehicle in the buffer")
	_expect(handovers.waiting(block), {"buffer": [6, 7, 8, 9], "road": [10]}, "and the first on the road moves into the buffer")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var holding := [1, 3, 4, 5]
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
		too_many = too_many or holding.size() > 4
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
	_expect(ticks, ceili(seconds / SimClock.TICK_SECONDS), "one move takes the data's time (%.1f s)" % seconds)
	_expect(phases, ["travel", "lift", "travel", "set_down"], "in the phases travel, lift, travel and set down")
	_expect(machines.list[rtg].bay, 8, "the machine ends where it set the box down")
	_expect(machines.phase(rtg), "", "and is idle")
	var stacker := machines.add(1, "reach_stacker", 8)
	machines.give(stacker, 8, 8)
	var lift_only := 0
	while machines.tick().is_empty():
		lift_only += 1
	_expect(lift_only + 1, ceili((gear.reach_stacker.lift_seconds + gear.reach_stacker.set_down_seconds) / SimClock.TICK_SECONDS), "a move within one bay is just lift and set down")


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


func _test_driveways() -> void:
	var sim := PortSim.new(0, Content.base(), true)
	var entry := sim.site_entry()
	# A 1+1 road from the site entry west to the coast. Drawn west, its right is
	# north: the westbound lane is the drawn row 300 and the eastbound lane row 301.
	sim.apply({"op": "build_road", "from": entry, "to": Vector2i(85, entry.y), "type": "terminal_1_1"})
	var road := sim.roads.segment_at(Vector2i(200, entry.y))
	sim.apply({"op": "build_area", "type": "yard_block", "segment": road, "side": -1, "from": 100, "to": 129})
	sim.apply({"op": "build_area", "type": "yard_block", "segment": road, "side": 1, "from": 100, "to": 129})
	var south: Dictionary = sim.areas.layout(1)
	var north: Dictionary = sim.areas.layout(2)
	var slot: Vector2i = south.slots[4][1]
	var inbound := _inbound(sim, entry)
	var there := sim.lanes.route(inbound, slot, true)
	_expect(there.is_empty(), false, "a lorry routes from the site entry into a yard slot")
	_expect(there.any(func(c: Vector2i) -> bool: return c in south.buffer), true, "through the block's buffer strip")
	_expect(_steps_are_single(there), true, "a cell at a time")
	var back := sim.lanes.route(slot, _outbound(sim, entry), true)
	_expect(back.is_empty(), false, "and from the slot back out to the site exit")
	var other := sim.lanes.route(inbound, north.slots[2][1], true)
	_expect(other.is_empty(), false, "blocks on both sides of a road are reached, each with its own flow")
	var parked: Vector2i = north.slots[3][1]
	var past := sim.lanes.route(inbound, north.slots[5][1], true)
	_expect(parked in past, false, "a slot is never driven through on the way to another")
	# Drawn south at x = 85, its right (west) side reaches the sea.
	sim.apply({"op": "build_road", "from": Vector2i(85, 200), "to": Vector2i(85, 300), "type": "terminal_1_1"})
	var coast := sim.roads.segment_at(Vector2i(85, 250))
	_expect(sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 10, "to": 39}), "", "an apron is built on the coast")
	var apron: Dictionary = sim.areas.layout(sim.areas.list.keys()[-1])
	var under_crane: Vector2i = apron.slots[7][1]
	_expect(sim.lanes.route(inbound, under_crane, false).is_empty(), false, "a tractor routes under the cranes")
	_expect(sim.lanes.route(inbound, under_crane, true), [] as Array[Vector2i], "a lorry can't drive onto an apron")


## A lane cell at the site entry a vehicle can drive in from.
func _inbound(sim: PortSim, entry: Vector2i) -> Vector2i:
	for y in range(entry.y - 4, entry.y + 5):
		if not sim.lanes.route(Vector2i(entry.x, y), Vector2i(entry.x - 3, y), true).is_empty():
			return Vector2i(entry.x, y)
	return PortMap.NONE


## A lane cell at the site entry a vehicle can drive out on.
func _outbound(sim: PortSim, entry: Vector2i) -> Vector2i:
	for y in range(entry.y - 4, entry.y + 5):
		if not sim.lanes.route(Vector2i(entry.x - 3, y), Vector2i(entry.x, y), true).is_empty():
			return Vector2i(entry.x, y)
	return PortMap.NONE


## Whether `layout`'s parts, other than the lanes slots lie in, cover `cells`
## exactly once each.
func _covers_once(layout: Dictionary, cells: Array[Vector2i]) -> bool:
	var used := {}
	var parts: Array = [layout.buffer, layout.edge] + layout.rails + layout.slots
	for part: Array in parts:
		for cell: Vector2i in part:
			if cell in used:
				return false
			used[cell] = true
	return cells.all(func(c: Vector2i) -> bool: return c in used)


func _steps_are_single(cells: Array[Vector2i]) -> bool:
	for i in cells.size() - 1:
		var d := (cells[i + 1] - cells[i]).abs()
		if maxi(d.x, d.y) != 1:
			return false
	return true


func _node(net: RoadNet, cell: Vector2i) -> int:
	return net.nodes.find_key(cell)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
