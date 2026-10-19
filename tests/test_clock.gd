extends SceneTree
## Headless tests for SimClock.
## godot --headless --script res://tests/test_clock.gd

var _failures := 0


func _initialize() -> void:
	_test_calendar()
	_test_ticks_for()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_calendar() -> void:
	var clock := SimClock.new()
	for i in 1200:
		clock.tick()
	_expect(clock.calendar_minutes(), 60.0, "1,200 ticks are one game hour")
	_expect(clock.game_hour(), 1, "hour after 1,200 ticks")
	for i in 28800 - 1200:
		clock.tick()
	_expect(clock.game_day(), 1, "28,800 ticks are one game day")
	_expect(clock.game_hour(), 0, "hour wraps at midnight")


func _test_ticks_for() -> void:
	_expect(SimClock.ticks_for(0.016, 8), 0, "a 60 fps frame holds no whole tick")
	_expect(SimClock.ticks_for(0.1, 8), 2, "0.1 s holds two ticks")
	_expect(SimClock.ticks_for(2.0, 8), 8, "a 2 s hitch is capped")
	_expect(SimClock.ticks_for(2.0, 48), 40, "the cap scales with speed")
