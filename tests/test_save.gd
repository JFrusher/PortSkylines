extends SceneTree
## Headless tests for SaveFile and the committed save fixtures.
## godot --headless --script res://tests/test_save.gd

var _failures := 0


func _initialize() -> void:
	_test_save_load_save_is_identical()
	_test_bad_files_are_refused()
	_test_save_replaces_existing()
	_test_failed_save_preserves_destination()
	_test_malformed_payloads_are_refused()
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


func _test_save_replaces_existing() -> void:
	var path := "user://replace.bin"
	var sim := PortSim.new(7)
	_expect(SaveFile.save(path, sim), "", "initial save")
	sim.money += 123
	_expect(SaveFile.save(path, sim), "", "replace an existing save")
	var loaded := SaveFile.load_from(path)
	_expect(loaded.has("sim"), true, "replacement loads")
	if loaded.has("sim"):
		_expect(loaded.sim.state_hash(), sim.state_hash(), "replacement contains the new state")
	_expect(FileAccess.file_exists(path + ".tmp"), false, "successful save leaves no temporary file")
	_write_payload("user://store_var.bin", {"version": SaveFile.VERSION, "sim": sim.to_dict()})
	_expect(FileAccess.get_file_as_bytes(path), FileAccess.get_file_as_bytes("user://store_var.bin"), "save bytes preserve the store_var format")


func _test_failed_save_preserves_destination() -> void:
	var path := "user://preserve.bin"
	var sim := PortSim.new()
	_expect(SaveFile.save(path, sim), "", "save before a failed replacement")
	var before := FileAccess.get_file_as_bytes(path)
	# A directory at the temporary path prevents opening it for writing.
	DirAccess.make_dir_absolute(path + ".tmp")
	sim.money += 1
	_expect(SaveFile.save(path, sim).is_empty(), false, "temporary open failure is reported")
	_expect(FileAccess.get_file_as_bytes(path), before, "open failure preserves the existing save")
	DirAccess.remove_absolute(path + ".tmp")
	# A directory at the destination prevents the final rename.
	var destination := "user://save_directory"
	DirAccess.make_dir_absolute(destination)
	var marker := destination.path_join("keep.bin")
	_write_payload(marker, {"keep": true})
	var marker_bytes := FileAccess.get_file_as_bytes(marker)
	_expect(SaveFile.save(destination, sim).is_empty(), false, "replacement failure is reported")
	_expect(FileAccess.get_file_as_bytes(marker), marker_bytes, "replacement failure preserves the destination")
	_expect(FileAccess.file_exists(destination + ".tmp"), false, "replacement failure removes the temporary file")
	DirAccess.remove_absolute(marker)
	DirAccess.remove_absolute(destination)


func _test_malformed_payloads_are_refused() -> void:
	var sim := PortSim.new()
	sim.ships.append(PortSim.Ship.new(Vector2i(12, 24), Vector2i(11, 24), 12))
	var route: Array[Vector2i] = [sim.map.entry, sim.map.entry + Vector2i.LEFT]
	sim.lorries.append(PortSim.Lorry.new(route, Vector2i(14, 23)))
	var valid := sim.to_dict()
	_write_payload("user://valid.bin", {"version": SaveFile.VERSION, "sim": valid})
	_expect(SaveFile.load_from("user://valid.bin").has("sim"), true, "complete ship and lorry payload loads")
	# Exercise every field consumed by each deserialiser, including fields in
	# nonempty traffic arrays, through the public load path.
	for section: Array in [[], ["map"], ["ships", 0], ["lorries", 0]]:
		var original := _section(valid, section)
		for key: String in original:
			var missing := valid.duplicate(true)
			_section(missing, section).erase(key)
			_expect_payload_refused(missing, "missing %s.%s" % [section, key])
			for wrong: Variant in [null, 0 if original[key] is String else "wrong"]:
				var mistyped := valid.duplicate(true)
				_section(mistyped, section)[key] = wrong
				_expect_payload_refused(mistyped, "mistyped %s.%s" % [section, key])
	for collection: String in ["ships", "lorries"]:
		var bad := valid.duplicate(true)
		bad[collection] = [42]
		_expect_payload_refused(bad, "non-dictionary in %s" % collection)
	for collection: String in ["stacked", "claimed"]:
		for counts: Dictionary in [{"bad key": 1}, {Vector2i(14, 23): "bad count"}]:
			var bad := valid.duplicate(true)
			bad[collection] = counts
			_expect_payload_refused(bad, "mistyped entries in %s" % collection)
	for route_value: Array in [[], ["bad cell"], [Vector2(1, 2)]]:
		var bad := valid.duplicate(true)
		bad.lorries[0].path = route_value
		_expect_payload_refused(bad, "invalid route %s" % [route_value])
	for size: Vector2i in [Vector2i.ZERO, Vector2i(-1, 48), Vector2i(64, 49)]:
		var bad := valid.duplicate(true)
		bad.map.size = size
		_expect_payload_refused(bad, "invalid map dimensions %s" % size)
	var bad_tiles := valid.duplicate(true)
	bad_tiles.map.tiles[0] = 255
	_expect_payload_refused(bad_tiles, "unknown tile kind")
	for value: float in [NAN, INF, -INF]:
		var bad := valid.duplicate(true)
		bad.lorries[0].t = value
		_expect_payload_refused(bad, "non-finite vehicle position")


func _section(data: Dictionary, keys: Array) -> Dictionary:
	var value: Variant = data
	for key: Variant in keys:
		value = value[key]
	return value


func _expect_payload_refused(sim: Dictionary, what: String) -> void:
	_write_payload("user://malformed.bin", {"version": SaveFile.VERSION, "sim": sim})
	var loaded := SaveFile.load_from("user://malformed.bin")
	_expect(loaded.get("error", "").contains("not a Port Skylines save"), true, what)


func _write_payload(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(SaveFile.MAGIC.to_ascii_buffer())
	file.store_var(data, false)
	file.close()
