extends SceneTree
## Determinism: a seed plus a tick-tagged command log always gives the same
## state, however the ticks are grouped into frames.
## godot --headless --script res://tests/test_replay.gd

const RandomPort := preload("res://tests/random_port.gd")
const TICKS := 10000

var _failures := 0


func _initialize() -> void:
	var log := RandomPort.command_log(7, TICKS, 300)
	var hashes: Array[int] = []
	for ticks_per_frame: int in [1, 3, 6]:
		hashes.append(_play(log, ticks_per_frame).state_hash())
	_expect(hashes[1], hashes[0], "3 ticks per frame replays like 1")
	_expect(hashes[2], hashes[0], "6 ticks per frame replays like 1")
	_expect(_play(RandomPort.command_log(8, TICKS, 300), 1).state_hash() != hashes[0], true, "a different log gives a different state")
	_expect(_play(log, 1).delivered > 0, true, "the replayed port is busy, not idle")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


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
