extends SceneTree
## Writes bench/endgame.bin: a port at the M5 target counts (about 2,000
## lorries, 20,000 stacked boxes and 6 berths) for bench/endgame_bench.gd.
## godot --headless --script res://bench/make_endgame.gd
## The yard is filled directly, since unloading 20,000 boxes from ships would
## take game months; lorries then flow in under fast spawn rules until the
## target count is on the roads. Trains join when rail exists (M5 step 13).

const EndgamePort := preload("res://bench/endgame_port.gd")
const LORRIES := 2000
const PATH := "res://bench/endgame.bin"


func _initialize() -> void:
	var sim := PortSim.new(5, EndgamePort.rules(), true)
	EndgamePort.build(sim)
	_phase("built")
	var start := Time.get_ticks_msec()
	while _lorries(sim) < LORRIES and sim.clock.ticks < 40000:
		sim.tick()
		if sim.clock.ticks % 1000 == 0:
			_phase("tick %d: %d lorries, %d vehicles, %d boxes, %d ships (%.0f s)" % [sim.clock.ticks, _lorries(sim), sim.vehicles.size(), sim.boxes.size(), sim.ships.size(), (Time.get_ticks_msec() - start) / 1000.0])
	var err := SaveFile.save(PATH, sim)
	print(err if err else "wrote %s: %d lorries, %d vehicles, %d boxes, %d berths, tick %d" % [PATH, _lorries(sim), sim.vehicles.size(), sim.boxes.size(), sim.map.berths().size(), sim.clock.ticks])
	quit(1 if err or _lorries(sim) < LORRIES else 0)


var _log := FileAccess.open("user://endgame_progress.txt", FileAccess.WRITE)
var _t0 := Time.get_ticks_msec()


## Progress straight to a file: stdout is buffered when redirected.
func _phase(text: String) -> void:
	_log.store_line("%.1f s: %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, text])
	_log.flush()


func _lorries(sim: PortSim) -> int:
	return sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "lorry").size()
