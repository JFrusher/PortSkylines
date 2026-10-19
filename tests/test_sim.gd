extends SceneTree
## Headless tests for the build rules and the ship-to-lorry loop.
## godot --headless --script res://tests/test_sim.gd

const ROAD := PortMap.Tile.ROAD
const QUAY := PortMap.Tile.QUAY
const YARD := PortMap.Tile.YARD
const GATE := PortMap.Tile.GATE
const RandomPort := preload("res://tests/random_port.gd")
## When the first test ship calls; see RandomPort.calls.
const FIRST_SHIP := 10

var _failures := 0


func _initialize() -> void:
	_test_build_rules()
	_test_bulldoze_rules()
	_test_bulldoze_in_use()
	_test_no_ship_without_a_road()
	_test_ships_unload_and_lorries_pay()
	_test_commands()
	_test_round_trip()
	_test_cells_of_matches_a_scan()
	_test_berths()
	_test_ships_fit_their_berth()
	_test_cranes()
	_test_crane_timing()
	_test_outreach()
	_test_route_cache()
	_test_yard_settings()
	_test_yard_machines_set_the_pace()
	_test_import_dwell()
	_test_exports_are_loaded()
	_test_gate()
	_test_parallel_gates()
	_test_upkeep_at_midnight()
	_test_events_do_not_repeat()
	_test_ships_never_overlap()
	_test_new_yard_tile_keeps_block_settings()
	_test_unreachable_block_does_not_stall_imports()
	_test_gate_is_an_access_road()
	_test_only_the_ledger_moves_cash()
	_test_a_service_calls_on_its_slot()
	_test_offers_accept_and_decline()
	_test_reputation_cancels_and_recovers()
	_test_storage_is_charged_per_day()
	_test_a_call_earns_its_moves()
	_test_loans_are_paid_back_with_interest()
	_test_bailout_fires_once()
	_test_saved_reputation_meets_a_new_line()
	_test_creative_mode_builds_without_cash()
	_test_inspect_each_entity()
	_test_land_must_be_bought()
	_test_cranes_arrive_after_their_lead_time()
	_test_dredging()
	_test_milestones_unlock_content()
	_test_year_end_scoreboard()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A road from the highway to the coast with a gate near the highway, a
## 12-tile quay with an apron road behind it, two cranes, six tractors and a
## 3x2 yard block beside the road.
func _port(rules := Content.base(), calls := "feeder") -> PortSim:
	var sim := PortSim.new(0, RandomPort.quick(rules))
	if calls != "":
		RandomPort.calls(sim, calls)
	var row := sim.map.entry.y
	var coast := sim.map.sea_width
	for x in range(coast + 1, sim.map.entry.x):
		_expect(sim.build(GATE if x == sim.map.entry.x - 3 else ROAD, Vector2i(x, row)), "", "road at x=%d" % x)
	for y in range(row - 6, row + 6):
		_expect(sim.build(QUAY, Vector2i(coast, y)), "", "quay at y=%d" % y)
		if y != row:
			_expect(sim.build(ROAD, Vector2i(coast + 1, y)), "", "apron road at y=%d" % y)
	for y: int in [row - 1, row]:
		_expect(sim.place_crane(Vector2i(coast, y)), "", "crane at y=%d" % y)
	_expect(sim.buy_tractors(6), "", "tractors")
	for x in range(coast + 3, coast + 6):
		for y: int in [row - 2, row - 1]:
			_expect(sim.build(YARD, Vector2i(x, y)), "", "yard at %d,%d" % [x, y])
	return sim


func _run(sim: PortSim, minutes: float) -> void:
	for i in roundi(minutes / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()


func _test_build_rules() -> void:
	var sim := PortSim.new()
	_expect(sim.build(ROAD, Vector2i(3, 3)), "Can't build on water", "road on water")
	_expect(sim.build(QUAY, Vector2i(30, 40)), "A quay must face the water", "inland quay")
	_expect(sim.build(QUAY, Vector2i(12, 40)), "", "coastal quay")
	_expect(sim.build(ROAD, Vector2i(12, 40)), "Bulldoze first", "road on a quay")
	_expect(sim.build(ROAD, Vector2i(99, 40)), "Off the map", "road off the map")
	_expect(sim.map.build_error(QUAY, Vector2i(12, 0)), "", "quay on the north edge faces the sea")
	_expect(sim.map.build_error(QUAY, Vector2i(30, 0)), "A quay must face the water", "map edge is not water")
	_expect(sim.money, sim.rules.start_money - 200, "quays cost money")
	sim.ledger.cash = 5
	_expect(sim.build(ROAD, Vector2i(30, 40)), "Not enough money", "building while broke")


func _test_bulldoze_rules() -> void:
	var sim := _port()
	var yard := Vector2i(sim.map.sea_width + 3, sim.map.entry.y - 1)
	_expect(sim.bulldoze(sim.map.entry), "That's the highway", "bulldoze highway")
	_expect(sim.bulldoze(Vector2i(30, 40)), "Nothing to bulldoze", "bulldoze empty land")
	_expect(sim.bulldoze(yard), "", "bulldoze an empty yard")
	_expect(sim.map.tile(yard), PortMap.Tile.LAND, "bulldozed yard is land again")


## As in Cities: Skylines, anything in use can be bulldozed; what used it is
## scrapped, rerouted or sent away, and the books of boxes, yard space,
## machines and lanes stay straight.
func _test_bulldoze_in_use() -> void:
	var sim := _port()
	_run(sim, FIRST_SHIP + 120)
	var ship := sim.ships[0]
	_expect(ship.state, PortSim.Ship.State.WORKING, "the first ship is being worked")
	var stacked := sim.yard.stacks.keys().filter(func(t: Vector2i) -> bool: return sim.yard.count(t) > 0)
	_expect(stacked.is_empty(), false, "imports are stacked")
	var tile: Vector2i = stacked[0]
	var lost := sim.yard.count(tile)
	var before := sim.boxes.size()
	_expect(sim.bulldoze(tile), "", "a yard tile holding boxes can be bulldozed")
	_expect(sim.boxes.size() <= before - lost, true, "its boxes are lost")
	_expect(sim.vehicles.all(func(v: Vehicle) -> bool: return v.target != tile), true, "nothing still heads for it")
	var crane := sim.cranes[0]
	_expect(sim.bulldoze(crane.cell), "", "a working crane can be bulldozed")
	_expect(sim.cranes.has(crane), false, "the crane is gone")
	var road := sim.map.access_road(sim.cranes[0].cell)
	_expect(sim.bulldoze(road), "", "the road behind a working crane can be bulldozed")
	_expect(sim.vehicles.all(func(v: Vehicle) -> bool: return v.home != road and road not in v.path), true, "no vehicle parks on or drives over it")
	_expect(sim.bulldoze(ship.cells[0]), "", "a quay with a ship alongside can be bulldozed")
	_expect(ship.state, PortSim.Ship.State.LEAVING, "the ship sails at once")
	_run(sim, 120)
	_expect(sim.vehicles.all(func(v: Vehicle) -> bool: return v.path.all(func(c: Vector2i) -> bool: return PortMap.is_road(sim.map.tile(c)))), true, "every vehicle still drives on road")
	var reserved := {}
	for v in sim.vehicles:
		if v.state != "handling":
			continue
		reserved[v.block] = reserved.get(v.block, 0) + 1
	_expect(reserved, sim.yard.busy, "busy machines match the vehicles being handled")


func _test_no_ship_without_a_road() -> void:
	var sim := PortSim.new()
	RandomPort.calls(sim)
	sim.build(QUAY, Vector2i(12, 40))
	_run(sim, FIRST_SHIP + 1)
	_expect(sim.ships.size(), 0, "no ship calls at an unconnected quay")


func _test_ships_unload_and_lorries_pay() -> void:
	var rules := Content.base().duplicate(true)
	rules.import_dwell_minutes = 0.0
	var sim := _port(rules)
	var before := sim.money
	_run(sim, FIRST_SHIP + 1)
	_expect(sim.ships.size(), 1, "a ship calls at the 12-tile berth")
	var cargo := sim.ships[0].boxes
	# One reach stacker serves the block, stacking each box and later loading
	# it onto a lorry, so the yard machine sets the pace.
	_run(sim, cargo * sim.rules.yard_gear.reach_stacker.handling_minutes * 2 + 200)
	_expect(sim.delivered >= cargo, true, "the first ship's %d boxes are all delivered (%d)" % [cargo, sim.delivered])
	_expect(sim.ledger.today.get("moves", 0) > 0, true, "the line pays for the moves")


func _test_commands() -> void:
	var by_command := PortSim.new()
	var direct := PortSim.new()
	var cell := Vector2i(12, 40)
	_expect(by_command.apply({"op": "build", "kind": QUAY, "cell": cell}), "", "build command")
	direct.build(QUAY, cell)
	_expect(by_command.map.tile(cell), direct.map.tile(cell), "a build command builds like build()")
	_expect(by_command.money, direct.money, "a build command charges like build()")
	_expect(by_command.apply({"op": "bulldoze", "cell": cell}), "", "bulldoze command")
	_expect(by_command.map.tile(cell), PortMap.Tile.LAND, "a bulldoze command clears the tile")
	_expect(by_command.apply({"op": "fly"}), "Unknown command: fly", "unknown command is refused")


func _test_round_trip() -> void:
	var straight := _port()
	var halves := _port()
	_run(straight, 50)
	_run(halves, 25)
	var copy := PortSim.from_dict(halves.to_dict())
	_expect(copy.state_hash(), halves.state_hash(), "to_dict -> from_dict keeps the state")
	_run(copy, 25)
	_expect(copy.ships.is_empty() and copy.vehicles.is_empty(), false, "the round trip happened mid-traffic")
	_expect(copy.state_hash(), straight.state_hash(), "a round trip mid-run changes nothing")
	_expect(copy.build(ROAD, Vector2i(30, 40)), "", "the copy's map still accepts builds")
	_expect(copy.map.route(copy.map.entry, Vector2i(copy.map.sea_width, copy.map.entry.y)).is_empty(), false, "the copy's road routing works")


func _test_cells_of_matches_a_scan() -> void:
	var sim := PortSim.new()
	var map := sim.map
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var kinds := [PortMap.Tile.LAND, ROAD, QUAY, YARD]
	for i in 1000:
		map.place(kinds[rng.randi() % kinds.size()], Vector2i(rng.randi_range(map.sea_width, map.size.x - 1), rng.randi_range(0, map.size.y - 1)))
	for kind: int in PortMap.Tile.values():
		var scan: Array[Vector2i] = []
		for y in map.size.y:
			for x in map.size.x:
				if map.tile(Vector2i(x, y)) == kind:
					scan.append(Vector2i(x, y))
		_expect(map.cells_of(kind), scan, "cells_of(%s) matches a full scan after 1,000 places" % PortMap.Tile.keys()[kind])


func _test_berths() -> void:
	var map := PortSim.new().map
	var coast := map.sea_width
	for y in range(10, 22):
		map.place(QUAY, Vector2i(coast, y))
	var berths := map.berths()
	_expect(berths.size(), 1, "a straight quay is one berth")
	_expect(berths[0].cells.size(), 12, "a 12-tile quay is a 12-tile berth")
	_expect(berths[0].side, Vector2i.LEFT, "the berth faces the sea")
	# A second quay row behind the first faces no water, so it adds no berth.
	map.place(QUAY, Vector2i(coast + 1, 10))
	_expect(map.berths().size(), 1, "quay tiles away from the water are not a berth")
	# Bulldozing a tile in the middle splits the berth in two.
	map.place(PortMap.Tile.LAND, Vector2i(coast, 15))
	var lengths := map.berths().map(func(b: Dictionary) -> int: return b.cells.size())
	_expect(lengths, [5, 6], "a gap splits a berth")


func _test_ships_fit_their_berth() -> void:
	var rules := RandomPort.quick()
	var sim := PortSim.new(0, rules)
	RandomPort.calls(sim, "panamax")
	var row := sim.map.entry.y
	for x in range(sim.map.sea_width + 1, sim.map.entry.x):
		sim.build(ROAD, Vector2i(x, row))
	for y in range(row - 4, row + 4):
		sim.build(QUAY, Vector2i(sim.map.sea_width, y))
	_run(sim, FIRST_SHIP + 1)
	_expect(sim.ships.size(), 0, "a panamax does not call at an 8-tile berth")
	_expect(sim.last_event().contains("12 quay tiles"), true, "the status says how long a berth it needs (%s)" % sim.last_event())
	rules.channel.start_depth = 11.0
	var shallow := PortSim.new(0, rules)
	RandomPort.calls(shallow, "panamax")
	_run(shallow, FIRST_SHIP + 1)
	_expect(shallow.last_event().contains("needs 13 m of channel"), true, "a panamax does not call at 11 m of water (%s)" % shallow.last_event())


func _test_cranes() -> void:
	var sim := _port()
	var coast := sim.map.sea_width
	var row := sim.map.entry.y
	_expect(sim.place_crane(Vector2i(coast + 1, row)), "Cranes stand on quay tiles", "no crane on a road")
	_expect(sim.place_crane(Vector2i(coast, row)), "There is a crane here already", "one crane per quay tile")
	var before := sim.cranes.size()
	_expect(sim.bulldoze(Vector2i(coast, row)), "", "bulldozing a crane's tile")
	_expect([sim.cranes.size(), sim.map.tile(Vector2i(coast, row))], [before - 1, QUAY], "removes the crane, not the quay")


## A Panamax of 120 moves with 3 cranes at 25 moves an hour takes
## 120 / (3 x 25 x 0.9) hours at berth, within 5%.
func _test_crane_timing() -> void:
	var rules := Content.base().duplicate(true)
	rules.ship_classes.panamax.import_moves = 120
	rules.start_money = 100000
	# A yard that never holds the cranes up: room for everything, a machine
	# per tile, near-instant stacking.
	rules.yard_gear.reach_stacker = {"capacity": 1000, "handling_minutes": 0.05, "tiles_per_machine": 1, "cost_per_tile": 0, "upkeep_per_machine": 0}
	var sim := _port(rules, "panamax")
	var row := sim.map.entry.y
	sim.place_crane(Vector2i(sim.map.sea_width, row + 2))
	sim.buy_tractors(10)
	_run(sim, FIRST_SHIP + 1)
	var first := sim.ships[0]
	var working_ticks := 0
	for i in roundi(240 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if first.state == PortSim.Ship.State.WORKING:
			working_ticks += 1
	var minutes := working_ticks * SimClock.CALENDAR_MINUTES_PER_TICK
	var expected := 120.0 / (3 * 25 * 0.9) * 60
	_expect(sim.cranes.size(), 3, "three cranes on the berth")
	_expect(absf(minutes - expected) <= expected * 0.05, true, "3 cranes work 120 moves in %.1f min (expected %.1f)" % [minutes, expected])
	_run(sim, 10)
	var k := sim.kpis()
	_expect(absf(k.crane_moves_per_hour - 25 * 0.9) < 25 * 0.9 * 0.05, true, "the crane-rate KPI reads 22.5 moves an hour (%.1f)" % k.crane_moves_per_hour)
	_expect(absf(k.berth_moves_per_hour - 3 * 25 * 0.9) < 3 * 25 * 0.9 * 0.05, true, "the berth KPI reads 67.5 moves an hour (%.1f)" % k.berth_moves_per_hour)


func _test_outreach() -> void:
	var rules := RandomPort.quick()
	rules.sts_crane.outreach = 8
	var sim := PortSim.new(0, rules)
	RandomPort.calls(sim, "panamax")
	var row := sim.map.entry.y
	for x in range(sim.map.sea_width + 1, sim.map.entry.x):
		sim.build(ROAD, Vector2i(x, row))
	for y in range(row - 6, row + 6):
		sim.build(QUAY, Vector2i(sim.map.sea_width, y))
	sim.place_crane(Vector2i(sim.map.sea_width, row))
	_run(sim, FIRST_SHIP + 30)
	_expect(sim.ships.size() == 1 and sim.ships[0].boxes == rules.ship_classes.panamax.import_moves, true, "a panamax gets no moves from cranes that are too short")
	_expect(sim.last_event().contains("reaches 13 rows"), true, "the status says why (%s)" % sim.last_event())


func _test_route_cache() -> void:
	var sim := _port()
	var map := sim.map
	var to := Vector2i(map.sea_width, map.entry.y)
	var first := map.route(map.entry, to)
	_expect(map._route_cache.size(), 1, "a route is cached after the first request")
	first.reverse()
	_expect(map.route(map.entry, to)[0], map.access_road(map.entry), "changing a returned route leaves the cache alone")
	sim.build(ROAD, Vector2i(30, 40))
	_expect(map._route_cache.size(), 0, "building clears the cache")


func _test_yard_settings() -> void:
	var sim := _port()
	var tile := Vector2i(sim.map.sea_width + 3, sim.map.entry.y - 1)
	_expect([sim.yard.capacity(tile), sim.yard.block(tile).size()], [6, 6], "a new 3x2 block holds 6 a tile with reach stackers")
	var before := sim.money
	_expect(sim.set_yard(tile, {"gear": "rtg"}), "", "switch the block to RTGs")
	_expect([sim.yard.capacity(tile), before - sim.money], [12, 6 * sim.rules.yard_gear.rtg.cost_per_tile], "RTGs hold 12 a tile and cost per tile")
	for i in 7:
		sim.yard.add(tile, 1000 + i)
	_expect(sim.set_yard(tile, {"gear": "reach_stacker"}), "Too many boxes here for reach stacker", "can't switch back with 7 boxes on a tile")
	_expect(sim.set_yard(Vector2i(30, 40), {"role": "export"}), "That is not a yard", "settings need a yard")
	var exports := _port()
	exports.set_yard(tile, {"role": "export"})
	_run(exports, FIRST_SHIP + 30)
	var imports_there: int = exports.yard.stacks.values().reduce(func(n: int, ids: Array) -> int: return n + ids.filter(func(id: int) -> bool: return exports.boxes[id].kind == "import").size(), 0)
	_expect(imports_there, 0, "imports never go to an export block")
	_expect(exports.last_event().contains("no import yard space"), true, "the status says why the ship waits (%s)" % exports.last_event())


## One machine per tile against one per two tiles, with handling slow enough
## (20 min) that the yard, not the cranes, sets the pace: half the machines
## take about twice as long to clear the ship.
func _test_yard_machines_set_the_pace() -> void:
	var minutes: Array[float] = []
	for per_machine: int in [1, 2]:
		var rules := Content.base().duplicate(true)
		rules.start_money = 100000
		rules.yard_gear.reach_stacker = {"capacity": 1000, "handling_minutes": 20.0, "tiles_per_machine": per_machine, "cost_per_tile": 0, "upkeep_per_machine": 0}
		rules.lorry_interval_minutes = 1e9  # no lorries competing for the machines
		var sim := _port(rules, "panamax")
		sim.buy_tractors(20)
		_run(sim, FIRST_SHIP + 1)
		var import_moves: int = rules.ship_classes.panamax.import_moves
		var ticks := 0
		while _stacked(sim) < import_moves and ticks < 100000:
			sim.tick()
			ticks += 1
		minutes.append(ticks * SimClock.CALENDAR_MINUTES_PER_TICK)
	_expect(absf(minutes[1] / minutes[0] - 2.0) < 0.2, true, "half the machines take twice as long to stack the ship (%.0f vs %.0f min)" % [minutes[1], minutes[0]])


func _stacked(sim: PortSim) -> int:
	return sim.yard.stacks.values().reduce(func(n: int, ids: Array) -> int: return n + ids.size(), 0)


func _test_import_dwell() -> void:
	var rules := Content.base().duplicate(true)
	rules.import_dwell_minutes = 60.0
	var sim := _port(rules)
	sim.set_storage(0, 0)  # free storage, so shippers take the whole dwell
	var first_stacked := -1.0
	var first_pickup := -1.0
	for i in roundi(240 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if first_stacked < 0 and not sim.yard.stacks.is_empty():
			first_stacked = sim.clock.calendar_minutes()
		if first_pickup < 0 and sim.vehicles.any(func(v: Vehicle) -> bool: return v.kind == "lorry"):
			first_pickup = sim.clock.calendar_minutes()
	_expect(first_stacked > 0 and first_pickup > 0, true, "imports were stacked and collected")
	_expect(first_pickup - first_stacked >= 55.0, true, "no lorry comes before the hour's dwell (stacked %.1f, first lorry %.1f)" % [first_stacked, first_pickup])


func _test_exports_are_loaded() -> void:
	var rules := Content.base().duplicate(true)
	var sim := _port(rules, "")
	RandomPort.calls(sim, "feeder", 120)
	var exports := Vector2i(sim.map.sea_width + 7, sim.map.entry.y + 1)
	for x in range(exports.x, exports.x + 3):
		sim.build(YARD, Vector2i(x, exports.y))
	_expect(sim.set_yard(exports, {"role": "export"}), "", "an export block")
	_run(sim, 119)
	var stacked := 0
	for tile in sim.yard.block(exports):
		stacked += sim.yard.count(tile)
	_expect(stacked >= rules.ship_classes.feeder.export_moves, true, "lorries brought %d exports before the ship" % stacked)
	_run(sim, 2)
	var ship := sim.ships[0]
	var ticks := 0
	while ship.state != PortSim.Ship.State.LEAVING and ticks < 200000:
		sim.tick()
		ticks += 1
	_expect([ship.boxes, ship.exports], [0, 0], "the feeder leaves discharged and fully loaded")
	_expect(sim.last_event().contains("fully loaded"), true, "and says so (%s)" % sim.last_event())


func _test_gate() -> void:
	var rules := Content.base().duplicate(true)
	rules.import_dwell_minutes = 0.0
	var gateless := PortSim.new(0, rules)
	var row := gateless.map.entry.y
	for x in range(gateless.map.sea_width + 1, gateless.map.entry.x):
		gateless.build(ROAD, Vector2i(x, row))
	gateless.build(YARD, Vector2i(gateless.map.sea_width + 3, row - 1))
	gateless.yard.add(Vector2i(gateless.map.sea_width + 3, row - 1), gateless._new_box("import", 0.0))
	_run(gateless, 5)
	_expect(gateless.vehicles.is_empty(), true, "no lorry comes in without a gate")
	_expect(gateless.last_event().contains("build a gate"), true, "the status says so (%s)" % gateless.last_event())
	var sim := _port(rules)
	_run(sim, FIRST_SHIP + 240)
	_expect(sim.turn_times.size() > 5, true, "lorries record turn times (%d)" % sim.turn_times.size())
	_expect(sim.turn_times.all(func(t: float) -> bool: return t >= 2 * rules.gate_minutes), true, "every turn includes a stop at the gate each way")


## Lorries bringing exports as fast as they can, through one gate or two
## parallel ones, with a slow gate and a fast yard: two gates take about twice
## as many boxes in.
func _test_parallel_gates() -> void:
	var counts: Array[int] = []
	for gates: int in [1, 2]:
		var rules := Content.base().duplicate(true)
		rules.gate_minutes = 6.0
		rules.export_lorry_interval_minutes = 0.05
		rules.start_money = 100000
		rules.yard_gear.reach_stacker = {"capacity": 1000, "handling_minutes": 0.05, "tiles_per_machine": 1, "cost_per_tile": 0, "upkeep_per_machine": 0}
		var sim := PortSim.new(0, rules)
		var row := sim.map.entry.y
		var gate_x := sim.map.entry.x - 6
		for x in range(sim.map.sea_width + 1, sim.map.entry.x):
			sim.build(GATE if x == gate_x else ROAD, Vector2i(x, row))
		if gates == 2:
			# A loop round the first gate through a second one.
			for cell: Vector2i in [Vector2i(gate_x + 2, row + 1), Vector2i(gate_x + 2, row + 2), Vector2i(gate_x + 1, row + 2), Vector2i(gate_x - 1, row + 2), Vector2i(gate_x - 2, row + 2), Vector2i(gate_x - 2, row + 1)]:
				sim.build(ROAD, cell)
			sim.build(GATE, Vector2i(gate_x, row + 2))
		for x in range(20, 26):
			sim.build(YARD, Vector2i(x, row - 1))
		sim.set_yard(Vector2i(20, row - 1), {"role": "export"})
		_run(sim, 300)
		counts.append(sim.delivered)
	_expect(counts[1] >= counts[0] * 1.7, true, "two gates take in about twice the exports of one (%d vs %d)" % [counts[1], counts[0]])


func _test_upkeep_at_midnight() -> void:
	var rules := Content.base().duplicate(true)
	var sim := _port(rules, "")
	var upkeep := sim.daily_upkeep()
	var expected: int = rules.upkeep.road * sim.map.cells_of(ROAD).size() + rules.upkeep.quay * 12 + rules.upkeep.yard * 6 + rules.upkeep.gate + rules.upkeep.sts_crane * 2 + rules.upkeep.tractor * 6 + rules.yard_gear.reach_stacker.upkeep_per_machine + rules.land.upkeep * 3
	_expect(upkeep, expected, "upkeep adds every tile, crane, tractor, yard machine and land tile")
	for i in SimClock.TICKS_PER_DAY - 1:
		sim.tick()
	var before := sim.money
	sim.tick()
	_expect([before - sim.money, -sim.ledger.days[-1].lines.upkeep], [upkeep, upkeep], "upkeep is charged exactly at midnight")
	_expect(sim.last_event().begins_with("Day 1: upkeep"), true, "and reported (%s)" % sim.last_event())


func _test_events_do_not_repeat() -> void:
	var sim := PortSim.new()
	var before := sim.events.size()
	sim._event("A crane is waiting for a free tractor")
	sim._event("A crane is waiting for a free tractor")
	_expect(sim.events.size(), before + 1, "a message repeated tick after tick is kept once")


## Extending a berth at its start must not let a second ship overlap the first.
func _test_ships_never_overlap() -> void:
	var sim := _port()
	var coast := sim.map.sea_width
	var top := sim.map.entry.y - 7
	var feeder: Dictionary = sim.contracts.services[0]
	sim.ships.clear()
	sim.call("_call", feeder)
	_expect(sim.call("_berth", sim.ships[0]), true, "the first feeder berths")
	sim.ledger.cash = 100000
	_expect(sim.build(QUAY, Vector2i(coast, top)), "", "quay at the berth start")
	_expect(sim.build(ROAD, Vector2i(coast + 1, top)), "", "apron at the berth start")
	sim.call("_call", feeder)
	sim.call("_berth", sim.ships[1])
	for ship: PortSim.Ship in sim.ships.slice(1):
		_expect(ship.cells.filter(func(c: Vector2i) -> bool: return c in sim.ships[0].cells), [], "ships share no quay tile")


## A tile that becomes a block's anchor must not reset its role and gear.
func _test_new_yard_tile_keeps_block_settings() -> void:
	var sim := _port()
	sim.ledger.cash = 100000
	var tile := Vector2i(sim.map.sea_width + 3, sim.map.entry.y - 2)
	_expect(sim.apply({"op": "set_yard", "cell": tile, "settings": {"role": "export", "gear": "rtg"}}), "", "export RTG block")
	_expect(sim.build(YARD, tile + Vector2i.UP), "", "yard tile above the anchor")
	var anchor := sim.yard.anchor(tile)
	_expect(anchor, tile + Vector2i.UP, "the new tile anchors the block")
	_expect([sim.yard.role_of(anchor), sim.yard.gear_of(anchor)], ["export", "rtg"], "the block keeps its settings")
	var before := sim.money
	_expect(sim.build(YARD, tile + Vector2i.UP * 2), "", "another tile on the RTG block")
	_expect(before - sim.money, sim.cost(YARD) + sim.rules.yard_gear.rtg.cost_per_tile, "joining an RTG block pays for its gear")
	sim.ledger.cash = sim.cost(YARD)
	_expect(sim.build(YARD, tile + Vector2i.UP * 3), "Not enough money", "the gear must be affordable")


## Imports in a block lorries can't reach must not hold up imports elsewhere.
func _test_unreachable_block_does_not_stall_imports() -> void:
	var sim := _port()
	var lone := Vector2i(sim.map.sea_width + 20, sim.map.entry.y + 10)
	_expect(sim.build(YARD, lone), "", "a yard tile with no road")
	var reachable := Vector2i(sim.map.sea_width + 3, sim.map.entry.y - 2)
	sim.yard.stacks.clear()
	for box: Array in [[900, lone], [901, reachable]]:
		sim.boxes[box[0]] = {"kind": "import", "due": 0.0}
		sim.yard.add(box[1], box[0])
	_expect(sim.call("_dispatch_import_lorry"), true, "a lorry is sent for the reachable box")
	_expect(901 in sim.get("_claimed"), true, "it claims the reachable box")


## A yard whose only neighbouring road is a gate is entered from that gate.
func _test_gate_is_an_access_road() -> void:
	var sim := _port()
	var gate := Vector2i(sim.map.entry.x - 3, sim.map.entry.y)
	var beside := gate + Vector2i.DOWN
	_expect(sim.build(YARD, beside), "", "a yard tile beside the gate")
	_expect(sim.yard.entrance(beside), beside, "the block has an entrance")
	_expect(sim.map.access_road(beside), gate, "it is entered from the gate")


## Cash changes only through Ledger.post, so the books always add up.
func _test_only_the_ledger_moves_cash() -> void:
	var dir := "res://scripts/sim"
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd") or file == "ledger.gd":
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(file))
		for pattern: String in ["money +=", "money -=", "cash +=", "cash -=", "cash ="]:
			_expect(text.contains(pattern), false, "%s has no '%s'" % [file, pattern])


## A weekly service's ship arrives exactly at its start minute, every week.
func _test_a_service_calls_on_its_slot() -> void:
	var sim := _port(Content.base(), "")
	var start := SimClock.MINUTES_PER_DAY + 5 * 60
	RandomPort.calls(sim, "feeder", start, 0, 1)
	var arrivals: Array[float] = []
	for i in roundi((start + Contracts.MINUTES_PER_WEEK + 60) / SimClock.CALENDAR_MINUTES_PER_TICK):
		var before := sim.ships.size()
		sim.tick()
		if sim.ships.size() > before:
			arrivals.append(sim.clock.calendar_minutes())
	_expect(arrivals, [float(start), float(start + Contracts.MINUTES_PER_WEEK)], "the service calls on day 1 at 05:00, two weeks running")


func _test_offers_accept_and_decline() -> void:
	var rules := Content.base().duplicate(true)
	rules.contracts.offer_chance = 1.0
	var sim := _port(rules, "")
	_run(sim, rules.contracts.offer_check_minutes * 2)
	_expect(sim.contracts.offers.size(), 2, "lines offer services to a port with a berth")
	var declined: int = sim.contracts.offers[0].id
	_expect(sim.apply({"op": "decline_offer", "id": declined}), "", "decline an offer")
	_expect(sim.contracts.offers.any(func(o: Dictionary) -> bool: return o.id == declined), false, "a declined offer is gone")
	var offer: Dictionary = sim.contracts.offers[0]
	_expect(sim.apply({"op": "accept_offer", "id": offer.id}), "", "accept an offer")
	_expect(sim.apply({"op": "accept_offer", "id": offer.id}), "No such offer", "an offer is accepted once")
	_expect(sim.contracts.services.map(func(s: Dictionary) -> int: return s.id), [offer.id], "the accepted offer is a service")
	var minute_of_week := fmod(sim.clock.calendar_minutes(), Contracts.MINUTES_PER_WEEK)
	_run(sim, fposmod(offer.start - minute_of_week, Contracts.MINUTES_PER_WEEK) + 1)
	_expect(sim.ships.size() == 1 and sim.ships[0].line == offer.line, true, "and its ship calls")


## Late calls cost a line's reputation until it cancels a service; good calls
## win it back until it offers services again.
func _test_reputation_cancels_and_recovers() -> void:
	var rules := Content.base().duplicate(true)
	rules.contracts.offer_chance = 1.0
	var contracts := Contracts.new(rules)
	for id: int in [1, 2]:
		contracts.services.append({"id": id, "line": "kestrel", "kind": "feeder", "start": 0, "window_hours": 12.0, "moves": 40})
	var said := ""
	var calls := 0
	while said == "" and calls < 20:
		said = contracts.called("kestrel", 12.0, 20.0, 60.0)
		calls += 1
	_expect(said.contains("cancelled"), true, "a line let down too often cancels a service (%s)" % said)
	_expect(contracts.services.size(), 1, "one service is gone")
	_expect(contracts.reputation.kestrel < rules.reputation.offer_above, true, "and it offers nothing while unhappy")
	while contracts.reputation.kestrel < rules.reputation.offer_above:
		contracts.called("kestrel", 0.0, 30.0, 40.0)
	var rng := RandomNumberGenerator.new()
	var offered := {}
	for i in 50:
		var offer := contracts.offer(rng, 0.0, 100, func(_kind: String) -> bool: return true)
		if not offer.is_empty():
			offered[offer.line] = true
			contracts.offers.clear()
	_expect(offered.has("kestrel"), true, "good calls win the line back to offering services")


## Boxes pay the fee for each midnight they spend in the yard past their free days.
func _test_storage_is_charged_per_day() -> void:
	var sim := _port(Content.base(), "")
	_expect(sim.apply({"op": "set_storage", "free_days": 1, "fee": 30}), "", "set storage terms")
	_expect(sim.apply({"op": "set_storage", "free_days": 4, "fee": 30}), "Free days run from 0 to 3", "free days are capped")
	var tile := Vector2i(sim.map.sea_width + 3, sim.map.entry.y - 1)
	for i in 2:
		sim.call("_stack", tile, sim._new_box("export", 0.0))
	_run(sim, 3 * SimClock.MINUTES_PER_DAY)
	# Stacked at minute 0: the first midnight is within the free day.
	var storage: Array = sim.ledger.days.map(func(day: Dictionary) -> int: return day.lines.get("storage", 0))
	_expect(storage, [0, 60, 60], "2 boxes x $30 for each day past the free one")


## A call of 40 ft boxes earns 1.8 x the 20 ft price per move.
func _test_a_call_earns_its_moves() -> void:
	var rules := Content.base().duplicate(true)
	rules.box_mix = {"forty_share": 1.0, "reefer_share": 0.0}
	var sim := _port(rules)
	var ship: PortSim.Ship
	while ship == null or ship.state != PortSim.Ship.State.LEAVING:
		sim.tick()
		if ship == null and not sim.ships.is_empty():
			ship = sim.ships[0]
	_expect(sim.ledger.today.moves, ship.moves * roundi(rules.move_price.per_20ft * 1.8), "%d moves at $180" % ship.moves)


func _test_loans_are_paid_back_with_interest() -> void:
	var sim := PortSim.new(0, RandomPort.quick())
	var terms: Dictionary = sim.rules.loans.small
	var before := sim.money
	for i: int in sim.rules.max_loans:
		_expect(sim.apply({"op": "take_loan", "kind": "small"}), "", "take loan %d" % (i + 1))
	_expect(sim.apply({"op": "take_loan", "kind": "small"}), "Pay back a loan first: %d at once at most" % sim.rules.max_loans, "a loan too many")
	_expect(sim.money - before, terms.amount * sim.rules.max_loans, "the loans are paid in")
	var paid := 0
	for day: int in terms.days + 5:
		var cash := sim.money
		sim.finance.end_of_day(0.0, sim.ledger, sim.contracts, true)
		paid += cash - sim.money
	var interest := roundi(terms.amount * terms.yearly_rate * terms.days / 365.0)
	_expect(paid, (terms.amount + interest) * sim.rules.max_loans, "payments add up to principal plus interest")
	_expect(sim.finance.loans.is_empty(), true, "and the loans are paid off")


## Three midnights below zero bring one bailout: debt cleared, every line's
## reputation knocked, no loans for a while.
func _test_bailout_fires_once() -> void:
	var sim := PortSim.new()
	sim.ledger.cash = -5000
	sim.finance.loans.append({"kind": "small", "owed": 3000, "payment": 100, "days_left": 30})
	var said: Array[String] = []
	for day: int in sim.rules.bailout.days:
		said.append_array(sim.finance.end_of_day(day * 1440.0, sim.ledger, sim.contracts, true))
	_expect(said.size(), 1, "one bailout at the third midnight (%s)" % [said])
	_expect([sim.money, sim.ledger.today.get("bailout", 0) + sim.ledger.today.get("loan_payments", 0)], [0, 5000], "it clears the debt through the ledger")
	_expect(sim.finance.loans.is_empty(), true, "loans included")
	_expect(sim.contracts.reputation.aurora, sim.rules.reputation.start + sim.rules.bailout.reputation, "and costs reputation")
	_expect(sim.finance.loan_error("small", 1440.0 * 5).begins_with("No lender"), true, "lenders stay away")
	sim.ledger.cash = -5000
	_expect(sim.finance.end_of_day(1440.0 * 3, sim.ledger, sim.contracts, true), [] as Array[String], "the count starts again after a bailout")
	_expect(sim.finance.end_of_day(1440.0 * 3, sim.ledger, sim.contracts, false).is_empty() and sim.finance.end_of_day(1440.0 * 3, sim.ledger, sim.contracts, false).is_empty(), true, "creative mode has no bailouts")


## A save from before a line was added to the data keeps its reputations, and
## the new line starts where every line does.
func _test_saved_reputation_meets_a_new_line() -> void:
	var rules := Content.base()
	var saved := Contracts.new(rules).to_dict()
	saved.reputation.aurora = 90.0
	saved.reputation.erase("kestrel")
	var loaded := Contracts.from_dict(saved, rules)
	_expect([loaded.reputation.aurora, loaded.reputation.kestrel], [90.0, float(rules.reputation.start)], "saved reputation kept, the new line at the start")


func _test_creative_mode_builds_without_cash() -> void:
	for creative: bool in [false, true]:
		var sim := PortSim.new(0, Content.base(), creative)
		sim.ledger.cash = 0
		_expect(sim.build(QUAY, Vector2i(12, 40)), "" if creative else "Not enough money", "building at $0 in %s mode" % ("creative" if creative else "normal"))
	var copy := PortSim.from_dict(PortSim.new(0, Content.base(), true).to_dict())
	_expect(copy.creative, true, "creative mode survives a save")


func _test_land_must_be_bought() -> void:
	var sim := PortSim.new(0, RandomPort.quick())
	sim.ledger.cash = 100000
	var north := Vector2i(40, 10)
	_expect(sim.build(ROAD, north), "Buy this land first", "no building outside the port's land")
	var before := sim.money
	var upkeep := sim.daily_upkeep()
	_expect(sim.apply({"op": "buy_land", "tile": sim.land_tile(north)}), "", "buy the land tile north of the start")
	_expect([before - sim.money, sim.daily_upkeep() - upkeep], [sim.rules.land.price, sim.rules.land.upkeep], "land costs its price, then upkeep every day")
	_expect(sim.build(ROAD, north), "", "and can be built on")
	_expect(sim.buy_land(sim.land_tile(north)), "The port owns this land already", "land is bought once")
	_expect(sim.buy_land(Vector2i(3, 0)), "Off the map", "only map tiles are for sale")
	_expect(sim.buy_land(sim.land_tile(PortMap.NONE)), "Off the map", "a click off the map buys nothing")


## An STS crane ordered now stands on its quay exactly when its lead time ends.
func _test_cranes_arrive_after_their_lead_time() -> void:
	var rules := Content.base().duplicate(true)
	rules.sts_crane.lead_days = 0.5
	var sim := PortSim.new(0, rules)
	var quay := Vector2i(sim.map.sea_width, sim.map.entry.y)
	sim.build(QUAY, quay)
	var before := sim.money
	_expect(sim.place_crane(quay), "", "order a crane")
	_expect([sim.cranes.size(), before - sim.money], [0, rules.sts_crane.cost], "paid now, not there yet")
	_expect(sim.place_crane(quay), "There is a crane here already", "one order per quay tile")
	var due := roundi(720 / SimClock.CALENDAR_MINUTES_PER_TICK)
	for i in due - 1:
		sim.tick()
	_expect(sim.cranes.size(), 0, "not there a tick early")
	sim.tick()
	_expect(sim.cranes.size(), 1, "there exactly 12 hours after the order")


func _test_dredging() -> void:
	var base := Content.base().duplicate(true)
	base.channel.maintenance_days = 1
	var sim := _port(base, "")
	var channel: Dictionary = sim.rules.channel
	sim.ledger.cash = 100000
	var before := sim.money
	_expect(sim.apply({"op": "dredge", "metres": 2}), "", "dredge two metres")
	_expect([sim.channel_depth, before - sim.money], [channel.start_depth + 2, 2 * channel.cost_per_metre], "the channel is deeper, at a cost per metre")
	_expect(sim.dredge(100), "The channel can't go below %.0f m" % channel.max_depth, "dredging stops at the limit")
	_run(sim, SimClock.MINUTES_PER_DAY)
	_expect(sim.ledger.days[-1].lines.dredging, -2 * channel.cost_per_metre - 2 * channel.maintenance_per_metre, "the dredged metres need maintenance at midnight")


## Below a milestone its content stays locked; crossing it unlocks it all.
func _test_milestones_unlock_content() -> void:
	var sim := PortSim.new()
	sim.ledger.cash = 1000000
	var tile := Vector2i(sim.map.sea_width + 3, sim.map.entry.y - 1)
	sim.build(YARD, tile)
	var terminal: Dictionary = sim.milestones()[1]
	var gateway: Dictionary = sim.milestones()[2]
	_expect(sim.milestones_reached(), 1, "the first milestone is reached at the start")
	for name: String in ["rtg", "loans", "land", "dredging", "panamax"]:
		_expect(sim.unlocked(name), false, "%s starts locked" % name)
	_expect(sim.set_yard(tile, {"gear": "rtg"}), "Unlocked at milestone 2: %d TEU across the quay" % terminal.teu, "RTGs wait for milestone 2")
	_expect(sim.apply({"op": "take_loan", "kind": "small"}).begins_with("Unlocked at milestone 2"), true, "so do loans")
	_expect(sim.apply({"op": "dredge", "metres": 1}).begins_with("Unlocked at milestone 3"), true, "dredging waits for milestone 3")
	var box := {"teu": 2, "reefer": false}
	while sim.teu_handled < terminal.teu - 2:
		sim.call("_moved", box)
	_expect(sim.unlocked("rtg"), false, "still locked 2 TEU short")
	sim.call("_moved", box)
	_expect(sim.last_event().begins_with("Milestone 2"), true, "crossing it is announced (%s)" % sim.last_event())
	_expect([sim.set_yard(tile, {"gear": "rtg"}), sim.apply({"op": "take_loan", "kind": "small"})], ["", ""], "RTGs and loans are unlocked")
	_expect(sim.unlocked("land"), false, "land waits for milestone 3")
	while sim.teu_handled < gateway.teu:
		sim.call("_moved", box)
	_expect(["land", "dredging", "panamax"].all(sim.unlocked), true, "milestone 3 unlocks land, dredging and Panamax services")
	var rules := Content.base().duplicate(true)
	rules.contracts.offer_chance = 1.0
	rules.contracts.max_offers = 100
	var offering := _port(rules, "")
	# _port's quick rules reach every milestone; put the real ones back.
	offering.rules.milestones = Content.base().milestones.duplicate(true)
	_run(offering, 40 * 60)
	_expect(offering.contracts.offers.size() >= 10, true, "lines made offers (%d)" % offering.contracts.offers.size())
	_expect(offering.contracts.offers.any(func(o: Dictionary) -> bool: return o.kind == "panamax"), false, "no Panamax is offered before milestone 3")


## Each game year closes with port hours per call, moves an hour and gate
## turn, computed from that year's calls.
func _test_year_end_scoreboard() -> void:
	var rules := Content.base().duplicate(true)
	rules.year_days = 1
	rules.import_dwell_minutes = 30.0
	var sim := _port(rules)
	var sailed: Array[Dictionary] = []
	var seen := 0
	for i in SimClock.TICKS_PER_DAY:
		sim.tick()
		var logged := sim.ship_log.size()
		if logged > seen or (logged == 10 and not sailed.is_empty() and sim.ship_log[-1] != sailed[-1]):
			sailed.append(sim.ship_log[-1])
		seen = logged
	var hours := 0.0
	var moves := 0
	for call in sailed:
		hours += call.hours
		moves += call.moves
	_expect(sim.scoreboard.size(), 1, "the year closed at midnight")
	var closed: Dictionary = sim.scoreboard[0]
	_expect(sailed.size() > 3, true, "calls sailed in the year (%d)" % sailed.size())
	_expect(absf(closed.port_hours - hours / sailed.size()) < 1e-6 and absf(closed.moves_per_hour - moves / hours) < 1e-6, true, "the scoreboard matches the year's calls (%s)" % closed)
	_expect(closed.turn_minutes > 2 * rules.gate_minutes, true, "and reports the gate turn")
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.begins_with("Year 1: ")), true, "the year is reported")


func _test_inspect_each_entity() -> void:
	var sim := _port()
	_run(sim, FIRST_SHIP + 30)
	var ship := sim.ships[0]
	var crane := sim.cranes[0]
	var vehicle := sim.vehicles[0]
	var yard := sim.map.cells_of(YARD)[0]
	_expect(Inspect.pick(sim, ship.cells[0] + ship.side), ship, "a click on the water beside a quay picks its ship")
	_expect(Inspect.describe(sim, ship)[0], "%s feeder" % sim.contracts.name_of(ship.line), "a ship is named by line and class")
	_expect(Inspect.pick(sim, crane.cell), crane, "a click on a crane's quay tile picks the crane")
	_expect(Inspect.describe(sim, crane)[0], "STS crane", "a crane is named")
	_expect(Inspect.pick(sim, Vector2i(vehicle.position(1.0).round())), vehicle, "a click on a vehicle picks it")
	_expect(Inspect.describe(sim, vehicle)[0], "Tractor %d" % vehicle.id, "a vehicle is named by kind and id")
	_expect(Inspect.describe(sim, yard).slice(0, 2), ["Yard", "Import block, reach stacker"] as Array[String], "a yard tile shows its block")
	sim.vehicles.erase(vehicle)
	_expect(Inspect.describe(sim, vehicle), [] as Array[String], "a vehicle that left shows nothing")
