extends SceneTree
## 10,000 ticks of a seeded random port, with the sim's invariants checked
## after every tick: money only changes through commands and fees, yards stay within capacity, lorries only
## come for boxes that exist, and every lorry drives on road.
## godot --headless --script res://tests/test_soak.gd

const RandomPort := preload("res://tests/random_port.gd")
const TICKS := 10000

var _failures := 0


func _initialize() -> void:
	var calm := _soak(Content.base())
	_expect(calm.delivered > 0, true, "the calm port delivers boxes (%d)" % calm.delivered)
	# A lorry every 10 game hours: yards fill up and ships wait, which the calm
	# port never pushes hard enough to test.
	var congested_rules := Content.base().duplicate(true)
	congested_rules.lorry_interval_minutes = 600.0
	var congested := _soak(congested_rules)
	_expect(congested.stacked.values().has(congested.rules.yard_capacity), true, "the congested port fills a yard to capacity")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _soak(rules: Dictionary) -> PortSim:
	var sim := PortSim.new(2, rules)
	var log := RandomPort.command_log(11, TICKS, 400)
	var spent := 0
	var next := 0
	while sim.clock.ticks < TICKS and _failures == 0:
		while next < log.size() and log[next].tick == sim.clock.ticks:
			var before := sim.money
			sim.apply(log[next].command)
			spent += before - sim.money
			next += 1
		sim.tick()
		_check(sim, spent)
	return sim


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _check(sim: PortSim, spent: int) -> void:
	var at := "at tick %d" % sim.clock.ticks
	_expect(sim.money, sim.rules.start_money - spent + sim.delivered * sim.rules.fee_per_box, "money adds up " + at)
	for yard: Vector2i in sim.stacked:
		var count: int = sim.stacked[yard]
		_expect(count >= 0 and count <= sim.rules.yard_capacity, true, "yard %s holds %d boxes %s" % [yard, count, at])
		_expect(sim._claimed.get(yard, 0) <= count, true, "lorries come only for boxes in yard %s %s" % [yard, at])
	for lorry: PortSim.Lorry in sim.lorries:
		for cell: Vector2i in lorry.path:
			if sim.map.tile(cell) != PortMap.Tile.ROAD:
				_expect(sim.map.tile(cell), PortMap.Tile.ROAD, "lorry path cell %s is road %s" % [cell, at])
				return
