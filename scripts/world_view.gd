class_name WorldView
extends Node3D
## Draws the sim as a small 3D model port. Reads PortSim every frame and
## never changes it.

## Road pieces, chosen per tile from its road neighbours: shape -> the
## neighbour sides it joins before turning. Corners are circular arcs.
const ROAD_SHAPES := {
	"straight": [Vector2i.UP, Vector2i.DOWN],
	"end": [Vector2i.DOWN],
	"corner": [Vector2i.DOWN, Vector2i.RIGHT],
	"junction": [],
}
const ARC_STEPS := 8
const TILE_HEIGHT := {PortMap.Tile.ROAD: 0.04, PortMap.Tile.QUAY: 0.25, PortMap.Tile.YARD: 0.08, PortMap.Tile.GATE: 0.5}
const TILE_COLOR := {
	PortMap.Tile.ROAD: Color(0.2, 0.2, 0.22),
	PortMap.Tile.QUAY: Color(0.62, 0.6, 0.55),
	PortMap.Tile.YARD: Color(0.45, 0.45, 0.43),
	PortMap.Tile.GATE: Color(0.2, 0.45, 0.7),
}
const BOX_HEIGHT := 0.3
## A box's length along the tile by TEU: 20 ft and 40 ft, at 1 tile = 25 m
## stretched a little so a lone 20 ft box still reads at a distance.
const BOX_LENGTH := {1: 0.4, 2: 0.8}
## Rows of 40 ft slots across a yard tile.
const YARD_ROWS := 2
## Boxes not yet booked on a line.
const PLAIN_BOX := Color(0.72, 0.72, 0.68)
const LANE_OFFSET := 0.22
## Metres in one world unit. shortcut: the tile view is drawn at 25 m a unit, so roads on the 4 m grid are scaled down to it; becomes 1 when M5 step 22 removes the tile model.
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
## Area ground by type, a little below road level.
const AREA_COLOR := {
	"yard_block": Color(0.56, 0.56, 0.53), "quay_apron": Color(0.66, 0.65, 0.6),
	"gate": Color(0.42, 0.5, 0.58), "depot": Color(0.6, 0.55, 0.45),
}
const AREA_TOP := 0.2
## A laid-out area's driven parts: the buffer strip, and handover slots in
## two alternating shades so each slot reads on its own.
const BUFFER_COLOR := Color(0.3, 0.3, 0.32)
const SLOT_COLORS: Array[Color] = [Color(0.24, 0.24, 0.26), Color(0.33, 0.33, 0.35)]
const RAIL_COLOR := Color(0.16, 0.16, 0.17)
## The quay edge's fender line, in safety yellow.
const EDGE_COLOR := Color(0.85, 0.7, 0.15)
## Camera distances to a chunk's centre past which it is drawn with less
## detail, as Cities: Skylines does: each tile's stack as one slab instead of
## every box, then no yard machines. Instances drawn cost the most render time.
const STACK_DETAIL := 60.0
const MACHINE_DETAIL := 80.0
const CRANE_HEIGHT := 3.2
## How far the girder reaches behind the quay edge and out over the water, in tiles.
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
const SEA_START := -18.0  # how far the water reaches past the map
const SEA_DISTANCE := 30.0  # how far out to sea ships appear

var sim: PortSim
## How far play has moved from the last tick towards the next, 0 to 1.
var alpha := 1.0

var _drawn_version := -1
## Tile kinds as last drawn, to find the chunks a map change touched.
var _drawn_tiles := PackedByteArray()
var _tiles := ChunkedMeshes.new()
var _tile_meshes := {}  # tile kind -> Mesh
var _road_meshes := {}  # road shape -> Mesh
var _marks_mesh: Mesh
var _quay_edge_mesh: Mesh
var _water := ShaderMaterial.new()
var _stacks := ChunkedMeshes.new()
var _stack_meshes := {}  # TEU -> Mesh, tinted per instance
## Far from the camera, each yard tile's stack as one slab in its top box's livery.
var _slabs := ChunkedMeshes.new()
var _slab_mesh: Mesh
## Stack parts ([chunk, teu]) drawn last time, so emptied ones get cleared.
var _stack_parts := {}
## Chunks with slabs drawn last time, so emptied ones get cleared.
var _slab_chunks := {}
## The tick and map version the stacks were drawn for; bulldozing a stack changes the map.
var _stacks_drawn := []
# shortcut: ships are one node each, fine at the handful a port works at once; MultiMesh them if berths grow past ~20.
var _ships := {}  # PortSim.Ship -> Node3D
## Every vehicle part drawn as one MultiMesh: "cab", "chassis", and boxes by TEU.
var _vehicle_parts := {}
## Each vehicle's last heading by id, kept while it waits on a one-tile path.
var _headings := {}
## A box on a vehicle's chassis: a container model turned along the vehicle and scaled to it.
var _vehicle_box := Transform3D(Basis(Vector3.UP, PI / 2).scaled_local(Vector3(0.65, 0.75, 0.8)), Vector3(0, 0.2, -0.06))
var _cranes := {}  # PortSim.Crane -> Node3D
var _machines := ChunkedMeshes.new()
var _machine_meshes := {}  # gear -> Mesh
## Machine parts ([chunk, gear]) drawn last frame, so emptied ones get cleared.
var _machine_parts_drawn := {}
## Every road on the 4 m grid as one mesh and its markings as another, redrawn when the roads change.
var _roads := MeshInstance3D.new()
var _road_marks := MeshInstance3D.new()
var _roads_drawn := -1
## Every area's ground as one mesh, redrawn when the areas change.
var _areas := MeshInstance3D.new()
var _areas_drawn := -1
var _area_preview := MeshInstance3D.new()
## The road being dragged out, tinted by whether it can be built.
var _road_preview := MeshInstance3D.new()
var _hover := _box(Vector3(1, 0.06, 1), Color(1, 1, 1, 0.5))
## Shade over each land tile the port does not own; rebuilt when it buys one.
var _unowned := {}  # land tile -> Node3D
var _drawn_land := -1


func _ready() -> void:
	var map := sim.map
	var water := _box(Vector3(map.size.x - SEA_START * 2, 0.1, map.size.y - SEA_START * 2), Color.WHITE)
	water.position = Vector3(map.size.x / 2.0, -0.35, map.size.y / 2.0)
	_water.shader = load("res://shaders/water.gdshader")
	_water.set_shader_parameter("coast_x", float(map.sea_width))
	water.material_override = _water
	add_child(water)
	var land_width := map.size.x - map.sea_width
	var land := _box(Vector3(land_width, 1, map.size.y), Color(0.36, 0.42, 0.3))
	land.position = Vector3(map.sea_width + land_width / 2.0, -0.5, map.size.y / 2.0)
	add_child(land)
	add_child(_hover)
	for node: MeshInstance3D in [_roads, _road_marks, _road_preview, _areas, _area_preview]:
		add_child(node)
	for preview: MeshInstance3D in [_road_preview, _area_preview]:
		preview.material_override = StandardMaterial3D.new()
		preview.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		preview.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(_tiles)
	_stacks.range_end = STACK_DETAIL
	_slabs.range_begin = STACK_DETAIL
	_machines.range_end = MACHINE_DETAIL
	add_child(_stacks)
	add_child(_slabs)
	add_child(_machines)
	_slab_mesh = _merged([[Vector3.ONE, Vector3(0, 0.5, 0), Color.WHITE]])
	for gear: String in sim.rules.yard_gear:
		_machine_meshes[gear] = _machine_mesh(gear)
	for kind: int in TILE_HEIGHT:
		_tile_meshes[kind] = _box_mesh(Vector3(1, TILE_HEIGHT[kind], 1), TILE_COLOR[kind])
	for teu: int in BOX_LENGTH:
		_stack_meshes[teu] = _container_mesh(teu)
	for shape: String in ROAD_SHAPES:
		_road_meshes[shape] = _road_mesh(shape)
	# A dashed centre line, two dashes a tile, just above a straight road.
	var top: float = TILE_HEIGHT[PortMap.Tile.ROAD] / 2.0 + 0.003
	_marks_mesh = _merged([[Vector3(0.04, 0.004, 0.22), Vector3(0, top, -0.25), Color(0.92, 0.92, 0.85)], [Vector3(0.04, 0.004, 0.22), Vector3(0, top, 0.25), Color(0.92, 0.92, 0.85)]])
	# A dark fender along the water's edge and two bollards, facing +Z.
	var deck: float = TILE_HEIGHT[PortMap.Tile.QUAY] / 2.0
	_quay_edge_mesh = _merged([
		[Vector3(1.0, 0.18, 0.06), Vector3(0, deck - 0.12, 0.52), Color(0.12, 0.12, 0.13)],
		[Vector3(1.0, 0.01, 0.08), Vector3(0, deck + 0.005, 0.44), Color(0.95, 0.75, 0.1)],
		[Vector3(0.07, 0.08, 0.07), Vector3(-0.3, deck + 0.04, 0.36), Color(0.15, 0.15, 0.16)],
		[Vector3(0.07, 0.08, 0.07), Vector3(0.3, deck + 0.04, 0.36), Color(0.15, 0.15, 0.16)],
	])


func show_hover(cell: Vector2i, ok: bool) -> void:
	_hover.visible = sim.map.in_bounds(cell)
	_hover.position = Vector3(cell.x + 0.5, 0.3, cell.y + 0.5)
	(_hover.mesh.material as StandardMaterial3D).albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


## Shows the road a drag would build from `from` to `to`, green if it can be
## built, else red; hidden when `from` is NONE.
func show_road_preview(from: Vector2i, to: Vector2i, type: String, ok: bool) -> void:
	_road_preview.visible = from != PortMap.NONE and from != to
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


func _process(_dt: float) -> void:
	if sim.roads.version != _roads_drawn:
		_draw_roads()
	if sim.areas.version != _areas_drawn:
		_draw_areas()
	var channel: Dictionary = sim.rules.channel
	_water.set_shader_parameter("channel", inverse_lerp(channel.start_depth, channel.max_depth, sim.channel_depth))
	if sim.map.version != _drawn_version:
		_draw_tiles()
	if sim.land.size() != _drawn_land:
		_draw_land()
	_draw_stacks()
	_draw_ships()
	_draw_cranes()
	_draw_vehicles()
	_draw_machines()


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
	_roads.mesh = surface.commit()
	_road_marks.mesh = marks.commit()


func _draw_areas() -> void:
	_areas_drawn = sim.areas.version
	var tool := _road_tool()
	for id: int in sim.areas.list:
		var colors := {}
		for cell in sim.areas.cells(id):
			colors[cell] = AREA_COLOR[sim.areas.list[id].type]
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
		for cell: Vector2i in colors:
			tool.set_color(colors[cell])
			_cell_quad(tool, cell, AREA_TOP)
	_areas.mesh = tool.commit()


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
## meet. Markings go to `marks` unless it is null: a solid line between the
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
	for centre: Vector2 in [start, end]:
		_disc(surface, centre, half, top)
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
	var cells: int = sim.rules.land.cells
	for y in ceili(sim.map.size.y / float(cells)):
		for x in ceili(sim.map.size.x / float(cells)):
			var tile := Vector2i(x, y)
			if sim.land.has(tile) and _unowned.has(tile):
				_unowned[tile].queue_free()
				_unowned.erase(tile)
			elif not sim.land.has(tile) and not _unowned.has(tile):
				# Only the land part of the tile: the sea is nobody's to buy.
				var from := maxi(x * cells, sim.map.sea_width)
				var width := mini((x + 1) * cells, sim.map.size.x) - from
				if width <= 0:
					continue
				var shade := _box(Vector3(width, 0.02, cells), Color(0, 0, 0, 0.3))
				shade.position = Vector3(from + width / 2.0, 0.02, (y + 0.5) * cells)
				add_child(shade)
				_unowned[tile] = shade


## Redraws only the chunks whose tiles changed since the last draw.
func _draw_tiles() -> void:
	_drawn_version = sim.map.version
	var map := sim.map
	_drawn_tiles.resize(map.size.x * map.size.y)
	var dirty := {}
	for y in map.size.y:
		for x in map.size.x:
			var kind := map.tile(Vector2i(x, y))
			if _drawn_tiles[x + y * map.size.x] != kind:
				_drawn_tiles[x + y * map.size.x] = kind
				# A road's shape depends on its neighbours, which may lie in the next chunk.
				for side: Vector2i in [Vector2i.ZERO] + PortMap.SIDES:
					if map.in_bounds(Vector2i(x, y) + side):
						dirty[ChunkedMeshes.chunk_of(Vector2i(x, y) + side)] = true
	for chunk: Vector2i in dirty:
		var by_kind := {}
		for kind: int in TILE_HEIGHT:
			by_kind[kind] = [] as Array[Transform3D]
		var by_shape := {}
		for shape: String in ROAD_SHAPES:
			by_shape[shape] = [] as Array[Transform3D]
		var marks: Array[Transform3D] = []
		var edges: Array[Transform3D] = []
		for y in range(chunk.y * ChunkedMeshes.CHUNK, mini((chunk.y + 1) * ChunkedMeshes.CHUNK, map.size.y)):
			for x in range(chunk.x * ChunkedMeshes.CHUNK, mini((chunk.x + 1) * ChunkedMeshes.CHUNK, map.size.x)):
				var cell := Vector2i(x, y)
				var kind := map.tile(cell)
				var centre := Vector3(x + 0.5, TILE_HEIGHT.get(kind, 0.0) / 2.0, y + 0.5)
				if kind == PortMap.Tile.ROAD:
					var piece := road_piece(map, cell)
					var placed := Transform3D(Basis(Vector3.UP, piece[1] * PI / 2), centre)
					by_shape[piece[0]].append(placed)
					if piece[0] == "straight":
						marks.append(placed)
				elif kind in TILE_HEIGHT:
					by_kind[kind].append(Transform3D(Basis(), centre))
				if kind == PortMap.Tile.QUAY:
					for side: Vector2i in PortMap.SIDES:
						if map.tile(cell + side) == PortMap.Tile.WATER:
							edges.append(Transform3D(Basis(Vector3.UP, atan2(side.x, side.y)), centre))
		for kind: int in by_kind:
			_tiles.show_part(Vector3i(chunk.x, chunk.y, kind), _tile_meshes[kind], by_kind[kind])
		for shape: String in by_shape:
			_tiles.show_part([chunk, shape], _road_meshes[shape], by_shape[shape])
		_tiles.show_part([chunk, "marks"], _marks_mesh, marks)
		_tiles.show_part([chunk, "quay edge"], _quay_edge_mesh, edges)


## The road piece for `cell`: [shape, quarter turns about +Y] whose turned
## sides match the road and gate tiles around it. The highway entry also
## joins the off-map road east of it.
static func road_piece(map: PortMap, cell: Vector2i) -> Array:
	var joined: Array[Vector2i] = []
	for side: Vector2i in PortMap.SIDES:
		if PortMap.is_road(map.tile(cell + side)) or (cell == map.entry and side == Vector2i.RIGHT):
			joined.append(side)
	if joined.size() != 1 and joined.size() != 2:
		return ["junction", 0]
	for shape: String in ["straight", "end", "corner"]:
		for turns in 4:
			var turned: Array = ROAD_SHAPES[shape].map(func(side: Vector2i) -> Vector2i: return _turn(side, turns))
			if turned.size() == joined.size() and turned.all(func(side: Vector2i) -> bool: return side in joined):
				return [shape, turns]
	return ["junction", 0]


## `side` turned the way Basis(Vector3.UP, turns * PI / 2) turns a tile, in map
## coordinates (map y is world z).
static func _turn(side: Vector2i, turns: int) -> Vector2i:
	var turned := Basis(Vector3.UP, turns * PI / 2) * Vector3(side.x, 0, side.y)
	return Vector2i(roundi(turned.x), roundi(turned.z))


## Where along `path` a vehicle `at` tiles in is drawn, as [position in tile
## coordinates, heading]. Through a tile where the path turns it follows a
## quarter circle between the middles of the tile's edges, so it never snaps.
## The 4 m grid cell at world point `at`.
static func grid_cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x * METRES_PER_UNIT / Grid.CELL), floori(at.z * METRES_PER_UNIT / Grid.CELL))


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


## Every stacked box, in its line's livery, redrawn when the sim has ticked
## or the map has changed.
func _draw_stacks() -> void:
	if _stacks_drawn == [sim.clock.ticks, sim.map.version]:
		return
	_stacks_drawn = [sim.clock.ticks, sim.map.version]
	var transforms := {}
	var colors := {}
	for part: Array in _stack_parts:
		transforms[part] = [] as Array[Transform3D]
		colors[part] = PackedColorArray()
	var slabs := {}
	var slab_colors := {}
	for chunk: Vector2i in _slab_chunks:
		slabs[chunk] = [] as Array[Transform3D]
		slab_colors[chunk] = PackedColorArray()
	for cell: Vector2i in sim.yard.stacks:
		var chunk := ChunkedMeshes.chunk_of(cell)
		var ids: Array = sim.yard.stacks[cell]
		if ids.is_empty():
			continue
		var forties := ids.filter(func(id: int) -> bool: return sim.boxes[id].teu == 2)
		var twenties := ids.filter(func(id: int) -> bool: return sim.boxes[id].teu == 1)
		if chunk not in slabs:
			slabs[chunk] = [] as Array[Transform3D]
			slab_colors[chunk] = PackedColorArray()
		var tiers: float = stack_spot(forties.size(), ids.size() - 1).y + 1
		var top: int = (forties + twenties)[-1]
		slabs[chunk].append(Transform3D(Basis().scaled(Vector3(BOX_LENGTH[2], tiers * BOX_HEIGHT, YARD_ROWS * 0.34)), Vector3(cell.x + 0.5, 0.08, cell.y + 0.5)))
		slab_colors[chunk].append(_livery(sim.boxes[top].line, top))
		for i in ids.size():
			var forty := i < forties.size()
			var id: int = forties[i] if forty else twenties[i - forties.size()]
			var spot := stack_spot(forties.size(), i)
			var part := [chunk, 2 if forty else 1]
			if part not in transforms:
				transforms[part] = [] as Array[Transform3D]
				colors[part] = PackedColorArray()
			transforms[part].append(Transform3D(Basis(), Vector3(cell.x + 0.5 + spot.x, 0.08 + (spot.y + 0.5) * BOX_HEIGHT, cell.y + 0.5 + spot.z)))
			colors[part].append(_livery(sim.boxes[id].line, id))
	_stack_parts.clear()
	for part: Array in transforms:
		_stacks.show_part(part, _stack_meshes[part[1]], transforms[part], colors[part])
		if not transforms[part].is_empty():
			_stack_parts[part] = true
	_slab_chunks.clear()
	for chunk: Vector2i in slabs:
		_slabs.show_part(chunk, _slab_mesh, slabs[chunk], slab_colors[chunk])
		if not slabs[chunk].is_empty():
			_slab_chunks[chunk] = true


## Where the `i`th box of a yard tile with `forties` 40 ft boxes sits, as
## (offset along the tile, tier, offset across it). The sim only knows which
## tile a box is on, so the view lays each tile out the way yards stack: two
## rows of 40 ft slots, filled a tier at a time across both rows, 40s first
## and then 20s in pairs end to end, so a 40 never rests on a 20.
static func stack_spot(forties: int, i: int) -> Vector3:
	var tier := i if i < forties else forties + (i - forties) / 2
	var along := 0.0
	if i >= forties:
		along = (BOX_LENGTH[1] / 2.0 + 0.01) * (-1 if (i - forties) % 2 == 0 else 1)
	return Vector3(along, tier / YARD_ROWS, ((tier % YARD_ROWS) - (YARD_ROWS - 1) / 2.0) * 0.34)


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
		var length := ship.cells.size()
		if ship not in _ships:
			_ships[ship] = _ship_model(ship, length)
		var model: Node3D = _ships[ship]
		var sail := lerpf(ship.prev_sail, ship.sail, alpha)
		var middle := (Vector2(ship.cells[0]) + Vector2(ship.cells[-1])) / 2.0 + Vector2(ship.side) + Vector2(0.5, 0.5)
		var alongside := Vector3(middle.x, 0.0, middle.y)
		var at_sea := alongside + Vector3(ship.side.x, 0, ship.side.y) * SEA_DISTANCE
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


## Where the first `count` boxes on deck of a ship `length` tiles long sit,
## in the ship's frame (length along +Z, bow at +Z): 40 ft bays from behind
## the bridge to short of the bow, three rows across, filled tier by tier.
## Boxes past the top tier are not drawn.
static func deck_slots(length: int, count: int) -> Array[Vector3]:
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
func _ship_model(ship: PortSim.Ship, length: int) -> Node3D:
	var model := Node3D.new()
	model.rotation.y = 0.0 if ship.side.x != 0 else PI / 2
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
		var ship := _ship_beside(crane.cell)
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
	var water := sim.map.neighbor(crane.cell, PortMap.Tile.WATER) - crane.cell
	model.position = Vector3(crane.cell.x + 0.5, 0.25, crane.cell.y + 0.5)
	model.rotation.y = atan2(water.x, water.y)
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


## The ship alongside the quay tile `cell`, or null.
func _ship_beside(cell: Vector2i) -> PortSim.Ship:
	for ship: PortSim.Ship in sim.ships:
		if cell in ship.cells:
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
		# Keep right: each direction drives in its own half of the road.
		var right := Vector2(-heading.y, heading.x) * LANE_OFFSET
		var placed := Transform3D(Basis(Vector3.UP, atan2(heading.x, heading.y)), Vector3(pose[0].x + 0.5 + right.x, 0.04, pose[0].y + 0.5 + right.y))
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


## Each yard block's machines: one over each box being handled, the rest
## parked along the block. RTGs straddle the stacks; reach stackers drive
## beside them. One MultiMesh per chunk and gear, as a port can have hundreds.
func _draw_machines() -> void:
	var working := {}  # block anchor -> tiles being handled
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.state == "handling":
			if vehicle.block not in working:
				working[vehicle.block] = []
			working[vehicle.block].append(vehicle.target)
	var parts := {}
	for part: Array in _machine_parts_drawn:
		parts[part] = [] as Array[Transform3D]
	for anchor in sim.yard.anchors():
		var gear := sim.yard.gear_of(anchor)
		var tiles := sim.yard.block(anchor)
		var busy: Array = working.get(anchor, [])
		var count := sim.yard.machines(anchor)
		for i in count:
			var cell: Vector2i = busy[i] if i < busy.size() else tiles[i * tiles.size() / count]
			var part := [ChunkedMeshes.chunk_of(cell), gear]
			if part not in parts:
				parts[part] = [] as Array[Transform3D]
			parts[part].append(Transform3D(Basis(), Vector3(cell.x + 0.5, 0.08, cell.y + 0.5 + (0.0 if gear == "rtg" else 0.38))))
	_machine_parts_drawn.clear()
	for part: Array in parts:
		_machines.show_part(part, _machine_meshes[part[1]], parts[part])
		if not parts[part].is_empty():
			_machine_parts_drawn[part] = true


## One mesh per kind of yard gear, standing on its origin.
func _machine_mesh(gear: String) -> Mesh:
	if gear != "rtg":
		return _merged([
			[Vector3(0.26, 0.2, 0.4), Vector3(0, 0.12, 0), Color(0.85, 0.35, 0.15)],
			[Vector3(0.06, 0.06, 0.4), Vector3(0, 0.36, -0.1), Color(0.2, 0.2, 0.22)],
		])
	# Tall enough to clear a tile stacked to the gear's capacity.
	var height: float = 0.3 + ceili(sim.rules.yard_gear.rtg.capacity / float(YARD_ROWS)) * BOX_HEIGHT
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


## A road piece one tile across and TILE_HEIGHT[ROAD] thick, centred on the
## origin, joining the sides ROAD_SHAPES gives for `shape`.
func _road_mesh(shape: String) -> Mesh:
	var outline := PackedVector2Array()
	match shape:
		"straight", "junction":
			outline = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
		"end":
			# Half a tile from the joined side, rounded off at the middle.
			outline = [Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
			for step in ARC_STEPS + 1:
				var angle := PI - PI * step / ARC_STEPS
				outline.append(Vector2(cos(angle), -sin(angle)) * 0.5)
		"corner":
			# A quarter disc of radius 1 about the corner between the joined sides.
			outline = [Vector2(0.5, 0.5)]
			for step in ARC_STEPS + 1:
				var angle := PI + PI / 2 * step / ARC_STEPS
				outline.append(Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)))
	return _prism(outline, TILE_HEIGHT[PortMap.Tile.ROAD], TILE_COLOR[PortMap.Tile.ROAD])


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
