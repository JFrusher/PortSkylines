extends SceneTree
## Builds the endgame port (bench/endgame_port.gd), runs it until LORRIES
## lorries and TRAINS trains are in the port or MAX_HOURS game hours pass, and saves it to
## bench/endgame.bin for endgame_bench.gd and profile_sim.gd.
## godot --headless --script res://bench/make_endgame.gd

const EndgamePort := preload("res://bench/endgame_port.gd")
const PATH := "res://bench/endgame.bin"
const LORRIES := 2000
const TRAINS := 2
const MAX_HOURS := 6


func _initialize() -> void:
	var start := Time.get_ticks_msec()
	var sim := EndgamePort.build(EndgamePort.bench_rules())
	print("built in %.1f s: %d areas, %d cranes, %d tractors, %d boxes" % [(Time.get_ticks_msec() - start) / 1000.0, sim.areas.list.size(), sim.cranes.size(), sim.tractors, sim.boxes.size()])
	var until := sim.clock.calendar_minutes() + MAX_HOURS * 60.0
	while (_lorries(sim) < LORRIES or sim.trains.size() < TRAINS) and sim.clock.calendar_minutes() < until:
		sim.tick()
		if sim.clock.ticks % (SimClock.TICKS_PER_DAY / 48) == 0:
			print("  %.1f h: %d lorries, %d vehicles, %d boxes, %d delivered, %.0f s so far" % [sim.clock.calendar_minutes() / 60.0, _lorries(sim), sim.vehicles.size(), sim.boxes.size(), sim.delivered, (Time.get_ticks_msec() - start) / 1000.0])
	var err := SaveFile.save(PATH, sim)
	if err:
		push_error(err)
	print("saved: %d lorries, %d vehicles, %d boxes, %d ships, %d trains at %.1f h" % [_lorries(sim), sim.vehicles.size(), sim.boxes.size(), sim.ships.size(), sim.trains.size(), sim.clock.calendar_minutes() / 60.0])
	quit(1 if err else 0)


static func _lorries(sim: PortSim) -> int:
	return sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "lorry").size()
