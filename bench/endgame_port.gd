extends RefCounted
## The endgame benchmark port (M5): a 160-tile map with 6 berths of 3
## cranes, a grid of roads with a gate on each, RTG yard bands and the yard
## filled with 20,000 imports. Shared by make_endgame.gd and profile_sim.gd.

const RandomPort := preload("res://tests/random_port.gd")
const SIZE := 160
const BOXES := 20000
const BERTHS := 6
## Horizontal roads every BAND rows, joined by vertical roads at these columns.
const BAND := 6
const COLUMNS: Array[int] = [40, 80, 120, 150]


## Rules for building it: a big map, and lorries every tick so traffic builds up fast.
static func rules() -> Dictionary:
	var rules := RandomPort.quick()
	rules.map = {"width": SIZE, "height": SIZE, "sea_width": 12}
	rules.lorry_interval_minutes = SimClock.CALENDAR_MINUTES_PER_TICK
	rules.export_lorry_interval_minutes = SimClock.CALENDAR_MINUTES_PER_TICK
	return rules


## Builds the port on `sim`, made with rules(), and fills its yard.
static func build(sim: PortSim) -> void:
	# A Panamax for each berth within the first minutes, then weekly.
	RandomPort.calls(sim, "panamax", 1, 2, BERTHS)
	_own_all_land(sim)
	_build(sim)
	_fill_yard(sim)


static func _own_all_land(sim: PortSim) -> void:
	var cells: int = sim.rules.land.cells
	# Land is bought next to land already owned, so sweep until nothing changes.
	var bought := true
	while bought:
		bought = false
		for y in ceili(SIZE / float(cells)):
			for x in ceili(SIZE / float(cells)):
				if not sim.land.has(Vector2i(x, y)) and sim.apply({"op": "buy_land", "tile": Vector2i(x, y)}) == "":
					bought = true


static func _build(sim: PortSim) -> void:
	var coast := sim.map.sea_width
	var entry := sim.map.entry
	var last_band := SIZE - BAND
	var commands: Array[Dictionary] = []
	# Six berths of 16 quay tiles, an apron road behind the whole quay, three cranes each.
	for y in range(8, last_band + 1):
		commands.append({"op": "build", "kind": PortMap.Tile.ROAD, "cell": Vector2i(coast + 1, y)})
	for berth in BERTHS:
		var top := 8 + berth * 24
		for y in range(top, top + 16):
			commands.append({"op": "build", "kind": PortMap.Tile.QUAY, "cell": Vector2i(coast, y)})
	# Horizontal roads, vertical roads, and a gate on each horizontal road by the highway column.
	for y in range(10, last_band + 1, BAND):
		for x in range(coast + 2, COLUMNS[-1]):
			commands.append({"op": "build", "kind": PortMap.Tile.GATE if x == COLUMNS[-1] - 1 else PortMap.Tile.ROAD, "cell": Vector2i(x, y)})
	for x: int in COLUMNS:
		for y in range(10, last_band + 1):
			commands.append({"op": "build", "kind": PortMap.Tile.ROAD, "cell": Vector2i(x, y)})
	for x in range(COLUMNS[-1] + 1, entry.x):
		commands.append({"op": "build", "kind": PortMap.Tile.ROAD, "cell": Vector2i(x, entry.y)})
	# Yard bands between the horizontal roads, RTG-worked; the southern third takes exports.
	for y in range(10, last_band, BAND):
		for row in range(y + 1, y + BAND):
			for x in range(coast + 3, COLUMNS[-1] - 1):
				if x not in COLUMNS:
					commands.append({"op": "build", "kind": PortMap.Tile.YARD, "cell": Vector2i(x, row)})
	for command in commands:
		# Roads cross, so a crossing tile comes up twice.
		if sim.map.tile(command.cell) == command.kind:
			continue
		var err := sim.apply(command)
		if err != "":
			push_error("%s: %s" % [command, err])
	for berth in BERTHS:
		var top := 8 + berth * 24
		for offset: int in [3, 7, 11]:
			sim.apply({"op": "place_crane", "cell": Vector2i(coast, top + offset)})
	sim.apply({"op": "buy_tractors", "count": 60})
	for anchor in sim.yard.anchors():
		sim.apply({"op": "set_yard", "cell": anchor, "settings": {"gear": "rtg", "role": "export" if anchor.y > SIZE * 2 / 3 else "import"}})


## Stacks BOXES import boxes, ready to collect, over the import blocks.
static func _fill_yard(sim: PortSim) -> void:
	var lines: Array = sim.rules.lines.keys()
	var placed := 0
	for tile in sim.map.cells_of(PortMap.Tile.YARD):
		if sim.yard.role_of(tile) != "import":
			continue
		while sim.yard.space(tile) > 0 and placed < BOXES:
			var id: int = sim.call("_new_box", "import", 0.0, lines[placed % lines.size()])
			sim.call("_stack", tile, id)
			placed += 1
		if placed == BOXES:
			return


## Puts `count` lorries on the yard roads, one per westbound lane, each
## through its gate and driving to collect an import box from the nearest
## block, booked the way the sim books one it dispatches.
static func place_lorries(sim: PortSim, count: int) -> void:
	var boxes := {}  # block entrance -> unclaimed import box ids there
	for tile: Vector2i in sim.yard.stacks:
		var way_in := sim.yard.entrance(tile)
		for id: int in sim.yard.stacks[tile]:
			if id not in sim._claimed:
				if way_in not in boxes:
					boxes[way_in] = []
				boxes[way_in].append([id, tile])
	var placed := 0
	for y in range(10, SIZE - BAND + 1, BAND):
		for x in range(COLUMNS[-1] - 2, sim.map.sea_width + 2, -1):
			if placed == count:
				return
			var here := Vector2i(x, y)
			var way_in := _nearest(sim, boxes, here)
			if way_in == PortMap.NONE:
				return
			var path := sim.map.route(here, way_in)
			var lorry := Vehicle.new(sim._next_vehicle, "lorry", path)
			lorry.lane = Traffic.lane(sim.map, path, 0)
			if path.size() < 2 or not sim.traffic.claim(lorry.lane, lorry.id):
				continue
			var box: Array = boxes[way_in].pop_back()
			lorry.box = box[0]
			lorry.target = box[1]
			lorry.gate_in = sim.clock.calendar_minutes()
			sim._claimed[box[0]] = true
			sim._next_vehicle += 1
			sim.vehicles.append(lorry)
			placed += 1


## The block entrance with boxes left nearest `here` by road, or NONE.
static func _nearest(sim: PortSim, boxes: Dictionary, here: Vector2i) -> Vector2i:
	var best := PortMap.NONE
	var best_length := 1 << 30
	for way_in: Vector2i in boxes:
		var length := sim.map.distance(here, way_in)
		if not boxes[way_in].is_empty() and length > 0 and length < best_length:
			best = way_in
			best_length = length
	return best
