extends SceneTree
## Headless tests for the Content loader.
## godot --headless --script res://tests/test_content.gd

const DIR := "user://content_test"

var _failures := 0


func _initialize() -> void:
	var base := Content.base()
	_expect(base.start_money is int, true, "whole numbers load as ints")
	_expect(base.sail_seconds is float, true, "float keys load as floats")
	_expect(_error_for({"start_money": null}), DIR + ": missing \"start_money\"", "a missing key names the key")
	_expect(_error_for({"map": {"width": 64, "height": 48}}), "rules.json: map: missing \"sea_width\"", "a missing nested key names the path")
	_expect(_error_for({"start_money": "lots"}), "rules.json: start_money: must be a number", "a wrong type names the key")
	_expect(_error_for({"start_money": 6.5}), "rules.json: start_money: must be a whole number", "an int key refuses fractions")
	_expect(_error_for({"colour": 1}), "rules.json: colour: unknown key", "an unknown key is refused")
	_expect(base.ship_classes.feeder.length is int, true, "records under a \"*\" key are checked and typed")
	for key: String in ["sail_seconds", "lorry_interval_minutes", "export_lorry_interval_minutes", "lorry_speed", "give_up_seconds"]:
		for value: int in [0, -1]:
			_expect(_error_for({key: value}), "rules.json: %s: must be greater than zero" % key, "%s refuses %d" % [key, value])
		_expect(_error_for({key: 1}), "", "%s accepts a positive whole number" % key)
	_expect(_error_for({"sail_seconds": 0.5}), "", "a positive fractional duration is valid")
	_expect(_error_for({"import_dwell_minutes": 0}), "", "imports may leave at once")
	_expect(_error_for({"site": {"width": 2402, "height": 2400, "sea_width": 300}}), "site.width: must be a positive multiple of 4 m", "the site is whole grid cells")
	_expect(_error_for({"site": {"width": 2400, "height": 0, "sea_width": 300}}), "site.height: must be a positive multiple of 4 m", "the site has a size")
	var roads: Dictionary = Content.base().road_types.duplicate(true)
	roads.one_way.lorries = "yes"
	_expect(_error_for({"road_types": roads}, "roads.json"), "roads.json: road_types.one_way.lorries: must be true or false", "a true/false key refuses text")
	roads.one_way.lorries = true
	roads.one_way.forward = 0
	_expect(_error_for({"road_types": roads}, "roads.json"), "road_types.one_way: needs lanes, with at least as many forward as backward", "a road needs a lane")
	var lines: Dictionary = Content.base().lines.duplicate(true)
	lines.aurora.classes["cruise"] = 1
	_expect(_error_for({"lines": lines}, "lines.json"), "lines.aurora.classes: unknown ship class \"cruise\"", "a line can only sail known ship classes")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Copies the base data with `changes` applied to `file_name` (null removes a
## key) and returns the loader's error.
func _error_for(changes: Dictionary, file_name := "rules.json") -> String:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Content.BASE_DIR.path_join(file_name)))
	for key: String in changes:
		if changes[key] == null:
			rules.erase(key)
		else:
			rules[key] = changes[key]
	DirAccess.make_dir_recursive_absolute(DIR)
	for name: String in DirAccess.get_files_at(Content.BASE_DIR):
		if name.ends_with(".json") and name != file_name:
			var copy := FileAccess.open(DIR.path_join(name), FileAccess.WRITE)
			copy.store_string(FileAccess.get_file_as_string(Content.BASE_DIR.path_join(name)))
			copy.close()
	var file := FileAccess.open(DIR.path_join(file_name), FileAccess.WRITE)
	file.store_string(JSON.stringify(rules))
	file.close()
	return Content.load_dir(DIR).get("error", "")
