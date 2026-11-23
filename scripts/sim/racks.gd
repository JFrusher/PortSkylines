class_name Racks
extends RefCounted
## Racks at a transfer block's AGV slots (M11), bought for the whole block.
## An AGV bringing an import sets it on its slot's rack and leaves at once;
## an ASC stacks it later. An export an AGV is sent for is staged on a free
## rack while the AGV drives over, and the AGV takes it and goes.
## sim.racks: block id -> {slot: {"box", "state"}}, state one of "in" (an
## import on the rack), "in_moving" (an ASC stacking it), "wait" (an export
## booked for the rack, still in its stack), "out_moving" (an ASC staging
## it), "ready" (an export on the rack).


## Whether transfer block `block` has racks.
static func has(sim: PortSim, block: int) -> bool:
	return sim.areas.list[block].settings.get("racks", false)


## Buys racks for transfer block `block`'s AGV slots.
static func buy(sim: PortSim, block: int) -> String:
	if block not in sim.areas.list or sim.areas.kind_of(sim.areas.list[block]) != "transfer_block":
		return "No transfer block there"
	if has(sim, block):
		return "This transfer block has racks already"
	if not sim._afford(sim.rules.agv.rack_cost):
		return "Not enough money"
	sim.ledger.post("equipment", -sim.rules.agv.rack_cost)
	sim.areas.list[block].settings.racks = true
	sim.racks[block] = {}
	return ""


## AGV `vehicle`, at a front slot of its racked block with its import, sets
## it on the slot's rack if that is free and heads back; true if it did.
static func drop(sim: PortSim, vehicle: Vehicle) -> bool:
	var block := vehicle.area
	if vehicle.kind != "agv" or not vehicle.loaded or not has(sim, block) or AreaFlow._door(sim, vehicle) < 0 or vehicle.slot in sim.racks[block]:
		return false
	sim.racks[block][vehicle.slot] = {"box": vehicle.box, "state": "in"}
	vehicle.box = 0
	vehicle.loaded = false
	_away(sim, vehicle, "returning")
	return true


## Books export `box`, an AGV coming for it, onto a free rack of `block`,
## for an ASC to stage; nothing when every rack is taken.
static func stage(sim: PortSim, block: int, box: int) -> void:
	for slot: int in sim.areas.layout(block).slots.size():
		if slot not in sim.racks[block]:
			sim.racks[block][slot] = {"box": box, "state": "wait"}
			return


## AGV `vehicle`, at a front slot of its racked block for an export: takes
## it from its rack and heads to its crane if it is there, waits if it is
## booked for a rack but not there yet; false when it isn't booked at all.
static func take(sim: PortSim, vehicle: Vehicle) -> bool:
	var block := vehicle.area
	if vehicle.kind != "agv" or vehicle.loaded or not has(sim, block):
		return false
	for slot: int in sim.racks[block]:
		var rack: Dictionary = sim.racks[block][slot]
		if rack.box != vehicle.box:
			continue
		if rack.state != "ready":
			vehicle.state = "handling"  # asked again when the ASC is done
			return true
		sim.racks[block].erase(slot)
		sim._claimed.erase(vehicle.box)
		vehicle.loaded = true
		_away(sim, vehicle, "to_crane")
		return true
	return false


## Gives each racked block's idle ASCs rack work: an import on a rack to its
## stack, an export booked for a rack onto it. An export whose AGV is no
## longer coming goes back to its stack.
static func tick(sim: PortSim) -> void:
	for block: int in sim.racks:
		if block not in sim.areas.list:
			continue
		var stacks := AreaFlow._stacks(sim, block)
		var layout := sim.areas.layout(block)
		for slot: int in sim.racks[block]:
			var rack: Dictionary = sim.racks[block][slot]
			if rack.state == "ready" and rack.box not in sim._claimed:
				rack.state = "in"
			if rack.state not in ["in", "wait"]:
				continue
			var machine := _idle(sim, block)
			if machine == 0:
				break
			if rack.state == "in":
				var position := stacks.place_spot(sim.boxes[rack.box].teu)
				if position < 0:
					continue
				sim.machines.give(machine, 0, layout.stacks[position].bay)
				sim.machine_jobs[machine] = {"rack": block, "slot": slot, "box": rack.box, "position": position}
				rack.state = "in_moving"
			else:
				var bay: int = layout.stacks[stacks.position_of(rack.box)].bay
				var rehandles := stacks.take(rack.box)
				sim.machines.give(machine, bay, 0, rehandles)
				sim.machine_jobs[machine] = {"rack": block, "slot": slot, "box": rack.box, "position": -1}
				rack.state = "out_moving"


## An ASC finished rack work: an import is stacked and its rack freed; an
## export is on its rack, ready.
static func job_done(sim: PortSim, machine: int) -> void:
	var job: Dictionary = sim.machine_jobs[machine]
	sim.machine_jobs.erase(machine)
	if job.rack not in sim.racks or job.box not in sim.boxes:
		return  # gone with its block while the ASC worked
	if job.position >= 0:
		var stacks := AreaFlow._stacks(sim, job.rack)
		var teu: int = sim.boxes[job.box].teu
		stacks.place_at(job.position if stacks.fits(job.position, teu) else stacks.place_spot(teu), job.box, teu)
		sim.boxes[job.box].in = sim.clock.calendar_minutes()
		sim.racks[job.rack].erase(job.slot)
	else:
		sim.racks[job.rack][job.slot].state = "ready"
	AreaFlow._retry_handling(sim, job.rack)


## The boxes sitting on block `block`'s racks: lost with it when it goes.
static func on_racks(sim: PortSim, block: int) -> Array[int]:
	var found: Array[int] = []
	for rack: Dictionary in sim.racks.get(block, {}).values():
		if rack.state in ["in", "ready"]:
			found.append(rack.box)
	return found


## An idle ASC of `block`, the one nearest its front, or 0.
static func _idle(sim: PortSim, block: int) -> int:
	var best := 0
	for id: int in sim.machines.list:
		var machine: Dictionary = sim.machines.list[id]
		if machine.area == block and id not in sim.machine_jobs and (best == 0 or machine.bay < sim.machines.list[best].bay):
			best = id
	return best


## Sends AGV `vehicle` away from its slot, done there: back to the pool
## ("returning") or to its crane ("to_crane").
static func _away(sim: PortSim, vehicle: Vehicle, state: String) -> void:
	var block := vehicle.area
	var door := AreaFlow._door(sim, vehicle)
	sim.handovers.leave(door, vehicle.id)
	sim._set_area(vehicle, 0)
	vehicle.slot = -1
	AreaFlow._head(sim, vehicle, AreaFlow._buffer_end(sim, door) if state == "returning" else vehicle.home, state)
	AreaFlow._promote(sim, block)
