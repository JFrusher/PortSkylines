class_name Guide
extends RefCounted
## The guided start: steps the player works through in order, each done when
## the sim's state shows it. Progress is read from the sim every time, so it
## needs no saving and follows a loaded game. Reads PortSim, never changes it.


## The steps in order for `sim`: {"text", "done": Callable() -> bool}.
static func steps(sim: PortSim) -> Array[Dictionary]:
	var feeder: int = sim.rules.ship_classes.feeder.length
	return [
		{"text": "Build a road from the highway on the east edge to the coast (Roads, key 1).", "done": func() -> bool:
			return sim.map.cells_of(PortMap.Tile.ROAD).any(func(c: Vector2i) -> bool: return c.x <= sim.map.sea_width + 1 and not sim.map.route(sim.map.entry, c).is_empty())},
		{"text": "Bulldoze one road tile near the highway and build a gate there, where lorries check in (Gate, key 5).", "done": func() -> bool:
			return not sim.map.cells_of(PortMap.Tile.GATE).is_empty()},
		{"text": "Build a quay of at least %d tiles along the coast, touching the road (Quay, key 2)." % feeder, "done": func() -> bool:
			return sim.map.berths().any(func(b: Dictionary) -> bool: return b.cells.size() >= feeder and b.cells.any(func(c: Vector2i) -> bool: return not sim.map.route(sim.map.entry, c).is_empty()))},
		{"text": "Place an STS crane on the quay. It arrives the next day (Cranes, key 3).", "done": func() -> bool:
			return not sim.cranes.is_empty() or not sim.crane_orders.is_empty()},
		{"text": "Buy tractors to carry boxes between crane and yard (Cranes, key 3).", "done": func() -> bool:
			return sim.tractors > 0},
		{"text": "Build a yard block beside a road for the boxes (Yard, key 4).", "done": func() -> bool:
			return sim.map.cells_of(PortMap.Tile.YARD).any(func(c: Vector2i) -> bool: return sim.yard.entrance(c) != PortMap.NONE)},
		{"text": "Open Contracts and accept a line's offer. Offers come every few hours.", "done": func() -> bool:
			return not sim.contracts.services.is_empty()},
		{"text": "Wait for the first ship and work it. Speed time up with 3×.", "done": func() -> bool:
			return not sim.ship_log.is_empty()},
	]


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

