class_name WorldView
extends Node3D
## Draws the sim as a small 3D model port. Reads PortSim every frame and
## never changes it.

## A deck box's height and its length by TEU (20 ft and 40 ft) on a ship
## model, in world units, stretched a little so boxes aboard read at a distance.
const BOX_HEIGHT := 0.3
## A junction's approach marking is drawn every this many cells along a lane.
const APPROACH_MARK := 3
const BOX_LENGTH := {1: 0.4, 2: 0.8}
## Boxes not yet booked on a line.
const PLAIN_BOX := Color(0.72, 0.72, 0.68)
## Metres in one world unit. Ships, cranes and the camera were made at this
## scale; roads, areas and what moves on them are drawn true to the 4 m grid in it.
const METRES_PER_UNIT := 25.0
## Straddle carriers, on the road and in their blocks.
const STRADDLE_RED := Color(0.85, 0.22, 0.15)
## Roads on the 4 m grid, in metres: how high the surface and markings sit
## (lorry roads above tractor lanes, so junctions read as asphalt), the
## markings' width, and dashes as long as their gaps are short.
const ROAD_TOP := 0.3
const ASPHALT_RISE := 0.05
const MARK_RISE := 0.12
const MARK_WIDTH := 0.15
const DASH := 3.0
const DASH_GAP := 6.0
const ASPHALT := Color(0.2, 0.2, 0.22)
## The surface of a road lorries may not use, so tractor lanes read at a glance.
const TRACTOR_ONLY := Color(0.36, 0.24, 0.2)
const MARKING := Color(0.92, 0.92, 0.85)
## A zebra crossing's depth and stripe width, the gap to the stop line and
## its width, in metres; and the length of road they take at a junction.
const ZEBRA_DEPTH := 3.0
const ZEBRA_STRIPE := 0.5
const STOP_GAP := 1.0
const STOP_WIDTH := 0.4
const JUNCTION_MARKS := ZEBRA_DEPTH + STOP_GAP + STOP_WIDTH + 1.0
## Where a road drag joins a road, and the ring's inner radius in cells.
const SNAP_COLOR := Color(0.2, 0.85, 1.0)
## Half a guide line's width, in cells.
const GUIDE_HALF := 0.2
const SNAP_RING := 1.6
const BALLAST := Color(0.42, 0.38, 0.33)
const STEEL := Color(0.62, 0.62, 0.66)
## Half the gauge and a rail's half width, in metres.
const RAIL_GAUGE := 0.72
const RAIL_HALF := 0.08
## Area ground by kind, a little below road level.
const AREA_COLOR := {
	"yard_block": Color(0.56, 0.56, 0.53), "quay_apron": Color(0.66, 0.65, 0.6),
	"gate": Color(0.42, 0.5, 0.58), "depot": Color(0.6, 0.55, 0.45),
	"parking": Color(0.38, 0.4, 0.42), "workshop": Color(0.5, 0.47, 0.42), "fire_station": Color(0.62, 0.3, 0.27),
	"agv_depot": Color(0.45, 0.5, 0.52), "transfer_block": Color(0.56, 0.56, 0.53), "tree_belt": Color(0.3, 0.42, 0.24),
}
const AREA_TOP := 0.2
## AGV-only lanes, amber over the asphalt.
## A full AGV battery's bar.
const AGV_CHARGE_FULL := Color(0.2, 0.85, 0.3)
const AGV_CHARGE_FLAT := Color(0.9, 0.15, 0.1)
## How fast a vehicle's drawn heading follows its path's, a second: about a
## sixth of the way a frame at 60 fps.
const HEADING_EASE := 10.0
## A rack's top, metres: a lift-AGV slides under a box on it.
const RACK_HEIGHT := 1.6
## Parking lanes in an AGV depot, two AGVs to each.
const AGV_LANES := 4
## A floodlight mast's height (30 m) and the cells between masts along an area.
const MAST_HEIGHT := 30.0 / METRES_PER_UNIT
const MAST_EVERY := 12.0
## How many cells out a floodlight's pool of light reaches.
const MAST_REACH := 7.0
const AGV_LANE := Color(0.55, 0.42, 0.18)
## How high ship lanes are drawn: just over the water.
const LANE_HEIGHT := -0.2
## Camera distance, in world units, past which yard boxes are drawn plain.
const STACK_DETAIL_RANGE := 30.0
## A container's real size in metres, by TEU, for things drawn on areas.
const REAL_BOX_LENGTH := {1: 6.06, 2: 12.19}
const REAL_BOX_HEIGHT := 2.59
const REAL_BOX_WIDTH := 2.44
## An RTG's real height in metres, one over five boxes high.
const REAL_RTG_HEIGHT := 20.0
## Vehicles on areas narrowed and lowered to lorry proportions (across, up, along).
const AREA_VEHICLE_SCALE := Vector3(0.45, 0.6, 1.0)
## A laid-out area's driven parts: the buffer strip, and handover slots in
## two alternating shades so each slot reads on its own.
const BUFFER_COLOR := Color(0.3, 0.3, 0.32)
const SLOT_COLORS: Array[Color] = [Color(0.24, 0.24, 0.26), Color(0.33, 0.33, 0.35)]
const RAIL_COLOR := Color(0.16, 0.16, 0.17)
## A berth's crane spots, striped across its apron.
const SPOT_COLOR := Color(0.85, 0.7, 0.2)
## The quay edge's fender line, in safety yellow.
const EDGE_COLOR := Color(0.85, 0.7, 0.15)
## Mixed into an idle area's ground, so an area cut off from its road stands out.
const IDLE_TINT := Color(0.85, 0.2, 0.15)
## STS cranes at true scale, in world units: the girder 45 m up, legs on
## rails 30.5 m apart, and the girder 15 m back behind the land-side rail;
## its reach out over the water comes from the crane's outreach in rows.
const CRANE_HEIGHT := 45.0 / METRES_PER_UNIT
const CRANE_GAUGE := 30.48 / METRES_PER_UNIT
const CRANE_BACK := -CRANE_GAUGE / 2.0 - 15.0 / METRES_PER_UNIT
const CRANE_COLOR := Color(0.85, 0.3, 0.2)
## A ship's deck height, the room its bridge and bow take, and its deck
## stacks at true scale: 40 ft bays with a 0.6 m gap, rows a box wide plus
## 0.1 m, as many rows as the class is boxes across.
const SHIP_DECK := 0.3
const SHIP_STERN := 1.0
const SHIP_BOW := 1.1
const DECK_BAY := 12.8 / METRES_PER_UNIT
const DECK_ROW := 2.54 / METRES_PER_UNIT
const DECK_TIERS := 4
## Metres of hull beside the outer rows, and of water between hull and quay edge.
const HULL_MARGIN := 2.0
const QUAY_GAP := 2.0
## A 40 ft box at true size, turned along the ship.
var _deck_box := Basis()
## Each info view's colours and what they mean, by HudDetails group.
const INFO_LEGENDS := {
	HudDetails.GROUP_TRAFFIC: [["Flowing", Color(0.2, 0.8, 0.35)], ["Slow", Color(0.95, 0.75, 0.15)], ["Jammed", Color(0.9, 0.2, 0.15)]],
	HudDetails.GROUP_CONTAINERS: [["Empty", Color(0.2, 0.8, 0.35)], ["Half full", Color(0.95, 0.75, 0.15)], ["Full", Color(0.9, 0.2, 0.15)]],
	TOWN_NOISE: [["Quiet", Color(0.2, 0.8, 0.35)], ["Heard", Color(0.95, 0.75, 0.15)], ["Loud", Color(0.9, 0.2, 0.15)]],
}
## The info view of what each area's noise does to the town next door.
const TOWN_NOISE := "Town noise"
const INFO_TOP := 0.6
## Seconds of waiting per vehicle passing a cell that the Traffic view shows
## as jammed: about a manual gate check (2 game minutes, which pass in 2 s of
## vehicle time), in every cell of a queue. Free flow can't set the scale: a
## lorry crosses a cell in about a hundredth of a second.
const JAM_SECONDS := 2.0
const INFO_SECONDS := 0.25
const SEA_START := -18.0  # how far the water reaches past the site
const LAND_COLOUR := Color(0.36, 0.42, 0.3)

var sim: PortSim
## The info view drawn over the map: a key of INFO_LEGENDS, or "" for none.
var info_view := ""
## How far play has moved from the last tick towards the next, 0 to 1.
var alpha := 1.0

var _water := ShaderMaterial.new()
var _land := ShaderMaterial.new()
## The coast as a texture a pixel a cell: red is land, green the water's depth
## against its map's deepest; redrawn when water is filled.
var _coast := ImageTexture.new()
## The coast as drawn, and the cells filled since: drawn once whole, then
## only the new fill, as a whole redraw takes seconds on a big site.
var _coast_image: Image
var _coast_filled := {}
## Each land tile a pixel, red where the port owns it.
var _owned := ImageTexture.new()
var _stack_meshes := {}  # TEU -> Mesh, tinted per instance
# shortcut: ships are one node each, fine at the handful a port works at once; MultiMesh them if berths grow past ~20.
var _ships := {}  # PortSim.Ship -> Node3D
## Pilot stations and tug depots by id: their jetty and office, a Node3D each.
var _bases := {}
## Pilot boats and tugs by id, a Node3D each, and where each was the last two ticks.
var _boats := {}
var _boat_seen := {}  # boat id -> [at the tick before, at this tick], in cells
var _boat_tick := -1
## Mechanics' vans by id, a Node3D each.
var _vans := {}
## Buildings standing on areas (a workshop's shed, a fire station) by area id.
var _area_buildings := {}
## Fire engines by id, a Node3D each, and each fire's flames and smoke.
var _engines := {}
var _fires := {}
## Every vehicle part drawn as one MultiMesh: "cab", "chassis", and boxes by TEU.
var _vehicle_parts := {}
## Trains drawn the same way: "loco", "wagon", and boxes by TEU.
var _train_parts := {}
## Each vehicle's last heading by id, kept while it waits on a one-cell path.
var _headings := {}
## A box on a vehicle's chassis: a container model turned along the vehicle and scaled to it.
var _vehicle_box := Transform3D(Basis(Vector3.UP, PI / 2).scaled_local(Vector3(0.65, 0.75, 0.8)), Vector3(0, 0.2, -0.06))
var _cranes := {}  # PortSim.Crane -> Node3D
## Yard machines on areas, by machine id, and how tall each gear's model is.
var _area_machines := {}
var _machine_heights := {}
## Boxes stacked in yard areas, a MultiMesh per box length, redrawn when the
## sim has ticked or the areas changed.
var _area_stacks := {}  # yard area -> {"drawn": [its stacks' version, areas version], "parts": {Vector2i(teu, far) -> MultiMeshInstance3D}}
## The container drawn as a plain 12-triangle box, by TEU: past STACK_DETAIL_RANGE
## a block's boxes use it, since 20,000 container models at full detail cost
## 94% of the endgame port's render time (docs/perf.md).
var _plain_box := {}
## Each box model scaled to real size, by TEU, for boxes on areas and vehicles.
var _real_box := {}
var _machine_meshes := {}  # gear -> Mesh
var _asc_meshes := {}
var _overlays := {}  # "stripe1".."placard2" -> Mesh, see _box_overlays
## Night lights (M11): masts on areas, their lamps and pools of light; the
## glow of vehicles' lamps and of ships' lights. Lit by DayNight.darkness.
var _masts := _flat_part()
var _lamps := _flat_part()
var _pools := _flat_part()
var _beams := _flat_part()
var _ship_lights: Array[Node3D] = []
var _glow := StandardMaterial3D.new()
var _bright := StandardMaterial3D.new()
var _dark := 0.0  # transfer block columns -> its ASCs' Mesh
## The town next door (see Town): its houses, and their windows lit at night,
## drawn again when it grows, its mood turns or the bypass is built.
var _town := MeshInstance3D.new()
var _town_windows := MeshInstance3D.new()
var _town_drawn := []
## Every road on the 4 m grid as one mesh and its markings as another, redrawn when the roads change.
var _roads := MeshInstance3D.new()
var _road_marks := MeshInstance3D.new()
var _roads_drawn := []
## Every area's ground as one mesh, redrawn when the areas change.
var _areas := MeshInstance3D.new()
## The area and road versions the areas were drawn for: idle tints follow the roads.
var _areas_drawn := []
## The AGV zone: a yellow-black safety line round it, its lanes tinted amber,
## and a barrier on each road lane where it crosses the zone's edge.
var _agv_zone := MeshInstance3D.new()
## Each barrier: {"node", "boom" (hinged at its post), "at" (cells), "lift" 0 down to 1 up}.
var _barriers: Array[Dictionary] = []
var _barrier_cache: Mesh
var _boom_cache: Mesh
var _area_preview := MeshInstance3D.new()
## The ship lanes on the water, and what they were drawn for.
var _ship_lanes := MeshInstance3D.new()
var _ship_lanes_drawn := []
## The road being dragged out, tinted by whether it can be built.
var _road_preview := MeshInstance3D.new()
## A ring on each end of a road drag that joins a road, so a join is plain.
var _snap_marks := MeshInstance3D.new()
## A mark at the head of each lane into a junction with signals (green or
## red for its phase) or a sign (white give way, orange stop), and what they
## were last drawn for.
var _junction_signs := MeshInstance3D.new()
var _junctions_drawn: Variant = null
var _hover := _box(Vector3(Grid.CELL, 1.5, Grid.CELL) / METRES_PER_UNIT, Color(1, 1, 1, 0.5))
var _info := MeshInstance3D.new()
var _info_left := 0.0
var _drawn_land := -1


func _ready() -> void:
	var site := site_size(sim)
	var water := _box(Vector3(site.x - SEA_START * 2, 0.1, site.y - SEA_START * 2), Color.WHITE)
	water.position = Vector3(site.x / 2.0, -0.35, site.y / 2.0)
	_water.shader = load("res://shaders/water.gdshader")
	water.material_override = _water
	add_child(water)
	# The site's land is a plane cut to the coast; past the east edge, where
	# the highway comes in from the hinterland, the land runs on.
	var land := MeshInstance3D.new()
	land.mesh = PlaneMesh.new()
	(land.mesh as PlaneMesh).size = site
	land.position = Vector3(site.x / 2.0, 0.0, site.y / 2.0)
	_land.shader = load("res://shaders/land.gdshader")
	land.material_override = _land
	add_child(land)
	var hinterland := _box(Vector3(-SEA_START, 1, site.y - SEA_START * 2), LAND_COLOUR)
	hinterland.position = Vector3(site.x - SEA_START / 2.0, -0.5, site.y / 2.0)
	add_child(hinterland)
	for material: ShaderMaterial in [_water, _land]:
		material.set_shader_parameter("coast", _coast)
		material.set_shader_parameter("site", site)
	_land.set_shader_parameter("owned", _owned)
	_land.set_shader_parameter("colour", LAND_COLOUR)
	add_child(_hover)
	for node: MeshInstance3D in [_roads, _road_marks, _road_preview, _snap_marks, _junction_signs, _areas, _area_preview, _ship_lanes, _agv_zone]:
		add_child(node)
	_ship_lanes.material_override = StandardMaterial3D.new()
	_ship_lanes.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ship_lanes.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ship_lanes.material_override.vertex_color_use_as_albedo = true
	add_child(_info)
	add_child(_town)
	add_child(_town_windows)
	for preview: MeshInstance3D in [_road_preview, _area_preview, _info]:
		preview.material_override = StandardMaterial3D.new()
		preview.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		preview.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_info.material_override.vertex_color_use_as_albedo = true
	_junction_signs.material_override = StandardMaterial3D.new()
	_junction_signs.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_junction_signs.material_override.vertex_color_use_as_albedo = true
	_snap_marks.material_override = StandardMaterial3D.new()
	_snap_marks.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snap_marks.material_override.albedo_color = SNAP_COLOR
	for gear: String in sim.rules.yard_gear:
		_machine_meshes[gear] = _machine_mesh(gear)
		_machine_heights[gear] = _machine_meshes[gear].get_aabb().end.y
	for teu: int in BOX_LENGTH:
		_stack_meshes[teu] = _container_mesh(teu)
		var real := Vector3(REAL_BOX_LENGTH[teu], REAL_BOX_HEIGHT, REAL_BOX_WIDTH) / METRES_PER_UNIT
		_real_box[teu] = real / _stack_meshes[teu].get_aabb().size
		var aabb: AABB = _stack_meshes[teu].get_aabb()
		_plain_box[teu] = _merged([[aabb.size, aabb.get_center(), Color.WHITE]])
	_deck_box = Basis(Vector3.UP, PI / 2) * Basis.from_scale(_real_box[2])
	_overlays = _box_overlays()
	_make_lights()


## The site in world units.
static func site_size(port: PortSim) -> Vector2:
	return Vector2(port.rules.site.width, port.rules.site.height) / METRES_PER_UNIT


## Marks grid cell `cell` under the mouse, green if the tool can act there, else red.
func show_hover(cell: Vector2i, ok: bool) -> void:
	show_hover_at(Vector2(cell) + Vector2(0.5, 0.5) if cell != Grid.NONE else Vector2.INF, 1, ok)


## Marks a square `cells` cells across centred on grid point `centre` (in
## cells): a road's width where a drag would start it. Hidden at INF.
func show_hover_at(centre: Vector2, cells: int, ok: bool) -> void:
	_hover.visible = centre != Vector2.INF
	if not _hover.visible:
		return
	_hover.position = _world(centre * Grid.CELL, 1.0)
	_hover.scale = Vector3(cells, 1, cells)
	(_hover.mesh.material as StandardMaterial3D).albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


## Shows the roundabout a drag would build round `centre`, `radius` cells
## out, green if it can be built, else red.
func show_ring_preview(centre: Vector2, radius: float, ok: bool) -> void:
	_road_preview.visible = radius > 0.0
	if not _road_preview.visible:
		return
	var surface := _road_tool()
	for piece: Array in RoadNet.ring_pieces(centre, radius):
		_add_road(surface, null, RoadCurve.new(piece[0], piece[1], piece[2]), sim.rules.road_types[PortSim.RING_ROAD])
	_road_preview.mesh = surface.commit()
	_road_preview.material_override.albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


## Shows the road a drag would build from `from` to `to`, curving through
## `control` (INF: straight), green if it can be built, else red; hidden
## when `from` is INF.
func show_road_preview(from: Vector2, to: Vector2, type: String, ok: bool, control := Vector2.INF) -> void:
	_road_preview.visible = from != Vector2.INF and from != to
	if not _road_preview.visible:
		return
	var surface := _road_tool()
	var curve := RoadCurve.straight(from, to) if control == Vector2.INF else RoadCurve.new(from, control, to)
	if type == "track":
		_add_track(surface, null, curve)
	else:
		_add_road(surface, null, curve, sim.rules.road_types[type])
	_road_preview.mesh = surface.commit()
	_road_preview.material_override.albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


## Marks the head of each lane into a junction with signals or a sign, when
## they or the phases showing green have changed.
func _draw_junctions() -> void:
	var junctions := Drive.junctions(sim)
	var green := {}
	for point: Vector2 in junctions.signals:
		var at: Dictionary = junctions.signals[point]
		green[point] = junctions.phases(Drive.junction_lanes(sim), point)[at.phase] if at.left > 0.0 else []
	var now := [sim.roads.version, green, junctions.signs.duplicate(true)]
	if now == _junctions_drawn:
		return
	_junctions_drawn = now
	var tool := _road_tool()
	var points := {}
	for point: Vector2 in junctions.signals.keys() + junctions.signs.keys():
		points[point] = true
	for point: Vector2 in points:
		for arm: Vector2i in Drive.arms(sim, point):
			var color := Color.TRANSPARENT
			if point in green:
				color = Color(0.2, 0.9, 0.3) if arm in green[point] else Color(0.95, 0.2, 0.15)
			elif junctions.signs.get(point, {}).has(arm):
				color = Color(0.95, 0.95, 0.95) if junctions.signs[point][arm] == "give_way" else Color(1.0, 0.55, 0.1)
			if color.a == 0.0:
				continue
			tool.set_color(color)
			# The approach lists each lane's last cells, nearest the box last.
			var cells := Drive.approach_cells(sim, point, arm)
			for i in range(APPROACH_MARK - 1, cells.size(), APPROACH_MARK):
				var middle := (Vector2(cells[i]) + Vector2(0.5, 0.5)) * Grid.CELL
				var way := Vector2(arm).normalized()
				_strip(tool, middle - way * Grid.CELL * 0.3, middle + way * Grid.CELL * 0.3, Grid.CELL * 0.35, ROAD_TOP + MARK_RISE * 3)
	_junction_signs.mesh = tool.commit()


## Rings the places where a road drag joins a road, in grid units (a road's
## grid point, or a track cell's middle), and dashes the guides it lines up
## with, as pairs of ends in `guides`; hidden when both are empty.
func show_snaps(places: Array[Vector2], guides: Array[Vector2]) -> void:
	_snap_marks.visible = not places.is_empty() or not guides.is_empty()
	if not _snap_marks.visible:
		return
	var tool := _road_tool()
	for place in places:
		_ring(tool, place * Grid.CELL, SNAP_RING * Grid.CELL, (SNAP_RING + 0.7) * Grid.CELL, ROAD_TOP + MARK_RISE * 2)
	for i in range(0, guides.size(), 2):
		var cells := guides[i].distance_to(guides[i + 1])
		var dir := guides[i].direction_to(guides[i + 1])
		# One cell dash, one cell gap.
		for k in range(0, ceili(cells), 2):
			var to := guides[i] + dir * minf(k + 1, cells)
			_strip(tool, (guides[i] + dir * k) * Grid.CELL, to * Grid.CELL, GUIDE_HALF * Grid.CELL, ROAD_TOP + MARK_RISE * 2)
	_snap_marks.mesh = tool.commit()


## Shows `cells` as the area a drag would build, green or red; hidden when empty.
func show_area_preview(cells: Array[Vector2i], ok: bool) -> void:
	_area_preview.visible = not cells.is_empty()
	if cells.is_empty():
		return
	var tool := _road_tool()
	for cell in cells:
		_cell_quad(tool, cell, AREA_TOP + 0.05)
	_area_preview.mesh = tool.commit()
	_area_preview.material_override.albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


func _process(dt: float) -> void:
	_info.visible = info_view in INFO_LEGENDS
	_info_left -= dt
	if _info.visible and _info_left <= 0.0:
		_info_left = INFO_SECONDS
		_draw_info()
	if [sim.roads.version, sim.rails.version, sim.town.bypass] != _roads_drawn:
		_draw_roads()
	if [sim.areas.version, sim.roads.version] != _areas_drawn:
		_draw_areas()
	if [sim.ship_lanes.version, sim.dredge_version, sim.anchorages.keys(), sim.areas.breakwaters.keys()] != _ship_lanes_drawn:
		_draw_ship_lanes()
	_draw_junctions()
	if _coast_image == null or sim.areas.filled.size() != _coast_filled.size():
		_draw_fill()
	if sim.land.size() != _drawn_land:
		_draw_land()
	_draw_ships()
	_draw_marine()
	_light_up()
	_draw_town()
	_draw_vans()
	_draw_fires()
	_animate_barriers(dt)
	_draw_cranes()
	_draw_vehicles(dt)
	_draw_trains()
	_draw_area_machines()
	_draw_area_stacks()


func _draw_roads() -> void:
	_roads_drawn = [sim.roads.version, sim.rails.version, sim.town.bypass]
	var surface := _road_tool()
	var marks := _road_tool()
	# Markings stop where a junction's shape cuts each road back, as its lanes do (LaneNetwork).
	var cut := LaneNetwork._trims(LaneNetwork._arms(sim.roads), sim.rules.junctions)
	var trim := func(id: int, end: String) -> float: return cut[[id, end]] * Grid.CELL if sim.roads.degree(sim.roads.segments[id][end]) >= 3 else 0.0
	for id: int in sim.roads.segments:
		var road: Dictionary = sim.roads.segments[id]
		_add_road(surface, marks, sim.roads.curve(id), sim.rules.road_types[road.type], trim.call(id, "a"), trim.call(id, "b"))
	# The highway, from off the map to the site entry, so the player sees where to join it.
	var entry := sim.site_entry_point()
	var off_map := Vector2i(ceili(-SEA_START * METRES_PER_UNIT / Grid.CELL), 0)
	_add_road(surface, marks, RoadCurve.straight(Vector2(entry + off_map), Vector2(entry)), sim.rules.road_types.terminal_2_2)
	if sim.town.bypass:
		_add_road(surface, marks, _bypass(sim), sim.rules.road_types.terminal_2_2)
	# The main line the same way, to the rail entry.
	var rail_entry := Vector2(sim.site_rail_entry()) + Vector2(0.5, 0.5)
	_add_track(surface, marks, RoadCurve.straight(rail_entry + Vector2(off_map), rail_entry))
	for id: int in sim.rails.segments:
		_add_track(surface, marks, sim.rails.curve(id))
	_roads.mesh = surface.commit()
	_road_marks.mesh = marks.commit()


func _draw_areas() -> void:
	_areas_drawn = [sim.areas.version, sim.roads.version]
	var tool := _road_tool()
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		# Each of the area's own cells (k, r) coloured by the part of its layout it holds.
		var colors := {}
		var layout := sim.areas.layout(id)
		var paint := func(spot: Vector3i, color: Color) -> void: colors[Vector2i(spot.y, spot.z)] = color
		for spot: Vector3i in layout.get("buffer", []) + layout.get("back_buffer", []):
			paint.call(spot, BUFFER_COLOR)
		for lane: Array in layout.get("lanes", []):
			for spot: Vector3i in lane:
				paint.call(spot, ASPHALT)
		for rail: Array in layout.get("rails", []):
			for spot: Vector3i in rail:
				paint.call(spot, RAIL_COLOR)
		for spot: Vector3i in layout.get("edge", []):
			paint.call(spot, EDGE_COLOR)
		for k in AreaFlow.crane_spots(sim, id) if area.type == "quay_apron" else ([] as Array[int]):
			for d in sim.areas.depth_of(area):
				colors[Vector2i(k, d)] = SPOT_COLOR
		for i: int in layout.get("slots", []).size():
			for spot: Vector3i in layout.slots[i]:
				paint.call(spot, SLOT_COLORS[i % 2])
		for i: int in layout.get("back_slots", []).size():
			for spot: Vector3i in layout.back_slots[i]:
				paint.call(spot, SLOT_COLORS[i % 2])
		var idle := sim.areas.idle_reason(id) != ""
		for cell: Dictionary in sim.areas.shape(id).cells:
			var color: Color = colors.get(Vector2i(cell.k, cell.r), AREA_COLOR[sim.areas.kind_of(area)])
			tool.set_color(color.lerp(IDLE_TINT, 0.4) if idle else color)
			_quad(tool, cell.corners, AREA_TOP)
	_areas.mesh = tool.commit()
	_draw_area_buildings()
	_draw_agv_zone()
	_draw_floodlights()


func _draw_agv_zone() -> void:
	var zone: Dictionary = sim.areas.agv_zone
	var tool := _road_tool()
	var lanes := {}
	for segment: int in sim.roads.segments:
		for cell in sim.roads.ground(segment):
			lanes[cell] = true
	var edge := 0.12  # of a cell
	for cell: Vector2i in zone:
		var at := Vector2(cell)
		if cell in lanes:
			tool.set_color(AGV_LANE)
			_quad(tool, [at, at + Vector2(1, 0), at + Vector2.ONE, at + Vector2(0, 1)], ROAD_TOP + ASPHALT_RISE + 0.02)
		tool.set_color(Color(1.0, 0.8, 0.1) if posmod(cell.x + cell.y, 2) == 0 else Color(0.1, 0.1, 0.1))
		for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if cell + side in zone:
				continue
			# The strip along this side, just inside the cell.
			var a := at + Vector2(maxi(side.x, 0), maxi(side.y, 0))
			var along := Vector2(absi(side.y), absi(side.x))
			var inward := -Vector2(side) * edge
			_quad(tool, [a, a + along, a + along + inward, a + inward], ROAD_TOP + ASPHALT_RISE + 0.04)
	_agv_zone.mesh = tool.commit()
	for barrier: Dictionary in _barriers:
		barrier.node.queue_free()
	_barriers.clear()
	Drive._refresh(sim)
	var pieces: Dictionary = sim.network.pieces
	for id: int in pieces:
		var piece: Dictionary = pieces[id]
		if not piece.next.any(func(n: int) -> bool: return pieces[n].agv != piece.agv):
			continue
		var points: PackedVector2Array = piece.points
		var way := (points[-1] - points[-2]).normalized()
		var barrier := MeshInstance3D.new()
		barrier.mesh = _barrier_mesh()
		var at := _world(points[-1] * Grid.CELL, ROAD_TOP + ASPHALT_RISE)
		barrier.position = at
		barrier.basis = Basis(Vector3.UP, atan2(-way.y, way.x))
		add_child(barrier)
		var boom := MeshInstance3D.new()
		boom.mesh = _boom_cache
		boom.position = Vector3(0, 0.055, -Grid.CELL / METRES_PER_UNIT * 0.5)
		barrier.add_child(boom)
		_barriers.append({"node": barrier, "boom": boom, "at": points[-1], "lift": 0.0})


## Lifts each barrier's boom while a service vehicle is close to it, a
## mechanic's van or fire engine passing into or out of the AGV zone, and
## lowers it once it has gone.
func _animate_barriers(dt: float) -> void:
	if _barriers.is_empty():
		return
	var near: Array[Vector2] = []
	for vehicle: Dictionary in sim.workshops.vans.values() + sim.fires.engines.values():
		if vehicle.job != "home":
			near.append(vehicle.at)
	for barrier: Dictionary in _barriers:
		var up := near.any(func(p: Vector2) -> bool: return p.distance_to(barrier.at) < 2.5)
		barrier.lift = move_toward(barrier.lift, 1.0 if up else 0.0, dt * 1.5)
		barrier.boom.rotation.x = -barrier.lift * PI * 0.45


## A boom barrier at a lane's end (x along the lane, z across it): a
## yellow post at the kerb, a red-white striped boom down across the lane, a
## small grey cabin with a sign.
func _barrier_mesh() -> Mesh:
	if _barrier_cache == null:
		var lane := Grid.CELL / METRES_PER_UNIT  # a cell, about a lane wide
		var parts: Array = [
			[Vector3(0.025, 0.06, 0.025), Vector3(0, 0.03, -lane * 0.5), Color(1.0, 0.8, 0.1)],
			[Vector3(0.03, 0.03, 0.03), Vector3(0, 0.06, -lane * 0.5), Color(0.15, 0.15, 0.15)],
			[Vector3(0.05, 0.05, 0.04), Vector3(-0.03, 0.025, -lane * 0.5 - 0.05), Color(0.7, 0.72, 0.74)],
			[Vector3(0.052, 0.006, 0.042), Vector3(-0.03, 0.053, -lane * 0.5 - 0.05), Color(0.25, 0.27, 0.3)],
			[Vector3(0.002, 0.02, 0.03), Vector3(-0.004, 0.035, -lane * 0.5 - 0.05), Color(1.0, 0.65, 0.1)],
		]
		_barrier_cache = _merged(parts)
		# The boom, red and white, from its hinge at the post across the lane.
		var boom: Array = []
		var stripes := 6
		for k: int in stripes:
			boom.append([Vector3(0.008, 0.008, lane / stripes), Vector3(0, 0, (k + 0.5) * lane / stripes), Color(0.9, 0.1, 0.1) if k % 2 == 0 else Color.WHITE])
		_boom_cache = _merged(boom)
	return _barrier_cache


## Night lights' parts and materials: masts in grey steel, lamps and ships'
## lights glowing in their own colours (unshaded), pools of light and lamps'
## beams soft and additive, brighter the darker it is.
func _make_lights() -> void:
	var ramp := Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(1, 1, 1, 0))
	var soft := GradientTexture2D.new()
	soft.gradient = ramp
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	_glow.albedo_texture = soft
	_glow.vertex_color_use_as_albedo = true
	_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.no_depth_test = false
	_bright.vertex_color_use_as_albedo = true
	_bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flat := QuadMesh.new()
	flat.orientation = PlaneMesh.FACE_Y
	flat.size = Vector2.ONE
	_masts.multimesh.mesh = _merged([[Vector3(0.025, MAST_HEIGHT, 0.025), Vector3(0, MAST_HEIGHT / 2.0, 0), Color(0.55, 0.57, 0.6)], [Vector3(0.12, 0.02, 0.05), Vector3(0, MAST_HEIGHT, 0), Color(0.3, 0.32, 0.35)]])
	var lamps: Mesh = _merged([[Vector3(0.1, 0.012, 0.04), Vector3(0, MAST_HEIGHT - 0.016, 0), Color.WHITE]])
	lamps.surface_set_material(0, _bright)
	_lamps.multimesh.mesh = lamps
	for part: MultiMeshInstance3D in [_pools, _beams]:
		part.multimesh.mesh = flat
		part.material_override = _glow
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for part: MultiMeshInstance3D in [_masts, _lamps, _pools, _beams]:
		add_child(part)


## A MultiMesh of one part, coloured per instance, to fill with _put.
func _flat_part() -> MultiMeshInstance3D:
	var part := MultiMeshInstance3D.new()
	part.multimesh = MultiMesh.new()
	part.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	part.multimesh.use_colors = true
	return part


## A floodlight mast every MAST_EVERY cells along each yard, transfer
## block, quay apron, gate, truck park and AGV depot, at its back edge
## (a quay apron's road side), with its lamps and the pool of light under it.
func _draw_floodlights() -> void:
	var masts := PackedFloat32Array()
	var lamps := PackedFloat32Array()
	var pools := PackedFloat32Array()
	var pool := MAST_REACH * Grid.CELL / METRES_PER_UNIT
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		var kind := sim.areas.kind_of(area)
		if kind not in ["yard_block", "transfer_block", "quay_apron", "gate", "parking", "agv_depot"]:
			continue
		var row: float = 0.0 if kind == "quay_apron" else sim.areas.depth_of(area) - 0.5
		var k := MAST_EVERY / 2.0
		while k < area.columns:
			var at := sim.areas.point(id, k, row) * Grid.CELL / METRES_PER_UNIT
			var out := sim.areas.out_at(id, k)
			# The lamps lean out over the area they light.
			var facing := Basis(Vector3.UP, atan2(out.x, out.y))
			var foot := Vector3(at.x, AREA_TOP / METRES_PER_UNIT, at.y)
			_put(masts, Transform3D(facing, foot), Color.WHITE)
			_put(lamps, Transform3D(facing, foot), Color(1.0, 0.92, 0.75))
			var lit := sim.areas.point(id, k, row - MAST_REACH * 0.5 * (1.0 if kind != "quay_apron" else -1.0)) * Grid.CELL / METRES_PER_UNIT
			_put(pools, Transform3D(Basis.IDENTITY.scaled(Vector3(pool * 2.0, 1.0, pool * 2.0)), Vector3(lit.x, AREA_TOP / METRES_PER_UNIT + 0.03, lit.y)), Color(1.0, 0.85, 0.6))
			k += MAST_EVERY
	for pair: Array in [[_masts, masts], [_lamps, lamps], [_pools, pools]]:
		var multimesh: MultiMesh = pair[0].multimesh
		multimesh.instance_count = pair[1].size() / 16
		if not pair[1].is_empty():
			multimesh.buffer = pair[1]


## Each frame, the lights as dark as the hour is: lamps and ships' lights
## on after dusk, the pools of light and beams fading in with the dark.
func _light_up() -> void:
	_dark = DayNight.darkness(fmod(sim.clock.calendar_minutes() / 60.0, 24.0))
	var on := _dark > 0.05
	_lamps.visible = on
	_pools.visible = on
	_beams.visible = on
	_glow.albedo_color = Color(1, 1, 1, _dark * 0.3)
	_town_windows.visible = on
	for lights: Node3D in _ship_lights:
		if is_instance_valid(lights):
			lights.visible = on


## The building on each area that has one, built again with the areas: a
## workshop's shed or a fire station, standing on the area's middle with its
## doors to the road.
func _draw_area_buildings() -> void:
	for node: Node3D in _area_buildings.values():
		node.queue_free()
	_area_buildings.clear()
	for id: int in sim.areas.list:
		var area: Dictionary = sim.areas.list[id]
		var kind := sim.areas.kind_of(area)
		if kind not in ["workshop", "fire_station", "agv_depot"]:
			continue
		var unit := Grid.CELL / METRES_PER_UNIT
		var middle: float = area.columns / 2.0
		var depth := sim.areas.depth_of(area)
		var size := _building_size(id)
		var model := MeshInstance3D.new()
		model.mesh = _merged({"fire_station": _fire_station(size), "workshop": _workshop(size), "agv_depot": _agv_depot(size)}[kind])
		var at := sim.areas.point(id, middle, (depth - 1) / 2.0) * unit
		var along := sim.areas.heading(id, middle)
		var out := sim.areas.out_at(id, middle)
		var x := Vector3(along.x, 0, along.y)
		# Keep the frame right-handed on either side of the road, so faces stay outward.
		if x.cross(Vector3.UP).dot(Vector3(out.x, 0, out.y)) < 0.0:
			x = -x
		model.basis = Basis(x, Vector3.UP, Vector3(out.x, 0, out.y))
		model.position = Vector3(at.x, AREA_TOP / METRES_PER_UNIT, at.y)
		add_child(model)
		_area_buildings[id] = model


## The size of area `id`'s building: across (along its road) and deep.
func _building_size(id: int) -> Vector2:
	var area: Dictionary = sim.areas.list[id]
	var unit := Grid.CELL / METRES_PER_UNIT
	return Vector2(minf(area.columns * unit * 0.85, 1.8), sim.areas.depth_of(area) * unit * 0.75)


## A fire station `size` across (x along the road) and deep (z away from
## it): red brick, three engine bays with white-framed red doors to the
## road, a white band, a flat roof with a blue light bar, a hose-drying
## tower at one end and a flagpole.
static func _fire_station(size: Vector2) -> Array:
	var brick := Color(0.62, 0.2, 0.15)
	var white := Color(0.95, 0.95, 0.93)
	var h := 0.32
	var front := -size.y / 2.0
	var parts: Array = [
		[Vector3(size.x, h, size.y), Vector3(0, h / 2.0, 0), brick],
		[Vector3(size.x + 0.01, 0.03, size.y + 0.01), Vector3(0, h * 0.72, 0), white],
		[Vector3(size.x + 0.04, 0.03, size.y + 0.04), Vector3(0, h + 0.015, 0), Color(0.35, 0.35, 0.37)],
		[Vector3(size.x * 0.3, 0.03, 0.04), Vector3(0, h + 0.045, front * 0.4), Color(0.2, 0.4, 1.0)],
	]
	var bays := 3
	var bay := size.x * 0.7 / bays
	for k: int in bays:
		var x := (k - (bays - 1) / 2.0) * bay * 1.15 - size.x * 0.1
		parts.append([Vector3(bay * 0.92, h * 0.62, 0.02), Vector3(x, h * 0.31, front - 0.005), white])
		parts.append([Vector3(bay * 0.8, h * 0.56, 0.025), Vector3(x, h * 0.28, front - 0.01), Color(0.78, 0.1, 0.08)])
	var tower := Vector3(size.x / 2.0 - 0.08, 0, size.y / 4.0)
	parts.append_array([
		[Vector3(0.14, h * 2.0, 0.14), tower + Vector3(0, h, 0), brick],
		[Vector3(0.16, 0.04, 0.16), tower + Vector3(0, h * 2.0 + 0.02, 0), white],
		[Vector3(0.012, 0.35, 0.012), Vector3(-size.x / 2.0 + 0.05, h + 0.175, front + 0.05), white],
		[Vector3(0.002, 0.06, 0.09), Vector3(-size.x / 2.0 + 0.05, h + 0.32, front + 0.1), Color(0.8, 0.15, 0.12)],
	])
	return parts


## An AGV (x across, z along, y up, before AREA_VEHICLE_SCALE): a long low
## white body with a teal stripe, a steel deck the box sits on, yellow bumpers at both ends,
## wheels, white lights ahead and red behind, an amber beacon.
static func _agv_parts() -> Array:
	var parts: Array = [
		[Vector3(0.22, 0.07, 0.6), Vector3(0, 0.045, 0), Color(0.95, 0.96, 0.97)],
		[Vector3(0.222, 0.018, 0.56), Vector3(0, 0.05, 0), Color(0.05, 0.6, 0.62)],
		[Vector3(0.21, 0.012, 0.56), Vector3(0, 0.086, 0), Color(0.45, 0.47, 0.5)],
	]
	for end: float in [-1.0, 1.0]:
		parts.append([Vector3(0.23, 0.03, 0.025), Vector3(0, 0.04, end * 0.31), Color(1.0, 0.8, 0.1)])
		parts.append([Vector3(0.231, 0.008, 0.026), Vector3(0, 0.04, end * 0.31), Color(0.1, 0.1, 0.1)])
		parts.append([Vector3(0.235, 0.04, 0.07), Vector3(0, 0.02, end * 0.2), Color(0.08, 0.08, 0.08)])
		for side: float in [-1.0, 1.0]:
			parts.append([Vector3(0.03, 0.015, 0.01), Vector3(side * 0.08, 0.065, end * 0.301), Color(1, 1, 0.9) if end > 0 else Color(0.9, 0.1, 0.1)])
	return parts


## An AGV depot `size` across and deep: an open-fronted canopy shed on
## posts over its bays, a glazed control office at one end, a teal sign.
static func _agv_depot(size: Vector2) -> Array:
	var steel := Color(0.72, 0.74, 0.76)
	var h := 0.26
	var front := -size.y / 2.0
	var shed := size.x * 0.75
	var middle := -size.x * 0.125
	var parts: Array = [
		[Vector3(shed, 0.03, size.y), Vector3(middle, h, 0), steel],
		[Vector3(shed, h, 0.02), Vector3(middle, h / 2.0, -front), steel.darkened(0.2)],
		[Vector3(shed + 0.01, 0.015, 0.02), Vector3(middle, h - 0.02, front), Color(0.1, 0.55, 0.55)],
		[Vector3(size.x * 0.22, h * 0.8, size.y * 0.55), Vector3(size.x * 0.38, h * 0.4, size.y * 0.15), Color(0.9, 0.9, 0.88)],
		[Vector3(size.x * 0.221, h * 0.3, size.y * 0.551), Vector3(size.x * 0.38, h * 0.55, size.y * 0.15), Color(0.25, 0.45, 0.6)],
		[Vector3(size.x * 0.24, 0.03, size.y * 0.57), Vector3(size.x * 0.38, h * 0.8 + 0.015, size.y * 0.15), Color(0.15, 0.2, 0.26)],
		[Vector3(size.x * 0.18, 0.05, 0.012), Vector3(size.x * 0.38, h * 0.95, size.y * 0.15 - size.y * 0.28), Color(0.1, 0.6, 0.6)],
	]
	var bays := 4
	for k: int in bays + 1:
		var x := middle - shed / 2.0 + k * shed / bays
		parts.append([Vector3(0.02, h, 0.02), Vector3(x, h / 2.0, front + 0.02), steel.darkened(0.35)])
	# Four parking lanes along the road, as AGVs drive in, marked in yellow.
	for r: int in AGV_LANES + 1:
		parts.append([Vector3(shed, 0.002, 0.008), Vector3(middle, 0.002, _lane_z(size, r) - size.y * 0.45 / AGV_LANES), Color(1.0, 0.8, 0.1)])
	return parts


## A workshop's shed `size` across and deep: blue-grey cladding, a ridged
## roof, a big roller door to the road with stripes, a white office annex at
## one end and an orange sign.
static func _workshop(size: Vector2) -> Array:
	var clad := Color(0.48, 0.55, 0.62)
	var h := 0.28
	var front := -size.y / 2.0
	var parts: Array = [
		[Vector3(size.x * 0.75, h, size.y), Vector3(-size.x * 0.125, h / 2.0, 0), clad],
		[Vector3(size.x * 0.77, 0.05, size.y * 0.55), Vector3(-size.x * 0.125, h + 0.02, -size.y * 0.22), clad.darkened(0.2)],
		[Vector3(size.x * 0.77, 0.05, size.y * 0.55), Vector3(-size.x * 0.125, h + 0.02, size.y * 0.22), clad.darkened(0.3)],
		[Vector3(size.x * 0.77, 0.04, 0.04), Vector3(-size.x * 0.125, h + 0.05, 0), clad.darkened(0.4)],
		[Vector3(size.x * 0.4, h * 0.8, 0.02), Vector3(-size.x * 0.125, h * 0.4, front - 0.005), Color(0.3, 0.32, 0.34)],
		[Vector3(size.x * 0.25, h * 0.75, size.y * 0.6), Vector3(size.x * 0.375, h * 0.375, -size.y * 0.2), Color(0.92, 0.92, 0.9)],
		[Vector3(size.x * 0.26, 0.04, size.y * 0.61), Vector3(size.x * 0.375, h * 0.5, -size.y * 0.2), Color(0.15, 0.2, 0.26)],
		[Vector3(size.x * 0.3, 0.06, 0.015), Vector3(-size.x * 0.125, h * 0.9, front - 0.01), Color(1.0, 0.55, 0.1)],
	]
	for k: int in 5:
		parts.append([Vector3(size.x * 0.4, 0.008, 0.022), Vector3(-size.x * 0.125, h * (0.12 + k * 0.14), front - 0.008), Color(0.22, 0.24, 0.26)])
	return parts


## Colours each place info_shares gives from green through amber to red.
func _draw_info() -> void:
	var legend: Array = INFO_LEGENDS[info_view]
	var shares := info_shares(sim, info_view)
	var tool := _road_tool()
	for cells: Array in shares:
		var share: float = shares[cells]
		var color: Color = legend[0][1].lerp(legend[1][1], share * 2.0) if share < 0.5 else legend[1][1].lerp(legend[2][1], share * 2.0 - 1.0)
		tool.set_color(Color(color, 0.7))
		for cell: Vector2i in cells:
			_cell_quad(tool, cell, INFO_TOP)
	_info.mesh = tool.commit()


## For the Traffic view, each cell vehicles wait in, alone -> its smoothed
## delay against JAM_SECONDS, from 0 (flowing) to 1 (jammed), so a queue
## shows where it is however long its road; for Containers, each yard
## block's cells -> how full it is.
static func info_shares(sim: PortSim, view: String) -> Dictionary:
	var shares := {}
	if view == HudDetails.GROUP_TRAFFIC:
		var delays := Drive.delays(sim)
		for cell: Vector2i in delays:
			shares[[cell]] = minf(delays[cell] / JAM_SECONDS, 1.0)
	elif view == TOWN_NOISE:
		shares = Town.noise_shares(sim)
	else:
		for id: int in sim.areas.list:
			if sim.areas.list[id].type in Areas.BLOCK_TYPES:
				var fill := sim.block_fill(id)
				shares[sim.areas.cells(id)] = fill.x / float(maxi(fill.y, 1))
	return shares


## Each ship lane as a pale band over the water it covers, its line down the
## middle: white where dredged, else pale blue.
func _draw_ship_lanes() -> void:
	_ship_lanes_drawn = [sim.ship_lanes.version, sim.dredge_version, sim.anchorages.keys(), sim.areas.breakwaters.keys()]
	_ship_lanes.visible = not (sim.ship_lanes.segments.is_empty() and sim.anchorages.is_empty() and sim.areas.breakwaters.is_empty())
	if not _ship_lanes.visible:
		return
	var tool := _road_tool()
	# Breakwaters as grey rock.
	tool.set_color(Color(0.55, 0.55, 0.52, 1.0))
	for wall: Dictionary in sim.areas.breakwaters.values():
		for cell in Areas.breakwater_cells(wall.from, wall.to):
			_cell_quad(tool, cell, 0.05)
	# Each anchorage as one pale yellow rectangle, a dot at each spot.
	for id: int in sim.anchorages:
		var a: Dictionary = sim.anchorages[id]
		tool.set_color(Color(1.0, 0.9, 0.4, 0.15))
		var low := Vector2(a.from) * Grid.CELL
		var high := Vector2(a.to + Vector2i.ONE) * Grid.CELL
		var corners := [Vector2(low.x, low.y), Vector2(high.x, low.y), Vector2(high.x, high.y), Vector2(low.x, high.y)]
		for i: int in [0, 1, 2, 0, 2, 3]:
			tool.add_vertex(_world(corners[i], LANE_HEIGHT))
		tool.set_color(Color(1.0, 0.9, 0.4, 0.6))
		for spot in Marine.spots(sim, id):
			_cell_quad(tool, Vector2i(spot.floor()), LANE_HEIGHT + 0.01)
	for segment: int in sim.ship_lanes.segments:
		var lane: Dictionary = sim.ship_lanes.segments[segment]
		tool.set_color(Color(0.75, 0.9, 1.0, 0.12))
		for cell in sim.ship_lanes.area(segment):
			_cell_quad(tool, cell, LANE_HEIGHT)
		tool.set_color(Color(1, 1, 1, 0.55) if lane.dredged > 0.0 else Color(0.7, 0.85, 1.0, 0.45))
		for cell in sim.ship_lanes.cells(segment):
			_cell_quad(tool, cell, LANE_HEIGHT + 0.01)
	_ship_lanes.mesh = tool.commit()


## One 4 m cell as a flat square `height` metres up.
static func _cell_quad(tool: SurfaceTool, cell: Vector2i, height: float) -> void:
	_quad(tool, [Vector2(cell), Vector2(cell) + Vector2(1, 0), Vector2(cell) + Vector2(1, 1), Vector2(cell) + Vector2(0, 1)], height)


## The quad with corners `corners`, in cells.
## A flat quad through `corners` at `height`, facing up whichever way round
## its corners run (an area's run one way on one side of its road and the
## other on the other), so it is never culled from above.
static func _quad(tool: SurfaceTool, corners: Array, height: float) -> void:
	var a: Vector2 = corners[0]
	var turn: float = (corners[1] - a).cross(corners[2] - a)
	for i: int in ([0, 1, 2, 0, 2, 3] if turn > 0.0 else [0, 2, 1, 0, 3, 2]):
		tool.add_vertex(_world(corners[i] * Grid.CELL, height))


static func _road_tool() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	tool.set_material(material)
	return tool


## Adds a road from cell `a` to cell `b` of type `road` to `surface`: a strip
## over its lane cells with round ends, which overlap into arcs where roads
## bend; ends at a junction (a trim) are left square. Markings go to `marks` unless it is null: a solid line between the
## two directions, dashes between lanes going the same way, stopping `trim_a`
## and `trim_b` metres short of the ends.
static func _add_road(surface: SurfaceTool, marks: Variant, curve: RoadCurve, road: Dictionary, trim_a := 0.0, trim_b := 0.0) -> void:
	var lanes: int = road.forward + road.backward
	var half := lanes * Grid.CELL / 2.0
	surface.set_color(ASPHALT if road.lorries else TRACTOR_ONLY)
	var top := ROAD_TOP + (ASPHALT_RISE if road.lorries else 0.0)
	# The asphalt is the road's own lane quads, as the sim lays them (RoadNet.shape), so it bends with the road.
	for cell: Dictionary in RoadNet._shape_of(curve, road).cells:
		# Cells left of the line are laid the other way round; face them all up.
		var corners: Array = cell.corners.duplicate()
		if (corners[1] - corners[0]).cross(corners[2] - corners[0]) < 0.0:
			corners.reverse()
		_quad(surface, corners, top)
	# A junction's widest road covers its middle, so an end there gets no round cap to poke out past it.
	if trim_a == 0.0:
		_disc(surface, curve.a * Grid.CELL, half, top)
	if trim_b == 0.0:
		_disc(surface, curve.b * Grid.CELL, half, top)
	if marks == null:
		return
	marks.set_color(MARKING)
	var total := curve.length * Grid.CELL
	var length := total - trim_a - trim_b
	if length <= 0.0:
		return
	# The point `d` metres along the road and `offset` metres right of its line, in metres.
	var at := func(d: float, offset: float) -> Vector2: return (curve.point_at(d / Grid.CELL) + curve.right_at(d / Grid.CELL) * offset / Grid.CELL) * Grid.CELL
	# Where a road meets a junction: a zebra crossing at its edge, a stop line
	# behind it across the lanes driving in, then the lane markings, if they fit.
	var ends := int(trim_a > 0.0) + int(trim_b > 0.0)
	if ends > 0 and length >= JUNCTION_MARKS * ends + DASH:
		var middle_line: float = road.backward * Grid.CELL - half
		if trim_a > 0.0:
			_junction_marks(marks, at.call(trim_a, 0.0), curve.direction_at(trim_a / Grid.CELL), curve.right_at(trim_a / Grid.CELL), half, -half, middle_line)
			trim_a += JUNCTION_MARKS
		if trim_b > 0.0:
			_junction_marks(marks, at.call(total - trim_b, 0.0), -curve.direction_at((total - trim_b) / Grid.CELL), curve.right_at((total - trim_b) / Grid.CELL), half, middle_line, half)
			trim_b += JUNCTION_MARKS
	for k in range(1, lanes):
		var offset := k * Grid.CELL - half
		var solid: bool = k == road.backward
		var d := trim_a
		while d < total - trim_b:
			var dash_end := total - trim_b if solid else minf(d + DASH, total - trim_b)
			# In half-cell steps, so a mark bends with the road.
			var step := d
			while step < dash_end:
				var next := minf(step + Grid.CELL / 2.0, dash_end)
				_strip(marks, at.call(step, offset), at.call(next, offset), MARK_WIDTH / 2.0, ROAD_TOP + MARK_RISE)
				step = next
			d = dash_end + (0.0 if solid else DASH_GAP)


## A zebra crossing across a road `half` metres wide each side of `edge`,
## where it meets a junction, reaching `away` from it; then a stop line
## across the lanes from `from` to `to` metres along `side`.
static func _junction_marks(marks: SurfaceTool, edge: Vector2, away: Vector2, side: Vector2, half: float, from: float, to: float) -> void:
	var stripe := -half + ZEBRA_STRIPE
	while stripe < half - ZEBRA_STRIPE / 2.0:
		_strip(marks, edge + side * stripe, edge + side * stripe + away * ZEBRA_DEPTH, ZEBRA_STRIPE / 2.0, ROAD_TOP + MARK_RISE)
		stripe += ZEBRA_STRIPE * 2.0
	if to > from:
		var line := edge + away * (ZEBRA_DEPTH + STOP_GAP)
		_strip(marks, line + side * from, line + side * to, STOP_WIDTH / 2.0, ROAD_TOP + MARK_RISE)


## Adds rail track from cell `a` to cell `b`: a ballast bed a cell wide on
## the cells' middle line, with two rails to `marks` unless it is null.
static func _add_track(surface: SurfaceTool, marks: Variant, curve: RoadCurve) -> void:
	surface.set_color(BALLAST)
	_polyline(surface, curve.offset_points(0.0), Grid.CELL / 2.0, ROAD_TOP)
	if marks == null:
		return
	marks.set_color(STEEL)
	for gauge: float in [-RAIL_GAUGE, RAIL_GAUGE]:
		_polyline(marks, curve.offset_points(gauge / Grid.CELL), RAIL_HALF, ROAD_TOP + MARK_RISE)


## Strips `half` either side of each piece of `points`, in cells.
static func _polyline(tool: SurfaceTool, points: PackedVector2Array, half: float, height: float) -> void:
	for i in points.size() - 1:
		_strip(tool, points[i] * Grid.CELL, points[i + 1] * Grid.CELL, half, height)


## A flat strip `half` either side of the line from `from` to `to`, in metres.
static func _strip(tool: SurfaceTool, from: Vector2, to: Vector2, half: float, height: float) -> void:
	var side := (to - from).normalized().orthogonal() * half
	var corners: Array[Vector2] = [from - side, to - side, to + side, from + side]
	# Clockwise from above, Godot's front face.
	for i: int in [0, 2, 1, 0, 3, 2]:
		tool.add_vertex(_world(corners[i], height))


## A flat ring between `inner` and `outer` metres round `centre`.
static func _ring(tool: SurfaceTool, centre: Vector2, inner: float, outer: float, height: float) -> void:
	const STEPS := 24
	for i in STEPS:
		var a := Vector2.from_angle(TAU * i / STEPS)
		var b := Vector2.from_angle(TAU * (i + 1) / STEPS)
		# Clockwise from above, Godot's front face.
		for point: Vector2 in [a * inner, a * outer, b * outer, a * inner, b * outer, b * inner]:
			tool.add_vertex(_world(centre + point, height))


## A flat disc of `radius` metres round `centre`, for a road's round end.
static func _disc(tool: SurfaceTool, centre: Vector2, radius: float, height: float) -> void:
	const STEPS := 16
	for i in STEPS:
		var from := centre + Vector2.from_angle(TAU * i / STEPS) * radius
		var to := centre + Vector2.from_angle(TAU * (i + 1) / STEPS) * radius
		for point: Vector2 in [centre, from, to]:
			tool.add_vertex(_world(point, height))


## A point in metres on the ground as a world position.
static func _world(metres: Vector2, height: float) -> Vector3:
	return Vector3(metres.x, height, metres.y) / METRES_PER_UNIT


## Marks the land tiles the port owns; the land shader shades the rest.
func _draw_land() -> void:
	_drawn_land = sim.land.size()
	var tiles := Vector2i((site_size(sim) * METRES_PER_UNIT / sim.rules.land.metres).ceil())
	var image := Image.create(tiles.x, tiles.y, false, Image.FORMAT_R8)
	for tile: Vector2i in sim.land:
		image.set_pixelv(tile, Color.RED)
	_owned.set_image(image)


## The coast a pixel a cell (see _coast): red 1 on land, green the water's
## depth against max_depth metres.
static func coast_image(sim: PortSim) -> Image:
	var size := sim.areas.coast.size
	var deepest: float = MapGen.of(sim.rules, sim.map).depth.max
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * 2)
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			var i := (y * size.x + x) * 2
			if sim.areas.is_water(cell):
				bytes[i + 1] = roundi(clampf(sim.areas.coast.depth(cell) / deepest, 0.0, 1.0) * 255.0)
			else:
				bytes[i] = 255
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RG8, bytes)


## Draws the coast whole the first time, then only the cells filled since.
func _draw_fill() -> void:
	if _coast_image == null:
		_coast_image = coast_image(sim)
		_coast_filled = sim.areas.filled.duplicate()
		_coast.set_image(_coast_image)
		return
	for cell: Vector2i in sim.areas.filled:
		if cell not in _coast_filled:
			_coast_filled[cell] = true
			_coast_image.set_pixelv(cell, Color(1, 0, 0))
	_coast.update(_coast_image)


## The 4 m grid cell at world point `at`.
static func grid_cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x * METRES_PER_UNIT / Grid.CELL), floori(at.z * METRES_PER_UNIT / Grid.CELL))


## The colour of box `id` of `line` (M11 box_look): a reefer white; else
## own_share in the line's livery, the rest leased in a lessor's colour; each
## faded and darkened by age, rust_share of them rusty. The same every frame:
## each choice is rolled from the box's id.
func _box_colour(line: String, id: int, reefer: bool) -> Color:
	var look: Dictionary = sim.rules.box_look
	var colour: Color
	if reefer:
		colour = Color.html(look.reefer)
	elif line == "":
		colour = PLAIN_BOX
	elif _own(id):
		colour = Color.html(sim.rules.lines[line].livery)
	else:
		colour = Color.html(look.lessors[mini(int(_roll(id, "lessor") * look.lessors.size()), look.lessors.size() - 1)])
	colour = colour.darkened(_roll(id, "dark") * look.weathering).lerp(PLAIN_BOX, _roll(id, "fade") * look.weathering * 0.5)
	if _roll(id, "rust") < look.rust_share:
		colour = colour.lerp(Color.html(look.rust), 0.15 + _roll(id, "rusty") * 0.25)
	return colour


## The band along box `id`'s side, or clear: stripe_share of a line's own boxes carry its stripe.
func _box_stripe(line: String, id: int, reefer: bool) -> Color:
	if reefer or line == "" or not _own(id) or _roll(id, "stripe") >= sim.rules.box_look.stripe_share:
		return Color.TRANSPARENT
	return Color.html(sim.rules.lines[line].stripe)


## Whether box `id` is its line's own, not leased.
func _own(id: int) -> bool:
	return _roll(id, "own") < sim.rules.box_look.own_share


## A number from 0 to 1 for box `id` and `what`, the same every frame.
static func _roll(id: int, what: String) -> float:
	return (hash([id, what]) & 0xFFFF) / 65536.0


## Puts box `id` at `placed` into `buffers`: its body by length (buffers[teu]),
## its stripe ("stripe%d") and a dangerous-goods placard ("placard%d") if it has them.
func _put_box(buffers: Dictionary, placed: Transform3D, id: int) -> void:
	var box: Dictionary = sim.boxes[id]
	_put(buffers[box.teu], placed, _box_colour(box.line, id, box.reefer))
	var stripe := _box_stripe(box.line, id, box.reefer)
	if stripe.a > 0.0:
		_put(buffers["stripe%d" % box.teu], placed, stripe)
	if box.dg:
		_put(buffers["placard%d" % box.teu], placed, Color.html(sim.rules.box_look.placard))


## The overlays drawn with a box, by its length's mesh: a band along both
## sides high up, and a placard on each side by one end. Keyed as _put_box writes them.
func _box_overlays() -> Dictionary:
	var found := {}
	for teu: int in BOX_LENGTH:
		var aabb: AABB = _stack_meshes[teu].get_aabb()
		var c := aabb.get_center()
		found["stripe%d" % teu] = _merged([[Vector3(aabb.size.x * 0.96, aabb.size.y * 0.16, aabb.size.z * 1.03), c + Vector3(0, aabb.size.y * 0.22, 0), Color.WHITE]])
		found["placard%d" % teu] = _merged([[Vector3(aabb.size.x * (0.07 if teu == 2 else 0.12), aabb.size.y * 0.24, aabb.size.z * 1.05), c + Vector3(aabb.size.x * 0.3, -aabb.size.y * 0.05, 0), Color.WHITE]])
	return found


func _draw_ships() -> void:
	_forget_gone(_ships, sim.ships)
	for ship: PortSim.Ship in sim.ships:
		# Ships waiting out at sea, off the map, are only counted in the HUD.
		if ship.state == PortSim.Ship.State.ANCHORED and not ship.anchorage:
			continue
		var length: float = sim.rules.ship_classes[ship.kind].length / METRES_PER_UNIT
		if ship not in _ships:
			_ships[ship] = _ship_model(ship, length)
		var model: Node3D = _ships[ship]
		_sail(model, ship, lerpf(ship.prev_sail, ship.sail, alpha))
		var spec: Dictionary = sim.rules.ship_classes[ship.kind]
		# Imports still aboard, plus the exports loaded so far.
		var aboard: int = ship.boxes + spec.export_moves - ship.exports
		var deck: MultiMesh = (model.get_node("Deck") as MultiMeshInstance3D).multimesh
		if model.get_meta("aboard", -1) != aboard:
			model.set_meta("aboard", aboard)
			var slots := deck_slots(length, aboard, spec.outreach)
			deck.instance_count = maxi(deck.instance_count, slots.size())
			deck.visible_instance_count = slots.size()
			for i in slots.size():
				deck.set_instance_transform(i, Transform3D(_deck_box, slots[i]))
				deck.set_instance_color(i, _box_colour(ship.line, hash([ship.id, i]), false))


## Each kind of boat's length and beam, in metres.
const BOAT_METRES := {"tug": Vector2(30, 10), "pilot": Vector2(16, 5), "fireboat": Vector2(26, 8), "bunkers": Vector2(60, 12), "provisions": Vector2(30, 8), "waste": Vector2(30, 8)}
## Where the water's surface lies, in world units.
const WATERLINE := -0.3


## Each pilot station and tug depot as a jetty out from the shore with a
## harbour office at its root, and every pilot boat and tug: moored along
## its jetty when home, under way where the sim has it, and a tug with a
## ship at its seaward side, bow to the hull, pushing.
func _draw_marine() -> void:
	var bases := sim.pilot_stations.merged(sim.tug_depots).merged(sim.service_jetties)
	for id: int in _bases.keys():
		if id not in bases or _bases[id].get_meta("boats") != sim.boats.of(id).size():
			_bases[id].queue_free()
			_bases.erase(id)
	for id: int in bases:
		if id not in _bases:
			_bases[id] = _base_model(id, "pilot" if id in sim.pilot_stations else ("tug" if id in sim.tug_depots else "services"))
	for id: int in _boats.keys():
		if id not in sim.boats.list:
			_boats[id].queue_free()
			_boats.erase(id)
			_boat_seen.erase(id)
	if sim.clock.ticks != _boat_tick:
		_boat_tick = sim.clock.ticks
		for id: int in sim.boats.list:
			var at: Vector2 = sim.boats.list[id].at
			_boat_seen[id] = [_boat_seen[id][1] if id in _boat_seen else at, at]
	for id: int in sim.boats.list:
		var boat: Dictionary = sim.boats.list[id]
		if id not in _boats:
			_boats[id] = _boat_model(boat.kind)
		var model: Node3D = _boats[id]
		var moving := false
		if boat.job in ["home", "ashore"]:
			var moored := _moored(id, boat)
			model.position = Vector3(moored[0].x, 0.0, moored[0].y) * Grid.CELL / METRES_PER_UNIT
			model.rotation.y = atan2(moored[1].x, moored[1].y)
		elif boat.job == "with" and _tug_at_ship(model, id, boat):
			pass
		elif boat.job == "serve" and _alongside_ship(model, boat.ship, boat.kind):
			pass
		elif boat.job == "fight" and boat.ship in sim.fires.list and sim.fires.list[boat.ship].target[0] == "ship" and _alongside_ship(model, sim.fires.list[boat.ship].target[1], boat.kind):
			pass
		else:
			var seen: Array = _boat_seen[id]
			var at: Vector2 = seen[0].lerp(seen[1], alpha)
			model.position = Vector3(at.x, 0.0, at.y) * Grid.CELL / METRES_PER_UNIT
			var way: Vector2 = seen[1] - seen[0]
			moving = way.length() > 0.01
			if moving:
				model.rotation.y = atan2(way.x, way.y)
		model.get_node("Wake").visible = moving


## Fire engines (red, with a blue beacon) at their station or on the road,
## and each fire: flames that flicker and a column of smoke, on its block or
## its ship.
func _draw_fires() -> void:
	for id: int in _engines.keys():
		if id not in sim.fires.engines:
			_engines[id].queue_free()
			_engines.erase(id)
	for id: int in sim.fires.engines:
		var engine: Dictionary = sim.fires.engines[id]
		if id not in _engines:
			var model := MeshInstance3D.new()
			model.mesh = _merged([
				[Vector3(0.1, 0.1, 0.32), Vector3(0, 0.07, 0), Color(0.8, 0.1, 0.08)],
				[Vector3(0.102, 0.03, 0.08), Vector3(0, 0.1, 0.11), Color(0.15, 0.2, 0.26)],
				[Vector3(0.06, 0.02, 0.2), Vector3(0, 0.13, -0.04), Color(0.75, 0.75, 0.75)],
				[Vector3(0.04, 0.02, 0.03), Vector3(0, 0.13, 0.09), Color(0.2, 0.4, 1.0)],
			])
			add_child(model)
			_engines[id] = model
		var node: Node3D = _engines[id]
		node.position = Vector3(engine.at.x, 0.02, engine.at.y) * Grid.CELL / METRES_PER_UNIT
		if not engine.path.is_empty() and engine.path[0] != engine.at:
			var way: Vector2 = engine.path[0] - engine.at
			node.rotation.y = atan2(way.x, way.y)
	for id: int in _fires.keys():
		if id not in sim.fires.list:
			_fires[id].queue_free()
			_fires.erase(id)
	var flicker := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 90.0)
	for id: int in sim.fires.list:
		var fire: Dictionary = sim.fires.list[id]
		if id not in _fires:
			_fires[id] = _fire_model()
		var node: Node3D = _fires[id]
		var at := Vector3.ZERO
		if fire.target[0] == "block" and fire.target[1] in sim.areas.list:
			var area: Dictionary = sim.areas.list[fire.target[1]]
			var middle := sim.areas.point(fire.target[1], area.columns / 2.0, sim.areas.depth_of(area) / 2.0)
			at = Vector3(middle.x, 0.3, middle.y) * Grid.CELL / METRES_PER_UNIT
			at.y = 0.3
		else:
			for ship: PortSim.Ship in sim.ships:
				if ship.id == fire.target[1] and ship in _ships:
					at = _ships[ship].position + Vector3(0, SHIP_DECK + 0.3, 0)
		node.position = at
		node.get_node("Flames").scale = Vector3(1.0, flicker, 1.0)


## Flames (orange and yellow, unlit so they glow) and a smoke column above.
func _fire_model() -> Node3D:
	var node := Node3D.new()
	var flames := MeshInstance3D.new()
	flames.name = "Flames"
	flames.mesh = _merged([
		[Vector3(0.5, 0.35, 0.5), Vector3(0, 0.17, 0), Color(1.0, 0.35, 0.05)],
		[Vector3(0.3, 0.55, 0.3), Vector3(0.08, 0.27, -0.05), Color(1.0, 0.6, 0.1)],
		[Vector3(0.18, 0.7, 0.18), Vector3(-0.08, 0.35, 0.06), Color(1.0, 0.85, 0.3)],
	])
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flames.material_override = glow
	node.add_child(flames)
	for k: int in 4:
		var puff := _box(Vector3(0.5 + k * 0.2, 0.35, 0.5 + k * 0.2), Color(0.2, 0.2, 0.22, 0.5 - k * 0.1))
		puff.position = Vector3(0.1 * k, 0.8 + k * 0.45, -0.08 * k)
		node.add_child(puff)
	add_child(node)
	return node


## Each mechanic's van: a white van with an orange beacon, at its workshop
## or on the road to a repair, facing the way it drives.
func _draw_vans() -> void:
	for id: int in _vans.keys():
		if id not in sim.workshops.vans:
			_vans[id].queue_free()
			_vans.erase(id)
	for id: int in sim.workshops.vans:
		var van: Dictionary = sim.workshops.vans[id]
		if id not in _vans:
			var model := MeshInstance3D.new()
			model.mesh = _merged([
				[Vector3(0.09, 0.08, 0.2), Vector3(0, 0.06, 0), Color(0.95, 0.95, 0.93)],
				[Vector3(0.092, 0.03, 0.06), Vector3(0, 0.08, 0.07), Color(0.15, 0.2, 0.26)],
				[Vector3(0.03, 0.02, 0.03), Vector3(0, 0.11, 0.03), Color(1.0, 0.55, 0.1)],
			])
			add_child(model)
			_vans[id] = model
		var node: Node3D = _vans[id]
		node.position = Vector3(van.at.x, 0.02, van.at.y) * Grid.CELL / METRES_PER_UNIT
		if not van.path.is_empty() and van.path[0] != van.at:
			var way: Vector2 = van.path[0] - van.at
			node.rotation.y = atan2(way.x, way.y)


## Where base `id`'s jetty starts on the shore and the way it runs out to
## sea, in cells: from the land cell nearest the base, through the base.
func _jetty(id: int) -> Array[Vector2]:
	var cell := sim.marine_base_cell(id)
	var shore := Vector2(cell)
	var near := INF
	for dx: int in range(-PortSim.MARINE_BASE_SHORE, PortSim.MARINE_BASE_SHORE + 1):
		for dy: int in range(-PortSim.MARINE_BASE_SHORE, PortSim.MARINE_BASE_SHORE + 1):
			var land := cell + Vector2i(dx, dy)
			if sim.areas.coast.inside(land) and not sim.areas.is_water(land) and Vector2(dx, dy).length() < near:
				near = Vector2(dx, dy).length()
				shore = Vector2(land)
	var out := (Vector2(cell) - shore).normalized()
	return [shore + Vector2(0.5, 0.5) + out * 0.5, out]


## How long base `id`'s jetty is, in cells: out past the base, with room
## along it for its boats moored either side, bow to stern.
func _jetty_length(id: int) -> float:
	var start: Vector2 = _jetty(id)[0]
	var cell := sim.marine_base_cell(id)
	var boat := 0.0
	for b: int in sim.boats.of(id):
		boat = maxf(boat, BOAT_METRES[sim.boats.list[b].kind].x / Grid.CELL)
	return maxf(start.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) + 1.0, ceili(sim.boats.of(id).size() / 2.0) * (boat + 1.0) + 2.0)


## [where boat `id` lies moored at its jetty, the way its bow points], in
## cells: in turn either side of the jetty from its far end in, bows to sea.
func _moored(id: int, boat: Dictionary) -> Array[Vector2]:
	var jetty := _jetty(boat.base)
	var out: Vector2 = jetty[1]
	var slot := sim.boats.of(boat.base).find(id)
	var size: Vector2 = BOAT_METRES[boat.kind] / Grid.CELL
	var length := 0.0
	for b: int in sim.boats.of(boat.base):
		length = maxf(length, BOAT_METRES[sim.boats.list[b].kind].x / Grid.CELL)
	var beam := size.y
	var along := _jetty_length(boat.base) - 1.0 - length / 2.0 - (slot / 2) * (length + 1.0)
	var across := (0.5 + beam / 2.0 + 0.2) * (1.0 if slot % 2 == 0 else -1.0)
	return [jetty[0] + out * along + Vector2(-out.y, out.x) * across, out]


## Puts tug `id`, with its ship, at the ship's seaward side, bow to its
## hull, its ship's tugs spread along its length; false if its ship is not
## drawn (out at sea).
func _tug_at_ship(model: Node3D, id: int, boat: Dictionary) -> bool:
	var ship: PortSim.Ship = null
	for s: PortSim.Ship in sim.ships:
		if s.id == boat.ship:
			ship = s
	if ship == null or ship not in _ships or ship.apron == 0:
		return false
	var hull: Node3D = _ships[ship]
	var tugs := sim.boats.list.keys().filter(func(t: int) -> bool: return sim.boats.list[t].ship == ship.id and sim.boats.list[t].kind == "tug")
	var k := tugs.find(id)
	var spec: Dictionary = sim.rules.ship_classes[ship.kind]
	var length: float = spec.length / METRES_PER_UNIT
	var side2 := sim.areas.out_at(ship.apron, ship.from + (AreaFlow.ship_cells(sim, ship.kind) - 1) / 2.0)
	var side := Vector3(side2.x, 0.0, side2.y)
	var bow := hull.basis.z.normalized()
	var along := (float(k) / maxi(tugs.size() - 1, 1) - 0.5) * length / 2.0 if tugs.size() > 1 else 0.0
	var off := beam(spec.outreach) / 2.0 + BOAT_METRES.tug.x / METRES_PER_UNIT / 2.0
	model.position = Vector3(hull.position.x, 0.0, hull.position.z) + bow * along + side * off
	model.rotation.y = atan2(-side.x, -side.z)
	return true


## Puts a boat of `kind` at work alongside the ship with id `ship_id` (a
## service boat, or a fireboat at a ship on fire): lying parallel to
## the hull on its seaward side (the side away from the quay, or its
## starboard side at anchor), each service at its own place along the hull;
## false if its ship is not drawn.
func _alongside_ship(model: Node3D, ship_id: int, kind: String) -> bool:
	var ship: PortSim.Ship = null
	for s: PortSim.Ship in sim.ships:
		if s.id == ship_id:
			ship = s
	if ship == null or ship not in _ships:
		return false
	var hull: Node3D = _ships[ship]
	var bow := hull.basis.z.normalized()
	var side := hull.basis.x.normalized()
	if ship.apron != 0:
		var out := sim.areas.out_at(ship.apron, ship.from + (AreaFlow.ship_cells(sim, ship.kind) - 1) / 2.0)
		side = Vector3(out.x, 0.0, out.y)
	var spec: Dictionary = sim.rules.ship_classes[ship.kind]
	var length: float = spec.length / METRES_PER_UNIT
	var along: float = {"bunkers": -0.15, "provisions": 0.2, "waste": 0.35, "fireboat": 0.0}[kind] * length
	var off: float = beam(spec.outreach) / 2.0 + BOAT_METRES[kind].y / METRES_PER_UNIT / 2.0 + 0.02
	model.position = Vector3(hull.position.x, 0.0, hull.position.z) + bow * along + side * off
	model.rotation.y = atan2(bow.x, bow.z)
	return true


## A jetty on piles from the shore out to sea, and at its root on land a
## two-storey harbour office with a signal mast: a white roof trimmed red
## and pilot flags (white over red) for a pilot station (`kind` "pilot"),
## an orange roof for a tug depot ("tug"), a green roof trimmed white for a
## services jetty ("services").
func _base_model(id: int, kind: String) -> Node3D:
	var pilots := kind == "pilot"
	var jetty := _jetty(id)
	var length := _jetty_length(id) * Grid.CELL / METRES_PER_UNIT
	var unit := Grid.CELL / METRES_PER_UNIT
	var roof: Color = {"pilot": Color(0.96, 0.96, 0.94), "tug": Color(1.0, 0.55, 0.15), "services": Color(0.2, 0.55, 0.35)}[kind]
	var trim: Color = {"pilot": Color(0.8, 0.15, 0.12), "tug": Color(0.12, 0.12, 0.12), "services": Color(0.95, 0.95, 0.93)}[kind]
	var timber := Color(0.55, 0.42, 0.28)
	var walls := Color(0.86, 0.84, 0.78)
	var glass := Color(0.18, 0.24, 0.3)
	var parts: Array = [[Vector3(unit, 0.03, length), Vector3(0, 0.02, length / 2.0), timber]]
	for k: int in floori(length / 0.25) + 1:
		for x: float in [-unit / 2.0, unit / 2.0]:
			parts.append([Vector3(0.03, 0.34, 0.03), Vector3(x, -0.15, minf(k * 0.25, length)), timber.darkened(0.5)])
	# The office stands on land behind the jetty's root.
	var office := Vector3(0, 0, -0.3)
	parts.append_array([
		[Vector3(0.48, 0.18, 0.36), office + Vector3(0, 0.09, 0), walls],
		[Vector3(0.485, 0.04, 0.365), office + Vector3(0, 0.11, 0), glass],
		[Vector3(0.44, 0.16, 0.32), office + Vector3(0, 0.26, 0), walls],
		[Vector3(0.445, 0.04, 0.325), office + Vector3(0, 0.28, 0), glass],
		[Vector3(0.5, 0.03, 0.38), office + Vector3(0, 0.335, 0), trim],
		[Vector3(0.5, 0.04, 0.38), office + Vector3(0, 0.37, 0), roof],
		[Vector3(0.025, 0.6, 0.025), office + Vector3(0.15, 0.69, 0.1), Color.WHITE],
		[Vector3(0.26, 0.02, 0.02), office + Vector3(0.15, 0.9, 0.1), Color.WHITE],
	])
	for x: float in [0.04, 0.26]:
		parts.append([Vector3(0.005, 0.03, 0.06), office + Vector3(x, 0.865, 0.1), Color.WHITE if pilots else roof])
		parts.append([Vector3(0.005, 0.03, 0.06), office + Vector3(x, 0.835, 0.1), trim if pilots else roof])
	var model := MeshInstance3D.new()
	model.mesh = _merged(parts)
	model.position = Vector3(jetty[0].x, 0.0, jetty[0].y) * unit
	model.rotation.y = atan2(jetty[1].x, jetty[1].y)
	model.set_meta("boats", sim.boats.of(id).size())
	add_child(model)
	return model


## A boat of `kind`, bow along +Z, floating, with a wake astern shown while
## it moves: a tug (black hull, orange bulwark, white deckhouse and
## wheelhouse, orange funnel, heavy fendering), a pilot boat (slim navy hull
## with an orange PILOT stripe, white cabin and mast), a bunker barge (long
## dark red hull, fuel tanks on deck, wheelhouse aft), a supply boat (white
## with a blue hull and a deck crane), a waste boat (green, with skips) or a
## fireboat (red, white bridge, a water cannon on its mast).
func _boat_model(kind: String) -> Node3D:
	var unit := Grid.CELL / METRES_PER_UNIT
	var parts: Array
	var length: float = BOAT_METRES[kind].x / METRES_PER_UNIT
	var beam_u: float = BOAT_METRES[kind].y / METRES_PER_UNIT
	var white := Color(0.95, 0.95, 0.93)
	var glass := Color(0.15, 0.2, 0.26)
	if kind == "tug":
		var orange := Color(1.0, 0.5, 0.1)
		parts = [
			[Vector3(beam_u, 0.14, length), Vector3(0, 0.0, 0), Color(0.14, 0.12, 0.12)],
			[Vector3(beam_u + 0.04, 0.05, length + 0.03), Vector3(0, 0.03, 0), Color(0.05, 0.05, 0.05)],
			[Vector3(beam_u + 0.02, 0.06, length + 0.02), Vector3(0, 0.09, 0), orange],
			[Vector3(beam_u * 0.75, 0.14, length * 0.36), Vector3(0, 0.19, length * 0.1), white],
			[Vector3(beam_u * 0.65, 0.12, length * 0.2), Vector3(0, 0.32, length * 0.14), white],
			[Vector3(beam_u * 0.66, 0.04, length * 0.21), Vector3(0, 0.34, length * 0.14), Color(0.15, 0.2, 0.26)],
			[Vector3(0.1, 0.18, 0.1), Vector3(0, 0.31, -length * 0.1), orange],
			[Vector3(0.105, 0.04, 0.105), Vector3(0, 0.41, -length * 0.1), Color(0.08, 0.08, 0.08)],
			[Vector3(beam_u * 0.7, 0.02, length * 0.35), Vector3(0, 0.125, -length * 0.3), Color(0.45, 0.45, 0.45)],
		]
	elif kind == "bunkers":
		var red := Color(0.45, 0.1, 0.08)
		parts = [
			[Vector3(beam_u, 0.12, length), Vector3(0, 0.0, 0), red],
			[Vector3(beam_u + 0.01, 0.025, length + 0.01), Vector3(0, 0.07, 0), Color(0.1, 0.1, 0.1)],
			[Vector3(beam_u * 0.55, 0.12, length * 0.18), Vector3(0, 0.15, -length * 0.38), white],
			[Vector3(beam_u * 0.56, 0.035, length * 0.19), Vector3(0, 0.17, -length * 0.38), glass],
			[Vector3(0.05, 0.12, 0.05), Vector3(0, 0.25, -length * 0.44), Color(0.1, 0.1, 0.1)],
		]
		for k: int in 3:
			parts.append([Vector3(beam_u * 0.7, 0.07, length * 0.18), Vector3(0, 0.1, length * (0.3 - k * 0.22)), Color(0.75, 0.72, 0.68)])
	elif kind == "fireboat":
		parts = [
			[Vector3(beam_u, 0.13, length), Vector3(0, 0.0, 0), Color(0.75, 0.1, 0.08)],
			[Vector3(beam_u + 0.01, 0.03, length + 0.01), Vector3(0, 0.07, 0), Color(0.95, 0.95, 0.93)],
			[Vector3(beam_u * 0.7, 0.16, length * 0.35), Vector3(0, 0.17, length * 0.05), Color(0.95, 0.95, 0.93)],
			[Vector3(beam_u * 0.71, 0.04, length * 0.36), Vector3(0, 0.2, length * 0.05), glass],
			[Vector3(0.03, 0.14, 0.03), Vector3(0, 0.32, length * 0.05), Color(0.75, 0.1, 0.08)],
			[Vector3(0.025, 0.025, 0.12), Vector3(0, 0.4, length * 0.1), Color(0.6, 0.6, 0.6)],
		]
	elif kind == "provisions":
		parts = [
			[Vector3(beam_u, 0.12, length), Vector3(0, 0.0, 0), Color(0.12, 0.28, 0.55)],
			[Vector3(beam_u * 0.8, 0.14, length * 0.3), Vector3(0, 0.13, length * 0.25), white],
			[Vector3(beam_u * 0.81, 0.04, length * 0.31), Vector3(0, 0.16, length * 0.25), glass],
			[Vector3(beam_u * 0.85, 0.02, length * 0.5), Vector3(0, 0.07, -length * 0.2), Color(0.5, 0.5, 0.5)],
			[Vector3(0.025, 0.2, 0.025), Vector3(0, 0.17, -length * 0.05), Color(1.0, 0.75, 0.1)],
			[Vector3(0.02, 0.02, length * 0.35), Vector3(0, 0.26, -length * 0.2), Color(1.0, 0.75, 0.1)],
			[Vector3(0.06, 0.05, 0.08), Vector3(0, 0.1, -length * 0.3), Color(0.8, 0.3, 0.15)],
		]
	elif kind == "waste":
		var green := Color(0.15, 0.42, 0.22)
		parts = [
			[Vector3(beam_u, 0.12, length), Vector3(0, 0.0, 0), green],
			[Vector3(beam_u * 0.7, 0.14, length * 0.25), Vector3(0, 0.13, -length * 0.3), white],
			[Vector3(beam_u * 0.71, 0.04, length * 0.26), Vector3(0, 0.16, -length * 0.3), glass],
		]
		for k: int in 2:
			parts.append([Vector3(beam_u * 0.75, 0.08, length * 0.2), Vector3(0, 0.1, length * (0.25 - k * 0.24)), Color(0.85, 0.65, 0.1)])
	else:
		var navy := Color(0.08, 0.12, 0.25)
		parts = [
			[Vector3(beam_u, 0.1, length * 0.85), Vector3(0, 0.0, -length * 0.075), navy],
			[Vector3(beam_u * 0.6, 0.1, length * 0.15), Vector3(0, 0.0, length * 0.425), navy],
			[Vector3(beam_u + 0.01, 0.03, length * 0.7), Vector3(0, 0.03, -length * 0.05), Color(1.0, 0.45, 0.05)],
			[Vector3(beam_u * 0.8, 0.12, length * 0.4), Vector3(0, 0.11, length * 0.05), Color(0.95, 0.95, 0.93)],
			[Vector3(beam_u * 0.82, 0.035, length * 0.41), Vector3(0, 0.13, length * 0.05), Color(0.15, 0.2, 0.26)],
			[Vector3(0.015, 0.12, 0.015), Vector3(0, 0.23, length * 0.1), Color.WHITE],
			[Vector3(0.005, 0.025, 0.05), Vector3(0, 0.27, length * 0.1 - 0.03), Color.WHITE],
			[Vector3(0.005, 0.025, 0.05), Vector3(0, 0.245, length * 0.1 - 0.03), Color(0.8, 0.15, 0.12)],
		]
	var hull := MeshInstance3D.new()
	hull.mesh = _merged(parts)
	hull.position.y = WATERLINE + 0.04
	var wake := _box(Vector3(length * 0.35, 0.01, length * 1.4), Color(1, 1, 1, 0.45))
	wake.name = "Wake"
	wake.position = Vector3(0, WATERLINE + 0.01, -length * 1.2)
	var node := Node3D.new()
	node.add_child(hull)
	node.add_child(wake)
	add_child(node)
	return node


## Puts `model` a fraction `sail` of the way along `ship`'s course, its bow
## as Marine.bow points it: along the lanes, round to lie along the quay off
## its berth, then pushed in sideways.
func _sail(model: Node3D, ship: PortSim.Ship, sail: float) -> void:
	if ship.anchorage:
		_to_anchor(model, ship, sail)
		return
	var frame := _berth_frame(ship)
	var at: Vector2 = frame[0]
	if ship.path.size() >= 2:
		var points: Array[Vector2] = []
		for point: Vector2 in ship.path.slice(0, -1):
			points.append(point * Grid.CELL / METRES_PER_UNIT)
		points.append(frame[0])
		at = Marine.point_along(points, sail)
	model.position = Vector3(at.x, 0.0, at.y)
	var bow := Marine.bow(sim, ship, sail)
	model.rotation.y = atan2(bow.x, bow.y)


## A ship sailing in to its spot at anchor, or lying there, bow along its
## last leg in.
func _to_anchor(model: Node3D, ship: PortSim.Ship, sail: float) -> void:
	var points: Array[Vector2] = []
	for point: Vector2 in ship.path:
		points.append(point * Grid.CELL / METRES_PER_UNIT)
	var at := Marine.point_along(points, sail if ship.state == PortSim.Ship.State.ANCHORING else 1.0)
	model.position = Vector3(at.x, 0.0, at.y)
	var way := points[-1] - points[-2]
	model.rotation.y = atan2(way.x, way.y)


## A ship's beam in world units: its rows of boxes across, plus hull each side.
static func beam(rows: int) -> float:
	return rows * DECK_ROW + 2.0 * HULL_MARGIN / METRES_PER_UNIT


## Where `ship` lies alongside in world units, and the way out to sea:
## [middle, side]. Its hull lies QUAY_GAP out from the quay's edge.
func _berth_frame(ship: PortSim.Ship) -> Array[Vector2]:
	var span := AreaFlow.ship_cells(sim, ship.kind)
	var middle := ship.from + (span - 1) / 2.0
	var side := sim.areas.out_at(ship.apron, middle)
	var depth := sim.areas.depth_of(sim.areas.list[ship.apron])
	var edge := sim.areas.point(ship.apron, middle, depth - 1) * Grid.CELL
	# `edge` is the outer row's middle, half a cell inside the quay's edge.
	var out := (Grid.CELL / 2.0 + QUAY_GAP) / METRES_PER_UNIT + beam(sim.rules.ship_classes[ship.kind].outreach) / 2.0
	return [edge / METRES_PER_UNIT + side * out, side]


## Where the first `count` boxes on deck of a ship `length` world units long
## and `rows` boxes across sit, in the ship's frame (length along +Z, bow at
## +Z): 40 ft bays from behind the bridge to short of the bow, filled tier
## by tier. Boxes past the top tier are not drawn.
static func deck_slots(length: float, count: int, rows: int) -> Array[Vector3]:
	var bays := floori((length - SHIP_BOW - SHIP_STERN) / DECK_BAY)
	var per_tier := bays * rows
	var tier_height := REAL_BOX_HEIGHT / METRES_PER_UNIT
	var slots: Array[Vector3] = []
	for i in mini(count, per_tier * DECK_TIERS):
		var bay := (i % per_tier) / rows
		var row := i % rows
		slots.append(Vector3((row - (rows - 1) / 2.0) * DECK_ROW, SHIP_DECK + (i / per_tier + 0.5) * tier_height, -length / 2.0 + SHIP_STERN + (bay + 0.5) * DECK_BAY))
	return slots


## A hull in the line's livery with a pointed bow, a bridge at the stern
## and a deck of boxes, turned so its length lies along the quay.
func _ship_model(ship: PortSim.Ship, length: float) -> Node3D:
	var model := Node3D.new()
	var half := length / 2.0 - 0.2
	var side_x := beam(sim.rules.ship_classes[ship.kind].outreach) / 2.0
	var outline := PackedVector2Array([Vector2(-side_x, -half), Vector2(side_x, -half), Vector2(side_x, half - 1.0), Vector2(0, half), Vector2(-side_x, half - 1.0)])
	var hull := MeshInstance3D.new()
	# Darker than the line's boxes, so a deck of its own boxes reads against it.
	hull.mesh = _prism(outline, 0.6, Color.html(sim.rules.lines[ship.line].livery).darkened(0.55))
	hull.position.y = SHIP_DECK - 0.3
	model.add_child(hull)
	var bridge := _box(Vector3(side_x * 2.0, 0.9, 0.5), Color(0.92, 0.92, 0.9))
	bridge.position = Vector3(0, SHIP_DECK + 0.45, -half + 0.35)
	model.add_child(bridge)
	var deck := MultiMeshInstance3D.new()
	deck.name = "Deck"
	deck.multimesh = MultiMesh.new()
	deck.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	deck.multimesh.use_colors = true
	deck.multimesh.mesh = _stack_meshes[2]
	model.add_child(deck)
	# At night: deck lights along the ship, a white masthead light on the
	# bridge, red to port and green to starboard at the bow.
	var lights := MeshInstance3D.new()
	var parts: Array = [[Vector3(0.05, 0.05, 0.05), Vector3(0, SHIP_DECK + 1.0, -half + 0.35), Color.WHITE]]
	for z: float in range(int(-half) + 1, int(half - 1.0)):
		for x: float in [-side_x + 0.05, side_x - 0.05]:
			parts.append([Vector3(0.035, 0.035, 0.035), Vector3(x, SHIP_DECK + 0.05, z), Color(1.0, 0.95, 0.8)])
	parts.append([Vector3(0.06, 0.06, 0.06), Vector3(-side_x, SHIP_DECK + 0.1, half - 1.0), Color(1.0, 0.1, 0.1)])
	parts.append([Vector3(0.06, 0.06, 0.06), Vector3(side_x, SHIP_DECK + 0.1, half - 1.0), Color(0.1, 1.0, 0.2)])
	lights.mesh = _merged(parts)
	lights.mesh.surface_set_material(0, _bright)
	lights.visible = _dark > 0.05
	model.add_child(lights)
	_ship_lights.append(lights)
	add_child(model)
	return model


## Where an STS crane's trolley and spreader are `phase` (0 to 1) into a
## move, as [along: 0 over the quay to 1 over the ship, drop: 0 raised to 1
## lowered]. It lowers and lifts at one end, runs along, then lowers and
## lifts at the other; discharging starts over the ship, loading over the quay.
static func crane_pose(phase: float, discharging: bool) -> Array[float]:
	var start := 1.0 if discharging else 0.0
	var along := start
	var drop := 0.0
	if phase < 0.3:
		drop = 1.0 - absf(phase - 0.15) / 0.15
	elif phase < 0.7:
		along = lerpf(start, 1.0 - start, smoothstep(0.3, 0.7, phase))
	else:
		along = 1.0 - start
		drop = 1.0 - absf(phase - 0.85) / 0.15
	return [along, drop]


## An STS crane: legs on the quay, a girder out over the water, and a
## trolley and spreader that follow the crane's move.
func _draw_cranes() -> void:
	_forget_gone(_cranes, sim.cranes)
	for crane: PortSim.Crane in sim.cranes:
		var move_minutes := AreaFlow.move_minutes_of(sim, crane)
		if crane not in _cranes:
			_cranes[crane] = _crane_model(crane)
		var model: Node3D = _cranes[crane]
		var ship := _ship_over(crane)
		var phase := crane.timer / move_minutes if crane.tractor != 0 else 0.0
		var pose := crane_pose(phase, ship != null and ship.boxes > 0)
		var trolley: Node3D = model.get_node("Trolley")
		trolley.position.z = lerpf(CRANE_BACK, model.get_meta("reach"), pose[0])
		var spreader: Node3D = trolley.get_node("Spreader")
		spreader.position.y = -lerpf(0.2, CRANE_HEIGHT - 0.6, pose[1])
		var cable: Node3D = trolley.get_node("Cable")
		cable.scale.y = -spreader.position.y
		cable.position.y = spreader.position.y / 2.0


## The crane's model, turned so +Z points out to the water.
func _crane_model(crane: PortSim.Crane) -> Node3D:
	var model := Node3D.new()
	# Between its apron's rails, facing the water.
	var depth := sim.areas.depth_of(sim.areas.list[crane.apron])
	var at := sim.areas.point(crane.apron, crane.along, (depth - 1) / 2.0) * Grid.CELL / METRES_PER_UNIT
	model.position = Vector3(at.x, AREA_TOP / METRES_PER_UNIT, at.y)
	var out := sim.areas.out_at(crane.apron, crane.along)
	model.rotation.y = atan2(out.x, out.y)
	var spec: Dictionary = sim.rules.sts_cranes[crane.kind]
	# Out from the water-side rail: the quay's edge, the gap and its outreach in rows, plus hull.
	var reach: float = CRANE_GAUGE / 2.0 + (Grid.CELL * depth / 2.0 - Grid.CELL / 2.0 + QUAY_GAP) / METRES_PER_UNIT + beam(spec.outreach)
	model.set_meta("reach", reach)
	var legs: float = (spec.width / 2.0 - 2.0) / METRES_PER_UNIT
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _sts_mesh(legs, reach)
	model.add_child(body)
	var trolley := _box(Vector3(0.24, 0.1, 0.32), Color(0.25, 0.25, 0.27))
	trolley.name = "Trolley"
	trolley.position.y = CRANE_HEIGHT - 0.11
	model.add_child(trolley)
	# The driver's cab, hung under the trolley's waterside end.
	var cab := _box(Vector3(0.12, 0.1, 0.12), Color(0.92, 0.92, 0.9))
	cab.position = Vector3(0.08, -0.1, 0.12)
	trolley.add_child(cab)
	var cable := _box(Vector3(0.02, 1.0, 0.02), Color(0.15, 0.15, 0.15))
	cable.name = "Cable"
	trolley.add_child(cable)
	var spreader := _box(Vector3(REAL_BOX_WIDTH, 1.0, REAL_BOX_LENGTH[2]) / METRES_PER_UNIT, Color(0.95, 0.75, 0.1))
	spreader.name = "Spreader"
	trolley.add_child(spreader)
	add_child(model)
	return model


## An STS crane's frame as one mesh, so it draws in one call: four legs on
## wheeled bogies along the rails, a sill beam low and a portal beam high
## between each pair, the twin boom from the backreach out over the water,
## the A-frame above the landside legs with the machinery house behind it.
## `legs` is half the leg spacing along the rails, `reach` how far the boom
## runs out, in world units; +Z points out to the water.
func _sts_mesh(legs: float, reach: float) -> Mesh:
	var thick := 0.07
	var water := CRANE_GAUGE / 2.0
	var land := -CRANE_GAUGE / 2.0
	var white := Color(0.92, 0.92, 0.9)
	var grey := Color(0.25, 0.25, 0.27)
	var parts := []
	for x: float in [-legs, legs]:
		for z: float in [land, water]:
			parts.append([Vector3(thick, CRANE_HEIGHT, thick), Vector3(x, CRANE_HEIGHT / 2.0, z), CRANE_COLOR])
			parts.append([Vector3(0.22, 0.05, 0.08), Vector3(x, 0.025, z), grey])
		# Along each side, low and high, joining the landside and waterside legs.
		for y: float in [CRANE_HEIGHT * 0.35, CRANE_HEIGHT * 0.95]:
			parts.append([Vector3(thick * 0.8, thick * 0.8, CRANE_GAUGE), Vector3(x, y, 0.0), CRANE_COLOR])
	for z: float in [land, water]:
		# Across the rails between each pair of legs: the sill low, the portal high.
		parts.append([Vector3(legs * 2.0, thick, thick), Vector3(0.0, CRANE_HEIGHT * 0.35, z), CRANE_COLOR])
		parts.append([Vector3(legs * 2.0, thick * 1.4, thick * 1.4), Vector3(0.0, CRANE_HEIGHT * 0.95, z), CRANE_COLOR])
	# The twin boom, backreach to tip, with a walkway between its girders.
	var length := reach - CRANE_BACK + 0.2
	for x: float in [-0.11, 0.11]:
		parts.append([Vector3(0.06, 0.12, length), Vector3(x, CRANE_HEIGHT, (reach + CRANE_BACK) / 2.0), CRANE_COLOR])
	parts.append([Vector3(0.16, 0.02, length), Vector3(0.0, CRANE_HEIGHT - 0.05, (reach + CRANE_BACK) / 2.0), grey])
	# The A-frame over the landside legs, and its top beam.
	var apex := 0.7
	for x: float in [-0.11, 0.11]:
		parts.append([Vector3(0.05, apex, 0.05), Vector3(x, CRANE_HEIGHT + apex / 2.0, land), CRANE_COLOR])
	parts.append([Vector3(0.3, 0.05, 0.05), Vector3(0.0, CRANE_HEIGHT + apex, land), CRANE_COLOR])
	# The machinery house on the backreach.
	parts.append([Vector3(0.34, 0.22, 0.36), Vector3(0.0, CRANE_HEIGHT + 0.17, CRANE_BACK + 0.22), white])
	return _merged(parts)


## The ship along crane `crane`'s stretch of quay, or null.
func _ship_over(crane: PortSim.Crane) -> PortSim.Ship:
	for ship: PortSim.Ship in sim.ships:
		if crane in AreaFlow.cranes_for(sim, ship):
			return ship
	return null


## Every vehicle as four MultiMeshes (cabs tinted by kind, chassis, and
## boxes by length in their line's livery), each filled with one buffer
## write a frame, so draw calls stay the same however many vehicles there are.
## Every train along its path: the locomotive at its head, then a flat
## wagon a bay long for each wagon, with its box if it carries one.
func _draw_trains() -> void:
	if _train_parts.is_empty():
		var bay := AreaLayout.BAY * Grid.CELL / METRES_PER_UNIT
		_train_parts = {
			"loco": _vehicle_part(_merged([[Vector3(bay * 0.95, 0.18, 0.13), Vector3(0, 0.12, 0), Color(0.55, 0.12, 0.1)]])),
			"wagon": _vehicle_part(_merged([[Vector3(bay * 0.95, 0.04, 0.12), Vector3(0, 0.05, 0), Color(0.25, 0.25, 0.27)]])),
			1: _vehicle_part(_stack_meshes[1]),
			2: _vehicle_part(_stack_meshes[2]),
		}
		for key: String in _overlays:
			_train_parts[key] = _vehicle_part(_overlays[key])
	var buffers := {}
	for part: Variant in _train_parts:
		buffers[part] = PackedFloat32Array()
	for train: Train in sim.trains:
		var head := lerpf(train.prev_t, train.t, alpha)
		for k in train.wagons.size() + 1:
			var at := head - AreaLayout.BAY * (k + 0.5)
			if at < 0.0:
				break
			var pose := train.pose(at)
			var turned := Basis(Vector3.UP, atan2(-pose[1].y, pose[1].x))
			var centre := pose[0] * Grid.CELL / METRES_PER_UNIT
			var origin := Vector3(centre.x, ROAD_TOP / METRES_PER_UNIT + 0.02, centre.y)
			_put(buffers["loco" if k == 0 else "wagon"], Transform3D(turned, origin), Color.WHITE)
			var box: int = train.wagons[k - 1] if k > 0 else 0
			if box != 0 and box in sim.boxes:
				var teu: int = sim.boxes[box].teu
				var lifted := origin + Vector3(0, 0.07 + REAL_BOX_HEIGHT / METRES_PER_UNIT / 2.0, 0)
				_put_box(buffers, Transform3D(turned.scaled_local(_real_box[teu]), lifted), box)
	for part: Variant in buffers:
		var multimesh: MultiMesh = _train_parts[part].multimesh
		multimesh.instance_count = buffers[part].size() / 16
		if not buffers[part].is_empty():
			multimesh.buffer = buffers[part]


func _draw_vehicles(dt: float) -> void:
	if _vehicle_parts.is_empty():
		_vehicle_parts = {
			"cab": _vehicle_part(_merged([[Vector3(0.24, 0.2, 0.16), Vector3.ZERO, Color.WHITE]])),
			"chassis": _vehicle_part(_merged([[Vector3(0.22, 0.04, 0.52), Vector3.ZERO, Color(0.2, 0.2, 0.22)]])),
			"straddle": _vehicle_part(_merged(_straddle_frame(Color.WHITE))),
			"agv": _vehicle_part(_merged(_agv_parts())),
			"agv_bar": _vehicle_part(_merged([[Vector3(0.004, 0.014, 0.22), Vector3.ZERO, Color.WHITE]])),
			"agv_beacon": _vehicle_part(_merged([[Vector3(0.02, 0.025, 0.02), Vector3(0.08, 0.1, 0.27), Color.WHITE]])),
			# A charger: a grey post with a cable arm, and its light on top, tinted by what it is doing.
			"charger": _vehicle_part(_merged([[Vector3(0.025, 0.11, 0.025), Vector3(0, 0.055, 0), Color(0.55, 0.58, 0.6)], [Vector3(0.012, 0.012, 0.06), Vector3(0, 0.09, 0.03), Color(0.12, 0.12, 0.12)], [Vector3(0.035, 0.025, 0.035), Vector3(0, 0.12, 0), Color(0.3, 0.32, 0.34)]])),
			"charger_light": _vehicle_part(_merged([[Vector3(0.02, 0.012, 0.02), Vector3(0, 0.138, 0), Color.WHITE]])),
			"rack": _vehicle_part(_merged(_rack_parts())),
			1: _vehicle_part(_stack_meshes[1]),
			2: _vehicle_part(_stack_meshes[2]),
		}
		for key: String in _overlays:
			_vehicle_parts[key] = _vehicle_part(_overlays[key])
	var buffers := {}
	for part: Variant in _vehicle_parts:
		buffers[part] = PackedFloat32Array()
	var headings := {}
	var beams := PackedFloat32Array()
	for vehicle: Vehicle in sim.vehicles:
		# Off the map, going round the highway's interchange: not drawn.
		var car: Dictionary = sim.traffic.cars.get(vehicle.id, {})
		if car and sim.network.pieces[car.route[car.i]].offmap:
			continue
		var pose := Drive.pose(sim, vehicle, alpha)
		var heading: Vector2 = pose[1].normalized() if pose[1] != Vector2.ZERO else _headings.get(vehicle.id, Vector2.DOWN)
		# Eased toward the way its path runs, so a sharp jog into a slot reads as a turn.
		if vehicle.id in _headings:
			heading = (_headings[vehicle.id] as Vector2).slerp(heading, minf(1.0, dt * HEADING_EASE))
		headings[vehicle.id] = heading
		# Each lane is its own cell, so a vehicle drives down the middle of it.
		var at: Vector2 = (pose[0] + Vector2(0.5, 0.5)) * Grid.CELL / METRES_PER_UNIT
		var basis := Basis(Vector3.UP, atan2(heading.x, heading.y)).scaled_local(AREA_VEHICLE_SCALE)
		var placed := Transform3D(basis, Vector3(at.x, 0.04, at.y))
		if _dark > 0.05:
			# Its headlights' beam on the road ahead, its tail lights' glow behind.
			var ahead := Vector3(heading.x, 0.0, heading.y)
			var turned := Basis(Vector3.UP, atan2(heading.x, heading.y))
			_put(beams, Transform3D(turned.scaled(Vector3(0.16, 1.0, 0.5)), placed.origin + ahead * 0.5 + Vector3(0, 0.006, 0)), Color(1.0, 0.95, 0.8))
			_put(beams, Transform3D(turned.scaled(Vector3(0.12, 1.0, 0.1)), placed.origin - ahead * 0.32 + Vector3(0, 0.006, 0)), Color(1.0, 0.1, 0.05))
		# A straddle carrier is a tall frame with the box slung inside it.
		var carried := placed * _vehicle_box
		if vehicle.straddle:
			_put(buffers.straddle, placed, STRADDLE_RED)
			carried = placed * Transform3D(Basis(), Vector3(0, 0.12, 0)) * _vehicle_box
		elif vehicle.kind == "agv":
			_put(buffers.agv, placed, Color.WHITE)
			_put_agv_bar(buffers, placed, vehicle.charge)
			# Its amber beacon flashes while it stands on a safety stop.
			var flash := vehicle.id in sim.traffic.held and fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.3
			_put(buffers.agv_beacon, placed, Color(1.0, 0.75, 0.2) * 1.6 if flash else Color(0.75, 0.4, 0.05))
			carried = placed * Transform3D(_vehicle_box.basis, Vector3(0, 0.215, 0))
		else:
			_put(buffers.cab, placed * Transform3D(Basis(), Vector3(0, 0.14, 0.24)), Color(0.95, 0.75, 0.1) if vehicle.kind == "tractor" else Color(0.9, 0.9, 0.86))
			_put(buffers.chassis, placed * Transform3D(Basis(), Vector3(0, 0.06, -0.06)), Color.WHITE)
		if vehicle.loaded:
			_put_box(buffers, carried, vehicle.box)
	_headings = headings
	_beams.multimesh.instance_count = beams.size() / 16
	if not beams.is_empty():
		_beams.multimesh.buffer = beams
	_park_agvs(buffers)
	_draw_racks(buffers)
	for part: Variant in _vehicle_parts:
		var multimesh: MultiMesh = _vehicle_parts[part].multimesh
		var buffer: PackedFloat32Array = buffers[part]
		var count := buffer.size() / 16
		if multimesh.instance_count < count:
			multimesh.instance_count = nearest_po2(count)
		buffer.resize(multimesh.instance_count * 16)
		multimesh.buffer = buffer
		multimesh.visible_instance_count = count


## A rack (x along its slot, before any scale): two grey steel beams on four
## yellow posts, as long as a 40 ft box and a little more, AGV-height.
static func _rack_parts() -> Array:
	var length := REAL_BOX_LENGTH[2] * 1.05 / METRES_PER_UNIT
	var width := REAL_BOX_WIDTH * 1.1 / METRES_PER_UNIT
	var top := RACK_HEIGHT / METRES_PER_UNIT
	var parts: Array = []
	for z: float in [-width / 2.0, width / 2.0]:
		parts.append([Vector3(length, 0.012, 0.012), Vector3(0, top, z), Color(0.5, 0.52, 0.55)])
		for x: float in [-length / 2.0, length / 2.0]:
			parts.append([Vector3(0.014, top, 0.014), Vector3(x, top / 2.0, z), Color(1.0, 0.78, 0.1)])
	return parts


## Each racked transfer block's racks, one at each AGV slot at its front,
## and the box on each that holds one.
func _draw_racks(buffers: Dictionary) -> void:
	for block: int in sim.racks:
		if block not in sim.areas.list:
			continue
		var layout := sim.areas.layout(block)
		for slot: int in layout.slots.size():
			var cells: Array = layout.slots[slot]
			var middle := (sim.areas.centre(cells[0]) + sim.areas.centre(cells[-1])) / 2.0
			var along := sim.areas.heading(block, cells[cells.size() / 2].y)
			var turned := Basis(Vector3.UP, atan2(-along.y, along.x))
			var at := middle * Grid.CELL / METRES_PER_UNIT
			var origin := Vector3(at.x, AREA_TOP / METRES_PER_UNIT, at.y)
			_put(buffers.rack, Transform3D(turned, origin), Color.WHITE)
			var rack: Dictionary = sim.racks[block].get(slot, {})
			if rack.get("state", "") in ["in", "ready"] and rack.box in sim.boxes:
				var teu: int = sim.boxes[rack.box].teu
				var lifted := origin + Vector3(0, (RACK_HEIGHT + REAL_BOX_HEIGHT / 2.0) / METRES_PER_UNIT + 0.006, 0)
				_put_box(buffers, Transform3D(turned.scaled_local(_real_box[teu]), lifted), rack.box)


## The middle of an AGV depot's parking lane `r` across, front to back, in a
## depot building `size` deep.
static func _lane_z(size: Vector2, r: int) -> float:
	return -size.y * 0.45 + (r + 0.5) * size.y * 0.9 / AGV_LANES


## An AGV's battery bar on both its sides at `placed`, green full to red flat.
func _put_agv_bar(buffers: Dictionary, placed: Transform3D, charge: float) -> void:
	for side: float in [-1.0, 1.0]:
		_put(buffers.agv_bar, placed * Transform3D(Basis(), Vector3(side * 0.113, 0.05, 0)), AGV_CHARGE_FLAT.lerp(AGV_CHARGE_FULL, charge))


## Each AGV depot's AGVs at home, parked lengthwise under its canopy as they
## drive in, two to each of its AGV_LANES lanes, as many as fit; and its
## chargers, a post at the outer end of each of the first places, lit green
## while it charges the AGV there and amber while it waits.
func _park_agvs(buffers: Dictionary) -> void:
	for id: int in _area_buildings:
		if id not in sim.areas.list or sim.areas.kind_of(sim.areas.list[id]) != "agv_depot":
			continue
		var model: Node3D = _area_buildings[id]
		var home: Array = sim.agv_home.get(id, [])
		var chargers: int = sim.areas.list[id].settings.chargers
		# Those AreaFlow._batteries charges this tick: home longest, not yet full.
		var plugged := {}
		for i in home.size():
			if plugged.size() < chargers and home[i] < 1.0:
				plugged[i] = true
		var size := _building_size(id)
		var shed := size.x * 0.75
		for k: int in maxi(mini(home.size(), AGV_LANES * 2), chargers):
			var end := -1.0 if k % 2 == 0 else 1.0
			var x := -size.x * 0.125 + end * shed / 4.0
			# Lengthwise: an AGV's length (its z) along the depot's road (x).
			var place := model.transform * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, 0.0, _lane_z(size, k / 2)))
			if k < home.size() and k < AGV_LANES * 2:
				var placed := place * Transform3D(Basis.IDENTITY.scaled(AREA_VEHICLE_SCALE), Vector3.ZERO)
				_put(buffers.agv, placed, Color.WHITE)
				_put(buffers.agv_beacon, placed, Color(0.75, 0.4, 0.05))
				_put_agv_bar(buffers, placed, home[k])
			if k < chargers:
				# At the AGV's outer end, beside its lane.
				var post := place * Transform3D(Basis.IDENTITY, Vector3(0.07, 0.0, end * 0.31))
				_put(buffers.charger, post, Color.WHITE)
				var charging: bool = k in plugged
				_put(buffers.charger_light, post, Color(0.2, 1.0, 0.35) if charging else Color(1.0, 0.65, 0.1))


## Appends `placed` and `color` to `buffer` in MultiMesh layout: the
## transform's 3x4 matrix row by row, then the colour.
static func _put(buffer: PackedFloat32Array, placed: Transform3D, color: Color) -> void:
	var b := placed.basis
	var o := placed.origin
	buffer.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, color.r, color.g, color.b, color.a])


func _vehicle_part(mesh: Mesh) -> MultiMeshInstance3D:
	var part := MultiMeshInstance3D.new()
	part.multimesh = MultiMesh.new()
	part.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	part.multimesh.use_colors = true
	part.multimesh.mesh = mesh
	add_child(part)
	return part


## Every box stacked in a yard area at real size: each stack position is a
## 12 m bay of one row, tiers from the ground up, a pair of 20 ft boxes end
## to end in a tier, each in its line's livery.
func _draw_area_stacks() -> void:
	for area: int in _area_stacks.keys():
		if area not in sim.area_stacks or area not in sim.areas.list:
			for part: Node in _area_stacks[area].parts.values():
				part.queue_free()
			_area_stacks.erase(area)
	for area: int in sim.area_stacks:
		if area not in sim.areas.list:
			continue
		var stacks: AreaStacks = sim.area_stacks[area]
		if area not in _area_stacks:
			var parts := {}
			for teu: int in BOX_LENGTH:
				for far: int in [0, 1]:
					var part := _vehicle_part(_plain_box[teu] if far else _stack_meshes[teu])
					if far:
						part.visibility_range_begin = STACK_DETAIL_RANGE
					else:
						part.visibility_range_end = STACK_DETAIL_RANGE
					parts[Vector2i(teu, far)] = part
			# Stripes and placards only up close, as the detailed boxes.
			for key: String in _overlays:
				parts[key] = _vehicle_part(_overlays[key])
				parts[key].visibility_range_end = STACK_DETAIL_RANGE
			_area_stacks[area] = {"drawn": [], "parts": parts}
		var drawn: Dictionary = _area_stacks[area]
		if drawn.drawn == [stacks.version, sim.areas.version]:
			continue
		drawn.drawn = [stacks.version, sim.areas.version]
		var buffers := _stack_buffers(area, stacks)
		for key: Variant in drawn.parts:
			var multimesh: MultiMesh = drawn.parts[key].multimesh
			var buffer: PackedFloat32Array = buffers[key.x] if key is Vector2i else buffers[key]
			multimesh.instance_count = buffer.size() / 16
			if not buffer.is_empty():
				multimesh.buffer = buffer


## The instance buffers, by TEU, of yard area `area`'s stacked boxes.
func _stack_buffers(area: int, stacks: AreaStacks) -> Dictionary:
	var buffers := {1: PackedFloat32Array(), 2: PackedFloat32Array()}
	for key: String in _overlays:
		buffers[key] = PackedFloat32Array()
	var layout := sim.areas.layout(area)
	for position in stacks.stacks.size():
		var spot: Vector3i = layout.stacks[position].cells[1]
		var centre := sim.areas.centre(spot) * Grid.CELL
		# A transfer block's boxes lie away from its road, along its stacks.
		var along := sim.areas.out_at(area, spot.y) if sim.areas.kind_of(sim.areas.list[area]) == "transfer_block" else sim.areas.heading(area, spot.y)
		var turned := Basis(Vector3.UP, atan2(-along.y, along.x))
		for tier: int in stacks.stacks[position].size():
			var ids: Array = stacks.stacks[position][tier]
			for i in ids.size():
				var teu: int = sim.boxes[ids[i]].teu
				var shift := 0.0 if teu == 2 else (-0.5 if i == 0 else 0.5) * (REAL_BOX_LENGTH[1] + 0.05)
				var at := centre + along.normalized() * shift
				var origin := Vector3(at.x, AREA_TOP + (tier + 0.5) * REAL_BOX_HEIGHT, at.y) / METRES_PER_UNIT
				_put_box(buffers, Transform3D(turned.scaled_local(_real_box[teu]), origin), ids[i])
	return buffers


## Every yard machine on an area as its own node, with the box on its spreader
## while it lifts, carries and sets one down: an RTG over the stack rows, a
## reach stacker in the truck lane, sliding between bays as it travels.
## shortcut: a node per machine, fine at the few dozen one terminal has; MultiMesh them if ports grow past ~200.
func _draw_area_machines() -> void:
	for id: int in _area_machines.keys():
		if id not in sim.machines.list:
			_area_machines[id].queue_free()
			_area_machines.erase(id)
	var depth: int = sim.rules.area_types.yard_block.depth
	for id: int in sim.machines.list:
		var machine: Dictionary = sim.machines.list[id]
		if machine.area not in sim.areas.list:
			continue
		if id not in _area_machines:
			var node := MeshInstance3D.new()
			# A transfer block's ASCs are built as wide as the block, legs and all.
			node.mesh = _asc_mesh(sim.areas.list[machine.area].columns) if machine.gear == "asc" else _machine_meshes[machine.gear]
			var box := MeshInstance3D.new()
			box.name = "Box"
			box.mesh = _stack_meshes[2]
			box.material_override = StandardMaterial3D.new()
			node.add_child(box)
			# A gantry's spreader, the yellow frame that grabs a box, always on show.
			var spreader := MeshInstance3D.new()
			spreader.name = "Spreader"
			spreader.mesh = _merged([[Vector3(0.12, 0.025, 0.55), Vector3.ZERO, Color(1.0, 0.75, 0.1)], [Vector3(0.01, 0.12, 0.01), Vector3(0, 0.07, 0), Color(0.15, 0.15, 0.15)]])
			spreader.visible = machine.gear in ["rtg", "rmg", "asc"]
			node.add_child(spreader)
			add_child(node)
			_area_machines[id] = node
		var model: MeshInstance3D = _area_machines[id]
		# An RTG spans the stack rows; an RMG spans them and the siding behind.
		var area: Dictionary = sim.areas.list[machine.area]
		var travel: float = sim.machines.position(id) * AreaLayout.BAY + (AreaLayout.BAY - 1) / 2.0
		# A transfer block's ASCs span its columns and run away from the road,
		# between its ends; other gear runs along the road.
		var across := sim.areas.kind_of(area) == "transfer_block"
		var row: float = 2.0 + travel if across else {"rtg": (2 + depth - 1) / 2.0, "rmg": (2 + depth) / 2.0}.get(machine.gear, 1.0)
		var k: float = area.columns / 2.0 if across else travel
		var at := sim.areas.point(machine.area, k, row) * Grid.CELL / METRES_PER_UNIT
		var out := (sim.areas.point(machine.area, k, 1.0) - sim.areas.point(machine.area, k, 0.0)).normalized()
		model.position = Vector3(at.x, AREA_TOP / METRES_PER_UNIT, at.y)
		model.rotation.y = atan2(-out.y, out.x) + (PI / 2.0 if across else 0.0)
		var gantry: bool = machine.gear in ["rtg", "rmg", "asc"]
		var tall: float = REAL_RTG_HEIGHT / METRES_PER_UNIT / _machine_heights[machine.gear] if gantry else 1.0
		var wide: float = 1.0 if across else ((depth - 1.0) / (depth - 2.0) if machine.gear == "rmg" else 1.0)
		model.scale = Vector3(wide, tall, 1.0)
		var job: Dictionary = machine.job
		var box: MeshInstance3D = model.get_node("Box")
		box.visible = not job.is_empty() and (job.phases[0].kind == "lift" or job.get("carrying", false))
		var lift := lerpf(0.05, _machine_heights[machine.gear] * 0.85, sim.machines.spreader(id))
		var spreader: MeshInstance3D = model.get_node("Spreader")
		# The spreader rides on the box's top as it lifts, sets down and travels.
		spreader.scale = Vector3(1.0 / wide, 1.0 / tall, 1.0)
		spreader.position = Vector3(0, lift + REAL_BOX_HEIGHT / METRES_PER_UNIT / tall * 0.55, 0)
		if box.visible:
			# Counter the machine's height scale so the box keeps its real size.
			box.scale = _real_box[2] / Vector3(wide, tall, 1.0)
			box.position = Vector3(0, lift, 0)
			box.rotation.y = PI / 2
			var carried := _carried_box(id)
			(box.material_override as StandardMaterial3D).albedo_color = _box_colour(sim.boxes[carried].line, carried, sim.boxes[carried].reefer) if carried in sim.boxes else PLAIN_BOX


## The box machine `id` is working, or 0: its vehicle's, rack's or train's.
func _carried_box(id: int) -> int:
	var job: Dictionary = sim.machine_jobs.get(id, {})
	if job.has("box"):
		return job.box
	if job.has("vehicle"):
		var vehicle: Vehicle = sim._by_id.get(job.vehicle)
		return vehicle.box if vehicle else 0
	return 0


## A straddle carrier's frame in `colour`: four legs and the beams joining
## them on top, tall enough to pass over a box, standing on its origin.
static func _straddle_frame(colour: Color) -> Array:
	var parts := []
	for x: float in [-0.14, 0.14]:
		for z: float in [-0.22, 0.22]:
			parts.append([Vector3(0.04, 0.46, 0.04), Vector3(x, 0.23, z), colour])
		parts.append([Vector3(0.04, 0.05, 0.5), Vector3(x, 0.46, 0), colour])
	for z: float in [-0.22, 0.22]:
		parts.append([Vector3(0.32, 0.05, 0.04), Vector3(0, 0.46, z), colour])
	return parts


## One mesh per kind of yard gear, standing on its origin.
## An ASC as wide as a transfer block `columns` cells across, a cell over:
## its legs at the block's sides, its girders over the whole width.
func _asc_mesh(columns: int) -> Mesh:
	if columns not in _asc_meshes:
		_asc_meshes[columns] = _merged(_gantry_parts("asc", (columns + 1) * Grid.CELL / METRES_PER_UNIT / 2.0))
	return _asc_meshes[columns]


func _machine_mesh(gear: String) -> Mesh:
	if gear == "straddle":
		return _merged(_straddle_frame(STRADDLE_RED))
	if gear not in ["rtg", "rmg", "asc"]:
		return _merged([
			[Vector3(0.26, 0.2, 0.4), Vector3(0, 0.12, 0), Color(0.85, 0.35, 0.15)],
			[Vector3(0.06, 0.06, 0.4), Vector3(0, 0.36, -0.1), Color(0.2, 0.2, 0.22)],
		])
	return _merged(_gantry_parts(gear, 0.56))


## A gantry crane of `gear`, its legs `half` either side of its middle.
## Drawn scaled to REAL_RTG_HEIGHT; this only sets its proportions.
func _gantry_parts(gear: String, half: float) -> Array:
	var height: float = 0.3 + sim.rules.yard_gear[gear].tiers * BOX_HEIGHT
	var parts := []
	for x: float in [-half, half]:
		for z: float in [-0.3, 0.3]:
			parts.append([Vector3(0.08, height, 0.08), Vector3(x, height / 2.0, z), Color(0.95, 0.95, 0.92)])
		parts.append([Vector3(0.14, 0.1, 0.72), Vector3(x, 0.05, 0), Color(0.2, 0.2, 0.22)])
	# RTGs in yellow, RMGs in blue, ASCs in teal (the AGV livery), so each yard reads apart.
	var colour: Color = {"rtg": Color(0.95, 0.75, 0.1), "rmg": Color(0.15, 0.45, 0.8), "asc": Color(0.05, 0.6, 0.62)}[gear]
	for z: float in [-0.3, 0.3]:
		parts.append([Vector3(half * 2.0 + 0.12, 0.1, 0.1), Vector3(0, height, z), colour])
		# A sill beam low across, between each pair of legs.
		parts.append([Vector3(half * 2.0, 0.06, 0.06), Vector3(0, height * 0.3, z), colour])
	for x: float in [-half, half]:
		# The side beams joining each side's legs at the top.
		parts.append([Vector3(0.08, 0.08, 0.6), Vector3(x, height - 0.02, 0), colour])
	# The trolley on the girders, its spreader hanging below, and the driver's cab.
	parts.append([Vector3(0.2, 0.08, 0.66), Vector3(0.1, height + 0.08, 0), Color(0.3, 0.3, 0.32)])
	parts.append([Vector3(0.12, 0.04, 0.5), Vector3(0.1, height - 0.35, 0), Color(0.95, 0.75, 0.1)])
	parts.append([Vector3(0.02, 0.4, 0.02), Vector3(0.1, height - 0.15, 0), Color(0.15, 0.15, 0.15)])
	if gear != "asc":
		parts.append([Vector3(0.14, 0.12, 0.12), Vector3(-half + 0.14, height - 0.1, -0.3), Color(0.92, 0.92, 0.9)])
	else:
		# Driverless: no cab, an electrical house on the girders and warning lights.
		parts.append([Vector3(0.22, 0.12, 0.3), Vector3(-half + 0.16, height + 0.1, 0), Color(0.92, 0.94, 0.95)])
		for z: float in [-0.3, 0.3]:
			parts.append([Vector3(0.04, 0.04, 0.04), Vector3(half, height + 0.07, z), Color(1.0, 0.55, 0.05)])
	return parts


## Frees the nodes of things the sim no longer has.
func _forget_gone(drawn: Dictionary, live: Array) -> void:
	for thing: Variant in drawn.keys():
		if thing not in live:
			drawn[thing].queue_free()
			drawn.erase(thing)


## `outline` (x, z) raised into a solid `height` thick, centred on y = 0.
func _prism(outline: PackedVector2Array, height: float, color: Color) -> Mesh:
	var top := height / 2.0
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)  # Flat: each face lit on its own, not blended with the walls.
	var triangles := Geometry2D.triangulate_polygon(outline)
	for i in range(0, triangles.size(), 3):
		for j: int in [0, 1, 2]:
			var p := outline[triangles[i + j]]
			tool.add_vertex(Vector3(p.x, top, p.y))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		for p: Vector3 in [Vector3(a.x, top, a.y), Vector3(b.x, -top, b.y), Vector3(b.x, top, b.y), Vector3(a.x, top, a.y), Vector3(a.x, -top, a.y), Vector3(b.x, -top, b.y)]:
			tool.add_vertex(p)
	tool.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	tool.set_material(material)
	return tool.commit()


## The `teu` container model from assets/, painted by per-instance colour.
func _container_mesh(teu: int) -> Mesh:
	var scene: Node = load("res://assets/container_%dft.glb" % (teu * 20)).instantiate()
	var mesh: ArrayMesh = (scene.get_node("Body") as MeshInstance3D).mesh.duplicate()
	scene.free()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.7
	mesh.surface_set_material(0, material)
	return mesh


## One mesh of boxes, each [size, centre, colour], lit by vertex colour.
func _merged(boxes: Array) -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in boxes:
		var box := BoxMesh.new()
		box.size = part[0]
		var arrays := box.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in indices:
			tool.set_color(part[2])
			tool.set_normal(normals[index])
			tool.add_vertex(vertices[index] + part[1])
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	tool.set_material(material)
	return tool.commit()


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _box_mesh(size, color)
	return node


func _box_mesh(size: Vector3, color: Color) -> BoxMesh:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	return mesh


## The town's bypass, in grid cells: off the highway west of the town,
## swinging south round it, back onto the highway east of it.
static func _bypass(port: PortSim) -> RoadCurve:
	var entry := Vector2(port.site_entry_point())
	var middle := Town.centre(port)
	return RoadCurve.new(entry + Vector2(8, 0), Vector2(middle.x, entry.y + 120), Vector2(middle.x * 2.0 - entry.x - 8, entry.y))


## The town's size in metres: half its width and depth, and the grid its
## houses stand on, every STREET_EVERY-th line of which is a street.
const TOWN_HALF := Vector2(220, 170)
const HOUSE_GRID := 16.0
const STREET_EVERY := Vector2i(4, 3)
## The town square, north of the high street (the highway), relative to the
## town's middle in metres: a rectangle from its first corner to its second.
const SQUARE := Rect2(-56, -44, 112, 36)
## How far from the middle along the high street its houses are shops.
const HIGH_STREET := Vector2(120, 40)


## Where the town's houses stand, nearest its middle first, in metres: on a
## 16 m grid between its streets, jittered, clear of the highway and the
## bypass. z is which look a house takes; odd ones face the other way.
static func town_spots(port: PortSim) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var middle := Town.centre(port) * Grid.CELL
	var road_y := float(port.site_entry_point().y * Grid.CELL)
	var edge := float(port.rules.site.width) + 24.0
	var bypass := _bypass(port)
	var curve: Array[Vector2] = []
	for i in 41:
		curve.append(bypass.point(i / 40.0) * Grid.CELL)
	var found: Array[Vector3] = []
	var near := {}
	for gx in range(-14, 15):
		for gy in range(-11, 12):
			if posmod(gx, STREET_EVERY.x) == 0 or posmod(gy, STREET_EVERY.y) == 0:
				continue
			var spot := middle + Vector2(gx, gy) * HOUSE_GRID + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
			var ellipse := pow((spot.x - middle.x) / TOWN_HALF.x, 2.0) + pow((spot.y - middle.y) / TOWN_HALF.y, 2.0)
			if ellipse > 1.0 or SQUARE.has_point(spot - middle) or spot.x < edge or absf(spot.y - road_y) < 16.0 or curve.any(func(p: Vector2) -> bool: return p.distance_to(spot) < 22.0):
				continue
			near[spot] = ellipse + rng.randf() * 0.15
			found.append(Vector3(spot.x, spot.y, rng.randi() % 6))
	found.sort_custom(func(a: Vector3, b: Vector3) -> bool: return near[Vector2(a.x, a.y)] < near[Vector2(b.x, b.y)])
	return found


## Draws the town: as many houses as it has grown to, protest boards out
## when it's sour, flags when it's warm.
func _draw_town() -> void:
	var rules: Dictionary = sim.rules.town
	var count: int = rules.houses + roundi(Town.jobs(sim) * rules.houses_per_job)
	var mood: String = "sour" if sim.town.mood < rules.sour_below else "warm" if sim.town.mood > rules.warm_above else ""
	if [count, mood, sim.town.bypass] == _town_drawn:
		return
	_town_drawn = [count, mood, sim.town.bypass]
	var walls := [Color(0.72, 0.4, 0.3), Color(0.9, 0.86, 0.76), Color(0.95, 0.95, 0.92), Color(0.66, 0.6, 0.5), Color(0.8, 0.7, 0.55)]
	var roofs := [Color(0.5, 0.2, 0.15), Color(0.3, 0.32, 0.36), Color(0.42, 0.3, 0.22)]
	var parts: Array = []
	var lit: Array = []
	var spots := town_spots(sim)
	var drawn := spots.slice(0, count)
	# Streets along the grid's street lines, as far as the houses reach.
	var middle := Town.centre(sim) * Grid.CELL
	var reach := Vector2.ZERO
	for spot: Vector3 in drawn:
		reach = reach.max((Vector2(spot.x, spot.y) - middle).abs() + Vector2(10, 10))
	for gx in range(-14, 15, 1):
		if posmod(gx, STREET_EVERY.x) == 0 and absf(gx * HOUSE_GRID) < reach.x:
			parts.append([Vector3(0.26, 0.01, reach.y * 2.0 / METRES_PER_UNIT), _world(middle + Vector2(gx * HOUSE_GRID, 0), 0.1), Color(0.3, 0.3, 0.3)])
	for gy in range(-11, 12, 1):
		if posmod(gy, STREET_EVERY.y) == 0 and absf(gy * HOUSE_GRID) < reach.y:
			parts.append([Vector3(reach.x * 2.0 / METRES_PER_UNIT, 0.01, 0.26), _world(middle + Vector2(0, gy * HOUSE_GRID), 0.1), Color(0.3, 0.3, 0.3)])
	parts.append_array(_town_centre(middle))
	for i in drawn.size():
		var spot: Vector3 = spots[i]
		var look := int(spot.z)
		var at := _world(Vector2(spot.x, spot.y), 0.0)
		var off := Vector2(spot.x, spot.y) - middle
		if absf(off.x) < HIGH_STREET.x and absf(off.y) < HIGH_STREET.y:
			_shop(parts, lit, at, i, signf(-off.y))
			continue
		var size := Vector2(0.4, 0.3) if look % 2 == 0 else Vector2(0.3, 0.4)
		var h := 0.22 if look < 4 else 0.34  # some houses have two storeys
		var roof: Color = roofs[look % roofs.size()]
		parts.append_array([
			[Vector3(size.x, h, size.y), at + Vector3(0, h / 2.0, 0), walls[(i * 7 + look) % walls.size()]],
			[Vector3(size.x + 0.03, 0.05, size.y + 0.03), at + Vector3(0, h + 0.025, 0), roof],
			[Vector3(size.x * 0.75 if look % 2 == 0 else size.x + 0.03, 0.05, size.y + 0.03 if look % 2 == 0 else size.y * 0.75), at + Vector3(0, h + 0.075, 0), roof],
			[Vector3(size.x * 0.4 if look % 2 == 0 else size.x + 0.03, 0.04, size.y + 0.03 if look % 2 == 0 else size.y * 0.4), at + Vector3(0, h + 0.12, 0), roof],
		])
		if i % 3 == 0:
			parts.append([Vector3(0.04, 0.12, 0.04), at + Vector3(size.x * 0.3, h + 0.1, 0), Color(0.45, 0.3, 0.25)])
		# Windows on the long sides, dark by day; lit ones sit just proud of them.
		for side: float in [-1.0, 1.0]:
			for k: float in [-0.25, 0.25]:
				for floor_y: float in ([0.12] if h < 0.3 else [0.1, 0.24]):
					var pane := at + (Vector3(size.x * k, floor_y, side * (size.y / 2.0 + 0.003)) if look % 2 == 0 else Vector3(side * (size.x / 2.0 + 0.003), floor_y, size.y * k))
					var shape := Vector3(0.06, 0.06, 0.004) if look % 2 == 0 else Vector3(0.004, 0.06, 0.06)
					parts.append([shape, pane, Color(0.2, 0.24, 0.3)])
					if (i + int(k * 4.0) + int(side)) % 3 != 0:  # not every room is lit
						lit.append([shape + Vector3(0.002, 0, 0.002), pane, Color(1.0, 0.82, 0.5)])
		if mood == "sour" and i % 4 == 0:
			var front := at + (Vector3(0, 0, size.y / 2.0 + 0.12) if look % 2 == 0 else Vector3(size.x / 2.0 + 0.12, 0, 0))
			parts.append_array([
				[Vector3(0.015, 0.16, 0.015), front + Vector3(-0.08, 0.08, 0), Color(0.4, 0.3, 0.2)],
				[Vector3(0.015, 0.16, 0.015), front + Vector3(0.08, 0.08, 0), Color(0.4, 0.3, 0.2)],
				[Vector3(0.22, 0.09, 0.01), front + Vector3(0, 0.14, 0), Color(0.95, 0.95, 0.9)],
				[Vector3(0.16, 0.025, 0.012), front + Vector3(0, 0.15, 0), Color(0.85, 0.1, 0.08)],
			])
		elif mood == "warm" and i % 5 == 0:
			parts.append_array([
				[Vector3(0.012, 0.3, 0.012), at + Vector3(-size.x / 2.0 - 0.06, 0.15, 0), Color(0.9, 0.9, 0.9)],
				[Vector3(0.012, 0.07, 0.1), at + Vector3(-size.x / 2.0 - 0.06, 0.26, 0.05), [Color(0.1, 0.55, 0.3), Color(0.95, 0.75, 0.1), Color(0.2, 0.4, 0.8)][i % 3]],
			])
	_town.mesh = _merged(parts) if not parts.is_empty() else null
	var windows: Mesh = _merged(lit) if not lit.is_empty() else null
	if windows:
		windows.surface_set_material(0, _bright)
	_town_windows.mesh = windows


## The square and its church, the town's middle at `middle` (metres).
static func _town_centre(middle: Vector2) -> Array:
	var square := _world(middle + SQUARE.get_center(), 0.0)
	var stone := Color(0.5, 0.47, 0.42)
	var church := square + Vector3(0, 0, -SQUARE.size.y / 2.0 / METRES_PER_UNIT + 0.35)
	var wall := Color(0.62, 0.58, 0.5)
	var slate := Color(0.28, 0.3, 0.34)
	return [
		[Vector3(SQUARE.size.x, 0.6, SQUARE.size.y) / METRES_PER_UNIT, square + Vector3(0, 0.012, 0), stone],
		# Benches and a fountain in the square.
		[Vector3(0.22, 0.03, 0.22), square + Vector3(0, 0.03, 0.15), Color(0.6, 0.6, 0.62)],
		[Vector3(0.12, 0.05, 0.12), square + Vector3(0, 0.05, 0.15), Color(0.35, 0.55, 0.75)],
		# The church: a nave with a pitched roof in steps, a tower and its spire.
		[Vector3(0.9, 0.36, 0.42), church + Vector3(0, 0.18, 0), wall],
		[Vector3(0.92, 0.06, 0.44), church + Vector3(0, 0.39, 0), slate],
		[Vector3(0.92, 0.06, 0.28), church + Vector3(0, 0.45, 0), slate],
		[Vector3(0.92, 0.05, 0.12), church + Vector3(0, 0.505, 0), slate],
		[Vector3(0.24, 0.8, 0.24), church + Vector3(-0.5, 0.4, 0), wall],
		[Vector3(0.18, 0.2, 0.18), church + Vector3(-0.5, 0.9, 0), slate],
		[Vector3(0.11, 0.2, 0.11), church + Vector3(-0.5, 1.1, 0), slate],
		[Vector3(0.05, 0.22, 0.05), church + Vector3(-0.5, 1.31, 0), slate],
		[Vector3(0.1, 0.1, 0.01), church + Vector3(-0.5, 0.65, 0.125), Color(0.9, 0.85, 0.6)],
		[Vector3(0.1, 0.16, 0.01), church + Vector3(0, 0.12, 0.215), Color(0.3, 0.2, 0.12)],
	]


## A shop on the high street at `at`: three storeys, a flat roof, and an
## awning over its window on the side facing the street (`face` +1 south, -1 north).
func _shop(parts: Array, lit: Array, at: Vector3, i: int, face: float) -> void:
	var fronts := [Color(0.85, 0.8, 0.7), Color(0.7, 0.45, 0.35), Color(0.92, 0.92, 0.88), Color(0.55, 0.62, 0.66)]
	var awnings := [Color(0.75, 0.15, 0.12), Color(0.12, 0.45, 0.3), Color(0.15, 0.3, 0.6), Color(0.9, 0.7, 0.15)]
	var size := Vector2(0.48, 0.36)
	var h := 0.42 + (i % 3) * 0.06
	var front := face * (size.y / 2.0 + 0.004)
	parts.append_array([
		[Vector3(size.x, h, size.y), at + Vector3(0, h / 2.0, 0), fronts[i % fronts.size()]],
		[Vector3(size.x + 0.02, 0.03, size.y + 0.02), at + Vector3(0, h + 0.015, 0), Color(0.35, 0.35, 0.36)],
		[Vector3(size.x * 0.8, 0.08, 0.006), at + Vector3(0, 0.07, front), Color(0.2, 0.24, 0.3)],
		[Vector3(size.x * 0.9, 0.02, 0.1), at + Vector3(0, 0.13, front + face * 0.05), awnings[i % awnings.size()]],
	])
	lit.append([Vector3(size.x * 0.8, 0.08, 0.008), at + Vector3(0, 0.07, front + face * 0.002), Color(1.0, 0.9, 0.65)])
	for floor_y: float in [0.22, 0.33]:
		for k: float in [-0.3, 0.0, 0.3]:
			var pane := at + Vector3(size.x * k, floor_y, front)
			parts.append([Vector3(0.06, 0.06, 0.004), pane, Color(0.2, 0.24, 0.3)])
			if (i + int(k * 10.0)) % 2 == 0:
				lit.append([Vector3(0.062, 0.062, 0.006), pane, Color(1.0, 0.82, 0.5)])
