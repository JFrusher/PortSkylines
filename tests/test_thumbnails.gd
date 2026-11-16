extends SceneTree
## Every item the build menu offers has its thumbnail, rendered by
## tools/make_thumbnails.gd.
## godot --headless --script res://tests/test_thumbnails.gd

const Thumbnails := preload("res://tools/make_thumbnails.gd")

var _failures := 0


func _initialize() -> void:
	for job: Dictionary in Thumbnails.jobs(Content.base()):
		var path := "res://ui/thumbnails/%s.png" % job.key
		if not ResourceLoader.exists(path):
			_failures += 1
			printerr("FAIL no thumbnail for %s: run tools/make_thumbnails.gd" % job.key)
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)
