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
	_test_malformed_v1_is_refused()
	_test_v2_cash_moves_into_the_ledger()
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
	sim.ledger.post("gate_fees", 123)
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
	sim.ledger.post("gate_fees", 1)
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
	# A busy port, so ships, cranes and vehicles all have entries to break.
	var sim: PortSim = SaveFile.load_from("res://tests/fixtures/save_v%d.bin" % SaveFile.VERSION).sim
	for i in 40000:
		if not (sim.ships.is_empty() or sim.cranes.is_empty() or sim.vehicles.is_empty() or sim.get("_claimed").is_empty()):
			break
		sim.tick()
	var valid := sim.to_dict()
	_write_payload("user://valid.bin", {"version": SaveFile.VERSION, "sim": valid})
	_expect(valid.claimed.is_empty(), false, "a box is claimed at save time")
	_expect(SaveFile.load_from("user://valid.bin").has("sim"), true, "complete ship, crane, vehicle and claim payload loads")
	# Every field each deserialiser reads, through the public load path.
	for section: Array in [[], ["map"], ["yard"], ["ledger"], ["contracts"], ["ships", 0], ["cranes", 0], ["vehicles", 0]]:
		var original := _section(valid, section)
		for key: String in original:
			var missing := valid.duplicate(true)
			_section(missing, section).erase(key)
			_expect_payload_refused(missing, "missing %s.%s" % [section, key])
			for wrong: Variant in [null, 0 if original[key] is String else "wrong"]:
				var mistyped := valid.duplicate(true)
				_section(mistyped, section)[key] = wrong
				_expect_payload_refused(mistyped, "mistyped %s.%s" % [section, key])
	for collection: String in ["ships", "cranes", "vehicles"]:
		var bad := valid.duplicate(true)
		bad[collection] = [42]
		_expect_payload_refused(bad, "non-dictionary in %s" % collection)
	for claimed: Dictionary in [{"bad key": true}, {Vector2i(14, 23): true}, {7: "yes"}, {7: false}]:
		var bad := valid.duplicate(true)
		bad.claimed = claimed
		_expect_payload_refused(bad, "mistyped entries in claimed")
	for route_value: Array in [["bad cell"], [Vector2(1, 2)]]:
		var bad := valid.duplicate(true)
		bad.vehicles[0].path = route_value
		_expect_payload_refused(bad, "invalid route %s" % [route_value])
	var no_cells := valid.duplicate(true)
	no_cells.ships[0].cells = []
	_expect_payload_refused(no_cells, "a berthed ship with no cells")
	for size: Vector2i in [Vector2i.ZERO, Vector2i(-1, 48), Vector2i(64, 49)]:
		var bad := valid.duplicate(true)
		bad.map.size = size
		_expect_payload_refused(bad, "invalid map dimensions %s" % size)
	var bad_tiles := valid.duplicate(true)
	bad_tiles.map.tiles[0] = 255
	_expect_payload_refused(bad_tiles, "unknown tile kind")
	for value: float in [NAN, INF, -INF]:
		var bad := valid.duplicate(true)
		bad.vehicles[0].t = value
		_expect_payload_refused(bad, "non-finite vehicle position")


func _test_malformed_v1_is_refused() -> void:
	var v1: Dictionary = {"version": 1, "sim": {"delivered": 0, "stacked": {Vector2i(14, 23): 3}}}
	for stacked: Variant in [null, [], {"bad key": 1}, {Vector2i(14, 23): "bad count"}, {Vector2i(14, 23): -1}, {Vector2i(14, 23): 1000000}]:
		var bad := v1.duplicate(true)
		bad.sim.stacked = stacked
		_write_payload("user://bad_v1.bin", bad)
		_expect(SaveFile.load_from("user://bad_v1.bin").get("error", "").contains("not a Port Skylines save"), true, "v1 stacked %s is refused" % [stacked])


func _test_v2_cash_moves_into_the_ledger() -> void:
	var file := FileAccess.open("res://tests/fixtures/save_v2.bin", FileAccess.READ)
	file.get_buffer(SaveFile.MAGIC.length())
	var raw: Dictionary = file.get_var(false)
	var sim: PortSim = SaveFile.load_from("res://tests/fixtures/save_v2.bin").sim
	_expect([sim.money, sim.ledger.opened, sim.ledger.today_total()], [raw.sim.money, raw.sim.money, 0], "v2 cash opens the ledger")


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
