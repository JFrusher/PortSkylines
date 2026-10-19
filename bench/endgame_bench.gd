extends SceneTree
## Loads bench/endgame.bin (from make_endgame.gd), plays it as the game does
## at a given speed, and prints the time per frame spent on the sim, on
## route searches, and on rendering, plus draw calls. Needs a renderer (a
## display, or xvfb-run); see tests/README.md. The camera looks at the
## middle of the port as the game's does, from `distance` (8 to 90 in game).
## godot --script res://bench/endgame_bench.gd -- <speed> [distance]

const FRAMES := 600
const WARMUP := 60
const PATH := "res://bench/endgame.bin"

var _sim: PortSim
var _view: WorldView
var _speed := 1
var _accumulated := 0.0
var _frame := 0
var _last := 0
var _frames: Array[float] = []
var _sim_ms: Array[float] = []
var _render_ms: Array[float] = []
var _draw_calls := 0
var _primitives := 0
var _distance := 90.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_speed = int(args[0]) if args.size() > 0 else 1
	_distance = float(args[1]) if args.size() > 1 else 90.0
	var loaded := SaveFile.load_from(PATH)
	if loaded.has("error"):
		push_error(loaded.error + " (run bench/make_endgame.gd first)")
		quit(1)
		return
	_sim = loaded.sim
	_view = WorldView.new()
	_view.sim = _sim
	root.add_child(_view)
	var rig := CameraRig.new()
	rig.distance = _distance
	rig.bounds = Rect2(Vector2.ZERO, Vector2(_sim.map.size))
	rig.position = Vector3(_sim.map.size.x / 2.0, 0, _sim.map.size.y / 2.0)
	root.add_child(rig)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_last = Time.get_ticks_usec()
	print("loaded: %d vehicles, %d boxes, %d ships, %d berths" % [_sim.vehicles.size(), _sim.boxes.size(), _sim.ships.size(), _sim.map.berths().size()])


func _process(dt: float) -> bool:
	if _sim == null:
		return true
	var now := Time.get_ticks_usec()
	_frame += 1
	# Ticks as main.gd runs them: whole ticks from frame time at this speed.
	_accumulated += dt * _speed
	var ticks := SimClock.ticks_for(_accumulated, 8 * _speed)
	var start := Time.get_ticks_usec()
	for i in ticks:
		_sim.tick()
	var sim_us := Time.get_ticks_usec() - start
	_accumulated = minf(_accumulated - ticks * SimClock.TICK_SECONDS, SimClock.TICK_SECONDS)
	_view.alpha = _accumulated / SimClock.TICK_SECONDS
	if _frame > WARMUP:
		_frames.append((now - _last) / 1000.0)
		_sim_ms.append(sim_us / 1000.0)
		_render_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
		_draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		_primitives = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_last = now
	if _frame < WARMUP + FRAMES:
		return false
	print("speed %dx, distance %d, %d vehicles: frame avg %.1f ms (p95 %.1f), sim %.2f ms, render cpu %.1f ms, %d draw calls, %d primitives" % [
		_speed, _distance, _sim.vehicles.size(), _average(_frames), _p95(_frames), _average(_sim_ms), _average(_render_ms), _draw_calls, _primitives])
	return true


func _average(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


func _p95(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int(sorted.size() * 0.95)]
