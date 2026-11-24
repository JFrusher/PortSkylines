extends SceneTree
## M11 fires: a fire no crew reaches burns a yard block's boxes after a
## grace, and its block's machines stop; a fire engine from a fire station
## in reach puts it out; a ship on fire isn't worked, and a fireboat puts it
## out; with fires off none break out.
## godot --headless --script res://tests/test_fires.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_off_no_fires()
	_test_an_unfought_fire_burns_boxes()
	_test_an_engine_puts_it_out()
	_test_a_fireboat_puts_out_a_ship()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The base port, run until its import block holds boxes; its id.
func _port_with_boxes() -> Array:
	var sim := AreaPort.base()
	var block := 0
	for i in roundi(24 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for area: int in sim.area_stacks:
			if sim.area_stacks[area].count() >= 10:
				block = area
		if block:
			break
	_expect(block != 0, true, "a yard block fills with boxes")
	return [sim, block]


func _set_fire(sim: PortSim, block: int) -> void:
	sim.fires.list[999] = {"target": ["block", block], "at": sim.areas.point(block, sim.areas.list[block].columns / 2.0, 0), "started": sim.clock.calendar_minutes(), "out_at": 0.0, "crew": []}


func _test_off_no_fires() -> void:
	var sim := AreaPort.base()
	sim.rules.events.fires.per_week = 5000.0
	for i in 2000:
		sim.tick()
	_expect(sim.fires.list.is_empty(), true, "fires off: none break out")
	sim.apply({"op": "set_event_kind", "kind": "fires", "on": true})
	for i in 2000:
		sim.tick()
	_expect(sim.fires.list.is_empty() and not sim.events.any(func(e: Dictionary) -> bool: return e.text.begins_with("Fire!")), false, "fires on: they do")


## Two hours of a fire nobody fights: boxes burn after the grace, each
## costing its value, and the block's machines stand still.
func _test_an_unfought_fire_burns_boxes() -> void:
	var start: Array = _port_with_boxes()
	var sim: PortSim = start[0]
	var block: int = start[1]
	var before: int = sim.area_stacks[block].count()
	var lost_before: int = sim.ledger.today.get("fire_losses", 0)
	_set_fire(sim, block)
	var moved := false
	for i in roundi(120.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		var jobs := {}
		for id: int in sim.machines.list:
			if sim.machines.list[id].area == block:
				jobs[id] = sim.machines.list[id].job.duplicate(true)
		sim.tick()
		for id: int in jobs:
			if id in sim.machines.list and not jobs[id].is_empty() and sim.machines.list[id].job != jobs[id]:
				moved = true
	var burned: int = (sim.ledger.today.get("fire_losses", 0) - lost_before) / -sim.rules.events.fires.box_value
	_expect(burned > 0, true, "boxes burn (%d of %d)" % [burned, before])
	_expect(moved, false, "the burning block's machines stand still")


## A fire station with an engine in the terminal: the engine drives there
## and the fire is out within the drive and fight_hours.
func _test_an_engine_puts_it_out() -> void:
	var start: Array = _port_with_boxes()
	var sim: PortSim = start[0]
	var block: int = start[1]
	sim.creative = true
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_expect(sim.apply({"op": "build_area", "type": "fire_station", "segment": east, "side": 1, "from": 62, "to": 70}), "", "a fire station along the east road")
	_expect(sim.apply({"op": "buy_engines", "area": sim.areas.list.keys().max(), "count": 1}), "", "with an engine")
	_set_fire(sim, block)
	var out := -1.0
	for i in roundi(4 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if sim.fires.list.is_empty():
			out = sim.clock.calendar_minutes()
			break
	_expect(out > 0.0, true, "the engine puts it out")
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text == "The fire is out"), true, "and the event list says so")


## A ship on fire with a fireboat at a tug depot: it isn't worked while it
## burns, and the fireboat puts it out.
func _test_a_fireboat_puts_out_a_ship() -> void:
	var sim := AreaPort.base()
	sim.creative = true
	_expect(sim.apply({"op": "build_tug_depot", "cell": Vector2i(66, 240)}), "", "a tug depot")
	_expect(sim.apply({"op": "buy_fireboats", "depot": sim.tug_depots.keys()[0], "count": 1}), "", "with a fireboat")
	var ship: PortSim.Ship = null
	for i in roundi(12 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for s: PortSim.Ship in sim.ships:
			if s.state == PortSim.Ship.State.WORKING:
				ship = s
		if ship:
			break
	_expect(ship != null, true, "a ship comes alongside")
	if ship == null:
		return
	sim.fires.list[999] = {"target": ["ship", ship.id], "at": Marine.alongside(sim, ship), "started": sim.clock.calendar_minutes(), "out_at": 0.0, "crew": []}
	var moves := ship.moves
	var fought_by := ""
	for i in roundi(4 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if 999 in sim.fires.list and not sim.fires.list[999].crew.is_empty():
			fought_by = sim.fires.list[999].crew[0]
			_expect(ship.moves, moves, "a burning ship isn't worked")
		if 999 not in sim.fires.list:
			break
	_expect(fought_by, "fireboat", "the fireboat goes")
	_expect(999 in sim.fires.list, false, "and puts it out")
