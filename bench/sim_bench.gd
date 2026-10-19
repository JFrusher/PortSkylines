extends SceneTree
## Headless sim timing: runs the soak test's busy port and fails when a tick
## costs more than the budget in docs/perf.md. CI runs it on every push.
## godot --headless --script res://bench/sim_bench.gd

const RandomPort := preload("res://tests/random_port.gd")
## Half a game day: ships worked, yards filling, lorries queueing at the gate.
const TICKS := SimClock.TICKS_PER_DAY / 2
const WARMUP := SimClock.TICKS_PER_DAY / 8
## Budgets from docs/perf.md, with headroom for slow CI machines.
const MAX_TICK_MS := 1.0
const MAX_US_PER_VEHICLE := 100.0


func _initialize() -> void:
	var rules := RandomPort.rules()
	rules.lorry_interval_minutes = 0.25
	rules.export_lorry_interval_minutes = 0.5
	var sim := PortSim.new(2, rules)
	RandomPort.calls(sim)
	var log := RandomPort.command_log(11, TICKS, 0)
	var next := 0
	var total_us := 0
	var worst_us := 0
	var vehicle_ticks := 0
	while sim.clock.ticks < TICKS:
		while next < log.size() and log[next].tick == sim.clock.ticks:
			sim.apply(log[next].command)
			next += 1
		var start := Time.get_ticks_usec()
		sim.tick()
		var spent := Time.get_ticks_usec() - start
		if sim.clock.ticks > WARMUP:
			total_us += spent
			worst_us = maxi(worst_us, spent)
			vehicle_ticks += sim.vehicles.size()
	var ticks := TICKS - WARMUP
	var tick_ms := total_us / 1000.0 / ticks
	var us_per_vehicle := total_us / float(maxi(vehicle_ticks, 1))
	print("sim bench: %d ticks, avg %.3f ms/tick, worst %.2f ms, %.1f vehicles on average, %.2f us per vehicle-tick, %d ships, %d boxes" % [
		ticks, tick_ms, worst_us / 1000.0, vehicle_ticks / float(ticks), us_per_vehicle, sim.ships.size(), sim.boxes.size()])
	var failures := 0
	if tick_ms > MAX_TICK_MS:
		printerr("FAIL average tick %.3f ms is over the %.1f ms budget" % [tick_ms, MAX_TICK_MS])
		failures += 1
	if us_per_vehicle > MAX_US_PER_VEHICLE:
		printerr("FAIL %.2f us per vehicle-tick is over the %.0f us budget" % [us_per_vehicle, MAX_US_PER_VEHICLE])
		failures += 1
	quit(1 if failures else 0)
