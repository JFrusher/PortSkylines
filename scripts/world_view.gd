class_name WorldView
extends Node3D
## Draws the sim as a small 3D model port. Reads PortSim every frame and
## never changes it.

const TILE_HEIGHT := {PortMap.Tile.ROAD: 0.04, PortMap.Tile.QUAY: 0.25, PortMap.Tile.YARD: 0.08, PortMap.Tile.GATE: 0.5}
const TILE_COLOR := {
	PortMap.Tile.ROAD: Color(0.2, 0.2, 0.22),
	PortMap.Tile.QUAY: Color(0.62, 0.6, 0.55),
	PortMap.Tile.YARD: Color(0.45, 0.45, 0.43),
	PortMap.Tile.GATE: Color(0.2, 0.45, 0.7),
}
const BOX_HEIGHT := 0.3
const LANE_OFFSET := 0.22
const BOX_COLOR := Color(0.85, 0.4, 0.15)
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
var _stacks := ChunkedMeshes.new()
var _stack_mesh := _box_mesh(Vector3(0.8, BOX_HEIGHT, 0.4), BOX_COLOR)
## Chunks that held stacks last frame, so emptied ones get cleared.
var _stack_chunks := {}
# shortcut: ships and vehicles are one node each, fine under ~100; MultiMesh them in M5.
var _ships := {}  # PortSim.Ship -> Node3D
var _vehicles := {}  # Vehicle -> Node3D
var _cranes := {}  # PortSim.Crane -> Node3D
var _hover := _box(Vector3(1, 0.06, 1), Color(1, 1, 1, 0.5))


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


func show_hover(cell: Vector2i, ok: bool) -> void:
	_hover.visible = sim.map.in_bounds(cell)
	_hover.position = Vector3(cell.x + 0.5, 0.3, cell.y + 0.5)
	(_hover.mesh.material as StandardMaterial3D).albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


func _process(_dt: float) -> void:
	if sim.map.version != _drawn_version:
		_draw_tiles()
	_draw_stacks()
	_draw_ships()
	_draw_cranes()
	_draw_vehicles()


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
				dirty[ChunkedMeshes.chunk_of(Vector2i(x, y))] = true
	for chunk: Vector2i in dirty:
		var by_kind := {}
		for kind: int in TILE_HEIGHT:
			by_kind[kind] = [] as Array[Transform3D]
		for y in range(chunk.y * ChunkedMeshes.CHUNK, mini((chunk.y + 1) * ChunkedMeshes.CHUNK, map.size.y)):
			for x in range(chunk.x * ChunkedMeshes.CHUNK, mini((chunk.x + 1) * ChunkedMeshes.CHUNK, map.size.x)):
				var kind := map.tile(Vector2i(x, y))
				if kind in TILE_HEIGHT:
					by_kind[kind].append(Transform3D(Basis(), Vector3(x + 0.5, TILE_HEIGHT[kind] / 2.0, y + 0.5)))
		for kind: int in by_kind:
			_tiles.show_part(Vector3i(chunk.x, chunk.y, kind), _tile_meshes[kind], by_kind[kind])


func _draw_stacks() -> void:
	var by_chunk := {}
	for chunk: Vector2i in _stack_chunks:
		by_chunk[chunk] = [] as Array[Transform3D]
	for cell: Vector2i in sim.yard.stacks:
		var count := sim.yard.count(cell)
		if count == 0:
			continue
		var chunk := ChunkedMeshes.chunk_of(cell)
		if chunk not in by_chunk:
			by_chunk[chunk] = [] as Array[Transform3D]
		by_chunk[chunk].append(Transform3D(Basis.from_scale(Vector3(1, count, 1)), Vector3(cell.x + 0.5, 0.08 + count * BOX_HEIGHT / 2.0, cell.y + 0.5)))
	_stack_chunks.clear()
	for chunk: Vector2i in by_chunk:
		_stacks.show_part(chunk, _stack_mesh, by_chunk[chunk])
		if not by_chunk[chunk].is_empty():
			_stack_chunks[chunk] = true


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


## A tower on the quay tile with a boom reaching out over the water.
func _draw_cranes() -> void:
	_forget_gone(_cranes, sim.cranes)
	for crane: PortSim.Crane in sim.cranes:
		if crane in _cranes:
			continue
		var tower := _box(Vector3(0.7, 3.0, 0.7), Color(0.85, 0.3, 0.2))
		tower.position = Vector3(crane.cell.x + 0.5, 1.5, crane.cell.y + 0.5)
		var water := sim.map.neighbor(crane.cell, PortMap.Tile.WATER) - crane.cell
		var boom := _box(Vector3(maxf(absf(water.x) * 3.5, 0.3), 0.3, maxf(absf(water.y) * 3.5, 0.3)), Color(0.85, 0.3, 0.2))
		boom.position = Vector3(water.x * 1.2, 1.4, water.y * 1.2)
		tower.add_child(boom)
		add_child(tower)
		_cranes[crane] = tower


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
		var at := lorry.position(alpha)
		var i := mini(int(lorry.t), lorry.path.size() - 1)
		var heading := Vector2(lorry.path[mini(i + 1, lorry.path.size() - 1)] - lorry.path[i])
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
