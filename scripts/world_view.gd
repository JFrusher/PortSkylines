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
## Boxes not yet booked on a line.
const PLAIN_BOX := Color(0.72, 0.72, 0.68)
const LANE_OFFSET := 0.22
const BOX_COLOR := Color(0.85, 0.4, 0.15)
const CRANE_HEIGHT := 3.2
## How far the girder reaches behind the quay edge and out over the water, in tiles.
const CRANE_BACK := -1.0
const CRANE_REACH := 2.6
const CRANE_COLOR := Color(0.85, 0.3, 0.2)
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
var _stacks := ChunkedMeshes.new()
var _stack_meshes := {}  # TEU -> Mesh, tinted per instance
## Stack parts ([chunk, teu]) drawn last time, so emptied ones get cleared.
var _stack_parts := {}
## The tick and map version the stacks were drawn for; bulldozing a stack changes the map.
var _stacks_drawn := []
# shortcut: ships and vehicles are one node each, fine under ~100; MultiMesh them in M5.
var _ships := {}  # PortSim.Ship -> Node3D
var _vehicles := {}  # Vehicle -> Node3D
var _cranes := {}  # PortSim.Crane -> Node3D
var _hover := _box(Vector3(1, 0.06, 1), Color(1, 1, 1, 0.5))
## Shade over each land tile the port does not own; rebuilt when it buys one.
var _unowned := {}  # land tile -> Node3D
var _drawn_land := -1


func _ready() -> void:
	var map := sim.map
	var water := _box(Vector3(map.size.x - SEA_START * 2, 0.1, map.size.y - SEA_START * 2), Color(0.12, 0.3, 0.45))
	water.position = Vector3(map.size.x / 2.0, -0.35, map.size.y / 2.0)
	add_child(water)
	var land_width := map.size.x - map.sea_width
	var land := _box(Vector3(land_width, 1, map.size.y), Color(0.36, 0.42, 0.3))
	land.position = Vector3(map.sea_width + land_width / 2.0, -0.5, map.size.y / 2.0)
	add_child(land)
	add_child(_hover)
	add_child(_tiles)
	add_child(_stacks)
	for kind: int in TILE_HEIGHT:
		_tile_meshes[kind] = _box_mesh(Vector3(1, TILE_HEIGHT[kind], 1), TILE_COLOR[kind])
	for teu: int in BOX_LENGTH:
		var mesh := _box_mesh(Vector3(BOX_LENGTH[teu] - 0.04, BOX_HEIGHT - 0.02, 0.32), Color.WHITE)
		(mesh.material as StandardMaterial3D).vertex_color_use_as_albedo = true
		_stack_meshes[teu] = mesh
	for shape: String in ROAD_SHAPES:
		_road_meshes[shape] = _road_mesh(shape)


func show_hover(cell: Vector2i, ok: bool) -> void:
	_hover.visible = sim.map.in_bounds(cell)
	_hover.position = Vector3(cell.x + 0.5, 0.3, cell.y + 0.5)
	(_hover.mesh.material as StandardMaterial3D).albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


func _process(_dt: float) -> void:
	if sim.map.version != _drawn_version:
		_draw_tiles()
	if sim.land.size() != _drawn_land:
		_draw_land()
	_draw_stacks()
	_draw_ships()
	_draw_cranes()
	_draw_vehicles()


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
		for y in range(chunk.y * ChunkedMeshes.CHUNK, mini((chunk.y + 1) * ChunkedMeshes.CHUNK, map.size.y)):
			for x in range(chunk.x * ChunkedMeshes.CHUNK, mini((chunk.x + 1) * ChunkedMeshes.CHUNK, map.size.x)):
				var cell := Vector2i(x, y)
				var kind := map.tile(cell)
				if kind == PortMap.Tile.ROAD:
					var piece := road_piece(map, cell)
					by_shape[piece[0]].append(Transform3D(Basis(Vector3.UP, piece[1] * PI / 2), Vector3(x + 0.5, TILE_HEIGHT[kind] / 2.0, y + 0.5)))
				elif kind in TILE_HEIGHT:
					by_kind[kind].append(Transform3D(Basis(), Vector3(x + 0.5, TILE_HEIGHT[kind] / 2.0, y + 0.5)))
		for kind: int in by_kind:
			_tiles.show_part(Vector3i(chunk.x, chunk.y, kind), _tile_meshes[kind], by_kind[kind])
		for shape: String in by_shape:
			_tiles.show_part([chunk, shape], _road_meshes[shape], by_shape[shape])


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
	for cell: Vector2i in sim.yard.stacks:
		var chunk := ChunkedMeshes.chunk_of(cell)
		var ids: Array = sim.yard.stacks[cell]
		var forties := ids.filter(func(id: int) -> bool: return sim.boxes[id].teu == 2)
		var twenties := ids.filter(func(id: int) -> bool: return sim.boxes[id].teu == 1)
		for i in ids.size():
			var forty := i < forties.size()
			var id: int = forties[i] if forty else twenties[i - forties.size()]
			var spot := stack_spot(forties.size(), i)
			var part := [chunk, 2 if forty else 1]
			if part not in transforms:
				transforms[part] = [] as Array[Transform3D]
				colors[part] = PackedColorArray()
			transforms[part].append(Transform3D(Basis(), Vector3(cell.x + 0.5 + spot.x, 0.08 + (spot.y + 0.5) * BOX_HEIGHT, cell.y + 0.5)))
			colors[part].append(_livery(sim.boxes[id].line, id))
	_stack_parts.clear()
	for part: Array in transforms:
		_stacks.show_part(part, _stack_meshes[part[1]], transforms[part], colors[part])
		if not transforms[part].is_empty():
			_stack_parts[part] = true


## Where the `i`th box of a yard tile with `forties` 40 ft boxes sits, as
## (offset along the tile, tier). The sim only knows which tile a box is on,
## so the view lays each tile out as one 40 ft slot the way yards stack: the
## 40s at the bottom, then the 20s in pairs end to end above them, so a 40
## never rests on a 20.
static func stack_spot(forties: int, i: int) -> Vector2:
	if i < forties:
		return Vector2(0, i)
	var k := i - forties
	return Vector2((BOX_LENGTH[1] / 2.0 + 0.01) * (-1 if k % 2 == 0 else 1), forties + k / 2)


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
		var along_z := ship.side.x != 0
		if ship not in _ships:
			var hull := _box(Vector3(1.4, 0.6, length - 0.4) if along_z else Vector3(length - 0.4, 0.6, 1.4), Color.html(sim.rules.lines[ship.line].livery))
			var cargo := _box(Vector3(1.0, 0.6, length - 1.6) if along_z else Vector3(length - 1.6, 0.6, 1.0), BOX_COLOR)
			cargo.name = "Cargo"
			cargo.position.y = 0.6
			hull.add_child(cargo)
			add_child(hull)
			_ships[ship] = hull
		var hull: Node3D = _ships[ship]
		var sail := lerpf(ship.prev_sail, ship.sail, alpha)
		var middle := (Vector2(ship.cells[0]) + Vector2(ship.cells[-1])) / 2.0 + Vector2(ship.side) + Vector2(0.5, 0.5)
		var alongside := Vector3(middle.x, -0.05, middle.y)
		var at_sea := alongside + Vector3(ship.side.x, 0, ship.side.y) * SEA_DISTANCE
		hull.position = at_sea.lerp(alongside, ease(sail, -2.0))
		var cargo: Node3D = hull.get_node("Cargo")
		cargo.visible = ship.boxes > 0
		cargo.scale.y = maxf(ship.boxes / float(sim.rules.ship_classes[ship.kind].import_moves), 0.01)


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


func _draw_vehicles() -> void:
	_forget_gone(_vehicles, sim.vehicles)
	for lorry: Vehicle in sim.vehicles:
		if lorry not in _vehicles:
			var cab := _box(Vector3(0.3, 0.25, 0.6), Color(0.85, 0.85, 0.8) if lorry.kind == "lorry" else Color(0.95, 0.75, 0.1))
			var box := _box(Vector3(0.28, 0.22, 0.5), BOX_COLOR)
			box.name = "Box"
			box.position.y = 0.23
			cab.add_child(box)
			add_child(cab)
			_vehicles[lorry] = cab
		var cab: Node3D = _vehicles[lorry]
		var pose := path_pose(lorry.path, lerpf(lorry.prev_t, lorry.t, alpha))
		var at := pose[0]
		var heading := pose[1].normalized()
		# Keep right: each direction drives in its own half of the road.
		var right := Vector2(-heading.y, heading.x) * LANE_OFFSET
		cab.position = Vector3(at.x + 0.5 + right.x, 0.17, at.y + 0.5 + right.y)
		if heading != Vector2.ZERO:
			cab.rotation.y = atan2(heading.x, heading.y)
		cab.get_node("Box").visible = lorry.loaded


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
