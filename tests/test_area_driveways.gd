extends SceneTree
## M10 step 6c-2b: areas' driveways built from their layouts on their own
## cells, as Cities: Skylines' parking lots are: the buffer strip (and an
## apron's through lane, a gate's lanes) a lane along its cells' middles,
## each slot entered sideways from it and left sideways one cell on, ending
## at its last cell where a vehicle stands, and the road lane beside the
## buffer's ends split for a way in and out.
## godot --headless --script res://tests/test_area_driveways.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_every_slot_and_booth_is_reached()
	_test_lanes_run_through_the_cells_middles()
	_test_driveways_bend_with_their_area()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _network(sim: PortSim) -> LaneNetwork:
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	network.add_driveways(sim.areas, sim.rules.traffic.area_kmh)
	return network


## Area `id`'s cell `cell`'s middle.
func _centre(sim: PortSim, id: int, cell: Vector2i) -> Vector2:
	for found: Dictionary in sim.areas.shape(id).cells:
		if Vector2i(found.k, found.r) == cell:
			return found.centre
	return Vector2.INF


## The cells of `cells` in the order traffic drives them in area `id`.
func _driven(network: LaneNetwork, id: int, cells: Array) -> Array:
	var found := cells.duplicate()
	if network.flows[id] < 0:
		found.reverse()
	return found


## The test port's yard block, apron and gate: from the site entry, a route
## reaches the end of every slot and booth, where a vehicle stands, and from
## there a route leads back to the entry.
func _test_every_slot_and_booth_is_reached() -> void:
	var sim := AreaPort.base()
	var network := _network(sim)
	var start := network.split_at(Vector2(sim.site_entry_point() - Vector2i(1, 0)) + Vector2(0.5, 0.5))
	_expect(start != 0, true, "the lane at the site entry is found")
	var kinds := {}
	for id: int in sim.areas.list:
		if id not in network.flows:
			continue
		var layout := sim.areas.local_layout(id)
		for s: int in layout.get("slots", []).size():
			var stand: Vector2i = _driven(network, id, layout.slots[s])[-1]
			var ends := network.ending_at(_centre(sim, id, stand))
			_expect(ends.is_empty(), false, "a piece ends where a vehicle stands in area %d's slot %d" % [id, s])
			if ends.is_empty():
				continue
			_expect(network.route(start, ends[0]).is_empty(), false, "area %d's slot %d is reached from the entry" % [id, s])
			_expect(network.route(ends[0], start).is_empty(), false, "and left again for the entry")
			kinds[sim.areas.kind_of(sim.areas.list[id])] = true
	_expect(kinds.keys().size() >= 3, true, "yard block, apron and gate slots are all among them (%s)" % [kinds.keys()])


## Every lane piece in an area runs from one of its cells' middles to
## another's, as the lanes of the port's yard block do.
func _test_lanes_run_through_the_cells_middles() -> void:
	var sim := AreaPort.base()
	var network := _network(sim)
	var middles := {}
	for id: int in network.flows:
		for cell: Dictionary in sim.areas.shape(id).cells:
			middles[LaneNetwork._key(cell.centre)] = true
	var inside := network.pieces.values().filter(func(p: Dictionary) -> bool: return p.area != 0 and LaneNetwork._key(p.points[0]) in middles and LaneNetwork._key(p.points[-1]) in middles)
	_expect(inside.size() > 20, true, "the areas' lanes and slots start and end at cells' middles (%d pieces)" % inside.size())


## The yard block's road curve bent 6 cells out at its middle: its cells
## bend, and so do its lanes, and every slot is still reached from the
## buffer's first piece.
func _test_driveways_bend_with_their_area() -> void:
	var sim := AreaPort.base()
	var block: int = sim.areas.list.keys().filter(func(id: int) -> bool: return sim.areas.kind_of(sim.areas.list[id]) == "yard_block")[0]
	var area: Dictionary = sim.areas.list[block]
	var a: Vector2 = area.curve[0]
	var b: Vector2 = area.curve[2]
	area.curve = [a, (a + b) / 2.0 + (b - a).normalized().orthogonal() * 6.0, b]
	sim.areas.version += 1
	var network := _network(sim)
	var layout := sim.areas.local_layout(block)
	var first: Vector2i = _driven(network, block, layout.buffer)[0]
	var starts := network.pieces.keys().filter(func(id: int) -> bool: return network.pieces[id].area == block and network.pieces[id].slot == LaneNetwork.NO_SLOT and network.pieces[id].points[0].distance_to(_centre(sim, block, first)) < 0.001)
	_expect(starts.is_empty(), false, "a lane leaves the buffer's first cell")
	var off_grid := network.pieces.values().filter(func(p: Dictionary) -> bool: return p.area == block and absf(p.points[0].y - roundf(p.points[0].y - 0.5) - 0.5) > 0.01)
	_expect(off_grid.is_empty(), false, "the bent block's lanes leave the grid's rows")
	for s: int in layout.slots.size():
		var ends := network.ending_at(_centre(sim, block, _driven(network, block, layout.slots[s])[-1]))
		_expect(not ends.is_empty() and not starts.is_empty() and not network.route(starts[0], ends[0]).is_empty(), true, "slot %d on the bend is reached from the buffer" % s)
