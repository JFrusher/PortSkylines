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
## How near a lane end a lane drag has to start or end to join it, in cells.
const LANE_SNAP := 4
## Where a ship lane drag started, or Grid.NONE.
var _lane_from := Grid.NONE
## The grid point, in cells, the mouse pressed at to start that drag.
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
	# Start looking at the coast on the middle row, where the start land runs to the water.
	var shore := Vector2i(0, sim.areas.coast.size.y / 2)
	while sim.areas.is_water(shore):
		shore.x += 1
	rig.position = Vector3(Grid.metres(shore.x) / WorldView.METRES_PER_UNIT + 10, 0, WorldView.site_size(sim).y / 2.0)
	add_child(rig)
	hud.sim = sim
	hud.save_pressed.connect(_save)
	hud.load_pressed.connect(_load)
	hud.command_issued.connect(func(command: Dictionary) -> void: _report(sim.apply(command)))
	hud.new_game_pressed.connect(func(creative: bool) -> void: _use(PortSim.new(randi(), Content.base(), creative)))
	# Loaded, not preloaded: bench/ is left out of exported builds, which have no such button.
	hud.mega_port_pressed.connect(func() -> void: _use(load("res://bench/endgame_port.gd").debug_port()))
	hud.event_picked.connect(_go_to)
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
	_lane_from = Grid.NONE
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
	view.info_view = hud.info_view()
	_follow(dt)
	var cell := _hovered_grid_cell()
	# Before a road drag, the hover shows where the drag would start, a road's
	# width across: on a road it snaps to, else at the point under the mouse.
	if hud.tool == Hud.DRAW_ROAD and hud.road_type != "" and not _upgrading() and _road_from == Grid.NONE and cell != Grid.NONE:
		view.show_hover_at(_place(_road_start()), _width(), _order_error(cell) == "")
	else:
		view.show_hover(cell, _order_error(cell) == "")
	view.show_snaps(_snapped_ends(cell), _guide_lines(cell))
	var dragged: Array[Vector2i] = []
	if not _area_from.is_empty():
		var area := _area_command()
		for side: int in ([1, -1] if hud.both_sides() else [area.side]):
			dragged.append_array(sim.areas.cells_of(area.type, area.segment, side, area.from, area.to))
	var berth: Dictionary = sim.berth_plan(hud.berth, cell) if hud.tool == Hud.BUILD_BERTH and cell != Grid.NONE else {}
	if berth.has("cells"):
		dragged = berth.cells
	if hud.tool == Hud.DRAW_LANE and _lane_from != Grid.NONE and cell != Grid.NONE:
		dragged = sim.ship_lanes.footprint(_lane_from, _lane_to(), hud.lane_type)
	view.show_area_preview(dragged, _order_error(cell) == "")
	var ends: Array[Vector2i] = [Grid.NONE, Grid.NONE]
	var road_type := hud.road_type
	var ok := _order_error(cell) == ""
	var picked := _picked_segment(cell)
	if hud.tool == Hud.DRAW_LANE:
		hud.hint("%d m, %s" % [Grid.metres(RoadNet.length(_lane_from, _lane_to())), HudDetails.dollars(sim.ship_lane_price(_lane_from, _lane_to(), hud.lane_type))] if _lane_from != Grid.NONE and _lane_to() != _lane_from else "")
	else:
		hud.hint(_segment_hint(picked) if _road_from == Grid.NONE else "%d m" % Grid.metres(RoadNet.length(_road_from, _road_to())))
	if _road_from != Grid.NONE:
		ends = _road_ends()
	elif not picked.is_empty():
		# The one segment, junction to junction, that a click would remove or change.
		var net: RoadNet = picked[0]
		var road: Dictionary = net.segments[picked[1]]
		ends = [net.nodes[road.a], net.nodes[road.b]] as Array[Vector2i]
		road_type = "track" if net == sim.rails else road.type
		if _upgrading():
			road_type = hud.road_type
		else:
			ok = false
	elif berth.has("line"):
		ends = berth.line
		road_type = PortSim.BERTH_ROAD
	view.show_road_preview(ends[0], ends[1], road_type, ok)
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
		if hud.tool == Hud.DRAW_ROAD and hud.road_type == "track":
			_report(sim.apply({"op": "build_rail", "from": _road_from, "to": _road_to()}))
		elif hud.tool == Hud.DRAW_ROAD:
			var ends := _road_ends()
			_report(sim.apply({"op": "build_road", "from": ends[0], "to": ends[1], "type": hud.road_type}))
		_road_from = Grid.NONE
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _lane_from != Grid.NONE:
		if hud.tool == Hud.DRAW_LANE:
			_report(sim.apply({"op": "build_ship_lane", "from": _lane_from, "to": _lane_to(), "type": hud.lane_type}))
		_lane_from = Grid.NONE
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not _area_from.is_empty():
		if hud.tool == Hud.DRAW_AREA:
			var area := _area_command()
			if hud.both_sides():
				area = {"op": "build_two_way_gate", "type": area.type, "segment": area.segment, "from": area.from, "to": area.to}
			_report(sim.apply(area))
		_area_from = {}
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if hud.tool == Hud.DRAW_AREA:
			_area_from = sim.areas.attach(_hovered_grid_cell(), hud.area_type)
			if _area_from.is_empty():
				hud.flash("Drag areas out along a road's edge")
			return
		if hud.tool == Hud.BUILD_BERTH:
			_order(_hovered_grid_cell(), true)
			return
		if hud.tool == Hud.DRAW_LANE:
			_lane_from = _lane_point(_hovered_grid_cell())
			return
		if _upgrading():
			_report(sim.apply({"op": "change_road", "segment": sim.roads.segment_at(_hovered_grid_cell()), "type": hud.road_type}))
			return
		if hud.tool == Hud.DRAW_ROAD:
			_road_from = _road_start()
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
	rig.position = rig.position.lerp(_over(at), minf(1.0, dt * 4.0))


## Moves the camera over grid cell `cell` and inspects what is there.
func _go_to(cell: Vector2i) -> void:
	_following = 0
	rig.position = _over(cell)
	hud.inspect(cell)


## The camera rig position over the middle of grid cell `at`.
func _over(at: Vector2) -> Vector3:
	var world := (at + Vector2(0.5, 0.5)) * Grid.CELL / WorldView.METRES_PER_UNIT
	return Vector3(world.x, 0, world.y)


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
			var crane := AreaFlow.crane_at(sim, cell)
			if crane:
				return {"op": "remove_sts", "apron": crane.apron, "along": crane.along}
			var area := sim.areas.area_at(cell)
			if area:
				return {"op": "remove_area", "id": area}
			if sim.roads.segment_at(cell):
				return {"op": "remove_road", "segment": sim.roads.segment_at(cell)}
			if sim.rails.segment_at(cell):
				return {"op": "remove_rail", "segment": sim.rails.segment_at(cell)}
			return {"op": "remove_ship_lane", "segment": Inspect.lane_at(sim, cell)}
		Hud.CRANE:
			var apron := _apron_at(cell)
			return {"op": "place_sts", "apron": apron, "along": _crane_along(apron, cell), "kind": hud.crane_kind}
		Hud.BUILD_BERTH:
			return {"op": "build_berth", "kind": hud.berth, "cell": cell}
	assert(false, "no command for tool %d" % hud.tool)
	return {}


## The quay apron covering grid cell `cell`, or 0.
func _apron_at(cell: Vector2i) -> int:
	var area := sim.areas.area_at(cell)
	return area if area and sim.areas.list[area].type == "quay_apron" else 0


## Where along apron `apron` a crane placed at `cell` stands: the nearest
## crane spot on a berth, else under the mouse.
func _crane_along(apron: int, cell: Vector2i) -> int:
	if not apron:
		return 0
	var along := sim.areas.along(apron, cell)
	var spots := AreaFlow.crane_spots(sim, apron)
	if spots.is_empty():
		return along
	var best := spots[0]
	for spot in spots:
		if absi(spot - along) < absi(best - along):
			best = spot
	return best


func _order_error(cell: Vector2i) -> String:
	match hud.tool:
		Hud.INSPECT:
			return ""
		Hud.DRAW_ROAD:
			if _upgrading():
				return sim.change_road_error(sim.roads.segment_at(cell), hud.road_type)
			if _road_from == Grid.NONE:
				return ""
			if hud.road_type == "track":
				return sim.build_rail_error(_road_from, _road_to())
			var ends := _road_ends()
			return sim.build_road_error(ends[0], ends[1], hud.road_type)
		Hud.DRAW_AREA:
			if _area_from.is_empty():
				return ""
			var area := _area_command()
			if hud.both_sides():
				return sim.build_two_way_gate_error(area.type, area.segment, area.from, area.to)
			return sim.build_area_error(area.type, area.segment, area.side, area.from, area.to)
		Hud.BULLDOZE:
			var crane := AreaFlow.crane_at(sim, cell)
			if crane:
				return sim.remove_sts_error(crane.apron, crane.along)
			return "" if sim.areas.area_at(cell) or sim.roads.segment_at(cell) or sim.rails.segment_at(cell) or Inspect.lane_at(sim, cell) else "Nothing to bulldoze here"
		Hud.CRANE:
			var apron := _apron_at(cell)
			return AreaFlow.sts_error(sim, apron, _crane_along(apron, cell), hud.crane_kind)
		Hud.BUILD_BERTH:
			return sim.build_berth_error(hud.berth, cell)
		Hud.DRAW_LANE:
			return "" if _lane_from == Grid.NONE else sim.build_ship_lane_error(_lane_from, _lane_to(), hud.lane_type)
	assert(false, "no error check for tool %d" % hud.tool)
	return ""


## The 4 m grid cell under the mouse, or NONE.
func _hovered_grid_cell() -> Vector2i:
	var hit: Variant = _hovered_point()
	return Grid.NONE if hit == null else WorldView.grid_cell(hit)


## Where a lane drag at `cell` attaches: a lane end within LANE_SNAP cells,
## else `cell`.
func _lane_point(cell: Vector2i) -> Vector2i:
	for node: int in sim.ship_lanes.nodes:
		var point: Vector2i = sim.ship_lanes.nodes[node]
		if (point - cell).abs().x <= LANE_SNAP and (point - cell).abs().y <= LANE_SNAP:
			return point
	return cell


## Where a lane drag from _lane_from ends: at the mouse or a lane end near
## it, kept straight or at 45°.
func _lane_to() -> Vector2i:
	var to := _lane_point(_hovered_grid_cell())
	var d := to - _lane_from
	return to if d.x == 0 or d.y == 0 or absi(d.x) == absi(d.y) else RoadNet.snap(_lane_from, to)


## Where a road drag from _road_from ends: snapped onto a road or guide near
## the mouse, else straight or to 45°; with Shift held, only straight or 45°.
func _road_to() -> Vector2i:
	if _raw():
		return RoadNet.snap(_road_from, _hovered_node())
	return _net().snap_end(_road_from, _hovered_node())


## Where a road drag would start: on a road or guide near the mouse, or with
## Shift held the point under it.
func _road_start() -> Vector2i:
	return _hovered_node() if _raw() else _net().snap_start(_hovered_node())


## Whether Shift is held, turning road and guide snapping off.
func _raw() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


## The guides the road drag's start or end lies on, unless it joins a road
## there: pairs of [guide's road end, the drag's point] in grid units.
func _guide_lines(cell: Vector2i) -> Array[Vector2]:
	var found: Array[Vector2] = []
	if hud.tool != Hud.DRAW_ROAD or hud.road_type == "" or _upgrading() or cell == Grid.NONE or _raw():
		return found
	var node := _hovered_node()
	var guided := _net().guide_start(node) if _road_from == Grid.NONE else _net().guide_end(_road_from, node)
	if _net().snaps(node, _road_from):
		return found
	for guide: Dictionary in guided.guides:
		found.append_array([_place(guide.at), _place(guided.point)])
	return found


## The node a road drag would use under the mouse: the nearest grid point,
## where a road's line runs, or for track the cell, as its line runs through
## cell middles (see RoadNet); NONE off the ground.
func _hovered_node() -> Vector2i:
	if _hovered_point() == null:
		return Grid.NONE
	return _hovered_grid_cell() if hud.road_type == "track" else Vector2i(_hovered_grid_point().round())


## Node `node` of the road tool's net in grid units, for markers.
func _place(node: Vector2i) -> Vector2:
	return Vector2(node) + (Vector2(0.5, 0.5) if hud.road_type == "track" else Vector2.ZERO)


## How many lanes across the road tool's road type is.
func _width() -> int:
	var road: Dictionary = _net().types[hud.road_type]
	return road.forward + road.backward


## Whether the road tool changes roads' type instead of drawing them.
func _upgrading() -> bool:
	return hud.tool == Hud.DRAW_ROAD and hud.upgrade_roads and hud.road_type != "track"


## The segment a click at `cell` would remove (bulldoze) or change
## (upgrade): [its RoadNet, its id], or [] for none.
func _picked_segment(cell: Vector2i) -> Array:
	if cell == Grid.NONE:
		return []
	if _upgrading() and sim.roads.segment_at(cell):
		return [sim.roads, sim.roads.segment_at(cell)]
	if hud.tool != Hud.BULLDOZE or AreaFlow.crane_at(sim, cell) or sim.areas.area_at(cell):
		return []
	if sim.roads.segment_at(cell):
		return [sim.roads, sim.roads.segment_at(cell)]
	if sim.rails.segment_at(cell):
		return [sim.rails, sim.rails.segment_at(cell)]
	return []


## The text beside the mouse for segment `picked`, from _picked_segment:
## what it is and how long, and for an upgrade what it becomes and costs.
func _segment_hint(picked: Array) -> String:
	if picked.is_empty():
		return ""
	var net: RoadNet = picked[0]
	var road: Dictionary = net.segments[picked[1]]
	var a: Vector2i = net.nodes[road.a]
	var b: Vector2i = net.nodes[road.b]
	var name: String = sim.rules.rail.name if net == sim.rails else sim.rules.road_types[road.type].name
	var text := "%s, %d m" % [name, Grid.metres(RoadNet.length(a, b))]
	if not _upgrading():
		return "Remove " + text
	var err := sim.change_road_error(picked[1], hud.road_type)
	if err != "":
		return "%s\n%s" % [text, err]
	return "%s\nto %s: %s" % [text, sim.rules.road_types[hud.road_type].name, Hud.HudDetails.dollars(sim.road_price(a, b, hud.road_type))]


## Where the ends of the road being drawn, or about to be, join a road, in
## grid units.
func _snapped_ends(cell: Vector2i) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var node := _hovered_node()
	if hud.tool != Hud.DRAW_ROAD or _upgrading() or cell == Grid.NONE or _raw():
		return found
	if _road_from == Grid.NONE:
		if _net().snaps(node):
			found.append(_place(_road_start()))
		return found
	if _net().snaps(_road_from):
		found.append(_place(_road_from))
	if _net().snaps(node, _road_from):
		found.append(_place(_road_to()))
	return found


## The graph the road tool draws on: rail for track, else roads.
func _net() -> RoadNet:
	return sim.rails if hud.road_type == "track" else sim.roads


## The grid points a road drag builds between.
func _road_ends() -> Array[Vector2i]:
	return [_road_from, _road_to()] as Array[Vector2i]


## The grid point under the mouse, in cells with their fractions.
func _hovered_grid_point() -> Vector2:
	var hit: Variant = _hovered_point()
	return Vector2.ZERO if hit == null else Vector2(hit.x, hit.z) * WorldView.METRES_PER_UNIT / Grid.CELL


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
