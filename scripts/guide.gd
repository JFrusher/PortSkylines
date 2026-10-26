class_name Guide
extends RefCounted
## The guided start: steps the player works through in order, each done when
## the sim's state shows it. Progress is read from the sim every time, so it
## needs no saving and follows a loaded game. Reads PortSim, never changes it.


## Services the guide asks for, so ships call through the week, not once a week.
const SERVICES := 3


## The steps in order for `sim`: {"text", "done": Callable() -> bool}.
static func steps(sim: PortSim) -> Array[Dictionary]:
	var feeder := AreaFlow.ship_cells(sim, "feeder")
	return [
		{"text": "Place a feeder berth: pick it under Quay (key 2) and click the coast. It brings its own road along its back.", "done": func() -> bool:
			return _areas(sim, "quay_apron").any(func(id: int) -> bool: return RoadNet.length(sim.areas.list[id].start, sim.areas.list[id].end) + 1 >= feeder)},
		{"text": "Draw a terminal road from the highway at the middle of the east edge to the berth's road (Roads, key 1).", "done": func() -> bool:
			return sim.roads.segment_at(sim.site_entry()) != 0},
		{"text": "Drag a gate along the road near the highway, beside the lane coming in, where lorries check in (Gate, key 5).", "done": func() -> bool:
			return not _areas(sim, "gate").is_empty()},
		{"text": "A terminal needs its gate and quay apron. Inspect the gate (key 8) and join it to the apron's terminal.", "done": func() -> bool:
			return sim.areas.terminals.keys().any(func(t: int) -> bool: return sim.areas.terminal_error(t) == "")},
		{"text": "Drag a yard block along the coast road's land side, behind the apron, and join it to the terminal too. It starts as an import block (Yard, key 4).", "done": func() -> bool:
			return _areas(sim, "yard_block").any(func(id: int) -> bool: return sim.areas.terminal_error(sim.areas.list[id].terminal) == "" and sim.areas.idle_reason(id) == "")},
		{"text": "Place an STS crane on one of the berth's marked crane spots (Cranes, key 3).", "done": func() -> bool:
			return not sim.cranes.is_empty() or not sim.crane_orders.is_empty()},
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

