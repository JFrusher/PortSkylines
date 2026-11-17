extends SceneTree
## Headless tests for M12's per-block rules: the boxes a yard block takes,
## how high it stacks, its stacking strategy and rule templates.
## godot --headless --script res://tests/test_block_rules.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_rules_are_checked()
	_test_a_box_breaking_a_rule_is_never_placed()
	_test_a_box_no_block_takes_stays_aboard()
	_test_export_lorries_respect_rules()
	_test_by_departure_needs_fewer_rehandles()
	_test_templates_copy_rules()
	_test_discharge_spreads_over_blocks()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _run(sim: PortSim, minutes: float) -> void:
	for i in roundi(minutes / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()


## AreaPort.base with a second import block east of the first; returns [sim, first, second].
func _two_blocks(rules: Dictionary) -> Array:
	var sim := AreaPort.base(rules)
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	sim.creative = true
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 60, "to": 89}), "", "a second import block is built")
	sim.creative = false
	return [sim, 3, sim.areas.list.keys()[-1]]


## The boxes stacked in `block`.
func _stacked(sim: PortSim, block: int) -> Array:
	return sim.area_stacks[block].boxes().map(func(id: int) -> Dictionary: return sim.boxes[id]) if block in sim.area_stacks else []


func _test_rules_are_checked() -> void:
	var sim := AreaPort.base()
	_expect(sim.areas.list[3].settings.sizes, [], "a new block takes every size")
	_expect([sim.areas.list[3].settings.reefers, sim.areas.list[3].settings.max_tiers], [true, 0], "and reefers, as high as its gear stacks")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"sizes": [3]}}) != "", true, "a size that isn't 20 or 40 ft is refused")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"max_tiers": -1}}) != "", true, "so is a negative height")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"reefers": 1}}) != "", true, "and reefers that aren't yes or no")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"lines": ["nobody"]}}) != "", true, "and an unknown line")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"sizes": [1], "reefers": false, "max_tiers": 2, "lines": [sim.rules.lines.keys()[0]]}}), "", "rules are set by command")
	_expect(PortSim.from_dict(sim.to_dict()).state_hash(), sim.state_hash(), "and saved")
	_expect(sim.block_fill(3).y, sim.areas.layout(3).stacks.size() * 2 * 2, "a block limited to 2 tiers holds 2 tiers of TEU")


## One block takes only 20 ft boxes that aren't reefers, two tiers high, the
## other everything: after ships have worked, the first holds nothing else.
func _test_a_box_breaking_a_rule_is_never_placed() -> void:
	var port := _two_blocks(RandomPort.quick())
	var sim: PortSim = port[0]
	_expect(sim.apply({"op": "set_area", "id": port[1], "settings": {"sizes": [1], "reefers": false, "max_tiers": 2}}), "", "the first block takes only dry 20 ft boxes, two high")
	var highest := 0
	for tick in roundi(240.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if port[1] in sim.area_stacks:
			for stack: Array in sim.area_stacks[port[1]].stacks:
				highest = maxi(highest, stack.size())
	var first := _stacked(sim, port[1])
	var second := _stacked(sim, port[2])
	_expect(first.size() > 10, true, "the ruled block took boxes (%d)" % first.size())
	_expect(first.all(func(box: Dictionary) -> bool: return box.teu == 1 and not box.reefer), true, "every one a dry 20 ft box")
	_expect(highest in [1, 2], true, "stacked no higher than its two tiers (%d)" % highest)
	_expect(second.any(func(box: Dictionary) -> bool: return box.teu == 2), true, "the 40 ft boxes went to the other block")
	# A line rule: the port's ships are all the first line's, so a block for another line takes none.
	var lines := _two_blocks(RandomPort.quick())
	sim = lines[0]
	_expect(sim.apply({"op": "set_area", "id": lines[1], "settings": {"lines": [sim.rules.lines.keys()[1]]}}), "", "the first block takes only another line's boxes")
	_run(sim, 120.0)
	_expect(_stacked(sim, lines[1]).size(), 0, "none of this line's boxes is placed in it")
	_expect(_stacked(sim, lines[2]).size() > 10, true, "they go to the open block (%d)" % _stacked(sim, lines[2]).size())


func _test_a_box_no_block_takes_stays_aboard() -> void:
	var sim := AreaPort.base()
	sim.apply({"op": "set_area", "id": 3, "settings": {"sizes": [1]}})
	_run(sim, 120.0)
	var held := _stacked(sim, 3)
	_expect(held.size() > 5 and held.all(func(box: Dictionary) -> bool: return box.teu == 1), true, "the only block holds 20 ft boxes alone (%d)" % held.size())
	_expect(sim.vehicles.all(func(v: Vehicle) -> bool: return v.box == 0 or sim.boxes[v.box].teu == 1), true, "and no vehicle carries a 40 ft box")
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.begins_with("A box was shut out")), true, "the player is told boxes were shut out")


## Export lorries bring boxes of every size; a block for 40 ft boxes takes
## only those, and the rest are turned away at the gate.
func _test_export_lorries_respect_rules() -> void:
	var sim := AreaPort.base()
	var block := AreaPort.add_export_block(sim)
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"sizes": [2]}}), "", "the export block takes only 40 ft boxes")
	_run(sim, 180.0)
	var held := _stacked(sim, block)
	_expect(held.size() > 5 and held.all(func(box: Dictionary) -> bool: return box.teu == 2), true, "it holds only 40 ft exports (%d)" % held.size())


## The scripted scenario: boxes come in with departures in no order and
## leave soonest first. Stacked by departure, digging them out takes fewer
## re-handles than filling the lowest stack; both are counted.
func _test_by_departure_needs_fewer_rehandles() -> void:
	var counts := {}
	for strategy: String in ["fill_low", "by_departure"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 12
		var stacks := AreaStacks.new(12, 4)
		var boxes := {}
		for id in range(1, 37):
			boxes[id] = {"due": float(rng.randi_range(0, 1000))}
			stacks.place_at(stacks.place_spot(2, strategy, boxes[id].due, boxes), id, 2)
		var leaving := boxes.keys()
		leaving.sort_custom(func(a: int, b: int) -> bool: return boxes[a].due < boxes[b].due)
		for id: int in leaving:
			_expect(stacks.take(id) >= 0, true, "box %d is dug out" % id)
		counts[strategy] = stacks.rehandles
	_expect(counts.fill_low > 0, true, "filling low buries boxes (%d re-handles)" % counts.fill_low)
	_expect(counts.by_departure < counts.fill_low, true, "stacking by departure needs fewer re-handles (%d against %d)" % [counts.by_departure, counts.fill_low])
	var sim := AreaPort.base()
	_expect(sim.areas.list[3].settings.stacking, "fill_low", "a new block fills low")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"stacking": "sideways"}}) != "", true, "an unknown strategy is refused")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"stacking": "by_departure"}}), "", "a block is set to stack by departure")
	_run(sim, 300.0)
	_expect(sim.area_stacks[3].count() > 0 or sim.delivered > 0, true, "and works ships that way")
	_expect(PortSim.from_dict(sim.to_dict()).area_stacks[3].rehandles, sim.area_stacks[3].rehandles, "re-handles are counted in the save (%d)" % sim.area_stacks[3].rehandles)


## A template saved from one block, applied to another, copies its rules
## (not its role or gear), and is saved with the port.
func _test_templates_copy_rules() -> void:
	var port := _two_blocks(RandomPort.quick())
	var sim: PortSim = port[0]
	var ruled := {"sizes": [2], "reefers": false, "max_tiers": 3, "stacking": "by_departure", "lines": [sim.rules.lines.keys()[1]]}
	sim.apply({"op": "set_area", "id": port[1], "settings": ruled})
	_expect(sim.apply({"op": "save_template", "name": "", "id": port[1]}), "Name the template", "a template needs a name")
	_expect(sim.apply({"op": "save_template", "name": "forties", "id": 1}), "Templates are saved from a yard block", "and comes from a yard block")
	_expect(sim.apply({"op": "save_template", "name": "forties", "id": port[1]}), "", "a block's rules are saved as a template")
	_expect(sim.apply({"op": "apply_template", "name": "nothing", "id": port[2]}), "No template called nothing", "an unknown template is refused")
	sim.apply({"op": "set_area", "id": port[2], "settings": {"role": "export"}})
	_expect(sim.apply({"op": "apply_template", "name": "forties", "id": port[2]}), "", "the template is applied to the other block")
	for key: String in ruled:
		_expect(sim.areas.list[port[2]].settings[key], ruled[key], "it copies %s" % key)
	_expect(sim.areas.list[port[2]].settings.role, "export", "but keeps the block's own role")
	_expect(PortSim.from_dict(sim.to_dict()).templates, sim.templates, "templates are saved")


## A ship's imports go to the block a tractor gets them handled at soonest,
## not the first with room: with two import blocks of one machine each, both
## take boxes while the first still has room, and neither holds most of them.
func _test_discharge_spreads_over_blocks() -> void:
	var port := _two_blocks(RandomPort.quick())
	var sim: PortSim = port[0]
	var most_bound := 0
	for tick in roundi(90.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		most_bound = maxi(most_bound, sim.vehicles.filter(func(v: Vehicle) -> bool: return v.area == port[1]).size())
	var first := _stacked(sim, port[1]).size()
	var second := _stacked(sim, port[2]).size()
	_expect(AreaFlow._stacks(sim, port[1]).room() > 0, true, "the first block still has room")
	_expect(second > 0, true, "yet the second takes boxes too (%d and %d)" % [first, second])
	_expect(absi(first - second) <= maxi(first, second) / 2, true, "about evenly (%d and %d)" % [first, second])
