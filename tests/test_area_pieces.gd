extends SceneTree
## M10 step 8c: areas' insides join the lane network as pieces, imported
## from today's lane graph: buffers, drive-through lanes, slots and their
## driveways, each edge a short piece ending at a cell's middle, the road's
## lane split where a driveway leaves it. A route takes an area's pieces only
## when it starts or ends in that area, and a slot only as its end.
## godot --headless --script res://tests/test_area_pieces.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_every_slot_is_reached_like_today()
	_test_roads_dont_cut_through_areas()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _network(sim: PortSim) -> LaneNetwork:
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	network.add_areas(sim.lanes, sim.rules.traffic.area_kmh)
	return network


## The test port's yard block, apron and gate: from the site entry to the
## middle of every slot and back, the network has a route about as long as
## today's lane graph does.
func _test_every_slot_is_reached_like_today() -> void:
	var sim := AreaPort.base()
	var network := _network(sim)
	var entry := sim.site_entry_point() - Vector2i(1, 0)
	var start: Array = [network.split_at(Vector2(entry) + Vector2(0.5, 0.5))]
	_expect(start[0] != 0, true, "the lane at the site entry is found")
	for area: int in sim.areas.list:
		var layout := sim.areas.layout(area)
		for s: int in layout.get("slots", []).size():
			var slot: Vector2i = layout.slots[s][1]
			var today := sim.lanes.route(entry, slot, sim.areas.list[area].type != "quay_apron")
			var ends: Array = network.ending_at(Vector2(slot) + Vector2(0.5, 0.5))
			_expect(ends.is_empty(), false, "a piece ends at area %d's slot %d" % [area, s])
			if today.is_empty() or ends.is_empty() or start.is_empty():
				continue
			var there := network.route(start[0], ends[0])
			_expect(there.is_empty(), false, "area %d's slot %d is reached from the entry" % [area, s])
			_expect(absf(network.length(there) - today.size()) < today.size() * 0.15, true, "as far as today (%.0f cells against %d)" % [network.length(there), today.size()])
			var back := network.route(ends[0], start[0])
			_expect(back.is_empty(), false, "and left again for the entry")


## From the site entry to the coast road's far end, a route keeps to roads.
func _test_roads_dont_cut_through_areas() -> void:
	var sim := AreaPort.base()
	var network := _network(sim)
	var entry := sim.site_entry_point() - Vector2i(1, 0)
	var start: Array = [network.split_at(Vector2(entry) + Vector2(0.5, 0.5))]
	var far := network.pieces.keys().filter(func(id: int) -> bool: return network.pieces[id].segment != 0 and network.pieces[id].points[-1].y < 205.0)
	_expect(far.is_empty(), false, "a lane runs to the coast road's north end")
	var route := network.route(start[0], far[0])
	_expect(route.is_empty(), false, "the north end is reached")
	_expect(route.any(func(id: int) -> bool: return network.pieces[id].area != 0), false, "without entering an area")
