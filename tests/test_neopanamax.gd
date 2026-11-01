extends SceneTree
## M6 step 18: Neopanamax ships, gated like Panamax by milestone, channel
## depth and berth length, and by outreach: only wide STS cranes reach across.
## godot --headless --script res://tests/test_neopanamax.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_milestone_locks()
	_test_could_berth()
	_test_wide_cranes_work_it()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _test_milestone_locks() -> void:
	var sim := PortSim.new(1, RandomPort.strait())
	var hub: Dictionary = sim.milestones()[3]
	for name: String in ["neopanamax", "wide_sts"]:
		_expect(sim.lock_error(name), "Unlocked at milestone 4: %d TEU across the quay" % hub.teu, "%s waits for the hub milestone" % name)
	_expect(PortSim.new(1, RandomPort.quick()).lock_error("neopanamax"), "", "every milestone reached unlocks it")


## Lines offer a Neopanamax only with water as deep as its draft, a berth
## its length, and a crane on that berth wide enough to reach across it.
func _test_could_berth() -> void:
	var draft: float = Content.base().ship_classes.neopanamax.draft
	_expect(_offers(_port(100, "wide_sts", draft - 1.0), "neopanamax"), false, "water shallower than its draft keeps it away")
	_expect(_offers(_port(100, "wide_sts", draft), "neopanamax"), true, "as deep as its draft, with a long berth and a wide crane, lines offer it")
	_expect(_offers(_port(75, "wide_sts", draft), "neopanamax"), false, "a Panamax berth is too short")
	_expect(_offers(_port(100, "sts", draft), "neopanamax"), false, "standard cranes don't reach across it")
	_expect(_offers(_port(100, "sts", draft), "panamax"), true, "they still serve a Panamax")


## A Neopanamax alongside is worked only by the wide crane on its berth.
func _test_wide_cranes_work_it() -> void:
	var sim := _port(100, "sts", 16.0)
	sim.apply({"op": "place_sts", "apron": 1, "along": 87, "kind": "wide_sts"})
	sim.apply({"op": "buy_tractors", "count": 6})
	var ship := PortSim.Ship.new("neopanamax", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 600.0, 30, 0)
	sim.ships.append(ship)
	_expect(AreaFlow.berth(sim, ship), true, "it berths")
	ship.state = PortSim.Ship.State.WORKING
	ship.sail = 1.0
	ship.berthed = sim.clock.calendar_minutes()
	for i in roundi(120.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(ship.boxes < 30, true, "the wide crane works it (%d of 30 left)" % ship.boxes)
	_expect(AreaFlow.cranes_for(sim, ship).map(func(c: PortSim.Crane) -> String: return c.kind), ["wide_sts"], "only the wide crane works it")


## A port with every milestone reached: a coast road, an apron `length`
## cells long with a crane of `kind` on its first crane spot, a gate, and an import
## block, all in one terminal; the water `depth` metres deep.
func _port(length: int, kind: String, depth := 16.0) -> PortSim:
	var sim := AreaPort.terminal(length, RandomPort.water(RandomPort.quick(), depth))
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 30, "to": 59}), "", "the import block is built")
	_expect(sim.apply({"op": "place_sts", "apron": 1, "along": 12, "kind": kind}), "", "a %s crane is placed" % kind)
	sim.tick()
	return sim


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Whether lines may offer `kind` at the port's first berth.
func _offers(sim: PortSim, kind: String) -> bool:
	return sim._could_offer(kind, AreaFlow.ready_aprons(sim)[0])
