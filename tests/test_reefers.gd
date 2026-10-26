extends SceneTree
## M6 step 17: reefers plug into reefer blocks, draw power billed on the day's
## peak, and cost a fine when left unplugged.
## godot --headless --script res://tests/test_reefers.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_reefer_ship_sets_a_peak()
	_test_unplugged_reefers_are_fined()
	_test_reefer_exports_plug_in()
	_test_hot_days_draw_more()
	_test_reefers_wait_for_their_milestone()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## A ship of reefers is stacked in the reefer block, its plugs set the day's
## peak, and midnight bills the kWh and the peak.
func _test_reefer_ship_sets_a_peak() -> void:
	var sim := _reefer_port(true)
	_expect(_run_until(sim, func() -> bool: return AreaFlow.plugged_reefers(sim) == 40), true, "the ship's 40 reefers are plugged in the reefer block")
	_expect(AreaFlow.unplugged_reefers(sim), 0, "none are stacked off a plug")
	# The draw is read early in a tick, before that tick's stacking.
	sim.tick()
	_expect(sim.power.peak_kw, 40 * sim.rules.reefers.kw, "they set the day's peak")
	while sim.clock.ticks % SimClock.TICKS_PER_DAY != SimClock.TICKS_PER_DAY - 1:
		sim.tick()
	var bill := roundi(sim.power.kwh * sim.rules.reefers.price_per_kwh + sim.power.peak_kw * sim.rules.reefers.peak_charge_per_kw)
	_expect(bill > 0, true, "the day drew power ($%d)" % bill)
	sim.tick()
	_expect(sim.ledger.days[-1].lines.get("power", 0), -bill, "midnight bills the kWh and the peak")
	_expect(sim.power.peak_kw, AreaFlow.plugged_reefers(sim) * sim.rules.reefers.kw, "the new day's peak starts from what is plugged now")
	_expect(sim.ledger.days[-1].lines.get("reefer_fines", 0), 0, "plugged reefers cost no fines")


## With no reefer block, reefers stack in the import block, and each is fined
## once after plug_minutes.
func _test_unplugged_reefers_are_fined() -> void:
	var sim := _reefer_port(false)
	_expect(_run_until(sim, func() -> bool: return AreaFlow.unplugged_reefers(sim) == 40), true, "the ship's 40 reefers stack in the import block")
	_expect(sim.power.peak_kw, 0.0, "unplugged reefers draw nothing")
	for i in roundi((sim.rules.reefers.plug_minutes + 60.0) / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(AreaFlow.unplugged_reefers(sim), 40, "they are still stacked")
	_expect(sim.ledger.today.get("reefer_fines", 0), -40 * sim.rules.reefers.fine, "each is fined past plug_minutes")
	for i in roundi(180.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(sim.ledger.today.get("reefer_fines", 0), -40 * sim.rules.reefers.fine, "and only once")


## Reefer exports from the gate go to the reefer block, not the export block.
func _test_reefer_exports_plug_in() -> void:
	var sim := _reefer_port(true, 0, 10)
	_expect(_run_until(sim, func() -> bool: return AreaFlow.plugged_reefers(sim) > 0), true, "a reefer export is stacked on a plug")
	_expect(AreaFlow.unplugged_reefers(sim), 0, "and none in the export block")


## A new port gets no reefers before the terminal milestone, so it is never
## fined for plugs it can't build yet; past it, reefers come.
func _test_reefers_wait_for_their_milestone() -> void:
	var rules := Content.base()
	rules.box_mix.reefer_share = 1.0
	var sim := PortSim.new(1, rules)
	var before := sim._new_box("import", 0.0, rules.lines.keys()[0])
	_expect(sim.boxes[before].reefer, false, "no reefer before the terminal milestone")
	sim.teu_handled = int(rules.milestones.terminal.teu)
	var after := sim._new_box("import", 0.0, rules.lines.keys()[0])
	_expect(sim.boxes[after].reefer, true, "reefers once it is reached")


func _test_hot_days_draw_more() -> void:
	var sim := PortSim.new(1)
	_expect(sim.reefer_kw(), sim.rules.reefers.kw, "an ordinary day draws kw a plug")
	sim.clock.ticks = sim.rules.reefers.hot_from * SimClock.TICKS_PER_DAY
	_expect(sim.reefer_kw(), sim.rules.reefers.hot_kw, "a hot day draws hot_kw a plug")
	sim.clock.ticks = (sim.rules.reefers.hot_to + 1) * SimClock.TICKS_PER_DAY
	_expect(sim.reefer_kw(), sim.rules.reefers.kw, "the hot days end")


## A working terminal whose feeder brings `imports` reefers and wants
## `exports`, with a reefer block when `plugs`.
func _reefer_port(plugs: bool, imports := 40, exports := 0) -> PortSim:
	# Every milestone reached, so reefers are unlocked.
	var rules := RandomPort.quick()
	rules.box_mix.reefer_share = 1.0
	var sim := AreaPort.working_terminal(imports, exports, rules)
	if plugs:
		var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
		_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 92 if exports else 61, "to": 121 if exports else 90}), "", "the reefer block is built")
		var id: int = sim.areas.list.keys()[-1]
		_expect(sim.apply({"op": "set_area", "id": id, "settings": {"role": "reefer"}}), "", "it is set to reefers")
		_expect(sim.apply({"op": "set_terminal", "id": id, "terminal": 1}), "", "it joins the terminal")
	return sim


## Ticks `sim` until `done`, for at most a day.
func _run_until(sim: PortSim, done: Callable) -> bool:
	for i in SimClock.TICKS_PER_DAY:
		sim.tick()
		if done.call():
			return true
	return false


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
