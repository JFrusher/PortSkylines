extends RefCounted
## Small ports on roads and areas for tests: a coastal terminal, and one
## working its first ship. Building them is checked with push_error, so a
## broken helper shows up as an ERROR line, which CI fails on.

## A terminal on the coast: a 1+1 road south along x = 85 from y = 100 to the
## site entry's row, then east to the entry; a quay apron `apron_length`
## cells long west of the coast road, and a gate on the north side of the
## east road, fed by the westbound lane lorries come in on. Traffic only
## turns back at dead ends, so areas sit beside the lane that reaches them.
static func terminal(apron_length: int) -> PortSim:
	var sim := PortSim.new(0, Content.base(), true)
	var entry := sim.site_entry()
	sim.apply({"op": "build_road", "from": Vector2i(85, 100), "to": Vector2i(85, entry.y), "type": "terminal_1_1"})
	sim.apply({"op": "build_road", "from": Vector2i(85, entry.y), "to": entry, "type": "terminal_1_1"})
	var coast := sim.roads.segment_at(Vector2i(85, 150))
	var east := sim.roads.segment_at(Vector2i(200, entry.y))
	_built(sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 0, "to": apron_length - 1}), "the terminal's apron is built")
	_built(sim.apply({"op": "build_area", "type": "gate", "segment": east, "side": -1, "from": 300, "to": 314}), "the terminal's gate is built")
	sim.apply({"op": "set_terminal", "id": 2, "terminal": 1})
	return sim


## `terminal` with an import yard block, a crane, tractors, and a feeder
## alongside carrying `imports` boxes with room for `exports`; with exports
## there is an export block too, filled by export lorries while the crane comes.
static func working_terminal(imports: int, exports := 0) -> PortSim:
	var sim := terminal(60)
	# South of the east road, fed by the eastbound lane tractors come off the coast road on.
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_built(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 30, "to": 59}), "the terminal's yard block is built")
	sim.apply({"op": "set_terminal", "id": 3, "terminal": 1})
	if exports > 0:
		_built(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 61, "to": 90}), "the terminal's export block is built")
		sim.apply({"op": "set_area", "id": 4, "settings": {"role": "export"}})
		sim.apply({"op": "set_terminal", "id": 4, "terminal": 1})
	sim.apply({"op": "place_sts", "apron": 1, "along": 20})
	for i in roundi(sim.rules.sts_crane.lead_days * SimClock.TICKS_PER_DAY):
		sim.tick()
	sim.apply({"op": "buy_tractors", "count": 4})
	var ship := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 600.0, imports, exports)
	sim.ships.append(ship)
	_built("" if sim._berth(ship) else "refused", "the feeder berths")
	ship.state = PortSim.Ship.State.WORKING
	ship.sail = 1.0
	ship.berthed = sim.clock.calendar_minutes()
	return sim


static func _built(err: String, what: String) -> void:
	if err != "":
		push_error("%s: %s" % [what, err])
