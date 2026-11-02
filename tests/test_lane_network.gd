extends SceneTree
## M10 step 8a: the lane network, built from the roads' curves: each lane a
## piece, cut back at junctions, joined across them by connection pieces
## under M7's turn rules, end to end round a bend, and back on itself at a
## dead end; routes run over pieces.
## godot --headless --script res://tests/test_lane_network.gd

const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_a_straight_road()
	_test_a_t_junction()
	_test_a_bend_carries_every_lane()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A sim with `roads` ([from, to, type]) built on the land it owns.
func _roads(roads: Array) -> PortSim:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	for road: Array in roads:
		_expect(sim.apply({"op": "build_road", "from": road[0], "to": road[1], "type": road[2]}), "", "a road from %s to %s is built" % [road[0], road[1]])
	return sim


## Every piece ends where each piece it leads into starts.
func _joined(network: LaneNetwork, what: String) -> void:
	for id: int in network.pieces:
		var piece: Dictionary = network.pieces[id]
		for next: int in piece.next:
			_expect(piece.points[-1].distance_to(network.pieces[next].points[0]) < 0.001, true, "%s: piece %d runs on into piece %d" % [what, id, next])


## The lane piece of `segment` whose line runs through `position`.
func _piece_at(network: LaneNetwork, position: Vector2) -> int:
	for id: int in network.pieces:
		var piece: Dictionary = network.pieces[id]
		if piece.segment != 0 and Geometry2D.get_closest_point_to_segment(position, piece.points[0], piece.points[-1]).distance_to(position) < 0.01:
			return id
	return 0


## A 1+1 road east: a lane each way, 40 cells long, and at each dead end a
## piece turning back from one lane into the other.
func _test_a_straight_road() -> void:
	var sim := _roads([[Vector2i(100, 250), Vector2i(140, 250), "terminal_1_1"]])
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	var lanes := network.pieces.values().filter(func(p: Dictionary) -> bool: return p.segment != 0)
	_expect(lanes.size(), 2, "a lane piece each way")
	_expect(lanes.all(func(p: Dictionary) -> bool: return absf(p.length - 40.0) < 0.01), true, "each 40 cells long")
	_expect(network.pieces.size(), 4, "and a turn back at each end")
	_joined(network, "a straight road")
	var east := _piece_at(network, Vector2(120, 250.5))
	var west := _piece_at(network, Vector2(120, 249.5))
	_expect(network.route(east, west), [east, network.pieces[east].next[0], west], "from the eastbound lane, the way west turns back at the east end")


## A 2+2 road east-west with a 2+2 stem south from its middle: coming in from
## the west, the right lane turns south; the left lane may not, so its way
## south goes on east and turns back.
func _test_a_t_junction() -> void:
	var sim := _roads([[Vector2i(100, 250), Vector2i(160, 250), "terminal_2_2"], [Vector2i(130, 250), Vector2i(130, 290), "terminal_2_2"]])
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	_joined(network, "a T")
	# Eastbound lanes run 0.5 and 1.5 cells south of the line; the right one is further out.
	var left := _piece_at(network, Vector2(110, 250.5))
	var right := _piece_at(network, Vector2(110, 251.5))
	var south := _piece_at(network, Vector2(129.5, 280))
	_expect([left != 0, right != 0, south != 0], [true, true, true], "the lanes are found")
	var turning := network.route(right, south)
	_expect(turning.size(), 3, "the right lane turns south through one connection")
	var round := network.route(left, south)
	_expect(network.length(round) > network.length(turning) + 20.0, true, "the left lane goes round (%.0f cells against %.0f)" % [network.length(round), network.length(turning)])


## A 2+2 road bending a right angle at a node with no other road: each
## lane coming in carries on into one lane going out.
func _test_a_bend_carries_every_lane() -> void:
	var sim := _roads([[Vector2i(100, 250), Vector2i(140, 250), "terminal_2_2"], [Vector2i(140, 250), Vector2i(140, 290), "terminal_2_2"]])
	var network := LaneNetwork.new(sim.roads, sim.rules.junctions)
	_joined(network, "a bend")
	for position: Vector2 in [Vector2(120, 250.5), Vector2(120, 251.5)]:
		var lane := _piece_at(network, position)
		_expect(network.pieces[lane].next.size(), 1, "the lane at %s carries on round the bend" % position)
