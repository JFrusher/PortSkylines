extends RefCounted
## Seeded command logs for tests: a working port on roads and areas, then
## random roads and areas, cranes, tractors, offer answers, loans, land,
## dredging and storage terms, at random ticks. Many are refused; that is part
## of the log. Also test rules that make a port work at once, and services.


## A copy of `game_rules` on the "strait" map: a straight coast down the
## west edge, the sea 300 m wide and 16 m deep from the shore out, which the
## tests' ports are drawn against.
static func strait(game_rules := Content.base()) -> Dictionary:
	var copy := game_rules.duplicate(true)
	copy.map = "strait"
	return copy


## `rules` (on the strait) with its water `metres` deep everywhere.
static func water(rules: Dictionary, metres: float) -> Dictionary:
	rules.maps.strait.depth = {"shore": metres, "per_metre": 0.0, "max": metres}
	return rules


## strait() for a port that works at once: cranes stand the moment they
## are ordered, and every milestone is already reached.
static func quick(game_rules := Content.base()) -> Dictionary:
	var copy := strait(game_rules)
	for crane: Dictionary in copy.sts_cranes.values():
		crane.lead_days = 0.0
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
		sim.contracts.services.append({"id": 1000 + i, "line": line, "kind": kind, "start": first + every * i, "window_hours": spec.window_hours, "moves": spec.import_moves + spec.export_moves, "apron": 0, "asked": first + every * i, "any_berth": true})


## A tick-tagged log: AreaPort.chain's port built by commands at tick 0 (a
## coast road and an east road to the highway, a quay apron and a ship lane
## in to it, a gate, an
## import and an export block in one terminal, three STS cranes and six
## tractors), then `extra_commands` random ones at random ticks: roads and
## areas south of the port, taken out again, cranes, tractors and the economy.
## Random commands leave the port's own roads and areas alone, so it keeps
## working; test_rules covers removing them in use.
static func command_log(seed_value: int, ticks: int, extra_commands: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var entry := PortSim.new(0, strait()).site_entry()
	var port: Array[Dictionary] = [
		{"op": "paint_terminal", "cells": _region(), "terminal": -1},
		{"op": "build_road", "from": Vector2i(86, 200), "to": Vector2i(86, entry.y), "type": "terminal_1_1"},
		{"op": "build_road", "from": Vector2i(86, entry.y), "to": PortSim.new(0, strait()).site_entry_point(), "type": "terminal_1_1"},
		{"op": "build_area", "type": "quay_apron", "segment": 1, "side": 1, "from": 0, "to": 79},
		{"op": "build_ship_lane", "from": Vector2i(0, 240), "to": Vector2i(68, 240), "type": "narrow"},
		{"op": "build_area", "type": "gate", "segment": 2, "side": -1, "from": 299, "to": 313},
		{"op": "build_area", "type": "yard_block", "segment": 2, "side": 1, "from": 29, "to": 58},
		{"op": "build_area", "type": "yard_block", "segment": 2, "side": 1, "from": 60, "to": 89},
		{"op": "set_area", "id": 4, "settings": {"role": "export"}},
	]
	for along: int in [12, 30, 48]:
		port.append({"op": "place_sts", "kind": "sts", "apron": 1, "along": along})
	port.append({"op": "buy_tractors", "count": 6})
	var log: Array[Dictionary] = []
	for command in port:
		log.append({"tick": 0, "command": command})
	var road_types: Array = Content.base().road_types.keys()
	var area_types: Array = Content.base().area_types.keys()
	# sort_custom is not stable, so only the random commands are sorted; the
	# port above must be built in the order written.
	var extra: Array[Dictionary] = []
	for i in extra_commands:
		var roll := rng.randf()
		var command := {}
		# Roads on the 4 m grid south of the port: drawn at any angle (some refused), and taken out again.
		if roll < 0.3:
			var from := Vector2i(rng.randi_range(150, 250), rng.randi_range(320, 390))
			var to := from + Vector2i(rng.randi_range(-12, 12), rng.randi_range(-12, 12))
			command = {"op": "build_road", "from": from, "to": to, "type": road_types[rng.randi() % road_types.size()]}
		elif roll < 0.33:
			command = {"op": "remove_road", "segment": rng.randi_range(3, 20)}
		elif roll < 0.45:
			command = {"op": "build_area", "type": area_types[rng.randi() % area_types.size()], "segment": rng.randi_range(3, 20), "side": [1, -1][rng.randi() % 2], "from": rng.randi_range(0, 4), "to": rng.randi_range(4, 30)}
		elif roll < 0.5:
			command = {"op": "remove_area", "id": rng.randi_range(5, 12)}
		elif roll < 0.56:
			command = {"op": "set_area", "id": rng.randi_range(5, 12), "settings": {"role": PortSim.AREA_ROLES[rng.randi() % PortSim.AREA_ROLES.size()]}}
		elif roll < 0.6:
			var corner := Vector2i(rng.randi_range(80, 560), rng.randi_range(200, 330))
			var patch: Array[Vector2i] = []
			for x in rng.randi_range(1, 12):
				for y in rng.randi_range(1, 12):
					patch.append(corner + Vector2i(x, y))
			command = {"op": "paint_terminal", "cells": patch, "terminal": rng.randi_range(-1, 3)}
		elif roll < 0.75:
			command = {"op": "place_sts", "kind": "sts", "apron": rng.randi_range(1, 6), "along": rng.randi_range(0, 80)}
		elif roll < 0.88:
			command = {"op": "buy_tractors", "count": rng.randi_range(1, 2)}
		# The economy: offers are numbered from 1, so some answers find one and
		# some are refused; loans, land and dredging are refused without the cash.
		else:
			var economy: Array[Dictionary] = [
				{"op": "accept_offer", "id": rng.randi_range(1, 10), "apron": rng.randi_range(1, 4)},
				{"op": "decline_offer", "id": rng.randi_range(1, 10)},
				{"op": "cancel_service", "id": rng.randi_range(1, 10)},
				{"op": "take_loan", "kind": ["small", "medium"][rng.randi() % 2]},
				{"op": "buy_land", "tile": Vector2i(rng.randi_range(0, 2), rng.randi_range(0, 2))},
				{"op": "dredge_berth", "apron": rng.randi_range(1, 4), "metres": 1},
				{"op": "set_storage", "free_days": rng.randi_range(0, 3), "fee": rng.randi_range(0, 20) * 10},
			]
			command = economy[rng.randi() % economy.size()]
		extra.append({"tick": rng.randi_range(0, ticks - 1), "command": command})
	extra.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick)
	log.append_array(extra)
	return log


## The scripted port's ground, painted as Terminal 1 before it is built.
static func _region() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(60, 601):
		for y in range(180, 340):
			cells.append(Vector2i(x, y))
	return cells
