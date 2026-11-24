extends RefCounted
## The sim's invariants, checked as a port runs (tests/test_soak.gd and
## test_soak_m11.gd): after every tick, cash moves only through the ledger and
## every closed day adds up to its change in cash; every `deep_every` ticks,
## stacks stay within their tiers, every box is in exactly one place, every
## vehicle holds the cell it is on and no two share one, and slots and
## machine jobs belong to vehicles that are there. `expect` is the test's
## expect(actual, expected, what).


static func check(sim: PortSim, expect: Callable, deep_every: int) -> void:
	var at := "at tick %d" % sim.clock.ticks
	expect.call(sim.ledger.today_total(), sim.money - sim.ledger.opened, "today's ledger lines add up to the change in cash " + at)
	for loan in sim.finance.loans:
		expect.call(loan.owed >= 0 and loan.days_left > 0, true, "loan %s is being paid down %s" % [loan, at])
	if sim.clock.ticks % SimClock.TICKS_PER_DAY == 0:
		var day: Dictionary = sim.ledger.days[-1]
		var total := 0
		for category: String in day.lines:
			total += day.lines[category]
		expect.call(total, day.closed - day.opened, "day %d's ledger adds up to its change in cash" % day.day)
	if sim.clock.ticks % deep_every != 0:
		return
	# Every box is in exactly one place: a yard stack or a vehicle's load.
	var seen := {}
	for area: int in sim.area_stacks:
		var stacks: AreaStacks = sim.area_stacks[area]
		var tiers: int = sim.rules.yard_gear[sim.areas.list[area].settings.gear].tiers
		expect.call(stacks.stacks.all(func(stack: Array) -> bool: return stack.size() <= tiers), true, "area %d's stacks stay within %d tiers %s" % [area, tiers, at])
		for id: int in stacks.boxes():
			expect.call(seen.has(id), false, "box %d is in one place only %s" % [id, at])
			seen[id] = area
	# M11: a box on a transfer block's rack, an import set down or an export staged.
	for block: int in sim.racks:
		for slot: int in sim.racks[block]:
			var rack: Dictionary = sim.racks[block][slot]
			if rack.state in ["in", "ready"]:
				expect.call(seen.has(rack.box), false, "box %d on a rack of block %d is in one place only %s" % [rack.box, block, at])
				seen[rack.box] = block
	# Boxes an ASC carries between a rack and its stack, counted below.
	var moving := {}
	for job: Dictionary in sim.machine_jobs.values():
		if job.has("rack"):
			moving[job.box] = true
	# A machine fetching a vehicle's box has lifted it off its stack.
	var lifting := {}
	for job: Dictionary in sim.machine_jobs.values():
		# A train's job carries its box itself, counted below.
		if job.has("vehicle") and job.position < 0:
			lifting[job.vehicle] = true
	var ids := {}
	for vehicle: Vehicle in sim.vehicles:
		ids[vehicle.id] = true
		if vehicle.loaded:
			expect.call(seen.has(vehicle.box), false, "box %d on vehicle %d is in one place only %s" % [vehicle.box, vehicle.id, at])
			seen[vehicle.box] = vehicle.id
		elif vehicle.id in lifting:
			expect.call(seen.has(vehicle.box), false, "box %d on the machine for %s %d is in one place only %s" % [vehicle.box, vehicle.kind, vehicle.id, at])
			seen[vehicle.box] = vehicle.id
		elif vehicle.box != 0:
			expect.call(seen.has(vehicle.box) or vehicle.box in moving, true, "%s %d's box %d waits in a stack, on a rack or on its way to one %s" % [vehicle.kind, vehicle.id, vehicle.box, at])
		expect.call(vehicle.id in sim.traffic.cars, true, "%s %d is on the lanes %s" % [vehicle.kind, vehicle.id, at])
	# M10: no two cars on a piece overlap.
	var on := {}
	for id: int in sim.traffic.cars:
		var car: Dictionary = sim.traffic.cars[id]
		on.get_or_add(car.route[car.i], []).append(car)
	for piece: int in on:
		var cars: Array = on[piece]
		cars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.s < b.s)
		for k in range(1, cars.size()):
			expect.call(cars[k].s - cars[k].length >= cars[k - 1].s - 0.001, true, "cars on piece %d keep apart %s" % [piece, at])
	# M8's water: no two ships' bookings of a narrow lane overlap, ships at
	# one anchorage hold their own spots, and a ship under way has a course.
	for i in sim.passages.size():
		for j in range(i + 1, sim.passages.size()):
			var a: Dictionary = sim.passages[i]
			var b: Dictionary = sim.passages[j]
			expect.call(a.segment == b.segment and a.ship != b.ship and a.from < b.to and b.from < a.to, false, "ships %d and %d both book lane %d at once %s" % [a.ship, b.ship, a.segment, at])
	var spots := {}
	for ship: PortSim.Ship in sim.ships:
		if ship.anchorage:
			expect.call(spots.has([ship.anchorage, ship.spot]), false, "two ships share spot %d at anchorage %d %s" % [ship.spot, ship.anchorage, at])
			spots[[ship.anchorage, ship.spot]] = true
		if ship.state in [PortSim.Ship.State.ARRIVING, PortSim.Ship.State.LEAVING, PortSim.Ship.State.ANCHORING]:
			expect.call(ship.path.size() >= 2, true, "a %s under way has a course %s" % [ship.kind, at])
	for train: Train in sim.trains:
		for box: int in train.wagons:
			if box != 0:
				expect.call(seen.has(box), false, "box %d on train %d is in one place only %s" % [box, train.id, at])
				seen[box] = train.id
	for job: Dictionary in sim.machine_jobs.values():
		if job.has("box"):
			seen[job.box] = "a machine"
	# M8: a box moving between terminals waits for its lorry in the transfers.
	for transfer: Dictionary in sim.transfers:
		expect.call(seen.has(transfer.box), false, "box %d in transfer is in one place only %s" % [transfer.box, at])
		seen[transfer.box] = "a transfer"
	expect.call(seen.size(), sim.boxes.size(), "every box in the port is somewhere %s" % at)
	expect.call(sim._by_id.size(), sim.vehicles.size(), "every vehicle is indexed by id %s" % at)
	var bound := {}
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.kind == "lorry" and vehicle.area != 0:
			bound[vehicle.area] = bound.get(vehicle.area, 0) + 1
	for area: int in sim._lorries_bound:
		expect.call(sim._lorries_bound[area], bound.get(area, 0), "area %d's bound lorries are counted %s" % [area, at])
	expect.call(sim._tractors_out(), sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "tractor" and not v.straddle).size(), "the tractor count matches the pool's vehicles %s" % at)
	for block: int in sim._straddles_out:
		expect.call(sim._straddles_out[block], sim.vehicles.filter(func(v: Vehicle) -> bool: return v.straddle == block).size(), "block %d's straddle carriers out are counted %s" % [block, at])
	expect.call(sim.exports, sim.boxes.values().filter(func(box: Dictionary) -> bool: return box.kind in ["export", "tranship"]).size(), "the export count matches the boxes %s" % at)
	# M9: a box going on by ship or barge never leaves by road; a transhipment
	# rides a lorry only between terminals, out to its onward ship's (it has
	# `to`) or in from the other (not stacked since).
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.kind == "lorry" and vehicle.box in sim.boxes:
			var box: Dictionary = sim.boxes[vehicle.box]
			expect.call(not box.barge and (box.kind != "tranship" or box.to != 0 or box.in < 0.0), true, "lorry %d never takes box %d, bound for a ship or barge, but between terminals %s" % [vehicle.id, vehicle.box, at])
	for area: int in sim.handovers.slots():
		for holder: int in sim.handovers.slots()[area]:
			expect.call(holder == 0 or holder in ids, true, "area %d's slots hold vehicles that are there %s" % [area, at])
	var trains := sim.trains.map(func(t: Train) -> int: return t.id)
	for machine: int in sim.machine_jobs:
		var job: Dictionary = sim.machine_jobs[machine]
		var there: bool = job.train in trains if job.has("train") else (job.rack in sim.areas.list if job.has("rack") else job.vehicle in ids)
		expect.call(there, true, "machine %d works for a vehicle, train or rack that is there %s" % [machine, at])
