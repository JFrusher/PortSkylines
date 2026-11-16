extends SceneTree
## M11 scenarios: each plays on its own map under its patched rules; a fresh
## go draws a new coast; it is won with the medal for the day, lost when time
## runs out or a kept condition breaks; a save keeps all of it.
## godot --headless --script res://tests/test_scenario.gd

var _failures := 0


func _initialize() -> void:
	_test_each_starts()
	_test_won_by_the_day()
	_test_lost()
	_test_saved()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_each_starts() -> void:
	for key: String in Content.base().scenarios:
		var scenario: Dictionary = Content.base().scenarios[key]
		var sim := Scenario.start(key, 5, false)
		_expect(sim.map, scenario.map, "%s plays on its own map" % key)
		_expect(sim.money, int(scenario.start_money), "%s starts with its money" % key)
		_expect(Scenario.progress(sim).size(), scenario.goals.size() + scenario.keep.size(), "%s lists its goals" % key)
		var fresh := Scenario.start(key, 5, true)
		_expect(fresh.map, MapGen.PREFIX + "5", "%s fresh draws a coast" % key)
	_expect(Scenario.start("storm_week", 1, false).rules.events.storms.per_season, 4.0, "its rules are patched")
	_expect(Content.base().events.storms.per_season, 1.0, "and the game's are not")


func _test_won_by_the_day() -> void:
	var sim := Scenario.start("storm_week", 1, false)
	Scenario.close_day(sim, 0, 5000)
	_expect(sim.scenario.status, "playing", "not won yet")
	Scenario.close_day(sim, 1, 15000)
	_expect([sim.scenario.status, sim.scenario.medal], ["won", "gold"], "won on day 2: gold")
	sim = Scenario.start("storm_week", 1, false)
	Scenario.close_day(sim, 13, 20000)
	_expect(sim.scenario.medal, "silver", "won on day 14: silver")


func _test_lost() -> void:
	var sim := Scenario.start("storm_week", 1, false)
	Scenario.close_day(sim, 20, 100)
	_expect(sim.scenario.status, "lost", "time runs out")
	sim = Scenario.start("angry_neighbours", 1, false)
	sim.town.mood = 20.0
	Scenario.close_day(sim, 0, 100)
	_expect(sim.scenario.status, "lost", "a kept condition breaks")


func _test_saved() -> void:
	var sim := Scenario.start("storm_week", 9, true)
	Scenario.close_day(sim, 0, 1234)
	var path := "user://scenario.bin"
	_expect(SaveFile.save(path, sim), "", "saved")
	var back: PortSim = SaveFile.load_from(path).sim
	_expect(back.scenario, sim.scenario, "the scenario comes back")
	_expect(back.map, sim.map, "on its fresh coast")
	_expect(back.rules.events.storms.per_season, 4.0, "under its rules")
