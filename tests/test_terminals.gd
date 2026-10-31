extends SceneTree
## M7 step F: terminals are painted on the map. An area belongs to the
## terminal holding most of its cells, or to none, and then it is idle.
## godot --headless --script res://tests/test_terminals.gd

const RandomPort := preload("res://tests/random_port.gd")
const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_painting_sets_terminals()
	_test_fill_stops_at_roads()
	_test_names_colours_and_saves()
	_test_turns_by_terminal()
	_test_two_terminals()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A creative sim with a road east along y = 205 from x = 150 to 200 and a
## 20-cell yard block on its south side.
func _port() -> PortSim:
	var sim := PortSim.new(0, RandomPort.quick(), true)
	_expect(sim.apply({"op": "build_road", "from": Vector2i(150, 205), "to": Vector2i(200, 205), "type": "terminal_1_1"}), "", "a road is built")
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": 1, "side": 1, "from": 10, "to": 29}), "", "a yard block is built")
	return sim


## Cells x0..x1 by y0..y1, both ends included.
func _rect(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			cells.append(Vector2i(x, y))
	return cells


func _test_painting_sets_terminals() -> void:
	var sim := _port()
	var block: int = sim.areas.list.keys()[0]
	_expect(sim.areas.list[block].terminal, 0, "a new area on unpainted ground is in no terminal")
	_expect(sim.areas.idle_reason(block).contains("Paint"), true, "and is idle, saying to paint it (%s)" % sim.areas.idle_reason(block))
	_expect(sim.apply({"op": "paint_terminal", "cells": _rect(140, 190, 210, 230), "terminal": -1}), "", "painting with a new terminal")
	var first: int = sim.areas.terminals.keys()[0]
	_expect(sim.areas.terminals[first].name, "Terminal 1", "makes Terminal 1")
	_expect(sim.areas.list[block].terminal, first, "and the block is in it")
	# A second terminal over most of the block's cells takes it; a corner alone doesn't.
	var cells := sim.areas.cells(block)
	var xs: Array = cells.map(func(c: Vector2i) -> int: return c.x)
	var west: int = xs.min()
	_expect(sim.apply({"op": "paint_terminal", "cells": _rect(west, 190, west + 5, 230), "terminal": -1}), "", "a second terminal over the block's west end")
	var second: int = sim.areas.terminals.keys().max()
	_expect(sim.areas.list[block].terminal, first, "the block stays in the terminal holding most of it")
	_expect(sim.apply({"op": "paint_terminal", "cells": _rect(west, 190, west + 15, 230), "terminal": second}), "", "the second spreads over most of it")
	_expect(sim.areas.list[block].terminal, second, "and the block moves to it at once")
	_expect(sim.apply({"op": "paint_terminal", "cells": _rect(140, 190, 210, 230), "terminal": 0}), "", "erasing everything")
	_expect(sim.areas.terminals.is_empty(), true, "leaves no terminals")
	_expect(sim.areas.list[block].terminal, 0, "and the block in none")
	_expect(sim.apply({"op": "paint_terminal", "cells": [Vector2i(170, 210)], "terminal": 99}), "No such terminal", "an unknown terminal is refused")


## A closed loop of road: the fill from inside covers exactly the cells
## the lanes enclose; from open ground it is refused.
func _test_fill_stops_at_roads() -> void:
	var sim := PortSim.new(0, RandomPort.quick(), true)
	for leg: Array in [[Vector2i(150, 205), Vector2i(180, 205)], [Vector2i(180, 205), Vector2i(180, 235)], [Vector2i(180, 235), Vector2i(150, 235)], [Vector2i(150, 235), Vector2i(150, 205)]]:
		_expect(sim.apply({"op": "build_road", "from": leg[0], "to": leg[1], "type": "terminal_1_1"}), "", "a leg of the loop is built")
	var inside := sim.areas.fill_cells(Vector2i(165, 220))
	_expect(inside.size(), 28 * 28, "the fill inside the loop covers the 28 by 28 cells its lanes enclose")
	_expect(inside.all(func(c: Vector2i) -> bool: return c.x > 150 and c.x < 179 and c.y > 205 and c.y < 234), true, "all of them inside it")
	_expect(sim.apply({"op": "fill_terminal", "cell": Vector2i(165, 220), "terminal": -1}), "", "a fill paints a new terminal")
	_expect(sim.areas.paint.size(), 28 * 28, "over those cells")
	_expect(sim.apply({"op": "fill_terminal", "cell": Vector2i(300, 400), "terminal": -1}), "No road closes in this ground", "a fill on open ground is refused")


func _test_names_colours_and_saves() -> void:
	var sim := _port()
	sim.apply({"op": "paint_terminal", "cells": _rect(140, 190, 210, 230), "terminal": -1})
	var id: int = sim.areas.terminals.keys()[0]
	_expect(sim.apply({"op": "name_terminal", "terminal": id, "name": "North Quay"}), "", "a terminal is renamed")
	_expect(sim.apply({"op": "name_terminal", "terminal": id, "name": "  "}), "A terminal needs a name", "but not to nothing")
	var colour: int = sim.areas.terminals[id].colour
	_expect(sim.apply({"op": "colour_terminal", "terminal": id}), "", "its colour moves on")
	_expect(sim.areas.terminals[id].colour != colour, true, "to another")
	var copy := PortSim.from_dict(sim.to_dict())
	_expect([copy.areas.terminals, copy.areas.paint.size(), copy.areas.list[1].terminal], [sim.areas.terminals, sim.areas.paint.size(), id], "terminals and paint survive a save")


## Lorry turn times are kept per terminal, by the gate a lorry leaves by.
func _test_turns_by_terminal() -> void:
	var sim := AreaPort.base(RandomPort.rules(), "")
	RandomPort.calls(sim, "feeder", 10, 45, 1)
	for i in roundi(3 * 60 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(sim.terminal_turns.get(1, []).size(), mini(sim.year.turns, 50), "each lorry's turn counts for Terminal 1, the gate's")
	_expect(sim.terminal_turn_minutes(1) > 0.0 and is_equal_approx(sim.terminal_turn_minutes(1), sim.kpis().gate_turn_minutes), true, "averaging as the port's own (%.1f min)" % sim.terminal_turn_minutes(1))


## M8 step A: two terminals on the test port, the second painted over a
## second apron down the coast road and a gate further along the east road.
## Each has its own ledger section and KPIs, and a ship signed for one
## terminal's berth waits rather than take the other's.
func _test_two_terminals() -> void:
	var sim := AreaPort.terminal(50)
	var coast := sim.roads.segment_at(Vector2i(85, 250))
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_expect(sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 50, "to": 99}), "", "a second apron down the coast")
	var second_apron: int = sim.areas.list.keys().max()
	_expect(sim.apply({"op": "build_area", "type": "gate", "segment": east, "side": -1, "from": 200, "to": 214}), "", "a second gate along the east road")
	var second_gate: int = sim.areas.list.keys().max()
	var cells: Array[Vector2i] = sim.areas.cells(second_apron)
	cells.append_array(sim.areas.cells(second_gate))
	_expect(sim.apply({"op": "paint_terminal", "cells": cells, "terminal": -1}), "", "painting them as a second terminal")
	var two: int = sim.areas.terminals.keys().max()
	_expect([sim.areas.list[second_apron].terminal, sim.areas.list[second_gate].terminal, sim.areas.list[1].terminal], [two, two, 1], "the second apron and gate are in it, the first apron isn't")
	_expect([sim.areas.terminal_error(1), sim.areas.terminal_error(two)], ["", ""], "both terminals work")
	# Ledger: building in a terminal is that terminal's cost, roads the port's.
	sim.creative = false
	sim.ledger.cash = 10_000_000
	var before: Dictionary = sim.ledger.terminals.duplicate(true)
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 29, "to": 58}), "", "a yard block in terminal 1")
	var block: int = sim.areas.list.keys().max()
	_expect(sim.ledger.terminals[1].construction < before.get(1, {}).get("construction", 0), true, "the block is charged to terminal 1")
	_expect(sim.ledger.terminals.get(two, {}).has("construction"), false, "and not to the other terminal")
	sim.apply({"op": "build_road", "from": Vector2i(150, 360), "to": Vector2i(170, 360), "type": "terminal_1_1"})
	_expect(sim.ledger.terminals[0].get("construction", 0) < before.get(0, {}).get("construction", 0), true, "a road is the port's")
	# Moves in a terminal are its income, and its KPIs count them.
	var line: String = sim.rules.lines.keys()[0]
	sim._moved(sim.boxes[sim._new_box("import", 0.0, line)], line, two)
	_expect(sim.ledger.terminals[two].moves > 0, true, "a move at the second terminal is its income")
	# Every section adds up to the day's lines.
	var total := {}
	for section: Dictionary in sim.ledger.terminals.values():
		for category: String in section:
			total[category] = total.get(category, 0) + section[category]
	_expect(total, sim.ledger.today, "the sections add up to the day's lines")
	sim._end_of_day()  # closes the day too
	var upkeep := 0
	for section: Dictionary in sim.ledger.days[-1].terminals.values():
		upkeep += section.get("upkeep", 0)
	_expect(upkeep, sim.ledger.days[-1].lines.upkeep, "upkeep is split across the sections and adds up")
	_expect(sim.ledger.days[-1].terminals[1].upkeep < 0, true, "terminal 1 pays its own upkeep")
	_expect(sim.terminal_kpis(two).moves_yesterday, 1, "the second terminal's KPIs count its move")
	_expect(sim.terminal_kpis(1).moves_yesterday, 0, "and the first's don't")
	_expect(sim.terminal_kpis(1).yard_use, sim.block_fill(block).x / float(sim.block_fill(block).y), "terminal 1's yard use is its own block's")
	# A service signed for terminal 1's berth doesn't take terminal 2's, even when it may move berth.
	var ship := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 600.0, 10, 0)
	ship.berth = 1
	ship.any_berth = true
	var blocker := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 600.0, 10, 0)
	blocker.berth = 1
	# Feeders until terminal 1's berth is full; the next waits rather than take terminal 2's.
	while AreaFlow.berth(sim, blocker):
		sim.ships.append(blocker)
		blocker = PortSim.Ship.new("feeder", blocker.line, blocker.due, 10, 0)
		blocker.berth = 1
	_expect(not sim.ships.is_empty() and sim.ships.all(func(s: PortSim.Ship) -> bool: return s.apron == 1), true, "terminal 1's ships fill its own berth")
	_expect(AreaFlow.berth(sim, ship), false, "the next ship for terminal 1 waits rather than take terminal 2's")
	ship.berth = second_apron
	_expect(AreaFlow.berth(sim, ship) and ship.apron == second_apron, true, "one signed for terminal 2 berths there")
