extends SceneTree
## Two game days of a seeded random port on roads and areas, with an RMG
## rail block whose track crosses the east road to the rail entry, and the sim's
## invariants checked as it runs: after every tick, cash moves only through the ledger
## and every closed day adds up to its change in cash (loans, land and
## dredging included); every vehicle second, stacks stay within their tiers, every box is in
## exactly one place (a stack, a vehicle or a machine's spreader), every vehicle holds the cell it is on and no two share
## one, and slots and machine jobs belong to vehicles that are there. Then half a
## game day of the showcase port, with M9's transhipment, barges and
## straddle carriers, where no lorry ever takes a box booked to go on by
## ship or barge.
## godot --headless --script res://tests/test_soak.gd

const RandomPort := preload("res://tests/random_port.gd")
const Showcase := preload("res://bench/showcase_port.gd")
# Two game days and a bit, so midnight closes the books twice.
const TICKS := SimClock.TICKS_PER_DAY * 2 + 1000
## Ticks between checks of every box, cell and slot, which cost more than
## the sim's own tick: one vehicle second, shorter than any state lasts.
const DEEP_EVERY := 20

var _failures := 0


func _initialize() -> void:
	var calm := _soak(RandomPort.rules())
	_expect(calm.delivered > 0, true, "the calm port delivers boxes (%d)" % calm.delivered)
	_expect(calm.by_rail > 0, true, "and sends boxes off by train (%d)" % calm.by_rail)
	# A lorry every 10 game hours: yards fill up and ships wait, which the calm
	# port never pushes hard enough to test.
	var congested_rules := RandomPort.rules()
	congested_rules.lorry_interval_minutes = 600.0
	var congested := _soak(congested_rules)
	_expect(congested.area_stacks.values().any(func(stacks: AreaStacks) -> bool: return stacks.room() <= 0), true, "the congested port fills a yard block")
	var refused: Array[String] = []
	var show := Showcase.build(refused)
	_expect(refused, [] as Array[String], "the showcase port builds")
	var tranships := 0
	var carriers := 0
	while show.clock.ticks < SimClock.TICKS_PER_DAY / 2 and _failures == 0:
		show.tick()
		_check(show)
		if show.clock.ticks % DEEP_EVERY == 0:
			tranships = maxi(tranships, show.boxes.values().filter(func(b: Dictionary) -> bool: return b.kind == "tranship").size())
			carriers = maxi(carriers, show.vehicles.filter(func(v: Vehicle) -> bool: return v.straddle).size())
	_expect(tranships > 0, true, "the showcase tranships boxes (%d at most)" % tranships)
	_expect(show.by_barge > 0, true, "and sends boxes up the river by barge (%d)" % show.by_barge)
	_expect(carriers > 0, true, "and its straddle carriers go out (%d at most)" % carriers)
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
			_add_rail(sim)
			sim.creative = false
		sim.tick()
		_check(sim)
	return sim


## An RMG block north of the east road, its siding track running east and
## crossing the road south to the rail entry.
func _add_rail(sim: PortSim) -> void:
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": -1, "from": 92, "to": 121}), "", "the rail block is built")
	var block: int = sim.areas.list.keys().max()
	sim.apply({"op": "set_area", "id": block, "settings": {"gear": "rmg"}})
	var area: Dictionary = sim.areas.list[block]
	var behind: Vector2i = area.start + area.out * sim.areas.depth_of(area)
	var entry := sim.site_rail_entry()
	var bend := Vector2i(entry.x - 5, behind.y)
	for leg: Array in [[behind, bend], [bend, Vector2i(bend.x, entry.y)], [Vector2i(bend.x, entry.y), entry]]:
		_expect(sim.apply({"op": "build_rail", "from": leg[0], "to": leg[1]}), "", "track to the rail entry")
	_expect(RailFlow.is_rail_block(sim, block), true, "the block is a rail block")


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
		# A train's job carries its box itself, counted below.
		if job.has("vehicle") and job.position < 0:
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
		# M7's routes (by cost, round areas and slots, keeping to turn lanes) still step cell to cell.
		var jumps := range(1, vehicle.path.size()).filter(func(i: int) -> bool: return RoadNet.length(vehicle.path[i - 1], vehicle.path[i]) > 1)
		_expect(jumps, [], "%s %d's route steps cell to cell %s" % [vehicle.kind, vehicle.id, at])
		_expect(cells.has(cell), false, "vehicles %d and %d share cell %s %s" % [vehicle.id, cells.get(cell, 0), cell, at])
		cells[cell] = vehicle.id
	# M8's water: no two ships' bookings of a narrow lane overlap, ships at
	# one anchorage hold their own spots, and a ship under way has a course.
	for i in sim.passages.size():
		for j in range(i + 1, sim.passages.size()):
			var a: Dictionary = sim.passages[i]
			var b: Dictionary = sim.passages[j]
			_expect(a.segment == b.segment and a.ship != b.ship and a.from < b.to and b.from < a.to, false, "ships %d and %d both book lane %d at once %s" % [a.ship, b.ship, a.segment, at])
	var spots := {}
	for ship: PortSim.Ship in sim.ships:
		if ship.anchorage:
			_expect(spots.has([ship.anchorage, ship.spot]), false, "two ships share spot %d at anchorage %d %s" % [ship.spot, ship.anchorage, at])
			spots[[ship.anchorage, ship.spot]] = true
		if ship.state in [PortSim.Ship.State.ARRIVING, PortSim.Ship.State.LEAVING, PortSim.Ship.State.ANCHORING]:
			_expect(ship.path.size() >= 2, true, "a %s under way has a course %s" % [ship.kind, at])
	for train: Train in sim.trains:
		for box: int in train.wagons:
			if box != 0:
				_expect(seen.has(box), false, "box %d on train %d is in one place only %s" % [box, train.id, at])
				seen[box] = train.id
	for job: Dictionary in sim.machine_jobs.values():
		if job.has("box"):
			seen[job.box] = "an RMG"
	# M8: a box moving between terminals waits for its lorry in the transfers.
	for transfer: Dictionary in sim.transfers:
		_expect(seen.has(transfer.box), false, "box %d in transfer is in one place only %s" % [transfer.box, at])
		seen[transfer.box] = "a transfer"
	_expect(seen.size(), sim.boxes.size(), "every box in the port is somewhere %s" % at)
	_expect(sim._by_id.size(), sim.vehicles.size(), "every vehicle is indexed by id %s" % at)
	var bound := {}
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.kind == "lorry" and vehicle.area != 0:
			bound[vehicle.area] = bound.get(vehicle.area, 0) + 1
	for area: int in sim._lorries_bound:
		_expect(sim._lorries_bound[area], bound.get(area, 0), "area %d's bound lorries are counted %s" % [area, at])
	_expect(sim._tractors_out(), sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "tractor" and not v.straddle).size(), "the tractor count matches the pool's vehicles %s" % at)
	for block: int in sim._straddles_out:
		_expect(sim._straddles_out[block], sim.vehicles.filter(func(v: Vehicle) -> bool: return v.straddle == block).size(), "block %d's straddle carriers out are counted %s" % [block, at])
	_expect(sim.exports, sim.boxes.values().filter(func(box: Dictionary) -> bool: return box.kind in ["export", "tranship"]).size(), "the export count matches the boxes %s" % at)
	# M9: a box going on by ship or barge never leaves by road.
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.kind == "lorry" and vehicle.box in sim.boxes:
			_expect(sim.boxes[vehicle.box].kind != "tranship" and not sim.boxes[vehicle.box].barge, true, "lorry %d never takes box %d, bound for a ship or barge %s" % [vehicle.id, vehicle.box, at])
	for area: int in sim.handovers.slots():
		for holder: int in sim.handovers.slots()[area]:
			_expect(holder == 0 or holder in ids, true, "area %d's slots hold vehicles that are there %s" % [area, at])
	var trains := sim.trains.map(func(t: Train) -> int: return t.id)
	for machine: int in sim.machine_jobs:
		var job: Dictionary = sim.machine_jobs[machine]
		_expect(job.train in trains if job.has("train") else job.vehicle in ids, true, "machine %d works for a vehicle or train that is there %s" % [machine, at])
