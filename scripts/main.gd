extends Node3D
## Wires the sim, view, camera and HUD together, and turns mouse clicks and
## drags into build and bulldoze orders.

var sim := PortSim.new()
var view := WorldView.new()
var rig := CameraRig.new()
var hud := Hud.new()

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
	add_child(hud)


func _process(dt: float) -> void:
	# shortcut: one tick per frame per speed step, replaced by the accumulator in M1.8.
	for i in hud.speed:
		sim.tick()
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
	var err := sim.bulldoze(cell) if hud.tool == Hud.BULLDOZE else sim.build(hud.tool, cell)
	if err != "" and report:
		hud.flash(err)


func _order_error(cell: Vector2i) -> String:
	return sim.bulldoze_error(cell) if hud.tool == Hud.BULLDOZE else sim.build_error(hud.tool, cell)


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
