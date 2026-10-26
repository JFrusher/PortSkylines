extends SceneTree
## Loads bench/endgame.bin (from make_endgame.gd), plays it as the game does
## at a given speed, and prints the time per frame spent on the sim, on route
## searches within it, and on rendering, plus draw calls. Needs a renderer (a
## display, or xvfb-run). The camera looks at the middle of the port from
## `distance` (8 to 90 in game). With `hide`, one group of the view is not
## drawn, to see what each costs: ground, roads, areas, stacks, machines,
## vehicles, ships or cranes.
## godot --script res://bench/endgame_bench.gd -- <speed> [distance] [hide]

const PATH := "res://bench/endgame.bin"
const TimedLanes := preload("res://bench/timed_lanes.gd")
const EndgamePort := preload("res://bench/endgame_port.gd")
const FRAMES := 300
const WARMUP := 30

var _sim: PortSim
var _view: WorldView
var _speed := 1
var _distance := 90.0
var _hide := ""
var _accumulated := 0.0
var _frame := 0
var _last := 0
var _route_us := 0
var _frames: Array[float] = []
var _sim_ms: Array[float] = []
var _route_ms: Array[float] = []
var _render_ms: Array[float] = []
var _draw_calls := 0
var _primitives := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_speed = int(args[0]) if args.size() > 0 else 1
	_distance = float(args[1]) if args.size() > 1 else 90.0
	_hide = args[2] if args.size() > 2 else ""
	var loaded := SaveFile.load_from(PATH)
	if loaded.has("error"):
		push_error(loaded.error + " (run bench/make_endgame.gd first)")
		quit(1)
		return
	_sim = loaded.sim
	# Rules are data, not saved: put the bench's back.
	_sim.rules = EndgamePort.bench_rules()
	TimedLanes.install(_sim, self)
	_view = WorldView.new()
	_view.sim = _sim
	root.add_child(_view)
	var rig := CameraRig.new()
	rig.distance = _distance
	rig.bounds = Rect2(Vector2.ZERO, WorldView.site_size(_sim))
	rig.position = Vector3(WorldView.site_size(_sim).x / 2.0, 0, WorldView.site_size(_sim).y / 2.0)
	root.add_child(rig)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_last = Time.get_ticks_usec()
	print("loaded: %d vehicles, %d boxes, %d ships" % [_sim.vehicles.size(), _sim.boxes.size(), _sim.ships.size()])


## Called by the timed lane graph for each route search.
func add(part: String, start: int) -> void:
	if part.begins_with("route"):
		_route_us += Time.get_ticks_usec() - start


func _process(dt: float) -> bool:
	if _sim == null:
		return true
	var now := Time.get_ticks_usec()
	_frame += 1
	# Ticks as main.gd runs them: whole ticks from frame time at this speed.
	_accumulated += dt * _speed
	var ticks := SimClock.ticks_for(_accumulated, 8 * _speed)
	_route_us = 0
	var start := Time.get_ticks_usec()
	for i in ticks:
		_sim.tick()
	var sim_us := Time.get_ticks_usec() - start
	_accumulated = minf(_accumulated - ticks * SimClock.TICK_SECONDS, SimClock.TICK_SECONDS)
	_view.alpha = _accumulated / SimClock.TICK_SECONDS
	for node: Node3D in _group(_hide):
		node.visible = false
	if _frame > WARMUP:
		_frames.append((now - _last) / 1000.0)
		_sim_ms.append(sim_us / 1000.0)
		_route_ms.append(_route_us / 1000.0)
		_render_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
		_draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		_primitives = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_last = now
	if _frame < WARMUP + FRAMES:
		return false
	print("hidden: %s" % (_hide if _hide else "nothing"))
	print("speed %dx, distance %d, %d vehicles: frame avg %.1f ms (p95 %.1f), sim %.2f ms (routes %.2f), render cpu %.1f ms, %d draw calls, %d primitives" % [
		_speed, _distance, _sim.vehicles.size(), _average(_frames), _p95(_frames), _average(_sim_ms), _average(_route_ms), _average(_render_ms), _draw_calls, _primitives])
	return true


## The view's nodes in group `name`; none for "".
func _group(name: String) -> Array:
	match name:
		"ground":
			# The water and the land are the view's first two children.
			return [_view.get_child(0), _view.get_child(1)] + _view._unowned.values()
		"roads":
			return [_view._roads, _view._road_marks]
		"areas":
			return [_view._areas]
		"stacks":
			return _view._area_stacks.values()
		"machines":
			return _view._area_machines.values()
		"vehicles":
			return _view._vehicle_parts.values()
		"ships":
			return _view._ships.values()
		"cranes":
			return _view._cranes.values()
	assert(name == "", "unknown group: " + name)
	return []


func _average(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


func _p95(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int(sorted.size() * 0.95)]
