class_name WorldView
extends Node3D
## Draws the sim as a small 3D model port. Reads PortSim every frame and
## never changes it.

## A deck box's height and its length by TEU (20 ft and 40 ft) on a ship
## model, in world units, stretched a little so boxes aboard read at a distance.
const BOX_HEIGHT := 0.3
const BOX_LENGTH := {1: 0.4, 2: 0.8}
## Boxes not yet booked on a line.
const PLAIN_BOX := Color(0.72, 0.72, 0.68)
## Metres in one world unit. Ships, cranes and the camera were made at this
## scale; roads, areas and what moves on them are drawn true to the 4 m grid in it.
const METRES_PER_UNIT := 25.0
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
	"parking": Color(0.38, 0.4, 0.42),
}
const AREA_TOP := 0.2
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
}
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
var _coast_filled := -1
## Each land tile a pixel, red where the port owns it.
var _owned := ImageTexture.new()
var _stack_meshes := {}  # TEU -> Mesh, tinted per instance
# shortcut: ships are one node each, fine at the handful a port works at once; MultiMesh them if berths grow past ~20.
var _ships := {}  # PortSim.Ship -> Node3D
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
## Every road on the 4 m grid as one mesh and its markings as another, redrawn when the roads change.
var _roads := MeshInstance3D.new()
var _road_marks := MeshInstance3D.new()
var _roads_drawn := []
## Every area's ground as one mesh, redrawn when the areas change.
var _areas := MeshInstance3D.new()
## The area and road versions the areas were drawn for: idle tints follow the roads.
var _areas_drawn := []
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
	for node: MeshInstance3D in [_roads, _road_marks, _road_preview, _snap_marks, _junction_signs, _areas, _area_preview, _ship_lanes]:
		add_child(node)
	_ship_lanes.material_override = StandardMaterial3D.new()
	_ship_lanes.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ship_lanes.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ship_lanes.material_override.vertex_color_use_as_albedo = true
	add_child(_info)
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


## Shows the road a drag would build from `from` to `to`, green if it can be
## built, else red; hidden when `from` is NONE.
func show_road_preview(from: Vector2i, to: Vector2i, type: String, ok: bool) -> void:
	_road_preview.visible = from != Grid.NONE and from != to
	if not _road_preview.visible:
		return
	var surface := _road_tool()
	if type == "track":
		_add_track(surface, null, from, to)
	else:
		_add_road(surface, null, from, to, sim.rules.road_types[type])
	_road_preview.mesh = surface.commit()
	_road_preview.material_override.albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


## Marks the head of each lane into a junction with signals or a sign, when
## they or the phases showing green have changed.
func _draw_junctions() -> void:
	var junctions := sim.lane_traffic.junctions
	var green := {}
	for point: Vector2i in junctions.signals:
		var at: Dictionary = junctions.signals[point]
		green[point] = junctions.phases(sim.lanes, point)[at.phase] if at.left > 0.0 else []
	var now := [sim.roads.version, green, junctions.signs.duplicate(true)]
	if now == _junctions_drawn:
		return
	_junctions_drawn = now
	var tool := _road_tool()
	var points := {}
	for point: Vector2i in junctions.signals.keys() + junctions.signs.keys():
		points[point] = true
	for point: Vector2i in points:
		for arm: Vector2i in sim.lanes.arms(point):
			var color := Color.TRANSPARENT
			if point in green:
				color = Color(0.2, 0.9, 0.3) if arm in green[point] else Color(0.95, 0.2, 0.15)
			elif junctions.signs.get(point, {}).has(arm):
				color = Color(0.95, 0.95, 0.95) if junctions.signs[point][arm] == "give_way" else Color(1.0, 0.55, 0.1)
			if color.a == 0.0:
				continue
			tool.set_color(color)
			# The approach lists each lane's last cells, nearest the box last.
			var cells := sim.lanes.approach(point, arm)
			for i in range(LaneGraph.APPROACH_CELLS - 1, cells.size(), LaneGraph.APPROACH_CELLS):
				var middle := (Vector2(cells[i]) + Vector2(0.5, 0.5)) * Grid.CELL
				_strip(tool, middle - Vector2(arm) * Grid.CELL * 0.3, middle + Vector2(arm) * Grid.CELL * 0.3, Grid.CELL * 0.35, ROAD_TOP + MARK_RISE * 3)
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
	if [sim.roads.version, sim.rails.version] != _roads_drawn:
		_draw_roads()
	if [sim.areas.version, sim.roads.version] != _areas_drawn:
		_draw_areas()
	if [sim.ship_lanes.version, sim.dredge_version, sim.anchorages.keys(), sim.pilot_stations.keys(), sim.tug_depots.keys(), sim.areas.breakwaters.keys()] != _ship_lanes_drawn:
		_draw_ship_lanes()
	_draw_junctions()
	if sim.areas.filled.size() != _coast_filled:
		_coast_filled = sim.areas.filled.size()
		_coast.set_image(coast_image(sim))
	if sim.land.size() != _drawn_land:
		_draw_land()
	_draw_ships()
	_draw_cranes()
	_draw_vehicles()
	_draw_trains()
	_draw_area_machines()
	_draw_area_stacks()


func _draw_roads() -> void:
	_roads_drawn = [sim.roads.version, sim.rails.version]
	var surface := _road_tool()
	var marks := _road_tool()
	# Markings stop where a junction's widest road begins.
	var trims := {}
	for id: int in sim.roads.segments:
		var road: Dictionary = sim.roads.segments[id]
		var lanes: int = sim.rules.road_types[road.type].forward + sim.rules.road_types[road.type].backward
		for node: int in [road.a, road.b]:
			if sim.roads.degree(node) >= 3:
				trims[node] = maxf(trims.get(node, 0.0), lanes * Grid.CELL / 2.0)
	for id: int in sim.roads.segments:
		var road: Dictionary = sim.roads.segments[id]
		_add_road(surface, marks, sim.roads.nodes[road.a], sim.roads.nodes[road.b], sim.rules.road_types[road.type], trims.get(road.a, 0.0), trims.get(road.b, 0.0))
	# The highway, from off the map to the site entry, so the player sees where to join it.
	var entry := sim.site_entry_point()
	var off_map := Vector2i(ceili(-SEA_START * METRES_PER_UNIT / Grid.CELL), 0)
	_add_road(surface, marks, entry + off_map, entry, sim.rules.road_types.terminal_2_2)
	# The main line the same way, to the rail entry.
	_add_track(surface, marks, sim.site_rail_entry() + off_map, sim.site_rail_entry())
	for id: int in sim.rails.segments:
		_add_track(surface, marks, sim.rails.nodes[sim.rails.segments[id].a], sim.rails.nodes[sim.rails.segments[id].b])
	_roads.mesh = surface.commit()
	_road_marks.mesh = marks.commit()


func _draw_areas() -> void:
	_areas_drawn = [sim.areas.version, sim.roads.version]
	var tool := _road_tool()
	for id: int in sim.areas.list:
		var colors := {}
		for cell in sim.areas.cells(id):
			colors[cell] = AREA_COLOR[sim.areas.kind_of(sim.areas.list[id])]
		var layout := sim.areas.layout(id)
		for cell: Vector2i in layout.get("buffer", []):
			colors[cell] = BUFFER_COLOR
		for lane: Array in layout.get("lanes", []):
			for cell: Vector2i in lane:
				colors[cell] = ASPHALT
		for rail: Array in layout.get("rails", []):
			for cell: Vector2i in rail:
				colors[cell] = RAIL_COLOR
		for cell: Vector2i in layout.get("edge", []):
			colors[cell] = EDGE_COLOR
		var area: Dictionary = sim.areas.list[id]
		for spot in AreaFlow.crane_spots(sim, id) if area.type == "quay_apron" else ([] as Array[int]):
			for d in sim.areas.depth_of(area):
				colors[area.start + (area.end - area.start).sign() * spot + area.out * d] = SPOT_COLOR
		for i: int in layout.get("slots", []).size():
			for cell: Vector2i in layout.slots[i]:
				colors[cell] = SLOT_COLORS[i % 2]
		var idle := sim.areas.idle_reason(id) != ""
		for cell: Vector2i in colors:
			tool.set_color(colors[cell].lerp(IDLE_TINT, 0.4) if idle else colors[cell])
			_cell_quad(tool, cell, AREA_TOP)
	_areas.mesh = tool.commit()


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
		var delays := sim.lane_traffic.delays()
		for cell: Vector2i in delays:
			shares[[cell]] = minf(delays[cell] / JAM_SECONDS, 1.0)
	else:
		for id: int in sim.areas.list:
			if sim.areas.kind_of(sim.areas.list[id]) == "yard_block":
				var fill := sim.block_fill(id)
				shares[sim.areas.cells(id)] = fill.x / float(maxi(fill.y, 1))
	return shares


## Each ship lane as a pale band over the water it covers, its line down the
## middle: white where dredged, else pale blue.
func _draw_ship_lanes() -> void:
	_ship_lanes_drawn = [sim.ship_lanes.version, sim.dredge_version, sim.anchorages.keys(), sim.pilot_stations.keys(), sim.tug_depots.keys(), sim.areas.breakwaters.keys()]
	_ship_lanes.visible = not (sim.ship_lanes.segments.is_empty() and sim.anchorages.is_empty() and sim.pilot_stations.is_empty() and sim.tug_depots.is_empty() and sim.areas.breakwaters.is_empty())
	if not _ship_lanes.visible:
		return
	var tool := _road_tool()
	# Breakwaters as grey rock.
	tool.set_color(Color(0.55, 0.55, 0.52, 1.0))
	for wall: Dictionary in sim.areas.breakwaters.values():
		for cell in Areas.breakwater_cells(wall.from, wall.to):
			_cell_quad(tool, cell, 0.05)
	# Pilot stations white and tug depots orange, five cells across.
	for bases: Array in [[sim.pilot_stations, Color(0.95, 0.95, 0.95, 0.9)], [sim.tug_depots, Color(1.0, 0.55, 0.15, 0.9)]]:
		tool.set_color(bases[1])
		for base: Dictionary in bases[0].values():
			for dx: int in range(-2, 3):
				for dy: int in range(-2, 3):
					_cell_quad(tool, base.cell + Vector2i(dx, dy), LANE_HEIGHT + 0.05)
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
		var a: Vector2i = sim.ship_lanes.nodes[lane.a]
		var b: Vector2i = sim.ship_lanes.nodes[lane.b]
		tool.set_color(Color(0.75, 0.9, 1.0, 0.12))
		for cell in sim.ship_lanes.footprint(a, b, lane.type):
			_cell_quad(tool, cell, LANE_HEIGHT)
		tool.set_color(Color(1, 1, 1, 0.55) if lane.dredged > 0.0 else Color(0.7, 0.85, 1.0, 0.45))
		for cell in RoadNet.line(a, b):
			_cell_quad(tool, cell, LANE_HEIGHT + 0.01)
	_ship_lanes.mesh = tool.commit()


## One 4 m cell as a flat square `height` metres up.
static func _cell_quad(tool: SurfaceTool, cell: Vector2i, height: float) -> void:
	var corner := Vector2(cell) * Grid.CELL
	var corners: Array[Vector2] = [corner, corner + Vector2(Grid.CELL, 0), corner + Vector2(Grid.CELL, Grid.CELL), corner + Vector2(0, Grid.CELL)]
	for i: int in [0, 1, 2, 0, 2, 3]:
		tool.add_vertex(_world(corners[i], height))


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
static func _add_road(surface: SurfaceTool, marks: Variant, a: Vector2i, b: Vector2i, road: Dictionary, trim_a := 0.0, trim_b := 0.0) -> void:
	var lanes: int = road.forward + road.backward
	var across := Vector2(RoadNet.right_of(b - a))
	var along := Vector2(b - a).normalized()
	var side := Vector2(-along.y, along.x)
	# A lane's width across the road: a cell, or less on 45° roads, where lanes step straight across.
	var lane_width := Grid.CELL * absf(across.dot(side))
	# The lanes lie evenly either side of the line between grid points a and b;
	# a 45° road's sit half a cell south of it (see RoadNet._row).
	var middle := Vector2(0, 0.5) if (b - a).x * (b - a).y != 0 else Vector2.ZERO
	var start: Vector2 = (Vector2(a) + middle) * Grid.CELL
	var end: Vector2 = (Vector2(b) + middle) * Grid.CELL
	var half := lanes * lane_width / 2.0
	surface.set_color(ASPHALT if road.lorries else TRACTOR_ONLY)
	var top := ROAD_TOP + (ASPHALT_RISE if road.lorries else 0.0)
	_strip(surface, start, end, half, top)
	# A junction's widest road covers its middle, so an end there gets no round cap to poke out past it.
	if trim_a == 0.0:
		_disc(surface, start, half, top)
	if trim_b == 0.0:
		_disc(surface, end, half, top)
	if marks == null:
		return
	marks.set_color(MARKING)
	var length: float = start.distance_to(end) - trim_a - trim_b
	if length <= 0.0:
		return
	# Where a road meets a junction: a zebra crossing at its edge, a stop line
	# behind it across the lanes driving in, then the lane markings, if they fit.
	var ends := int(trim_a > 0.0) + int(trim_b > 0.0)
	if ends > 0 and length >= JUNCTION_MARKS * ends + DASH:
		var middle_line: float = road.backward * lane_width - half
		if trim_a > 0.0:
			_junction_marks(marks, start + along * trim_a, along, side, half, -half, middle_line)
			trim_a += JUNCTION_MARKS
		if trim_b > 0.0:
			_junction_marks(marks, end - along * trim_b, -along, side, half, middle_line, half)
			trim_b += JUNCTION_MARKS
		length = start.distance_to(end) - trim_a - trim_b
	start += along * trim_a
	end = start + along * length
	for k in range(1, lanes):
		var offset := side * (k * lane_width - half)
		if k == road.backward:
			_strip(marks, start + offset, end + offset, MARK_WIDTH / 2.0, ROAD_TOP + MARK_RISE)
			continue
		var at := 0.0
		while at < length:
			var dash_end := minf(at + DASH, length)
			_strip(marks, start + offset + along * at, start + offset + along * dash_end, MARK_WIDTH / 2.0, ROAD_TOP + MARK_RISE)
			at += DASH + DASH_GAP


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
static func _add_track(surface: SurfaceTool, marks: Variant, a: Vector2i, b: Vector2i) -> void:
	var start := (Vector2(a) + Vector2(0.5, 0.5)) * Grid.CELL
	var end := (Vector2(b) + Vector2(0.5, 0.5)) * Grid.CELL
	surface.set_color(BALLAST)
	_strip(surface, start, end, Grid.CELL / 2.0, ROAD_TOP)
	if marks == null:
		return
	var side := (end - start).normalized().orthogonal()
	marks.set_color(STEEL)
	for gauge: float in [-RAIL_GAUGE, RAIL_GAUGE]:
		_strip(marks, start + side * gauge, end + side * gauge, RAIL_HALF, ROAD_TOP + MARK_RISE)


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
	var deepest: float = sim.rules.maps[sim.map].depth.max
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


## The 4 m grid cell at world point `at`.
static func grid_cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x * METRES_PER_UNIT / Grid.CELL), floori(at.z * METRES_PER_UNIT / Grid.CELL))


## Where along `path` a vehicle `at` cells in is drawn, as [position in grid
## cells, heading]. Through a cell where the path turns it follows a quarter
## circle between the middles of the cell's edges, so it never snaps.
static func path_pose(path: Array[Vector2i], at: float) -> Array[Vector2]:
	var i := clampi(int(at), 0, path.size() - 1)
	var f := at - i
	if path.size() < 2:
		return [Vector2(path[0]), Vector2.ZERO]
	if i >= path.size() - 1:
		return [Vector2(path[-1]), Vector2(path[-1] - path[-2])]
	var corner := i + 1 if f >= 0.5 else i
	if corner > 0 and corner < path.size() - 1:
		var d_in := Vector2(path[corner] - path[corner - 1])
		var d_out := Vector2(path[corner + 1] - path[corner])
		if d_in != d_out and d_in != -d_out:
			var u := (f - 0.5 if corner == i + 1 else f + 0.5) * PI / 2
			var centre := Vector2(path[corner]) + (d_out - d_in) * 0.5
			return [centre + 0.5 * (d_in * sin(u) - d_out * cos(u)), d_in * cos(u) + d_out * sin(u)]
	return [Vector2(path[i]).lerp(Vector2(path[i + 1]), f), Vector2(path[i + 1] - path[i])]


## `line`'s livery, a touch lighter or darker per box so a stack reads as
## separate boxes. shortcut: a shade stands in for M4's wear texture until the box model has UVs.
func _livery(line: String, id: int) -> Color:
	var color: Color = PLAIN_BOX if line == "" else Color.html(sim.rules.lines[line].livery)
	return color.darkened((id * 37 % 100) / 100.0 * 0.25)


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
				deck.set_instance_color(i, _livery(ship.line, i))


## Puts `model` a fraction `sail` of the way along `ship`'s course: along the
## lanes, then in to lie alongside, its bow along its way until the last leg,
## where it turns to lie along the quay.
func _sail(model: Node3D, ship: PortSim.Ship, sail: float) -> void:
	if ship.anchorage:
		_to_anchor(model, ship, sail)
		return
	var frame := _berth_frame(ship)
	var quay_heading := atan2(-frame[1].y, frame[1].x)
	if ship.path.size() < 2:
		model.position = Vector3(frame[0].x, 0.0, frame[0].y)
		model.rotation.y = quay_heading
		return
	var points: Array[Vector2] = []
	for point: Vector2 in ship.path.slice(0, -1):
		points.append(point * Grid.CELL / METRES_PER_UNIT)
	points.append(frame[0])
	var at := Marine.point_along(points, sail)
	model.position = Vector3(at.x, 0.0, at.y)
	# Which leg it is on, and how far along it.
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	var left := sail * length
	for i in range(1, points.size()):
		var leg := points[i - 1].distance_to(points[i])
		if left <= leg or i == points.size() - 1:
			var way := points[i] - points[i - 1]
			var heading := atan2(way.x, way.y) if ship.state == PortSim.Ship.State.ARRIVING else atan2(-way.x, -way.y)
			model.rotation.y = lerp_angle(heading, quay_heading, clampf(left / maxf(leg, 0.001), 0.0, 1.0)) if i == points.size() - 1 else heading
			return
		left -= leg


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
	var area: Dictionary = sim.areas.list[ship.apron]
	var along := Vector2((area.end - area.start).sign())
	var side := Vector2(area.out).normalized()
	var span := AreaFlow.ship_cells(sim, ship.kind)
	var depth := sim.areas.depth_of(area)
	var edge := (Vector2(area.start) + along * (ship.from + (span - 1) / 2.0) + Vector2(area.out) * (depth - 1) + Vector2(0.5, 0.5)) * Grid.CELL
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
	var area: Dictionary = sim.areas.list[crane.apron]
	var depth := sim.areas.depth_of(area)
	var at := (Vector2(area.start + (area.end - area.start).sign() * crane.along) + Vector2(area.out) * ((depth - 1) / 2.0) + Vector2(0.5, 0.5)) * Grid.CELL / METRES_PER_UNIT
	model.position = Vector3(at.x, AREA_TOP / METRES_PER_UNIT, at.y)
	model.rotation.y = atan2(area.out.x, area.out.y)
	var spec: Dictionary = sim.rules.sts_cranes[crane.kind]
	# Out from the water-side rail: the quay's edge, the gap and its outreach in rows, plus hull.
	var reach: float = CRANE_GAUGE / 2.0 + (Grid.CELL * depth / 2.0 - Grid.CELL / 2.0 + QUAY_GAP) / METRES_PER_UNIT + beam(spec.outreach)
	model.set_meta("reach", reach)
	var legs: float = (spec.width / 2.0 - 2.0) / METRES_PER_UNIT
	for x: float in [-legs, legs]:
		for z: float in [-CRANE_GAUGE / 2.0, CRANE_GAUGE / 2.0]:
			var leg := _box(Vector3(0.06, CRANE_HEIGHT, 0.06), CRANE_COLOR)
			leg.position = Vector3(x, CRANE_HEIGHT / 2.0, z)
			model.add_child(leg)
	var girder := _box(Vector3(0.24, 0.12, reach - CRANE_BACK + 0.2), CRANE_COLOR)
	girder.position = Vector3(0, CRANE_HEIGHT, (reach + CRANE_BACK) / 2.0)
	model.add_child(girder)
	var trolley := _box(Vector3(0.24, 0.1, 0.32), Color(0.25, 0.25, 0.27))
	trolley.name = "Trolley"
	trolley.position.y = CRANE_HEIGHT - 0.11
	model.add_child(trolley)
	var cable := _box(Vector3(0.02, 1.0, 0.02), Color(0.15, 0.15, 0.15))
	cable.name = "Cable"
	trolley.add_child(cable)
	var spreader := _box(Vector3(REAL_BOX_WIDTH, 1.0, REAL_BOX_LENGTH[2]) / METRES_PER_UNIT, Color(0.95, 0.75, 0.1))
	spreader.name = "Spreader"
	trolley.add_child(spreader)
	add_child(model)
	return model


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
	var buffers := {}
	for part: Variant in _train_parts:
		buffers[part] = PackedFloat32Array()
	for train: Train in sim.trains:
		var head := lerpf(train.prev_t, train.t, alpha)
		for k in train.wagons.size() + 1:
			var at := head - AreaLayout.BAY * (k + 0.5)
			if at < 0.0:
				break
			var pose := path_pose(train.path, at)
			var turned := Basis(Vector3.UP, atan2(-pose[1].y, pose[1].x))
			var centre := (pose[0] + Vector2(0.5, 0.5)) * Grid.CELL / METRES_PER_UNIT
			var origin := Vector3(centre.x, ROAD_TOP / METRES_PER_UNIT + 0.02, centre.y)
			_put(buffers["loco" if k == 0 else "wagon"], Transform3D(turned, origin), Color.WHITE)
			var box: int = train.wagons[k - 1] if k > 0 else 0
			if box != 0 and box in sim.boxes:
				var teu: int = sim.boxes[box].teu
				var lifted := origin + Vector3(0, 0.07 + REAL_BOX_HEIGHT / METRES_PER_UNIT / 2.0, 0)
				_put(buffers[teu], Transform3D(turned.scaled_local(_real_box[teu]), lifted), _livery(sim.boxes[box].line, box))
	for part: Variant in buffers:
		var multimesh: MultiMesh = _train_parts[part].multimesh
		multimesh.instance_count = buffers[part].size() / 16
		if not buffers[part].is_empty():
			multimesh.buffer = buffers[part]


func _draw_vehicles() -> void:
	if _vehicle_parts.is_empty():
		_vehicle_parts = {
			"cab": _vehicle_part(_merged([[Vector3(0.24, 0.2, 0.16), Vector3.ZERO, Color.WHITE]])),
			"chassis": _vehicle_part(_merged([[Vector3(0.22, 0.04, 0.52), Vector3.ZERO, Color(0.2, 0.2, 0.22)]])),
			1: _vehicle_part(_stack_meshes[1]),
			2: _vehicle_part(_stack_meshes[2]),
		}
	var buffers := {}
	for part: Variant in _vehicle_parts:
		buffers[part] = PackedFloat32Array()
	var headings := {}
	for vehicle: Vehicle in sim.vehicles:
		var pose := path_pose(vehicle.path, lerpf(vehicle.prev_t, vehicle.t, alpha))
		var heading: Vector2 = pose[1].normalized() if pose[1] != Vector2.ZERO else _headings.get(vehicle.id, Vector2.DOWN)
		headings[vehicle.id] = heading
		# Each lane is its own cell, so a vehicle drives down the middle of it.
		var at: Vector2 = (pose[0] + Vector2(0.5, 0.5)) * Grid.CELL / METRES_PER_UNIT
		var basis := Basis(Vector3.UP, atan2(heading.x, heading.y)).scaled_local(AREA_VEHICLE_SCALE)
		var placed := Transform3D(basis, Vector3(at.x, 0.04, at.y))
		_put(buffers.cab, placed * Transform3D(Basis(), Vector3(0, 0.14, 0.24)), Color(0.95, 0.75, 0.1) if vehicle.kind == "tractor" else Color(0.9, 0.9, 0.86))
		_put(buffers.chassis, placed * Transform3D(Basis(), Vector3(0, 0.06, -0.06)), Color.WHITE)
		if vehicle.loaded:
			var box: Dictionary = sim.boxes[vehicle.box]
			_put(buffers[box.teu], placed * _vehicle_box, _livery(box.line, vehicle.box))
	_headings = headings
	for part: Variant in _vehicle_parts:
		var multimesh: MultiMesh = _vehicle_parts[part].multimesh
		var buffer: PackedFloat32Array = buffers[part]
		var count := buffer.size() / 16
		if multimesh.instance_count < count:
			multimesh.instance_count = nearest_po2(count)
		buffer.resize(multimesh.instance_count * 16)
		multimesh.buffer = buffer
		multimesh.visible_instance_count = count


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
			_area_stacks[area] = {"drawn": [], "parts": parts}
		var drawn: Dictionary = _area_stacks[area]
		if drawn.drawn == [stacks.version, sim.areas.version]:
			continue
		drawn.drawn = [stacks.version, sim.areas.version]
		var buffers := _stack_buffers(area, stacks)
		for key: Vector2i in drawn.parts:
			var multimesh: MultiMesh = drawn.parts[key].multimesh
			var buffer: PackedFloat32Array = buffers[key.x]
			multimesh.instance_count = buffer.size() / 16
			if not buffer.is_empty():
				multimesh.buffer = buffer


## The instance buffers, by TEU, of yard area `area`'s stacked boxes.
func _stack_buffers(area: int, stacks: AreaStacks) -> Dictionary:
	var buffers := {1: PackedFloat32Array(), 2: PackedFloat32Array()}
	var geometry: Dictionary = sim.areas.list[area]
	var along := Vector2((geometry.end - geometry.start).sign())
	var turned := Basis(Vector3.UP, atan2(-along.normalized().y, along.normalized().x))
	var layout := sim.areas.layout(area)
	for position in stacks.stacks.size():
		var middle: Vector2i = layout.stacks[position].cells[1]
		var centre := (Vector2(middle) + Vector2(0.5, 0.5)) * Grid.CELL
		for tier: int in stacks.stacks[position].size():
			var ids: Array = stacks.stacks[position][tier]
			for i in ids.size():
				var teu: int = sim.boxes[ids[i]].teu
				var shift := 0.0 if teu == 2 else (-0.5 if i == 0 else 0.5) * (REAL_BOX_LENGTH[1] + 0.05)
				var at := centre + along.normalized() * shift
				var origin := Vector3(at.x, AREA_TOP + (tier + 0.5) * REAL_BOX_HEIGHT, at.y) / METRES_PER_UNIT
				_put(buffers[teu], Transform3D(turned.scaled_local(_real_box[teu]), origin), _livery(sim.boxes[ids[i]].line, ids[i]))
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
			node.mesh = _machine_meshes[machine.gear]
			var box := MeshInstance3D.new()
			box.name = "Box"
			box.mesh = _stack_meshes[2]
			box.material_override = StandardMaterial3D.new()
			node.add_child(box)
			add_child(node)
			_area_machines[id] = node
		var model: MeshInstance3D = _area_machines[id]
		var area: Dictionary = sim.areas.list[machine.area]
		var along := Vector2((area.end - area.start).sign())
		var out := Vector2(area.out)
		# An RTG spans the stack rows; an RMG spans them and the siding behind.
		var row: float = {"rtg": (2 + depth - 1) / 2.0, "rmg": (2 + depth) / 2.0}.get(machine.gear, 1.0)
		var k := sim.machines.position(id) * AreaLayout.BAY + (AreaLayout.BAY - 1) / 2.0
		var at := (Vector2(area.start) + along * k + out * row + Vector2(0.5, 0.5)) * Grid.CELL / METRES_PER_UNIT
		model.position = Vector3(at.x, AREA_TOP / METRES_PER_UNIT, at.y)
		model.rotation.y = atan2(-out.normalized().y, out.normalized().x)
		var gantry: bool = machine.gear in ["rtg", "rmg"]
		var tall: float = REAL_RTG_HEIGHT / METRES_PER_UNIT / _machine_heights[machine.gear] if gantry else 1.0
		var wide: float = (depth - 1.0) / (depth - 2.0) if machine.gear == "rmg" else 1.0
		model.scale = Vector3(wide, tall, 1.0)
		var job: Dictionary = machine.job
		var box: MeshInstance3D = model.get_node("Box")
		box.visible = not job.is_empty() and (job.phases[0].kind == "lift" or job.get("carrying", false))
		if box.visible:
			# Counter the machine's height scale so the box keeps its real size.
			box.scale = _real_box[2] / Vector3(wide, tall, 1.0)
			box.position = Vector3(0, lerpf(0.05, _machine_heights[machine.gear] * 0.85, sim.machines.spreader(id)), 0)
			box.rotation.y = PI / 2
			(box.material_override as StandardMaterial3D).albedo_color = PLAIN_BOX


## One mesh per kind of yard gear, standing on its origin.
func _machine_mesh(gear: String) -> Mesh:
	if gear not in ["rtg", "rmg"]:
		return _merged([
			[Vector3(0.26, 0.2, 0.4), Vector3(0, 0.12, 0), Color(0.85, 0.35, 0.15)],
			[Vector3(0.06, 0.06, 0.4), Vector3(0, 0.36, -0.1), Color(0.2, 0.2, 0.22)],
		])
	# Drawn scaled to REAL_RTG_HEIGHT; this only sets its proportions.
	var height: float = 0.3 + sim.rules.yard_gear[gear].tiers * BOX_HEIGHT
	var parts := []
	for x: float in [-0.56, 0.56]:
		for z: float in [-0.3, 0.3]:
			parts.append([Vector3(0.08, height, 0.08), Vector3(x, height / 2.0, z), Color(0.95, 0.95, 0.92)])
		parts.append([Vector3(0.14, 0.1, 0.72), Vector3(x, 0.05, 0), Color(0.2, 0.2, 0.22)])
	for z: float in [-0.3, 0.3]:
		# RTGs in yellow, RMGs in blue, so a rail yard reads apart from the stacks.
		parts.append([Vector3(1.24, 0.1, 0.1), Vector3(0, height, z), Color(0.95, 0.75, 0.1) if gear == "rtg" else Color(0.15, 0.45, 0.8)])
	return _merged(parts)


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
