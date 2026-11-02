extends SceneTree
## Junctions on the lane graph: every turn drives forward through the
## junction and never back over a cell; a vehicle can turn back at a
## junction, not only at a dead end; every cell where two roads' lanes
## overlap is a junction cell, so nobody stops inside the box. (Traffic
## through junctions is test_traffic's and test_traffic_junctions'.)
## godot --headless --script res://tests/test_junctions.gd


var _failures := 0


func _initialize() -> void:
	for type: String in ["terminal_1_1", "terminal_2_2"]:
		_test_turns(type, true)
		_test_turns(type, false)
		_test_turn_back(type)
		_test_box_is_junction(type)
	_test_lane_rules()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## A road south down grid line x = 20 from y = 0 to 40, and one east along
## grid line y = 20 from x = 0 to 40 (or to 20 for a T). Traffic keeps right
## and the inner lanes sit either side of each line, so columns 19 and rows
## 20 are the in-lanes from north and west, and column 20 and row 19 the
## lanes back out; a road's cells run 0 to 39 between points 0 and 40.
func _net(type: String, crossing: bool) -> RoadNet:
	var net := RoadNet.new(Content.base().road_types)
	_expect(net.add(Vector2i(20, 0), Vector2i(20, 40), type), "", "%s north-south road is built" % type)
	_expect(net.add(Vector2i(0, 20), Vector2i(40 if crossing else 20, 20), type), "", "%s east-west road is built" % type)
	return net


## Each arm: [cell driving in, cell driving out].
func _arms(crossing: bool) -> Dictionary:
	var arms := {
		"north": [Vector2i(19, 0), Vector2i(20, 0)],
		"south": [Vector2i(20, 39), Vector2i(19, 39)],
		"west": [Vector2i(0, 20), Vector2i(0, 19)],
	}
	if crossing:
		arms.east = [Vector2i(39, 19), Vector2i(39, 20)]
	return arms


func _test_turns(type: String, crossing: bool) -> void:
	var lanes := LaneGraph.new(_net(type, crossing))
	var arms := _arms(crossing)
	var shape := "%s %s" % [type, "crossing" if crossing else "T"]
	for from: String in arms:
		for to: String in arms:
			if from == to:
				continue
			var route := lanes.route(arms[from][0], arms[to][1], true)
			_expect(route.is_empty(), false, "%s: %s to %s has a route" % [shape, from, to])
			var seen := {}
			var again: Array[Vector2i] = []
			for cell in route:
				if cell in seen:
					again.append(cell)
				seen[cell] = true
			_expect(again, [] as Array[Vector2i], "%s: %s to %s never drives back over a cell" % [shape, from, to])
			# 40 cells in, 40 out of a 4-cell box: anything much longer is a detour.
			_expect(route.size() <= 48, true, "%s: %s to %s takes no detour (%d cells)" % [shape, from, to, route.size()])


func _test_turn_back(type: String) -> void:
	var lanes := LaneGraph.new(_net(type, false))
	# Southbound 15 cells north of the T, back to where it started, northbound.
	var route := lanes.route(Vector2i(19, 5), Vector2i(20, 5), true)
	_expect(route.size() > 0 and route.size() <= 40, true, "%s: a vehicle turns back at the junction, not the dead end 20 cells on (%d cells)" % [type, route.size()])


func _test_box_is_junction(type: String) -> void:
	var net := _net(type, true)
	var lanes := LaneGraph.new(net)
	var lane_cells := {}  # cell -> segments whose lanes cover it
	for segment: int in net.segments:
		for lane in net.lanes(segment):
			for cell: Vector2i in lane.cells:
				lane_cells[cell] = lane_cells.get(cell, {})
				lane_cells[cell][segment] = true
	var open: Array[Vector2i] = []
	for cell: Vector2i in lane_cells:
		if lane_cells[cell].size() > 1 and not lanes.is_junction(cell):
			open.append(cell)
	_expect(open, [] as Array[Vector2i], "%s crossing: every cell two roads' lanes share is a junction cell" % type)




func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## On a 2+2 crossing, a lorry on the last cell of a lane from the west before
## the junction box (x = 17), where lanes may no longer change: from the left
## lane (row 20) it turns left
## (north) or goes straight, from the right lane (row 21) it turns right
## (south) or goes straight. A turn its lane doesn't allow means a detour.
func _test_lane_rules() -> void:
	var lanes := LaneGraph.new(_net("terminal_2_2", true))
	var left := Vector2i(17, 20)
	var right := Vector2i(17, 21)
	var north := Vector2i(20, 0)
	var south := Vector2i(19, 39)
	var east := Vector2i(39, 20)
	var size := func(from: Vector2i, to: Vector2i) -> int: return lanes.route(from, to, true).size()
	_expect(size.call(left, north) <= 24, true, "the left lane turns left (%d cells)" % size.call(left, north))
	_expect(size.call(right, north) > size.call(left, north) + 8, true, "the right lane can't turn left: it goes round (%d cells)" % size.call(right, north))
	_expect(size.call(right, south) <= 24, true, "the right lane turns right (%d cells)" % size.call(right, south))
	_expect(size.call(left, south) > size.call(right, south) + 8, true, "the left lane can't turn right: it goes round (%d cells)" % size.call(left, south))
	_expect([size.call(left, east) <= 24, size.call(right, east) <= 24], [true, true], "both lanes go straight on (%d, %d cells)" % [size.call(left, east), size.call(right, east)])

