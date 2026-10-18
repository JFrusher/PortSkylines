extends SceneTree
## Determinism: a seed plus a tick-tagged command log always gives the same
## state, however the ticks are grouped into frames.
## godot --headless --script res://tests/test_replay.gd

const TICKS := 10000

var _failures := 0


func _initialize() -> void:
	var log := _command_log(7)
	var hashes: Array[int] = []
	for ticks_per_frame: int in [1, 3, 6]:
		hashes.append(_play(log, ticks_per_frame).state_hash())
	_expect(hashes[1], hashes[0], "3 ticks per frame replays like 1")
	_expect(hashes[2], hashes[0], "6 ticks per frame replays like 1")
	_expect(_play(_command_log(8), 1).state_hash() != hashes[0], true, "a different log gives a different state")
	_expect(_play(log, 1).delivered > 0, true, "the replayed port is busy, not idle")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## A working port (road from the highway, quay, yard), then random builds and bulldozes
## near the coast at random ticks. Many are refused; that is part of the log.
func _command_log(seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var map := PortSim.new().map
	var log: Array[Dictionary] = []
	for x in range(map.sea_width + 1, map.entry.x):
		log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.ROAD, "cell": Vector2i(x, map.entry.y)}})
	log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.QUAY, "cell": Vector2i(map.sea_width, map.entry.y)}})
	log.append({"tick": 0, "command": {"op": "build", "kind": PortMap.Tile.YARD, "cell": Vector2i(map.sea_width + 2, map.entry.y - 1)}})
	var kinds := [PortMap.Tile.ROAD, PortMap.Tile.QUAY, PortMap.Tile.YARD]
	for i in 300:
		var cell := Vector2i(rng.randi_range(map.sea_width - 1, map.sea_width + 8), rng.randi_range(map.entry.y - 5, map.entry.y + 5))
		var command := {"op": "bulldoze", "cell": cell} if rng.randf() < 0.2 else {"op": "build", "kind": kinds[rng.randi() % kinds.size()], "cell": cell}
		log.append({"tick": rng.randi_range(0, TICKS - 1), "command": command})
	log.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick)
	return log


## Runs the log for TICKS ticks, `ticks_per_frame` at a time, applying each
## command between ticks at its tick, as main.gd does.
func _play(log: Array[Dictionary], ticks_per_frame: int) -> PortSim:
	var sim := PortSim.new(1)
	var next := 0
	while sim.clock.ticks < TICKS:
		for i in mini(ticks_per_frame, TICKS - sim.clock.ticks):
			while next < log.size() and log[next].tick == sim.clock.ticks:
				sim.apply(log[next].command)
				next += 1
			sim.tick()
	return sim
