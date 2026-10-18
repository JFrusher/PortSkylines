extends Node3D
## Wires the sim, view, camera and HUD together, and turns mouse clicks and
## drags into build and bulldoze orders.

var sim := PortSim.new()
var view := WorldView.new()
var rig := CameraRig.new()
var hud := Hud.new()

## Most ticks one frame may run per speed step; a slower frame drops the rest.
const MAX_TICKS_PER_FRAME := 8
## shortcut: one save slot, add named slots and autosave in M11.
const SAVE_PATH := "user://save.bin"

## Play time not yet turned into ticks, in seconds.
var _accumulated := 0.0
var _painting := false
var _last_cell := PortMap.NONE


func _ready() -> void:
	add_child(_environment())
	add_child(_sun())
	view.sim = sim
	add_child(view)
	rig.bounds = Rect2(Vector2.ZERO, Vector2(sim.map.size))
	rig.position = Vector3(sim.map.sea_width + 10, 0, sim.map.size.y / 2.0)
	add_child(rig)
	hud.sim = sim
	hud.save_pressed.connect(_save)
	hud.load_pressed.connect(_load)
	hud.tractors_pressed.connect(func() -> void: _report(sim.apply({"op": "buy_tractors", "count": 2})))
	add_child(hud)


func _save() -> void:
	var err := SaveFile.save(SAVE_PATH, sim)
	hud.flash(err if err else "Saved")


## Swaps in the saved sim and a fresh view of it.
func _load() -> void:
	var loaded := SaveFile.load_from(SAVE_PATH)
	if loaded.has("error"):
		hud.flash(loaded.error)
		return
	sim = loaded.sim
	rig.bounds = Rect2(Vector2.ZERO, Vector2(sim.map.size))
	_accumulated = 0.0
	view.queue_free()
	view = WorldView.new()
	view.sim = sim
	add_child(view)
	hud.sim = sim
	hud.flash("Loaded")


func _process(dt: float) -> void:
	_accumulated += dt * hud.speed
	var max_ticks := MAX_TICKS_PER_FRAME * hud.speed
	var ticks := SimClock.ticks_for(_accumulated, max_ticks)
	for i in ticks:
		sim.tick()
	var left := _accumulated - ticks * SimClock.TICK_SECONDS
	if ticks == max_ticks and left >= SimClock.TICK_SECONDS and OS.is_debug_build():
		print_debug("Dropped %.2f s of sim time after a slow frame" % left)
	_accumulated = minf(left, SimClock.TICK_SECONDS)
	view.alpha = _accumulated / SimClock.TICK_SECONDS
	var cell := _hovered_cell()
	view.show_hover(cell, _order_error(cell) == "")
	if _painting:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_painting = false
		elif cell != _last_cell:
			_order(cell, false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_painting = true
		_order(_hovered_cell(), true)


## Builds or bulldozes `cell`. Refusals are only reported for clicks, not for
## every cell a drag passes over.
func _order(cell: Vector2i, report: bool) -> void:
	_last_cell = cell
	var err := sim.apply(_command(cell))
	if report:
		_report(err)


func _report(err: String) -> void:
	if err != "":
		hud.flash(err)


## The command the selected tool gives for `cell`.
func _command(cell: Vector2i) -> Dictionary:
	match hud.tool:
		Hud.BULLDOZE:
			return {"op": "bulldoze", "cell": cell}
		Hud.CRANE:
			return {"op": "place_crane", "cell": cell}
		Hud.IMPORT_YARD, Hud.EXPORT_YARD, Hud.RTG:
			return {"op": "set_yard", "cell": cell, "settings": _yard_settings()}
	return {"op": "build", "kind": hud.tool, "cell": cell}


func _yard_settings() -> Dictionary:
	match hud.tool:
		Hud.IMPORT_YARD:
			return {"role": "import"}
		Hud.EXPORT_YARD:
			return {"role": "export"}
	return {"gear": "rtg"}


func _order_error(cell: Vector2i) -> String:
	match hud.tool:
		Hud.BULLDOZE:
			return sim.bulldoze_error(cell)
		Hud.CRANE:
			return sim.crane_error(cell)
		Hud.IMPORT_YARD, Hud.EXPORT_YARD, Hud.RTG:
			return sim.set_yard_error(cell, _yard_settings())
	return sim.build_error(hud.tool, cell)


func _hovered_cell() -> Vector2i:
	var mouse := get_viewport().get_mouse_position()
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(rig.camera.project_ray_origin(mouse), rig.camera.project_ray_normal(mouse))
	if hit == null:
		return PortMap.NONE
	return Vector2i(floori(hit.x), floori(hit.z))


func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	return sun


func _environment() -> WorldEnvironment:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.environment = env
	return world
