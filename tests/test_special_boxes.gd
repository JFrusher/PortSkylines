extends SceneTree
## M6 notes: rush boxes fine the port when their call is late, and dangerous
## goods stack only in dangerous-goods blocks, kept apart from other blocks.
## godot --headless --script res://tests/test_special_boxes.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_late_rush_boxes_are_fined()
	_test_dangerous_goods_need_their_block()
	_test_dangerous_blocks_stand_apart()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## Rush boxes discharged after their ship's window closed each cost a fine;
## on time they cost nothing.
func _test_late_rush_boxes_are_fined() -> void:
	for late: bool in [false, true]:
		var sim := AreaPort.working_terminal(20, 0, _rules({"rush_share": 1.0}))
		var ship: PortSim.Ship = sim.ships[0]
		if late:
			ship.due = sim.clock.calendar_minutes() - 1.0
		_run_until(sim, func() -> bool: return ship.boxes == 0)
		_expect(ship.boxes, 0, "the ship is discharged")
		var want: int = -20 * sim.rules.special_boxes.rush_fine if late else 0
		_expect(sim.ledger.today.get("rush_fines", 0), want, "a %s call's rush boxes cost %d" % ["late" if late else "timely", -want])


## With no dangerous-goods block, dangerous imports are shut out, never
## stacked; with one, they all stack there.
func _test_dangerous_goods_need_their_block() -> void:
	for has_block: bool in [false, true]:
		var sim := AreaPort.working_terminal(20, 0, _rules({"dg_share": 1.0}))
		var ship: PortSim.Ship = sim.ships[0]
		var dg := 0
		if has_block:
			dg = _block(sim, 70)
			_expect(sim.apply({"op": "set_area", "id": dg, "settings": {"role": "dangerous"}}), "", "a block far enough off takes dangerous goods")
		var stacked_elsewhere := 0
		for i in SimClock.TICKS_PER_DAY / 4:
			sim.tick()
			for id: int in sim.area_stacks:
				if id != dg:
					stacked_elsewhere += sim.area_stacks[id].count()
		_expect(ship.boxes, 0, "the ship is discharged either way")
		_expect(stacked_elsewhere, 0, "no dangerous box ever stacks in a block that refuses it")
		_expect(sim.area_stacks[dg].count() if has_block else 0, 20 if has_block else 0, "the dangerous-goods block takes them all" if has_block else "they are shut out")


## A dangerous-goods block keeps the data's distance from every other yard block.
func _test_dangerous_blocks_stand_apart() -> void:
	var sim := AreaPort.working_terminal(0, 0, _rules({}))
	var near := _block(sim, 61)
	var gap: int = sim.rules.special_boxes.dg_distance
	var refusal := "A dangerous-goods block stands %d m from other yard blocks" % Grid.metres(gap)
	_expect(sim.apply({"op": "set_area", "id": near, "settings": {"role": "dangerous"}}), refusal, "a block beside another can't take dangerous goods")
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	var far := _block(sim, 61 + 30 + gap + 1)
	_expect(sim.apply({"op": "set_area", "id": far, "settings": {"role": "dangerous"}}), "", "one %d cells clear can" % gap)
	_expect(sim.build_area_error("yard_block", east, 1, 61 + 30 + gap + 1 + 30, 61 + 30 + gap + 1 + 30 + 9), refusal, "and no yard block is built close to it")


## A 30-cell yard block south of the east road from `from`, in terminal 1.
func _block(sim: PortSim, from: int) -> int:
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	sim.creative = true
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": from, "to": from + 29}), "", "a block at %d is built" % from)
	var id: int = sim.areas.list.keys()[-1]
	return id


## Base rules with only the given special-box shares, no reefers.
func _rules(mix: Dictionary) -> Dictionary:
	var rules := Content.base()
	rules.box_mix.reefer_share = 0.0
	rules.box_mix.rush_share = 0.0
	rules.box_mix.dg_share = 0.0
	rules.box_mix.merge(mix, true)
	return rules


func _run_until(sim: PortSim, done: Callable) -> void:
	for i in SimClock.TICKS_PER_DAY:
		sim.tick()
		if done.call():
			return


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
