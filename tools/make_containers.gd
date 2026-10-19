extends SceneTree
## Writes assets/container_20ft.glb and container_40ft.glb: corrugated
## sides, doors at one end and corner castings, white so the game can tint
## them in a line's livery.
## godot --headless --script res://tools/make_containers.gd
## shortcut: stands in for Blender sources in art/ until the art pass models the containers; delete it then.

const HEIGHT := 0.28
const WIDTH := 0.3
const RIB := 0.03


func _initialize() -> void:
	for teu: int in [1, 2]:
		var length := 0.38 if teu == 1 else 0.78
		var scene := Node3D.new()
		scene.name = "Container%dft" % (teu * 20)
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = _container(length)
		scene.add_child(body)
		body.owner = scene
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var err := gltf.append_from_scene(scene, state)
		if err == OK:
			err = gltf.write_to_filesystem(state, "res://assets/container_%dft.glb" % (teu * 20))
		print("container_%dft.glb: %s" % [teu * 20, error_string(err)])
		scene.free()
	quit()


## A container `length` long (along X), centred on the origin.
func _container(length: float) -> Mesh:
	var boxes: Array = [[Vector3(length, HEIGHT, WIDTH), Vector3.ZERO]]
	# Corrugation: ribs standing proud of both long sides and the roof.
	var ribs := floori((length - 0.04) / RIB)
	for i in ribs:
		var x := -length / 2.0 + 0.02 + (i + 0.5) * (length - 0.04) / ribs
		for z: float in [-1.0, 1.0]:
			boxes.append([Vector3(RIB * 0.5, HEIGHT - 0.03, 0.006), Vector3(x, 0, z * (WIDTH / 2.0 + 0.003))])
		boxes.append([Vector3(RIB * 0.5, 0.004, WIDTH - 0.03), Vector3(x, HEIGHT / 2.0 + 0.002, 0)])
	# Door bars at the +X end, and the eight corner castings.
	for z: float in [-0.08, -0.03, 0.03, 0.08]:
		boxes.append([Vector3(0.006, HEIGHT - 0.04, 0.008), Vector3(length / 2.0 + 0.003, 0, z)])
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				boxes.append([Vector3(0.02, 0.02, 0.02), Vector3(x * (length / 2.0 - 0.005), y * (HEIGHT / 2.0 - 0.005), z * (WIDTH / 2.0 - 0.005))])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in boxes:
		var box := BoxMesh.new()
		box.size = part[0]
		var arrays := box.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			tool.set_normal(normals[index])
			tool.add_vertex(vertices[index] + part[1])
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 0.7
	tool.set_material(material)
	return tool.commit()
