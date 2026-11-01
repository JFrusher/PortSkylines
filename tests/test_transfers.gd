extends SceneTree
## M8 step L: a line calling at two terminals lands imports at one that
## leave on its ship at the other, moved by road between them and charged
## as an internal move.
## godot --headless --script res://tests/test_transfers.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_a_box_moves_to_the_other_terminal()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The test port as Terminal 1 (apron, gate, import block, cranes), and
## Terminal 2 down the coast: a second apron with its own lane, a gate and
## an export block further along the east road. One line has a service at
## each; every import it lands at Terminal 1 is bound for Terminal 2.
func _test_a_box_moves_to_the_other_terminal() -> void:
	var rules := RandomPort.quick()
	rules.transfers.share = 1.0
	var sim := AreaPort.base(rules, "")
	sim.creative = true
	var entry := sim.site_entry()
	var east := sim.roads.segment_at(Vector2i(200, entry.y))
	sim.apply({"op": "build_road", "from": Vector2i(86, entry.y), "to": Vector2i(86, entry.y + 90), "type": "terminal_1_1"})
	var coast := sim.roads.segment_at(Vector2i(85, entry.y + 50))
	_expect(sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 5, "to": 84}), "", "Terminal 2's apron")
	var second: int = sim.areas.list.keys().max()
	AreaPort.add_lane(sim, second)
	_expect(sim.apply({"op": "build_area", "type": "gate", "segment": east, "side": -1, "from": 200, "to": 214}), "", "Terminal 2's gate")
	var gate: int = sim.areas.list.keys().max()
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 200, "to": 229}), "", "Terminal 2's block")
	var block: int = sim.areas.list.keys().max()
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"role": "export"}}), "", "an export block")
	var cells: Array[Vector2i] = []
	for id: int in [second, gate, block]:
		cells.append_array(sim.areas.cells(id))
	_expect(sim.apply({"op": "paint_terminal", "cells": cells, "terminal": -1}), "", "painted as Terminal 2")
	var two: int = sim.areas.terminals.keys().max()
	_expect([sim.areas.list[second].terminal, sim.areas.list[gate].terminal, sim.areas.list[block].terminal], [two, two, two], "all in Terminal 2")
	var line: String = sim.rules.lines.keys()[0]
	for apron: int in [1, second]:
		sim.contracts.services.append({"id": 900 + apron, "line": line, "kind": "feeder", "start": 9000, "window_hours": 12.0, "moves": 0, "apron": apron, "any_berth": false, "asked": 9000})
	sim.creative = false
	sim.ledger.cash = 10_000_000
	var ship := PortSim.Ship.new("feeder", line, sim.clock.calendar_minutes() + 600.0, 6, 0)
	ship.berth = 1
	ship.any_berth = false
	sim.ships.append(ship)
	_expect(AreaFlow.berth(sim, ship), true, "the line's feeder berths at Terminal 1")
	ship.state = PortSim.Ship.State.WORKING
	ship.sail = 1.0
	ship.berthed = sim.clock.calendar_minutes()
	var arrived := false
	for i in roundi(4 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if block in sim.area_stacks and sim.area_stacks[block].boxes().any(func(b: int) -> bool: return sim.boxes[b].from == 1 and sim.boxes[b].line == line):
			arrived = true
			break
	_expect(arrived, true, "an import landed at Terminal 1 reaches Terminal 2's export block")
	if arrived:
		var box: int = sim.area_stacks[block].boxes().filter(func(b: int) -> bool: return sim.boxes[b].from == 1)[0]
		_expect(sim.boxes[box].kind, "export", "as an export for the line's ship there")
	var charged := 0
	for day: Dictionary in sim.ledger.days + [{"terminals": sim.ledger.terminals}]:
		charged += day.terminals.get(1, {}).get("transfers", 0)
	_expect(charged < 0 and charged % sim.rules.transfers.cost_per_box == 0, true, "each move out of Terminal 1 is charged to it (%d)" % charged)
