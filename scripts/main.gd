extends Node3D
## Wires the sim, view, camera and HUD together, and turns mouse clicks and
## drags into build and bulldoze orders.

var sim := PortSim.new()
var view := WorldView.new()
var rig := CameraRig.new()
var hud := Hud.new()
var reporter := CrashReporter.new()

## Most ticks one frame may run per speed step; a slower frame drops the rest.
const MAX_TICKS_PER_FRAME := 8
## shortcut: one save slot, add named slots and autosave in M12.
const SAVE_PATH := "user://save.bin"

## Play time not yet turned into ticks, in seconds.
var _accumulated := 0.0
var _painting := false
var _last_cell := PortMap.NONE
## Where a road drag started on the 4 m grid, or NONE.
var _road_from := PortMap.NONE
## Where an area drag attached to a road edge ({"segment", "side", "index"}), or {}.
var _area_from := {}
var _reported := false


func _ready() -> void:
	OS.add_logger(reporter)
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
	hud.command_issued.connect(func(command: Dictionary) -> void: _report(sim.apply(command)))
	hud.new_game_pressed.connect(func(creative: bool) -> void: _use(PortSim.new(randi(), Content.base(), creative)))
	add_child(hud)


func _save() -> void:
	var err := SaveFile.save(SAVE_PATH, sim)
	hud.flash(err if err else "Saved")


func _load() -> void:
	var loaded := SaveFile.load_from(SAVE_PATH)
	if loaded.has("error"):
		hud.flash(loaded.error)
		return
	_use(loaded.sim)
	hud.flash("Loaded")


## Swaps in `new_sim` and a fresh view of it.
func _use(new_sim: PortSim) -> void:
	sim = new_sim
	_painting = false
	rig.bounds = Rect2(Vector2.ZERO, Vector2(sim.map.size))
	_accumulated = 0.0
	view.queue_free()
	view = WorldView.new()
	view.sim = sim
	add_child(view)
	hud.sim = sim


func _process(dt: float) -> void:
	if reporter.errored and not _reported:
		_report_crash()
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
	var dragged: Array[Vector2i] = []
	if not _area_from.is_empty():
		var area := _area_command()
		dragged = sim.areas.cells_of(area.type, area.segment, area.side, area.from, area.to)
	view.show_area_preview(dragged, _order_error(cell) == "")
	view.show_road_preview(_road_from, _road_to() if _road_from != PortMap.NONE else _road_from, hud.road_type, _order_error(cell) == "")
	if _painting:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_painting = false
		elif cell != _last_cell:
			_order(cell, false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _road_from != PortMap.NONE:
		_report(sim.apply({"op": "build_road", "from": _road_from, "to": _road_to(), "type": hud.road_type}))
		_road_from = PortMap.NONE
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not _area_from.is_empty():
		_report(sim.apply(_area_command()))
		_area_from = {}
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if hud.tool == Hud.DRAW_AREA:
			_area_from = sim.areas.attach(_hovered_grid_cell(), hud.area_type)
			if _area_from.is_empty():
				hud.flash("Drag areas out along a road's edge")
			return
		if hud.tool == Hud.DRAW_ROAD:
			_road_from = _hovered_grid_cell()
			return
		if hud.tool == Hud.INSPECT:
			hud.inspect(_hovered_cell())
			return
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
			var area := sim.areas.area_at(_hovered_grid_cell())
			if area:
				return {"op": "remove_area", "id": area}
			var road := sim.roads.segment_at(_hovered_grid_cell())
			return {"op": "remove_road", "segment": road} if road else {"op": "bulldoze", "cell": cell}
		Hud.CRANE:
			return {"op": "place_crane", "cell": cell}
		Hud.BUY_LAND:
			return {"op": "buy_land", "tile": sim.land_tile(cell)}
		Hud.IMPORT_YARD, Hud.EXPORT_YARD, Hud.RTG:
			var area := sim.areas.area_at(_hovered_grid_cell())
			if area:
				return {"op": "set_area", "id": area, "settings": _yard_settings()}
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
		Hud.INSPECT:
			return ""
		Hud.DRAW_ROAD:
			return "" if _road_from == PortMap.NONE else sim.build_road_error(_road_from, _road_to(), hud.road_type)
		Hud.DRAW_AREA:
			if _area_from.is_empty():
				return ""
			var area := _area_command()
			return sim.build_area_error(area.type, area.segment, area.side, area.from, area.to)
		Hud.BULLDOZE:
			var grid := _hovered_grid_cell()
			return "" if sim.areas.area_at(grid) or sim.roads.segment_at(grid) else sim.bulldoze_error(cell)
		Hud.CRANE:
			return sim.crane_error(cell)
		Hud.BUY_LAND:
			return sim.buy_land_error(sim.land_tile(cell))
		Hud.IMPORT_YARD, Hud.EXPORT_YARD, Hud.RTG:
			var area := sim.areas.area_at(_hovered_grid_cell())
			return sim.set_area_error(area, _yard_settings()) if area else sim.set_yard_error(cell, _yard_settings())
	return sim.build_error(hud.tool, cell)


func _hovered_cell() -> Vector2i:
	var hit: Variant = _hovered_point()
	return PortMap.NONE if hit == null else Vector2i(floori(hit.x), floori(hit.z))


## The 4 m grid cell under the mouse.
func _hovered_grid_cell() -> Vector2i:
	var hit: Variant = _hovered_point()
	return PortMap.NONE if hit == null else WorldView.grid_cell(hit)


## Where a road drag from _road_from ends, snapped straight or to 45°.
func _road_to() -> Vector2i:
	return RoadNet.snap(_road_from, _hovered_grid_cell())


## The build_area command for the area dragged from _area_from to the mouse.
func _area_command() -> Dictionary:
	var to := sim.areas.index_near(_area_from.segment, _hovered_grid_cell())
	return {"op": "build_area", "type": hud.area_type, "segment": _area_from.segment, "side": _area_from.side, "from": mini(_area_from.index, to), "to": maxi(_area_from.index, to)}


## Where the mouse points on the ground, or null.
func _hovered_point() -> Variant:
	var mouse := get_viewport().get_mouse_position()
	return Plane(Vector3.UP, 0).intersects_ray(rig.camera.project_ray_origin(mouse), rig.camera.project_ray_normal(mouse))


## Writes one crash report a run and shows its folder to the player.
func _report_crash() -> void:
	_reported = true
	var dir := CrashReporter.write(sim)
	if dir == "":
		hud.flash("Something went wrong, and the report could not be written")
		return
	hud.flash("Something went wrong. A report is in " + ProjectSettings.globalize_path(dir))
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(dir))


func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	return sun


func _environment() -> WorldEnvironment:
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	# Below the horizon is land, so the view past the map's edge reads as countryside.
	material.ground_horizon_color = Color(0.42, 0.5, 0.36)
	material.ground_bottom_color = Color(0.36, 0.42, 0.3)
	sky.sky_material = material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.environment = env
	return world
