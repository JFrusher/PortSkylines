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
	_expect(sim.agvs > 0 and sim.areas.list.values().any(func(a: Dictionary) -> bool: return a.type == "yard_block" and sim.rules.yard_gear[a.settings.gear].automated), true, "it has AGVs and an automated block")
	_expect(sim.policies.keys().size(), Showcase.POLICIES.size(), "its policies are on")
	_expect(sim.templates.keys(), ["By departure"], "a template is saved")
	var agv_seen := false
	for i: int in roundi(120.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		agv_seen = agv_seen or sim.vehicles.any(func(v: Vehicle) -> bool: return v.agv)
	_expect(agv_seen, true, "AGVs work in the first two hours")
	_expect(sim.ledger.moves.total > 0, true, "its ships are worked in the first two hours")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
