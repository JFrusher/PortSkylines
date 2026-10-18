class_name WorldView
extends Node3D
## Draws the sim as a small 3D model port. Reads PortSim every frame and
## never changes it.

const TILE_HEIGHT := {PortMap.Tile.ROAD: 0.04, PortMap.Tile.QUAY: 0.25, PortMap.Tile.YARD: 0.08}
const TILE_COLOR := {
	PortMap.Tile.ROAD: Color(0.2, 0.2, 0.22),
	PortMap.Tile.QUAY: Color(0.62, 0.6, 0.55),
	PortMap.Tile.YARD: Color(0.45, 0.45, 0.43),
}
const BOX_HEIGHT := 0.3
const BOX_COLOR := Color(0.85, 0.4, 0.15)
const SEA_START := -18.0  # where ships appear, west of the map

var sim: PortSim
## How far play has moved from the last tick towards the next, 0 to 1.
var alpha := 1.0

var _drawn_version := -1
var _tiles := {}  # Vector2i -> MeshInstance3D
var _stacks := {}  # Vector2i -> MeshInstance3D
var _ships := {}  # PortSim.Ship -> Node3D
var _lorries := {}  # PortSim.Lorry -> Node3D
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


func show_hover(cell: Vector2i, ok: bool) -> void:
	_hover.visible = sim.map.in_bounds(cell)
	_hover.position = Vector3(cell.x + 0.5, 0.3, cell.y + 0.5)
	(_hover.mesh.material as StandardMaterial3D).albedo_color = Color(0.3, 1, 0.4, 0.5) if ok else Color(1, 0.25, 0.2, 0.5)


func _process(_dt: float) -> void:
	if sim.map.version != _drawn_version:
		_draw_tiles()
	_draw_stacks()
	_draw_ships()
	_draw_lorries()


func _draw_tiles() -> void:
	_drawn_version = sim.map.version
	var wanted := {}
	for kind: int in TILE_HEIGHT:
		for cell in sim.map.cells_of(kind):
			wanted[cell] = kind
	for cell: Vector2i in _tiles.keys():
		if wanted.get(cell, -1) != _tiles[cell].get_meta("kind"):
			_tiles[cell].queue_free()
			_tiles.erase(cell)
	for cell: Vector2i in wanted:
		if cell in _tiles:
			continue
		var kind: int = wanted[cell]
		var tile := _box(Vector3(1, TILE_HEIGHT[kind], 1), TILE_COLOR[kind])
		tile.position = Vector3(cell.x + 0.5, TILE_HEIGHT[kind] / 2.0, cell.y + 0.5)
		tile.set_meta("kind", kind)
		add_child(tile)
		_tiles[cell] = tile


func _draw_stacks() -> void:
	for cell: Vector2i in _stacks.keys():
		if sim.stacked.get(cell, 0) == 0:
			_stacks[cell].queue_free()
			_stacks.erase(cell)
	for cell: Vector2i in sim.stacked:
		var count: int = sim.stacked[cell]
		if count == 0:
			continue
		if cell not in _stacks:
			_stacks[cell] = _box(Vector3(0.8, BOX_HEIGHT, 0.4), BOX_COLOR)
			add_child(_stacks[cell])
		_stacks[cell].scale.y = count
		_stacks[cell].position = Vector3(cell.x + 0.5, 0.08 + count * BOX_HEIGHT / 2.0, cell.y + 0.5)


func _draw_ships() -> void:
	_forget_gone(_ships, sim.ships)
	for ship: PortSim.Ship in sim.ships:
		if ship not in _ships:
			var hull := _box(Vector3(1.4, 0.6, 4.5), Color(0.15, 0.2, 0.35))
			var cargo := _box(Vector3(1.0, 0.6, 3.6), BOX_COLOR)
			cargo.name = "Cargo"
			cargo.position.y = 0.6
			hull.add_child(cargo)
			add_child(hull)
			_ships[ship] = hull
		var hull: Node3D = _ships[ship]
		var sail := lerpf(ship.prev_sail, ship.sail, alpha)
		var x := lerpf(SEA_START, ship.berth.x + 0.5, ease(sail, -2.0))
		hull.position = Vector3(x, -0.05, ship.berth.y + 0.5)
		var cargo: Node3D = hull.get_node("Cargo")
		cargo.visible = ship.boxes > 0
		cargo.scale.y = maxf(ship.boxes / float(PortSim.SHIP_BOXES), 0.01)


func _draw_lorries() -> void:
	_forget_gone(_lorries, sim.lorries)
	for lorry: PortSim.Lorry in sim.lorries:
		if lorry not in _lorries:
			var cab := _box(Vector3(0.3, 0.25, 0.6), Color(0.85, 0.85, 0.8))
			var box := _box(Vector3(0.28, 0.22, 0.5), BOX_COLOR)
			box.name = "Box"
			box.position.y = 0.23
			cab.add_child(box)
			add_child(cab)
			_lorries[lorry] = cab
		var cab: Node3D = _lorries[lorry]
		var at := lorry.position(alpha)
		cab.position = Vector3(at.x + 0.5, 0.17, at.y + 0.5)
		var i := mini(int(lorry.t), lorry.path.size() - 1)
		var heading := Vector2(lorry.path[mini(i + 1, lorry.path.size() - 1)] - lorry.path[i])
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
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node
