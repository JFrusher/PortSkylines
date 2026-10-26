extends SceneTree
## Headless tests for the game's rules on roads and areas: ship calls, cranes,
## the yard's pace, dwell and the gate, upkeep, contracts, money, land,
## dredging, milestones, the year's scoreboard and the inspect tool.
## godot --headless --script res://tests/test_rules.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")
## When the first test ship calls; see RandomPort.calls.
const FIRST_SHIP := 10

var _failures := 0


func _initialize() -> void:
	_test_no_ship_without_a_terminal()
	_test_ships_unload_and_lorries_pay()
	_test_commands()
	_test_round_trip()
	_test_ships_fit_their_berth()
	_test_crane_timing()
	_test_outreach()
	_test_yard_machines_set_the_pace()
	_test_changing_gear_replaces_machines()
	_test_import_dwell()
	_test_gate()
	_test_upkeep_at_midnight()
	_test_events_do_not_repeat()
	_test_ships_never_overlap()
	_test_only_the_ledger_moves_cash()
	_test_a_service_calls_on_its_slot()
	_test_offers_accept_and_decline()
	_test_services_spread_across_the_week()
	_test_reputation_cancels_and_recovers()
	_test_storage_is_charged_per_day()
	_test_a_call_earns_its_moves()
	_test_service_windows_overlap_across_the_week()
	_test_loans_are_paid_back_with_interest()
	_test_bailout_fires_once()
	_test_saved_reputation_meets_a_new_line()
	_test_creative_mode_builds_without_cash()
	_test_land_must_be_bought()
	_test_cranes_arrive_after_their_lead_time()
	_test_dredging()
	_test_milestones_unlock_content()
	_test_year_end_scoreboard()
	_test_inspect_each_entity()
	_test_removing_areas_in_use()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _run(sim: PortSim, minutes: float) -> void:
	for i in roundi(minutes / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()


func _test_no_ship_without_a_terminal() -> void:
	var sim := AreaPort.base()
	sim.apply({"op": "set_terminal", "id": 2, "terminal": 0})
	_run(sim, FIRST_SHIP + 1)
	_expect(sim.ships.size(), 0, "no ship calls at an apron whose terminal has no gate")
	_expect(sim.last_event().contains("in a terminal with a gate"), true, "and the status says why (%s)" % sim.last_event())


func _test_ships_unload_and_lorries_pay() -> void:
	var rules := RandomPort.quick()
	rules.import_dwell_minutes = 0.0
	var sim := AreaPort.base(rules)
	_run(sim, FIRST_SHIP + 1)
	_expect(sim.ships.size(), 1, "a ship calls at the apron")
	var cargo := sim.ships[0].boxes
	_run(sim, 600)
	_expect(sim.delivered >= cargo, true, "the first ship's %d boxes are all delivered (%d)" % [cargo, sim.delivered])
	_expect(sim.ledger.today.get("moves", 0) > 0 or sim.ledger.days.any(func(d: Dictionary) -> bool: return d.lines.get("moves", 0) > 0), true, "the line pays for the moves")


func _test_commands() -> void:
	var sim := PortSim.new()
	_expect(sim.apply({"op": "build_road", "from": Vector2i(150, 300), "to": Vector2i(160, 300), "type": "terminal_1_1"}), "", "a build command")
	_expect(sim.roads.segments.size(), 1, "builds")
	_expect(sim.apply({"op": "fly"}), "Unknown command: fly", "unknown command is refused")


func _test_round_trip() -> void:
	var straight := AreaPort.base()
	var halves := AreaPort.base()
	_run(straight, 50)
	_run(halves, 25)
	var copy := PortSim.from_dict(halves.to_dict())
	_expect(copy.state_hash(), halves.state_hash(), "to_dict -> from_dict keeps the state")
	_run(copy, 25)
	_expect(copy.ships.is_empty() and copy.vehicles.is_empty(), false, "the round trip happened mid-traffic")
	_expect(copy.state_hash(), straight.state_hash(), "a round trip mid-run changes nothing")


func _test_ships_fit_their_berth() -> void:
	var rules := RandomPort.quick()
	var short := AreaPort.terminal(60, rules)
	short.creative = false
	RandomPort.calls(short, "panamax")
	_run(short, FIRST_SHIP + 1)
	_expect(short.ships.size(), 0, "a panamax does not call at a 240 m apron")
	_expect(short.last_event().contains("no quay apron of 300 m"), true, "the status says how long a quay it needs (%s)" % short.last_event())
	rules.channel.start_depth = 11.0
	var shallow := AreaPort.base(rules, "panamax")
	_run(shallow, FIRST_SHIP + 1)
	_expect(shallow.last_event().contains("needs 13 m of channel"), true, "a panamax does not call at 11 m of water (%s)" % shallow.last_event())


## A Panamax of 120 moves with 3 cranes at 25 moves an hour takes
## 120 / (3 x 25 x 0.9) hours at berth, within 5%, with a yard that never
## holds the cranes up.
func _test_crane_timing() -> void:
	var rules := RandomPort.quick()
	rules.ship_classes.panamax.import_moves = 120
	rules.ship_classes.panamax.export_moves = 0
	rules.yard_gear.reach_stacker.bays_per_machine = 1
	rules.yard_gear.reach_stacker.lift_seconds = 1.0
	rules.yard_gear.reach_stacker.set_down_seconds = 1.0
	var sim := AreaPort.base(rules, "panamax")
	sim.creative = true
	sim.apply({"op": "place_sts", "kind": "sts", "apron": 1, "along": 60})
	sim.apply({"op": "buy_tractors", "count": 24})
	_run(sim, FIRST_SHIP + 1)
	var first := sim.ships[0]
	var working_ticks := 0
	for i in roundi(240 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if first.state == PortSim.Ship.State.WORKING:
			working_ticks += 1
	var minutes := working_ticks * SimClock.CALENDAR_MINUTES_PER_TICK
	var expected := 120.0 / (3 * 25 * 0.9) * 60
	_expect(AreaFlow.cranes_for(sim, first).size(), 3, "three cranes along the ship")
	_expect(absf(minutes - expected) <= expected * 0.05, true, "3 cranes work 120 moves in %.1f min (expected %.1f)" % [minutes, expected])
	var k := sim.kpis()
	_expect(absf(k.crane_moves_per_hour - 25 * 0.9) < 25 * 0.9 * 0.05, true, "the crane-rate KPI reads 22.5 moves an hour (%.1f)" % k.crane_moves_per_hour)
	_expect(absf(k.berth_moves_per_hour - 3 * 25 * 0.9) < 3 * 25 * 0.9 * 0.05, true, "the berth KPI reads 67.5 moves an hour (%.1f)" % k.berth_moves_per_hour)


func _test_outreach() -> void:
	var rules := RandomPort.quick()
	rules.sts_cranes.sts.outreach = 8
	var sim := AreaPort.base(rules, "panamax")
	_run(sim, FIRST_SHIP + 30)
	_expect(sim.ships.size() == 1 and sim.ships[0].boxes == rules.ship_classes.panamax.import_moves, true, "a panamax gets no moves from cranes that are too short")
	_expect(sim.last_event().contains("reaches 13 rows"), true, "the status says why (%s)" % sim.last_event())
	_expect(sim.events[-1].get("at"), sim.areas.list[1].start, "and links to the ship's apron")


## One machine per bay against one per two bays, with lifts slow enough that
## the yard, not the cranes, sets the pace: half the machines take about
## twice as long to stack the ship.
func _test_yard_machines_set_the_pace() -> void:
	var minutes: Array[float] = []
	for per_machine: int in [5, 10]:
		var rules := RandomPort.quick()
		rules.yard_gear.reach_stacker.bays_per_machine = per_machine
		rules.yard_gear.reach_stacker.lift_seconds = 600.0
		rules.lorry_interval_minutes = 1e9  # no lorries competing for the machines
		var sim := AreaPort.base(rules, "panamax")
		sim.creative = true
		sim.apply({"op": "buy_tractors", "count": 20})
		_run(sim, FIRST_SHIP + 1)
		var import_moves: int = rules.ship_classes.panamax.import_moves
		var ticks := 0
		while _stacked(sim) < import_moves and ticks < 300000:
			sim.tick()
			ticks += 1
		minutes.append(ticks * SimClock.CALENDAR_MINUTES_PER_TICK)
	_expect(absf(minutes[1] / minutes[0] - 2.0) < 0.25, true, "half the machines take twice as long to stack the ship (%.0f vs %.0f min)" % [minutes[1], minutes[0]])


## A block switched to RTGs in use gets RTGs in place of its reach stackers,
## once each has finished the box it is handling, and stacks RTG high.
func _test_changing_gear_replaces_machines() -> void:
	var sim := AreaPort.base()
	_run(sim, FIRST_SHIP + 30)
	var gears := func() -> Array: return sim.machines.list.values().filter(func(m: Dictionary) -> bool: return m.area == 3).map(func(m: Dictionary) -> String: return m.gear)
	_expect(_stacked(sim) > 0 and gears.call().has("reach_stacker"), true, "the block works with reach stackers")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"gear": "rtg"}}), "", "switch it to RTGs")
	_run(sim, 10)
	var count := sim.machines.count_for("rtg", sim.areas.layout(3).slots.size())
	_expect(gears.call(), range(count).map(func(_i: int) -> String: return "rtg"), "its machines are RTGs now")
	_expect(sim.area_stacks[3].to_dict().tiers, sim.rules.yard_gear.rtg.tiers, "and its stacks go RTG high")


func _stacked(sim: PortSim) -> int:
	return sim.area_stacks.values().reduce(func(n: int, stacks: AreaStacks) -> int: return n + stacks.boxes().size(), 0)


func _test_import_dwell() -> void:
	var rules := RandomPort.quick()
	rules.import_dwell_minutes = 60.0
	var sim := AreaPort.base(rules)
	sim.set_storage(0, 0)  # free storage, so shippers take the whole dwell
	# Dwell runs from the crane's lift, as on tiles.
	var first_lifted := -1.0
	var first_pickup := -1.0
	for i in roundi(240 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if first_lifted < 0 and not sim.boxes.is_empty():
			first_lifted = sim.clock.calendar_minutes()
		if first_pickup < 0 and sim.vehicles.any(func(v: Vehicle) -> bool: return v.kind == "lorry"):
			first_pickup = sim.clock.calendar_minutes()
	_expect(first_lifted > 0 and first_pickup > 0, true, "imports were lifted and collected")
	_expect(first_pickup - first_lifted >= 60.0, true, "no lorry comes before the hour's dwell (lifted %.1f, first lorry %.1f)" % [first_lifted, first_pickup])


func _test_gate() -> void:
	var rules := RandomPort.quick()
	rules.import_dwell_minutes = 0.0
	var gateless := AreaPort.base(rules, "")
	gateless.apply({"op": "remove_area", "id": 2})
	var box := gateless._new_box("import", 0.0, "")
	AreaFlow._stacks(gateless, 3).place(box, gateless.boxes[box].teu)
	_run(gateless, 5)
	_expect(gateless.vehicles.is_empty(), true, "no lorry comes in without a gate")
	_expect(gateless.last_event().contains("build a gate"), true, "the status says so (%s)" % gateless.last_event())
	var sim := AreaPort.base(rules)
	_run(sim, FIRST_SHIP + 240)
	_expect(sim.turn_times.size() > 5, true, "lorries record turn times (%d)" % sim.turn_times.size())
	_expect(sim.turn_times.all(func(t: float) -> bool: return t >= 2 * rules.gate_levels.manual.minutes), true, "every turn includes a stop at the gate each way")


func _test_upkeep_at_midnight() -> void:
	var rules := RandomPort.quick()
	var sim := AreaPort.base(rules, "")
	sim.tick()  # the yard block's machines are fitted on the first tick
	var cells := 0.0
	for segment: int in sim.roads.segments:
		var road: Dictionary = sim.roads.segments[segment]
		cells += RoadNet.length(sim.roads.nodes[road.a], sim.roads.nodes[road.b]) * rules.road_types[road.type].upkeep_per_cell
	for id: int in sim.areas.list:
		cells += sim.areas.cells(id).size() * rules.area_types[sim.areas.list[id].type].upkeep_per_cell
	var expected := roundi(cells)
	expected += rules.upkeep.sts_crane * 2 + rules.upkeep.tractor * 6 + rules.land.upkeep * sim.land.size()
	expected += rules.yard_gear.reach_stacker.upkeep_per_machine * sim.machines.list.size()
	_expect(sim.daily_upkeep(), expected, "upkeep adds every road and area cell, crane, tractor, yard machine and land tile")
	var upkeep := sim.daily_upkeep()
	for i in SimClock.TICKS_PER_DAY - 2:
		sim.tick()
	var before := sim.money
	sim.tick()
	_expect([before - sim.money, -sim.ledger.days[-1].lines.upkeep], [upkeep, upkeep], "upkeep is charged exactly at midnight")
	_expect(sim.last_event().begins_with("Upkeep"), true, "and reported (%s)" % sim.last_event())


func _test_events_do_not_repeat() -> void:
	var sim := PortSim.new()
	var before := sim.events.size()
	sim._event("A crane is waiting for a free tractor")
	sim._event("A crane is waiting for a free tractor")
	_expect(sim.events.size(), before + 1, "a message repeated tick after tick is kept once")


func _test_ships_never_overlap() -> void:
	var sim := AreaPort.base(RandomPort.quick(), "")
	var line: String = sim.rules.lines.keys()[0]
	var first := PortSim.Ship.new("feeder", line, 0.0, 1, 0)
	var second := PortSim.Ship.new("feeder", line, 0.0, 1, 0)
	sim.ships.append_array([first, second])
	_expect(AreaFlow.berth(sim, first), true, "the first feeder berths")
	_expect(AreaFlow.berth(sim, second), false, "an 80-cell apron has no room for a second 50-cell feeder")


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
	var sim := AreaPort.base(RandomPort.quick(), "")
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
	var rules := RandomPort.quick()
	rules.contracts.offer_chance = 1.0
	var sim := AreaPort.base(rules, "")
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


## Services agreed one after another call on different days: each new offer
## takes the hour of the week furthest from the calls already agreed or offered.
func _test_services_spread_across_the_week() -> void:
	var rules := Content.base().duplicate(true)
	rules.contracts.offer_chance = 1.0
	rules.contracts.max_offers = 1
	var contracts := Contracts.new(rules)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	while contracts.services.size() < 4:
		var offer := contracts.offer(rng, 8 * 60.0, 10, func(_kind: String) -> bool: return true, 1.0)
		if not offer.is_empty():
			contracts.accept(offer.id)
	var hours: Array = contracts.services.map(func(s: Dictionary) -> int: return s.start / 60)
	var closest := 7 * 24
	for a: int in hours:
		for b: int in hours:
			if a != b:
				closest = mini(closest, mini(absi(a - b), 7 * 24 - absi(a - b)))
	_expect(closest >= 36, true, "four services agreed on one morning call at least 36 h apart (hours of the week %s)" % [hours])


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
		var offer := contracts.offer(rng, 0.0, 100, func(_kind: String) -> bool: return true, 1.0)
		if not offer.is_empty():
			offered[offer.line] = true
			contracts.offers.clear()
	_expect(offered.has("kestrel"), true, "good calls win the line back to offering services")


## Boxes pay the fee for each midnight they spend in the yard past their free days.
func _test_storage_is_charged_per_day() -> void:
	var sim := AreaPort.base(RandomPort.quick(), "")
	_expect(sim.apply({"op": "set_storage", "free_days": 1, "fee": 30}), "", "set storage terms")
	_expect(sim.apply({"op": "set_storage", "free_days": 4, "fee": 30}), "Free days run from 0 to 3", "free days are capped")
	for i in 2:
		var box := sim._new_box("export", 0.0, "")
		AreaFlow._stacks(sim, 3).place(box, sim.boxes[box].teu)
		sim.boxes[box].in = 0.0
	_run(sim, 3 * SimClock.MINUTES_PER_DAY)
	# Stacked at minute 0: the first midnight is within the free day.
	var storage: Array = sim.ledger.days.map(func(day: Dictionary) -> int: return day.lines.get("storage", 0))
	_expect(storage, [0, 60, 60], "2 boxes x $30 for each day past the free one")


## A call of 40 ft boxes earns 1.8 x the 20 ft price per move.
func _test_a_call_earns_its_moves() -> void:
	var rules := RandomPort.quick()
	rules.box_mix = {"forty_share": 1.0, "reefer_share": 0.0, "rush_share": 0.0, "dg_share": 0.0}
	var sim := AreaPort.base(rules)
	var ship: PortSim.Ship
	while ship == null or ship.state != PortSim.Ship.State.LEAVING:
		sim.tick()
		if ship == null and not sim.ships.is_empty():
			ship = sim.ships[0]
	_expect(sim.ledger.today.moves, ship.moves * roundi(rules.move_price.per_20ft * 1.8), "%d moves at $180" % ship.moves)
	var service: Dictionary = sim.contracts.services[0]
	_expect(sim.contracts.call_value(service), service.moves * 180, "a call is worth its moves at $180")


## A Sunday 22:00 call with a 12 h window runs to Monday 10:00.
func _test_service_windows_overlap_across_the_week() -> void:
	var contracts := Contracts.new(RandomPort.quick())
	var sunday := {"id": 1, "start": 6 * 1440 + 22 * 60, "window_hours": 12.0}
	contracts.services.assign([sunday])
	_expect(contracts.overlaps({"id": 2, "start": 8 * 60, "window_hours": 4.0}), [sunday], "Monday 08:00 overlaps it")
	_expect(contracts.overlaps({"id": 3, "start": 10 * 60, "window_hours": 4.0}), [], "Monday 10:00 does not")
	_expect(contracts.overlaps({"id": 4, "start": 6 * 1440 + 20 * 60, "window_hours": 3.0}), [sunday], "Sunday 20:00 for 3 h runs into it")
	_expect(contracts.overlaps(sunday), [], "a service does not overlap itself")


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
		_expect(sim.apply({"op": "build_road", "from": Vector2i(150, 300), "to": Vector2i(160, 300), "type": "terminal_1_1"}), "" if creative else "Not enough money", "building at $0 in %s mode" % ("creative" if creative else "normal"))
	var copy := PortSim.from_dict(PortSim.new(0, Content.base(), true).to_dict())
	_expect(copy.creative, true, "creative mode survives a save")


## The port starts owning the middle third of the site; roads and areas
## elsewhere wait until it buys the land, which then costs upkeep.
func _test_land_must_be_bought() -> void:
	var sim := PortSim.new(0, RandomPort.quick())
	sim.ledger.cash = 100000
	var north := {"op": "build_road", "from": Vector2i(150, 100), "to": Vector2i(170, 100), "type": "terminal_1_1"}
	_expect(sim.apply(north), "Buy this land first", "no road outside the port's land")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(150, 205), "to": Vector2i(170, 205), "type": "terminal_1_1"}), "", "a road on the port's land")
	var refused: Array = [1, -1].map(func(side: int) -> String: return sim.build_area_error("yard_block", 1, side, 0, 15))
	_expect(refused.has("Buy this land first") and refused.has(""), true, "an area reaching off the port's land is refused, the other side of the road is not (%s)" % [refused])
	var before := sim.money
	var upkeep := sim.daily_upkeep()
	_expect(sim.apply({"op": "buy_land", "tile": sim.land_tile(Vector2i(150, 100))}), "", "buy the land tile north of the start")
	_expect([before - sim.money, sim.daily_upkeep() - upkeep], [sim.rules.land.price, sim.rules.land.upkeep], "land costs its price, then upkeep every day")
	_expect(sim.apply(north), "", "and can be built on")
	_expect(sim.buy_land(sim.land_tile(Vector2i(150, 100))), "The port owns this land already", "land is bought once")
	_expect(sim.buy_land(Vector2i(3, 0)), "Off the site", "only the site's tiles are for sale")
	_expect(sim.buy_land(sim.land_tile(Grid.NONE)), "Off the site", "a click off the site buys nothing")


## An STS crane ordered now stands on its apron exactly when its lead time ends.
func _test_cranes_arrive_after_their_lead_time() -> void:
	var rules := Content.base().duplicate(true)
	rules.sts_cranes.sts.lead_days = 0.5
	var sim := AreaPort.terminal(60, rules)
	sim.creative = false
	sim.ledger.cash = rules.start_money
	var before := sim.money
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": 1, "along": 20}), "", "order a crane")
	_expect([sim.cranes.size(), before - sim.money], [0, rules.sts_cranes.sts.cost], "paid now, not there yet")
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": 1, "along": 20}), "Too close to another crane", "one order per place on the rails")
	var due := roundi(720 / SimClock.CALENDAR_MINUTES_PER_TICK)
	for i in due - 1:
		sim.tick()
	_expect(sim.cranes.size(), 0, "not there a tick early")
	sim.tick()
	_expect(sim.cranes.size(), 1, "there exactly 12 hours after the order")


func _test_dredging() -> void:
	var base := RandomPort.quick()
	base.channel.maintenance_days = 1
	base.channel.start_depth = Content.base().channel.start_depth
	var sim := AreaPort.base(base, "")
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
	var sim := AreaPort.base(Content.base(), "")
	sim.ledger.cash = 1000000
	var terminal: Dictionary = sim.milestones()[1]
	var gateway: Dictionary = sim.milestones()[2]
	_expect(sim.milestones_reached(), 1, "the first milestone is reached at the start")
	for name: String in ["rtg", "loans", "land", "dredging", "panamax"]:
		_expect(sim.unlocked(name), false, "%s starts locked" % name)
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"gear": "rtg"}}), "Unlocked at milestone 2: %d TEU across the quay" % terminal.teu, "RTGs wait for milestone 2")
	_expect(sim.apply({"op": "take_loan", "kind": "small"}).begins_with("Unlocked at milestone 2"), true, "so do loans")
	_expect(sim.apply({"op": "dredge", "metres": 1}).begins_with("Unlocked at milestone 3"), true, "dredging waits for milestone 3")
	var box := {"teu": 2, "reefer": false}
	while sim.teu_handled < terminal.teu - 2:
		sim._moved(box)
	_expect(sim.unlocked("rtg"), false, "still locked 2 TEU short")
	sim._moved(box)
	_expect(sim.last_event().begins_with("Milestone 2"), true, "crossing it is announced (%s)" % sim.last_event())
	_expect([sim.apply({"op": "set_area", "id": 3, "settings": {"gear": "rtg"}}), sim.apply({"op": "take_loan", "kind": "small"})], ["", ""], "RTGs and loans are unlocked")
	_expect(sim.unlocked("land"), false, "land waits for milestone 3")
	while sim.teu_handled < gateway.teu:
		sim._moved(box)
	_expect(["land", "dredging", "panamax"].all(sim.unlocked), true, "milestone 3 unlocks land, dredging and Panamax services")
	var rules := RandomPort.quick()
	rules.contracts.offer_chance = 1.0
	rules.contracts.max_offers = 100
	var offering := AreaPort.base(rules, "")
	# The quick rules reach every milestone; put the real ones back.
	offering.rules.milestones = Content.base().milestones.duplicate(true)
	_run(offering, 40 * 60)
	_expect(offering.contracts.offers.size() >= 10, true, "lines made offers (%d)" % offering.contracts.offers.size())
	_expect(offering.contracts.offers.any(func(o: Dictionary) -> bool: return o.kind == "panamax"), false, "no Panamax is offered before milestone 3")


## Each game year closes with port hours per call, moves an hour and gate
## turn, computed from that year's calls.
func _test_year_end_scoreboard() -> void:
	var rules := RandomPort.quick()
	rules.year_days = 1
	rules.import_dwell_minutes = 30.0
	var sim := AreaPort.base(rules)
	# Each call as it sails, from the ship itself.
	var sailed: Array[Dictionary] = []
	var seen := {}
	for i in SimClock.TICKS_PER_DAY:
		sim.tick()
		for ship in sim.ships:
			if ship.state == PortSim.Ship.State.LEAVING and ship not in seen:
				seen[ship] = true
				sailed.append({"hours": (sim.clock.calendar_minutes() - ship.berthed) / 60.0, "moves": ship.moves})
	var hours := 0.0
	var moves := 0
	for call in sailed:
		hours += call.hours
		moves += call.moves
	_expect(sim.scoreboard.size(), 1, "the year closed at midnight")
	var closed: Dictionary = sim.scoreboard[0]
	_expect(sailed.size() > 3, true, "calls sailed in the year (%d)" % sailed.size())
	_expect(absf(closed.port_hours - hours / sailed.size()) < 1e-6 and absf(closed.moves_per_hour - moves / hours) < 1e-6, true, "the scoreboard matches the year's calls (%s)" % closed)
	_expect(closed.turn_minutes > 2 * rules.gate_levels.manual.minutes, true, "and reports the gate turn")
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.begins_with("Year 1: ")), true, "the year is reported")


func _test_inspect_each_entity() -> void:
	var sim := AreaPort.base()
	while sim.vehicles.is_empty():
		sim.tick()
	var ship := sim.ships[0]
	var crane := sim.cranes[0]
	var vehicle := sim.vehicles[0]
	var apron: Dictionary = sim.areas.list[1]
	var along: Vector2i = (apron.end - apron.start).sign()
	var water: Vector2i = apron.start + along * (ship.from + 5) + apron.out * (sim.rules.area_types.quay_apron.depth + 2)
	_expect(Inspect.pick(sim, water), ship, "a click on the water beside an apron picks its ship")
	_expect(Inspect.describe(sim, ship)[0], "%s feeder" % sim.contracts.name_of(ship.line), "a ship is named by line and class")
	_expect(Inspect.pick(sim, apron.start + along * crane.along + apron.out * 4), crane, "a click between a crane's rails picks the crane")
	_expect(Inspect.describe(sim, crane)[0], "STS crane", "a crane is named")
	_expect(Inspect.pick(sim, Vector2i(vehicle.position(1.0).round())), vehicle, "a click on a vehicle picks it")
	_expect(Inspect.describe(sim, vehicle)[0], "Tractor %d" % vehicle.id, "a vehicle is named by kind and id")
	_expect(Inspect.describe(sim, {"area": 3}).slice(0, 3), ["Yard block", "Terminal 1", "Import block, worked by reach stackers"] as Array[String], "a yard block shows its rules")
	sim.vehicles.erase(vehicle)
	# Held in a typed array, as the HUD holds it: an untyped [] fails there.
	var shown: Array[String] = Inspect.describe(sim, vehicle)
	_expect(shown, [] as Array[String], "a vehicle that left shows nothing")


## Bulldozing areas in use, as in Cities: Skylines: an apron's ship sails and
## its cranes come down; a block's boxes are lost and its vehicles scrapped.
func _test_removing_areas_in_use() -> void:
	var sim := AreaPort.base()
	_run(sim, FIRST_SHIP + 20)
	var ship := sim.ships[0]
	_expect(_stacked(sim) > 0 and not sim.vehicles.is_empty(), true, "boxes are stacked and tractors busy")
	var boxes := sim.boxes.size()
	var lost := _stacked(sim) + sim.vehicles.filter(func(v: Vehicle) -> bool: return v.area == 3 and v.loaded).size()
	_expect(sim.apply({"op": "remove_area", "id": 3}), "", "the yard block is removed in use")
	_expect([sim.boxes.size(), sim.vehicles.any(func(v: Vehicle) -> bool: return v.area == 3)], [boxes - lost, false], "its boxes are lost and its vehicles scrapped")
	_expect(sim.last_event().begins_with("Removing the area lost"), true, "and the status says so (%s)" % sim.last_event())
	_expect(sim.apply({"op": "remove_area", "id": 1}), "", "the apron is removed with a ship alongside")
	_expect([ship in sim.ships, sim.ship_log[-1].moves, sim.cranes.size()], [false, ship.moves, 0], "the ship sails at once with its call logged, and the cranes come down")
	for i in 200:
		sim.tick()
	_expect(sim.machines.list.is_empty(), true, "the block's machines go")
