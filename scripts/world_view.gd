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
## Area ground by kind, a little below road level.
const AREA_COLOR := {
	"yard_block": Color(0.56, 0.56, 0.53), "quay_apron": Color(0.66, 0.65, 0.6),
	"gate": Color(0.42, 0.5, 0.58), "depot": Color(0.6, 0.55, 0.45),
}
const AREA_TOP := 0.2
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
## The quay edge's fender line, in safety yellow.
const EDGE_COLOR := Color(0.85, 0.7, 0.15)
## Mixed into an idle area's ground, so an area cut off from its road stands out.
const IDLE_TINT := Color(0.85, 0.2, 0.15)
const CRANE_HEIGHT := 3.2
## How far the girder reaches behind the quay edge and out over the water, in world units.
const CRANE_BACK := -1.0
const CRANE_REACH := 2.6
const CRANE_COLOR := Color(0.85, 0.3, 0.2)
## A ship's deck height, the room its bridge and bow take, and its deck stacks.
const SHIP_DECK := 0.3
const SHIP_STERN := 1.0
const SHIP_BOW := 1.1
const DECK_BAY := 0.48
const DECK_ROWS := 3
const DECK_TIERS := 4
## A 40 ft box turned along the ship and sized to a deck bay.
var _deck_box := Basis(Vector3.UP, PI / 2) * Basis.from_scale(Vector3((DECK_BAY - 0.04) / 0.78, 0.8, 1.27))
## Each info view's colours and what they mean, by HudDetails group.
const INFO_LEGENDS := {
	HudDetails.GROUP_TRAFFIC: [["Flowing", Color(0.2, 0.8, 0.35)], ["Half stopped", Color(0.95, 0.75, 0.15)], ["Stopped", Color(0.9, 0.2, 0.15)]],
	HudDetails.GROUP_CONTAINERS: [["Empty", Color(0.2, 0.8, 0.35)], ["Half full", Color(0.95, 0.75, 0.15)], ["Full", Color(0.9, 0.2, 0.15)]],
}
const INFO_TOP := 0.6
const INFO_SECONDS := 0.25
const SEA_START := -18.0  # how far the water reaches past the site
const SEA_DISTANCE := 30.0  # how far out to sea ships appear

var sim: PortSim
## The info view drawn over the map: a key of INFO_LEGENDS, or "" for none.
var info_view := ""
## How far play has moved from the last tick towards the next, 0 to 1.
var alpha := 1.0

var _water := ShaderMaterial.new()
var _stack_meshes := {}  # TEU -> Mesh, tinted per instance
# shortcut: ships are one node each, fine at the handful a port works at once; MultiMesh them if berths grow past ~20.
var _ships := {}  # PortSim.Ship -> Node3D
## Every vehicle part drawn as one MultiMesh: "cab", "chassis", and boxes by TEU.
var _vehicle_parts := {}
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
var _area_stacks := {}
var _area_stacks_drawn := []
## Each box model scaled to real size, by TEU, for boxes on areas and vehicles.
var _real_box := {}
var _machine_meshes := {}  # gear -> Mesh
## Every road on the 4 m grid as one mesh and its markings as another, redrawn when the roads change.
var _roads := MeshInstance3D.new()
var _road_marks := MeshInstance3D.new()
var _roads_drawn := -1
## Every area's ground as one mesh, redrawn when the areas change.
var _areas := MeshInstance3D.new()
## The area and road versions the areas were drawn for: idle tints follow the roads.
var _areas_drawn := []
var _area_preview := MeshInstance3D.new()
## The road being dragged out, tinted by whether it can be built.
var _road_preview := MeshInstance3D.new()
var _hover := _box(Vector3(Grid.CELL, 1.5, Grid.CELL) / METRES_PER_UNIT, Color(1, 1, 1, 0.5))
## Shade over each land tile the port does not own; rebuilt when it buys one.
var _info := MeshInstance3D.new()
var _info_left := 0.0
var _unowned := {}  # land tile -> Node3D
var _drawn_land := -1


func _ready() -> void:
	var site := site_size(sim)
	var sea: float = sim.rules.site.sea_width / METRES_PER_UNIT
	var water := _box(Vector3(site.x - SEA_START * 2, 0.1, site.y - SEA_START * 2), Color.WHITE)
	water.position = Vector3(site.x / 2.0, -0.35, site.y / 2.0)
	_water.shader = load("res://shaders/water.gdshader")
	_water.set_shader_parameter("coast_x", sea)
	water.material_override = _water
	add_child(water)
	# The land runs on past the east edge, where the highway comes in from the hinterland.
	var land := _box(Vector3(site.x - sea - SEA_START, 1, site.y), Color(0.36, 0.42, 0.3))
	land.position = Vector3((site.x - SEA_START + sea) / 2.0, -0.5, site.y / 2.0)
	add_child(land)
	add_child(_hover)
	for node: MeshInstance3D in [_roads, _road_marks, _road_preview, _areas, _area_preview]:
		add_child(node)
	add_child(_info)
	for preview: MeshInstance3D in [_road_preview, _area_preview, _info]:
		preview.material_override = StandardMaterial3D.new()
		preview.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		preview.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_info.material_override.vertex_color_use_as_albedo = true
	for gear: String in sim.rules.yard_gear:
		_machine_meshes[gear] = _machine_mesh(gear)
		_machine_heights[gear] = _machine_meshes[gear].get_aabb().end.y
	for teu: int in BOX_LENGTH:
		_stack_meshes[teu] = _container_mesh(teu)
		var real := Vector3(REAL_BOX_LENGTH[teu], REAL_BOX_HEIGHT, REAL_BOX_WIDTH) / METRES_PER_UNIT
		_real_box[teu] = real / _stack_meshes[teu].get_aabb().size
		_area_stacks[teu] = _vehicle_part(_stack_meshes[teu])


## The site in world units.
static func site_size(port: PortSim) -> Vector2:
	return Vector2(port.rules.site.width, port.rules.site.height) / METRES_PER_UNIT


## Marks grid cell `cell` under the mouse, green if the tool can act there, else red.
func show_hover(cell: Vector2i, ok: bool) -> void:
	_hover.visible = cell != Grid.NONE
	_hover.position = _world((Vector2(cell) + Vector2(0.5, 0.5)) * Grid.CELL, 1.0)
	(_hover.mesh.material as StandardMaterial3D).albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


## Shows the road a drag would build from `from` to `to`, green if it can be
## built, else red; hidden when `from` is NONE.
func show_road_preview(from: Vector2i, to: Vector2i, type: String, ok: bool) -> void:
	_road_preview.visible = from != Grid.NONE and from != to
	if not _road_preview.visible:
		return
	var surface := _road_tool()
	_add_road(surface, null, from, to, sim.rules.road_types[type])
	_road_preview.mesh = surface.commit()
	_road_preview.material_override.albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


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
	if sim.roads.version != _roads_drawn:
		_draw_roads()
	if [sim.areas.version, sim.roads.version] != _areas_drawn:
		_draw_areas()
	var channel: Dictionary = sim.rules.channel
	_water.set_shader_parameter("channel", inverse_lerp(channel.start_depth, channel.max_depth, sim.channel_depth))
	if sim.land.size() != _drawn_land:
		_draw_land()
	_draw_ships()
	_draw_cranes()
	_draw_vehicles()
	_draw_area_machines()
	_draw_area_stacks()


func _draw_roads() -> void:
	_roads_drawn = sim.roads.version
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
	var entry := sim.site_entry()
	_add_road(surface, marks, entry + Vector2i(ceili(-SEA_START * METRES_PER_UNIT / Grid.CELL), 0), entry, sim.rules.road_types.terminal_2_2)
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


## For the Traffic view, each road's or area's cells -> the share of the
## vehicles in it that are stopped; for Containers, each yard block's cells ->
## how full it is.
# shortcut: traffic shows this moment only, not an average over time; average once players ask where jams were.
static func info_shares(sim: PortSim, view: String) -> Dictionary:
	var shares := {}
	if view == HudDetails.GROUP_TRAFFIC:
		var places: Array[Array] = []
		for id: int in sim.roads.segments:
			var cells: Array[Vector2i] = []
			for lane: Dictionary in sim.roads.lanes(id):
				cells.append_array(lane.cells)
			places.append(cells)
		for id: int in sim.areas.list:
			places.append(sim.areas.cells(id))
		var place_of := {}
		for cells in places:
			for cell: Vector2i in cells:
				place_of[cell] = cells
		var counts := {}  # cells -> (stopped, vehicles)
		for vehicle in sim.vehicles:
			var cells: Variant = place_of.get(Vector2i(vehicle.position(1.0).round()))
			if cells != null:
				counts[cells] = counts.get(cells, Vector2i.ZERO) + Vector2i(1 if vehicle.waited > 0 else 0, 1)
		for cells: Array in counts:
			shares[cells] = counts[cells].x / float(counts[cells].y)
	else:
		for id: int in sim.areas.list:
			if sim.areas.kind_of(sim.areas.list[id]) == "yard_block":
				var fill := sim.block_fill(id)
				shares[sim.areas.cells(id)] = fill.x / float(maxi(fill.y, 1))
	return shares


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
	var middle: Vector2 = across * ((lanes - 1) / 2.0 - road.backward)
	var start: Vector2 = (Vector2(a) + Vector2(0.5, 0.5) + middle) * Grid.CELL
	var end: Vector2 = (Vector2(b) + Vector2(0.5, 0.5) + middle) * Grid.CELL
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


## A flat strip `half` either side of the line from `from` to `to`, in metres.
static func _strip(tool: SurfaceTool, from: Vector2, to: Vector2, half: float, height: float) -> void:
	var side := (to - from).normalized().orthogonal() * half
	var corners: Array[Vector2] = [from - side, to - side, to + side, from + side]
	# Clockwise from above, Godot's front face.
	for i: int in [0, 2, 1, 0, 3, 2]:
		tool.add_vertex(_world(corners[i], height))


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


func _draw_land() -> void:
	_drawn_land = sim.land.size()
	var site := site_size(sim)
	var size: float = sim.rules.land.metres / METRES_PER_UNIT
	var sea: float = sim.rules.site.sea_width / METRES_PER_UNIT
	for y in ceili(site.y / size):
		for x in ceili(site.x / size):
			var tile := Vector2i(x, y)
			if sim.land.has(tile) and _unowned.has(tile):
				_unowned[tile].queue_free()
				_unowned.erase(tile)
			elif not sim.land.has(tile) and not _unowned.has(tile):
				# Only the land part of the tile: the sea is nobody's to buy.
				var from := maxf(x * size, sea)
				var width := minf((x + 1) * size, site.x) - from
				if width <= 0.0:
					continue
				var shade := _box(Vector3(width, 0.02, size), Color(0, 0, 0, 0.3))
				shade.position = Vector3(from + width / 2.0, 0.02, (y + 0.5) * size)
				add_child(shade)
				_unowned[tile] = shade


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
		# shortcut: ships at anchorage are only counted in the HUD; draw them offshore if players miss them.
		if ship.state == PortSim.Ship.State.ANCHORED:
			continue
		var length: float = sim.rules.ship_classes[ship.kind].length / METRES_PER_UNIT
		if ship not in _ships:
			_ships[ship] = _ship_model(ship, length)
		var model: Node3D = _ships[ship]
		var sail := lerpf(ship.prev_sail, ship.sail, alpha)
		var frame := _berth_frame(ship)
		var alongside := Vector3(frame[0].x, 0.0, frame[0].y)
		var at_sea := alongside + Vector3(frame[1].x, 0, frame[1].y) * SEA_DISTANCE
		model.position = at_sea.lerp(alongside, ease(sail, -2.0))
		var spec: Dictionary = sim.rules.ship_classes[ship.kind]
		# Imports still aboard, plus the exports loaded so far.
		var aboard: int = ship.boxes + spec.export_moves - ship.exports
		var deck: MultiMesh = (model.get_node("Deck") as MultiMeshInstance3D).multimesh
		if model.get_meta("aboard", -1) != aboard:
			model.set_meta("aboard", aboard)
			var slots := deck_slots(length, aboard)
			deck.instance_count = maxi(deck.instance_count, slots.size())
			deck.visible_instance_count = slots.size()
			for i in slots.size():
				deck.set_instance_transform(i, Transform3D(_deck_box, slots[i]))
				deck.set_instance_color(i, _livery(ship.line, i))


## Where `ship` lies alongside in world units, and the way out to sea:
## [middle, side]. A ship's middle is a world unit out from the quay's edge.
func _berth_frame(ship: PortSim.Ship) -> Array[Vector2]:
	var area: Dictionary = sim.areas.list[ship.apron]
	var along := Vector2((area.end - area.start).sign())
	var side := Vector2(area.out).normalized()
	var span := AreaFlow.ship_cells(sim, ship.kind)
	var depth := sim.areas.depth_of(area)
	var edge := (Vector2(area.start) + along * (ship.from + (span - 1) / 2.0) + Vector2(area.out) * (depth - 1) + Vector2(0.5, 0.5)) * Grid.CELL
	return [edge / METRES_PER_UNIT + side, side]


## Where the first `count` boxes on deck of a ship `length` world units long sit,
## in the ship's frame (length along +Z, bow at +Z): 40 ft bays from behind
## the bridge to short of the bow, three rows across, filled tier by tier.
## Boxes past the top tier are not drawn.
static func deck_slots(length: float, count: int) -> Array[Vector3]:
	var bays := floori((length - SHIP_BOW - SHIP_STERN) / DECK_BAY)
	var per_tier := bays * DECK_ROWS
	var slots: Array[Vector3] = []
	for i in mini(count, per_tier * DECK_TIERS):
		var bay := (i % per_tier) / DECK_ROWS
		var row := i % DECK_ROWS
		slots.append(Vector3((row - (DECK_ROWS - 1) / 2.0) * 0.42, SHIP_DECK + (i / per_tier + 0.5) * BOX_HEIGHT * 0.8, -length / 2.0 + SHIP_STERN + (bay + 0.5) * DECK_BAY))
	return slots


## A hull in the line's livery with a pointed bow, a bridge at the stern
## and a deck of boxes, turned so its length lies along the quay.
func _ship_model(ship: PortSim.Ship, length: float) -> Node3D:
	var model := Node3D.new()
	var side := Vector2(sim.areas.list[ship.apron].out)
	model.rotation.y = atan2(-side.y, side.x)
	var half := length / 2.0 - 0.2
	var outline := PackedVector2Array([Vector2(-0.7, -half), Vector2(0.7, -half), Vector2(0.7, half - 1.0), Vector2(0, half), Vector2(-0.7, half - 1.0)])
	var hull := MeshInstance3D.new()
	hull.mesh = _prism(outline, 0.6, Color.html(sim.rules.lines[ship.line].livery))
	hull.position.y = SHIP_DECK - 0.3
	model.add_child(hull)
	var bridge := _box(Vector3(1.2, 0.9, 0.5), Color(0.92, 0.92, 0.9))
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
	var move_minutes: float = 60.0 / (sim.rules.sts_crane.rate * sim.rules.crane_interference)
	for crane: PortSim.Crane in sim.cranes:
		if crane not in _cranes:
			_cranes[crane] = _crane_model(crane)
		var model: Node3D = _cranes[crane]
		var ship := _ship_over(crane)
		var phase := crane.timer / move_minutes if crane.tractor != 0 else 0.0
		var pose := crane_pose(phase, ship != null and ship.boxes > 0)
		var trolley: Node3D = model.get_node("Trolley")
		trolley.position.z = lerpf(CRANE_BACK, CRANE_REACH, pose[0])
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
	for x: float in [-0.35, 0.35]:
		for z: float in [-0.35, 0.35]:
			var leg := _box(Vector3(0.1, CRANE_HEIGHT, 0.1), CRANE_COLOR)
			leg.position = Vector3(x, CRANE_HEIGHT / 2.0, z)
			model.add_child(leg)
	var girder := _box(Vector3(0.5, 0.18, CRANE_REACH - CRANE_BACK + 0.6), CRANE_COLOR)
	girder.position = Vector3(0, CRANE_HEIGHT, (CRANE_REACH + CRANE_BACK) / 2.0)
	model.add_child(girder)
	var trolley := _box(Vector3(0.4, 0.14, 0.3), Color(0.25, 0.25, 0.27))
	trolley.name = "Trolley"
	trolley.position.y = CRANE_HEIGHT - 0.16
	model.add_child(trolley)
	var cable := _box(Vector3(0.03, 1.0, 0.03), Color(0.15, 0.15, 0.15))
	cable.name = "Cable"
	trolley.add_child(cable)
	var spreader := _box(Vector3(0.36, 0.06, 0.8), Color(0.95, 0.75, 0.1))
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
	if _area_stacks_drawn == [sim.clock.ticks, sim.areas.version]:
		return
	_area_stacks_drawn = [sim.clock.ticks, sim.areas.version]
	var buffers := {1: PackedFloat32Array(), 2: PackedFloat32Array()}
	for area: int in sim.area_stacks:
		if area not in sim.areas.list:
			continue
		var geometry: Dictionary = sim.areas.list[area]
		var along := Vector2((geometry.end - geometry.start).sign())
		var turned := Basis(Vector3.UP, atan2(-along.normalized().y, along.normalized().x))
		var layout := sim.areas.layout(area)
		var stacks: AreaStacks = sim.area_stacks[area]
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
	for teu: int in buffers:
		var multimesh: MultiMesh = _area_stacks[teu].multimesh
		var buffer: PackedFloat32Array = buffers[teu]
		var count := buffer.size() / 16
		if multimesh.instance_count < count:
			multimesh.instance_count = nearest_po2(count)
		buffer.resize(multimesh.instance_count * 16)
		multimesh.buffer = buffer
		multimesh.visible_instance_count = count


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
		var row: float = (2 + depth - 1) / 2.0 if machine.gear == "rtg" else 1.0
		var k := sim.machines.position(id) * AreaLayout.BAY + (AreaLayout.BAY - 1) / 2.0
		var at := (Vector2(area.start) + along * k + out * row + Vector2(0.5, 0.5)) * Grid.CELL / METRES_PER_UNIT
		model.position = Vector3(at.x, AREA_TOP / METRES_PER_UNIT, at.y)
		model.rotation.y = atan2(-out.normalized().y, out.normalized().x)
		var tall: float = REAL_RTG_HEIGHT / METRES_PER_UNIT / _machine_heights.rtg if machine.gear == "rtg" else 1.0
		model.scale = Vector3(1.0, tall, 1.0)
		var job: Dictionary = machine.job
		var box: MeshInstance3D = model.get_node("Box")
		box.visible = not job.is_empty() and (job.phases[0].kind == "lift" or job.get("carrying", false))
		if box.visible:
			# Counter the machine's height scale so the box keeps its real size.
			box.scale = _real_box[2] / Vector3(1.0, tall, 1.0)
			box.position = Vector3(0, lerpf(0.05, _machine_heights[machine.gear] * 0.85, sim.machines.spreader(id)), 0)
			box.rotation.y = PI / 2
			(box.material_override as StandardMaterial3D).albedo_color = PLAIN_BOX


## One mesh per kind of yard gear, standing on its origin.
func _machine_mesh(gear: String) -> Mesh:
	if gear != "rtg":
		return _merged([
			[Vector3(0.26, 0.2, 0.4), Vector3(0, 0.12, 0), Color(0.85, 0.35, 0.15)],
			[Vector3(0.06, 0.06, 0.4), Vector3(0, 0.36, -0.1), Color(0.2, 0.2, 0.22)],
		])
	# Drawn scaled to REAL_RTG_HEIGHT; this only sets its proportions.
	var height: float = 0.3 + sim.rules.yard_gear.rtg.tiers * BOX_HEIGHT
	var parts := []
	for x: float in [-0.56, 0.56]:
		for z: float in [-0.3, 0.3]:
			parts.append([Vector3(0.08, height, 0.08), Vector3(x, height / 2.0, z), Color(0.95, 0.95, 0.92)])
		parts.append([Vector3(0.14, 0.1, 0.72), Vector3(x, 0.05, 0), Color(0.2, 0.2, 0.22)])
	for z: float in [-0.3, 0.3]:
		parts.append([Vector3(1.24, 0.1, 0.1), Vector3(0, height, z), Color(0.95, 0.75, 0.1)])
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
