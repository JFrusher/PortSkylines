class_name AreaFlow
extends RefCounted
## The port's work on roads and areas: ships berth along quay aprons, STS
## cranes stand on their rails, and boxes move by slots and machine jobs. It
## runs beside the tile flow in PortSim until M5 step 22 removes that. Its
## functions take the sim, whose state they work on, so nothing refers back.

## shortcut: ship lengths are in 25 m tiles until M5 step 22 moves them to metres.
const TILE_METRES := 25

## How many cells of quay a ship of `kind` needs.
static func ship_cells(sim: PortSim, kind: String) -> int:
	return ceili(sim.rules.ship_classes[kind].length * TILE_METRES / float(Grid.CELL))


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
	if along < 0 or along >= _length(sim, apron):
		return "STS cranes stand on a quay apron's rails"
	var room := ceili(sim.rules.sts_crane.width / float(Grid.CELL))
	var near := func(a: int, k: int) -> bool: return a == apron and absi(k - along) < room
	if sim.cranes.any(func(c: PortSim.Crane) -> bool: return near.call(c.apron, c.along)) or sim.crane_orders.any(func(o: Dictionary) -> bool: return o.has("apron") and near.call(o.apron, o.along)):
		return "Too close to another crane"
	return ""


static func _length(sim: PortSim, apron: int) -> int:
	var area: Dictionary = sim.areas.list[apron]
	return RoadNet.length(area.start, area.end) + 1


## A tractor's speed on the grid, in cells a vehicle second: the data gives
## it in 25 m tiles.
static func tractor_speed(sim: PortSim) -> float:
	return sim.rules.tractor.speed * TILE_METRES / Grid.CELL


## One tick of the area flow, after ships: machines work, then vehicles drive.
static func tick(sim: PortSim) -> void:
	_fit_machines(sim)
	for machine: int in sim.machines.tick():
		_machine_done(sim, machine)
	for vehicle: Vehicle in sim.area_vehicles.duplicate():
		_drive(sim, vehicle)


## One tick of an apron ship alongside: each of its cranes discharges, and
## once the holds are empty and the cranes idle it sails.
static func work(sim: PortSim, ship: PortSim.Ship) -> void:
	var working := cranes_for(sim, ship)
	if working.is_empty():
		sim._event("A %s is waiting: no crane stands along it" % ship.kind)
		return
	var move_minutes: float = 60.0 / (sim.rules.sts_crane.rate * sim.rules.crane_interference)
	for crane in working:
		if ship.boxes > 0:
			_discharge(sim, crane, ship, move_minutes)
	if ship.boxes == 0 and working.all(func(c: PortSim.Crane) -> bool: return c.tractor == 0):
		# shortcut: loading exports from areas comes in M5 step 19.5; until then ships sail without them.
		sim._sail(ship, working.size())
		sim._event("A %s sailed %d exports short: none ready in the yard" % [ship.kind, ship.exports] if ship.exports > 0 else "A %s is sailing, fully loaded" % ship.kind)


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


## Puts a tractor from the pool in the apron slot under `crane`, bound for an
## import block of the ship's terminal with room. False when there is no free
## tractor, slot or block yet.
static func _send_tractor(sim: PortSim, crane: PortSim.Crane, ship: PortSim.Ship) -> bool:
	if sim._tractors_out() >= sim.tractors:
		return false
	var block := _import_block(sim, sim.areas.list[ship.apron].terminal)
	if block == 0:
		sim._event("A ship is waiting: no import yard block with room and a road in its terminal")
		return false
	var depth: int = sim.rules.area_types.quay_apron.depth
	var slot: Array = sim.areas.layout(ship.apron).slots[crane.along / AreaLayout.BAY * (depth - 4)]
	var tractor := Vehicle.new(sim._next_vehicle, "tractor", [slot[1]] as Array[Vector2i])
	if not sim.lane_traffic.place(tractor):
		return false
	sim._next_vehicle += 1
	tractor.state = "under_crane"
	tractor.area = block
	sim.area_vehicles.append(tractor)
	crane.tractor = tractor.id
	return true


## The first import yard block of `terminal` that works and has room for one
## more box than is already on its way, or 0.
static func _import_block(sim: PortSim, terminal: int) -> int:
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type != "yard_block" or area.terminal != terminal or area.settings.role != "import" or sim.areas.idle_reason(id) != "":
			continue
		var coming := sim.area_vehicles.filter(func(v: Vehicle) -> bool: return v.area == id and v.loaded).size()
		if _stacks(sim, id).room() > coming:
			return id
	return 0


## Sends a lorry in from the site entry for an import box due out, to its
## terminal's gate first; false when no box is due or the way in is busy.
static func dispatch_import_lorry(sim: PortSim) -> bool:
	var now := sim.clock.calendar_minutes()
	for block: int in sim.area_stacks:
		if block not in sim.areas.list or sim.areas.idle_reason(block) != "":
			continue
		var gate := _gate_of(sim, sim.areas.list[block].terminal)
		if gate == 0:
			continue
		for box: int in sim.area_stacks[block].boxes():
			if box in sim._claimed or sim.boxes[box].kind != "import" or sim.boxes[box].due > now:
				continue
			var entry := _entry_cell(sim)
			if entry == PortMap.NONE:
				return false
			var lorry := Vehicle.new(sim._next_vehicle, "lorry", [entry] as Array[Vector2i])
			sim.lane_traffic.place(lorry)
			sim._next_vehicle += 1
			lorry.box = box
			sim._claimed[box] = true
			sim.area_vehicles.append(lorry)
			_go_to(sim, lorry, gate)
			return true
	return false


## A free lane cell at the site entry heading into the site, or NONE.
static func _entry_cell(sim: PortSim) -> Vector2i:
	for cell in _edge_cells(sim):
		if sim.lane_traffic.holder(cell) == 0 and sim.lanes.steps_at(cell).any(func(step: Vector2i) -> bool: return step.x < 0):
			return cell
	return PortMap.NONE


## A lane cell at the site entry leaving the site, or NONE.
static func _exit_cell(sim: PortSim) -> Vector2i:
	for cell in _edge_cells(sim):
		var steps := sim.lanes.steps_at(cell)
		if not steps.is_empty() and not steps.any(func(step: Vector2i) -> bool: return step.x < 0):
			return cell
	return PortMap.NONE


## Cells on the site's east edge near the entry, where the highway's lanes meet the roads.
static func _edge_cells(sim: PortSim) -> Array[Vector2i]:
	var entry := sim.site_entry()
	var found: Array[Vector2i] = []
	for dy in range(-8, 9):
		found.append(entry + Vector2i(0, dy))
	return found


## The first working gate of `terminal`, or 0.
static func _gate_of(sim: PortSim, terminal: int) -> int:
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type == "gate" and area.terminal == terminal and sim.areas.idle_reason(id) == "":
			return id
	return 0


## The yard block holding `box`, or 0.
static func _block_of(sim: PortSim, box: int) -> int:
	for block: int in sim.area_stacks:
		if sim.area_stacks[block].boxes().has(box):
			return block
	return 0


## Books `vehicle` a handover slot at `area` and heads there; with no slot
## free it drives into the buffer strip and waits its turn.
static func _go_to(sim: PortSim, vehicle: Vehicle, area: int) -> void:
	vehicle.area = area
	vehicle.slot = -1
	if sim.handovers.arrive(area, vehicle.id) == "slot":
		_head_to_slot(sim, vehicle)
		return
	_head(sim, vehicle, _buffer_end(sim, area), "queued")


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
	return (sim.rules.lorry_speed * TILE_METRES / Grid.CELL) if vehicle.kind == "lorry" else tractor_speed(sim)


static func _drive(sim: PortSim, vehicle: Vehicle) -> void:
	if vehicle.state.begins_with("no_route:"):
		_head(sim, vehicle, vehicle.target, vehicle.state.trim_prefix("no_route:"))
		return
	if vehicle.state == "at_gate":
		vehicle.timer -= SimClock.CALENDAR_MINUTES_PER_TICK
		if vehicle.timer <= 0.0:
			_gate_done(sim, vehicle)
		return
	if vehicle.state not in ["to_slot", "queued", "returning", "leaving"]:
		return
	if not sim.lane_traffic.advance(vehicle, _speed(sim, vehicle)):
		return
	match vehicle.state:
		"to_slot":
			_arrived(sim, vehicle)
		"returning":
			_gone(sim, vehicle)
		"leaving":
			if vehicle.loaded and sim.boxes[vehicle.box].kind == "import":
				sim.boxes.erase(vehicle.box)
				sim.delivered += 1
			_gone(sim, vehicle)


static func _gone(sim: PortSim, vehicle: Vehicle) -> void:
	sim.lane_traffic.leave(vehicle)
	sim.area_vehicles.erase(vehicle)


## A vehicle reached its handover slot: at a gate it is checked for the gate
## time, which starts a lorry's turn on the way in and ends it on the way
## out; at a yard block a machine is asked for.
static func _arrived(sim: PortSim, vehicle: Vehicle) -> void:
	if sim.areas.list[vehicle.area].type != "gate":
		vehicle.state = "handling"
		_start_handling(sim, vehicle)
		return
	vehicle.state = "at_gate"
	vehicle.timer = sim.rules.gate_minutes
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


## Done at the gate: in, a lorry heads for the block holding its box; out,
## it heads for the site exit.
static func _gate_done(sim: PortSim, vehicle: Vehicle) -> void:
	var gate := vehicle.area
	sim.handovers.leave(gate, vehicle.id)
	_promote(sim, gate)
	if vehicle.loaded:
		vehicle.area = 0
		vehicle.slot = -1
		_head(sim, vehicle, _exit_cell(sim), "leaving")
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
		if machine.area != vehicle.area or not machine.job.is_empty():
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
		vehicle.area = 0
		vehicle.slot = -1
		_head(sim, vehicle, _buffer_end(sim, block), "returning")
	else:
		sim.dwell_times.append(sim.clock.calendar_minutes() - sim.boxes[vehicle.box].in)
		if sim.dwell_times.size() > 50:
			sim.dwell_times.pop_front()
		sim._claimed.erase(vehicle.box)
		vehicle.loaded = true
		var gate := _gate_of(sim, sim.areas.list[block].terminal)
		if gate:
			_go_to(sim, vehicle, gate)
		else:
			vehicle.area = 0
			vehicle.slot = -1
			_head(sim, vehicle, _exit_cell(sim), "leaving")
	_promote(sim, block)
	for other: Vehicle in sim.area_vehicles:
		if other.area == block and other.state == "handling":
			_start_handling(sim, other)


## Sends the vehicles just given a slot at `area` on to it.
static func _promote(sim: PortSim, area: int) -> void:
	for waiting: Vehicle in sim.area_vehicles:
		if waiting.area == area and waiting.slot < 0 and sim.handovers.slot_of(area, waiting.id) >= 0:
			_head_to_slot(sim, waiting)


## Gives each yard block the machines its gear and size call for, adding
## idle ones as it grows, and drops the machines of blocks that have gone.
static func _fit_machines(sim: PortSim) -> void:
	for id: int in sim.machines.list.keys():
		var area: int = sim.machines.list[id].area
		if area not in sim.areas.list and sim.machines.list[id].job.is_empty():
			sim.machines.list.erase(id)
	for area: int in sim.areas.list:
		if sim.areas.list[area].type != "yard_block":
			continue
		var gear: String = sim.areas.list[area].settings.gear
		var bays: int = sim.areas.layout(area).slots.size()
		var have := sim.machines.list.values().filter(func(m: Dictionary) -> bool: return m.area == area).size()
		for i in sim.machines.count_for(gear, bays) - have:
			sim.machines.add(area, gear, 0)


## Takes away area `id` and everything working there: boxes stacked in it
## are lost, vehicles bound for it are scrapped with their loads, its
## machines go, a ship at it sails at once and its cranes come down.
static func remove(sim: PortSim, id: int) -> void:
	var lost := 0
	if id in sim.area_stacks:
		for box: int in sim.area_stacks[id].boxes():
			sim.boxes.erase(box)
			lost += 1
		sim.area_stacks.erase(id)
	for vehicle: Vehicle in sim.area_vehicles.duplicate():
		if vehicle.area == id:
			if vehicle.loaded:
				sim.boxes.erase(vehicle.box)
				lost += 1
			sim.lane_traffic.leave(vehicle)
			sim.area_vehicles.erase(vehicle)
	for machine: int in sim.machines.list.keys():
		if sim.machines.list[machine].area == id:
			sim.machines.list.erase(machine)
			sim.machine_jobs.erase(machine)
	for ship: PortSim.Ship in sim.ships:
		if ship.apron == id and ship.state != PortSim.Ship.State.LEAVING:
			sim._sail(ship, cranes_for(sim, ship).size())
			sim._event("A %s sailed early: its quay apron was removed" % ship.kind)
	for crane: PortSim.Crane in sim.cranes.duplicate():
		if crane.apron == id:
			var tractor := _vehicle(sim, crane.tractor)
			if tractor:
				sim.lane_traffic.leave(tractor)
				sim.area_vehicles.erase(tractor)
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
	for vehicle in sim.area_vehicles:
		if vehicle.id == id:
			return vehicle
	return null
