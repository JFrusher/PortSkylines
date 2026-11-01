extends SceneTree
## M8 steps F, G and H: ships book narrow lanes so two never pass in one;
## Panamaxes and up take a pilot each passage and wait for tugs to berth.
## godot --headless --script res://tests/test_marine.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_one_pilot_serialises_arrivals()
	_test_nearer_tugs_berth_sooner()
	_test_ships_never_pass_in_a_narrow_lane()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## AreaPort.base's port with a second apron south down the coast and its own
## lane, every milestone reached, creative, `pilots` pilots at a station
## and four tugs at a depot by `depot`.
func _port(pilots: int, depot := Vector2i(66, 240)) -> PortSim:
	var rules := RandomPort.quick()
	rules.ship_classes.panamax.pilot = true
	rules.ship_classes.panamax.tugs = 2
	var sim := AreaPort.base(rules, "")
	sim.creative = true
	var entry := sim.site_entry()
	sim.apply({"op": "build_road", "from": Vector2i(86, entry.y), "to": Vector2i(86, entry.y + 90), "type": "terminal_1_1"})
	var coast := sim.roads.segment_at(Vector2i(85, entry.y + 50))
	_expect(sim.apply({"op": "build_area", "type": "quay_apron", "segment": coast, "side": 1, "from": 5, "to": 84}), "", "a second apron")
	AreaPort.add_lane(sim, sim.areas.list.keys().max())
	_expect(sim.apply({"op": "build_pilot_station", "cell": Vector2i(66, 180)}), "", "a pilot station by the shore")
	_expect(sim.apply({"op": "hire_pilots", "station": 1, "count": pilots}), "", "with its pilots")
	_expect(sim.apply({"op": "build_tug_depot", "cell": depot}), "", "a tug depot")
	_expect(sim.apply({"op": "buy_tugs", "depot": 2, "count": 4}), "", "with four tugs")
	return sim


func _panamax(sim: PortSim) -> PortSim.Ship:
	var ship := PortSim.Ship.new("panamax", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 6000.0, 10, 0)
	ship.id = sim.ships.size() + 100
	sim.ships.append(ship)
	return ship


## Two Panamaxes for two free berths: with one pilot the second sets off only
## once the first is alongside; with two they come in together.
func _test_one_pilot_serialises_arrivals() -> void:
	for pilots: int in [1, 2]:
		var sim := _port(pilots)
		_panamax(sim)
		_panamax(sim)
		var together := false
		var both := false
		for i in roundi(90.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
			sim.tick()
			var moving := sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.state == PortSim.Ship.State.ARRIVING and s.sail > 0.0)
			together = together or moving.size() == 2
			both = sim.ships.all(func(s: PortSim.Ship) -> bool: return s.state == PortSim.Ship.State.WORKING)
		_expect(both, true, "with %d pilot(s) both Panamaxes berth" % pilots)
		_expect(together, pilots == 2, "with %d pilot(s) they %s" % [pilots, "come in together" if pilots == 2 else "come in one at a time"])


## A Panamax needs two tugs to berth; from a depot further from its berth
## it berths later, by about the tugs' extra sailing time.
func _test_nearer_tugs_berth_sooner() -> void:
	var berthed := []
	var depots := [Vector2i(66, 240), Vector2i(66, 520)]
	for depot: Vector2i in depots:
		var sim := _port(1, depot)
		var ship := _panamax(sim)
		for i in roundi(90.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
			sim.tick()
			if ship.state == PortSim.Ship.State.WORKING:
				break
		berthed.append(ship.berthed)
		_expect(ship.state, PortSim.Ship.State.WORKING, "a Panamax berths with tugs from the depot at %s" % depot)
	var extra: float = (berthed[1] - berthed[0])
	var sim := _port(1)
	var further := Vector2(depots[1]).distance_to(Vector2(68, 240)) - Vector2(depots[0]).distance_to(Vector2(68, 240))
	_expect(extra > 1.0, true, "from the further depot it berths %.1f min later" % extra)
	_expect(extra <= further * Grid.CELL / sim.rules.water.tugs.speed + 1.0, true, "no later than the tugs' extra sailing (%.1f min)" % (further * Grid.CELL / sim.rules.water.tugs.speed))


## One feeder leaves berth 1 as another comes in to berth 2, through the same
## narrow lane: they never sail it at once.
func _test_ships_never_pass_in_a_narrow_lane() -> void:
	var sim := _port(1)
	for segment: int in sim.ship_lanes.segments.keys():
		sim.apply({"op": "remove_ship_lane", "segment": segment})
	# One long narrow lane in from the sea at the north edge, down the coast
	# past both berths, with a branch off it to each.
	var rows: Array[int] = []
	for apron: int in [1, sim.areas.list.keys().max()]:
		var area: Dictionary = sim.areas.list[apron]
		var cells := RoadNet.line(area.start, area.end)
		rows.append(cells[cells.size() / 2].y)
	var fork := Vector2i(30, rows[1])
	_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(fork.x, 0), "to": fork, "type": "narrow"}), "", "a narrow lane in from the sea")
	for row: int in rows:
		_expect(sim.apply({"op": "build_ship_lane", "from": Vector2i(68, row), "to": Vector2i(fork.x, row), "type": "narrow"}), "", "a branch from the berth's water onto the lane")
	var leaving := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 600.0, 0, 0)
	leaving.id = 1
	leaving.berth = 1
	leaving.any_berth = false
	sim.ships.append(leaving)
	_expect(AreaFlow.berth(sim, leaving), true, "a feeder at berth 1")
	leaving.state = PortSim.Ship.State.WORKING
	leaving.sail = 1.0
	leaving.berthed = sim.clock.calendar_minutes()
	var arriving := PortSim.Ship.new("feeder", sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 600.0, 10, 0)
	arriving.id = 2
	arriving.berth = sim.areas.list.keys().max()
	arriving.any_berth = false
	sim.ships.append(arriving)
	var narrow: int = sim.ship_lanes.segment_at(Vector2i(fork.x, 100))
	var line := sim.ship_lanes.cells(narrow)
	var clash := 0
	var both_used := [false, false]
	for i in roundi(60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		var inside := 0
		for k in 2:
			var ship: PortSim.Ship = [leaving, arriving][k]
			# Under way: cleared and moving, not waiting at the lane's end to set off.
			if ship in sim.ships and ship.state in [PortSim.Ship.State.ARRIVING, PortSim.Ship.State.LEAVING] and ship.cleared and ship.sail > 0.0 and ship.sail < 1.0:
				var at := Vector2i(Marine.point_along(ship.path, ship.sail).floor())
				if at in line:
					inside += 1
					both_used[k] = true
		clash += 1 if inside > 1 else 0

	_expect(both_used, [true, true], "both ships sail the narrow lane")
	_expect(clash, 0, "never both at once")
