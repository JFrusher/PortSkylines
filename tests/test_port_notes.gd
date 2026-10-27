extends SceneTree
## M6 notes from the M5 playtest: one STS crane comes down without its apron.
## godot --headless --script res://tests/test_port_notes.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_remove_one_crane()
	_test_berth_plan()
	_test_ships_go_to_their_berth()
	_test_berth_board()
	_test_cost_per_move()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## A crane working a ship stays up; once the ship has sailed it comes down
## alone, leaving its apron and the other crane, and the berth works on.
func _test_remove_one_crane() -> void:
	var sim := AreaPort.working_terminal(10)
	sim.creative = true
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": 1, "along": 40}), "", "a second crane goes up")
	sim.tick()
	_expect(sim.apply({"op": "remove_sts", "apron": 1, "along": 20}), "Wait for the ship alongside to sail", "a crane working a ship stays up")
	var ship: PortSim.Ship = sim.ships[0]
	for i in SimClock.TICKS_PER_DAY:
		sim.tick()
		if ship not in sim.ships:
			break
	_expect(ship in sim.ships, false, "the ship is worked and sails")
	_expect(sim.apply({"op": "remove_sts", "apron": 1, "along": 30}), "No crane there", "only a crane's own spot takes it down")
	_expect(sim.apply({"op": "remove_sts", "apron": 1, "along": 20}), "", "an idle crane comes down")
	_expect(sim.cranes.map(func(c: PortSim.Crane) -> int: return c.along), [40], "only that crane is gone")
	_expect(1 in sim.areas.list, true, "its apron stays")
	var cell: Vector2i = sim.areas.list[1].start + (sim.areas.list[1].end - sim.areas.list[1].start).sign() * 40
	_expect(AreaFlow.crane_at(sim, cell) == sim.cranes[0], true, "the crane left is found from a cell under it")


## An offer accepted onto a berth calls at the line's time if free there,
## else the nearest free hour within flex_hours; with none, it is refused,
## and another berth takes it at its own time. An agreed service moves the
## same way, and may be let take any berth.
func _test_berth_plan() -> void:
	var sim := _two_berths()
	var aprons := AreaFlow.ready_aprons(sim)
	var line: String = sim.rules.lines.keys()[0]
	var offer := func(id: int, hour: int) -> int:
		sim.contracts.offers.append({"id": id, "line": line, "kind": "feeder", "start": hour * 60, "asked": hour * 60, "window_hours": 12.0, "moves": 40, "apron": aprons[0], "any_berth": false, "expires": 1e9})
		return id
	_expect(sim.apply({"op": "accept_offer", "id": offer.call(1, 0), "apron": aprons[0]}), "", "an offer is agreed on a berth")
	_expect(sim.apply({"op": "accept_offer", "id": offer.call(2, 6), "apron": aprons[0]}), "", "an overlapping one too")
	var starts: Array = sim.contracts.services.map(func(s: Dictionary) -> int: return s.start / 60)
	_expect(starts, [0, 12], "at the line's time, then moved to the nearest free hour (12:00, 6 h on)")
	_expect(sim.apply({"op": "accept_offer", "id": offer.call(3, 6), "apron": aprons[0]}), "No free window on this berth within %d h of the line's time" % sim.rules.contracts.flex_hours, "with no free hour in reach it is refused")
	_expect(sim.apply({"op": "accept_offer", "id": 3, "apron": aprons[1]}), "", "the other berth takes it")
	_expect(sim.contracts.services[-1].start, 6 * 60, "at the line's own time")
	_expect(AreaFlow.berth_plan(sim).any(func(p: Dictionary) -> bool: return p.clash), false, "nothing clashes")
	_expect(sim.apply({"op": "move_service", "id": 3, "apron": aprons[0]}), "No free window on this berth within %d h of the line's time" % sim.rules.contracts.flex_hours, "a move onto a full berth is refused")
	_expect(sim.apply({"op": "move_service", "id": 1, "apron": aprons[1]}), "", "a service moves to another berth")
	_expect([sim.contracts.services[0].apron, sim.contracts.services[0].start / 60], [aprons[1], 7 * 24 - 6], "the nearest free hour there to its line's Monday 00:00: Sunday 18:00")
	_expect(sim.apply({"op": "set_any_berth", "id": 2, "any_berth": true}), "", "a service may take any berth")
	_expect(sim.contracts.services[1].any_berth, true, "and keeps that")
	_expect(sim.apply({"op": "accept_offer", "id": offer.call(4, 30), "apron": 999}), "Not a working berth", "only a working berth takes calls")


## A port with two ready berths: the base port's apron and one south of it.
func _two_berths() -> PortSim:
	var sim := AreaPort.base(RandomPort.quick(), "")
	sim.creative = true
	var entry := sim.site_entry()
	sim.apply({"op": "build_road", "from": Vector2i(85, entry.y), "to": Vector2i(85, entry.y + 90), "type": "terminal_1_1"})
	var coast := sim.roads.segment_at(Vector2i(85, entry.y + 50))
	sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 10, "to": 79})
	sim.apply({"op": "set_terminal", "id": sim.areas.list.keys()[-1], "terminal": 1})
	return sim


## A ship goes to its service's berth though another is free first; with
## its berth full it waits, unless its service may take any berth.
func _test_ships_go_to_their_berth() -> void:
	var sim := _two_berths()
	var aprons := AreaFlow.ready_aprons(sim)
	_expect(aprons.size(), 2, "two ready berths")
	var ship := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], 0.0, 0, 0)
	ship.berth = aprons[1]
	ship.any_berth = false
	_expect(AreaFlow.berth(sim, ship) and ship.apron == aprons[1], true, "a ship goes to its own berth, not the first free one")
	# Fill the first berth end to end.
	var span := AreaFlow.ship_cells(sim, "feeder")
	for from in range(0, AreaFlow._length(sim, aprons[0]) - span + 1, span):
		var moored := PortSim.Ship.new("feeder", ship.line, 0.0, 0, 0)
		moored.apron = aprons[0]
		moored.from = from
		moored.state = PortSim.Ship.State.WORKING
		sim.ships.append(moored)
	var waiting := PortSim.Ship.new("feeder", ship.line, 0.0, 0, 0)
	waiting.berth = aprons[0]
	waiting.any_berth = false
	_expect(AreaFlow.berth(sim, waiting), false, "with its berth full, it waits at anchor")
	waiting.any_berth = true
	_expect(AreaFlow.berth(sim, waiting) and waiting.apron == aprons[1], true, "unless its service takes any berth")


## The board shows where a dragged offer would land, or why not, and a drop
## or a click on a call sends the command that does it.
func _test_berth_board() -> void:
	var sim := _two_berths()
	var aprons := AreaFlow.ready_aprons(sim)
	var line: String = sim.rules.lines.keys()[0]
	for id: int in [1, 2]:
		var asked := (id - 1) * 6 * 60
		sim.contracts.offers.append({"id": id, "line": line, "kind": "feeder", "start": asked, "asked": asked, "window_hours": 12.0, "moves": 40, "apron": aprons[0], "any_berth": false, "expires": 1e9})
	var board := BerthBoard.new()
	board.sim = sim
	var sent: Array[Dictionary] = []
	board.command_issued.connect(func(command: Dictionary) -> void: sent.append(command))
	_expect(board.landing({"id": 1, "offer": true}, aprons[0]).start, 0, "an offer lands at its line's time on a free berth")
	board.drop({"id": 1, "offer": true}, aprons[0])
	_expect(sent[-1], {"op": "accept_offer", "id": 1, "apron": aprons[0]}, "a drop agrees it there")
	_expect(sim.apply(sent[-1]), "", "and the sim takes it")
	_expect(board.landing({"id": 2, "offer": true}, aprons[0]).start, 12 * 60, "the next, asked for 06:00, lands at the nearest free hour, 12:00")
	_expect(board.landing({"id": 2, "offer": true}, 999).why, "Not a working berth", "and shows why where it can't")
	board.toggle_any_berth(1)
	_expect(sent[-1], {"op": "set_any_berth", "id": 1, "any_berth": true}, "a click lets a call take any berth")
	board.drop({"id": 1, "offer": false}, aprons[1])
	_expect(sent[-1].op, "move_service", "dragging a call moves it")
	board.free()


## Over three days of feeder calls, the panel's figures per move are the
## ledger's closed days over the moves counted in them, and its per-line and
## per-terminal moves and upkeep add up to the port's.
func _test_cost_per_move() -> void:
	var sim := AreaPort.base(RandomPort.quick())
	for i in 3 * SimClock.TICKS_PER_DAY:
		sim.tick()
	var per := HudDetails.per_move(sim)
	var moves := 0
	var net := 0
	var income := 0
	for day: Dictionary in sim.ledger.days:
		moves += day.moves.total
		net += day.closed - day.opened
		income += day.lines.get("moves", 0)
	_expect(moves > 100 and per.moves == moves, true, "it counts the closed days' moves (%d)" % moves)
	_expect(is_equal_approx(per.net, float(net) / moves), true, "net per move is the ledger's net over moves (%.2f)" % per.net)
	_expect(is_equal_approx(per.categories.moves, float(income) / moves), true, "income per move is the ledger's move income over moves")
	var by_line := 0
	for line: String in per.lines:
		by_line += per.lines[line].moves
	_expect(by_line, moves, "every move is some line's")
	_expect(per.terminals[1].moves, moves, "and the one terminal's")
	var parts := sim.upkeep_parts()
	_expect(roundi(parts.values().reduce(func(a: float, b: float) -> float: return a + b, 0.0)), sim.daily_upkeep(), "upkeep by terminal and shared adds up to the day's")


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
