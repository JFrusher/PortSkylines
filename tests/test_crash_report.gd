extends SceneTree
## The crash reporter: an error raises its flag, a warning does not, and a
## report holds the log, a loadable save and the content hash.
## godot --headless --script res://tests/test_crash_report.gd

var _failures := 0


func _initialize() -> void:
	var reporter := CrashReporter.new()
	var no_trace: Array[ScriptBacktrace] = []
	# Called directly: a real push_error would print an ERROR line, which CI treats as a failure.
	reporter._log_error("f", "file.gd", 1, "code", "", false, Logger.ERROR_TYPE_WARNING, no_trace)
	_expect(reporter.errored, false, "a warning does not ask for a report")
	reporter._log_error("f", "file.gd", 1, "code", "", false, Logger.ERROR_TYPE_SCRIPT, no_trace)
	_expect(reporter.errored, true, "a script error asks for a report")
	var sim := PortSim.new(3)
	sim.tick()
	var dir := CrashReporter.write(sim)
	_expect(dir.begins_with(CrashReporter.REPORTS), true, "the report goes in user://reports")
	_expect(SaveFile.load_from(dir + "/save.bin").get("sim") is PortSim, true, "the report's save loads")
	var info := FileAccess.get_file_as_string(dir + "/report.txt")
	_expect(info.contains("Content hash: %x" % hash(var_to_bytes(sim.rules))), true, "the report names the content hash")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
