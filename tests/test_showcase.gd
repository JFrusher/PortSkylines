extends SceneTree
## The showcase port (bench/showcase_port.gd), the debug menu's port with one
## of nearly everything: it builds with no command refused and its ships work.
## godot --headless --script res://tests/test_showcase.gd

const Showcase := preload("res://bench/showcase_port.gd")

var _failures := 0


func _initialize() -> void:
	var refused: Array[String] = []
	var sim := Showcase.build(refused)
	_expect(refused, [] as Array[String], "every command builds")
	for i: int in roundi(120.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect(sim.ledger.moves.total > 0, true, "its ships are worked in the first two hours")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
