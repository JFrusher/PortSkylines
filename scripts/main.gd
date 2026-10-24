extends Node3D
## Wires the sim, view, camera and HUD together, and turns mouse clicks and
## drags into the player's commands.

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
var _last_cell := Grid.NONE
## Where a road drag started on the 4 m grid, or NONE.
var _road_from := Grid.NONE
## Where an area drag attached to a road edge ({"segment", "side", "index"}), or {}.
var _area_from := {}
## The box the camera follows, or 0.
var _following := 0
var _reported := false


func _ready() -> void:
	OS.add_logger(reporter)
	add_child(_environment())
	add_child(_sun())
	view.sim = sim
	add_child(view)
	rig.bounds = Rect2(Vector2.ZERO, WorldView.site_size(sim))
	rig.position = Vector3(sim.rules.site.sea_width / WorldView.METRES_PER_UNIT + 10, 0, WorldView.site_size(sim).y / 2.0)
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
	_road_from = Grid.NONE
	_area_from = {}
	_following = 0
	rig.bounds = Rect2(Vector2.ZERO, WorldView.site_size(sim))
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
	_follow(dt)
	var cell := _hovered_grid_cell()
	# Before a road drag, the hover shows where the drag would snap on.
	view.show_hover(sim.roads.snap_start(cell) if hud.tool == Hud.DRAW_ROAD and _road_from == Grid.NONE else cell, _order_error(cell) == "")
	var dragged: Array[Vector2i] = []
	if not _area_from.is_empty():
		var area := _area_command()
		dragged = sim.areas.cells_of(area.type, area.segment, area.side, area.from, area.to)
	view.show_area_preview(dragged, _order_error(cell) == "")
	view.show_road_preview(_road_from, _road_to() if _road_from != Grid.NONE else _road_from, hud.road_type, _order_error(cell) == "")
	if _painting:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_painting = false
		elif cell != _last_cell:
			_order(cell, false)


func _unhandled_input(event: InputEvent) -> void:
	if _following and event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		_following = 0
	# A drag builds on release only if its tool is still the one selected.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _road_from != Grid.NONE:
		if hud.tool == Hud.DRAW_ROAD:
			_report(sim.apply({"op": "build_road", "from": _road_from, "to": _road_to(), "type": hud.road_type}))
		_road_from = Grid.NONE
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not _area_from.is_empty():
		if hud.tool == Hud.DRAW_AREA:
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
			_road_from = sim.roads.snap_start(_hovered_grid_cell())
			return
		if hud.tool == Hud.INSPECT:
			var box := AreaFlow.box_at(sim, _hovered_grid_cell())
			if box:
				_following = box
				hud.flash("Following a box: Esc or moving the camera stops")
				return
			hud.inspect(_hovered_grid_cell())
			return
		_painting = true
		_order(_hovered_grid_cell(), true)


## Glides the camera to the followed box; stops once it has left the port.
func _follow(dt: float) -> void:
	if not _following:
		return
	var at := AreaFlow.box_cell(sim, _following)
	if at == Vector2.INF:
		_following = 0
		hud.flash("The box has left the port")
		return
	var world := (at + Vector2(0.5, 0.5)) * Grid.CELL / WorldView.METRES_PER_UNIT
	rig.position = rig.position.lerp(Vector3(world.x, 0, world.y), minf(1.0, dt * 4.0))


## Gives the selected tool's order for grid cell `cell`. Refusals are only
## reported for clicks, not for every cell a drag passes over.
func _order(cell: Vector2i, report: bool) -> void:
	_last_cell = cell
	var err := sim.apply(_command(cell))
	if report:
		_report(err)


func _report(err: String) -> void:
	if err != "":
		hud.flash(err)


## The command the selected tool gives for grid cell `cell`: the sim refuses
## it with the reason when there is nothing there to act on.
func _command(cell: Vector2i) -> Dictionary:
	match hud.tool:
		Hud.BULLDOZE:
			var area := sim.areas.area_at(cell)
			return {"op": "remove_area", "id": area} if area else {"op": "remove_road", "segment": sim.roads.segment_at(cell)}
		Hud.CRANE:
			var apron := _apron_at(cell)
			return {"op": "place_sts", "apron": apron, "along": sim.areas.along(apron, cell) if apron else 0}
		Hud.BUY_LAND:
			return {"op": "buy_land", "tile": sim.land_tile(cell)}
	return {"op": "set_area", "id": sim.areas.area_at(cell), "settings": _yard_settings()}


## The quay apron covering grid cell `cell`, or 0.
func _apron_at(cell: Vector2i) -> int:
	var area := sim.areas.area_at(cell)
	return area if area and sim.areas.list[area].type == "quay_apron" else 0


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
			return "" if _road_from == Grid.NONE else sim.build_road_error(_road_from, _road_to(), hud.road_type)
		Hud.DRAW_AREA:
			if _area_from.is_empty():
				return ""
			var area := _area_command()
			return sim.build_area_error(area.type, area.segment, area.side, area.from, area.to)
		Hud.BULLDOZE:
			return "" if sim.areas.area_at(cell) or sim.roads.segment_at(cell) else "Nothing to bulldoze here"
		Hud.CRANE:
			var apron := _apron_at(cell)
			return AreaFlow.sts_error(sim, apron, sim.areas.along(apron, cell) if apron else 0)
		Hud.BUY_LAND:
			return sim.buy_land_error(sim.land_tile(cell))
	return sim.set_area_error(sim.areas.area_at(cell), _yard_settings())


## The 4 m grid cell under the mouse, or NONE.
func _hovered_grid_cell() -> Vector2i:
	var hit: Variant = _hovered_point()
	return Grid.NONE if hit == null else WorldView.grid_cell(hit)


## Where a road drag from _road_from ends: snapped onto a road near the
## mouse, else straight or to 45°.
func _road_to() -> Vector2i:
	return sim.roads.snap_end(_road_from, _hovered_grid_cell())


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
