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
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## A road south along x = 20 from y = 0 to 40, and one east along y = 20 from
## x = 0 to 40 (or to 20 for a T). Southbound and eastbound lanes are on the
## drawn lines, so x = 20 and y = 20 are in-lanes from north and west, and
## x = 21 and y = 19 the lanes back out.
func _net(type: String, crossing: bool) -> RoadNet:
	var net := RoadNet.new(Content.base().road_types)
	_expect(net.add(Vector2i(20, 0), Vector2i(20, 40), type), "", "%s north-south road is built" % type)
	_expect(net.add(Vector2i(0, 20), Vector2i(40 if crossing else 20, 20), type), "", "%s east-west road is built" % type)
	return net


## Each arm: [cell driving in, cell driving out].
func _arms(crossing: bool) -> Dictionary:
	var arms := {
		"north": [Vector2i(20, 0), Vector2i(21, 0)],
		"south": [Vector2i(21, 40), Vector2i(20, 40)],
		"west": [Vector2i(0, 20), Vector2i(0, 19)],
	}
	if crossing:
		arms.east = [Vector2i(40, 19), Vector2i(40, 20)]
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
	var route := lanes.route(Vector2i(20, 5), Vector2i(21, 5), true)
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
	var traffic := LaneTraffic.new(lanes)
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
