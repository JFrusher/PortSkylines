extends SceneTree
## Writes tests/fixtures/save_v<VERSION>.bin from a busy port. Run once per
## save version and commit the file; older fixtures are never regenerated.
## godot --headless --script res://tests/make_fixtures.gd


const RandomPort := preload("res://tests/random_port.gd")


func _initialize() -> void:
	var sim := PortSim.new(1, RandomPort.quick())
	RandomPort.calls(sim)
	var row := sim.map.entry.y
	for x in range(sim.map.sea_width + 1, sim.map.entry.x):
		sim.apply({"op": "build", "kind": PortMap.Tile.GATE if x == sim.map.entry.x - 3 else PortMap.Tile.ROAD, "cell": Vector2i(x, row)})
	for y in range(row - 6, row + 6):
		sim.apply({"op": "build", "kind": PortMap.Tile.QUAY, "cell": Vector2i(sim.map.sea_width, y)})
		sim.apply({"op": "build", "kind": PortMap.Tile.ROAD, "cell": Vector2i(sim.map.sea_width + 1, y)})
	for y: int in [row - 1, row]:
		sim.apply({"op": "place_crane", "cell": Vector2i(sim.map.sea_width, y)})
	sim.apply({"op": "buy_tractors", "count": 6})
	for x in range(sim.map.sea_width + 3, sim.map.sea_width + 6):
		sim.apply({"op": "build", "kind": PortMap.Tile.YARD, "cell": Vector2i(x, row - 1)})
	# Roads on the 4 m grid, from v5: a crossing of a 2+2 and a 1+1 road.
	sim.apply({"op": "build_road", "from": Vector2i(100, 120), "to": Vector2i(140, 120), "type": "terminal_2_2"})
	sim.apply({"op": "build_road", "from": Vector2i(120, 100), "to": Vector2i(120, 140), "type": "terminal_1_1"})
	# 30 game minutes: a ship alongside, boxes stacked and lorries on the road.
	for i in roundi(30 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	var path := "res://tests/fixtures/save_v%d.bin" % SaveFile.VERSION
	var err := SaveFile.save(path, sim)
	print(err if err else "wrote %s (ships %d, vehicles %d)" % [path, sim.ships.size(), sim.vehicles.size()])
	quit(1 if err else 0)
