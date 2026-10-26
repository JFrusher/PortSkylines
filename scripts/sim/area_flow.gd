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


## Moves an anchored ship to a free stretch of a ready apron; false if none yet.
static func berth(sim: PortSim, ship: PortSim.Ship) -> bool:
	var span := ship_cells(sim, ship.kind)
	for apron in ready_aprons(sim):
		for from in range(_length(sim, apron) - span + 1):
			if sim.ships.any(func(other: PortSim.Ship) -> bool: return other.apron == apron and other.from < from + span and from < other.from + ship_cells(sim, other.kind)):
				continue
			ship.apron = apron
			ship.from = from
			ship.state = PortSim.Ship.State.ARRIVING
			return true
	return false


## Whether some ready apron is long enough for `kind`, busy or not.
static func could_berth(sim: PortSim, kind: String) -> bool:
	return ready_aprons(sim).any(func(apron: int) -> bool: return _length(sim, apron) >= ship_cells(sim, kind))


## Ready aprons with a crane on them: berths lines may offer services for.
static func offer_berths(sim: PortSim) -> int:
	return ready_aprons(sim).filter(func(apron: int) -> bool: return sim.cranes.any(func(c: PortSim.Crane) -> bool: return c.apron == apron)).size()


## The cranes on `ship`'s apron within its length.
static func cranes_for(sim: PortSim, ship: PortSim.Ship) -> Array[PortSim.Crane]:
	var span := ship_cells(sim, ship.kind)
	var found: Array[PortSim.Crane] = []
	for crane in sim.cranes:
		if crane.apron == ship.apron and crane.along >= ship.from and crane.along < ship.from + span:
			found.append(crane)
	return found


## Why an STS crane can't stand `along` cells into apron `apron`, or "".
static func sts_error(sim: PortSim, apron: int, along: int) -> String:
	if apron not in sim.areas.list or sim.areas.list[apron].type != "quay_apron":
		return "STS cranes stand on a quay apron's rails"
	# A crane works over a handover slot, and slots cover whole bays only.
	if along < 0 or along >= _length(sim, apron) / AreaLayout.BAY * AreaLayout.BAY:
		return "STS cranes stand on a quay apron's rails"
	var spots := crane_spots(sim, apron)
	if not spots.is_empty() and along not in spots:
		return "Cranes stand at the berth's crane spots"
	var room := ceili(sim.rules.sts_crane.width / float(Grid.CELL))
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
	for vehicle: Vehicle in sim.vehicles.duplicate():
		_drive(sim, vehicle)


## One tick of an apron ship alongside: each of its cranes discharges, and
## once the holds are empty and the cranes idle it sails.
static func work(sim: PortSim, ship: PortSim.Ship) -> void:
	var working := cranes_for(sim, ship)
	var rows: int = sim.rules.ship_classes[ship.kind].outreach
	if working.is_empty() or sim.rules.sts_crane.outreach < rows:
		sim._event("A %s is waiting: no crane on its berth reaches %d rows" % [ship.kind, rows], sim.areas.list[ship.apron].start)
		return
	var move_minutes: float = 60.0 / (sim.rules.sts_crane.rate * sim.rules.crane_interference)
	for crane in working:
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
			sim._sail(ship, working.size())
			sim._event("A %s is sailing, fully loaded" % ship.kind, sim.areas.list[ship.apron].start)
		elif _export_box(sim, sim.areas.list[ship.apron].terminal) == 0 and not _exports_coming(sim, sim.areas.list[ship.apron].terminal):
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
	var id := sim._new_box("import", sim.clock.calendar_minutes() + sim.rules.import_dwell_minutes * sim._dwell_factor(), ship.line)
	ship.boxes -= 1
	ship.moves += 1
	sim._moved(sim.boxes[id])
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
	if ship.exports > fetchers.size() and mine.size() < sim.rules.sts_crane.max_fetchers:
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
	sim._moved(sim.boxes[tractor.box])
	sim.boxes.erase(tractor.box)
	ship.exports -= 1
	ship.moves += 1
	_gone(sim, tractor)


## Sends a tractor from the pool, starting in the apron slot under `crane`,
## to fetch an export from its terminal's export blocks and bring it back.
static func _send_fetcher(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> void:
	if sim._tractors_out() >= sim.tractors:
		return
	var box := _export_box(sim, sim.areas.list[ship.apron].terminal)
	if box == 0:
		return
	var tractor := Vehicle.new(sim._next_vehicle, "tractor", [_crane_slot(sim, crane, ship)] as Array[Vector2i])
	if not sim.lane_traffic.place(tractor):
		return
	sim._next_vehicle += 1
	tractor.home = tractor.path[0]
	tractor.box = box
	sim._claimed[box] = true
	sim.vehicles.append(tractor)
	_go_to(sim, tractor, _block_of(sim, box))


## The tractors out fetching exports for `ship`: each has its home in the
## apron slot under one of the ship's cranes.
static func _fetchers(sim: PortSim, ship: PortSim.Ship) -> Array[Vehicle]:
	var slots := cranes_for(sim, ship).map(func(c: PortSim.Crane) -> Vector2i: return _crane_slot(sim, c, ship))
	var found: Array[Vehicle] = []
	for vehicle in sim.vehicles:
		if vehicle.kind == "tractor" and vehicle.home in slots:
			found.append(vehicle)
	return found


## The least buried export box waiting in a working export block of
## `terminal`, or 0, so loading digs out as few boxes as it can.
static func _export_box(sim: PortSim, terminal: int) -> int:
	var best := 0
	var fewest := 0
	for block: int in sim.area_stacks:
		if block not in sim.areas.list or sim.areas.list[block].terminal != terminal or sim.areas.idle_reason(block) != "":
			continue
		var stacks: AreaStacks = sim.area_stacks[block]
		for box: int in stacks.boxes():
			if box not in sim._claimed and sim.boxes[box].kind == "export" and (best == 0 or stacks.above(box) < fewest):
				best = box
				fewest = stacks.above(box)
	return best


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
	tractor.area = block
	sim.vehicles.append(tractor)
	crane.tractor = tractor.id
	return true


## The first yard block of `role` in `terminal` that works and has room for
## one more box than is already on its way, or 0.
static func _block_for(sim: PortSim, role: String, terminal: int) -> int:
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type != "yard_block" or area.terminal != terminal or area.settings.role != role or sim.areas.idle_reason(id) != "":
			continue
		var coming := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.area == id and v.loaded).size()
		if _stacks(sim, id).room() > coming:
			return id
	return 0


## Sends a lorry in from the site entry for the import box due out longest,
## whichever block holds it, to its terminal's gate first; false when no box
## is due or the way in is busy.
static func dispatch_import_lorry(sim: PortSim) -> bool:
	var now := sim.clock.calendar_minutes()
	var box := 0
	var terminal := 0
	for block: int in sim.area_stacks:
		if block not in sim.areas.list or sim.areas.idle_reason(block) != "":
			continue
		if not _has_gate(sim, sim.areas.list[block].terminal):
			sim._event("Lorries can't come in: build a gate in %s" % sim.areas.terminals[sim.areas.list[block].terminal].name)
			continue
		for id: int in sim.area_stacks[block].boxes():
			if id in sim._claimed or sim.boxes[id].kind != "import" or sim.boxes[id].due > now:
				continue
			if box == 0 or sim.boxes[id].due < sim.boxes[box].due:
				box = id
				terminal = sim.areas.list[block].terminal
	if box == 0:
		return false
	var entry := _entry_cell(sim)
	if entry == Grid.NONE:
		return false
	var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector2i])
	sim.lane_traffic.place(lorry)
	sim._next_vehicle += 1
	lorry.box = box
	sim._claimed[box] = true
	sim.vehicles.append(lorry)
	_go_to(sim, lorry, _gate_of(sim, terminal, entry))
	return true


## Sends a lorry in from the site entry with an export box, while calls want
## more exports than the port holds, to a terminal with a gate whose export
## blocks have room for more than the export lorries already on their way;
## false when none is wanted, there is no room, or the way in is busy.
static func dispatch_export_lorry(sim: PortSim) -> bool:
	if export_demand(sim) <= 0:
		return false
	for terminal: int in sim.areas.terminals:
		if not _has_gate(sim, terminal) or _export_room(sim, terminal) <= 0:
			continue
		var entry := _entry_cell(sim)
		if entry == Grid.NONE:
			return false
		var gate := _gate_of(sim, terminal, entry)
		var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector2i])
		sim.lane_traffic.place(lorry)
		sim._next_vehicle += 1
		# shortcut: an export is booked on no line until a ship loads it, as on tiles.
		lorry.box = sim._new_box("export", 0.0, "")
		lorry.loaded = true
		sim.vehicles.append(lorry)
		_go_to(sim, lorry, gate)
		return true
	return false


## Exports wanted and not yet in the port: room on ships in port, and on the
## calls of agreed services due within export_lead_hours, less every export
## box already in a yard, on a vehicle or on its way.
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
	for box: Dictionary in sim.boxes.values():
		if box.kind == "export":
			wanted -= 1
	return wanted


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
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.kind == "lorry" and vehicle.loaded and sim.boxes[vehicle.box].kind == "export" and vehicle.area in sim.areas.list and sim.areas.list[vehicle.area].terminal == terminal:
			room -= 1
	return room


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
	var found: Array[int] = []
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if sim.areas.kind_of(area) == "gate" and area.terminal == terminal and sim.areas.idle_reason(id) == "":
			found.append(id)
	return found


static func _has_gate(sim: PortSim, terminal: int) -> bool:
	return not _gates(sim, terminal).is_empty()


## The working gate of `terminal` a lorry at `from` reaches by the shortest
## route, so lorries check in and out at the gate on their side of the road;
## 0 when the terminal has none.
# shortcut: ranks by route length alone, not queues; weigh each gate's queue when one gate of several jams.
static func _gate_of(sim: PortSim, terminal: int, from: Vector2i) -> int:
	var best := 0
	var shortest := INF
	for gate in _gates(sim, terminal):
		var route := sim.lanes.route(from, _buffer_start(sim, gate), true)
		var length: float = route.size() if not route.is_empty() else INF
		if best == 0 or length < shortest:
			best = gate
			shortest = length
	return best


## The yard block holding `box`, or 0.
static func _block_of(sim: PortSim, box: int) -> int:
	for block: int in sim.area_stacks:
		if sim.area_stacks[block].boxes().has(box):
			return block
	return 0


## Sends `vehicle` to the start of `area`'s buffer strip. It books a
## handover slot only on getting there, so slots go in the order vehicles
## arrive; with none free it waits at the start of the strip, and others
## queue behind it on the road. Vehicles leave slots back into the strip
## ahead of it, so waiting never blocks the way out.
static func _go_to(sim: PortSim, vehicle: Vehicle, area: int) -> void:
	vehicle.area = area
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
	vehicle.path = route if not route.is_empty() else [here] as Array[Vector2i]
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
				sim.delivered += 1 if sim.boxes[vehicle.box].kind == "import" else 0
				sim.boxes.erase(vehicle.box)
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
		sim.boxes.erase(vehicle.box)
	elif vehicle.box != 0:
		sim._claimed.erase(vehicle.box)
	var at := Vector2i(vehicle.position(1.0).round())
	_gone(sim, vehicle)
	sim.gave_up += 1
	sim._event("A lorry gave up on a traffic jam and left", at)


static func _gone(sim: PortSim, vehicle: Vehicle) -> void:
	sim.lane_traffic.leave(vehicle)
	sim.vehicles.erase(vehicle)


## A vehicle reached its handover slot: at a gate it is checked for the gate
## time, which starts a lorry's turn on the way in and ends it on the way
## out; at a yard block a machine is asked for.
static func _arrived(sim: PortSim, vehicle: Vehicle) -> void:
	if sim.areas.kind_of(sim.areas.list[vehicle.area]) != "gate":
		vehicle.state = "handling"
		_start_handling(sim, vehicle)
		return
	vehicle.state = "at_gate"
	vehicle.timer = gate_minutes(sim, vehicle.area)
	var now := sim.clock.calendar_minutes()
	if vehicle.gate_in < 0.0:
		vehicle.gate_in = now
		return
	sim.turn_times.append(now - vehicle.gate_in)
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
		vehicle.area = 0
		vehicle.slot = -1
		_head(sim, vehicle, _exit_cell(sim), "leaving")
	elif vehicle.loaded:
		var block := _block_for(sim, "export", sim.areas.list[gate].terminal)
		if block:
			_go_to(sim, vehicle, block)
		else:
			# The export blocks filled while it queued: it takes its box away.
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
			vehicle.area = 0
			vehicle.slot = -1
			_head(sim, vehicle, _buffer_end(sim, block), "returning")
	elif vehicle.kind == "tractor":
		# An export fetched for a crane: back to the slot under it.
		sim._claimed.erase(vehicle.box)
		vehicle.loaded = true
		vehicle.area = 0
		vehicle.slot = -1
		_head(sim, vehicle, vehicle.home, "to_crane")
	else:
		sim.dwell_times.append(sim.clock.calendar_minutes() - sim.boxes[vehicle.box].in)
		if sim.dwell_times.size() > 50:
			sim.dwell_times.pop_front()
		sim._claimed.erase(vehicle.box)
		vehicle.loaded = true
		_go_out(sim, vehicle, sim.areas.list[block].terminal)
	_promote(sim, block)
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
	vehicle.area = 0
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
			sim.boxes.erase(box)
			lost += 1
		sim.area_stacks.erase(id)
	var cells := sim.areas.cells(id)
	for vehicle: Vehicle in sim.vehicles.duplicate():
		# Bound for the area, or fetching an export for a crane on it.
		if vehicle.area == id or vehicle.home in cells:
			if vehicle.loaded:
				sim.boxes.erase(vehicle.box)
				lost += 1
			elif vehicle.box != 0:
				sim._claimed.erase(vehicle.box)
			if vehicle.area != id and vehicle.area in sim.areas.list:
				sim.handovers.drop(vehicle.area, vehicle.id)
				_promote(sim, vehicle.area)
			sim.lane_traffic.leave(vehicle)
			sim.vehicles.erase(vehicle)
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
				sim.lane_traffic.leave(tractor)
				sim.vehicles.erase(tractor)
			sim.cranes.erase(crane)
	sim.handovers.forget(id)
	sim.areas.remove(id)
	if lost:
		sim._event("Removing the area lost %d boxes" % lost)


## Area `area`'s stacks, made empty the first time it is asked for.
static func _stacks(sim: PortSim, area: int) -> AreaStacks:
	if area not in sim.area_stacks:
		var gear: String = sim.areas.list[area].settings.gear
		sim.area_stacks[area] = AreaStacks.new(sim.areas.layout(area).stacks.size(), sim.rules.yard_gear[gear].tiers)
	return sim.area_stacks[area]


static func _vehicle(sim: PortSim, id: int) -> Vehicle:
	for vehicle in sim.vehicles:
		if vehicle.id == id:
			return vehicle
	return null


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
