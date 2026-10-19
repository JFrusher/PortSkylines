extends RefCounted
## Seeded command logs for tests: a working port (road from the highway,
## quay, yard), then random builds and bulldozes near the coast at random
## ticks. Many are refused; that is part of the log.


static func command_log(seed_value: int, ticks: int, extra_commands: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var map := PortSim.new().map
	var log: Array[Dictionary] = []
	for x in range(map.sea_width + 1, map.entry.x):
		log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.ROAD, "cell": Vector2i(x, map.entry.y)}})
	log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.QUAY, "cell": Vector2i(map.sea_width, map.entry.y)}})
	log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.YARD, "cell": Vector2i(map.sea_width + 2, map.entry.y - 1)}})
	var kinds := [PortMap.Tile.ROAD, PortMap.Tile.QUAY, PortMap.Tile.YARD]
	for i in extra_commands:
		var cell := Vector2i(rng.randi_range(map.sea_width - 1, map.sea_width + 8), rng.randi_range(map.entry.y - 5, map.entry.y + 5))
		var command := {"op": "bulldoze", "cell": cell} if rng.randf() < 0.2 else {"op": "build", "kind": kinds[rng.randi() % kinds.size()], "cell": cell}
		log.append({"tick": rng.randi_range(0, ticks - 1), "command": command})
	log.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick)
	return log
