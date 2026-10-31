extends SceneTree
## Junctions on the lane graph: every turn drives forward through the
## junction and never back over a cell; a vehicle can turn back at a
## junction, not only at a dead end; every cell where two roads' lanes
## overlap is a junction cell, so nobody stops inside the box; and traffic
## from every arm to every other arm gets through a crossing.
## godot --headless --script res://tests/test_junctions.gd

const SPEED := 3.0

var _failures := 0
var _next_id := 1


func _initialize() -> void:
	for type: String in ["terminal_1_1", "terminal_2_2"]:
		_test_turns(type, true)
		_test_turns(type, false)
		_test_turn_back(type)
		_test_box_is_junction(type)
		_test_crossing_traffic(type)
	_test_lane_rules()
	_test_both_lanes_carry()
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


func _test_crossing_traffic(type: String) -> void:
	var lanes := LaneGraph.new(_net(type, true))
	var traffic := LaneTraffic.new(lanes, Junctions.new(Content.base().traffic))
	var arms := _arms(true)
	var waiting := {}  # arm -> routes still to start there
	for from: String in arms:
		waiting[from] = []
		for i in 3:
			for to: String in arms:
				if to != from:
					waiting[from].append(lanes.route(arms[from][0], arms[to][1], true))
	var vehicles: Array[Vehicle] = []
	var shared := false
	for tick in 4000:
		for from: String in arms:
			if not waiting[from].is_empty():
				var vehicle := Vehicle.new(_next_id, "lorry", waiting[from][0])
				if traffic.place(vehicle):
					_next_id += 1
					waiting[from].pop_front()
					vehicles.append(vehicle)
		var cells := {}
		for vehicle in vehicles:
			if vehicle.at_end():
				continue
			if traffic.advance(vehicle, SPEED):
				traffic.leave(vehicle)
				continue
			var cell := vehicle.path[int(vehicle.t)]
			shared = shared or cell in cells
			cells[cell] = true
	var started := waiting.values().all(func(w: Array) -> bool: return w.is_empty())
	var through := vehicles.filter(func(v: Vehicle) -> bool: return v.at_end()).size()
	_expect(started and through == vehicles.size(), true, "%s crossing: all 36 vehicles, every arm to every other, get through (%d of %d through)" % [type, through, vehicles.size()])
	_expect(shared, false, "%s crossing: no two vehicles are ever in one cell" % type)


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


## M7's lane-use exit criterion: forty lorries come in at the west end of a
## 2+2 road to a T, all in its left lane, every other one bound south. Those
## change into the right lane before the box, so both lanes carry traffic,
## and every lorry gets through. (Shortest routes already split them so
## before the turn rules; this keeps it so.)
func _test_both_lanes_carry() -> void:
	var lanes := LaneGraph.new(_net("terminal_2_2", false))
	var traffic := LaneTraffic.new(lanes, Junctions.new(Content.base().traffic))
	var waiting := 40
	var moving: Array[Vehicle] = []
	var rows := {}  # row each lorry drove at x = 15 -> lorries
	var through := 0
	for tick in 4000:
		if waiting > 0 and traffic.holder(Vector2i(0, 20)) == 0:
			var to := Vector2i(19, 39) if waiting % 2 == 0 else Vector2i(20, 0)
			var lorry := Vehicle.new(_next_id, "lorry", lanes.route(Vector2i(0, 20), to, true))
			_next_id += 1
			if traffic.place(lorry):
				moving.append(lorry)
				waiting -= 1
		for lorry: Vehicle in moving.duplicate():
			if traffic.advance(lorry, SPEED):
				var row: int = lorry.path.filter(func(c: Vector2i) -> bool: return c.x == 15)[0].y
				rows[row] = rows.get(row, 0) + 1
				traffic.leave(lorry)
				moving.erase(lorry)
				through += 1
	_expect(through, 40, "every lorry gets through the T")
	_expect([rows.get(20, 0), rows.get(21, 0)], [20, 20], "at x = 15 the left lane carries those turning left, the right lane those turning right")
