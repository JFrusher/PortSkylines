extends SceneTree
## M8 step M: milestones need reputation, calls on time and berth
## productivity as well as TEU, and stay reached; objectives between
## milestones pay cash and reputation once.
## godot --headless --script res://tests/test_progression.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_reputation_gate()
	_test_objective_pays_once()
	_test_every_unlock_is_documented()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Milestone 2 needs reputation 40: with the lines at 30 it stays locked
## past its TEU, passes once reputation is back, and stays passed when it falls.
func _test_reputation_gate() -> void:
	var sim := AreaPort.base(RandomPort.strait(), "")
	var terminal: Dictionary = sim.milestones()[1]
	_expect(terminal.reputation, 40.0, "milestone 2 needs reputation 40")
	for line: String in sim.contracts.reputation:
		sim.contracts.reputation[line] = 30.0
	var box := {"kind": "import", "teu": 2, "reefer": false}
	while sim.teu_handled < terminal.teu:
		sim._moved(box, "aurora", 1)
	_expect([sim.milestones_reached(), sim.unlocked("rtg")], [1, false], "with enough TEU and too little reputation it stays locked")
	_expect(sim.milestone_needs(terminal).size(), 1, "and says what it still needs (%s)" % [sim.milestone_needs(terminal)])
	sim.contracts.lift(15.0)
	sim._moved(box, "aurora", 1)
	_expect([sim.milestones_reached(), sim.unlocked("rtg")], [2, true], "with reputation back above 40 it is reached")
	sim.contracts.lift(-45.0)
	sim._moved(box, "aurora", 1)
	_expect(sim.unlocked("rtg"), true, "and stays reached when reputation falls")


## Working three feeders on time pays $50,000 and 5 reputation with every
## line, once.
func _test_objective_pays_once() -> void:
	var sim := AreaPort.base(RandomPort.strait(), "")
	var objective: Dictionary = sim.rules.objectives.feeders_on_time
	var before: Dictionary = sim.contracts.reputation.duplicate()
	sim.on_time_calls = {"feeder": 2}
	sim._check_objectives()
	_expect(sim.ledger.today.get("objectives", 0), 0, "two feeders on time aren't enough")
	sim.on_time_calls = {"feeder": 3}
	sim._check_objectives()
	_expect(sim.ledger.today.get("objectives", 0), objective.cash, "three pay the objective's cash")
	_expect(sim.contracts.reputation.keys().all(func(line: String) -> bool: return is_equal_approx(sim.contracts.reputation[line], minf(before[line] + objective.reputation, 100.0))), true, "and lift every line's reputation")
	sim.on_time_calls = {"feeder": 9}
	sim._check_objectives()
	_expect(sim.ledger.today.get("objectives", 0), objective.cash, "only once")
	_expect(sim.objectives_done.has("feeders_on_time"), true, "it is marked done")


## docs/progression.md names every unlock in the data, as `key`.
func _test_every_unlock_is_documented() -> void:
	var doc := FileAccess.get_file_as_string("res://docs/progression.md")
	for milestone: Dictionary in Content.base().milestones.values():
		for unlock: String in milestone.unlocks:
			_expect(doc.contains("`%s`" % unlock), true, "docs/progression.md names the unlock `%s`" % unlock)
