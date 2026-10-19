extends SceneTree
## The M3 economy scenarios, scripted end to end: overbooking a berth makes
## calls late, raising storage fees makes shippers collect sooner, and
## dredging the channel lets a deeper class call.
## godot --headless --script res://tests/test_economy_scenarios.gd

const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_overbooking_makes_ships_late()
	_test_higher_fees_lower_dwell()
	_test_dredging_lets_a_panamax_call()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The test port of test_sim: a gate, a 12-tile quay with an apron, two
## cranes, six tractors and a 3x2 import block.
func _port(rules: Dictionary) -> PortSim:
	var sim := PortSim.new(0, rules)
	sim.creative = true  # build the test port without worrying about cash
	var row := sim.map.entry.y
	var coast := sim.map.sea_width
	for x in range(coast + 1, sim.map.entry.x):
		sim.build(PortMap.Tile.GATE if x == sim.map.entry.x - 3 else PortMap.Tile.ROAD, Vector2i(x, row))
	for y in range(row - 6, row + 6):
		sim.build(PortMap.Tile.QUAY, Vector2i(coast, y))
		if y != row:
			sim.build(PortMap.Tile.ROAD, Vector2i(coast + 1, y))
	for y: int in [row - 1, row]:
		sim.place_crane(Vector2i(coast, y))
	sim.buy_tractors(6)
	for x in range(coast + 3, coast + 6):
		for y: int in [row - 2, row - 1]:
			sim.build(PortMap.Tile.YARD, Vector2i(x, y))
	return sim


func _run(sim: PortSim, minutes: float) -> void:
	for i in roundi(minutes / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()


## One berth sold a Panamax every 2 hours, each taking longer than that to
## work: every call waits longer at anchorage than the one before.
func _test_overbooking_makes_ships_late() -> void:
	var rules := RandomPort.quick()
	rules.ship_classes.panamax.window_hours = 2.0
	rules.import_dwell_minutes = 0.0
	var sim := _port(rules)
	RandomPort.calls(sim, "panamax", 10, 120, 12)
	_run(sim, SimClock.MINUTES_PER_DAY)
	var late: Array = sim.ship_log.map(func(entry: Dictionary) -> float: return entry.late)
	_expect(late.size() >= 3, true, "several overbooked calls sailed (%d)" % late.size())
	for i in range(1, late.size()):
		_expect(late[i] > late[i - 1], true, "each call is later than the last (%s)" % [late])


## The same port and ships with storage at $0 and at the cap: shippers
## collect imports much sooner when storage is dear.
func _test_higher_fees_lower_dwell() -> void:
	var dwell: Array[float] = []
	for fee: int in [0, 200]:
		var rules := RandomPort.quick()
		rules.import_dwell_minutes = 240.0
		var sim := _port(rules)
		RandomPort.calls(sim)
		_expect(sim.apply({"op": "set_storage", "free_days": 0, "fee": fee}), "", "storage at $%d" % fee)
		_run(sim, 12 * 60)
		_expect(sim.dwell_times.size() > 10, true, "imports were collected at $%d (%d)" % [fee, sim.dwell_times.size()])
		dwell.append(sim.kpis().import_dwell_hours)
	_expect(dwell[1] < dwell[0] * 0.6, true, "average dwell falls from %.1f h to %.1f h" % [dwell[0], dwell[1]])


## Panamax calls miss an 11 m channel; after dredging to 13 m the next one
## berths.
func _test_dredging_lets_a_panamax_call() -> void:
	var rules := RandomPort.quick()
	rules.channel.start_depth = 11.0
	var sim := _port(rules)
	sim.channel_depth = 11.0
	RandomPort.calls(sim, "panamax", 10, 60, 3)
	_run(sim, 30)
	_expect([sim.ships.size(), sim.last_event().contains("needs 13 m of channel")], [0, true], "an 11 m channel turns a Panamax away (%s)" % sim.last_event())
	_expect(sim.apply({"op": "dredge", "metres": 2}), "", "dredge to 13 m")
	_run(sim, 60)
	_expect(sim.ships.size() == 1 and sim.ships[0].kind == "panamax", true, "the next Panamax calls")
