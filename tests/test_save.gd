extends SceneTree
## Headless tests for SaveFile and the committed save fixtures.
## godot --headless --script res://tests/test_save.gd

var _failures := 0


func _initialize() -> void:
	_test_save_load_save_is_identical()
	_test_bad_files_are_refused()
	_test_every_fixture_loads()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_save_load_save_is_identical() -> void:
	var sim := PortSim.new(3)
	sim.apply({"op": "build", "kind": PortMap.Tile.QUAY, "cell": Vector2i(12, 3)})
	for i in 500:
		sim.tick()
	_expect(SaveFile.save("user://a.bin", sim), "", "save")
	var loaded := SaveFile.load_from("user://a.bin")
	_expect(loaded.has("sim"), true, "load (%s)" % loaded.get("error", ""))
	_expect(SaveFile.save("user://b.bin", loaded.sim), "", "save again")
	_expect(FileAccess.get_file_as_bytes("user://b.bin"), FileAccess.get_file_as_bytes("user://a.bin"), "save -> load -> save gives identical bytes")


func _test_bad_files_are_refused() -> void:
	var file := FileAccess.open("user://future.bin", FileAccess.WRITE)
	file.store_buffer(SaveFile.MAGIC.to_ascii_buffer())
	file.store_var({"version": 999, "sim": {}}, false)
	file.close()
	_expect(SaveFile.load_from("user://future.bin").get("error", "").contains("newer version"), true, "a save from a newer version is refused")
	file = FileAccess.open("user://junk.bin", FileAccess.WRITE)
	file.store_string("not a save")
	file.close()
	_expect(SaveFile.load_from("user://junk.bin").get("error", "").contains("not a Port Skylines save"), true, "junk is refused")
	_expect(SaveFile.load_from("user://missing.bin").has("error"), true, "a missing file is refused")


func _test_every_fixture_loads() -> void:
	var fixtures := Array(DirAccess.get_files_at("res://tests/fixtures")).filter(func(f: String) -> bool: return f.begins_with("save_v") and f.ends_with(".bin"))
	_expect(fixtures.size() >= SaveFile.VERSION, true, "a fixture exists for every save version (%s)" % [fixtures])
	for name: String in fixtures:
		var loaded := SaveFile.load_from("res://tests/fixtures/" + name)
		_expect(loaded.has("sim"), true, "%s loads (%s)" % [name, loaded.get("error", "")])
		if loaded.has("sim"):
			var sim: PortSim = loaded.sim
			for i in 100:
				sim.tick()
			_expect(sim.clock.ticks > 100, true, "%s plays on after loading" % name)
