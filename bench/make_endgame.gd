extends SceneTree
## Writes bench/endgame.bin: a port at the M6 target counts (about 2,000
## lorries, 20,000 stacked boxes and 6 berths) for bench/endgame_bench.gd.
## godot --headless --script res://bench/make_endgame.gd
## The yard is filled directly, since unloading 20,000 boxes from ships would
## take game months. Lorries are placed directly too, already through a gate
## and heading for an import box: one highway entry lets in a lorry every few
## ticks and they finish their trips about as fast, so traffic alone levels
## off near 500. Trains join when rail exists (M6 step 13).

const EndgamePort := preload("res://bench/endgame_port.gd")
const LORRIES := 2000
const PATH := "res://bench/endgame.bin"
const SETTLE := 300


func _initialize() -> void:
	var sim := PortSim.new(5, EndgamePort.rules(), true)
	EndgamePort.build(sim)
	_phase("built")
	# A few hundred ticks first, so ships are in and tractors are working.
	for i in SETTLE:
		sim.tick()
	EndgamePort.place_lorries(sim, LORRIES - _lorries(sim))
	_phase("placed lorries")
	for i in SETTLE:
		sim.tick()
	_phase("settled: %d lorries, %d vehicles, %d boxes, %d ships" % [_lorries(sim), sim.vehicles.size(), sim.boxes.size(), sim.ships.size()])
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
