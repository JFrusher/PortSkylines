extends SceneTree
## M8 steps I and J, and the exit criterion: with the channel the
## bottleneck, the queue at anchor grows, and it shrinks when the player
## widens the channel or adds pilots. The port charges dues per call and a
## fee per piloted passage.
## godot --headless --script res://tests/test_channel.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_widening()
	_test_port_fees()
	_test_channel_bottleneck()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Two berths on the test port, feeders of one move each way so the berths
## are never what holds ships up (`pilot` or not), `pilots` pilots at a
## station by the south edge, and one long narrow lane in from the sea at
## the north edge down past both berths, a branch to each, and an anchorage
## where the first branch leaves it, near the berths.
func _port(pilot: bool, pilots: int) -> PortSim:
	var rules := RandomPort.quick()
	rules.ship_classes.feeder.pilot = pilot
	rules.ship_classes.feeder.import_moves = 1
	rules.ship_classes.feeder.export_moves = 1
	var sim := AreaPort.base(rules, "")
	sim.creative = true
	var entry := sim.site_entry()
	sim.apply({"op": "build_road", "from": Vector2i(86, entry.y), "to": Vector2i(86, entry.y + 90), "type": "terminal_1_1"})
	var coast := sim.roads.segment_at(Vector2i(85, entry.y + 50))
	_expect(sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 5, "to": 84}), "", "a second apron")
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": sim.areas.list.keys().max(), "along": 30}), "", "with a crane")
	for segment: int in sim.ship_lanes.segments.keys():
		sim.apply({"op": "remove_ship_lane", "segment": segment})
	var rows: Array[int] = []
	for apron: int in [1, sim.areas.list.keys().max()]:
		var cells := RoadNet.line(sim.areas.list[apron].start, sim.areas.list[apron].end)
		rows.append(cells[cells.size() / 2].y)
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(30, 0), "to": Vector2i(30, rows[1]), "type": "narrow"}), "", "a long narrow lane in from the north")
	for row: int in rows:
		_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(68, row), "to": Vector2i(30, row), "type": "narrow"}), "", "a branch to a berth")
	_expect(sim.apply({"op": "build_anchorage", "from": Vector2i(0, rows[0] - 50), "to": Vector2i(49, rows[0] + 49)}), "", "an anchorage where the first branch leaves the lane")
	_expect(sim.apply({"op": "build_pilot_station", "cell": Vector2i(66, 590)}), "", "a pilot station by the south edge")
	if pilots > 0:
		sim.apply({"op": "hire_pilots", "station": 1, "count": pilots})
	sim.buy_tractors(6)
	sim.creative = false
	sim.ledger.cash = 100_000_000
	RandomPort.calls(sim, "feeder", 10, 8, 40)
	return sim


## The average number of ships waiting at anchor or out at sea, over hours 2 to 6.
func _queue(sim: PortSim) -> float:
	var total := 0
	var looks := 0
	for i in roundi(6 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if sim.clock.calendar_minutes() >= 120.0 and i % 200 == 0:
			total += sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.state in [PortSim.Ship.State.ANCHORED, PortSim.Ship.State.ANCHORING]).size()
			looks += 1
	return float(total) / looks


func _test_widening() -> void:
	var sim := _port(false, 0)
	var trunk: int = sim.ship_lanes.segment_at(Vector2i(30, 100))
	_expect(sim.widen_ship_lane_error(trunk), "", "the trunk out at sea can be widened")
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(62, 450), "to": Vector2i(62, 500), "type": "narrow"}), "", "a narrow lane along the shore")
	_expect(sim.widen_ship_lane_error(sim.ship_lanes.segment_at(Vector2i(62, 470))).begins_with("A wide lane needs open water"), true, "is too near the land to widen")
	var before := sim.money
	_expect(sim.apply({"op": "widen_ship_lane", "segment": trunk}), "", "widening the trunk")
	_expect(sim.ship_lanes.segments[trunk].type, "wide", "it is wide")
	var lane: Dictionary = sim.ship_lanes.segments[trunk]
	_expect(before - sim.money, sim.ship_lane_price(sim.ship_lanes.nodes[lane.a], sim.ship_lanes.nodes[lane.b], "wide"), "at a wide lane's price")
	_expect(sim.widen_ship_lane_error(trunk), "This lane is wide already", "only once")


func _test_port_fees() -> void:
	var sim := _port(true, 2)
	for i in roundi(30.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	var calls: int = sim._next_ship - 1
	_expect(calls > 0, true, "feeders called")
	_expect(sim.ledger.today.get("port_dues", 0), calls * sim.rules.ship_classes.feeder.port_dues, "each call pays its port dues")
	_expect(sim.ledger.today.get("pilotage", 0) > 0 and sim.ledger.today.pilotage % sim.rules.water.pilots.fee == 0, true, "each piloted passage pays the pilotage fee (%d)" % sim.ledger.today.get("pilotage", 0))


## Ships every 8 minutes through one long narrow lane: the queue at anchor
## grows, and widening the lane shrinks it. With pilots needed, one pilot
## holds the queue up and four let it shrink.
func _test_channel_bottleneck() -> void:
	var narrow := _queue(_port(false, 0))
	var widened := _port(false, 0)
	widened.creative = true
	widened.apply({"op": "widen_ship_lane", "segment": widened.ship_lanes.segment_at(Vector2i(30, 100))})
	widened.creative = false
	var wide := _queue(widened)
	_expect(narrow > 3.0, true, "through a narrow channel the queue grows (%.1f ships waiting)" % narrow)
	_expect(wide < narrow / 2.0, true, "widening it shrinks the queue (%.1f against %.1f)" % [wide, narrow])
	var one := _queue(_with_wide_trunk(_port(true, 1)))
	var four := _queue(_with_wide_trunk(_port(true, 4)))
	_expect(one > 3.0, true, "with pilots needed and one pilot, the queue grows (%.1f)" % one)
	_expect(four < one / 2.0, true, "four pilots shrink it (%.1f against %.1f)" % [four, one])


func _with_wide_trunk(sim: PortSim) -> PortSim:
	sim.creative = true
	sim.apply({"op": "widen_ship_lane", "segment": sim.ship_lanes.segment_at(Vector2i(30, 100))})
	sim.creative = false
	return sim
