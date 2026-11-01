extends RefCounted
## The endgame port on roads and areas, built by the commands the toolbar
## sends: a coast road with six Panamax quay aprons of three STS cranes each
## and a ship lane out to sea from each,
## seven rows of RTG yard blocks between it and a spine road, two-way gates on
## the spine, and the highway entry. M6's target counts are about 2,000
## lorries, 20,000 stacked boxes, 6 berths and 2 trains.
# shortcut: no trains until M6's rail steps add them.

const RandomPort := preload("res://tests/random_port.gd")
const AreaPort := preload("res://tests/area_port.gd")
## The grid lines the coast road and the spine run south down: their 2+2
## lanes cover the two columns either side, and each row road meets them at
## a grid point.
const COAST_X := 89
const SPINE_X := 561
const ROWS: Array[int] = [12, 108, 204, 300, 396, 492, 588]
const BLOCK := 50
const BOXES := 20000
const DUE_HOURS := 2


## The bench's rules: every milestone unlocked, a lorry sent every tick, and
## blocks given enough RTGs to keep up.
static func bench_rules() -> Dictionary:
	var rules := RandomPort.quick()
	rules.lorry_interval_minutes = SimClock.CALENDAR_MINUTES_PER_TICK
	# An RTG per 3 bays, not 10: one per block handles about 20 lorries an
	# hour, and the port's queues would then measure the yard, not the sim.
	rules.yard_gear.rtg.bays_per_machine = 3.0
	# A train every half hour to each rail block, for M6's 2 trains in the port.
	rules.rail.train.interval_minutes = 30.0
	return rules


## The port to play for testing, from the pause menu in debug builds: the
## same port in creative mode on the game's rules with every milestone
## unlocked, and a Panamax service on each day of the week so ships keep coming.
static func debug_port() -> PortSim:
	var sim := build(RandomPort.quick())
	RandomPort.calls(sim, "panamax", 600, Contracts.MINUTES_PER_WEEK / 7, 7)
	return sim


## Builds the port into a new creative sim on `rules`, fills its import
## blocks with BOXES boxes due from now on, and berths a Panamax at each apron.
static func build(rules: Dictionary) -> PortSim:
	var sim := PortSim.new(3, rules, true)
	for x in 3:
		for y in 3:
			if not sim.land.has(Vector2i(x, y)):
				_do(sim, {"op": "buy_land", "tile": Vector2i(x, y)})
	_do(sim, {"op": "build_road", "from": Vector2i(COAST_X, ROWS[0]), "to": Vector2i(COAST_X, ROWS[-1]), "type": "terminal_2_2"})
	_do(sim, {"op": "build_road", "from": Vector2i(SPINE_X, ROWS[0]), "to": Vector2i(SPINE_X, ROWS[-1]), "type": "terminal_2_2"})
	for y in ROWS:
		_do(sim, {"op": "build_road", "from": Vector2i(COAST_X, y), "to": Vector2i(SPINE_X, y), "type": "terminal_1_1"})
	_do(sim, {"op": "build_road", "from": Vector2i(SPINE_X, 300), "to": sim.site_entry_point(), "type": "terminal_2_2"})
	var aprons: Array[int] = []
	for i in ROWS.size() - 1:
		var coast := sim.roads.segment_at(Vector2i(COAST_X, ROWS[i] + 48))
		aprons.append(_area(sim, {"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 10, "to": 85}))
		AreaPort.add_lane(sim, aprons[-1])
		var spine := sim.roads.segment_at(Vector2i(SPINE_X, ROWS[i] + 48))
		_do(sim, {"op": "build_two_way_gate", "type": "gate_large", "segment": spine, "from": 30, "to": 44})
	var blocks: Array[int] = []
	for y in ROWS:
		var row := sim.roads.segment_at(Vector2i(COAST_X + 200, y))
		for side: int in ([1] if y == ROWS[0] else [-1] if y == ROWS[-1] else [1, -1]):
			for from in range(20, 400, BLOCK + 2):
				var block := _area(sim, {"op": "build_area", "type": "yard_block", "segment": row, "side": side, "from": from, "to": from + BLOCK - 1})
				_do(sim, {"op": "set_area", "id": block, "settings": {"gear": "rtg", "role": ["import", "import", "reefer", "import", "import", "export"][blocks.size() % 6]}})
				blocks.append(block)
	# Two rail blocks south of the last row, sharing the siding track behind them.
	var last := sim.roads.segment_at(Vector2i(COAST_X + 200, ROWS[-1]))
	var rail: Array[int] = []
	for from: int in [20, 20 + BLOCK + 2]:
		rail.append(_area(sim, {"op": "build_area", "type": "yard_block", "segment": last, "side": 1, "from": from, "to": from + BLOCK - 1}))
		_do(sim, {"op": "set_area", "id": rail[-1], "settings": {"gear": "rmg"}})
	var area: Dictionary = sim.areas.list[rail[0]]
	var behind: Vector2i = area.start + area.out * sim.areas.depth_of(area)
	var entry := sim.site_rail_entry()
	var bend := Vector2i(entry.x - 9, behind.y)
	for leg: Array in [[behind, bend], [bend, Vector2i(bend.x, entry.y)], [Vector2i(bend.x, entry.y), entry]]:
		_do(sim, {"op": "build_rail", "from": leg[0], "to": leg[1]})
	# One terminal, painted over exactly the areas built.
	var cells: Array[Vector2i] = []
	for id: int in sim.areas.list:
		cells.append_array(sim.areas.cells(id))
	_do(sim, {"op": "paint_terminal", "cells": cells, "terminal": -1})
	for apron in aprons:
		for along: int in [10, 35, 60]:
			_do(sim, {"op": "place_sts", "kind": "sts", "apron": apron, "along": along})
	while not sim.crane_orders.is_empty():
		sim.tick()
	_do(sim, {"op": "buy_tractors", "count": 4 * sim.cranes.size()})
	_fill(sim, blocks)
	for apron in aprons:
		var spec: Dictionary = rules.ship_classes.panamax
		var ship := PortSim.Ship.new("panamax", rules.lines.keys()[0], sim.clock.calendar_minutes() + 60.0 * spec.window_hours, spec.import_moves, spec.export_moves)
		sim.ships.append(ship)
		var berthed := AreaFlow.berth(sim, ship)
		assert(berthed, "a Panamax berths at apron %d" % apron)
	return sim


## Stacks BOXES imports across the import and reefer blocks, due over the
## next DUE_HOURS, reefers on the reefer blocks.
static func _fill(sim: PortSim, blocks: Array[int]) -> void:
	var now := sim.clock.calendar_minutes()
	var placed := 0
	while placed < BOXES:
		var before := placed
		for block in blocks:
			var role: String = sim.areas.list[block].settings.role
			if role == "export" or placed == BOXES:
				continue
			var stacks := AreaFlow._stacks(sim, block)
			var box := sim._new_box("import", now + placed % (DUE_HOURS * 60), sim.rules.lines.keys()[0])
			# Reefers go on the reefer blocks' plugs, everything else beside them.
			if sim.boxes[box].reefer != (role == "reefer") or stacks.place(box, sim.boxes[box].teu) < 0:
				sim._drop_box(box)
				continue
			sim.boxes[box].in = now
			placed += 1
		assert(placed > before, "the import blocks hold %d boxes, short of %d" % [placed, BOXES])


static func _do(sim: PortSim, command: Dictionary) -> void:
	var err := sim.apply(command)
	if err:
		push_error("%s refused: %s" % [command, err])
		Engine.get_main_loop().quit(1)


static func _area(sim: PortSim, command: Dictionary) -> int:
	_do(sim, command)
	return sim.areas.list.keys().max()
