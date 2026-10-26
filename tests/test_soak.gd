extends SceneTree
## Two game days of a seeded random port on roads and areas, with the sim's
## invariants checked as it runs: after every tick, cash moves only through the ledger
## and every closed day adds up to its change in cash (loans, land and
## dredging included); every vehicle second, stacks stay within their tiers, every box is in
## exactly one place (a stack, a vehicle or a machine's spreader), every vehicle holds the cell it is on and no two share
## one, and slots and machine jobs belong to vehicles that are there.
## godot --headless --script res://tests/test_soak.gd

const RandomPort := preload("res://tests/random_port.gd")
# Two game days and a bit, so midnight closes the books twice.
const TICKS := SimClock.TICKS_PER_DAY * 2 + 1000
## Ticks between checks of every box, cell and slot, which cost more than
## the sim's own tick: one vehicle second, shorter than any state lasts.
const DEEP_EVERY := 20

var _failures := 0


func _initialize() -> void:
	var calm := _soak(RandomPort.rules())
	_expect(calm.delivered > 0, true, "the calm port delivers boxes (%d)" % calm.delivered)
	# A lorry every 10 game hours: yards fill up and ships wait, which the calm
	# port never pushes hard enough to test.
	var congested_rules := RandomPort.rules()
	congested_rules.lorry_interval_minutes = 600.0
	var congested := _soak(congested_rules)
	_expect(congested.area_stacks.values().any(func(stacks: AreaStacks) -> bool: return stacks.room() <= 0), true, "the congested port fills a yard block")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _soak(rules: Dictionary) -> PortSim:
	var sim := PortSim.new(2, rules, true)
	RandomPort.calls(sim)
	var log := RandomPort.command_log(11, TICKS, 400)
	var next := 0
	while sim.clock.ticks < TICKS and _failures == 0:
		while next < log.size() and log[next].tick == sim.clock.ticks:
			sim.apply(log[next].command)
			next += 1
		# The port is built for free, then plays for money.
		if sim.clock.ticks == 0:
			sim.creative = false
		sim.tick()
		_check(sim)
	return sim


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _check(sim: PortSim) -> void:
	var at := "at tick %d" % sim.clock.ticks
	_expect(sim.ledger.today_total(), sim.money - sim.ledger.opened, "today's ledger lines add up to the change in cash " + at)
	for loan in sim.finance.loans:
		_expect(loan.owed >= 0 and loan.days_left > 0, true, "loan %s is being paid down %s" % [loan, at])
	if sim.clock.ticks % SimClock.TICKS_PER_DAY == 0:
		var day: Dictionary = sim.ledger.days[-1]
		var total := 0
		for category: String in day.lines:
			total += day.lines[category]
		_expect(total, day.closed - day.opened, "day %d's ledger adds up to its change in cash" % day.day)
	if sim.clock.ticks % DEEP_EVERY != 0:
		return
	# Every box is in exactly one place: a yard stack or a vehicle's load.
	var seen := {}
	for area: int in sim.area_stacks:
		var stacks: AreaStacks = sim.area_stacks[area]
		var tiers: int = sim.rules.yard_gear[sim.areas.list[area].settings.gear].tiers
		_expect(stacks.stacks.all(func(stack: Array) -> bool: return stack.size() <= tiers), true, "area %d's stacks stay within %d tiers %s" % [area, tiers, at])
		for id: int in stacks.boxes():
			_expect(seen.has(id), false, "box %d is in one place only %s" % [id, at])
			seen[id] = area
	# A machine fetching a vehicle's box has lifted it off its stack.
	var lifting := {}
	for job: Dictionary in sim.machine_jobs.values():
		if job.position < 0:
			lifting[job.vehicle] = true
	var cells := {}
	var ids := {}
	for vehicle: Vehicle in sim.vehicles:
		ids[vehicle.id] = true
		if vehicle.loaded:
			_expect(seen.has(vehicle.box), false, "box %d on vehicle %d is in one place only %s" % [vehicle.box, vehicle.id, at])
			seen[vehicle.box] = vehicle.id
		elif vehicle.id in lifting:
			_expect(seen.has(vehicle.box), false, "box %d on the machine for %s %d is in one place only %s" % [vehicle.box, vehicle.kind, vehicle.id, at])
			seen[vehicle.box] = vehicle.id
		elif vehicle.box != 0:
			_expect(seen.has(vehicle.box), true, "%s %d's box %d waits in a stack %s" % [vehicle.kind, vehicle.id, vehicle.box, at])
		var cell := vehicle.path[int(vehicle.t)]
		_expect(sim.lane_traffic.holder(cell), vehicle.id, "%s %d holds the cell it is on %s" % [vehicle.kind, vehicle.id, at])
		_expect(cells.has(cell), false, "vehicles %d and %d share cell %s %s" % [vehicle.id, cells.get(cell, 0), cell, at])
		cells[cell] = vehicle.id
	_expect(seen.size(), sim.boxes.size(), "every box in the port is somewhere %s" % at)
	_expect(sim.exports, sim.boxes.values().filter(func(box: Dictionary) -> bool: return box.kind == "export").size(), "the export count matches the boxes %s" % at)
	for area: int in sim.handovers.slots():
		for holder: int in sim.handovers.slots()[area]:
			_expect(holder == 0 or holder in ids, true, "area %d's slots hold vehicles that are there %s" % [area, at])
	for machine: int in sim.machine_jobs:
		_expect(sim.machine_jobs[machine].vehicle in ids, true, "machine %d works for a vehicle that is there %s" % [machine, at])
