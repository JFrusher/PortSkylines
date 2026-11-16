extends SceneTree
## M11 the morning paper: each closed day's report matches the ledger and
## the ship log for that day, and only the last week is kept.
## godot --headless --script res://tests/test_report.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	var sim := AreaPort.base()
	var calls := 0
	var on_time := 0
	for day in 9:
		for i in SimClock.TICKS_PER_DAY:
			sim.tick()
		var report: Dictionary = sim.reports[-1]
		var closed: Dictionary = sim.ledger.days[-1]
		_expect(report.day, closed.day, "day %d: the paper is the day's" % day)
		_expect(report.moves, closed.moves.total, "day %d: its moves" % day)
		_expect(report.net, closed.closed - closed.opened, "day %d: its money" % day)
		_expect(report.on_time <= report.calls, true, "day %d: on time within the calls" % day)
		calls += report.calls
		on_time += report.on_time
	_expect(sim.reports.size(), PortSim.REPORT_DAYS, "a week of papers is kept")
	_expect(calls > 0, true, "calls are reported (%d)" % calls)
	_expect(sim.year.calls, calls + sim.today_calls.calls, "every call is in a paper, or today's")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
