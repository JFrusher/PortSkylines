extends SceneTree
## Writes tests/fixtures/save_v<VERSION>.bin from a busy port. Run once per
## save version and commit the file; older fixtures are never regenerated.
## godot --headless --script res://tests/make_fixtures.gd

const AreaPort := preload("res://tests/area_port.gd")


func _initialize() -> void:
	# AreaPort.base's port with an export block too, so a ship is worked both ways.
	var sim := AreaPort.base()
	AreaPort.add_export_block(sim)
	# 30 game minutes: a ship alongside, boxes stacked and vehicles on the roads.
	for i in roundi(30 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	var path := "res://tests/fixtures/save_v%d.bin" % SaveFile.VERSION
	var err := SaveFile.save(path, sim)
	print(err if err else "wrote %s (ships %d, vehicles %d)" % [path, sim.ships.size(), sim.vehicles.size()])
	quit(1 if err else 0)
