extends SceneTree
## M8 step K: ULCVs, unlocked at the fifth milestone, need the mega STS
## crane's 24-row reach, and call light-loaded, with fewer moves, where the
## water is too shallow for their full draft but deep enough for their
## light draft.
## godot --headless --script res://tests/test_ulcv.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_gating()
	_test_it_needs_the_mega_crane()
	_test_light_loaded_calls()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_gating() -> void:
	var sim := PortSim.new(1, RandomPort.strait())
	var mega: Dictionary = sim.milestones()[4]
	for name: String in ["ulcv", "mega_sts"]:
		_expect(sim.lock_error(name), "Unlocked at milestone 5: %d TEU across the quay" % mega.teu, "%s waits for the fifth milestone" % name)
	_expect(sim.build_berth_error("ulcv", Vector2i(80, 300)), "Unlocked at milestone 5: %d TEU across the quay" % mega.teu, "so does the ULCV berth")
	_expect(PortSim.new(1, RandomPort.quick()).lock_error("ulcv"), "", "every milestone reached unlocks it")


## A ULCV-long berth with a crane of `kind`, every milestone reached, the
## water `depth` metres deep.
func _port(kind: String, depth := 18.0) -> PortSim:
	var sim := AreaPort.terminal(100, RandomPort.water(RandomPort.quick(), depth))
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 30, "to": 59}), "", "an import block")
	_expect(sim.apply({"op": "place_sts", "apron": 1, "along": AreaFlow.crane_spots(sim, 1)[0], "kind": kind}), "", "a %s on the first crane spot" % kind)
	sim.tick()
	return sim


func _offered(sim: PortSim, kind: String) -> bool:
	return sim._could_offer(kind, 1)


func _test_it_needs_the_mega_crane() -> void:
	_expect(_offered(_port("wide_sts"), "ulcv"), false, "a wide STS (22 rows) doesn't reach across a ULCV, so none is offered")
	_expect(_offered(_port("mega_sts"), "ulcv"), true, "a mega STS (24 rows) does")
	var sim := _port("mega_sts")
	sim.apply({"op": "buy_tractors", "count": 6})
	var ship := PortSim.Ship.new("ulcv", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 6000.0, 30, 0)
	sim.ships.append(ship)
	_expect(AreaFlow.berth(sim, ship), true, "a ULCV berths")
	ship.state = PortSim.Ship.State.WORKING
	ship.sail = 1.0
	ship.berthed = sim.clock.calendar_minutes()
	for i in roundi(60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(ship.boxes < 30, true, "the mega STS works it (%d of 30 left)" % ship.boxes)


## In 15 m of water a ULCV (16 m, 14.5 m light) calls light-loaded with its
## light share of the moves; in 16 m it calls full; in 14 m not at all.
func _test_light_loaded_calls() -> void:
	var spec: Dictionary = Content.base().ship_classes.ulcv
	for depth: float in [15.0, 16.0, 14.0]:
		var sim := _port("mega_sts", depth)
		RandomPort.calls(sim, "ulcv", 1, 600, 1)
		for i in roundi(5.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
			sim.tick()
		if depth == 14.0:
			_expect(sim.ships.size(), 0, "in 14 m of water no ULCV calls")
			continue
		_expect(sim.ships.size(), 1, "in %.0f m of water a ULCV calls" % depth)
		if sim.ships.is_empty():
			continue
		var ship: PortSim.Ship = sim.ships[0]
		var share: float = spec.light_share if depth < spec.draft else 1.0
		_expect([ship.light, ship.boxes, ship.exports], [depth < spec.draft, roundi(spec.import_moves * share), roundi(spec.export_moves * share)], "in %.0f m it calls %s" % [depth, "light-loaded, with %d%% of its moves" % roundi(share * 100) if share < 1.0 else "full"])
