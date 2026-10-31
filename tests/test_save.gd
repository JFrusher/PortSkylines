extends SceneTree
## Headless tests for SaveFile and the committed save fixtures.
## godot --headless --script res://tests/test_save.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_save_load_save_is_identical()
	_test_bad_files_are_refused()
	_test_save_replaces_existing()
	_test_failed_save_preserves_destination()
	_test_malformed_payloads_are_refused()
	_test_every_fixture_loads_or_is_refused()
	_test_area_flow_round_trips()
	_test_a_removed_apron_saves()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_save_load_save_is_identical() -> void:
	var sim := AreaPort.base()
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


## Saves from before roads ran on grid lines are refused with a reason;
## every later one loads and plays on.
func _test_every_fixture_loads_or_is_refused() -> void:
	var fixtures := Array(DirAccess.get_files_at("res://tests/fixtures")).filter(func(f: String) -> bool: return f.begins_with("save_v") and f.ends_with(".bin"))
	_expect(fixtures.size() >= SaveFile.VERSION, true, "a fixture exists for every save version (%s)" % [fixtures])
	for name: String in fixtures:
		var loaded := SaveFile.load_from("res://tests/fixtures/" + name)
		if name.trim_prefix("save_v").to_int() < SaveFile.FIRST:
			_expect(loaded.get("error", "").contains("saved before terminals were painted on the map"), true, "%s is refused with the reason (%s)" % [name, loaded.get("error", "")])
			continue
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
	sim.ledger.post("moves", 123)
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
	sim.ledger.post("moves", 1)
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
	for section: Array in [[], ["ledger"], ["contracts"], ["finance"], ["ships", 0], ["cranes", 0], ["vehicles", 0], ["roads"], ["areas"], ["roads", "segments", 1], ["areas", "list", 1], ["machines"]]:
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
	var unknown_apron := valid.duplicate(true)
	unknown_apron.ships[0].apron = 99
	_expect_payload_refused(unknown_apron, "a ship at a quay apron that isn't there")
	var adrift := valid.duplicate(true)
	adrift.ships[0].apron = 0
	_expect_payload_refused(adrift, "a ship out of anchorage at no apron")
	var floating := valid.duplicate(true)
	floating.cranes[0].apron = 99
	_expect_payload_refused(floating, "a crane on a quay apron that isn't there")
	for value: float in [NAN, INF, -INF]:
		var bad := valid.duplicate(true)
		bad.vehicles[0].t = value
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


## A port mid-discharge on roads and areas saves and loads to the same state,
## then plays on the same as one never saved.
func _test_area_flow_round_trips() -> void:
	var sim: PortSim = AreaPort.working_terminal(3, 2)
	for i in 2000:
		sim.tick()
		if not (sim.vehicles.is_empty() or sim.machine_jobs.is_empty()):
			break
	_expect(sim.vehicles.is_empty() or sim.machine_jobs.is_empty(), false, "tractors and machines are busy at save time")
	_expect(SaveFile.save("user://area_flow.bin", sim), "", "a port mid-discharge saves")
	var loaded: PortSim = SaveFile.load_from("user://area_flow.bin").sim
	_expect(loaded.to_dict(), sim.to_dict(), "and loads to the same state")
	_expect([loaded.exports, sim.exports], [2, 2], "with its exports counted again")
	for i in 300:
		sim.tick()
		loaded.tick()
	_expect(loaded.state_hash(), sim.state_hash(), "then plays on the same")


## Bulldozing a quay apron with a ship alongside: the port saves and loads.
func _test_a_removed_apron_saves() -> void:
	var sim: PortSim = AreaPort.working_terminal(5)
	_expect(sim.apply({"op": "remove_area", "id": 1}), "", "the apron is removed with a ship alongside")
	_expect(SaveFile.save("user://removed.bin", sim), "", "the port saves")
	var loaded := SaveFile.load_from("user://removed.bin")
	_expect(loaded.has("sim"), true, "and loads (%s)" % loaded.get("error", ""))
