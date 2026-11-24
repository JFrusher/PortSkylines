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
## if it has one, or another only if it may; or, sent there by the harbour
## master, of apron `only`. False if none yet.
static func berth(sim: PortSim, ship: PortSim.Ship, only := 0) -> bool:
	var span := ship_cells(sim, ship.kind)
	var aprons := ready_aprons(sim).filter(func(apron: int) -> bool: return Marine.reaches(sim, ship.kind, apron, ship.anchorage, ship.light))
	if only:
		aprons = aprons.filter(func(apron: int) -> bool: return apron == only)
	elif ship.berth != 0:
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
	# A crane works over a handover slot, and slots cover whole pairs of bays only.
	if along < 0 or along >= _length(sim, apron) / AreaLayout.SLOT * AreaLayout.SLOT:
		return "STS cranes stand on a quay apron's rails"
	if _slot_at_column(sim, apron, along) < 0:
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
	return sim.areas.list[apron].columns


## A tractor's speed on the grid, in cells a vehicle second: the data gives
## it in metres.
static func tractor_speed(sim: PortSim) -> float:
	return sim.rules.tractor.speed / Grid.CELL


## One tick of the area flow, after ships: machines work, then vehicles drive.
static func tick(sim: PortSim) -> void:
	_fit_machines(sim)
	_batteries(sim)
	Racks.tick(sim)
	var wind := sim.event_plan.wind(sim.rules, sim.clock.calendar_minutes())
	var stopped: Array[String] = []
	for gear: String in sim.rules.yard_gear:
		if wind >= sim.rules.yard_gear[gear].wind_limit_kmh:
			stopped.append(gear)
	var stopped_machines: Array[int] = []
	for id: int in sim.machines.list:
		var machine: Dictionary = sim.machines.list[id]
		if machine.job.is_empty() or machine.broken or machine.gear in stopped:
			continue
		if sim.fires.block_burning(machine.area):
			stopped_machines.append(id)
			continue
		machine.worked += SimClock.CALENDAR_MINUTES_PER_TICK
		if sim.event_plan.breaks(Events.mtbf(sim.rules, "yard_gear", machine.gear, sim.serviced)):
			machine.broken = true
			sim._event("A %s broke down" % sim.rules.yard_gear[machine.gear].name, sim.areas.cell_at(machine.area, machine.bay, 0))
	for machine: int in sim.machines.tick(stopped, stopped_machines):
		_machine_done(sim, machine)
	_unpark(sim)
	sim.traffic.due_after = _unstick_minutes(sim) * 60.0
	for vehicle: Vehicle in sim.vehicles.duplicate():
		_drive(sim, vehicle)


## One tick of an apron ship alongside: each of its cranes discharges, and
## once the holds are empty and the cranes idle it sails.
static func work(sim: PortSim, ship: PortSim.Ship) -> void:
	# A burning ship isn't worked until the fire is out.
	if sim.fires.ship_burning(ship.id):
		return
	var working := cranes_for(sim, ship)
	if working.is_empty():
		sim._event("A %s is waiting: no crane on its berth reaches %d rows" % [ship.kind, sim.rules.ship_classes[ship.kind].outreach], sim.areas.cell_at(ship.apron, 0, 0))
		return
	var wind := sim.event_plan.wind(sim.rules, sim.clock.calendar_minutes())
	for crane in working:
		# Over its wind limit a crane stops where it is; a broken one waits for its repair.
		if crane.broken or wind >= sim.rules.sts_cranes[crane.kind].wind_limit_kmh:
			continue
		crane.worked += SimClock.CALENDAR_MINUTES_PER_TICK
		if sim.event_plan.breaks(Events.mtbf(sim.rules, "sts_cranes", crane.kind, sim.serviced)):
			crane.broken = true
			sim._event("A %s broke down" % sim.rules.sts_cranes[crane.kind].name, sim.areas.cell_at(crane.apron, crane.along, 0))
			continue
		var move_minutes := move_minutes_of(sim, crane)
		if ship.boxes > 0 and not _dual_cycle(sim, crane, ship):
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
				sim._event("A %s is sailing, fully loaded" % ship.kind, sim.areas.cell_at(ship.apron, 0, 0))
		elif _export_box(sim, ship) == 0 and not _exports_coming(sim, sim.areas.list[ship.apron].terminal):
			sim._sail(ship, working.size())
			sim._event("A %s sailed %d exports short: none ready in the yard" % [ship.kind, ship.exports], sim.areas.cell_at(ship.apron, 0, 0))


## Whether `crane` loads this tick though `ship` still has imports aboard:
## under the dual-cycling policy, while a tractor is back beneath it with an
## export. Either way it keeps tractors fetching exports as it discharges.
static func _dual_cycle(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> bool:
	if sim.policy_value("dual_cycling", 0.0) <= 0.0:
		return false
	var slot := _crane_slot(sim, crane, ship)
	if crane.tractor != 0:
		return _vehicle(sim, crane.tractor).home == slot
	_keep_fetching(sim, crane, ship)
	return sim.fetching_to(slot).any(func(v: Vehicle) -> bool: return v.state == "under_crane")


## Sends `crane` another tractor to fetch for `ship` while the ship has room
## for more than are already being fetched, up to the crane's max_fetchers.
static func _keep_fetching(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> void:
	var fetchers := _fetchers(sim, ship)
	var slot := _crane_slot(sim, crane, ship)
	var mine := fetchers.filter(func(v: Vehicle) -> bool: return v.home == slot)
	var wanted := ship.exports if ship.exports > 0 else ship.empties
	if wanted > fetchers.size() and mine.size() < sim.rules.sts_cranes[crane.kind].max_fetchers:
		_send_fetcher(sim, crane, ship)


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
	if sim.boxes[id].to == 0 and onward != "" and sim.rng.randf() < sim.rules.lines[ship.line].tranship_share and _onward_room(sim, ship.line, onward) > 0:
		sim.boxes[id].kind = "tranship"
		sim.boxes[id].onward = onward
		sim.boxes[id].due = sim.clock.calendar_minutes() + sim.rules.lines[ship.line].connection_hours * 60.0
		sim.exports += 1
		# Its onward ship calls only at another terminal: a lorry takes it there (inter-terminal trucking).
		sim.boxes[id].to = _onward_terminal(sim, ship.line, onward, here)
	# Booked to barge first, by its line's share while barges call at this
	# terminal, so a barge discount takes boxes from rail and road alike: it
	# waits in its block for a barge, and no lorry takes it.
	if sim.boxes[id].kind == "import" and sim.boxes[id].to == 0 and sim.by_barge_to(id) and barges_call(sim, here) and sim.rng.randf() < sim.barge_share(ship.line):
		sim.boxes[id].barge = true
	# Booked to rail by its line's share, only while a rail block has room for
	# it and its place has a rail link, so a port without rail rolls nothing.
	var customs := Customs.flag(sim, id, here)
	var rail := RailFlow.block_with_room(sim, sim.areas.list[ship.apron].terminal)
	var at := sim.areas.centre(Drive.here(sim, tractor))
	var plugs := _block_for(sim, "reefer", here, id, at) if sim.boxes[id].reefer else 0
	if sim.boxes[id].dg:
		var hazard := _block_for(sim, "dangerous", here, id, at)
		if hazard == 0:
			_shut_out(sim, crane, ship, tractor, id, "A dangerous-goods box was shut out: no dangerous-goods block with room in %s")
			return
		sim._set_area(tractor, hazard)
	elif customs:
		sim._set_area(tractor, customs)
	elif rail and accepts(sim, rail, id) and sim.boxes[id].kind == "import" and not sim.boxes[id].barge and sim.by_rail_to(id) and sim.rng.randf() < sim.rail_share(ship.line):
		sim.boxes[id].rail = true
		sim._set_area(tractor, rail)
	elif plugs:
		sim._set_area(tractor, plugs)
	# Unplugged either way, a reefer without a reefer block goes on like any box.
	elif sim.boxes[id].kind == "tranship":
		var block := _tranship_block(sim, ship, onward, id)
		if block:
			sim._set_area(tractor, block)
	elif sim.boxes[id].kind == "export":
		var block := _block_for(sim, "export", here, id, at)
		if block:
			sim._set_area(tractor, block)
	# shortcut: the vehicle was chosen by the import block it came for, so an AGV may carry a box rerouted here (rail, reefer, export, transhipment) to a manual block; route by box before choosing the vehicle if players want AGVs kept to automated blocks.
	# The block the tractor came for, or fell back on, may not take this box
	# by its rules: then an import block that does, or it stays aboard.
	if not accepts(sim, tractor.area, id):
		var block := _block_for(sim, "import", here, id, at)
		if block == 0:
			_shut_out(sim, crane, ship, tractor, id, "A box was shut out: no yard block's rules take it in %s")
			return
		sim._set_area(tractor, block)
	if sim.boxes[id].rush and sim.clock.calendar_minutes() > ship.due:
		sim.ledger.post("rush_fines", -sim.rules.special_boxes.rush_fine, sim.areas.list[ship.apron].terminal)
	ship.boxes -= 1
	ship.moves += 1
	sim._moved(sim.boxes[id], ship.line, sim.areas.list[ship.apron].terminal)
	tractor.box = id
	tractor.loaded = true
	_go_to(sim, tractor, tractor.area)


## Box `id`, just lifted by `crane`, has no block that may take it: never
## stacked where it isn't allowed, it stays aboard, unpaid, and the tractor
## waits for the next box. `why` takes the terminal's name.
static func _shut_out(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship, tractor: Vehicle, id: int, why: String) -> void:
	sim._drop_box(id)
	crane.tractor = tractor.id
	ship.boxes -= 1
	sim._event(why % sim.areas.terminals[sim.areas.list[ship.apron].terminal].name, sim.areas.cell_at(ship.apron, 0, 0))


## One crane's tick loading: while the ship has room for more exports than
## are already being fetched, it keeps up to max_fetchers tractors fetching
## them, and lifts each box aboard once its tractor is back beneath it, so
## the crane works while others drive.
static func _load(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship, move_minutes: float) -> void:
	_keep_fetching(sim, crane, ship)
	if crane.tractor == 0:
		var back := sim.fetching_to(_crane_slot(sim, crane, ship)).filter(func(v: Vehicle) -> bool: return v.state == "under_crane")
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
	if sim.boxes[tractor.box].barge:
		# An import gone up the river: delivered, at the barge discount.
		sim._import_left(tractor.box)
		sim.delivered += 1
		sim.by_barge += 1
		if sim.barge_discount > 0:
			sim.ledger.post("barge", -sim.barge_discount, sim.areas.list[ship.apron].terminal)
	sim._drop_box(tractor.box)
	ship.moves += 1
	# Dual cycling: with imports still aboard, the tractor stays beneath the
	# crane for one, bound for an import block, as a tractor sent for it would be.
	var block := _block_for(sim, "import", sim.areas.list[ship.apron].terminal, 0, sim.areas.centre(tractor.home)) if ship.boxes > 0 and tractor.straddle == 0 else 0
	if block == 0 or carries(sim, block):
		_gone(sim, tractor)
		return
	sim._fetching[tractor.home].erase(tractor)
	tractor.home = Areas.NO_SPOT
	tractor.box = 0
	tractor.loaded = false
	sim._set_area(tractor, block)
	crane.tractor = tractor.id


## Sends a tractor from the pool, starting in the apron slot under `crane`,
## to fetch an export from its terminal's export blocks and bring it back.
static func _send_fetcher(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> void:
	if not _may_send(sim, sim.areas.list[ship.apron].terminal):
		return
	var box := _export_box(sim, ship, sim.areas.centre(_crane_slot(sim, crane, ship))) if ship.exports > 0 else _surplus_empty(sim, ship)
	if box == 0:
		return
	var block := _block_of(sim, box)
	if not _carrier_free(sim, block):
		return
	var tractor := _pool_vehicle(sim, block, _crane_slot(sim, crane, ship))
	if not Drive.place(sim, tractor):
		return
	sim._next_vehicle += 1
	if tractor.depot:
		sim.agv_home[tractor.depot].erase(tractor.charge)
	tractor.home = Drive.here(sim, tractor)
	tractor.box = box
	sim._claimed[box] = true
	sim._add_vehicle(tractor)
	_go_to(sim, tractor, block)
	# At a racked transfer block the ASC stages it on a rack while the AGV drives over.
	if tractor.kind == "agv" and Racks.has(sim, block):
		Racks.stage(sim, block, box)


## The working AGV depots of `terminal`: a terminal with any runs on its
## depots' AGVs (M11), one without on the port's tractors.
## Kept until the areas or roads change: asked for every crane every tick.
static func agv_depots(sim: PortSim, terminal: int) -> Array[int]:
	var now := Vector2i(sim.areas.version, sim.roads.version)
	if sim._agv_depots_for != now:
		sim._agv_depots_for = now
		sim._agv_depots.clear()
		for id: int in sim.areas.list:
			if sim.areas.kind_of(sim.areas.list[id]) == "agv_depot" and sim.areas.idle_reason(id) == "":
				sim._agv_depots.get_or_add(sim.areas.list[id].terminal, [] as Array[int]).append(id)
	return sim._agv_depots.get(terminal, [] as Array[int])


## Whether, in an AGV terminal, AGVs can't drive to `area`: to a yard block
## from any of the terminal's quay slots, or to an AGV depot from the way
## out of each of its yard blocks, where low AGVs set off home. Its zone
## gives AGVs nowhere to turn, or doesn't join them up.
static func agv_unreachable(sim: PortSim, area: int) -> bool:
	var terminal: int = sim.areas.list[area].terminal
	if agv_depots(sim, terminal).is_empty():
		return false
	var to := _buffer_start(sim, area)
	if sim.areas.kind_of(sim.areas.list[area]) == "agv_depot":
		for block: int in sim.areas.list:
			if sim.areas.list[block].type in Areas.BLOCK_TYPES and sim.areas.list[block].terminal == terminal and not Drive.reaches(sim, _buffer_end(sim, block), to, "agv"):
				return true
		return false
	var slots := []
	for apron: int in sim.areas.list:
		if sim.areas.kind_of(sim.areas.list[apron]) == "quay_apron" and sim.areas.list[apron].terminal == terminal:
			for s: int in sim.areas.layout(apron).slots.size():
				slots.append(_stand(sim, apron, s))
	return not slots.is_empty() and not slots.any(func(slot: Vector3i) -> bool: return Drive.reaches(sim, slot, to, "agv"))


## One of `terminal`'s AGV depots with an AGV at home charged above
## low_share, or 0.
static func _free_agv_depot(sim: PortSim, terminal: int) -> int:
	for depot in agv_depots(sim, terminal):
		if sim.agv_home.get(depot, []).any(func(charge: float) -> bool: return charge >= sim.rules.agv.low_share):
			return depot
	return 0


## Whether `terminal`'s pool has a vehicle free: an AGV at one of its
## depots in an AGV terminal, else one of the port's tractors.
static func _pool_free(sim: PortSim, terminal: int) -> bool:
	if agv_depots(sim, terminal).is_empty():
		return sim._tractors_out() < sim.tractors
	return _free_agv_depot(sim, terminal) != 0


## The vehicle that goes for a box at yard block `block`, standing at
## `slot`: the block's own straddle carrier if its gear carries, else one
## from its terminal's pool, an AGV or a tractor (see _pool_free).
static func _pool_vehicle(sim: PortSim, block: int, slot: Vector3i) -> Vehicle:
	var terminal: int = sim.areas.list[block].terminal
	var agv := not carries(sim, block) and not agv_depots(sim, terminal).is_empty()
	var vehicle := Vehicle.new(sim._next_vehicle, "agv" if agv else "tractor", [slot] as Array[Vector3i])
	vehicle.straddle = block if carries(sim, block) else 0
	if agv:
		vehicle.depot = _free_agv_depot(sim, terminal)
		assert(vehicle.depot != 0, "an AGV is sent only when one is free")
		# The fullest goes; the AGV leaves home only once it is placed (see _send_*).
		var home: Array[float] = sim.agv_home[vehicle.depot]
		vehicle.charge = home.max()
	return vehicle


## Buys `count` AGVs at AGV depot `area`.
static func buy_agvs(sim: PortSim, area: int, count: int) -> String:
	if count < 1:
		return "Buy at least one"
	if area not in sim.areas.list or sim.areas.kind_of(sim.areas.list[area]) != "agv_depot":
		return "No AGV depot there"
	var cost: int = count * sim.rules.agv.cost
	if not sim._afford(cost):
		return "Not enough money"
	sim.ledger.post("equipment", -cost)
	sim.areas.list[area].settings.agvs += count
	for i in count:
		sim.agv_home.get_or_add(area, [] as Array[float]).append(1.0)
	return ""


## Buys `count` chargers at AGV depot `area`, up to max_chargers.
static func buy_chargers(sim: PortSim, area: int, count: int) -> String:
	if count < 1:
		return "Buy at least one"
	if area not in sim.areas.list or sim.areas.kind_of(sim.areas.list[area]) != "agv_depot":
		return "No AGV depot there"
	if sim.areas.list[area].settings.chargers + count > sim.rules.agv.max_chargers:
		return "An AGV depot holds at most %d chargers" % sim.rules.agv.max_chargers
	var cost: int = count * sim.rules.agv.charger_cost
	if not sim._afford(cost):
		return "Not enough money"
	sim.ledger.post("equipment", -cost)
	sim.areas.list[area].settings.chargers += count
	return ""


## The service vehicles in the AGV zone, where each is (cells): mechanics'
## vans and fire engines out on the roads.
static func service_in_zone(sim: PortSim) -> Array[Vector2]:
	var found: Array[Vector2] = []
	if sim.areas.agv_zone.is_empty():
		return found
	var out: Array = sim.workshops.vans.values().filter(func(v: Dictionary) -> bool: return v.job != "home") + sim.fires.engines.values().filter(func(e: Dictionary) -> bool: return e.job != "home")
	for vehicle: Dictionary in out:
		if Vector2i(vehicle.at.floor()) in sim.areas.agv_zone:
			found.append(vehicle.at)
	return found


## Holds every AGV within safety_cells of a service vehicle in the AGV zone
## where it stands for the tick: a safety stop while people drive among them.
static func safety_stops(sim: PortSim) -> void:
	Drive._refresh(sim)
	sim.traffic.held.clear()
	var near := service_in_zone(sim)
	if near.is_empty():
		return
	var reach: float = sim.rules.agv.safety_cells
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.kind != "agv" or vehicle.id not in sim.traffic.cars:
			continue
		var at := Drive.where(sim, vehicle) + Vector2(0.5, 0.5)
		if near.any(func(p: Vector2) -> bool: return p.distance_to(at) <= reach):
			sim.traffic.held[vehicle.id] = true


## A tick of AGV batteries: each AGV out drains, a full charge lasting
## battery_hours; at each depot as many AGVs at home as it has chargers
## charge, flat to full in charge_hours: those home longest not yet full,
## each staying plugged in until it is.
static func _batteries(sim: PortSim) -> void:
	var minutes := SimClock.CALENDAR_MINUTES_PER_TICK
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.kind == "agv":
			vehicle.charge = maxf(0.0, vehicle.charge - minutes / (sim.rules.agv.battery_hours * 60.0))
	for depot: int in sim.agv_home:
		if depot not in sim.areas.list:
			continue
		var home: Array[float] = sim.agv_home[depot]
		var free: int = sim.areas.list[depot].settings.chargers
		for i in home.size():
			if free == 0:
				break
			if home[i] < 1.0:
				home[i] = minf(1.0, home[i] + minutes / (sim.rules.agv.charge_hours * 60.0))
				free -= 1


## Whether yard block `block`'s gear carries its own boxes to the quay
## (straddle carriers), so no tractor from the pool is needed.
static func carries(sim: PortSim, block: int) -> bool:
	return sim.rules.yard_gear[sim.areas.list[block].settings.gear].carries


## Whether yard block `block` is automated (ASCs).
static func automated(sim: PortSim, block: int) -> bool:
	return sim.rules.yard_gear[sim.areas.list[block].settings.gear].automated


## How fast yard block `block`'s machines work, against their gear's own
## times: 1, or for an automated block its ramp-up pace for the days since
## it was automated (data automation.ramp_up).
static func pace(sim: PortSim, block: int) -> float:
	if block not in sim.automated_since:
		return 1.0
	return ramp_pace(sim.rules.automation.ramp_up, (sim.clock.calendar_minutes() - sim.automated_since[block]) / SimClock.MINUTES_PER_DAY)


## The pace on ramp-up curve `ramp` ([days, pace] points) `days` in.
static func ramp_pace(ramp: Array, days: float) -> float:
	if days <= ramp[0][0]:
		return ramp[0][1]
	for i in range(1, ramp.size()):
		if days <= ramp[i][0]:
			return lerpf(ramp[i - 1][1], ramp[i][1], (days - ramp[i - 1][0]) / (ramp[i][0] - ramp[i - 1][0]))
	return ramp[-1][1]


## Whether anything could go for a box in `terminal`: one from its pool
## (see _pool_free), or a straddle block's own carrier. Checked first, as
## finding the box is dearer.
static func _may_send(sim: PortSim, terminal: int) -> bool:
	if _pool_free(sim, terminal):
		return true
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type in Areas.BLOCK_TYPES and area.terminal == terminal and carries(sim, id) and _carrier_free(sim, id):
			return true
	return false


## Whether a vehicle can go for a box at `block`: one of its own straddle
## carriers (one a machine) if its gear carries, else one from its
## terminal's pool (see _pool_free).
# shortcut: a straddle block's machines also stack for lorries while its carriers drive to the quay; split them if lorry-heavy straddle blocks look too quick.
static func _carrier_free(sim: PortSim, block: int) -> bool:
	if not carries(sim, block):
		return _pool_free(sim, sim.areas.list[block].terminal)
	var carriers := sim.machines.count_for(sim.areas.list[block].settings.gear, _bays(sim, block))
	return sim._straddles_out.get(block, 0) < carriers


## The tractors out fetching exports for `ship`: each has its home in the
## apron slot under one of the ship's cranes.
static func _fetchers(sim: PortSim, ship: PortSim.Ship) -> Array[Vehicle]:
	var found: Array[Vehicle] = []
	for crane in cranes_for(sim, ship):
		found.append_array(sim.fetching_to(_crane_slot(sim, crane, ship)))
	return found


## The box `ship` loads next from its terminal's working blocks, or 0: for
## a barge, an import booked to barge; else a transhipment box of its line
## going on by a ship of its size first, then an export. For a tractor at
## `from`, the cheapest by _block_cost plus a move for each box dug out above
## it; else (INF) the least buried. Ties went to the first block, so every
## crane's tractors emptied one export block at a time behind its one machine.
static func _export_box(sim: PortSim, ship: PortSim.Ship, from := Vector2.INF) -> int:
	var terminal: int = sim.areas.list[ship.apron].terminal
	var group := "feeder" if ship.kind == "feeder" else "mother"
	var inland: bool = sim.rules.ship_classes[ship.kind].inland
	var mine := func(box: int) -> bool: return sim.boxes[box].barge if inland else sim.boxes[box].line == ship.line and sim.boxes[box].onward == group
	var bound := _bound(sim) if from != Vector2.INF else {}
	for kind: String in (["import"] if inland else ["tranship", "export"]):
		var best := 0
		var lowest := INF
		for block: int in sim.area_stacks:
			if block not in sim.areas.list or sim.areas.list[block].terminal != terminal or sim.areas.idle_reason(block) != "":
				continue
			var stacks: AreaStacks = sim.area_stacks[block]
			var base := _block_cost(sim, block, from, bound) if from != Vector2.INF else 0.0
			var move := _move_minutes(sim, block) if from != Vector2.INF else 1.0
			for box: int in stacks.of_kind(kind, sim.boxes):
				if box in sim._claimed or not (kind == "export" or mine.call(box)):
					continue
				var cost := base + stacks.above(box) * move
				if cost < lowest:
					best = box
					lowest = cost
		if best:
			return best
	return 0


## Whether a barge service calls at a berth in `terminal`.
static func barges_call(sim: PortSim, terminal: int) -> bool:
	return sim.contracts.services.any(func(s: Dictionary) -> bool: return sim.rules.ship_classes[s.kind].inland and s.apron in sim.areas.list and sim.areas.list[s.apron].terminal == terminal)


## Where `ship`'s transhipment boxes go on: "feeder" off a big ship, "mother"
## off a feeder, while its line has a service of that size and transhipment
## is unlocked; else "".
## The terminal `line`'s `onward` services ("feeder" or "mother") berth at,
## when none berths at `here`; else 0.
static func _onward_terminal(sim: PortSim, line: String, onward: String, here: int) -> int:
	var found := 0
	for service: Dictionary in sim.contracts.services:
		if service.line != line or (service.kind == "feeder") != (onward == "feeder") or service.apron not in sim.areas.list:
			continue
		var terminal: int = sim.areas.list[service.apron].terminal
		if terminal == here:
			return 0
		if found == 0:
			found = terminal
	return found


## How many more of `line`'s boxes its `onward` ships calling within its
## connection window can take: their export moves, less the boxes already
## waiting for them. Past that, a box lands as a plain import.
# shortcut: a ship of the line already alongside isn't counted, as its call is this week's; count it if transhipment runs short while one is in.
static func _onward_room(sim: PortSim, line: String, onward: String) -> int:
	var now := sim.clock.calendar_minutes()
	var by: float = now + sim.rules.lines[line].connection_hours * 60.0
	var room := 0
	for service: Dictionary in sim.contracts.services:
		if service.line == line and (service.kind == "feeder") == (onward == "feeder") and Contracts.next_call(service, now) <= by:
			room += int(sim.rules.ship_classes[service.kind].export_moves)
	if room == 0:
		return 0
	for box: Dictionary in sim.boxes.values():
		if box.kind == "tranship" and box.line == line and box.onward == onward:
			room -= 1
	return room


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
		if area.type not in Areas.BLOCK_TYPES or area.terminal != terminal or area.settings.role != "empty" or sim.areas.idle_reason(id) != "" or id not in sim.area_stacks:
			continue
		for box: int in sim.area_stacks[id].of_kind("empty", sim.boxes):
			if box not in sim._claimed and sim.boxes[box].line == ship.line:
				free.append(box)
	return free[0] if free.size() > sim.rules.empties.keep else 0


## Where a tractor stands in the apron slot under `crane`.
static func _crane_slot(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> Vector3i:
	var slot := _slot_at_column(sim, ship.apron, crane.along)
	return _stand(sim, ship.apron, slot) if slot >= 0 else Areas.NO_SPOT


static func _slot_at_column(sim: PortSim, apron: int, column: int) -> int:
	var slots: Array = sim.areas.layout(apron).slots
	for i in slots.size():
		if slots[i].any(func(cell: Vector3i) -> bool: return cell.y == column):
			return i
	return -1


## Where a vehicle stands in slot `slot` at `door` (see _door): its last
## cell in driving order, the rest of the slot behind it.
static func _stand(sim: PortSim, door: int, slot: int) -> Vector3i:
	var cells: Array = _part(sim, door, "slots")[slot]
	return cells[-1] if Drive.flow(sim, door) >= 0 else cells[0]


## The door vehicle `vehicle` uses at its area: a transfer block's lorries
## hand over at its back, -area (M11); everyone else at an area's front, area.
static func _door(sim: PortSim, vehicle: Vehicle) -> int:
	if vehicle.kind == "lorry" and vehicle.area in sim.areas.list and sim.areas.kind_of(sim.areas.list[vehicle.area]) == "transfer_block":
		return -vehicle.area
	return vehicle.area


## `key` ("slots" or "buffer") of the layout of `door`'s area: its back's for a back door.
static func _part(sim: PortSim, door: int, key: String) -> Array:
	return sim.areas.layout(absi(door))[("back_" + key) if door < 0 else key]


## The bay where a machine meets a vehicle in slot `slot` at `door`: the
## one in the middle of the slot, or a transfer block's end bay by its door.
static func _slot_bay(sim: PortSim, door: int, slot: int) -> int:
	if sim.areas.kind_of(sim.areas.list[absi(door)]) == "transfer_block":
		return 0 if door > 0 else _bays(sim, absi(door)) - 1
	var cells: Array = sim.areas.layout(door).slots[slot]
	return (cells[0].y + cells[-1].y) / 2 / AreaLayout.BAY


## How many bays `area` is long: along its road, or a transfer block's
## away from it, between its two ends.
static func _bays(sim: PortSim, area: int) -> int:
	var shape: Dictionary = sim.areas.list[area]
	if sim.areas.kind_of(shape) == "transfer_block":
		return (sim.areas.depth_of(shape) - 4) / AreaLayout.BAY
	return shape.columns / AreaLayout.BAY


## Puts a tractor from the pool in the apron slot under `crane`, bound for an
## import block of the ship's terminal with room. False when there is no free
## tractor, slot or block yet.
static func _send_tractor(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> bool:
	if not _may_send(sim, sim.areas.list[ship.apron].terminal):
		return false
	var blocks := _blocks_with_room(sim, "import", sim.areas.list[ship.apron].terminal, 0, sim.areas.centre(_crane_slot(sim, crane, ship)))
	if blocks.is_empty():
		sim._event("A ship is waiting: no import yard block with room and a road in its terminal")
		return false
	# The first block something can go for: a manual block takes a tractor, an automated one an AGV.
	var free := blocks.filter(func(b: int) -> bool: return _carrier_free(sim, b))
	if free.is_empty():
		return false
	var block: int = free[0]
	var tractor := _pool_vehicle(sim, block, _crane_slot(sim, crane, ship))
	if not Drive.place(sim, tractor):
		return false
	sim._next_vehicle += 1
	if tractor.depot:
		sim.agv_home[tractor.depot].erase(tractor.charge)
	tractor.state = "under_crane"
	sim._set_area(tractor, block)
	sim._add_vehicle(tractor)
	crane.tractor = tractor.id
	return true


## An area other than `except` that `wanted` accepts, within dg_distance
## cells of `cells`, or 0.
# shortcut: compares bounding boxes, so a 45° block keeps more than the distance; compare cells if players build DG on diagonals.
static func near(sim: PortSim, cells: Array[Vector2i], except: int, wanted: Callable) -> int:
	var reach := _bounds(cells).grow(sim.rules.special_boxes.dg_distance)
	for id: int in sim.areas.list:
		if id != except and wanted.call(sim.areas.list[id]) and reach.intersects(_bounds(sim.areas.cells(id))):
			return id
	return 0


## Whether `area` is a dangerous-goods yard block.
static func is_dangerous(area: Dictionary) -> bool:
	return area.type in Areas.BLOCK_TYPES and area.settings.role == "dangerous"


## Whether `area` must keep dg_distance from a dangerous-goods block: any
## other yard block, quay apron or gate.
static func keeps_from_dangerous(sim: PortSim, area: Dictionary) -> bool:
	return sim.areas.kind_of(area) in ["yard_block", "transfer_block", "quay_apron", "gate"]


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
## ship and waits a further window for the next one. The first time it
## misses, its line is fined and thinks less of the port, in one knock per
## line for the check, so a check cancels at most one service per line.
## Returns how many missed.
static func miss_connections(sim: PortSim, now: float) -> int:
	var missed := 0
	var knocks := {}  # line -> boxes missing for the first time
	for id: int in sim.boxes:
		var box: Dictionary = sim.boxes[id]
		if box.kind != "tranship" or box.due > now:
			continue
		if not box.missed:
			box.missed = true
			sim.ledger.post("connection_fines", -sim.rules.transhipment.missed_fine, box.from)
			knocks[box.line] = knocks.get(box.line, 0) + 1
		box.due += sim.rules.lines[box.line].connection_hours * 60.0
		missed += 1
	for line: String in knocks:
		sim._event_if(sim.contracts.penalise(line, sim.rules.transhipment.missed_reputation * knocks[line]))
	return missed


## Where `box` goes in yard block `block`, by the block's stacking strategy
## (AreaStacks.place_spot), or -1.
static func _place_spot(sim: PortSim, block: int, box: int, within_room := true) -> int:
	return _stacks(sim, block).place_spot(sim.boxes[box].teu, sim.areas.list[block].settings.stacking, sim.boxes[box].due, sim.boxes, within_room, targeted(sim, block))


## The stack positions in `block` a machine is carrying a box to, so two
## machines are never sent to the same last tier.
static func targeted(sim: PortSim, block: int) -> Dictionary:
	var found := {}
	for job: Dictionary in sim.machine_jobs.values():
		if job.position < 0:
			continue
		var at := 0
		if job.has("rack"):
			at = job.rack
		elif job.has("train"):
			var train := RailFlow._train(sim, job.train)
			at = train.block if train else 0
		else:
			var vehicle := _vehicle(sim, job.vehicle)
			at = vehicle.area if vehicle else 0
		if at == block:
			found[job.position] = true
	return found


## How high yard block `block` stacks: as high as its gear, or its own
## lower limit.
static func tiers(sim: PortSim, block: int) -> int:
	var settings: Dictionary = sim.areas.list[block].settings
	var gear: int = sim.rules.yard_gear[settings.gear].tiers
	return mini(gear, settings.max_tiers) if settings.max_tiers > 0 else gear


## Whether yard block `block`'s rules take box `box`: its size, its line
## (an export is on no line until a ship loads it, so every block takes it)
## and, for a reefer, whether the block takes reefers.
# shortcut: rules are checked when a box is sent to a block, so one already on its way when the rules change, and an export a train brings to its rail block, is still stacked; check again at the stack if players lean on changing rules in a busy yard.
static func accepts(sim: PortSim, block: int, box: int) -> bool:
	var settings: Dictionary = sim.areas.list[block].settings
	var b: Dictionary = sim.boxes[box]
	if not settings.sizes.is_empty() and b.teu not in settings.sizes:
		return false
	if not settings.lines.is_empty() and b.line != "" and b.line not in settings.lines:
		return false
	return settings.reefers or not b.reefer


## The yard block of `role` in `terminal` a vehicle at `from` gets its box
## handled at soonest (see _blocks_with_room), or 0.
static func _block_for(sim: PortSim, role: String, terminal: int, box: int, from: Vector2) -> int:
	var found := _blocks_with_room(sim, role, terminal, box, from)
	return found[0] if not found.is_empty() else 0


## `terminal`'s working yard blocks of `role` with room for one more box than
## is already on its way to it, counting tractors waiting under a crane for a
## box bound for it, whose rules take `box` (0: any box); soonest first for a
## vehicle at `from` (INF: unranked). As Cities: Skylines picks a
## destination by its cost and _gate_of picks a gate: the minutes to drive
## there plus the vehicles already bound for it times a move of its gear, over
## its machines at their pace. Taking the first with room sent a terminal's
## whole discharge to one block, whose one machine then set the quay's pace
## and whose queue backed up the roads.
static func _blocks_with_room(sim: PortSim, role: String, terminal: int, box: int, from: Vector2) -> Array[int]:
	var candidates: Array[int] = []
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type not in Areas.BLOCK_TYPES or area.terminal != terminal or area.settings.role != role or sim.areas.idle_reason(id) != "" or RailFlow.is_rail_block(sim, id):
			continue
		if box != 0 and not accepts(sim, id, box):
			continue
		candidates.append(id)
	if candidates.is_empty():
		return candidates
	var coming := {}  # block -> boxes on their way, and tractors under a crane waiting for a box bound for it
	for v: Vehicle in sim.vehicles:
		if v.loaded or v.state == "under_crane":
			coming[v.area] = coming.get(v.area, 0) + 1
	var bound := _bound(sim)
	var found: Array[int] = []
	var cost := {}
	for id in candidates:
		if _stacks(sim, id).room() <= coming.get(id, 0):
			continue
		found.append(id)
		if from != Vector2.INF:
			cost[id] = _block_cost(sim, id, from, bound)
	if from != Vector2.INF:
		# Stable on ties, by id, so a replay picks the same.
		found.sort_custom(func(a: int, b: int) -> bool: return [cost[a], a] < [cost[b], b])
	return found


## Block -> every vehicle bound for it.
static func _bound(sim: PortSim) -> Dictionary:
	var bound := {}
	for v: Vehicle in sim.vehicles:
		bound[v.area] = bound.get(v.area, 0) + 1
	return bound


## Minutes for a vehicle at `from` to be served at block `id`: the drive
## there plus the vehicles already bound for it (`bound`, from _bound) times
## a move of its gear, over its machines.
static func _block_cost(sim: PortSim, id: int, from: Vector2, bound: Dictionary) -> float:
	var drive := from.distance_to(sim.areas.centre(_buffer_start(sim, id))) / tractor_speed(sim)
	return drive + bound.get(id, 0) * _move_minutes(sim, id) / sim.machines.count_for(sim.areas.list[id].settings.gear, _bays(sim, id))


## Minutes one move of block `id`'s gear takes at its pace.
static func _move_minutes(sim: PortSim, id: int) -> float:
	var gear: Dictionary = sim.rules.yard_gear[sim.areas.list[id].settings.gear]
	# A vehicle second is a calendar minute, and a machine's seconds are game seconds.
	return (gear.lift_seconds + gear.set_down_seconds) / 60.0 / pace(sim, id)


## The transhipment block with room in `ship`'s terminal nearest the berths
## of its line's `onward` services, where the box goes on; or 0.
static func _tranship_block(sim: PortSim, ship: PortSim.Ship, onward: String, box: int) -> int:
	var berths: Array[Vector2i] = []
	for service: Dictionary in sim.contracts.services:
		if service.line == ship.line and (service.kind == "feeder") == (onward == "feeder") and service.apron in sim.areas.list:
			berths.append(sim.areas.cell_at(service.apron, 0, 0))
	var best := 0
	var nearest := 0
	for id in _blocks_with_room(sim, "tranship", sim.areas.list[ship.apron].terminal, box, Vector2.INF):
		var start: Vector2i = sim.areas.cell_at(id, 0, 0)
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
		# A transhipment bound for another terminal goes first: it has a ship to meet there.
		for id: int in sim.area_stacks[block].of_kind("tranship", sim.boxes):
			if sim.boxes[id].to == 0 or id in sim._claimed:
				continue
			if box == 0 or sim.boxes[box].kind != "tranship" or sim.boxes[id].due < sim.boxes[box].due:
				box = id
				terminal = sim.areas.list[block].terminal
			break
		if box != 0 and sim.boxes[box].kind == "tranship":
			continue
		# Imports come soonest due first, so the block's first unclaimed one is its best.
		for id: int in sim.area_stacks[block].of_kind("import", sim.boxes):
			if id in sim._claimed or sim.boxes[id].barge or sim.boxes[id].customs != "":
				continue
			if sim.boxes[id].due <= now and (box == 0 or (sim.boxes[box].kind == "import" and sim.boxes[id].due < sim.boxes[box].due)):
				box = id
				terminal = sim.areas.list[block].terminal
			break
	if box == 0:
		return false
	var entry := _entry_cell(sim)
	if entry == Areas.NO_SPOT:
		return false
	var gate := _gate_of(sim, terminal, entry)
	if not can_book(sim, gate):
		return false
	var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector3i])
	Drive.place(sim, lorry)
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
	var roomy: Array = gated.filter(func(t: int) -> bool: return _block_for(sim, "empty", t, 0, Vector2.INF) != 0)
	var terminal: int = roomy[0] if not roomy.is_empty() else gated[0]
	var entry := _entry_cell(sim)
	if entry == Areas.NO_SPOT:
		return false
	var gate := _gate_of(sim, terminal, entry)
	if not can_book(sim, gate):
		return false
	var back: Dictionary = sim.returning.pop_front()
	var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector3i])
	Drive.place(sim, lorry)
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
	# With the way in busy nothing is sent, so demand isn't worked out for nothing.
	if _entry_cell(sim) == Areas.NO_SPOT:
		return false
	if not sim.transfers.is_empty() and _transfer_in(sim):
		return true
	var packed: bool = not sim.stuffing.is_empty() and sim.stuffing[0].at <= sim.clock.calendar_minutes()
	if not packed and export_demand(sim) <= 0:
		return false
	for terminal: int in sim.areas.terminals:
		if not _has_gate(sim, terminal) or _export_room(sim, terminal) <= 0:
			continue
		var entry := _entry_cell(sim)
		if entry == Areas.NO_SPOT:
			return false
		var gate := _gate_of(sim, terminal, entry)
		if not can_book(sim, gate):
			continue
		var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector3i])
		Drive.place(sim, lorry)
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
	if entry == Areas.NO_SPOT:
		return false
	var gate := _gate_of(sim, terminal, entry)
	if not can_book(sim, gate):
		return false
	var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector3i])
	Drive.place(sim, lorry)
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
		if area.type not in Areas.BLOCK_TYPES or area.terminal != terminal or area.settings.role != "empty" or sim.areas.idle_reason(id) != "" or id not in sim.area_stacks:
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
		if area.type in Areas.BLOCK_TYPES and area.terminal == terminal and area.settings.role == "export" and sim.areas.idle_reason(id) == "":
			room += _stacks(sim, id).room()
	return room - _lorries(sim).exports.get(terminal, 0)


static func _entry_cell(sim: PortSim) -> Vector3i:
	return Drive.entry_cell(sim)


static func _exit_cell(sim: PortSim) -> Vector3i:
	return Drive.exit_cell(sim)


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
static func _gate_of(sim: PortSim, terminal: int, from: Vector3i) -> int:
	var gates := _gates(sim, terminal).duplicate()
	while not gates.is_empty():
		var best := 0
		var soonest := INF
		for gate: int in gates:
			# A vehicle second is a calendar minute, so driving and queueing add up.
			var drive: float = sim.areas.centre(from).distance_to(sim.areas.centre(_buffer_start(sim, gate))) / (sim.rules.lorry_speed / Grid.CELL)
			var minutes: float = drive + sim.lorries_bound_for(gate) * gate_minutes(sim, gate) / sim.areas.layout(gate).lanes.size()
			if best == 0 or minutes < soonest:
				best = gate
				soonest = minutes
		if Drive.reaches(sim, from, _buffer_start(sim, best), "lorry"):
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
	if slots_per_hour(sim, gate) > 0:
		var hour := _free_hour(sim, gate)
		sim.bookings[gate][hour] = sim.bookings[gate].get(hour, 0) + 1
		lorry.booked = hour * 60.0
	var park := _park_for(sim, sim.areas.list[gate].terminal)
	var early := lorry.booked > sim.clock.calendar_minutes()
	if park and (early or _gate_full(sim, gate) or sim.vehicles.any(func(v: Vehicle) -> bool: return v.area == park)):
		_go_to(sim, lorry, park)
	else:
		_go_to(sim, lorry, gate)


## Lorries `gate` books an hour, 0 for none: its own setting, else under
## the appointments policy that share of what its lanes can check.
static func slots_per_hour(sim: PortSim, gate: int) -> int:
	var own: int = sim.areas.list[gate].settings.slots_per_hour
	return own if own > 0 else floori(gate_throughput(sim, gate) * sim.policy_value("appointment_share", 0.0))


## The first hour of the calendar, from this one, that `gate` has a booking
## left in, forgetting hours gone by; -1 when it takes no bookings.
static func _free_hour(sim: PortSim, gate: int) -> int:
	var slots := slots_per_hour(sim, gate)
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
	var room: int = sim.areas.layout(gate).slots.size() + sim.handovers.buffer_room(gate)
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
		var gate := _gate_of(sim, sim.areas.list[park].terminal, Drive.here(sim, lorry))
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
	_head(sim, vehicle, _buffer_start(sim, _door(sim, vehicle)), "arriving")


## Sends a tractor with an export back to the slot under its crane; with that
## slot taken, to wait in the nearest free apron slot before it instead, off
## the apron's one through lane, where a queue for one crane held up every
## crane past it and every tractor leaving for the yard. AGVs keep to their grid.
static func _to_crane(sim: PortSim, vehicle: Vehicle) -> void:
	if vehicle.kind == "tractor" and _stand_taken(sim, vehicle):
		var wait := _waiting_stand(sim, vehicle.home)
		if wait != Areas.NO_SPOT:
			_head(sim, vehicle, wait, "to_wait")
			return
	_head(sim, vehicle, vehicle.home, "to_crane")


## Whether the slot under `vehicle`'s crane holds a vehicle or another is
## already bringing its export there.
static func _stand_taken(sim: PortSim, vehicle: Vehicle) -> bool:
	var slot := Vector2i(vehicle.home.x, _slot_of(sim, vehicle.home))
	for other: Vehicle in sim.vehicles:
		if other != vehicle and other.home == vehicle.home and other.state.trim_prefix("no_route:") == "to_crane":
			return true
	for id: int in sim.traffic.cars:
		var car: Dictionary = sim.traffic.cars[id]
		if id != vehicle.id and sim.network.pieces[car.route[car.i]].slot == slot:
			return true
	return false


## The stand of the free apron slot nearest before crane stand `home` in
## driving order, under no crane and with no vehicle in it or bound for it;
## NO_SPOT with none.
static func _waiting_stand(sim: PortSim, home: Vector3i) -> Vector3i:
	var apron := home.x
	var count: int = sim.areas.layout(apron).slots.size()
	var at := _slot_of(sim, home)
	var step := -1 if Drive.flow(sim, apron) >= 0 else 1
	var cranes := {}
	for crane: PortSim.Crane in sim.cranes:
		if crane.apron == apron:
			cranes[_slot_at_column(sim, apron, crane.along)] = true
	var held := {}
	for id: int in sim.traffic.cars:
		var car: Dictionary = sim.traffic.cars[id]
		held[sim.network.pieces[car.route[car.i]].slot] = true
	var bound := {}
	for v: Vehicle in sim.vehicles:
		bound[v.target] = true
	var s := at + step
	while s >= 0 and s < count:
		var stand := _stand(sim, apron, s)
		if s not in cranes and Vector2i(apron, s) not in held and stand not in bound:
			return stand
		s += step
	return Areas.NO_SPOT


## The index of the apron slot holding spot `spot`, or -1.
static func _slot_of(sim: PortSim, spot: Vector3i) -> int:
	return sim.areas.layout(spot.x).slots.find_custom(func(cells: Array) -> bool: return spot in cells)


## The first cell of `door`'s buffer strip in driving order, where vehicles come in.
static func _buffer_start(sim: PortSim, door: int) -> Vector3i:
	var buffer: Array = _part(sim, door, "buffer")
	return buffer[0] if Drive.flow(sim, door) > 0 else buffer[-1]


## `vehicle` reached the start of its area's buffer strip: it books a slot.
static func _book(sim: PortSim, vehicle: Vehicle) -> void:
	if sim.handovers.arrive(_door(sim, vehicle), vehicle.id) == "slot":
		_head_to_slot(sim, vehicle)
	else:
		vehicle.state = "queued"


static func _head_to_slot(sim: PortSim, vehicle: Vehicle) -> void:
	vehicle.slot = sim.handovers.slot_of(_door(sim, vehicle), vehicle.id)
	_head(sim, vehicle, _stand(sim, _door(sim, vehicle), vehicle.slot), "to_slot")


## The last cell of `door`'s buffer strip in driving order, beside its way out.
static func _buffer_end(sim: PortSim, door: int) -> Vector3i:
	var buffer: Array = _part(sim, door, "buffer")
	return buffer[-1] if Drive.flow(sim, door) > 0 else buffer[0]


## Sets `vehicle` driving from where it stands to `to`, in `state` once there.
## With no route yet it waits where it is and tries again each tick.
static func _head(sim: PortSim, vehicle: Vehicle, to: Vector3i, state: String) -> void:
	Drive.head(sim, vehicle, to, state)


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
	if vehicle.state == "waiting":
		if not _stand_taken(sim, vehicle):
			_head(sim, vehicle, vehicle.home, "to_crane")
		return
	if vehicle.state not in ["arriving", "to_slot", "returning", "leaving", "to_crane", "to_charge", "to_wait"]:
		return
	# On its way, not there yet nor waited long enough to unstick: nothing to do.
	if vehicle.id in sim.traffic.cars and vehicle.id not in sim.traffic.due:
		return
	if not Drive.advance(sim, vehicle, _speed(sim, vehicle)):
		_unstick(sim, vehicle)
		return
	match vehicle.state:
		"arriving":
			_book(sim, vehicle)
		"to_slot":
			_arrived(sim, vehicle)
		"returning", "to_charge":
			_gone(sim, vehicle)
		"to_crane":
			vehicle.state = "under_crane"
		"to_wait":
			vehicle.state = "waiting"
		"leaving":
			if vehicle.loaded:
				if sim.boxes[vehicle.box].kind in ["import", "tranship"] and sim.boxes[vehicle.box].to:
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
	# Stuck stuck_minutes, it is moved on to where it was heading with its box,
	# as Cities: Skylines despawns a stuck vehicle; a lorry with no room there
	# still gives up later.
	if Drive.waited(sim, vehicle) >= sim.rules.traffic.stuck_minutes and Drive.move_on(sim, vehicle):
		sim.moved_on += 1
		sim._event("A %s stuck in traffic was moved on" % ("lorry" if vehicle.kind == "lorry" else "tractor"), Vector2i(sim.areas.centre(vehicle.target).floor()))
		return
	if vehicle.kind != "lorry" or Drive.waited(sim, vehicle) < _give_up_minutes(sim):
		return
	if vehicle.area in sim.areas.list:
		sim.handovers.drop(_door(sim, vehicle), vehicle.id)
		_promote(sim, vehicle.area)
	if vehicle.loaded:
		sim._drop_box(vehicle.box)
	elif vehicle.box != 0:
		sim._claimed.erase(vehicle.box)
	var at := Vector2i(Drive.where(sim, vehicle).round())
	_gone(sim, vehicle)
	sim.gave_up += 1
	sim._event("A lorry gave up on a traffic jam and left", at)


## How long a lorry waits, in minutes, before it gives up and leaves.
static func _give_up_minutes(sim: PortSim) -> float:
	return roundi(sim.rules.give_up_seconds / SimClock.TICK_SECONDS) * 2 * SimClock.TICK_SECONDS


## How long any vehicle waits, in minutes, before _unstick may act on it.
static func _unstick_minutes(sim: PortSim) -> float:
	return minf(sim.rules.traffic.stuck_minutes, _give_up_minutes(sim))


static func _gone(sim: PortSim, vehicle: Vehicle) -> void:
	if vehicle.kind == "agv" and vehicle.depot in sim.areas.list:
		# Low, it drives home to charge first; at home it joins its depot's AGVs.
		if vehicle.state != "to_charge" and vehicle.charge < sim.rules.agv.low_share:
			sim._set_area(vehicle, vehicle.depot)
			# Into one of its bays, the next along by how many are home, where it parks.
			var bays: Array = sim.areas.layout(vehicle.depot).slots
			var bay: int = sim.agv_home.get(vehicle.depot, []).size() % bays.size()
			_head(sim, vehicle, _stand(sim, vehicle.depot, bay) if not bays.is_empty() else _buffer_start(sim, vehicle.depot), "to_charge")
			return
		sim.agv_home.get_or_add(vehicle.depot, [] as Array[float]).append(vehicle.charge)
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
		var at := sim.areas.centre(Drive.here(sim, vehicle))
		var block := _block_for(sim, "reefer", terminal, vehicle.box, at) if box.reefer else 0
		if box.kind == "empty":
			block = _block_for(sim, "empty", terminal, vehicle.box, at)
		elif box.dg:
			block = _block_for(sim, "dangerous", terminal, vehicle.box, at)
		elif block == 0:
			if box.kind == "tranship":
				block = _block_for(sim, "tranship", terminal, vehicle.box, at)
			if block == 0:
				block = _block_for(sim, "export", terminal, vehicle.box, at)
		if block:
			_go_to(sim, vehicle, block)
		else:
			# Its blocks filled while it queued, or it has none: it takes its box away.
			if box.kind == "empty":
				sim._event("An empty of %s was turned away: no room in an empty block in %s" % [sim.contracts.name_of(box.line), sim.areas.terminals[terminal].name], sim.areas.cell_at(gate, 0, 0))
				sim._event_if(sim.contracts.penalise(box.line, sim.rules.empties.refused))
			vehicle.gate_in = -1.0
			_go_out(sim, vehicle, 0)
	else:
		_go_to(sim, vehicle, _block_of(sim, vehicle.box))


## The room in block `block` promised to boxes on their way: a loaded
## vehicle bound for it, or a tractor under a crane for a box bound for it,
## as _blocks_with_room counts them.
static func promised(sim: PortSim, block: int) -> int:
	return sim.vehicles.filter(func(v: Vehicle) -> bool: return v.area == block and (v.loaded or v.state == "under_crane")).size()


## Gives the block's machine `vehicle`'s job: a tractor's box onto a stack,
## or a lorry's box off its stack, moving any boxes above it first. With
## every machine busy, the vehicle waits in its slot and asks again when one
## finishes.
static func _start_handling(sim: PortSim, vehicle: Vehicle) -> void:
	# At a racked transfer block an AGV drops its import or takes its export and goes.
	if Racks.drop(sim, vehicle) or Racks.take(sim, vehicle):
		return
	var stacks := _stacks(sim, vehicle.area)
	var layout := sim.areas.layout(vehicle.area)
	# The idle machine nearest the slot goes: a transfer block's twin ASCs
	# each keep to their own end.
	var meet := _slot_bay(sim, _door(sim, vehicle), vehicle.slot)
	var idle: Array = sim.machines.list.keys().filter(func(m: int) -> bool: return sim.machines.list[m].area == vehicle.area and m not in sim.machine_jobs)
	idle.sort_custom(func(a: int, b: int) -> bool: return absi(sim.machines.list[a].bay - meet) < absi(sim.machines.list[b].bay - meet))
	for id: int in idle:
		# A machine meets a vehicle at the bay in the middle of its slot.
		if vehicle.loaded:
			var position := _place_spot(sim, vehicle.area, vehicle.box)
			if position < 0:
				return
			sim.machines.give(id, _slot_bay(sim, _door(sim, vehicle), vehicle.slot), layout.stacks[position].bay, 0, pace(sim, vehicle.area))
			sim.machine_jobs[id] = {"vehicle": vehicle.id, "position": position}
		else:
			var bay: int = layout.stacks[stacks.position_of(vehicle.box)].bay
			var rehandles := stacks.take(vehicle.box, promised(sim, vehicle.area))
			sim.machines.give(id, bay, _slot_bay(sim, _door(sim, vehicle), vehicle.slot), rehandles, pace(sim, vehicle.area))
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
	if sim.machine_jobs[machine].has("rack"):
		Racks.job_done(sim, machine)
		return
	var job: Dictionary = sim.machine_jobs[machine]
	sim.machine_jobs.erase(machine)
	var vehicle := _vehicle(sim, job.vehicle)
	if vehicle == null:
		return  # scrapped with its area while the machine worked
	var block := vehicle.area
	var door := _door(sim, vehicle)
	var stacks := _stacks(sim, block)
	sim.handovers.leave(door, vehicle.id)
	if job.position >= 0:
		var teu: int = sim.boxes[vehicle.box].teu
		var position: int = job.position if stacks.fits(job.position, teu) else _place_spot(sim, block, vehicle.box, false)
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
			_head(sim, vehicle, _buffer_end(sim, door), "returning")
	elif vehicle.kind != "lorry":
		# An export fetched for a crane, by a tractor or an AGV: back to the slot under it.
		sim._claimed.erase(vehicle.box)
		vehicle.loaded = true
		sim._set_area(vehicle, 0)
		vehicle.slot = -1
		_to_crane(sim, vehicle)
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
	var gate := _gate_of(sim, terminal, Drive.here(sim, vehicle)) if terminal else 0
	if gate:
		_go_to(sim, vehicle, gate)
		return
	sim._set_area(vehicle, 0)
	vehicle.slot = -1
	_head(sim, vehicle, _exit_cell(sim), "leaving")


## Sends the vehicles just given a slot at `area` on to it.
static func _promote(sim: PortSim, area: int) -> void:
	for waiting: Vehicle in sim.vehicles:
		if waiting.area == area and waiting.slot < 0 and sim.handovers.slot_of(_door(sim, waiting), waiting.id) >= 0:
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
		if sim.areas.list[area].type not in Areas.BLOCK_TYPES:
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
		var bays := _bays(sim, area)
		var have := sim.machines.list.values().filter(func(m: Dictionary) -> bool: return m.area == area and m.gear == gear).size()
		# A transfer block has twin ASCs, one parked at each end.
		var twin := sim.areas.kind_of(sim.areas.list[area]) == "transfer_block"
		var missing := (2 if twin else sim.machines.count_for(gear, bays)) - have
		for i in missing:
			sim.machines.add(area, gear, (bays - 1) * ((have + i) % 2) if twin else 0)
		if missing > 0:
			# Vehicles waiting in the block's slots ask the new machines.
			for other: Vehicle in sim.vehicles:
				if other.area == area and other.state == "handling":
					_start_handling(sim, other)
		if area in sim.area_stacks:
			sim.area_stacks[area].set_tiers(tiers(sim, area))


## Takes away area `id` and everything working there: boxes stacked in it
## are lost, vehicles bound for it are scrapped with their loads, its
## machines go, a ship alongside sails at once and is gone, one coming in
## turns back to anchorage, and its cranes come down.
static func remove(sim: PortSim, id: int) -> void:
	var lost := 0
	var stacked := {}
	if id in sim.area_stacks:
		for box: int in sim.area_stacks[id].boxes():
			stacked[box] = true
			sim._drop_box(box)
			lost += 1
		sim.area_stacks.erase(id)
	for vehicle: Vehicle in sim.vehicles.duplicate():
		# Bound for the area, fetching an export for a crane on it, driving out
		# through it, or on its way to collect a box that was stacked in it.
		if vehicle.area == id or vehicle.home.x == id or vehicle.target.x == id or vehicle.box in stacked:
			if vehicle.loaded:
				sim._drop_box(vehicle.box)
				lost += 1
			elif vehicle.box != 0:
				sim._claimed.erase(vehicle.box)
			if vehicle.area != id and vehicle.area in sim.areas.list:
				sim.handovers.drop(_door(sim, vehicle), vehicle.id)
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
			Marine.release(sim, ship)
			ship.apron = 0
			ship.path.clear()
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
	for box: int in Racks.on_racks(sim, id):
		sim._drop_box(box)
		lost += 1
	sim.racks.erase(id)
	sim.handovers.forget(id)
	sim.handovers.forget(-id)
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
	for k: int in area.columns:
		var cell := Vector2i(sim.areas.point(block, k, sim.areas.depth_of(area)).floor())
		if sim.rails.segment_at(cell) == 0:
			return [] as Array[Vector2i]
		found.append(cell)
	return found


## Area `area`'s stacks, made empty the first time it is asked for.
static func _stacks(sim: PortSim, area: int) -> AreaStacks:
	if area not in sim.area_stacks:
		sim.area_stacks[area] = AreaStacks.new(sim.areas.layout(area).stacks.size(), tiers(sim, area))
	return sim.area_stacks[area]


static func _vehicle(sim: PortSim, id: int) -> Vehicle:
	return sim.vehicle_by_id(id)


## The box at grid cell `cell`: one on a vehicle there, else the top box of
## a stack covering it; 0 for none. For picking a box to follow.
static func box_at(sim: PortSim, cell: Vector2i) -> int:
	var spot := sim.areas.spot_in(cell)
	for vehicle in sim.vehicles:
		if vehicle.box != 0 and vehicle.box in sim.boxes and Vector2i(Drive.where(sim, vehicle).round()) == cell:
			return vehicle.box
	for area: int in sim.area_stacks:
		if area not in sim.areas.list:
			continue
		var layout := sim.areas.layout(area)
		var stacks: AreaStacks = sim.area_stacks[area]
		for position in stacks.stacks.size():
			if spot in layout.stacks[position].cells and not stacks.stacks[position].is_empty():
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
				var travel := sim.machines.position(machine) * AreaLayout.BAY + (AreaLayout.BAY - 1) / 2.0
				var area: Dictionary = sim.areas.list[sim.machines.list[machine].area]
				if sim.areas.kind_of(area) == "transfer_block":
					return sim.areas.point(sim.machines.list[machine].area, area.columns / 2.0, 2.0 + travel) - Vector2(0.5, 0.5)
				return sim.areas.point(sim.machines.list[machine].area, travel, 2.0) - Vector2(0.5, 0.5)
		return Drive.where(sim, vehicle)
	for area: int in sim.area_stacks:
		var stacks: AreaStacks = sim.area_stacks[area]
		if stacks.boxes().has(box) and area in sim.areas.list:
			return sim.areas.centre(sim.areas.layout(area).stacks[stacks.position_of(box)].cells[1]) - Vector2(0.5, 0.5)
	return Vector2.INF
