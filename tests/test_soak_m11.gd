extends SceneTree
## M11's systems together: a game day of the base port with tides, storms,
## breakdowns and fires all on, a workshop and a fire station manned, a gate
## scanner with customs flagging, shore power, the town's fund, bypass and a
## tree belt, and the morning paper; the sim's invariants (tests/invariants.gd)
## checked as it runs, and the paper filed for the day.
## godot --headless --script res://tests/test_soak_m11.gd

const AreaPort := preload("res://tests/area_port.gd")
const Invariants := preload("res://tests/invariants.gd")
const DEEP_EVERY := 20

var _failures := 0


func _initialize() -> void:
	var sim := AreaPort.base()
	for line: String in sim.rules.lines:
		sim.rules.lines[line].customs_share = 0.3
	# Money for it all, bought for real so the books add up.
	# The base port was built for free, its lines in today's books with no
	# cash spent, so the day opens where those lines leave it.
	sim.ledger.cash = 100000000
	sim.ledger.opened = sim.ledger.cash - sim.ledger.today_total()
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	var gate := 0
	for id: int in sim.areas.list:
		if sim.areas.kind_of(sim.areas.list[id]) == "gate":
			gate = id
	for command: Dictionary in [
		{"op": "set_event_kind", "kind": "tides", "on": true},
		{"op": "set_event_kind", "kind": "breakdowns", "on": true},
		{"op": "set_event_kind", "kind": "fires", "on": true},
		{"op": "build_area", "type": "workshop", "segment": east, "side": 1, "from": 62, "to": 70},
		{"op": "hire_mechanics", "area": 4, "count": 2},
		{"op": "build_area", "type": "fire_station", "segment": east, "side": 1, "from": 72, "to": 80},
		{"op": "buy_engines", "area": 5, "count": 1},
		{"op": "build_area", "type": "tree_belt", "segment": east, "side": -1, "from": 330, "to": 345},
		{"op": "buy_scanner", "gate": gate},
		{"op": "buy_shore_power", "area": 1},
		{"op": "buy_bypass"},
		{"op": "set_town_fund", "per_day": 500},
	]:
		_expect(sim.apply(command), "", "%s is done" % command.op)
	while sim.clock.ticks < SimClock.TICKS_PER_DAY + 1000 and _failures == 0:
		sim.tick()
		Invariants.check(sim, _expect, DEEP_EVERY)
	if _failures:
		print("tests: %d failure(s)" % _failures)
		quit(1)
		return
	_expect(sim.reports.size(), 1, "the day's paper is filed")
	_expect(sim.ledger.days[0].lines.get("town", 0), -500, "the fund is paid")
	_expect(sim.ledger.days[0].moves.total > 0, true, "the port works through it all (%d moves)" % sim.ledger.days[0].moves.total)
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
