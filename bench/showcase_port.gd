extends RefCounted

const RandomPort := preload("res://tests/random_port.gd")
## The showcase port, for testing and showing the game's parts: a dense
## two-terminal port on the Estuary's natural coast, built by the commands
## the toolbar sends, with one of nearly everything the game has. Grown as
## features land; tests/test_showcase.gd builds it and runs it.
##
## Layout: berths along the curving coast (a Neopanamax berth for the North
## Terminal, an AGV terminal (M11): an AGV zone from its quay to transfer
## blocks (reefer ones too), lorries at their backs, an AGV depot with
## chargers, racks; ULCV,
## Panamax and feeder berths for the South Terminal, with manual gear), a
## spine road down x = SPINE with a connector road east from each berth to
## it, and the highway road from the spine to the site entry, with the
## gates and truck park. Yards line the connectors and the yard lanes
## between them, parallel lanes from each quay road to the spine. A barge
## berth on the river's south bank joins the spine's north end, with a gate
## and blocks of its own along the spine, in the South Terminal. M13's
## policies are on, some blocks stack by departure or have rules of their
## own, and a template is saved and applied. M10's curves:
## a yard road curving south off the spine to a roundabout, with blocks on
## its bend, the track's corner to the rail block on a curve, and the river
## channel curving down the river. M11's harbour life: every event kind on,
## a manned workshop and fire station, a customs block with inspectors and a
## gate scanner, shore power at the ULCV berth, a tree belt toward the town
## and a fund for it.

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


## Where the barge berth is clicked, on the river's south bank.
const BARGE_CLICK := Vector2i(310, 110)

## The curved yard road east of the spine: straight out to BEND_FROM, then
## curving through BEND_CONTROL to BEND_TO, ending in a roundabout of
## BEND_RING cells' radius; and its blocks along the bend, as for YARDS.
const BEND_START := Vector2(SPINE, 420)
const BEND_FROM := Vector2(400, 420)
const BEND_CONTROL := Vector2(460, 420)
const BEND_TO := Vector2(460, 480)
const BEND_RING := 8.0
const BEND_YARDS: Array = [[1, 4, "import", "rtg"], [1, 50, "export", "rtg"], [-1, 4, "empty", "empty_handler"], [-1, 50, "empty", "empty_handler"]]

## Policies switched on; the other two (day gates, day shifts) idle the port at night.
const POLICIES: Array[String] = ["appointments", "dual_cycling"]

## Imports stacked in the yards at the start.
const BOXES := 3000
## How long each yard block runs along its road, in cells.
const BLOCK := 40
## The yards along each berth's connector, west to east: [side, from, role, gear].
const YARDS: Array = [
	[],  # the North Terminal is the AGV terminal: transfer blocks, built by _agv_terminal
	[[-1, 20, "import", "rtg"], [-1, 62, "export", "rtg"], [1, 20, "import", "straddle"], [1, 62, "reefer", "rtg"]],
	[[-1, 20, "import", "rtg"], [-1, 62, "empty", "empty_handler"], [1, 20, "import", "reach_stacker"], [1, 62, "empty", "empty_handler"]],
	[[-1, 20, "export", "reach_stacker"], [1, 20, "import", "reach_stacker"], [-1, 62, "tranship", "rtg"], [1, 62, "tranship", "rtg"]],
]

## Each berth's yard lanes, as rows off its connector; 18 apart, so a block
## (8 deep) fits each side with a cell between neighbours' blocks.
const LANES: Array = [[-18, 18], [-36, -18, 18, 36], [-18, 18], [-18]]
## The North Terminal's transfer blocks, along its connector: where each
## starts on it, either side, 12 cells long, reaching back to the lanes
## either side, where lorries come; and the dangerous-goods one, alone at
## the east end, as dangerous goods stand 24 m from other blocks.
const AGV_BLOCKS: Array[int] = [30, 50, 70, 90, 110]
## Their roles, north side then south: reefers plugged in as in a real ASC
## block, one block each side.
const AGV_ROLES: Array[String] = ["import", "export", "reefer", "import", "export", "export", "import", "reefer", "export", "import"]
const AGV_DG_BLOCK := 134
## The AGV depot's AGVs and chargers.
const AGVS := 20
const CHARGERS := 8
## The barge berth's own gate and blocks along the spine's run north to it:
## [type, side, from, to, role or gate level].
const BARGE_AREAS: Array = [["gate", -1, 2, 16, "ocr"], ["yard_block", -1, 19, 40, "import"], ["yard_block", 1, 10, 21, "export"], ["yard_block", 1, 56, 67, "dangerous"]]

## The blocks along each yard lane, west to east, as for YARDS.
const LANE_YARDS: Array = [[-1, 20, "import", "rtg"], [-1, 62, "export", "rtg"], [-1, 104, "import", "rtg"], [1, 20, "export", "rtg"], [1, 62, "import", "rtg"], [1, 104, "export", "rtg"]]


## The rules the showcase plays by: the game's own, with every milestone
## reached and cranes standing the moment they're ordered.
static func rules() -> Dictionary:
	var copy := RandomPort.small_site(Content.base())
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
		# Laid out for berths facing west, as they did before berths turned (M10 step 21).
		var plan := sim.berth_plan(berth.kind, click, 180.0)
		if plan.has("error"):
			refused.append("%s berth at %s: %s" % [berth.kind, click, plan.error])
			continue
		_do(sim, refused, {"op": "build_berth", "kind": berth.kind, "cell": click, "angle": 180.0})
		berth.apron = sim.areas.list.keys().max()
		berth.road_x = plan.line[0].x
		for offset: int in [0] + LANES[berths.find(berth)]:
			_do(sim, refused, {"op": "build_road", "from": Vector2i(berth.road_x, berth.row + offset), "to": Vector2i(SPINE, berth.row + offset), "type": "terminal_1_1"})
	var north: Array[int] = [berths[0].apron]
	# The barge berth, its road run on from the spine's north end.
	# Facing north onto the river, as before berths turned.
	var barge_road: int = sim.berth_plan("barge", BARGE_CLICK, 270.0).line[0].y
	_do(sim, refused, {"op": "build_berth", "kind": "barge", "cell": BARGE_CLICK, "angle": 270.0})
	var barge: int = sim.areas.list.keys().max()
	_do(sim, refused, {"op": "build_road", "from": Vector2i(SPINE, barge_road), "to": Vector2i(SPINE, SPINE_ROWS.x), "type": "terminal_2_2"})
	var south: Array[int] = [berths[1].apron, berths[2].apron, berths[3].apron]
	# Yards along the connectors and yard lanes (a road east is side 1 to its
	# south, -1 to its north).
	for i in range(1, berths.size()):
		var mine := south
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
	var behind: Vector2i = sim.areas.cell_at(rail, 0, sim.areas.depth_of(sim.areas.list[rail]))
	var entry := sim.site_rail_entry()
	var bend := Vector2i(entry.x - 9, behind.y)
	# The first corner on a curve 20 cells each way (14 cells' radius at its tightest), the last square.
	var into := bend - Vector2i(20, 0)
	var out_of := bend + Vector2i(0, 20 * signi(entry.y - bend.y))
	_do(sim, refused, {"op": "build_rail", "from": behind, "to": into})
	_do(sim, refused, {"op": "build_rail", "from": into, "to": out_of, "control": Vector2(bend) + Vector2(0.5, 0.5)})
	for leg: Array in [[out_of, Vector2i(bend.x, entry.y)], [Vector2i(bend.x, entry.y), entry]]:
		_do(sim, refused, {"op": "build_rail", "from": leg[0], "to": leg[1]})
	# The curved yard road, its blocks on the bend and the roundabout at its end.
	_do(sim, refused, {"op": "build_road", "from": BEND_START, "to": BEND_FROM, "type": "terminal_1_1"})
	_do(sim, refused, {"op": "build_road", "from": BEND_FROM, "to": BEND_TO, "type": "terminal_1_1", "control": BEND_CONTROL})
	var curve := sim.roads.segment_between(BEND_FROM, BEND_TO)
	for plan: Array in BEND_YARDS:
		var block := _area(sim, refused, {"op": "build_area", "type": "yard_block", "segment": curve, "side": plan[0], "from": plan[1], "to": plan[1] + BLOCK - 1})
		_do(sim, refused, {"op": "set_area", "id": block, "settings": {"role": plan[2], "gear": plan[3]}})
		south.append(block)
	_do(sim, refused, {"op": "build_roundabout", "centre": BEND_TO + Vector2(0, BEND_RING), "radius": BEND_RING})
	# The barge berth is the South Terminal's, served by tractors, with a gate
	# and blocks of its own on the spine's run north to it: barges take the
	# boxes big ships bring for places up the river, so they share a terminal.
	var barge_areas: Array[int] = [barge]
	var spine_to_barge := sim.roads.segment_at(Vector2i(SPINE, (SPINE_ROWS.x + barge_road) / 2))
	for plan: Array in BARGE_AREAS:
		var id := _area(sim, refused, {"op": "build_area", "type": plan[0], "segment": spine_to_barge, "side": plan[1], "from": plan[2], "to": plan[3]})
		_do(sim, refused, {"op": "set_area", "id": id, "settings": {"level": plan[4]} if plan[0] == "gate" else {"role": plan[4]}})
		barge_areas.append(id)
	# The North Terminal: AGVs from the quay to transfer blocks, lorries at their backs.
	var agv := _agv_terminal(sim, refused, berths[0])
	north.append_array(agv.areas)
	# The North Terminal's own gate, on the spine north of the highway.
	var spine_north := sim.roads.segment_at(Vector2i(SPINE, (berths[0].row + sim.site_entry().y) / 2))
	north.append(_area(sim, refused, {"op": "build_area", "type": "gate", "segment": spine_north, "side": 1, "from": 20, "to": 34}))
	_do(sim, refused, {"op": "set_area", "id": north[-1], "settings": {"level": "ocr"}})
	north.append(_area(sim, refused, {"op": "build_area", "type": "gate", "segment": spine_north, "side": -1, "from": 20, "to": 34}))
	_do(sim, refused, {"op": "set_area", "id": north[-1], "settings": {"level": "ocr"}})
	# M11's harbour life, south of the highway road west of the gates: a
	# workshop and a fire station, a customs block, and a tree belt east of
	# the gates, between the port and the town.
	var workshop := _area(sim, refused, {"op": "build_area", "type": "workshop", "segment": highway, "side": 1, "from": 10, "to": 18})
	var station := _area(sim, refused, {"op": "build_area", "type": "fire_station", "segment": highway, "side": 1, "from": 22, "to": 30})
	# Clear of the dangerous-goods block across the road, between the rail block and the gates.
	var customs := _area(sim, refused, {"op": "build_area", "type": "yard_block", "segment": highway, "side": 1, "from": 172, "to": 172 + BLOCK - 1})
	var belt := _area(sim, refused, {"op": "build_area", "type": "tree_belt", "segment": highway, "side": 1, "from": 256, "to": 290})
	south.append_array([workshop, station, customs, belt])
	south.append_array(barge_areas)
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
	# Cranes on every one of each berth's spots, by the ships it takes.
	var cranes := {"neopanamax": "wide_sts", "ulcv": "mega_sts", "panamax": "sts", "feeder": "sts"}
	for berth: Dictionary in berths:
		var spots := AreaFlow.crane_spots(sim, berth.apron)
		for k in spots.size():
			_do(sim, refused, {"op": "place_sts", "apron": berth.apron, "along": spots[k], "kind": cranes[berth.kind]})
	_do(sim, refused, {"op": "place_sts", "apron": barge, "along": AreaFlow.crane_spots(sim, barge)[0], "kind": "barge_crane"})
	_do(sim, refused, {"op": "buy_tractors", "count": 150})
	_do(sim, refused, {"op": "buy_agvs", "area": agv.depot, "count": AGVS})
	_do(sim, refused, {"op": "buy_chargers", "area": agv.depot, "count": CHARGERS})
	for block: int in agv.racked:
		_do(sim, refused, {"op": "buy_racks", "area": block})
	for policy: String in POLICIES:
		_do(sim, refused, {"op": "set_policy", "policy": policy, "on": true})
	_rules(sim, refused)
	# Harbour life switched on and manned: every event kind, mechanics, a fire
	# engine, customs inspectors and a scanner, shore power at the ULCV berth,
	# and a fund for the town.
	for kind: String in ["tides", "breakdowns", "fires"]:
		_do(sim, refused, {"op": "set_event_kind", "kind": kind, "on": true})
	_do(sim, refused, {"op": "hire_mechanics", "area": workshop, "count": 2})
	_do(sim, refused, {"op": "buy_engines", "area": station, "count": 1})
	_do(sim, refused, {"op": "set_area", "id": customs, "settings": {"role": "customs"}})
	_do(sim, refused, {"op": "hire_inspectors", "area": customs, "count": 2})
	_do(sim, refused, {"op": "buy_scanner", "gate": gate})
	_do(sim, refused, {"op": "buy_shore_power", "area": berths[1].apron})
	_do(sim, refused, {"op": "set_town_fund", "per_day": 1000})
	_water(sim, refused, berths)
	_river(sim, refused)
	_fill(sim)
	# Weekly services at every berth, Meridian (every class) at each and Aurora
	# at the feeder berth, so lines call at both terminals and tranship, and
	# Riverline's barges; and a ship of each berth's class sailing in now.
	var id := 800
	var lines := {"feeder": ["meridian", "aurora"], "barge": ["riverline"]}
	for berth: Dictionary in berths + [{"kind": "barge", "apron": barge}]:
		for line: String in lines.get(berth.kind, ["meridian"]):
			var spec: Dictionary = sim.rules.ship_classes[berth.kind]
			id += 1
			# Every 28 h from 12 h in, so all seven days of the week have a call
			# (one a day from day 1 left day 0 without a move every week).
			var start := 720 + (id - 801) * 1680
			sim.contracts.services.append({"id": id, "line": line, "kind": berth.kind, "start": start, "window_hours": spec.window_hours, "moves": spec.import_moves + spec.export_moves, "apron": berth.apron, "any_berth": false, "asked": start, "next_start": -1.0})
		var ship := PortSim.Ship.new(berth.kind, lines.get(berth.kind, ["meridian"])[0], sim.clock.calendar_minutes() + 60.0 * sim.rules.ship_classes[berth.kind].window_hours, sim.rules.ship_classes[berth.kind].import_moves / 4, sim.rules.ship_classes[berth.kind].export_moves / 4)
		ship.berth = berth.apron
		ship.any_berth = false
		ship.arrived = sim.clock.calendar_minutes()
		sim.ships.append(ship)
		if not AreaFlow.berth(sim, ship):
			refused.append("a %s doesn't berth at its berth" % berth.kind)
	_stage_exports(sim)
	return sim


## The North Terminal around `berth` as an AGV terminal (M11): an AGV zone
## over the quay, the road beside it and its connector, where AGVs drive and
## nothing else may; an AGV depot in it; transfer blocks either side of the
## connector, AGVs at their fronts and lorries at their backs on the lanes;
## a stub off the connector's east end for AGVs to turn in, and one off each
## lane west of the blocks for lorries. Its areas, its depot and its racked
## transfer blocks.
static func _agv_terminal(sim: PortSim, refused: Array[String], berth: Dictionary) -> Dictionary:
	var row: int = berth.row
	var road_x: int = berth.road_x
	var lo := Vector2i(99999, 99999)
	var hi := Vector2i(-99999, -99999)
	for cell: Vector2i in sim.areas.cells(berth.apron):
		lo = lo.min(cell)
		hi = hi.max(cell)
	# The quay and its road, a little past both ends of the apron, where its
	# lane leaves and joins the road; short of the next berth's road.
	_paint_zone(sim, refused, Rect2i(lo.x - 1, lo.y - 4, road_x - lo.x + 19, hi.y - lo.y + 11))
	_paint_zone(sim, refused, Rect2i(road_x, row - 9, SPINE - 14 - road_x, 19))
	_do(sim, refused, {"op": "build_road", "from": Vector2i(SPINE - 28, row), "to": Vector2i(SPINE - 28, row + 14), "type": "terminal_1_1"})
	_paint_zone(sim, refused, Rect2i(SPINE - 38, row, 22, 15))
	for lane: int in [-18, 18]:
		_do(sim, refused, {"op": "build_road", "from": Vector2i(road_x + 24, row + lane), "to": Vector2i(road_x + 24, row + lane + 12 * signi(lane)), "type": "terminal_1_1"})
	var depot := _area(sim, refused, {"op": "build_area", "type": "agv_depot", "segment": sim.roads.segment_at(Vector2i(road_x, row + 34)), "side": -1, "from": 6, "to": 16})
	var connector := sim.roads.segment_at(Vector2i((road_x + SPINE) / 2, row))
	var racked: Array[int] = []
	for side: int in [-1, 1]:
		for start: int in AGV_BLOCKS:
			racked.append(_area(sim, refused, {"op": "build_area", "type": "transfer_block", "segment": connector, "side": side, "from": start, "to": start + 11}))
	for k in racked.size():
		_do(sim, refused, {"op": "set_area", "id": racked[k], "settings": {"role": AGV_ROLES[k]}})
	var dangerous := _area(sim, refused, {"op": "build_area", "type": "transfer_block", "segment": connector, "side": -1, "from": AGV_DG_BLOCK, "to": AGV_DG_BLOCK + 11})
	_do(sim, refused, {"op": "set_area", "id": dangerous, "settings": {"role": "dangerous"}})
	var areas: Array[int] = [depot, dangerous]
	areas.append_array(racked)
	return {"areas": areas, "depot": depot, "racked": racked}


static func _paint_zone(sim: PortSim, refused: Array[String], rect: Rect2i) -> void:
	var cells: Array[Vector2i] = []
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			cells.append(Vector2i(x, y))
	_do(sim, refused, {"op": "paint_agv_zone", "cells": cells, "on": true})


## M13's block rules on the manual import blocks, in order: the first stacks
## by departure, the second takes no reefers and stacks three high, and a
## template of the first's rules is saved and applied to the third.
static func _rules(sim: PortSim, refused: Array[String]) -> void:
	var blocks: Array[int] = []
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		if area.type == "yard_block" and area.settings.role == "import":
			blocks.append(id)
	_do(sim, refused, {"op": "set_area", "id": blocks[0], "settings": {"stacking": "by_departure"}})
	_do(sim, refused, {"op": "set_area", "id": blocks[1], "settings": {"reefers": false, "max_tiers": 3}})
	_do(sim, refused, {"op": "save_template", "name": "By departure", "id": blocks[0]})
	_do(sim, refused, {"op": "apply_template", "name": "By departure", "id": blocks[2]})


## Stacks BOXES imports, due over the next few hours, across the import and
## reefer blocks, transfer blocks too, reefers on the reefer blocks' plugs.
static func _fill(sim: PortSim) -> void:
	var now := sim.clock.calendar_minutes()
	var placed := 0
	var tries := 0
	var half := {}  # block -> the room() it keeps for ships: half what it had empty
	while placed < BOXES and tries < BOXES * 4:
		for block: int in sim.areas.list:
			var area: Dictionary = sim.areas.list[block]
			if area.type not in Areas.BLOCK_TYPES or area.settings.role not in ["import", "reefer"] or placed == BOXES:
				continue
			tries += 1
			var box := sim._new_box("import", now + 30.0 + placed % 240, "meridian")
			var stacks := AreaFlow._stacks(sim, block)
			if stacks.room() <= half.get_or_add(block, stacks.room() / 2):
				sim._drop_box(box)
				continue
			# Placed as a machine would, keeping the room to dig a box out.
			var spot := AreaFlow._place_spot(sim, block, box)
			if sim.boxes[box].reefer != (area.settings.role == "reefer") or sim.boxes[box].dg or spot < 0:
				sim._drop_box(box)
				continue
			stacks.place_at(spot, box, sim.boxes[box].teu)
			sim.boxes[box].in = now
			placed += 1


## Stacks the exports each terminal's ships due want in its export blocks, as lorries
## would have brought them over the days before in a running port; each block
## kept half empty, as _fill keeps them.
static func _stage_exports(sim: PortSim) -> void:
	var now := sim.clock.calendar_minutes()
	var half := {}
	var tries := 0
	while AreaFlow.export_demand(sim) > 0 and tries < BOXES * 4:
		var before := tries
		for block: int in sim.areas.list:
			var area: Dictionary = sim.areas.list[block]
			if area.type not in Areas.BLOCK_TYPES or area.settings.role != "export" or AreaFlow.export_demand_at(sim, area.terminal) <= 0:
				continue
			tries += 1
			var box := sim._new_box("export", now + sim.rules.export_lead_hours * 60.0, "meridian")
			var stacks := AreaFlow._stacks(sim, block)
			var spot := AreaFlow._place_spot(sim, block, box)
			if stacks.room() <= half.get_or_add(block, stacks.room() / 2) or sim.boxes[box].reefer or sim.boxes[box].dg or spot < 0:
				sim._drop_box(box)
				continue
			stacks.place_at(spot, box, sim.boxes[box].teu)
			sim.boxes[box].in = now
		if tries == before:
			break


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


## River channels from the river's inland end down to the barge berth's
## pocket: straight in from the site's edge, then curving down the river
## through a control point, whose middle passes the river's own bend.
## The river bends, so these points were found to fit inside it.
const RIVER_LANES: Array = [[Vector2i(396, 0), Vector2i(396, 7)], [Vector2i(396, 7), Vector2i(318, 85), Vector2(350.5, 66.5)]]


static func _river(sim: PortSim, refused: Array[String]) -> void:
	for lane: Array in RIVER_LANES:
		var command := {"op": "build_ship_lane", "from": lane[0], "to": lane[1], "type": "river"}
		if lane.size() > 2:
			command.control = lane[2]
		_do(sim, refused, command)


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
