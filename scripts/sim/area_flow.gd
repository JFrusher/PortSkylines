class_name AreaFlow
extends RefCounted
## The port's work on roads and areas: ships berth along quay aprons, STS
## cranes stand on their rails, and boxes move by slots and machine jobs. Its
## functions take the sim, whose state they work on, so nothing refers back.

## How many cells of quay a ship of `kind` needs.
static func ship_cells(sim: PortSim, kind: String) -> int:
	return ceili(sim.rules.ship_classes[kind].length / float(Grid.CELL))


## Aprons that can take ships: in a terminal with a gate, and with a road.
static func ready_aprons(sim: PortSim) -> Array[int]:
	var found: Array[int] = []
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type == "quay_apron" and sim.areas.terminal_error(area.terminal) == "" and sim.areas.idle_reason(id) == "":
			found.append(id)
	return found


## Moves an anchored ship to a free stretch of a ready apron, its own berth
## if it has one, or another only if it may; false if none yet.
static func berth(sim: PortSim, ship: PortSim.Ship) -> bool:
	var span := ship_cells(sim, ship.kind)
	var aprons := ready_aprons(sim).filter(func(apron: int) -> bool: return Marine.reaches(sim, ship.kind, apron, ship.anchorage, ship.light))
	if ship.berth != 0:
		# A service is signed for its berth's terminal: other berths only there,
		# or anywhere once its berth is gone.
		var mine := func(a: int) -> bool: return ship.berth not in sim.areas.list or sim.areas.list[a].terminal == sim.areas.list[ship.berth].terminal
		var others := aprons.filter(func(a: int) -> bool: return a != ship.berth and mine.call(a)) if ship.any_berth else []
		var own := ship.berth in aprons
		aprons.clear()
		if own:
			aprons.append(ship.berth)
		aprons.append_array(others)
	for apron: int in aprons:
		for from in range(_length(sim, apron) - span + 1):
			if sim.ships.any(func(other: PortSim.Ship) -> bool: return other.apron == apron and other.from < from + span and from < other.from + ship_cells(sim, other.kind) and not Marine.clear_of_berth(sim, other)):
				continue
			ship.apron = apron
			ship.from = from
			ship.state = PortSim.Ship.State.ARRIVING
			Marine.set_course(sim, ship)
			return true
	return false


## Whether some ready apron is long enough for `kind`, busy or not.
static func could_berth(sim: PortSim, kind: String) -> bool:
	return ready_aprons(sim).any(func(apron: int) -> bool: return _length(sim, apron) >= ship_cells(sim, kind))


## Each agreed service, then each offer, on its berth: {"service", "apron"
## (0 for none yet), "clash"}, a clash where its window overlaps another
## agreed service's on the same berth.
static func berth_plan(sim: PortSim) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	for service: Dictionary in sim.contracts.services + sim.contracts.offers:
		var clash: bool = service.apron != 0 and sim.contracts.services.any(func(other: Dictionary) -> bool: return other.id != service.id and other.apron == service.apron and Contracts.windows_overlap(service, other))
		plan.append({"service": service, "apron": service.apron, "clash": clash})
	return plan


## Ready aprons with a crane on them: berths lines may offer services for.
static func offer_berths(sim: PortSim) -> Array[int]:
	var found: Array[int] = []
	for apron in ready_aprons(sim):
		if sim.cranes.any(func(c: PortSim.Crane) -> bool: return c.apron == apron):
			found.append(apron)
	return found


## Whether a ship of `kind` could be worked at berth `apron`: long enough,
## with a crane that reaches across it.
static func could_work_at(sim: PortSim, kind: String, apron: int) -> bool:
	var rows: int = sim.rules.ship_classes[kind].outreach
	return _length(sim, apron) >= ship_cells(sim, kind) and sim.cranes.any(func(c: PortSim.Crane) -> bool: return c.apron == apron and _reach(sim, c) >= rows)


## The crane whose legs stand over grid cell `cell`, or null.
static func crane_at(sim: PortSim, cell: Vector2i) -> PortSim.Crane:
	var apron := sim.areas.area_at(cell)
	if apron == 0 or sim.areas.list[apron].type != "quay_apron":
		return null
	var along := sim.areas.along(apron, cell)
	for crane in sim.cranes:
		if crane.apron == apron and absi(crane.along - along) * Grid.CELL * 2 < sim.rules.sts_cranes[crane.kind].width:
			return crane
	return null


## Box rows `crane` reaches across a ship.
static func _reach(sim: PortSim, crane: PortSim.Crane) -> int:
	return sim.rules.sts_cranes[crane.kind].outreach


## Calendar minutes one move of `crane` takes.
static func move_minutes_of(sim: PortSim, crane: PortSim.Crane) -> float:
	return 60.0 / (sim.rules.sts_cranes[crane.kind].rate * sim.rules.crane_interference)


## The cranes on `ship`'s apron within its length that reach across it.
static func cranes_for(sim: PortSim, ship: PortSim.Ship) -> Array[PortSim.Crane]:
	var span := ship_cells(sim, ship.kind)
	var rows: int = sim.rules.ship_classes[ship.kind].outreach
	var found: Array[PortSim.Crane] = []
	for crane in sim.cranes:
		if crane.apron == ship.apron and crane.along >= ship.from and crane.along < ship.from + span and _reach(sim, crane) >= rows:
			found.append(crane)
	return found


## Why an STS crane of `kind` can't stand `along` cells into apron `apron`, or "".
static func sts_error(sim: PortSim, apron: int, along: int, kind: String) -> String:
	if apron not in sim.areas.list or sim.areas.list[apron].type != "quay_apron":
		return "STS cranes stand on a quay apron's rails"
	# A crane works over a handover slot, and slots cover whole bays only.
	if along < 0 or along >= _length(sim, apron) / AreaLayout.BAY * AreaLayout.BAY:
		return "STS cranes stand on a quay apron's rails"
	var spots := crane_spots(sim, apron)
	if not spots.is_empty() and along not in spots:
		return "Cranes stand at the berth's crane spots"
	var room := ceili(sim.rules.sts_cranes[kind].width / float(Grid.CELL))
	var near := func(a: int, k: int) -> bool: return a == apron and absi(k - along) < room
	if sim.cranes.any(func(c: PortSim.Crane) -> bool: return near.call(c.apron, c.along)) or sim.crane_orders.any(func(o: Dictionary) -> bool: return o.has("apron") and near.call(o.apron, o.along)):
		return "Too close to another crane"
	return ""


## Where cranes stand on apron `apron`, in cells along it: evenly along a
## berth, by its data; [] for an apron of no berth's length, where they stand anywhere.
static func crane_spots(sim: PortSim, apron: int) -> Array[int]:
	var length := _length(sim, apron)
	var found: Array[int] = []
	for kind: String in sim.rules.berths:
		var berth: Dictionary = sim.rules.berths[kind]
		if berth.length == length:
			for k: int in berth.crane_spots:
				found.append(floori((k + 0.5) * length / berth.crane_spots))
	return found


static func _length(sim: PortSim, apron: int) -> int:
	var area: Dictionary = sim.areas.list[apron]
	return RoadNet.length(area.start, area.end) + 1


## A tractor's speed on the grid, in cells a vehicle second: the data gives
## it in metres.
static func tractor_speed(sim: PortSim) -> float:
	return sim.rules.tractor.speed / Grid.CELL


## One tick of the area flow, after ships: machines work, then vehicles drive.
static func tick(sim: PortSim) -> void:
	_fit_machines(sim)
	for machine: int in sim.machines.tick():
		_machine_done(sim, machine)
	_unpark(sim)
	for vehicle: Vehicle in sim.vehicles.duplicate():
		_drive(sim, vehicle)


## One tick of an apron ship alongside: each of its cranes discharges, and
## once the holds are empty and the cranes idle it sails.
static func work(sim: PortSim, ship: PortSim.Ship) -> void:
	var working := cranes_for(sim, ship)
	if working.is_empty():
		sim._event("A %s is waiting: no crane on its berth reaches %d rows" % [ship.kind, sim.rules.ship_classes[ship.kind].outreach], sim.areas.list[ship.apron].start)
		return
	for crane in working:
		var move_minutes := move_minutes_of(sim, crane)
		if ship.boxes > 0:
			_discharge(sim, crane, ship, move_minutes)
			continue
		if crane.tractor != 0 and _vehicle(sim, crane.tractor).box == 0:
			# Another crane lifted the last import: this one's empty tractor goes back.
			_gone(sim, _vehicle(sim, crane.tractor))
			crane.tractor = 0
			crane.timer = 0.0
		_load(sim, crane, ship, move_minutes)
	if ship.boxes == 0 and working.all(func(c: PortSim.Crane) -> bool: return c.tractor == 0) and _fetchers(sim, ship).is_empty():
		if ship.exports == 0:
			if ship.empties == 0 or _surplus_empty(sim, ship) == 0:
				sim._sail(ship, working.size())
				sim._event("A %s is sailing, fully loaded" % ship.kind, sim.areas.list[ship.apron].start)
		elif _export_box(sim, ship) == 0 and not _exports_coming(sim, sim.areas.list[ship.apron].terminal):
			sim._sail(ship, working.size())
			sim._event("A %s sailed %d exports short: none ready in the yard" % [ship.kind, ship.exports], sim.areas.list[ship.apron].start)


## One crane's tick discharging: a tractor waits in the apron slot below it
## while the crane works its move, then takes the box to an import block.
static func _discharge(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship, move_minutes: float) -> void:
	if crane.tractor == 0 and not _send_tractor(sim, crane, ship):
		return
	crane.timer = minf(crane.timer + SimClock.CALENDAR_MINUTES_PER_TICK, move_minutes)
	var tractor := _vehicle(sim, crane.tractor)
	if crane.timer < move_minutes or tractor.state != "under_crane":
		return
	crane.timer = 0.0
	crane.tractor = 0
	# A barge brings exports down the river, from places it reaches.
	var inland: bool = sim.rules.ship_classes[ship.kind].inland
	var id := sim._new_box("export" if inland else "import", sim.clock.calendar_minutes() + sim.rules.import_dwell_minutes * sim._dwell_factor(), ship.line)
	var here: int = sim.areas.list[ship.apron].terminal
	sim.boxes[id].from = here
	if inland:
		sim.boxes[id].place = sim._pick_place("barge_km")
	var other := _transfer_terminal(sim, ship.line, here) if not inland else 0
	# A share of a line's imports leave on its ship at its other terminal; they go at once.
	if other and sim.rng.randf() < sim.rules.transfers.share:
		sim.boxes[id].to = other
		sim.boxes[id].due = sim.clock.calendar_minutes()
	# A share of a line's boxes go on with it: off its big ships onto its next
	# feeder, or off its feeders onto its next big ship, within the window.
	var onward := tranship_onward(sim, ship) if not inland else ""
	if sim.boxes[id].to == 0 and onward != "" and sim.rng.randf() < sim.rules.lines[ship.line].tranship_share:
		sim.boxes[id].kind = "tranship"
		sim.boxes[id].onward = onward
		sim.boxes[id].due = sim.clock.calendar_minutes() + sim.rules.lines[ship.line].connection_hours * 60.0
		sim.exports += 1
	# Booked to rail by its line's share, only while a rail block has room for
	# it and its place has a rail link, so a port without rail rolls nothing.
	var rail := RailFlow.block_with_room(sim, sim.areas.list[ship.apron].terminal)
	var plugs := _block_for(sim, "reefer", sim.areas.list[ship.apron].terminal) if sim.boxes[id].reefer else 0
	if sim.boxes[id].dg:
		var hazard := _block_for(sim, "dangerous", sim.areas.list[ship.apron].terminal)
		if hazard == 0:
			# Never stacked where it isn't allowed: it stays aboard, unpaid, and the tractor waits for the next box.
			sim._drop_box(id)
			crane.tractor = tractor.id
			ship.boxes -= 1
			sim._event("A dangerous-goods box was shut out: no dangerous-goods block with room in %s" % sim.areas.terminals[sim.areas.list[ship.apron].terminal].name, sim.areas.list[ship.apron].start)
			return
		sim._set_area(tractor, hazard)
	elif rail and sim.boxes[id].kind == "import" and sim.by_rail_to(id) and sim.rng.randf() < sim.rail_share(ship.line):
		sim.boxes[id].rail = true
		sim._set_area(tractor, rail)
	elif plugs:
		sim._set_area(tractor, plugs)
	# Unplugged either way, a reefer without a reefer block goes on like any box.
	elif sim.boxes[id].kind == "tranship":
		var block := _tranship_block(sim, ship, onward)
		if block:
			sim._set_area(tractor, block)
	elif sim.boxes[id].kind == "export":
		var block := _block_for(sim, "export", here)
		if block:
			sim._set_area(tractor, block)
	# Booked to barge by its line's share while barges call at this terminal:
	# it waits in its block for one, and no lorry takes it.
	if sim.boxes[id].kind == "import" and not sim.boxes[id].rail and sim.boxes[id].to == 0 and sim.by_barge_to(id) and barges_call(sim, here) and sim.rng.randf() < sim.barge_share(ship.line):
		sim.boxes[id].barge = true
	if sim.boxes[id].rush and sim.clock.calendar_minutes() > ship.due:
		sim.ledger.post("rush_fines", -sim.rules.special_boxes.rush_fine, sim.areas.list[ship.apron].terminal)
	ship.boxes -= 1
	ship.moves += 1
	sim._moved(sim.boxes[id], ship.line, sim.areas.list[ship.apron].terminal)
	tractor.box = id
	tractor.loaded = true
	_go_to(sim, tractor, tractor.area)


## One crane's tick loading: while the ship has room for more exports than
## are already being fetched, it keeps up to max_fetchers tractors fetching
## them, and lifts each box aboard once its tractor is back beneath it, so
## the crane works while others drive.
static func _load(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship, move_minutes: float) -> void:
	var fetchers := _fetchers(sim, ship)
	var slot := _crane_slot(sim, crane, ship)
	var mine := fetchers.filter(func(v: Vehicle) -> bool: return v.home == slot)
	var wanted := ship.exports if ship.exports > 0 else ship.empties
	if wanted > fetchers.size() and mine.size() < sim.rules.sts_cranes[crane.kind].max_fetchers:
		_send_fetcher(sim, crane, ship)
	if crane.tractor == 0:
		var back := mine.filter(func(v: Vehicle) -> bool: return v.state == "under_crane")
		if back.is_empty():
			return
		crane.tractor = back[0].id
	var tractor := _vehicle(sim, crane.tractor)
	if tractor.state != "under_crane":
		return
	crane.timer += SimClock.CALENDAR_MINUTES_PER_TICK
	if crane.timer < move_minutes:
		return
	crane.timer = 0.0
	crane.tractor = 0
	sim._moved(sim.boxes[tractor.box], ship.line, sim.areas.list[ship.apron].terminal)
	if sim.boxes[tractor.box].kind == "empty":
		ship.empties -= 1
	else:
		ship.exports -= 1
	sim._drop_box(tractor.box)
	ship.moves += 1
	_gone(sim, tractor)


## Sends a tractor from the pool, starting in the apron slot under `crane`,
## to fetch an export from its terminal's export blocks and bring it back.
static func _send_fetcher(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> void:
	if sim._tractors_out() >= sim.tractors:
		return
	var box := _export_box(sim, ship) if ship.exports > 0 else _surplus_empty(sim, ship)
	if box == 0:
		return
	var tractor := Vehicle.new(sim._next_vehicle, "tractor", [_crane_slot(sim, crane, ship)] as Array[Vector2i])
	if not sim.lane_traffic.place(tractor):
		return
	sim._next_vehicle += 1
	tractor.home = tractor.path[0]
	tractor.box = box
	sim._claimed[box] = true
	sim._add_vehicle(tractor)
	_go_to(sim, tractor, _block_of(sim, box))


## The tractors out fetching exports for `ship`: each has its home in the
## apron slot under one of the ship's cranes.
static func _fetchers(sim: PortSim, ship: PortSim.Ship) -> Array[Vehicle]:
	var found: Array[Vehicle] = []
	for crane in cranes_for(sim, ship):
		found.append_array(sim.fetching_to(_crane_slot(sim, crane, ship)))
	return found


## The box `ship` loads next from its terminal's working blocks, or 0: for
## a barge, an import booked to barge; else a transhipment box of its line
## going on by a ship of its size first, then an export; the least buried,
## so loading digs out as few boxes as it can.
static func _export_box(sim: PortSim, ship: PortSim.Ship) -> int:
	var terminal: int = sim.areas.list[ship.apron].terminal
	var group := "feeder" if ship.kind == "feeder" else "mother"
	var inland: bool = sim.rules.ship_classes[ship.kind].inland
	var mine := func(box: int) -> bool: return sim.boxes[box].barge if inland else sim.boxes[box].line == ship.line and sim.boxes[box].onward == group
	for kind: String in (["import"] if inland else ["tranship", "export"]):
		var best := 0
		var fewest := 0
		for block: int in sim.area_stacks:
			if block not in sim.areas.list or sim.areas.list[block].terminal != terminal or sim.areas.idle_reason(block) != "":
				continue
			var stacks: AreaStacks = sim.area_stacks[block]
			for box: int in stacks.of_kind(kind, sim.boxes):
				if box not in sim._claimed and (kind == "export" or mine.call(box)) and (best == 0 or stacks.above(box) < fewest):
					best = box
					fewest = stacks.above(box)
		if best:
			return best
	return 0


## Whether a barge service calls at a berth in `terminal`.
static func barges_call(sim: PortSim, terminal: int) -> bool:
	return sim.contracts.services.any(func(s: Dictionary) -> bool: return sim.rules.ship_classes[s.kind].inland and s.apron in sim.areas.list and sim.areas.list[s.apron].terminal == terminal)


## Where `ship`'s transhipment boxes go on: "feeder" off a big ship, "mother"
## off a feeder, while its line has a service of that size and transhipment
## is unlocked; else "".
static func tranship_onward(sim: PortSim, ship: PortSim.Ship) -> String:
	if sim.lock_error("transhipment") or sim.rules.lines[ship.line].tranship_share <= 0.0:
		return ""
	var onward := "mother" if ship.kind == "feeder" else "feeder"
	var any := sim.contracts.services.any(func(s: Dictionary) -> bool: return s.line == ship.line and (s.kind == "feeder") == (onward == "feeder"))
	return onward if any else ""


## An empty of `ship`'s line in its terminal's working empty blocks that no
## vehicle is coming for, while they hold more than empties.keep of that
## line not yet claimed; else 0.
static func _surplus_empty(sim: PortSim, ship: PortSim.Ship) -> int:
	var terminal: int = sim.areas.list[ship.apron].terminal
	var free: Array[int] = []
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type != "yard_block" or area.terminal != terminal or area.settings.role != "empty" or sim.areas.idle_reason(id) != "" or id not in sim.area_stacks:
			continue
		for box: int in sim.area_stacks[id].of_kind("empty", sim.boxes):
			if box not in sim._claimed and sim.boxes[box].line == ship.line:
				free.append(box)
	return free[0] if free.size() > sim.rules.empties.keep else 0


## The middle cell of the apron slot under `crane`, in the lane nearest the road.
static func _crane_slot(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> Vector2i:
	return sim.areas.layout(ship.apron).slots[crane.along / AreaLayout.BAY][1]


## Puts a tractor from the pool in the apron slot under `crane`, bound for an
## import block of the ship's terminal with room. False when there is no free
## tractor, slot or block yet.
static func _send_tractor(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> bool:
	if sim._tractors_out() >= sim.tractors:
		return false
	var block := _block_for(sim, "import", sim.areas.list[ship.apron].terminal)
	if block == 0:
		sim._event("A ship is waiting: no import yard block with room and a road in its terminal")
		return false
	var tractor := Vehicle.new(sim._next_vehicle, "tractor", [_crane_slot(sim, crane, ship)] as Array[Vector2i])
	if not sim.lane_traffic.place(tractor):
		return false
	sim._next_vehicle += 1
	tractor.state = "under_crane"
	sim._set_area(tractor, block)
	sim._add_vehicle(tractor)
	crane.tractor = tractor.id
	return true


## A yard block other than `except`, of `role` ("" for any), within
## dg_distance cells of `cells`, or 0.
# shortcut: compares bounding boxes, so a 45° block keeps more than the distance; compare cells if players build DG on diagonals.
static func near_yard(sim: PortSim, cells: Array[Vector2i], except: int, role: String) -> int:
	var reach := _bounds(cells).grow(sim.rules.special_boxes.dg_distance)
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if id != except and area.type == "yard_block" and (role == "" or area.settings.role == role) and reach.intersects(_bounds(sim.areas.cells(id))):
			return id
	return 0


## The smallest rectangle of cells holding `cells`.
static func _bounds(cells: Array[Vector2i]) -> Rect2i:
	var low := cells[0]
	var high := cells[0]
	for cell in cells:
		low = low.min(cell)
		high = high.max(cell)
	return Rect2i(low, high - low + Vector2i.ONE)


## Reefers stacked in reefer blocks, on their plugs.
static func plugged_reefers(sim: PortSim) -> int:
	var found := 0
	for id: int in sim.area_stacks:
		if id in sim.areas.list and sim.areas.list[id].settings.get("role") == "reefer":
			found += sim.area_stacks[id].count()
	return found


## Reefers stacked anywhere but a reefer block, off a plug.
static func unplugged_reefers(sim: PortSim) -> int:
	return _unplugged(sim).size()


## The reefer boxes stacked off a plug.
static func _unplugged(sim: PortSim) -> Dictionary:
	var found := {}  # box -> its block's terminal
	for id: int in sim.area_stacks:
		if id in sim.areas.list and sim.areas.list[id].settings.get("role") != "reefer":
			for box: int in sim.area_stacks[id].boxes():
				if sim.boxes[box].reefer:
					found[box] = sim.areas.list[id].terminal
	return found


## Fines the port for each reefer whose plug_minutes off a plug ran out in
## the hour to `now`, so each is fined once by an hourly check.
static func fine_unplugged(sim: PortSim, now: float) -> void:
	var late: float = now - sim.rules.reefers.plug_minutes
	var unplugged := _unplugged(sim)
	for box: int in unplugged:
		if sim.boxes[box].in > late - 60.0 and sim.boxes[box].in <= late:
			sim.ledger.post("reefer_fines", -sim.rules.reefers.fine, unplugged[box])


## Each transhipment box whose connection window ran out by `now` misses its
## ship: its line is fined and thinks less of the port, and the box waits a
## further window for the next one. Returns how many missed.
static func miss_connections(sim: PortSim, now: float) -> int:
	var missed := 0
	for id: int in sim.boxes:
		var box: Dictionary = sim.boxes[id]
		if box.kind != "tranship" or box.due > now:
			continue
		sim.ledger.post("connection_fines", -sim.rules.transhipment.missed_fine, box.from)
		var cancelled := sim.contracts.penalise(box.line, sim.rules.transhipment.missed_reputation)
		if cancelled:
			sim._event(cancelled)
		box.due += sim.rules.lines[box.line].connection_hours * 60.0
		missed += 1
	return missed


## The first yard block of `role` in `terminal` that works and has room for
## one more box than is already on its way to it, counting tractors waiting
## under a crane for a box bound for it, or 0.
static func _block_for(sim: PortSim, role: String, terminal: int) -> int:
	var found := _blocks_with_room(sim, role, terminal)
	return found[0] if not found.is_empty() else 0


## `terminal`'s working yard blocks of `role` with room for one more box.
static func _blocks_with_room(sim: PortSim, role: String, terminal: int) -> Array[int]:
	var found: Array[int] = []
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type != "yard_block" or area.terminal != terminal or area.settings.role != role or sim.areas.idle_reason(id) != "" or RailFlow.is_rail_block(sim, id):
			continue
		# Boxes on their way, and tractors under a crane waiting for a box bound here.
		var coming := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.area == id and (v.loaded or v.state == "under_crane")).size()
		if _stacks(sim, id).room() > coming:
			found.append(id)
	return found


## The transhipment block with room in `ship`'s terminal nearest the berths
## of its line's `onward` services, where the box goes on; or 0.
static func _tranship_block(sim: PortSim, ship: PortSim.Ship, onward: String) -> int:
	var berths: Array[Vector2i] = []
	for service: Dictionary in sim.contracts.services:
		if service.line == ship.line and (service.kind == "feeder") == (onward == "feeder") and service.apron in sim.areas.list:
			berths.append(sim.areas.list[service.apron].start)
	var best := 0
	var nearest := 0
	for id in _blocks_with_room(sim, "tranship", sim.areas.list[ship.apron].terminal):
		var start: Vector2i = sim.areas.list[id].start
		var distance: int = berths.map(func(b: Vector2i) -> int: return absi(b.x - start.x) + absi(b.y - start.y)).min() if not berths.is_empty() else 0
		if best == 0 or distance < nearest:
			best = id
			nearest = distance
	return best


## Sends a lorry in from the site entry for the import box due out longest,
## whichever block holds it, to its terminal's gate first; false when no box
## is due or the way in is busy.
static func dispatch_import_lorry(sim: PortSim) -> bool:
	var now := sim.clock.calendar_minutes()
	var box := 0
	var terminal := 0
	for block: int in sim.area_stacks:
		if block not in sim.areas.list or sim.areas.idle_reason(block) != "" or RailFlow.is_rail_block(sim, block):
			continue
		if not _has_gate(sim, sim.areas.list[block].terminal):
			sim._event("Lorries can't come in: build a gate in %s" % sim.areas.terminals[sim.areas.list[block].terminal].name)
			continue
		# Imports come soonest due first, so the block's first unclaimed one is its best.
		for id: int in sim.area_stacks[block].of_kind("import", sim.boxes):
			if id in sim._claimed or sim.boxes[id].barge:
				continue
			if sim.boxes[id].due <= now and (box == 0 or sim.boxes[id].due < sim.boxes[box].due):
				box = id
				terminal = sim.areas.list[block].terminal
			break
	if box == 0:
		return false
	var entry := _entry_cell(sim)
	if entry == Grid.NONE:
		return false
	var gate := _gate_of(sim, terminal, entry)
	if not can_book(sim, gate):
		return false
	var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector2i])
	sim.lane_traffic.place(lorry)
	sim._next_vehicle += 1
	lorry.box = box
	sim._claimed[box] = true
	sim._add_vehicle(lorry)
	_to_gate(sim, lorry, gate)
	return true


## Sends a lorry in with the empty due back soonest, to a terminal with room
## in its empty blocks, else to any terminal with a gate, where it is turned
## away; false when none is due, no terminal has a gate, or the way in is busy.
static func dispatch_empty_lorry(sim: PortSim) -> bool:
	if sim.returning.is_empty() or sim.returning[0].at > sim.clock.calendar_minutes():
		return false
	var gated: Array = sim.areas.terminals.keys().filter(func(t: int) -> bool: return _has_gate(sim, t))
	if gated.is_empty():
		return false
	var roomy: Array = gated.filter(func(t: int) -> bool: return _block_for(sim, "empty", t) != 0)
	var terminal: int = roomy[0] if not roomy.is_empty() else gated[0]
	var entry := _entry_cell(sim)
	if entry == Grid.NONE:
		return false
	var gate := _gate_of(sim, terminal, entry)
	if not can_book(sim, gate):
		return false
	var back: Dictionary = sim.returning.pop_front()
	var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector2i])
	sim.lane_traffic.place(lorry)
	sim._next_vehicle += 1
	lorry.box = sim._new_empty(back.line, back.teu)
	lorry.loaded = true
	sim._add_vehicle(lorry)
	_to_gate(sim, lorry, gate)
	return true


## Sends a lorry in from the site entry to a terminal with a gate whose
## export blocks have room for more than the export lorries already on their
## way: with an export packed in an empty it took out, once one is due back;
## else, while calls want more exports than the port holds, to take out an
## empty to pack, or with an export packed in its own empty when the port
## has none. False when nothing is due or wanted, there is no room, or the
## way in is busy.
static func dispatch_export_lorry(sim: PortSim) -> bool:
	if not sim.transfers.is_empty() and _transfer_in(sim):
		return true
	var packed: bool = not sim.stuffing.is_empty() and sim.stuffing[0].at <= sim.clock.calendar_minutes()
	if not packed and export_demand(sim) <= 0:
		return false
	for terminal: int in sim.areas.terminals:
		if not _has_gate(sim, terminal) or _export_room(sim, terminal) <= 0:
			continue
		var entry := _entry_cell(sim)
		if entry == Grid.NONE:
			return false
		var gate := _gate_of(sim, terminal, entry)
		if not can_book(sim, gate):
			continue
		var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector2i])
		sim.lane_traffic.place(lorry)
		sim._next_vehicle += 1
		var empty := 0 if packed else _free_empty(sim, terminal)
		if empty:
			lorry.box = empty
			sim._claimed[empty] = true
		else:
			if packed:
				sim.stuffing.pop_front()
			# shortcut: an export is booked on no line until a ship loads it, as on tiles.
			lorry.box = sim._new_box("export", 0.0, "")
			lorry.loaded = true
		sim._add_vehicle(lorry)
		_to_gate(sim, lorry, gate)
		return true
	return false


## Sends a lorry in with the first box moving between terminals, to the
## terminal it is bound for, once that terminal's gate and export blocks
## can take it; false when they can't yet or the way in is busy.
static func _transfer_in(sim: PortSim) -> bool:
	var terminal: int = sim.transfers[0].terminal
	if terminal not in sim.areas.terminals or not _has_gate(sim, terminal) or _export_room(sim, terminal) <= 0:
		return false
	var entry := _entry_cell(sim)
	if entry == Grid.NONE:
		return false
	var gate := _gate_of(sim, terminal, entry)
	if not can_book(sim, gate):
		return false
	var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector2i])
	sim.lane_traffic.place(lorry)
	sim._next_vehicle += 1
	lorry.box = sim.transfers.pop_front().box
	lorry.loaded = true
	sim._add_vehicle(lorry)
	_to_gate(sim, lorry, gate)
	return true


## The other terminal `line` has a service at, besides `here`, or 0: the
## one of its lowest service id.
static func _transfer_terminal(sim: PortSim, line: String, here: int) -> int:
	for service: Dictionary in sim.contracts.services:
		if service.line == line and service.apron in sim.areas.list:
			var terminal: int = sim.areas.list[service.apron].terminal
			if terminal != 0 and terminal != here:
				return terminal
	return 0


## An empty in `terminal`'s working empty blocks that no vehicle is coming
## for, or 0.
static func _free_empty(sim: PortSim, terminal: int) -> int:
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type != "yard_block" or area.terminal != terminal or area.settings.role != "empty" or sim.areas.idle_reason(id) != "" or id not in sim.area_stacks:
			continue
		for box: int in sim.area_stacks[id].of_kind("empty", sim.boxes):
			if box not in sim._claimed:
				return box
	return 0


## Exports wanted and not yet in the port: room on ships in port, and on the
## calls of agreed services due within export_lead_hours, less every export
## box already in a yard, on a vehicle or on its way, and every empty being
## packed or a lorry is coming to take out.
# shortcut: demand is port-wide; split it per terminal when contracts belong to one (M8 step 3).
static func export_demand(sim: PortSim) -> int:
	var week_now := fposmod(sim.clock.calendar_minutes(), Contracts.MINUTES_PER_WEEK)
	var wanted := 0
	for ship: PortSim.Ship in sim.ships:
		if ship.state != PortSim.Ship.State.LEAVING:
			wanted += ship.exports
	for service: Dictionary in sim.contracts.services:
		var until := fposmod(service.start - week_now, Contracts.MINUTES_PER_WEEK)
		if until > 0.0 and until <= sim.rules.export_lead_hours * 60.0:
			wanted += sim.rules.ship_classes[service.kind].export_moves
	return wanted - sim.exports - sim.stuffing.size() - _lorries(sim).collecting


## The lorries export demand and room count, in one pass over the vehicles:
## {"collecting": lorries with an empty from the yard, on their way to it or
## out with it (one never stacked was turned away), "exports": terminal ->
## loaded export lorries bound for it}. Kept until the tick, or the vehicles,
## change: both are asked for every tick and scanning was most of a tick's
## export dispatch (docs/perf.md).
static func _lorries(sim: PortSim) -> Dictionary:
	var key := [sim.clock.ticks, sim._next_vehicle, sim.vehicles.size()]
	if sim._lorries_for == key:
		return sim._lorries
	var collecting := 0
	var exports := {}
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.kind != "lorry" or vehicle.box not in sim.boxes:
			continue
		var box: Dictionary = sim.boxes[vehicle.box]
		if box.kind == "empty" and box.in >= 0.0:
			collecting += 1
		elif vehicle.loaded and box.kind == "export" and vehicle.area in sim.areas.list:
			var terminal: int = sim.areas.list[vehicle.area].terminal
			exports[terminal] = exports.get(terminal, 0) + 1
	sim._lorries = {"collecting": collecting, "exports": exports}
	sim._lorries_for = key
	return sim._lorries


## Whether exports are on their way into `terminal`, or can still be sent:
## wanted, with a gate to come in by and room in its export blocks.
static func _exports_coming(sim: PortSim, terminal: int) -> bool:
	if export_demand(sim) > 0 and _has_gate(sim, terminal) and _export_room(sim, terminal) > 0:
		return true
	return sim.vehicles.any(func(v: Vehicle) -> bool: return v.kind == "lorry" and v.loaded and sim.boxes[v.box].kind == "export" and v.area in sim.areas.list and sim.areas.list[v.area].terminal == terminal)


## Room left in `terminal`'s working export blocks, less the export lorries
## bound for it.
static func _export_room(sim: PortSim, terminal: int) -> int:
	var room := 0
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type == "yard_block" and area.terminal == terminal and area.settings.role == "export" and sim.areas.idle_reason(id) == "":
			room += _stacks(sim, id).room()
	return room - _lorries(sim).exports.get(terminal, 0)


## A free lane cell at the site entry heading into the site, or NONE.
static func _entry_cell(sim: PortSim) -> Vector2i:
	for cell in _edge_cells(sim):
		if sim.lane_traffic.holder(cell) == 0 and sim.lanes.steps_at(cell).any(func(step: Vector2i) -> bool: return step.x < 0):
			return cell
	return Grid.NONE


## A lane cell at the site entry leaving the site, or NONE.
static func _exit_cell(sim: PortSim) -> Vector2i:
	for cell in _edge_cells(sim):
		var steps := sim.lanes.steps_at(cell)
		if not steps.is_empty() and not steps.any(func(step: Vector2i) -> bool: return step.x < 0):
			return cell
	return Grid.NONE


## Cells on the site's east edge near the entry, where the highway's lanes meet the roads.
static func _edge_cells(sim: PortSim) -> Array[Vector2i]:
	var entry := sim.site_entry()
	var found: Array[Vector2i] = []
	for dy in range(-8, 9):
		found.append(entry + Vector2i(0, dy))
	return found


## Minutes gate `gate` takes to check one lorry, from its level.
static func gate_minutes(sim: PortSim, gate: int) -> float:
	return sim.rules.gate_levels[sim.areas.list[gate].settings.level].minutes


## Lorries an hour gate `gate` can check: a booth per lane, each taking its level's minutes.
static func gate_throughput(sim: PortSim, gate: int) -> float:
	return sim.areas.layout(gate).lanes.size() * 60.0 / gate_minutes(sim, gate)


## The working gates of `terminal`.
static func _gates(sim: PortSim, terminal: int) -> Array[int]:
	return sim.areas.working_gates(terminal)


static func _has_gate(sim: PortSim, terminal: int) -> bool:
	return not _gates(sim, terminal).is_empty()


## The working gate of `terminal` a lorry at `from` gets through soonest,
## of those it has a route to: minutes to drive there, by grid distance,
## plus the lorries already bound for it times the minutes each takes at a
## booth over its lanes. Lorries check in and out on their side of the road,
## and spread over the gates as one jams. The first gate when none can be
## reached, as the lorry then waits for a road; 0 when the terminal has none.
# shortcut: drive minutes by grid distance, not route length, which cost 12 route searches a lorry; use route lengths if detours mislead the choice.
static func _gate_of(sim: PortSim, terminal: int, from: Vector2i) -> int:
	var gates := _gates(sim, terminal).duplicate()
	while not gates.is_empty():
		var best := 0
		var soonest := INF
		for gate: int in gates:
			# A vehicle second is a calendar minute, so driving and queueing add up.
			var drive: float = RoadNet.length(from, _buffer_start(sim, gate)) / (sim.rules.lorry_speed / Grid.CELL)
			var minutes: float = drive + sim.lorries_bound_for(gate) * gate_minutes(sim, gate) / sim.areas.layout(gate).lanes.size()
			if best == 0 or minutes < soonest:
				best = gate
				soonest = minutes
		if not sim.lanes.route(from, _buffer_start(sim, best), true).is_empty():
			return best
		gates.erase(best)
	return _gates(sim, terminal)[0] if _has_gate(sim, terminal) else 0


## The yard block holding `box`, or 0.
static func _block_of(sim: PortSim, box: int) -> int:
	for block: int in sim.area_stacks:
		if sim.area_stacks[block].boxes().has(box):
			return block
	return 0


## Sends inbound lorry `lorry` to `gate`, or, while the lorries already bound
## for the gate fill its slots and buffer or others are in a park for it, to
## the gate's terminal's truck park with the most room, to wait off the road
## in turn (queueing at the park when it is full, so the park feeds the gate
## first come, first served); with no park it queues on the road to the gate.
static func _to_gate(sim: PortSim, lorry: Vehicle, gate: int) -> void:
	if sim.areas.list[gate].settings.slots_per_hour > 0:
		var hour := _free_hour(sim, gate)
		sim.bookings[gate][hour] = sim.bookings[gate].get(hour, 0) + 1
		lorry.booked = hour * 60.0
	var park := _park_for(sim, sim.areas.list[gate].terminal)
	var early := lorry.booked > sim.clock.calendar_minutes()
	if park and (early or _gate_full(sim, gate) or sim.vehicles.any(func(v: Vehicle) -> bool: return v.area == park)):
		_go_to(sim, lorry, park)
	else:
		_go_to(sim, lorry, gate)


## The first hour of the calendar, from this one, that `gate` has a booking
## left in, forgetting hours gone by; -1 when it takes no bookings.
static func _free_hour(sim: PortSim, gate: int) -> int:
	var slots: int = sim.areas.list[gate].settings.slots_per_hour
	if slots == 0:
		return -1
	var now := floori(sim.clock.calendar_minutes() / 60.0)
	var booked: Dictionary = sim.bookings.get_or_add(gate, {})
	for hour: int in booked.keys():
		if hour < now:
			booked.erase(hour)
	var hour := now
	while booked.get(hour, 0) >= slots:
		hour += 1
	return hour


## Whether a lorry can be sent to `gate` now: it takes walk-ins, or has a
## booking left this hour or the next, so lorries come at most an hour early.
static func can_book(sim: PortSim, gate: int) -> bool:
	return _free_hour(sim, gate) <= floori(sim.clock.calendar_minutes() / 60.0) + 1


## Whether the lorries coming in through `gate` fill its slots and buffer.
static func _gate_full(sim: PortSim, gate: int) -> bool:
	var room: int = sim.areas.layout(gate).slots.size() + sim.areas.layout(gate).buffer.size() / AreaLayout.BAY
	var coming := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.area == gate and v.gate_in < 0.0 and v.state in ["arriving", "queued", "to_slot", "at_gate", "early"]).size()
	return coming >= room


## The working truck park of `terminal` with the most slots no lorry has
## taken or is coming for, or 0 when it has none.
static func _park_for(sim: PortSim, terminal: int) -> int:
	var best := 0
	var most := -INF
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if sim.areas.kind_of(area) != "parking" or area.terminal != terminal or sim.areas.idle_reason(id) != "":
			continue
		var room: float = sim.areas.layout(id).slots.size() - sim.vehicles.filter(func(v: Vehicle) -> bool: return v.area == id).size()
		if room > most:
			best = id
			most = room
	return best


## Sends parked lorries on to their terminal's gate, first parked first, while
## the gate has room for them.
static func _unpark(sim: PortSim) -> void:
	for lorry: Vehicle in sim.vehicles:
		if lorry.state != "parked":
			continue
		var park := lorry.area
		var gate := _gate_of(sim, sim.areas.list[park].terminal, lorry.path[int(lorry.t)])
		if gate == 0 or _gate_full(sim, gate) or lorry.booked > sim.clock.calendar_minutes():
			continue
		sim.handovers.leave(park, lorry.id)
		_promote(sim, park)
		_go_to(sim, lorry, gate)


## Sends `vehicle` to the start of `area`'s buffer strip. It books a
## handover slot only on getting there, so slots go in the order vehicles
## arrive; with none free it waits at the start of the strip, and others
## queue behind it on the road. Vehicles leave slots back into the strip
## ahead of it, so waiting never blocks the way out.
static func _go_to(sim: PortSim, vehicle: Vehicle, area: int) -> void:
	sim._set_area(vehicle, area)
	vehicle.slot = -1
	_head(sim, vehicle, _buffer_start(sim, area), "arriving")


## The first cell of `area`'s buffer strip in driving order, where vehicles come in.
static func _buffer_start(sim: PortSim, area: int) -> Vector2i:
	var buffer: Array = sim.areas.layout(area).buffer
	return buffer[0] if sim.lanes.flow_of(area) > 0 else buffer[-1]


## `vehicle` reached the start of its area's buffer strip: it books a slot.
static func _book(sim: PortSim, vehicle: Vehicle) -> void:
	if sim.handovers.arrive(vehicle.area, vehicle.id) == "slot":
		_head_to_slot(sim, vehicle)
	else:
		vehicle.state = "queued"


static func _head_to_slot(sim: PortSim, vehicle: Vehicle) -> void:
	vehicle.slot = sim.handovers.slot_of(vehicle.area, vehicle.id)
	var slot: Array = sim.areas.layout(vehicle.area).slots[vehicle.slot]
	_head(sim, vehicle, slot[1], "to_slot")


## The last cell of `area`'s buffer strip in driving order, beside its way out.
static func _buffer_end(sim: PortSim, area: int) -> Vector2i:
	var buffer: Array = sim.areas.layout(area).buffer
	return buffer[-1] if sim.lanes.flow_of(area) > 0 else buffer[0]


## Sets `vehicle` driving from where it stands to `to`, in `state` once there.
## With no route yet it waits where it is and tries again each tick.
static func _head(sim: PortSim, vehicle: Vehicle, to: Vector2i, state: String) -> void:
	var here := vehicle.path[int(vehicle.t)]
	var route := sim.lanes.route(here, to, vehicle.kind == "lorry")
	var new_path: Array[Vector2i] = []
	if not route.is_empty():
		new_path.assign(route)
	else:
		new_path.append(here)

	vehicle.path = new_path
	vehicle.t = 0.0
	vehicle.prev_t = 0.0
	vehicle.state = state if not route.is_empty() else "no_route:" + state
	vehicle.target = to


static func _speed(sim: PortSim, vehicle: Vehicle) -> float:
	return (sim.rules.lorry_speed / Grid.CELL) if vehicle.kind == "lorry" else tractor_speed(sim)


static func _drive(sim: PortSim, vehicle: Vehicle) -> void:
	if vehicle.state.begins_with("no_route:"):
		_head(sim, vehicle, vehicle.target, vehicle.state.trim_prefix("no_route:"))
		return
	if vehicle.state == "at_gate":
		vehicle.timer -= SimClock.CALENDAR_MINUTES_PER_TICK
		if vehicle.timer <= 0.0:
			_gate_done(sim, vehicle)
		return
	if vehicle.state == "early":
		if vehicle.booked <= sim.clock.calendar_minutes():
			_arrived(sim, vehicle)
		return
	if vehicle.state not in ["arriving", "to_slot", "returning", "leaving", "to_crane"]:
		return
	if not sim.lane_traffic.advance(vehicle, _speed(sim, vehicle)):
		_unstick(sim, vehicle)
		return
	match vehicle.state:
		"arriving":
			_book(sim, vehicle)
		"to_slot":
			_arrived(sim, vehicle)
		"returning":
			_gone(sim, vehicle)
		"to_crane":
			vehicle.state = "under_crane"
		"leaving":
			if vehicle.loaded:
				if sim.boxes[vehicle.box].kind == "import" and sim.boxes[vehicle.box].to:
					sim._transfer_out(vehicle.box)
					_gone(sim, vehicle)
					return
				if sim.boxes[vehicle.box].kind == "import":
					sim.delivered += 1
					sim._import_left(vehicle.box)
				# An empty that was stacked left with an exporter; one never stacked was turned away.
				elif sim.boxes[vehicle.box].kind == "empty" and sim.boxes[vehicle.box].in >= 0.0:
					sim._empty_collected(vehicle.box)
				sim._drop_box(vehicle.box)
			_gone(sim, vehicle)


## The safety valve for jams, as on tiles: a lorry stuck for twice the
## give-up time leaves with whatever it carries, paying nothing, and its
## place in any queue goes to the next. Tractors keep waiting.
static func _unstick(sim: PortSim, vehicle: Vehicle) -> void:
	if vehicle.kind != "lorry" or vehicle.waited < roundi(sim.rules.give_up_seconds / SimClock.TICK_SECONDS) * 2:
		return
	if vehicle.area in sim.areas.list:
		sim.handovers.drop(vehicle.area, vehicle.id)
		_promote(sim, vehicle.area)
	if vehicle.loaded:
		sim._drop_box(vehicle.box)
	elif vehicle.box != 0:
		sim._claimed.erase(vehicle.box)
	var at := Vector2i(vehicle.position(1.0).round())
	_gone(sim, vehicle)
	sim.gave_up += 1
	sim._event("A lorry gave up on a traffic jam and left", at)


static func _gone(sim: PortSim, vehicle: Vehicle) -> void:
	sim._drop_vehicle(vehicle)


## A vehicle reached its handover slot: at a gate it is checked for the gate
## time, which starts a lorry's turn on the way in and ends it on the way
## out; at a yard block a machine is asked for.
static func _arrived(sim: PortSim, vehicle: Vehicle) -> void:
	if sim.areas.kind_of(sim.areas.list[vehicle.area]) == "parking":
		vehicle.state = "parked"
		return
	if sim.areas.kind_of(sim.areas.list[vehicle.area]) != "gate":
		vehicle.state = "handling"
		_start_handling(sim, vehicle)
		return
	vehicle.state = "at_gate"
	vehicle.timer = gate_minutes(sim, vehicle.area)
	var now := sim.clock.calendar_minutes()
	if vehicle.gate_in < 0.0 and vehicle.booked > now:
		# Early for its booking, with no park to wait in: it waits in the booth.
		vehicle.state = "early"
		return
	if vehicle.gate_in < 0.0:
		vehicle.gate_in = now
		return
	sim.turn_times.append(now - vehicle.gate_in)
	var by_terminal: Array = sim.terminal_turns.get_or_add(sim.areas.list[vehicle.area].terminal, [])
	by_terminal.append(now - vehicle.gate_in)
	if by_terminal.size() > 50:
		by_terminal.pop_front()
	sim.year.turns += 1
	sim.year.turn_minutes += now - vehicle.gate_in
	if sim.turn_times.size() > 50:
		sim.turn_times.pop_front()
	vehicle.gate_in = -1.0


## Done at the gate: on the way in (its turn clock running) a lorry heads for
## an export block with its box, or the block holding the box it collects;
## on the way out it heads for the site exit.
static func _gate_done(sim: PortSim, vehicle: Vehicle) -> void:
	var gate := vehicle.area
	sim.handovers.leave(gate, vehicle.id)
	_promote(sim, gate)
	if vehicle.gate_in < 0.0:
		sim._set_area(vehicle, 0)
		vehicle.slot = -1
		_head(sim, vehicle, _exit_cell(sim), "leaving")
	elif vehicle.loaded:
		var box: Dictionary = sim.boxes[vehicle.box]
		var terminal: int = sim.areas.list[gate].terminal
		var block := _block_for(sim, "reefer", terminal) if box.reefer else 0
		if box.kind == "empty":
			block = _block_for(sim, "empty", terminal)
		elif box.dg:
			block = _block_for(sim, "dangerous", terminal)
		elif block == 0:
			block = _block_for(sim, "export", terminal)
		if block:
			_go_to(sim, vehicle, block)
		else:
			# Its blocks filled while it queued, or it has none: it takes its box away.
			if box.kind == "empty":
				sim._event("An empty of %s was turned away: no room in an empty block in %s" % [sim.contracts.name_of(box.line), sim.areas.terminals[terminal].name], sim.areas.list[gate].start)
				sim._event_if(sim.contracts.penalise(box.line, sim.rules.empties.refused))
			vehicle.gate_in = -1.0
			_go_out(sim, vehicle, 0)
	else:
		_go_to(sim, vehicle, _block_of(sim, vehicle.box))


## Gives the block's machine `vehicle`'s job: a tractor's box onto a stack,
## or a lorry's box off its stack, moving any boxes above it first. With
## every machine busy, the vehicle waits in its slot and asks again when one
## finishes.
static func _start_handling(sim: PortSim, vehicle: Vehicle) -> void:
	var stacks := _stacks(sim, vehicle.area)
	var layout := sim.areas.layout(vehicle.area)
	for id: int in sim.machines.list:
		var machine: Dictionary = sim.machines.list[id]
		# A machine done this tick is still busy until its job is booked off.
		if machine.area != vehicle.area or id in sim.machine_jobs:
			continue
		# A yard block has one slot per bay, so a slot's index is its bay.
		if vehicle.loaded:
			var position := stacks.place_spot(sim.boxes[vehicle.box].teu)
			if position < 0:
				return
			sim.machines.give(id, vehicle.slot, layout.stacks[position].bay)
			sim.machine_jobs[id] = {"vehicle": vehicle.id, "position": position}
		else:
			var bay: int = layout.stacks[stacks.position_of(vehicle.box)].bay
			var rehandles := stacks.take(vehicle.box)
			if rehandles < 0:
				return
			sim.machines.give(id, bay, vehicle.slot, rehandles)
			sim.machine_jobs[id] = {"vehicle": vehicle.id, "position": -1}
		vehicle.state = "handled"
		return


## A machine finished: a tractor's box goes on its stack and the tractor
## heads back to the pool; a lorry has its box and heads out through the
## gate. The next in line gets the slot, and waiting vehicles ask again.
static func _machine_done(sim: PortSim, machine: int) -> void:
	if sim.machine_jobs[machine].has("train"):
		RailFlow.job_done(sim, machine)
		return
	var job: Dictionary = sim.machine_jobs[machine]
	sim.machine_jobs.erase(machine)
	var vehicle := _vehicle(sim, job.vehicle)
	if vehicle == null:
		return  # scrapped with its area while the machine worked
	var block := vehicle.area
	var stacks := _stacks(sim, block)
	sim.handovers.leave(block, vehicle.id)
	if job.position >= 0:
		var teu: int = sim.boxes[vehicle.box].teu
		var position: int = job.position if stacks.fits(job.position, teu) else stacks.place_spot(teu)
		stacks.place_at(position, vehicle.box, teu)
		sim.boxes[vehicle.box].in = sim.clock.calendar_minutes()
		vehicle.box = 0
		vehicle.loaded = false
		if vehicle.kind == "lorry":
			# An export delivered, as on tiles; out through the gate.
			sim.delivered += 1
			_go_out(sim, vehicle, sim.areas.list[block].terminal)
		else:
			sim._set_area(vehicle, 0)
			vehicle.slot = -1
			_head(sim, vehicle, _buffer_end(sim, block), "returning")
	elif vehicle.kind == "tractor":
		# An export fetched for a crane: back to the slot under it.
		sim._claimed.erase(vehicle.box)
		vehicle.loaded = true
		sim._set_area(vehicle, 0)
		vehicle.slot = -1
		_head(sim, vehicle, vehicle.home, "to_crane")
	else:
		if sim.boxes[vehicle.box].kind == "import":
			sim.dwell_times.append(sim.clock.calendar_minutes() - sim.boxes[vehicle.box].in)
			if sim.dwell_times.size() > 50:
				sim.dwell_times.pop_front()
		sim._claimed.erase(vehicle.box)
		vehicle.loaded = true
		_go_out(sim, vehicle, sim.areas.list[block].terminal)
	_promote(sim, block)
	_retry_handling(sim, block)


## Vehicles waiting in `block`'s slots for a machine ask again.
static func _retry_handling(sim: PortSim, block: int) -> void:
	for other: Vehicle in sim.vehicles:
		if other.area == block and other.state == "handling":
			_start_handling(sim, other)


## Sends a lorry out through `terminal`'s gate, or straight to the site
## exit when there is no gate to pass.
static func _go_out(sim: PortSim, vehicle: Vehicle, terminal: int) -> void:
	var gate := _gate_of(sim, terminal, vehicle.path[int(vehicle.t)]) if terminal else 0
	if gate:
		_go_to(sim, vehicle, gate)
		return
	sim._set_area(vehicle, 0)
	vehicle.slot = -1
	_head(sim, vehicle, _exit_cell(sim), "leaving")


## Sends the vehicles just given a slot at `area` on to it.
static func _promote(sim: PortSim, area: int) -> void:
	for waiting: Vehicle in sim.vehicles:
		if waiting.area == area and waiting.slot < 0 and sim.handovers.slot_of(area, waiting.id) >= 0:
			_head_to_slot(sim, waiting)


## Gives each yard block the machines its gear and size call for, adding
## idle ones as it grows, and drops the machines of blocks that have gone.
static func _fit_machines(sim: PortSim) -> void:
	if sim._machines_fit_for == sim.areas.version:
		return
	sim._machines_fit_for = sim.areas.version
	for id: int in sim.machines.list.keys():
		var area: int = sim.machines.list[id].area
		if area not in sim.areas.list and sim.machines.list[id].job.is_empty():
			sim.machines.list.erase(id)
	for area: int in sim.areas.list:
		if sim.areas.list[area].type != "yard_block":
			continue
		var gear: String = sim.areas.list[area].settings.gear
		# Machines of the gear the block had go once idle; until the busy ones
		# have finished their box, fit again next tick.
		for id: int in sim.machines.list.keys():
			var machine: Dictionary = sim.machines.list[id]
			if machine.area != area or machine.gear == gear:
				continue
			if id in sim.machine_jobs:
				sim._machines_fit_for = -1
			else:
				sim.machines.list.erase(id)
		var bays: int = sim.areas.layout(area).slots.size()
		var have := sim.machines.list.values().filter(func(m: Dictionary) -> bool: return m.area == area and m.gear == gear).size()
		var missing := sim.machines.count_for(gear, bays) - have
		for i in missing:
			sim.machines.add(area, gear, 0)
		if missing > 0:
			# Vehicles waiting in the block's slots ask the new machines.
			for other: Vehicle in sim.vehicles:
				if other.area == area and other.state == "handling":
					_start_handling(sim, other)
		if area in sim.area_stacks:
			sim.area_stacks[area].set_tiers(sim.rules.yard_gear[gear].tiers)


## Takes away area `id` and everything working there: boxes stacked in it
## are lost, vehicles bound for it are scrapped with their loads, its
## machines go, a ship alongside sails at once and is gone, one coming in
## turns back to anchorage, and its cranes come down.
static func remove(sim: PortSim, id: int) -> void:
	var lost := 0
	if id in sim.area_stacks:
		for box: int in sim.area_stacks[id].boxes():
			sim._drop_box(box)
			lost += 1
		sim.area_stacks.erase(id)
	var cells := sim.areas.cells(id)
	for vehicle: Vehicle in sim.vehicles.duplicate():
		# Bound for the area, or fetching an export for a crane on it.
		if vehicle.area == id or vehicle.home in cells:
			if vehicle.loaded:
				sim._drop_box(vehicle.box)
				lost += 1
			elif vehicle.box != 0:
				sim._claimed.erase(vehicle.box)
			if vehicle.area != id and vehicle.area in sim.areas.list:
				sim.handovers.drop(vehicle.area, vehicle.id)
				_promote(sim, vehicle.area)
			sim._drop_vehicle(vehicle)
	for machine: int in sim.machines.list.keys():
		if sim.machines.list[machine].area == id:
			sim.machines.list.erase(machine)
			sim.machine_jobs.erase(machine)
	for ship: PortSim.Ship in sim.ships.duplicate():
		if ship.apron != id:
			continue
		if ship.state == PortSim.Ship.State.ARRIVING:
			ship.state = PortSim.Ship.State.ANCHORED
			ship.apron = 0
			ship.path.clear()
			Marine.release(ship)
			ship.sail = 0.0
			ship.prev_sail = 0.0
			continue
		if ship.state == PortSim.Ship.State.WORKING:
			sim._sail(ship, cranes_for(sim, ship).size())
			sim._event("A %s sailed early: its quay apron was removed" % ship.kind)
		sim.ships.erase(ship)
		sim._departures += 1
	for crane: PortSim.Crane in sim.cranes.duplicate():
		if crane.apron == id:
			var tractor := _vehicle(sim, crane.tractor)
			if tractor:
				sim._drop_vehicle(tractor)
			sim.cranes.erase(crane)
	lost += RailFlow.forget(sim, id)
	sim.handovers.forget(id)
	sim.areas.remove(id)
	if lost:
		sim._event("Removing the area lost %d boxes" % lost)


## The siding of RMG block `block`: the cells of the row just behind it,
## when track runs along all of it; [] otherwise. A wagon stands at each bay.
static func siding(sim: PortSim, block: int) -> Array[Vector2i]:
	var area: Dictionary = sim.areas.list[block]
	var found: Array[Vector2i] = []
	if area.type != "yard_block" or area.settings.gear != "rmg":
		return found
	var behind := sim.areas.depth_of(area)
	var along: Vector2i = (area.end - area.start).sign()
	for k in RoadNet.length(area.start, area.end) + 1:
		var cell: Vector2i = area.start + along * k + area.out * behind
		if sim.rails.segment_at(cell) == 0:
			return [] as Array[Vector2i]
		found.append(cell)
	return found


## Area `area`'s stacks, made empty the first time it is asked for.
static func _stacks(sim: PortSim, area: int) -> AreaStacks:
	if area not in sim.area_stacks:
		var gear: String = sim.areas.list[area].settings.gear
		sim.area_stacks[area] = AreaStacks.new(sim.areas.layout(area).stacks.size(), sim.rules.yard_gear[gear].tiers)
	return sim.area_stacks[area]


static func _vehicle(sim: PortSim, id: int) -> Vehicle:
	return sim.vehicle_by_id(id)


## The box at grid cell `cell`: one on a vehicle there, else the top box of
## a stack covering it; 0 for none. For picking a box to follow.
static func box_at(sim: PortSim, cell: Vector2i) -> int:
	for vehicle in sim.vehicles:
		if vehicle.box != 0 and vehicle.box in sim.boxes and Vector2i(vehicle.position(1.0).round()) == cell:
			return vehicle.box
	for area: int in sim.area_stacks:
		if area not in sim.areas.list:
			continue
		var layout := sim.areas.layout(area)
		var stacks: AreaStacks = sim.area_stacks[area]
		for position in stacks.stacks.size():
			if cell in layout.stacks[position].cells and not stacks.stacks[position].is_empty():
				return stacks.stacks[position][-1][-1]
	return 0


## Where box `box` is on the grid, in cells: on the vehicle or machine
## carrying it, or on its stack; Vector2.INF once it has left the port or
## gone aboard a ship.
static func box_cell(sim: PortSim, box: int) -> Vector2:
	if box not in sim.boxes:
		return Vector2.INF
	for vehicle in sim.vehicles:
		if vehicle.box != box:
			continue
		for machine: int in sim.machine_jobs:
			if sim.machine_jobs[machine].vehicle == vehicle.id:
				var area: Dictionary = sim.areas.list[sim.machines.list[machine].area]
				var k := sim.machines.position(machine) * AreaLayout.BAY + (AreaLayout.BAY - 1) / 2.0
				return Vector2(area.start) + Vector2((area.end - area.start).sign()) * k + Vector2(area.out) * 2.0
		return vehicle.position(1.0)
	for area: int in sim.area_stacks:
		var stacks: AreaStacks = sim.area_stacks[area]
		if stacks.boxes().has(box) and area in sim.areas.list:
			return Vector2(sim.areas.layout(area).stacks[stacks.position_of(box)].cells[1])
	return Vector2.INF
