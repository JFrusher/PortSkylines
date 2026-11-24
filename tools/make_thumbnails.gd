extends SceneTree
## Renders the build menu's thumbnails: each buildable item built alone on a
## small test port and drawn by the game's own view, framed from above, saved
## to ui/thumbnails/<key>.png. Run it again when an item is added or its look
## changes; tests/test_thumbnails.gd checks every item has one.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/make_thumbnails.gd

const RandomPort := preload("res://tests/random_port.gd")
const AreaPort := preload("res://tests/area_port.gd")
const OUT := "res://ui/thumbnails/"
const SIZE := Vector2i(160, 120)
## Frames to let the view draw before the shot.
const SETTLE := 16

var _jobs: Array[Dictionary] = []
var _job := -1
var _frames := 0
var _viewport: SubViewport
var _camera: Camera3D
var _view: WorldView


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_jobs = jobs(RandomPort.quick())
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	root.add_child(_viewport)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	_viewport.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.16, 0.21)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	_viewport.add_child(world)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	_viewport.add_child(_camera)


## Every buildable item: {"key", "commands", "frame" (a Rect2 of grid cells)}.
static func jobs(rules: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var y := 300
	for key: String in rules.road_types:
		if not rules.road_types[key].ring:
			found.append({"key": key, "commands": [{"op": "build_road", "from": Vector2i(200, y), "to": Vector2i(232, y), "type": key}], "frame": Rect2(204, y - 8, 24, 16)})
	found.append({"key": "track", "commands": [{"op": "build_rail", "from": Vector2i(200, y), "to": Vector2i(232, y)}], "frame": Rect2(204, y - 8, 24, 16)})
	for key: String in rules.area_types:
		var area: Dictionary = rules.area_types[key]
		if area.kind in ["depot", "quay_apron"]:
			continue
		var length := maxi(roundi(area.min_length), 16)
		# In a terminal, so it isn't tinted as idle.
		var paint: Array[Vector2i] = []
		for cx in range(180, 261):
			for cy in range(y - 40, y + 50):
				paint.append(Vector2i(cx, cy))
		var commands: Array = [{"op": "paint_terminal", "cells": paint, "terminal": -1}, {"op": "build_road", "from": Vector2i(180, y), "to": Vector2i(260, y), "type": "terminal_2_2"}]
		var frame := Rect2(198, y - 3, length + 4, area.depth + 6)
		if area.kind == "transfer_block":
			# Across its road, north back to a road behind it, as tests/test_transfer_block.gd lays one.
			commands = [commands[0], {"op": "build_road", "from": Vector2i(180, y), "to": Vector2i(260, y), "type": "terminal_1_1"}, {"op": "build_road", "from": Vector2i(180, y - 30), "to": Vector2i(260, y - 30), "type": "terminal_1_1"}]
			commands.append({"op": "build_area", "type": key, "segment": 1, "side": -1, "from": 20, "to": 20 + length - 1})
			frame = Rect2(198, y - 33, length + 4, 36)
		else:
			if area.kind == "agv_depot":
				# In the AGV zone, where it works.
				commands.append({"op": "paint_agv_zone", "cells": paint, "on": true})
			commands.append({"op": "build_area", "type": key, "segment": 1, "side": 1, "from": 20, "to": 20 + length - 1})
		found.append({"key": key, "commands": commands, "frame": frame})
	# Berths and cranes on the coast, in a terminal so they aren't tinted as idle.
	var coast: Array[Vector2i] = []
	for cx in range(40, 140):
		for cy in range(y - 90, y + 90):
			coast.append(Vector2i(cx, cy))
	var terminal := {"op": "paint_terminal", "cells": coast, "terminal": -1}
	for key: String in rules.berths:
		var long: float = rules.berths[key].length
		found.append({"key": key, "commands": [terminal, {"op": "build_berth", "kind": key, "cell": Vector2i(80, y), "angle": PortSim.AUTO_ANGLE}], "frame": Rect2(66, y - long * 0.4, 24, long * 0.8)})
	for key: String in rules.sts_cranes:
		found.append({"key": key, "commands": [terminal, {"op": "build_berth", "kind": "feeder", "cell": Vector2i(80, y), "angle": PortSim.AUTO_ANGLE}, {"op": "place_sts", "apron": 1, "along": -1, "kind": key}], "frame": Rect2(52, y - 28, 44, 44)})
	for key: String in rules.water.lanes:
		found.append({"key": key, "commands": [{"op": "build_ship_lane", "from": Vector2i(0, y), "to": Vector2i(60, y), "type": key}], "frame": Rect2(8, y - 18, 40, 36)})
	found.append({"key": "anchorage", "commands": [{"op": "build_anchorage", "from": Vector2i(6, y - 30), "to": Vector2i(62, y + 30)}], "frame": Rect2(0, y - 36, 68, 72)})
	found.append({"key": "breakwater", "commands": [{"op": "build_breakwater", "from": Vector2i(40, y - 20), "to": Vector2i(40, y + 20)}], "frame": Rect2(22, y - 22, 36, 44)})
	for base: String in ["pilot_station", "tug_depot", "services_jetty"]:
		found.append({"key": base, "commands": [{"op": "build_%s" % base, "cell": Vector2i(69, y)}], "frame": Rect2(56, y - 12, 28, 24)})
	return found


func _next() -> void:
	_job += 1
	if _view:
		_view.queue_free()
	if _job == _jobs.size():
		print("thumbnails: %d" % _jobs.size())
		quit()
		return
	var job: Dictionary = _jobs[_job]
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.quick(), true))
	sim.clock.ticks = SimClock.TICKS_PER_DAY / 2  # noon, lights off
	for command: Dictionary in job.commands:
		# A crane at the berth's first crane spot.
		if command.get("along") == -1:
			command.along = AreaFlow.crane_spots(sim, command.apron)[0]
		var err := sim.apply(command)
		if err != "":
			push_error("%s: %s refused: %s" % [job.key, command.op, err])
			_job = _jobs.size()
			quit(1)
			return
	_view = WorldView.new()
	_view.sim = sim
	_viewport.add_child(_view)
	var frame: Rect2 = job.frame
	var centre := Vector3(frame.get_center().x, 0, frame.get_center().y) * Grid.CELL / WorldView.METRES_PER_UNIT
	var reach := maxf(frame.size.x, frame.size.y * 1.3) * Grid.CELL / WorldView.METRES_PER_UNIT
	_camera.position = centre + Vector3(0.45, 0.85, 0.75).normalized() * reach * 1.7
	_camera.look_at(centre)
	_frames = 0


func _process(_dt: float) -> bool:
	# The first job starts here: the camera can only aim once it is in the tree.
	if _job == -1:
		_next()
		return false
	if _job >= _jobs.size():
		return true
	_frames += 1
	if _frames == SETTLE:
		var key: String = _jobs[_job].key
		_viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + key + ".png"))
		_next()
	return false
