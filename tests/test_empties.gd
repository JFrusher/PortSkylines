extends SceneTree
## Empties: blocks that hold them, their return by lorry, exporters taking
## them out, and lines shipping the surplus (M6 steps E1-E4).

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_empty_blocks()
	_test_empties_come_back()
	_test_empties_turned_away()
	_test_exporters_collect_empties()
	_test_lines_ship_surplus_empties()
	_test_some_empties_go_inland()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Empty handlers work only blocks set to the empty role, and stack their
## data's tiers.
func _test_empty_blocks() -> void:
	var sim := AreaPort.base(RandomPort.quick(), "")
	var block := 3
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"gear": "empty_handler"}}), "Empty handlers only work empty blocks", "an import block can't take empty handlers")
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"role": "empty", "gear": "empty_handler"}}), "", "an empty block can")
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"role": "import"}}), "Empty handlers only work empty blocks", "and can't be made an import block while they work it")
	sim.tick()
	_expect(AreaFlow._stacks(sim, block).to_dict().tiers, sim.rules.yard_gear.empty_handler.tiers, "its stacks go the handlers' tiers high")


## A port whose imports go out by lorry 30 minutes after landing and come back
## as empties `return_days` later; `empty_block` adds an empty block.
func _returning_port(empty_block: bool) -> PortSim:
	var rules := RandomPort.rules()
	rules.empties.return_days = 0.25
	rules.empties.return_share = 1.0
	var sim := AreaPort.base(rules, "")
	if empty_block:
		var block := AreaPort.add_export_block(sim)
		sim.apply({"op": "set_area", "id": block, "settings": {"role": "empty"}})
	RandomPort.calls(sim, "feeder", 10, 45, 1)
	return sim


## Each import collected comes back as an empty of its line and size, by lorry
## into the empty block, return_days after it left.
func _test_empties_come_back() -> void:
	var sim := _returning_port(true)
	var left := {}  # import box id -> the minute it left
	var lines := {}
	for i in roundi(SimClock.MINUTES_PER_DAY / SimClock.CALENDAR_MINUTES_PER_TICK):
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.state == "leaving" and vehicle.loaded and sim.boxes[vehicle.box].kind == "import" and vehicle.box not in left:
				left[vehicle.box] = sim.clock.calendar_minutes()
				lines[sim.boxes[vehicle.box].line] = true
		sim.tick()
	var block: int = sim.areas.list.keys().filter(func(id: int) -> bool: return sim.areas.list[id].settings.get("role") == "empty")[0]
	var empties: Array = AreaFlow._stacks(sim, block).boxes().filter(func(id: int) -> bool: return sim.boxes[id].kind == "empty")
	_expect(left.size() > 0 and empties.size() > 0, true, "imports left (%d) and empties came back into the empty block (%d)" % [left.size(), empties.size()])
	var first_left: float = left.values().min() if not left.is_empty() else INF
	_expect(empties.all(func(id: int) -> bool: return sim.boxes[id].in >= first_left + sim.rules.empties.return_days * SimClock.MINUTES_PER_DAY), true, "none came back before return_days had passed")
	_expect(empties.all(func(id: int) -> bool: return sim.boxes[id].line in lines), true, "each is of a line whose imports left")


## With no empty block, a returning empty's lorry is turned away at the gate
## and its line thinks less of the port.
func _test_empties_turned_away() -> void:
	var sim := _returning_port(false)
	var line: String = sim.rules.lines.keys()[0]
	var before: float = sim.contracts.reputation[line]
	for i in roundi(SimClock.MINUTES_PER_DAY / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(sim.boxes.values().any(func(b: Dictionary) -> bool: return b.kind == "empty" and b.in >= 0.0), false, "no empty is stacked")
	_expect(sim.contracts.reputation[line] < before, true, "the line's reputation fell (%.1f -> %.1f)" % [before, sim.contracts.reputation[line]])
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.contains("turned away")), true, "the status says an empty was turned away")


## With empties in the port, export demand first sends lorries to collect
## them; each comes back full stuffing_hours later.
func _test_exporters_collect_empties() -> void:
	var rules := RandomPort.rules()
	rules.empties.stuffing_hours = 1.0
	rules.ship_classes.feeder.export_moves = 5  # fewer than the empties in the port
	var sim := AreaPort.base(rules, "")
	AreaPort.add_export_block(sim)
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	sim.creative = true
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 91, "to": 120}), "", "an empty block is built")
	sim.creative = false
	var block: int = sim.areas.list.keys()[-1]
	sim.apply({"op": "set_area", "id": block, "settings": {"role": "empty"}})
	for i in 10:
		sim.returning.append({"at": 0.0, "line": sim.rules.lines.keys()[0], "teu": 1})
	# The empties come in first, before any export is wanted.
	while AreaFlow._stacks(sim, block).boxes().size() < 10:
		sim.tick()
	# Due in 10 h, within export_lead_hours, so exports are wanted now; no ship arrives in the run.
	RandomPort.calls(sim, "feeder", roundi(sim.clock.calendar_minutes()) + 600, 45, 1)
	var collected := -1.0
	var first_export := -1.0
	for i in roundi(4 * 60 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for vehicle: Vehicle in sim.vehicles:
			if collected < 0.0 and vehicle.state == "leaving" and vehicle.loaded and sim.boxes[vehicle.box].kind == "empty":
				collected = sim.clock.calendar_minutes()
		if first_export < 0.0 and sim.boxes.values().any(func(b: Dictionary) -> bool: return b.kind == "export"):
			first_export = sim.clock.calendar_minutes()
	_expect(collected >= 0.0, true, "an exporter's lorry left with an empty")
	_expect(first_export >= collected + 60.0, true, "and the first export came in after it was packed (collected %.0f, export %.0f)" % [collected, first_export])
	_expect(AreaFlow._stacks(sim, block).boxes().size(), 5, "each of the 5 exports took out an empty")


## A ship loads its line's empties after its exports, while the port holds
## more than keep of them, up to max_per_call, at price_factor of a move.
func _test_lines_ship_surplus_empties() -> void:
	var rules := RandomPort.rules()
	rules.empties.keep = 5
	rules.empties.max_per_call = 10
	rules.empties.return_days = 30.0  # none of this ship's imports come back in the run
	rules.ship_classes.feeder.import_moves = 4
	rules.ship_classes.feeder.export_moves = 0
	var sim := AreaPort.base(rules, "")
	var block := AreaPort.add_export_block(sim)
	sim.apply({"op": "set_area", "id": block, "settings": {"role": "empty"}})
	var line: String = sim.rules.lines.keys()[0]
	for i in 12:
		sim.returning.append({"at": 0.0, "line": line, "teu": 1})
	while AreaFlow._stacks(sim, block).boxes().size() < 12:
		sim.tick()
	RandomPort.calls(sim, "feeder", roundi(sim.clock.calendar_minutes()) + 10, 45, 1)
	for i in roundi(12 * 60 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if not sim.ship_log.is_empty():
			break
	_expect(sim.ship_log.size(), 1, "the ship sailed")
	_expect(sim.ship_log[0].moves if not sim.ship_log.is_empty() else -1, 4 + 7, "it took its 4 imports off and the 7 empties above keep aboard")
	_expect(AreaFlow._stacks(sim, block).boxes().size(), 5, "keep empties stay in the port")
	var empty := {"kind": "empty", "teu": 1, "reefer": false}
	_expect(sim.move_price(empty), roundi(rules.move_price.per_20ft * rules.empties.price_factor), "an empty earns price_factor of a move")


## Only return_share of the imports that leave come back as empties.
func _test_some_empties_go_inland() -> void:
	var rules := RandomPort.rules()
	rules.empties.return_share = 0.5
	var sim := AreaPort.base(rules, "")
	for i in 400:
		sim.boxes[100000 + i] = {"kind": "import", "line": sim.rules.lines.keys()[0], "teu": 1}
		sim._import_left(100000 + i)
	_expect(absi(sim.returning.size() - 200) < 40, true, "about half of 400 imports come back (%d)" % sim.returning.size())
