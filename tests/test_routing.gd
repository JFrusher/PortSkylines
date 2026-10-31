extends SceneTree
## M7's routing scenarios: lorries go round a jam once its delay builds up.
## godot --headless --script res://tests/test_routing.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_lorries_take_the_way_round_a_jam()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## AreaPort.base's port with a bypass looping 30 cells north of the east road,
## from x = 420 to x = 560, and a broken-down lorry in the westbound lane at
## x = 500 that never moves. Lorries coming in from the east queue behind it
## until a route epoch has seen the delay; after that, new lorries go round.
func _test_lorries_take_the_way_round_a_jam() -> void:
	var sim := AreaPort.base(RandomPort.rules(), "")
	var y := sim.site_entry_point().y
	sim.creative = true
	for leg: Array in [[Vector2i(560, y), Vector2i(560, y - 30)], [Vector2i(560, y - 30), Vector2i(420, y - 30)], [Vector2i(420, y - 30), Vector2i(420, y)]]:
		_expect(sim.apply({"op": "build_road", "from": leg[0], "to": leg[1], "type": "terminal_1_1"}), "", "a bypass leg is built")
	sim.creative = false
	var east := sim.roads.segment_at(Vector2i(500, y))
	var westbound: Array = sim.roads.lanes(east).filter(func(lane: Dictionary) -> bool: return not lane.forward)[0].cells
	var broken := Vehicle.new(999999, "lorry", [westbound.filter(func(c: Vector2i) -> bool: return c.x == 500)[0]] as Array[Vector2i])
	_expect(sim.lane_traffic.place(broken), true, "the broken-down lorry stands in the westbound lane")
	RandomPort.calls(sim, "feeder", 10, 45, 1)
	var round := {}  # lorry id -> true once it is routed over the bypass
	var straight := {}
	var epoch := roundi(sim.rules.traffic.route_epoch_seconds / SimClock.TICK_SECONDS)
	var seen := {}
	for i in roundi(3 * 60 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for v: Vehicle in sim.vehicles:
			if v.id in seen:
				continue
			seen[v.id] = true
			# Lorries just in from the east, on their first route, once two epochs have seen the jam.
			if sim.clock.ticks > epoch * 2 and v.kind == "lorry" and v.gate_in < 0.0 and v.path[0].x > 560:
				if v.path.any(func(c: Vector2i) -> bool: return c.y < y - 5):
					round[v.id] = true
				else:
					straight[v.id] = true
	_expect(round.size() > 0, true, "once the jam is seen, lorries from the east are routed round it (%d round, %d straight)" % [round.size(), straight.size()])
	_expect(round.size() >= 4 * straight.size(), true, "and most of them (%d round, %d straight)" % [round.size(), straight.size()])
