extends SceneTree
## Renders a seeded map and prints frame time and draw calls. Needs a real
## renderer (a display, or xvfb-run); see tests/README.md.
## godot --script res://bench/bench.gd -- 256
## The number after "--" is the map size in tiles (default 256).

const FRAMES := 600
const WARMUP := 60

var _view: WorldView
var _times: Array[float] = []
var _draw_calls := 0
var _last := 0
var _frame := 0
var _tiles := 0


func _initialize() -> void:
	var size := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 256
	var rules := Content.base().duplicate(true)
	rules.map = {"width": size, "height": size, "sea_width": 12}
	var sim := PortSim.new(1, rules)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var kinds := [PortMap.Tile.ROAD, PortMap.Tile.QUAY, PortMap.Tile.YARD]
	for y in size:
		for x in range(sim.map.sea_width, size):
			if rng.randf() < 0.3:
				sim.map.place(kinds[rng.randi() % kinds.size()], Vector2i(x, y))
	_tiles = sim.map.cells_of(PortMap.Tile.ROAD).size() + sim.map.cells_of(PortMap.Tile.QUAY).size() + sim.map.cells_of(PortMap.Tile.YARD).size()
	_view = WorldView.new()
	_view.sim = sim
	root.add_child(_view)
	var camera := Camera3D.new()
	camera.position = Vector3(size / 2.0, size * 0.9, size * 1.1)
	camera.rotation.x = deg_to_rad(-45)
	camera.far = size * 4.0
	root.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	_last = Time.get_ticks_usec()


func _process(_dt: float) -> bool:
	var now := Time.get_ticks_usec()
	_frame += 1
	if _frame > WARMUP:
		_times.append((now - _last) / 1000.0)
		_draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_last = now
	if _frame < WARMUP + FRAMES:
		return false
	_times.sort()
	var total := 0.0
	for t in _times:
		total += t
	print("map %dx%d, %d built tiles, %d chunks: avg %.2f ms, p95 %.2f ms, %d draw calls" % [
		_view.sim.map.size.x, _view.sim.map.size.y, _tiles, _view._tiles._parts.size(),
		total / _times.size(), _times[int(_times.size() * 0.95)], _draw_calls])
	return true
