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
	_expect(_error_for({"fee_per_box": "lots"}), "rules.json: fee_per_box: must be a number", "a wrong type names the key")
	_expect(_error_for({"ship_boxes": 12.5}), "rules.json: ship_boxes: must be a whole number", "an int key refuses fractions")
	_expect(_error_for({"colour": 1}), "rules.json: colour: unknown key", "an unknown key is refused")
	for key: String in ["ship_interval_minutes", "ship_boxes", "sail_seconds", "crane_minutes", "lorry_interval_minutes", "lorry_speed"]:
		for value: int in [0, -1]:
			_expect(_error_for({key: value}), "rules.json: %s: must be greater than zero" % key, "%s refuses %d" % [key, value])
		_expect(_error_for({key: 1}), "", "%s accepts a positive whole number" % key)
	_expect(_error_for({"sail_seconds": 0.5}), "", "a positive fractional duration is valid")
	_expect(_error_for({"first_ship_minutes": 0}), "", "the first ship can arrive immediately")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Loads the base rules with `changes` applied (null removes a key) and
## returns the loader's error. The file is named rules.json, like the real one.
func _error_for(changes: Dictionary) -> String:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Content.BASE_DIR.path_join("rules.json")))
	for key: String in changes:
		if changes[key] == null:
			rules.erase(key)
		else:
			rules[key] = changes[key]
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(DIR.path_join("rules.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(rules))
	file.close()
	return Content.load_dir(DIR).get("error", "")
