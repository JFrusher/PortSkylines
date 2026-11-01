class_name Guide
extends RefCounted
## The guided start: steps the player works through in order, each done when
## the sim's state shows it. Progress is read from the sim every time, so it
## needs no saving and follows a loaded game. Reads PortSim, never changes it.


## Services the guide asks for, so ships call through the week, not once a week.
const SERVICES := 3
## Cells a yard block runs along the road, so it holds a feeder's imports while
## they wait for lorries; a shorter one fills and stalls the cranes.
const YARD_LENGTH := 40


## The steps in order for `sim`: {"text", "done": Callable() -> bool}.
static func steps(sim: PortSim) -> Array[Dictionary]:
	var feeder := AreaFlow.ship_cells(sim, "feeder")
	return [
		{"text": "Place a feeder berth: pick it under Quay (key 2) and click the coast. It brings its own road along its back.", "done": func() -> bool:
			return _areas(sim, "quay_apron").any(func(id: int) -> bool: return RoadNet.length(sim.areas.list[id].start, sim.areas.list[id].end) + 1 >= feeder)},
		{"text": "Ships need a way in: draw a ship lane from the map's west edge into the water in front of your berth (Water, key 7).", "done": func() -> bool:
			return _areas(sim, "quay_apron").any(func(id: int) -> bool: return Marine.reaches(sim, "feeder", id))},
		{"text": "Draw a two-lane road from the highway at the middle of the east edge to the berth's road (Roads, key 1).", "done": func() -> bool:
			return sim.roads.segment_at(sim.site_entry()) != 0},
		{"text": "Drag a gate along the road near the highway, beside the lane coming in, where lorries check in (Gate, key 5).", "done": func() -> bool:
			return not _areas(sim, "gate").is_empty()},
		{"text": "A terminal needs its gate and quay apron. Open the map (Map, key 6) and paint a terminal over your berth, gate and the ground beside your roads.", "done": func() -> bool:
			return sim.areas.terminals.keys().any(func(t: int) -> bool: return sim.areas.terminal_error(t) == "")},
		{"text": "Drag a yard block at least %d m long along the road from the highway, inside your terminal's paint. A feeder unloads hundreds of boxes, so a short block fills and stops the cranes. It starts as an import block (Yard, key 4)." % Grid.metres(YARD_LENGTH), "done": func() -> bool:
			return _areas(sim, "yard_block").any(func(id: int) -> bool:
				var block: Dictionary = sim.areas.list[id]
				return RoadNet.length(block.start, block.end) + 1 >= YARD_LENGTH and sim.areas.terminal_error(block.terminal) == "" and sim.areas.idle_reason(id) == "")},
		{"text": "Place STS cranes on both of the berth's marked crane spots: one crane alone can't work a feeder within its window (Cranes, key 3).", "done": func() -> bool:
			return sim.cranes.size() + sim.crane_orders.size() >= sim.rules.berths.feeder.crane_spots},
		{"text": "Buy tractors to carry boxes between crane and yard (Cranes, key 3).", "done": func() -> bool:
			return sim.tractors > 0},
		{"text": "Open Contracts and accept %d lines' offers. Each is a weekly call, so several keep the berth busy; offers come every few hours once the crane is up." % SERVICES, "done": func() -> bool:
			return sim.contracts.services.size() >= SERVICES},
		{"text": "Wait for the first ship and work it. Speed time up with 3×.", "done": func() -> bool:
			return not sim.ship_log.is_empty()},
	]


static func _areas(sim: PortSim, kind: String) -> Array:
	return sim.areas.list.keys().filter(func(id: int) -> bool: return sim.areas.kind_of(sim.areas.list[id]) == kind)


## The index of the step to do now, or steps().size() once the first ship has
## been worked, whatever the player builds or bulldozes after that.
static func current(sim: PortSim) -> int:
	var list := steps(sim)
	if list[-1].done.call():
		return list.size()
	for i in list.size():
		if not list[i].done.call():
			return i
	return list.size()

