extends RefCounted
## The showcase port, for testing and showing the game's parts: a dense
## two-terminal port on the Estuary's natural coast, built by the commands
## the toolbar sends, with one of nearly everything the game has. Grown as
## features land; tests/test_showcase.gd builds it and runs it.
##
## Layout: berths along the curving coast (a Neopanamax berth for the North
## Terminal; ULCV, Panamax and feeder berths for the South Terminal), a
## spine road down x = SPINE with a connector road east from each berth to
## it, and the highway road from the spine to the site entry, with the
## gates and truck park. Yards line the connectors and the yard lanes
## between them, parallel lanes from each quay road to the spine.

## The grid line the spine road runs down, and the rows it spans.
const SPINE := 300
const SPINE_ROWS := Vector2i(180, 580)
## Each berth: its kind, the row it is centred on, and its terminal (1 north, 2 south).
const BERTHS: Array[Dictionary] = [
	{"kind": "neopanamax", "row": 236, "terminal": 1},
	{"kind": "ulcv", "row": 354, "terminal": 2},
	{"kind": "panamax", "row": 470, "terminal": 2},
	{"kind": "feeder", "row": 540, "terminal": 2},
]


## Imports stacked in the yards at the start.
const BOXES := 3000
## How long each yard block runs along its road, in cells.
const BLOCK := 40
## The yards along each berth's connector, west to east: [side, from, role, gear].
const YARDS: Array = [
	[[-1, 20, "import", "rtg"], [-1, 62, "import", "rtg"], [-1, 104, "export", "rtg"], [1, 20, "reefer", "rtg"], [1, 62, "tranship", "reach_stacker"], [1, 104, "empty", "empty_handler"]],
	[[-1, 20, "import", "rtg"], [-1, 62, "export", "rtg"], [1, 20, "import", "rtg"], [1, 62, "reefer", "rtg"]],
	[[-1, 20, "import", "rtg"], [-1, 62, "export", "rtg"], [1, 20, "import", "reach_stacker"], [1, 62, "empty", "empty_handler"]],
	[[-1, 20, "export", "reach_stacker"], [1, 20, "import", "reach_stacker"], [-1, 62, "tranship", "rtg"], [1, 62, "tranship", "rtg"]],
]

## Each berth's yard lanes, as rows off its connector; 18 apart, so a block
## (8 deep) fits each side with a cell between neighbours' blocks.
const LANES: Array = [[-36, -18, 18], [-36, -18, 18, 36], [-18, 18], [-18]]
## The blocks along each yard lane, west to east, as for YARDS.
const LANE_YARDS: Array = [[-1, 20, "import", "rtg"], [-1, 62, "export", "rtg"], [-1, 104, "import", "rtg"], [1, 20, "export", "rtg"], [1, 62, "import", "rtg"], [1, 104, "export", "rtg"]]


## The rules the showcase plays by: the game's own, with every milestone
## reached and cranes standing the moment they're ordered.
static func rules() -> Dictionary:
	var copy := Content.base().duplicate(true)
	for milestone: Dictionary in copy.milestones.values():
		milestone.teu = 0
		milestone.reputation = 0.0
		milestone.on_time = 0.0
		milestone.productivity = 0.0
	for crane: Dictionary in copy.sts_cranes.values():
		crane.lead_days = 0.0
	return copy


## The showcase for the pause menu in debug builds; a refused command is an
## error, since tests/test_showcase.gd builds it with none.
static func debug_port() -> PortSim:
	var refused: Array[String] = []
	var sim := build(refused)
	for line: String in refused:
		push_error("The showcase port: " + line)
	return sim


## Builds the showcase into a new creative sim; `refused` collects every
## command the sim refused, as "command: reason".
static func build(refused: Array[String]) -> PortSim:
	var sim := PortSim.new(5, rules(), true)
	var berths: Array = BERTHS.duplicate(true)
	for x in 3:
		for y in 3:
			if not sim.land.has(Vector2i(x, y)):
				_do(sim, refused, {"op": "buy_land", "tile": Vector2i(x, y)})
	_do(sim, refused, {"op": "build_road", "from": Vector2i(SPINE, SPINE_ROWS.x), "to": Vector2i(SPINE, SPINE_ROWS.y), "type": "terminal_2_2"})
	_do(sim, refused, {"op": "build_road", "from": Vector2i(SPINE, sim.site_entry().y), "to": sim.site_entry_point(), "type": "terminal_2_2"})
	for berth: Dictionary in berths:
		var click := _shore(sim, berth.row) + Vector2i(8, 0)
		var plan := sim.berth_plan(berth.kind, click)
		if plan.has("error"):
			refused.append("%s berth at %s: %s" % [berth.kind, click, plan.error])
			continue
		_do(sim, refused, {"op": "build_berth", "kind": berth.kind, "cell": click})
		berth.apron = sim.areas.list.keys().max()
		berth.road_x = plan.line[0].x
		for offset: int in [0] + LANES[berths.find(berth)]:
			_do(sim, refused, {"op": "build_road", "from": Vector2i(berth.road_x, berth.row + offset), "to": Vector2i(SPINE, berth.row + offset), "type": "terminal_1_1"})
	var north: Array[int] = [berths[0].apron]
	var south: Array[int] = [berths[1].apron, berths[2].apron, berths[3].apron]
	# Yards along the connectors and yard lanes (a road east is side 1 to its
	# south, -1 to its north).
	for i in berths.size():
		var mine := north if i == 0 else south
		for offset: int in [0] + LANES[i]:
			var road := sim.roads.segment_at(Vector2i((berths[i].road_x + SPINE) / 2, berths[i].row + offset))
			for plan: Array in (YARDS[i] if offset == 0 else LANE_YARDS):
				var block := _area(sim, refused, {"op": "build_area", "type": "yard_block", "segment": road, "side": plan[0], "from": plan[1], "to": plan[1] + BLOCK - 1})
				_do(sim, refused, {"op": "set_area", "id": block, "settings": {"role": plan[2], "gear": plan[3]}})
				mine.append(block)
	# The highway road: the South Terminal's gate, truck park, dangerous goods
	# and rail block, east of the spine.
	var highway := sim.roads.segment_at(Vector2i(450, sim.site_entry().y))
	var gate := _area(sim, refused, {"op": "build_area", "type": "gate_large", "segment": highway, "side": -1, "from": 230, "to": 244})
	south.append(gate)
	south.append(_area(sim, refused, {"op": "build_area", "type": "gate_large", "segment": highway, "side": 1, "from": 230, "to": 244}))
	for id: int in [south[-2], south[-1]]:
		_do(sim, refused, {"op": "set_area", "id": id, "settings": {"level": "automated"}})
	south.append(_area(sim, refused, {"op": "build_area", "type": "truck_park", "segment": highway, "side": -1, "from": 180, "to": 220}))
	var hazard := _area(sim, refused, {"op": "build_area", "type": "yard_block", "segment": highway, "side": -1, "from": 60, "to": 60 + BLOCK - 1})
	_do(sim, refused, {"op": "set_area", "id": hazard, "settings": {"role": "dangerous"}})
	south.append(hazard)
	var rail := _area(sim, refused, {"op": "build_area", "type": "yard_block", "segment": highway, "side": 1, "from": 130, "to": 130 + BLOCK - 1})
	_do(sim, refused, {"op": "set_area", "id": rail, "settings": {"gear": "rmg"}})
	south.append(rail)
	var behind: Vector2i = sim.areas.list[rail].start + sim.areas.list[rail].out * sim.areas.depth_of(sim.areas.list[rail])
	var entry := sim.site_rail_entry()
	var bend := Vector2i(entry.x - 9, behind.y)
	for leg: Array in [[behind, bend], [bend, Vector2i(bend.x, entry.y)], [Vector2i(bend.x, entry.y), entry]]:
		_do(sim, refused, {"op": "build_rail", "from": leg[0], "to": leg[1]})
	# The North Terminal's own gate, on the spine north of the highway.
	var spine_north := sim.roads.segment_at(Vector2i(SPINE, (berths[0].row + sim.site_entry().y) / 2))
	north.append(_area(sim, refused, {"op": "build_area", "type": "gate", "segment": spine_north, "side": 1, "from": 20, "to": 34}))
	_do(sim, refused, {"op": "set_area", "id": north[-1], "settings": {"level": "ocr"}})
	north.append(_area(sim, refused, {"op": "build_area", "type": "gate", "segment": spine_north, "side": -1, "from": 20, "to": 34}))
	_do(sim, refused, {"op": "set_area", "id": north[-1], "settings": {"level": "ocr"}})
	# Two terminals, painted over exactly their areas.
	for group: Array[int] in [north, south]:
		var cells: Array[Vector2i] = []
		for id: int in group:
			cells.append_array(sim.areas.cells(id))
		_do(sim, refused, {"op": "paint_terminal", "cells": cells, "terminal": -1})
	_do(sim, refused, {"op": "name_terminal", "terminal": 1, "name": "North Terminal"})
	_do(sim, refused, {"op": "name_terminal", "terminal": 2, "name": "South Terminal"})
	# Signals where the connectors and the highway meet the spine.
	for row: int in [berths[0].row, sim.site_entry().y, berths[1].row, berths[2].row]:
		_do(sim, refused, {"op": "set_signals", "point": Vector2i(SPINE, row), "on": true})
	# Cranes on each berth's spots, by the ships it takes.
	var cranes := {"neopanamax": "wide_sts", "ulcv": "mega_sts", "panamax": "sts", "feeder": "sts"}
	for berth: Dictionary in berths:
		var spots := AreaFlow.crane_spots(sim, berth.apron)
		for k in mini(spots.size(), 3):
			_do(sim, refused, {"op": "place_sts", "apron": berth.apron, "along": spots[k], "kind": cranes[berth.kind]})
	_do(sim, refused, {"op": "buy_tractors", "count": 72})
	_water(sim, refused, berths)
	_fill(sim)
	# Weekly services at every berth, Meridian (every class) at each and Aurora
	# at the feeder berth, so lines call at both terminals and tranship; and a
	# ship of each berth's class sailing in now.
	var id := 800
	for berth: Dictionary in berths:
		for line: String in (["meridian", "aurora"] if berth.kind == "feeder" else ["meridian"]):
			var spec: Dictionary = sim.rules.ship_classes[berth.kind]
			id += 1
			# Spread through the week, so the port is busy but not swamped.
			var start := (id - 800) * 1800
			sim.contracts.services.append({"id": id, "line": line, "kind": berth.kind, "start": start, "window_hours": spec.window_hours, "moves": spec.import_moves + spec.export_moves, "apron": berth.apron, "any_berth": false, "asked": start})
		var ship := PortSim.Ship.new(berth.kind, "meridian", sim.clock.calendar_minutes() + 60.0 * sim.rules.ship_classes[berth.kind].window_hours, sim.rules.ship_classes[berth.kind].import_moves / 4, sim.rules.ship_classes[berth.kind].export_moves / 4)
		ship.berth = berth.apron
		ship.any_berth = false
		ship.arrived = sim.clock.calendar_minutes()
		sim.ships.append(ship)
		if not AreaFlow.berth(sim, ship):
			refused.append("a %s doesn't berth at its berth" % berth.kind)
	return sim


## Stacks BOXES imports, due over the next few hours, across the import and
## reefer blocks, reefers on the reefer blocks' plugs.
static func _fill(sim: PortSim) -> void:
	var now := sim.clock.calendar_minutes()
	var placed := 0
	var tries := 0
	while placed < BOXES and tries < BOXES * 4:
		for block: int in sim.areas.list:
			var area: Dictionary = sim.areas.list[block]
			if area.type != "yard_block" or area.settings.role not in ["import", "reefer"] or placed == BOXES:
				continue
			tries += 1
			var box := sim._new_box("import", now + 30.0 + placed % 240, "meridian")
			var stacks := AreaFlow._stacks(sim, block)
			if sim.boxes[box].reefer != (area.settings.role == "reefer") or sim.boxes[box].dg or stacks.place(box, sim.boxes[box].teu) < 0:
				sim._drop_box(box)
				continue
			sim.boxes[box].in = now
			placed += 1


## Lanes in from the sea to every berth (the Panamax's wide, the ULCV's
## below the island) joined by a trunk lane along the sea edge, each pocket
## and lane dredged to its ships' draft, an anchorage, a pilot station, a tug
## depot and a breakwater.
static func _water(sim: PortSim, refused: Array[String], berths: Array) -> void:
	for berth: Dictionary in berths:
		var pocket := Marine.pocket(sim, berth.apron)
		var row: int = 380 if berth.kind == "ulcv" else berth.row
		var end := Vector2i(pocket[0].x, row)
		for cell in pocket:
			if cell.y == row:
				end = cell
				break
		var lanes := sim.ship_lanes.segments.size()
		_do(sim, refused, {"op": "build_ship_lane", "from": Vector2i(0, row), "to": end, "type": "wide" if berth.kind == "panamax" else "narrow"})
		var draft: float = sim.rules.ship_classes[berth.kind].draft
		var short := ceili(draft - Marine.pocket_depth(sim, berth.apron))
		if short > 0:
			_do(sim, refused, {"op": "dredge_berth", "apron": berth.apron, "metres": short})
		for segment: int in sim.ship_lanes.segments:
			if segment > lanes:
				var lane_short := ceili(draft - sim.ship_lanes.depth(segment, sim.areas.coast))
				if lane_short > 0:
					_do(sim, refused, {"op": "dredge_lane", "segment": segment, "metres": lane_short})
	# A trunk lane along the sea edge joins every berth's lane, so ships at the
	# anchorage, over the North lane's sea end, reach every berth.
	var rows: Array[int] = [berths[0].row, 380, berths[2].row, berths[3].row]
	for i in range(1, rows.size()):
		_do(sim, refused, {"op": "build_ship_lane", "from": Vector2i(10, rows[i - 1]), "to": Vector2i(10, rows[i]), "type": "narrow"})
	_do(sim, refused, {"op": "build_anchorage", "from": Vector2i(0, 230), "to": Vector2i(99, 310)})
	var station := Vector2i(_shore(sim, 420).x - 5, 420)
	_do(sim, refused, {"op": "build_pilot_station", "cell": station})
	_do(sim, refused, {"op": "hire_pilots", "station": sim.pilot_stations.keys().max(), "count": 3})
	var depot := Vector2i(_shore(sim, 505).x - 5, 505)
	_do(sim, refused, {"op": "build_tug_depot", "cell": depot})
	_do(sim, refused, {"op": "buy_tugs", "depot": sim.tug_depots.keys().max(), "count": 6})
	_do(sim, refused, {"op": "build_breakwater", "from": Vector2i(40, 420), "to": Vector2i(40, 445)})


static func _area(sim: PortSim, refused: Array[String], command: Dictionary) -> int:
	var before: int = sim.areas.list.keys().max() if not sim.areas.list.is_empty() else 0
	_do(sim, refused, command)
	return sim.areas.list.keys().max() if not sim.areas.list.is_empty() and sim.areas.list.keys().max() != before else 0


## The mainland's shore on `row`: the land just east of the first water
## west of the spine, so an island offshore isn't taken for it.
static func _shore(sim: PortSim, row: int) -> Vector2i:
	var cell := Vector2i(SPINE, row)
	while not sim.areas.is_water(cell):
		cell.x -= 1
	return cell + Vector2i(1, 0)


static func _do(sim: PortSim, refused: Array[String], command: Dictionary) -> void:
	var err := sim.apply(command)
	if err:
		refused.append("%s: %s" % [command, err])
