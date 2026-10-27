class_name RailFlow
extends RefCounted
## Trains to the port's rail blocks: RMG yard blocks whose siding track runs
## back to the rail entry. Each rail block gets a train every
## rail.train.interval_minutes while none is at it. A train comes in from off
## the map, stands along the siding, and the block's RMGs lift the imports
## booked to rail onto its wagons as they fall due; at its departure time,
## or once its wagons are full, with nothing left for it, it leaves.
## Its functions take the sim, whose state they work on, as AreaFlow's do.


## The rail blocks, by block id, each holding its train's path from the rail
## entry to the far end of its siding. Kept until roads, areas or track change.
static func rail_blocks(sim: PortSim) -> Dictionary:
	var now := Vector3i(sim.areas.version, sim.roads.version, sim.rails.version)
	if sim._rail_blocks_for != now:
		sim._rail_blocks_for = now
		sim._rail_blocks.clear()
		for id: int in sim.areas.list:
			var siding := AreaFlow.siding(sim, id)
			if siding.size() < 2 * AreaLayout.BAY or sim.areas.idle_reason(id) != "":
				continue
			# The route to the far end passes the near one: it is the longer.
			var to_first := sim.rails.path(sim.site_rail_entry(), siding[0])
			var to_last := sim.rails.path(sim.site_rail_entry(), siding[-1])
			if not to_first.is_empty() and not to_last.is_empty():
				sim._rail_blocks[id] = to_first if to_first.size() > to_last.size() else to_last
	return sim._rail_blocks


static func is_rail_block(sim: PortSim, block: int) -> bool:
	return rail_blocks(sim).has(block)


## A rail block of `terminal` with room for one more box than is already on
## its way, or 0: where tractors take imports booked to rail.
static func block_with_room(sim: PortSim, terminal: int) -> int:
	for id: int in rail_blocks(sim):
		if sim.areas.list[id].terminal != terminal:
			continue
		var coming := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.area == id and v.loaded).size()
		if AreaFlow._stacks(sim, id).room() > coming:
			return id
	return 0


## One tick of rail: trains are sent on time, then each moves or is worked.
static func tick(sim: PortSim) -> void:
	for block: int in rail_blocks(sim):
		sim._until_train[block] = sim._until_train.get(block, 0.0) - SimClock.CALENDAR_MINUTES_PER_TICK
		if sim._until_train[block] <= 0.0 and not sim.trains.any(func(t: Train) -> bool: return t.block == block):
			_send(sim, block)
			sim._until_train[block] = sim.rules.rail.train.interval_minutes
	for train: Train in sim.trains.duplicate():
		_run(sim, train)


static func _send(sim: PortSim, block: int) -> void:
	var bays := AreaFlow.siding(sim, block).size() / AreaLayout.BAY
	# The locomotive stands at one bay and a wagon at each of the others.
	var train := Train.new(sim._next_train, block, rail_blocks(sim)[block], mini(sim.rules.rail.train.wagons, bays - 1))
	sim._next_train += 1
	# It brings the lines' share, on average, of the exports still wanted.
	var share := 0.0
	for line: String in sim.rules.lines:
		share += sim.rail_share(line) / sim.rules.lines.size()
	var linked: bool = sim.rules.hinterland.places.values().any(func(p: Dictionary) -> bool: return p.rail_km > 0.0)
	var exports := mini(train.wagons.size(), ceili(maxi(AreaFlow.export_demand(sim), 0) * share)) if linked else 0
	for i in exports:
		# shortcut: an export is booked on no line until a ship loads it, as by road.
		var box := sim._new_box("export", 0.0, "")
		# Rail carries only boxes from places with a rail link.
		sim.boxes[box].place = sim._pick_place(true)
		train.wagons[i] = box
	_pay_discount(sim, exports)
	sim.trains.append(train)
	sim._event("A train is coming for %s" % sim.areas.terminals[sim.areas.list[block].terminal].name, sim.areas.list[block].start)


## Cells a train moves a tick: the data gives its speed in metres a vehicle second.
static func _step(sim: PortSim) -> float:
	return sim.rules.rail.train.speed / Grid.CELL * SimClock.TICK_SECONDS


static func _run(sim: PortSim, train: Train) -> void:
	train.prev_t = train.t
	match train.state:
		"arriving":
			if _move(sim, train, minf(train.t + _step(sim), train.path.size() - 1)) and train.t == train.path.size() - 1:
				train.state = "working"
				train.depart = sim.clock.calendar_minutes() + sim.rules.rail.train.dwell_minutes
		"working":
			_work(sim, train)
		"leaving":
			if _move(sim, train, train.t - _step(sim)) and train.t <= 0.0:
				_gone(sim, train)


## Moves the train's head to `to` cells along its path, booking every level
## crossing its body will cover, and those just ahead, through LaneTraffic as
## the one way onto a crossing; with a vehicle on one, it waits where it is.
# shortcut: trains book only level crossings, not track, so two trains could share a cell; book track blocks when lines get busy.
static func _move(sim: PortSim, train: Train, to: float) -> bool:
	var ahead := ceili(_step(sim)) + 2
	var from := maxi(floori(minf(train.t, to)) - train.length() - ahead, 0)
	var past := mini(ceili(maxf(train.t, to)) + ahead, train.path.size() - 1)
	var crossings := sim.lanes.crossings()
	var wanted: Array[Vector2i] = []
	for i in range(from, past + 1):
		if train.path[i] in crossings:
			wanted.append(train.path[i])
	if not sim.lane_traffic.rebook(-train.id, wanted):
		return false
	train.t = to
	return true


## Gives each idle RMG of the train's block a wagon to work, unloading first,
## then loading the rail imports due longest; with nothing left to do and no
## RMG still at it, the train leaves.
static func _work(sim: PortSim, train: Train) -> void:
	for machine: int in sim.machines.list:
		if sim.machines.list[machine].area != train.block or machine in sim.machine_jobs:
			continue
		if not _give(sim, train, machine):
			break
	# It keeps its schedule, leaving early only with every wagon full.
	var due := sim.clock.calendar_minutes() >= train.depart or _empty_wagon(train) < 0
	if train.busy.is_empty() and due and not _has_work(sim, train):
		train.state = "leaving"


## Gives `machine` the train's next wagon to work; false when there is none.
static func _give(sim: PortSim, train: Train, machine: int) -> bool:
	var stacks := AreaFlow._stacks(sim, train.block)
	var layout := sim.areas.layout(train.block)
	for i in train.wagons.size():
		if _to_unload(sim, train, i):
			var position := stacks.place_spot(sim.boxes[train.wagons[i]].teu)
			if position < 0:
				continue
			sim.machines.give(machine, _wagon_bay(sim, train, i), layout.stacks[position].bay)
			sim.machine_jobs[machine] = {"train": train.id, "wagon": i, "position": position}
			train.busy.append(i)
			return true
	var box := _due_import(sim, train)
	var wagon := _empty_wagon(train)
	if box == 0 or wagon < 0:
		return false
	var bay: int = layout.stacks[stacks.position_of(box)].bay
	var rehandles := stacks.take(box)
	if rehandles < 0:
		return false
	sim._claimed[box] = true
	sim.machines.give(machine, bay, _wagon_bay(sim, train, wagon), rehandles)
	sim.machine_jobs[machine] = {"train": train.id, "wagon": wagon, "position": -1, "box": box}
	train.busy.append(wagon)
	return true


## Whether anything is left for the train: a box to unload where it fits, or
## a due import with an empty wagon for it.
static func _has_work(sim: PortSim, train: Train) -> bool:
	var stacks := AreaFlow._stacks(sim, train.block)
	for i in train.wagons.size():
		if _to_unload(sim, train, i) and stacks.place_spot(sim.boxes[train.wagons[i]].teu) >= 0:
			return true
	return _empty_wagon(train) >= 0 and _due_import(sim, train) != 0


## The rail block's unclaimed import due out longest, or 0 when none is due.
static func _due_import(sim: PortSim, train: Train) -> int:
	for box: int in AreaFlow._stacks(sim, train.block).of_kind("import", sim.boxes):
		if box not in sim._claimed:
			return box if sim.boxes[box].due <= sim.clock.calendar_minutes() else 0
	return 0


## Whether wagon `i` carries an export in, which comes off; imports loaded stay on.
static func _to_unload(sim: PortSim, train: Train, i: int) -> bool:
	return train.wagons[i] != 0 and i not in train.busy and sim.boxes[train.wagons[i]].kind == "export"


static func _empty_wagon(train: Train) -> int:
	for i in train.wagons.size():
		if train.wagons[i] == 0 and i not in train.busy:
			return i
	return -1


## The block bay wagon `i` stands at: the locomotive is at the head, at the
## siding's far end, and the wagons behind it a bay each.
static func _wagon_bay(sim: PortSim, train: Train, i: int) -> int:
	var bays := AreaFlow.siding(sim, train.block).size() / AreaLayout.BAY
	var head_at_end: bool = train.path[-1] == AreaFlow.siding(sim, train.block)[-1]
	return bays - 2 - i if head_at_end else i + 1


## An RMG finished a wagon: a box unloaded goes on its stack, a box loaded
## stays on its wagon. Vehicles waiting at the block ask the RMG again.
static func job_done(sim: PortSim, machine: int) -> void:
	var job: Dictionary = sim.machine_jobs[machine]
	sim.machine_jobs.erase(machine)
	var train := _train(sim, job.train)
	if train == null:
		return  # gone with its block while the RMG worked
	train.busy.erase(job.wagon)
	var stacks := AreaFlow._stacks(sim, train.block)
	if job.position >= 0:
		var box: int = train.wagons[job.wagon]
		var teu: int = sim.boxes[box].teu
		stacks.place_at(job.position if stacks.fits(job.position, teu) else stacks.place_spot(teu), box, teu)
		sim.boxes[box].in = sim.clock.calendar_minutes()
		train.wagons[job.wagon] = 0
	else:
		train.wagons[job.wagon] = job.box
		sim._claimed.erase(job.box)
		sim.dwell_times.append(sim.clock.calendar_minutes() - sim.boxes[job.box].in)
		if sim.dwell_times.size() > 50:
			sim.dwell_times.pop_front()
	AreaFlow._retry_handling(sim, train.block)


## A train off the map: the boxes on its wagons have left the port by rail.
static func _gone(sim: PortSim, train: Train) -> void:
	for box: int in train.wagons:
		if box != 0:
			sim._import_left(box)
			sim._drop_box(box)
			sim.delivered += 1
			sim.by_rail += 1
	_pay_discount(sim, train.wagons.filter(func(box: int) -> bool: return box != 0).size())
	sim.lane_traffic.release(-train.id)
	sim.trains.erase(train)


## The rail discount on `boxes` boxes carried by train.
static func _pay_discount(sim: PortSim, boxes: int) -> void:
	if boxes > 0 and sim.rail_discount > 0:
		sim.ledger.post("rail", -boxes * sim.rail_discount)


## Takes away the trains serving block `id`, with their boxes, as the block goes.
static func forget(sim: PortSim, id: int) -> int:
	var lost := 0
	for train: Train in sim.trains.duplicate():
		if train.block != id:
			continue
		for box: int in train.wagons:
			if box != 0:
				sim._drop_box(box)
				lost += 1
		sim.lane_traffic.release(-train.id)
		sim.trains.erase(train)
	sim._until_train.erase(id)
	return lost


static func _train(sim: PortSim, id: int) -> Train:
	for train: Train in sim.trains:
		if train.id == id:
			return train
	return null
