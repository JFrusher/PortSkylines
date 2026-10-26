extends RefCounted

const RandomPort := preload("res://tests/random_port.gd")
## Small ports on roads and areas for tests: a coastal terminal, and one
## working its first ship. Building them is checked with push_error, so a
## broken helper shows up as an ERROR line, which CI fails on.

## A terminal on the coast: a 1+1 road south along x = 85 from y = 200 to the
## site entry's row, then east to the entry; a quay apron `apron_length`
## cells long west of the coast road, and a gate on the north side of the
## east road, fed by the westbound lane lorries come in on. Traffic only
## turns back at dead ends, so areas sit beside the lane that reaches them.
static func terminal(apron_length: int, rules := Content.base()) -> PortSim:
	var sim := PortSim.new(0, rules, true)
	var entry := sim.site_entry()
	sim.apply({"op": "build_road", "from": Vector2i(85, 200), "to": Vector2i(85, entry.y), "type": "terminal_1_1"})
	sim.apply({"op": "build_road", "from": Vector2i(85, entry.y), "to": entry, "type": "terminal_1_1"})
	var coast := sim.roads.segment_at(Vector2i(85, 250))
	var east := sim.roads.segment_at(Vector2i(200, entry.y))
	_built(sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 0, "to": apron_length - 1}), "the terminal's apron is built")
	_built(sim.apply({"op": "build_area", "type": "gate", "segment": east, "side": -1, "from": 300, "to": 314}), "the terminal's gate is built")
	sim.apply({"op": "set_terminal", "id": 2, "terminal": 1})
	return sim


## `terminal` with an import yard block, a crane, tractors, and a feeder
## alongside carrying `imports` boxes with room for `exports`; with exports
## there is an export block too, filled by export lorries while the crane comes.
static func working_terminal(imports: int, exports := 0, rules := Content.base()) -> PortSim:
	var sim := terminal(60, rules)
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
	_built("" if AreaFlow.berth(sim, ship) else "refused", "the feeder berths")
	ship.state = PortSim.Ship.State.WORKING
	ship.sail = 1.0
	ship.berthed = sim.clock.calendar_minutes()
	return sim


## A port for rule tests, like the tile tests' port: `terminal` with an apron
## long enough for a Panamax, an import block, two cranes and six tractors,
## under `rules` (see RandomPort.quick), and weekly `calls` services. Built
## for free, then the cash is set back to the start money and creative mode
## off, so tests start from an ordinary port.
static func base(rules := RandomPort.quick(), calls := "feeder") -> PortSim:
	var sim := terminal(80, rules)
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_built(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 30, "to": 59}), "the import block is built")
	_built(sim.apply({"op": "set_terminal", "id": 3, "terminal": 1}), "the block joins the terminal")
	for along: int in [20, 40]:
		_built(sim.apply({"op": "place_sts", "apron": 1, "along": along}), "a crane is ordered")
	_built(sim.apply({"op": "buy_tractors", "count": 6}), "tractors are bought")
	sim.creative = false
	sim.ledger.cash = rules.start_money
	if calls != "":
		RandomPort.calls(sim, calls)
	return sim


## An export block next to `base`'s import block, in its terminal.
static func add_export_block(sim: PortSim) -> int:
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	sim.creative = true
	_built(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 61, "to": 90}), "the export block is built")
	sim.creative = false
	var id: int = sim.areas.list.keys()[-1]
	_built(sim.apply({"op": "set_area", "id": id, "settings": {"role": "export"}}), "the export block is set")
	_built(sim.apply({"op": "set_terminal", "id": id, "terminal": 1}), "it joins the terminal")
	return id


## The first slice's chain, built with commands only on `terminal`: an import
## and an export block, an STS crane on the apron and tractors. Ships come
## from contracts; nothing is placed by hand.
static func chain(seed_value: int) -> PortSim:
	var sim := terminal(60)
	sim.rng.seed = seed_value
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_built(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 30, "to": 59}), "the import block is built")
	_built(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": 1, "from": 61, "to": 90}), "the export block is built")
	_built(sim.apply({"op": "set_area", "id": 4, "settings": {"role": "export"}}), "the export block is set")
	for id: int in [3, 4]:
		_built(sim.apply({"op": "set_terminal", "id": id, "terminal": 1}), "the blocks join the terminal")
	for along: int in [12, 30, 48]:
		_built(sim.apply({"op": "place_sts", "apron": 1, "along": along}), "a crane is ordered")
	_built(sim.apply({"op": "buy_tractors", "count": 6}), "tractors are bought")
	return sim


## Gives `sim` every land tile of the site, for tests that build anywhere.
static func owned(sim: PortSim) -> PortSim:
	var metres: float = sim.rules.land.metres
	for x in ceili(sim.rules.site.width / metres):
		for y in ceili(sim.rules.site.height / metres):
			sim.land[Vector2i(x, y)] = true
	return sim


static func _built(err: String, what: String) -> void:
	if err != "":
		push_error("%s: %s" % [what, err])
