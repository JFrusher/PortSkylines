extends SceneTree
## Berths: fixed-size quays placed by clicking the coast, with crane spots.
## godot --headless --script res://tests/test_berths.gd

var _failures := 0


func _initialize() -> void:
	var sim := PortSim.new(1)
	var money := sim.money
	_expect(sim.apply({"op": "build_berth", "kind": "feeder", "y": 250}), "", "a feeder berth goes on the coast")
	_expect(sim.areas.list.size(), 1, "it brings one apron")
	var apron: int = sim.areas.list.keys()[0]
	var cells := sim.areas.cells(apron)
	_expect(cells.size(), 50 * 10, "the apron is the berth's 50 cells long, its full depth")
	_expect(cells.all(func(c: Vector2i) -> bool: return c.y >= 225 and c.y < 275 and c.x >= 75 and c.x < 85), true, "centred on the clicked row, from the water to the road")
	_expect(sim.roads.segments.size(), 1, "and one road along its back")
	_expect(money - sim.money, sim.road_price(Vector2i(85, 224), Vector2i(85, 275), PortSim.BERTH_ROAD) + 500 * 3, "it costs its road and its apron")
	_expect(AreaFlow.crane_spots(sim, apron), [12, 37] as Array[int], "two crane spots, evenly along it")
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": apron, "along": 20}), "Cranes stand at the berth's crane spots", "a crane off a spot is refused")
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": apron, "along": 37}), "", "a crane on a spot stands")
	_expect(sim.build_berth_error("feeder", 260), "Something is already built here", "a berth over another is refused")
	_expect(sim.apply({"op": "build_berth", "kind": "feeder", "y": 301}), "", "a berth end to end with the first")
	_expect(sim.roads.segments.size(), 2, "its road joins the first's at a shared end")
	_expect(PortSim.new(1).build_berth_error("neopanamax", 300), "Unlocked at milestone 4: 1500 TEU across the quay", "the neopanamax berth waits for the hub milestone")
	_expect(PortSim.new(1).build_berth_error("panamax", 300), "Unlocked at milestone 3: 600 TEU across the quay", "the panamax berth waits for its milestone")
	_expect(sim.build_berth_error("feeder", 600), "Buy this land first", "a berth on unbought land is refused")
	sim.apply({"op": "build_road", "from": Vector2i(80, 420), "to": Vector2i(120, 420), "type": "terminal_1_1"})
	_expect(sim.build_berth_error("feeder", 420) != "", true, "a berth across a road is refused")

	# A port with no lines gets an offer at the first check, whatever the dice.
	for seed in 20:
		var contracts := Contracts.new(sim.rules)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		_expect(contracts.offer(rng, 0.0, 1, func(_kind: String) -> bool: return true, 1.0).is_empty(), false, "a first offer at the first check (seed %d)" % seed)
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(got: Variant, want: Variant, what: String) -> void:
	if got != want:
		_failures += 1
		print("FAIL %s: got %s, want %s" % [what, got, want])
