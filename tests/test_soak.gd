extends SceneTree
## Two game days of a seeded random port, with the sim's invariants checked
## after every tick: cash moves only through the ledger and every closed day
## adds up to its change in cash, yards stay
## within capacity, every box is in exactly one place, busy yard machines match
## the vehicles they serve, every vehicle drives on road, and no two vehicles
## ever share a lane.
## godot --headless --script res://tests/test_soak.gd

const RandomPort := preload("res://tests/random_port.gd")
# Two game days and a bit, so midnight closes the books twice.
const TICKS := SimClock.TICKS_PER_DAY * 2 + 1000

var _failures := 0


func _initialize() -> void:
	var calm := _soak(RandomPort.rules())
	_expect(calm.delivered > 0, true, "the calm port delivers boxes (%d)" % calm.delivered)
	# A lorry every 10 game hours: yards fill up and ships wait, which the calm
	# port never pushes hard enough to test.
	var congested_rules := RandomPort.rules()
	congested_rules.lorry_interval_minutes = 600.0
	var congested := _soak(congested_rules)
	_expect(congested.yard.stacks.keys().any(func(t: Vector2i) -> bool: return congested.yard.count(t) == congested.yard.capacity(t)), true, "the congested port fills a yard tile to capacity")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _soak(rules: Dictionary) -> PortSim:
	var sim := PortSim.new(2, rules)
	RandomPort.calls(sim)
	var log := RandomPort.command_log(11, TICKS, 400)
	var next := 0
	while sim.clock.ticks < TICKS and _failures == 0:
		while next < log.size() and log[next].tick == sim.clock.ticks:
			sim.apply(log[next].command)
			next += 1
		sim.tick()
		_check(sim)
	return sim


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _check(sim: PortSim) -> void:
	var at := "at tick %d" % sim.clock.ticks
	_expect(sim.ledger.today_total(), sim.money - sim.ledger.opened, "today's ledger lines add up to the change in cash " + at)
	if sim.clock.ticks % SimClock.TICKS_PER_DAY == 0:
		var day: Dictionary = sim.ledger.days[-1]
		var total := 0
		for category: String in day.lines:
			total += day.lines[category]
		_expect(total, day.closed - day.opened, "day %d's ledger adds up to its change in cash" % day.day)
	# Every box is in exactly one place: a yard stack or a vehicle's load.
	var seen := {}
	for tile: Vector2i in sim.yard.stacks:
		var count := sim.yard.count(tile)
		_expect(count + sim.yard.reserved.get(tile, 0) <= sim.yard.capacity(tile), true, "yard %s holds %d + %d reserved %s" % [tile, count, sim.yard.reserved.get(tile, 0), at])
		for id: int in sim.yard.stacks[tile]:
			_expect(seen.has(id), false, "box %d is in one place only %s" % [id, at])
			seen[id] = tile
	var handling := {}
	var lanes := {}
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.loaded:
			_expect(seen.has(vehicle.box), false, "box %d on vehicle %d is in one place only %s" % [vehicle.box, vehicle.id, at])
			seen[vehicle.box] = vehicle.id
		elif vehicle.box != 0:
			_expect(seen.get(vehicle.box) == vehicle.target, true, "%s %d's box %d waits at its target %s" % [vehicle.kind, vehicle.id, vehicle.box, at])
		if vehicle.state == "handling":
			handling[vehicle.block] = handling.get(vehicle.block, 0) + 1
		if vehicle.lane == Traffic.NO_LANE:
			_expect(vehicle.state in ["under_crane", "handling", "no_route"], true, "vehicle %d is off the road only under a crane, in a bay or waiting to re-enter %s" % [vehicle.id, at])
			continue
		if vehicle.lane in lanes:
			_expect(vehicle.lane, null, "vehicles %d and %d share a lane %s" % [vehicle.id, lanes[vehicle.lane], at])
		lanes[vehicle.lane] = vehicle.id
		if vehicle.ahead != Traffic.NO_LANE:
			_expect(vehicle.lane.z, Traffic.JUNCTION, "vehicle %d holds a lane ahead only while in a junction %s" % [vehicle.id, at])
			_expect(sim.traffic.holder(vehicle.ahead), vehicle.id, "vehicle %d holds its lane past the junction %s" % [vehicle.id, at])
			_expect(lanes.has(vehicle.ahead), false, "vehicle %d's lane ahead is its own %s" % [vehicle.id, at])
			lanes[vehicle.ahead] = vehicle.id
		_expect(Vector2i(vehicle.lane.x, vehicle.lane.y), vehicle.path[int(vehicle.t)], "vehicle %d holds the lane of the tile it is on %s" % [vehicle.id, at])
		_expect(sim.traffic.holder(vehicle.lane), vehicle.id, "traffic agrees vehicle %d holds its lane %s" % [vehicle.id, at])
		for cell: Vector2i in vehicle.path:
			if not PortMap.is_road(sim.map.tile(cell)):
				_expect(sim.map.tile(cell), PortMap.Tile.ROAD, "vehicle path cell %s is road %s" % [cell, at])
				return
	_expect(seen.size(), sim.boxes.size(), "every box in the port is somewhere %s" % at)
	_expect(handling, sim.yard.busy, "busy machines match the vehicles being handled %s" % at)
