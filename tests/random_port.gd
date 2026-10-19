extends RefCounted
## Seeded command logs for tests: a working port (road from the highway,
## quay, cranes, tractors, an import and an export block), then random builds
## and bulldozes near the coast, and offer answers, loans, land, dredging and
## storage terms, at random ticks. Many are refused; that is part of the log.


## A copy of `game_rules` for a port that works at once: cranes stand the
## moment they are ordered, the channel is M2's 14 m, deep enough for every
## class, and every milestone is already reached.
static func quick(game_rules := Content.base()) -> Dictionary:
	var copy := game_rules.duplicate(true)
	copy.sts_crane.lead_days = 0.0
	copy.channel.start_depth = 14.0
	for milestone: Dictionary in copy.milestones.values():
		milestone.teu = 0
	return copy


## quick() with imports dwelling 30 minutes, so lorries collect them within a
## test's run.
static func rules() -> Dictionary:
	var fast := quick()
	fast.import_dwell_minutes = 30.0
	return fast


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
		# Roads on the 4 m grid: drawn at any angle (some refused), and taken out again.
		if roll >= 0.2 and roll < 0.3:
			var from := Vector2i(rng.randi_range(80, 120), rng.randi_range(80, 120))
			var to := from + Vector2i(rng.randi_range(-12, 12), rng.randi_range(-12, 12))
			command = {"op": "build_road", "from": from, "to": to, "type": Content.base().road_types.keys()[rng.randi() % Content.base().road_types.size()]}
		elif roll >= 0.3 and roll < 0.33:
			command = {"op": "remove_road", "segment": rng.randi_range(1, 20)}
		elif roll >= 0.33 and roll < 0.4:
			var type: String = Content.base().area_types.keys()[rng.randi() % Content.base().area_types.size()]
			command = {"op": "build_area", "type": type, "segment": rng.randi_range(1, 20), "side": [1, -1][rng.randi() % 2], "from": rng.randi_range(0, 4), "to": rng.randi_range(4, 30)}
		elif roll >= 0.4 and roll < 0.42:
			command = {"op": "remove_area", "id": rng.randi_range(1, 10)}
		# The economy: offers are numbered from 1, so some answers find one and
		# some are refused; loans, land and dredging are refused without the cash.
		if roll > 0.88:
			var economy: Array[Dictionary] = [
				{"op": "accept_offer", "id": rng.randi_range(1, 10)},
				{"op": "decline_offer", "id": rng.randi_range(1, 10)},
				{"op": "take_loan", "kind": ["small", "medium"][rng.randi() % 2]},
				{"op": "buy_land", "tile": Vector2i(rng.randi_range(0, 2), rng.randi_range(0, 2))},
				{"op": "dredge", "metres": 1},
				{"op": "set_storage", "free_days": rng.randi_range(0, 3), "fee": rng.randi_range(0, 20) * 10},
			]
			command = economy[rng.randi() % economy.size()]
		extra.append({"tick": rng.randi_range(0, ticks - 1), "command": command})
	extra.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick)
	log.append_array(extra)
	return log
