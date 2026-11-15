extends SceneTree
## Berths: fixed-size quays placed by clicking the coast, with crane spots.
## godot --headless --script res://tests/test_berths.gd

const RandomPort := preload("res://tests/random_port.gd")
var _failures := 0


func _initialize() -> void:
	var sim := PortSim.new(1, RandomPort.strait())
	var money := sim.money
	_expect(sim.apply({"op": "build_berth", "kind": "feeder", "cell": Vector2i(80, 250)}), "", "a feeder berth goes on the coast")
	_expect(sim.areas.list.size(), 1, "it brings one apron")
	var apron: int = sim.areas.list.keys()[0]
	var cells := sim.areas.cells(apron)
	_expect(cells.size(), 50 * 10, "the apron is the berth's 50 cells long, its full depth")
	_expect(cells.all(func(c: Vector2i) -> bool: return c.y >= 225 and c.y < 275 and c.x >= 75 and c.x < 85), true, "centred on the clicked row, from the water to the road")
	_expect(sim.roads.segments.size(), 1, "and one road along its back")
	_expect(money - sim.money, sim.road_price(sim.berth_plan("feeder", Vector2i(80, 250)).line[0], sim.berth_plan("feeder", Vector2i(80, 250)).line[1], PortSim.BERTH_ROAD) + 500 * sim.rules.area_types.quay_apron.cost_per_cell, "it costs its road and its apron")
	_expect(AreaFlow.crane_spots(sim, apron), [12, 37] as Array[int], "two crane spots, evenly along it")
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": apron, "along": 20}), "Cranes stand at the berth's crane spots", "a crane off a spot is refused")
	_expect(sim.apply({"op": "place_sts", "kind": "sts", "apron": apron, "along": 37}), "", "a crane on a spot stands")
	_expect(sim.build_berth_error("feeder", Vector2i(80, 260)), "Something is already built here", "a berth over another is refused")
	_expect(sim.apply({"op": "build_berth", "kind": "feeder", "cell": Vector2i(80, 300)}), "", "a berth end to end with the first")
	_expect(sim.roads.segments.size(), 2, "its road joins the first's at a shared end")
	_expect(PortSim.new(1, RandomPort.strait()).build_berth_error("neopanamax", Vector2i(80, 300)), "Unlocked at milestone 4: %d TEU across the quay" % sim.rules.milestones.hub.teu, "the neopanamax berth waits for the hub milestone")
	_expect(PortSim.new(1, RandomPort.strait()).build_berth_error("panamax", Vector2i(80, 300)), "Unlocked at milestone 3: %d TEU across the quay" % sim.rules.milestones.gateway.teu, "the panamax berth waits for its milestone")
	_expect(sim.build_berth_error("feeder", Vector2i(80, 450)), "Buy this land first", "a berth on unbought land is refused")
	sim.apply({"op": "build_road", "from": Vector2i(80, 420), "to": Vector2i(120, 420), "type": "terminal_1_1"})
	_expect(sim.build_berth_error("feeder", Vector2i(80, 420)) != "", true, "a berth across a road is refused")

	# A port with no lines gets an offer at the first check, whatever the dice.
	for seed in 20:
		var contracts := Contracts.new(sim.rules)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		_expect(contracts.offer(rng, 0.0, 1, func(_kind: String) -> bool: return true, 1.0).is_empty(), false, "a first offer at the first check (seed %d)" % seed)
	_test_berths_turn_to_the_coast()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(got: Variant, want: Variant, what: String) -> void:
	if got != want:
		_failures += 1
		print("FAIL %s: got %s, want %s" % [what, got, want])


## M10 step 21: on a coast off the grid a berth turns, in BERTH_TURN steps,
## to the angle that fills the least water, or to the one it is turned to;
## its apron, quay and a ship alongside face that way.
func _test_berths_turn_to_the_coast() -> void:
	var sim := PortSim.new(1, preload("res://bench/showcase_port.gd").rules(), true)
	for x in 3:
		for y in 3:
			if not sim.land.has(Vector2i(x, y)):
				sim.apply({"op": "buy_land", "tile": Vector2i(x, y)})
	var click := Vector2i(sim.areas.coast.size.x / 2, 470)
	while not sim.areas.is_water(click):
		click.x -= 1
	click += Vector2i(8, 0)
	var plan := sim.berth_plan("feeder", click)
	var west := sim.berth_plan("feeder", click, 180.0)
	_expect(int(plan.angle) % 90 != 0, true, "on this bank it turns off the grid (%d°)" % plan.angle)
	_expect(plan.fill.size() < west.fill.size(), true, "to fill less than facing west (%d cells against %d)" % [plan.fill.size(), west.fill.size()])
	_expect(sim.apply({"op": "build_berth", "kind": "feeder", "cell": click}), "", "and is built so")
	var apron: int = sim.areas.list.keys().max()
	var faces := sim.areas.out_at(apron, 25.0)
	_expect(faces.distance_to(Vector2.from_angle(deg_to_rad(plan.angle))) < 0.01, true, "its apron faces that way (%s)" % faces)
	_expect(sim.areas.cells(apron).any(sim.areas.is_water), false, "and stands on land")
	var ship := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], 0.0, 0, 0)
	ship.apron = apron
	ship.from = 0
	_expect(sim.areas.is_water(Vector2i(Marine.alongside(sim, ship).floor())), true, "a ship alongside lies on the water")
	_expect(sim.build_berth_error("feeder", click + Vector2i(0, 120), fposmod(plan.angle + 180.0, 360.0)) != "", true, "turned to face inland, a berth is refused")
