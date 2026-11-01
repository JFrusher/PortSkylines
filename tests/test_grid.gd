extends SceneTree
## Headless tests for the 4 m grid.
## godot --headless --script res://tests/test_grid.gd

var _failures := 0


func _initialize() -> void:
	var site: Dictionary = Content.base().site
	_expect(Grid.size(site), Vector2i(600, 600), "the base site is 600 cells a side")
	_expect(Grid.cells(300), 75, "300 m is 75 cells")
	for metres: int in [0, 4, 300, 2400]:
		_expect(Grid.metres(Grid.cells(metres)), metres, "%d m round-trips through cells" % metres)
	_expect(Grid.centre(Vector2i(0, 0)), Vector3(2, 0, 2), "a cell's centre is half a cell in")
	_expect(Grid.centre(Vector2i(3, 1)), Vector3(14, 0, 6), "cells step by 4 m")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
