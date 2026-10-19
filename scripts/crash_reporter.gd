class_name CrashReporter
extends Logger
## Notices the first engine or script error so the game can write a report:
## the log, a save and the game data's hash, in user://reports/. Godot may
## call a logger from any thread, so this only raises a flag; the main
## thread writes the report.

const REPORTS := "user://reports"

var errored := false


func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != ERROR_TYPE_WARNING:
		errored = true


## Writes a report of `sim` into a new folder under REPORTS and returns the
## folder, or "" when it could not be made.
static func write(sim: PortSim) -> String:
	var dir := "%s/%s" % [REPORTS, Time.get_datetime_string_from_system().replace(":", "-")]
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	# Godot's own log of this run, when file logging is on (the default on desktop).
	var log_path: String = ProjectSettings.get_setting("debug/file_logging/log_path")
	if FileAccess.file_exists(log_path):
		DirAccess.copy_absolute(log_path, dir + "/godot.log")
	SaveFile.save(dir + "/save.bin", sim)
	var info := FileAccess.open(dir + "/report.txt", FileAccess.WRITE)
	info.store_line("Game version: %s" % ProjectSettings.get_setting("application/config/version"))
	info.store_line("Godot: %s" % Engine.get_version_info().string)
	info.store_line("Content hash: %x" % hash(var_to_bytes(sim.rules)))
	info.store_line("Day %d, tick %d" % [sim.clock.game_day(), sim.clock.ticks])
	return dir
