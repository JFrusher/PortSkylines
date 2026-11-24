extends SceneTree
## M13's exit criterion: a large port runs a game month with no commands and
## stays solvent and stable. The showcase port (bench/showcase_port.gd), whose
## North Terminal is already automated (AGVs to ASC transfer blocks), set up
## to run by rules: dual cycling on, every yard block stacking by departure
## through one template. It then starts from the start money, not creative, and runs 30 game
## days with no command, checked at every midnight: cash never below zero,
## every closed day adding up, ships sailing every day, and the yard, boxes
## and vehicles staying bounded. About an hour and a half on the CI box, so
## it is run by hand and its result kept in docs/perf.md.
## godot --headless --script res://bench/month_soak.gd

const Showcase := preload("res://bench/showcase_port.gd")
const DAYS := 30

var _failures := 0


func _initialize() -> void:
	var refused: Array[String] = []
	var sim := Showcase.build(refused)
	_expect(refused, [] as Array[String], "the showcase builds")
	_run_by_rules(sim)
	sim.creative = false
	sim.ledger.cash = sim.rules.start_money
	# The creative build's costs sit in today's lines with no cash spent.
	sim.ledger.opened = sim.ledger.cash - sim.ledger.today_total()
	var start := Time.get_ticks_msec()
	var lowest := sim.money
	var most_boxes := 0
	var most_vehicles := 0
	var sailed := sim.ship_log.size()
	var quiet_days := 0
	for day in DAYS:
		var calls_before: int = sim.year.calls + sim.scoreboard.size() * 1000
		for i in SimClock.TICKS_PER_DAY:
			sim.tick()
			lowest = mini(lowest, sim.money)
		var closed: Dictionary = sim.ledger.days[-1]
		var total := 0
		for category: String in closed.lines:
			total += closed.lines[category]
		_expect(total, closed.closed - closed.opened, "day %d's lines add up to its change in cash" % (day + 1))
		most_boxes = maxi(most_boxes, sim.boxes.size())
		most_vehicles = maxi(most_vehicles, sim.vehicles.size())
		quiet_days += 1 if closed.moves.total == 0 else 0
		print("day %2d: %.0f s, cash %d, moves %d, delivered %d, ships %d, boxes %d, vehicles %d, reputation %.0f, services %d" % [day + 1, (Time.get_ticks_msec() - start) / 1000.0, sim.money, closed.moves.total, sim.delivered, sim.ships.size(), sim.boxes.size(), sim.vehicles.size(), sim.average_reputation(), sim.contracts.services.size()])
	_expect(lowest >= 0, true, "the port stays solvent: lowest cash %d" % lowest)
	_expect(sim.finance.loans.is_empty(), true, "with no loan, as no command takes one")
	_expect(quiet_days, 0, "cranes work every day (%d days with no move)" % quiet_days)
	_expect(most_boxes < 20000 and most_vehicles < 2000, true, "boxes (most %d) and vehicles (most %d) stay bounded" % [most_boxes, most_vehicles])
	_expect(sim.money > sim.rules.start_money, true, "and ends richer than it started (%d)" % sim.money)
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Sets the port up to run without input: dual cycling, and stacking by
## departure everywhere by template.
func _run_by_rules(sim: PortSim) -> void:
	_expect(sim.apply({"op": "set_policy", "policy": "dual_cycling", "on": true}), "", "dual cycling is on")
	var blocks := sim.areas.list.keys().filter(func(id: int) -> bool: return sim.areas.list[id].type == "yard_block")
	_expect(sim.apply({"op": "set_area", "id": blocks[0], "settings": {"stacking": "by_departure"}}), "", "a block stacks by departure")
	_expect(sim.apply({"op": "save_template", "name": "by departure", "id": blocks[0]}), "", "its rules are a template")
	for id: int in blocks:
		_expect(sim.apply({"op": "apply_template", "name": "by departure", "id": id}), "", "block %d takes the template" % id)
