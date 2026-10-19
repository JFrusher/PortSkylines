extends SceneTree
## Headless tests for the build rules and the ship-to-lorry loop.
## godot --headless --script res://tests/test_sim.gd

const ROAD := PortMap.Tile.ROAD
const QUAY := PortMap.Tile.QUAY
const YARD := PortMap.Tile.YARD
const GATE := PortMap.Tile.GATE

var _failures := 0


func _initialize() -> void:
	_test_build_rules()
	_test_bulldoze_rules()
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
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A road from the highway to the coast with a gate near the highway, a
## 12-tile quay with an apron road behind it, two cranes, six tractors and a
## 3x2 yard block beside the road.
func _port(rules := Content.base()) -> PortSim:
	var sim := PortSim.new(0, rules)
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
	_expect(sim.build(QUAY, Vector2i(30, 3)), "A quay must face the water", "inland quay")
	_expect(sim.build(QUAY, Vector2i(12, 3)), "", "coastal quay")
	_expect(sim.build(ROAD, Vector2i(12, 3)), "Bulldoze first", "road on a quay")
	_expect(sim.build(ROAD, Vector2i(99, 3)), "Off the map", "road off the map")
	_expect(sim.build(QUAY, Vector2i(12, 0)), "", "quay on the north edge faces the sea")
	_expect(sim.build(QUAY, Vector2i(30, 0)), "A quay must face the water", "map edge is not water")
	_expect(sim.money, sim.rules.start_money - 400, "quays cost money")
	sim.money = 5
	_expect(sim.build(ROAD, Vector2i(30, 3)), "Not enough money", "building while broke")


func _test_bulldoze_rules() -> void:
	var sim := _port()
	var yard := Vector2i(sim.map.sea_width + 3, sim.map.entry.y - 1)
	_expect(sim.bulldoze(sim.map.entry), "That's the highway", "bulldoze highway")
	_expect(sim.bulldoze(Vector2i(30, 3)), "Nothing to bulldoze", "bulldoze empty land")
	sim.yard.add(yard, 999)
	_expect(sim.bulldoze(yard), "The yard still holds boxes", "bulldoze a full yard")
	sim.yard.take(yard, 999)
	_expect(sim.bulldoze(yard), "", "bulldoze an empty yard")
	_expect(sim.map.tile(yard), PortMap.Tile.LAND, "bulldozed yard is land again")


func _test_no_ship_without_a_road() -> void:
	var sim := PortSim.new()
	sim.build(QUAY, Vector2i(12, 3))
	_run(sim, sim.rules.first_ship_minutes + 1)
	_expect(sim.ships.size(), 0, "no ship calls at an unconnected quay")


func _test_ships_unload_and_lorries_pay() -> void:
	var rules := Content.base().duplicate(true)
	rules.import_dwell_minutes = 0.0
	var sim := _port(rules)
	var before := sim.money
	_run(sim, sim.rules.first_ship_minutes + 1)
	_expect(sim.ships.size(), 1, "a ship calls at the 12-tile berth")
	var cargo := sim.ships[0].boxes
	# One reach stacker serves the block, stacking each box and later loading
	# it onto a lorry, so the yard machine sets the pace.
	_run(sim, cargo * sim.rules.yard_gear.reach_stacker.handling_minutes * 2 + 200)
	_expect(sim.delivered >= cargo, true, "the first ship's %d boxes are all delivered (%d)" % [cargo, sim.delivered])
	_expect(sim.money, before + sim.delivered * sim.rules.fee_per_box, "every delivery is paid")


func _test_commands() -> void:
	var by_command := PortSim.new()
	var direct := PortSim.new()
	var cell := Vector2i(12, 3)
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
	_expect(copy.build(ROAD, Vector2i(30, 3)), "", "the copy's map still accepts builds")
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
	var rules := Content.base().duplicate(true)
	rules.ship_classes.feeder.weight = 0.0
	var sim := PortSim.new(0, rules)
	var row := sim.map.entry.y
	for x in range(sim.map.sea_width + 1, sim.map.entry.x):
		sim.build(ROAD, Vector2i(x, row))
	for y in range(row - 4, row + 4):
		sim.build(QUAY, Vector2i(sim.map.sea_width, y))
	_run(sim, sim.rules.first_ship_minutes + 1)
	_expect(sim.ships.size(), 0, "a panamax does not call at an 8-tile berth")
	_expect(sim.last_event().contains("12 quay tiles"), true, "the status says how long a berth it needs (%s)" % sim.last_event())
	rules.water_depth = 11.0
	var shallow := PortSim.new(0, rules)
	_run(shallow, shallow.rules.first_ship_minutes + 1)
	_expect(shallow.last_event().contains("needs 13 m"), true, "a panamax does not call at 11 m of water (%s)" % shallow.last_event())


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
	rules.ship_classes.feeder.weight = 0.0
	rules.ship_classes.panamax.import_moves = 120
	rules.start_money = 100000
	# A yard that never holds the cranes up: room for everything, a machine
	# per tile, near-instant stacking.
	rules.yard_gear.reach_stacker = {"capacity": 1000, "handling_minutes": 0.05, "tiles_per_machine": 1, "cost_per_tile": 0, "upkeep_per_machine": 0}
	var sim := _port(rules)
	var row := sim.map.entry.y
	sim.place_crane(Vector2i(sim.map.sea_width, row + 2))
	sim.buy_tractors(10)
	_run(sim, rules.first_ship_minutes + 1)
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
	var rules := Content.base().duplicate(true)
	rules.ship_classes.feeder.weight = 0.0
	rules.sts_crane.outreach = 8
	var sim := PortSim.new(0, rules)
	var row := sim.map.entry.y
	for x in range(sim.map.sea_width + 1, sim.map.entry.x):
		sim.build(ROAD, Vector2i(x, row))
	for y in range(row - 6, row + 6):
		sim.build(QUAY, Vector2i(sim.map.sea_width, y))
	sim.place_crane(Vector2i(sim.map.sea_width, row))
	_run(sim, sim.rules.first_ship_minutes + 30)
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
	sim.build(ROAD, Vector2i(30, 3))
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
	_expect(sim.set_yard(Vector2i(30, 3), {"role": "export"}), "That is not a yard", "settings need a yard")
	var exports := _port()
	exports.set_yard(tile, {"role": "export"})
	_run(exports, exports.rules.first_ship_minutes + 30)
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
		rules.ship_classes.feeder.weight = 0.0
		rules.start_money = 100000
		rules.yard_gear.reach_stacker = {"capacity": 1000, "handling_minutes": 20.0, "tiles_per_machine": per_machine, "cost_per_tile": 0, "upkeep_per_machine": 0}
		rules.lorry_interval_minutes = 1e9  # no lorries competing for the machines
		var sim := _port(rules)
		sim.buy_tractors(20)
		_run(sim, rules.first_ship_minutes + 1)
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
	rules.ship_classes.panamax.weight = 0.0
	rules.first_ship_minutes = 120.0
	var sim := _port(rules)
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
	_run(sim, sim.rules.first_ship_minutes + 240)
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
		rules.first_ship_minutes = 1e9
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
	rules.first_ship_minutes = 1e9
	var sim := _port(rules)
	var upkeep := sim.daily_upkeep()
	var expected: int = rules.upkeep.road * sim.map.cells_of(ROAD).size() + rules.upkeep.quay * 12 + rules.upkeep.yard * 6 + rules.upkeep.gate + rules.upkeep.sts_crane * 2 + rules.upkeep.tractor * 6 + rules.yard_gear.reach_stacker.upkeep_per_machine
	_expect(upkeep, expected, "upkeep adds every tile, crane, tractor and yard machine")
	for i in SimClock.TICKS_PER_DAY - 1:
		sim.tick()
	var before := sim.money
	sim.tick()
	_expect([before - sim.money, sim.upkeep_paid], [upkeep, upkeep], "upkeep is charged exactly at midnight")
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
	sim.ships.clear()
	sim.call("_call_ship")
	sim.money = 100000
	_expect(sim.build(QUAY, Vector2i(coast, top)), "", "quay at the berth start")
	_expect(sim.build(ROAD, Vector2i(coast + 1, top)), "", "apron at the berth start")
	sim.call("_call_ship")
	for ship: PortSim.Ship in sim.ships.slice(1):
		_expect(ship.cells.filter(func(c: Vector2i) -> bool: return c in sim.ships[0].cells), [], "ships share no quay tile")


## A tile that becomes a block's anchor must not reset its role and gear.
func _test_new_yard_tile_keeps_block_settings() -> void:
	var sim := _port()
	sim.money = 100000
	var tile := Vector2i(sim.map.sea_width + 3, sim.map.entry.y - 2)
	_expect(sim.apply({"op": "set_yard", "cell": tile, "settings": {"role": "export", "gear": "rtg"}}), "", "export RTG block")
	_expect(sim.build(YARD, tile + Vector2i.UP), "", "yard tile above the anchor")
	var anchor := sim.yard.anchor(tile)
	_expect(anchor, tile + Vector2i.UP, "the new tile anchors the block")
	_expect([sim.yard.role_of(anchor), sim.yard.gear_of(anchor)], ["export", "rtg"], "the block keeps its settings")
	var before := sim.money
	_expect(sim.build(YARD, tile + Vector2i.UP * 2), "", "another tile on the RTG block")
	_expect(before - sim.money, sim.cost(YARD) + sim.rules.yard_gear.rtg.cost_per_tile, "joining an RTG block pays for its gear")
	sim.money = sim.cost(YARD)
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
