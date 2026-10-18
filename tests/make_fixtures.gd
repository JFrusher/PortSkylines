extends SceneTree
## Writes tests/fixtures/save_v<VERSION>.bin from a busy port. Run once per
## save version and commit the file; older fixtures are never regenerated.
## godot --headless --script res://tests/make_fixtures.gd


func _initialize() -> void:
	var sim := PortSim.new(1)
	var row := sim.map.entry.y
	for x in range(sim.map.sea_width + 1, sim.map.entry.x):
		sim.apply({"op": "build", "kind": PortMap.Tile.ROAD, "cell": Vector2i(x, row)})
	for y in range(row - 6, row + 6):
		sim.apply({"op": "build", "kind": PortMap.Tile.QUAY, "cell": Vector2i(sim.map.sea_width, y)})
	for y: int in [row - 1, row]:
		sim.apply({"op": "place_crane", "cell": Vector2i(sim.map.sea_width, y)})
	sim.apply({"op": "build", "kind": PortMap.Tile.YARD, "cell": Vector2i(sim.map.sea_width + 2, row - 1)})
	# 30 game minutes: a ship alongside, boxes stacked and lorries on the road.
	for i in roundi(30 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	var path := "res://tests/fixtures/save_v%d.bin" % SaveFile.VERSION
	var err := SaveFile.save(path, sim)
	print(err if err else "wrote %s (ships %d, lorries %d)" % [path, sim.ships.size(), sim.lorries.size()])
	quit(1 if err else 0)
