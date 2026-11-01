extends SceneTree
## M8 step O: coastlines generated from a seed, in the maps' own form. The
## same seed gives the same map, and every map passes the data's checks,
## reaches the open sea and has room for a berth.
## godot --headless --script res://tests/test_map_gen.gd

var _failures := 0


func _initialize() -> void:
	_test_same_seed_same_map()
	_test_every_map_is_playable()
	_test_a_game_on_a_generated_coast()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_same_seed_same_map() -> void:
	var site: Dictionary = Content.base().site
	_expect(MapGen.make(7, site), MapGen.make(7, site), "the same seed gives the same map")
	_expect(MapGen.make(7, site) != MapGen.make(8, site), true, "another seed gives another")


## Twenty seeds: each map passes the data's checks, has open sea on the
## site's edge, and a feeder berth fits on its coast by the highway's row.
func _test_every_map_is_playable() -> void:
	var rules := Content.base().duplicate(true)
	for seed_value: int in range(1, 21):
		var map := MapGen.make(seed_value, rules.site)
		_expect(Content._map_error(map, rules.site), "", "map %d passes the data's checks" % seed_value)
		rules.map = MapGen.PREFIX + str(seed_value)
		var sim := PortSim.new(seed_value, rules, true)
		var size := sim.areas.coast.size
		_expect(range(size.y).any(func(y: int) -> bool: return sim.areas.is_water(Vector2i(0, y))), true, "map %d has open sea on its west edge" % seed_value)
		var shore := Vector2i(size.x / 2, size.y / 2)
		while not sim.areas.is_water(shore):
			shore.x -= 1
		_expect(sim.berth_plan("feeder", shore + Vector2i(8, 0)).has("error"), false, "map %d has room for a feeder berth by the highway's row" % seed_value)


## A game on a generated coast saves and loads on the same coast.
func _test_a_game_on_a_generated_coast() -> void:
	var rules := Content.base().duplicate(true)
	rules.map = MapGen.PREFIX + "42"
	var sim := PortSim.new(42, rules, true)
	var loaded := PortSim.from_dict(sim.to_dict())
	_expect(loaded.map, rules.map, "a game remembers its generated coast")
	_expect(loaded.areas.coast, sim.areas.coast, "and is on the same coast once loaded")
