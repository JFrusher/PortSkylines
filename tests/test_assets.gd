extends SceneTree
## Every model in assets/ imports with at least one LOD, as the import
## defaults in project.godot ask.
## godot --headless --script res://tests/test_assets.gd

var _failures := 0


func _initialize() -> void:
	var models := Array(DirAccess.get_files_at("res://assets")).filter(func(f: String) -> bool: return f.ends_with(".glb"))
	_expect(models.is_empty(), false, "assets/ has models")
	for name: String in models:
		var scene: Node = load("res://assets/" + name).instantiate()
		for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D"):
			var surface := RenderingServer.mesh_get_surface(node.mesh.get_rid(), 0)
			_expect(surface.get("lods", []).size() > 0, true, "%s's %s has LODs" % [name, node.name])
		scene.free()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
