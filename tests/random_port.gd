extends RefCounted
## Seeded command logs for tests: a working port (road from the highway,
## quay, cranes, tractors, an import and an export block), then random builds
## and bulldozes near the coast and offer answers at random ticks. Many are
## refused; that is part of the log.


## The base rules with imports dwelling 30 minutes, so lorries collect them
## within a test's run.
static func rules() -> Dictionary:
	var quick := Content.base().duplicate(true)
	quick.import_dwell_minutes = 30.0
	return quick


## Weekly services standing in for M2's ship timer: a ship of `kind` at
## minute `first`, then every `every` minutes, `count` times, for the first line.
static func calls(sim: PortSim, kind := "feeder", first := 10, every := 45, count := 32) -> void:
	var line: String = sim.rules.lines.keys()[0]
	var spec: Dictionary = sim.rules.ship_classes[kind]
	for i in count:
		sim.contracts.services.append({"id": 1000 + i, "line": line, "kind": kind, "start": first + every * i, "window_hours": spec.window_hours, "moves": spec.import_moves + spec.export_moves})


static func command_log(seed_value: int, ticks: int, extra_commands: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var map := PortSim.new().map
	var log: Array[Dictionary] = []
	for x in range(map.sea_width + 1, map.entry.x):
		var kind := PortMap.Tile.GATE if x == map.entry.x - 3 else PortMap.Tile.ROAD
		log.append({"tick": 0, "command": {"op": "build", "kind": kind, "cell": Vector2i(x, map.entry.y)}})
	# A 12-tile quay, long enough for every ship class.
	for y in range(map.entry.y - 6, map.entry.y + 6):
		log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.QUAY, "cell": Vector2i(map.sea_width, y)}})
		if y != map.entry.y:
			log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.ROAD, "cell": Vector2i(map.sea_width + 1, y)}})
	log.append({"tick": 0, "command": {"op": "buy_tractors", "count": 6}})
	for y: int in [map.entry.y - 1, map.entry.y]:
		log.append({"tick": 0, "command": {"op": "place_crane", "cell": Vector2i(map.sea_width, y)}})
	log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.YARD, "cell": Vector2i(map.sea_width + 2, map.entry.y - 1)}})
	var exports := Vector2i(map.sea_width + 6, map.entry.y + 1)
	log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.YARD, "cell": exports}})
	log.append({"tick": 0, "command": {"op": "set_yard", "cell": exports, "settings": {"role": "export"}}})
	var kinds := [PortMap.Tile.ROAD, PortMap.Tile.QUAY, PortMap.Tile.YARD]
	# sort_custom is not stable, so only the random commands are sorted; the
	# port above must be built in the order written.
	var extra: Array[Dictionary] = []
	for i in extra_commands:
		var cell := Vector2i(rng.randi_range(map.sea_width - 1, map.sea_width + 8), rng.randi_range(map.entry.y - 5, map.entry.y + 5))
		var roll := rng.randf()
		var command := {"op": "bulldoze", "cell": cell} if roll < 0.2 else {"op": "build", "kind": kinds[rng.randi() % kinds.size()], "cell": cell}
		# Offers are numbered from 1, so some of these find one and some are refused.
		if roll > 0.9:
			command = {"op": "accept_offer" if roll > 0.95 else "decline_offer", "id": rng.randi_range(1, 10)}
		extra.append({"tick": rng.randi_range(0, ticks - 1), "command": command})
	extra.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick)
	log.append_array(extra)
	return log
