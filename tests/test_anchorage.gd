extends SceneTree
## M8 step E: ships that find no free berth wait at an anchorage on the
## water; with no room at anchor they wait out at sea for a while, then go
## elsewhere. Lateness counts the time at anchor.
## godot --headless --script res://tests/test_anchorage.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_anchorages_are_built_on_water()
	_test_overbooking_fills_the_anchorage()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_anchorages_are_built_on_water() -> void:
	var sim := PortSim.new(0, RandomPort.strait(), true)
	_expect(sim.apply({"op": "build_anchorage", "from": Vector2i(10, 100), "to": Vector2i(90, 200)}), "An anchorage needs open water all over it", "an anchorage stays off the land")
	_expect(sim.apply({"op": "build_anchorage", "from": Vector2i(10, 100), "to": Vector2i(30, 120)}), "Too small for a ship: at least 200 m each way", "an anchorage holds at least one ship")
	_expect(sim.apply({"op": "build_anchorage", "from": Vector2i(10, 100), "to": Vector2i(59, 199)}), "", "an anchorage is built on the water")
	_expect(Marine.spots(sim, 1).size(), 2, "with a spot every 200 m each way")
	_expect(sim.apply({"op": "build_anchorage", "from": Vector2i(20, 150), "to": Vector2i(69, 249)}), "Anchorages can't overlap", "anchorages don't overlap")


## One berth, small feeders (20 moves each way) calling every 10 minutes
## with half-hour windows, more than the berth can work, and an
## anchorage of four spots over the lane's sea end: the queue at anchor
## grows to fill it, then ships wait out at sea and go elsewhere; a ship
## that waited at anchor sails late by at least the time it waited.
func _test_overbooking_fills_the_anchorage() -> void:
	var rules := RandomPort.quick()
	rules.ship_classes.feeder.window_hours = 0.5
	rules.ship_classes.feeder.import_moves = 20
	rules.ship_classes.feeder.export_moves = 20
	var sim := AreaPort.base(rules, "")
	var row: int = sim.ship_lanes.nodes.values()[0].y
	sim.creative = true
	_expect(sim.apply({"op": "build_anchorage", "from": Vector2i(0, row - 100), "to": Vector2i(49, row + 99)}), "", "an anchorage over the lane's sea end")
	sim.creative = false
	_expect(Marine.spots(sim, 1).size(), 4, "it has four spots")
	RandomPort.calls(sim, "feeder", 10, 10, 30)
	var most := 0
	var spots_ok := true
	# Each ship that waits at anchor: the hours it waited, then how late it sailed.
	var anchored := {}  # ship -> hours waited since it arrived, when it heads in
	var sailed := {}  # ship -> hours late as it sailed
	var last_state := {}
	for i in roundi(12 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for ship: PortSim.Ship in sim.ships:
			var was: int = last_state.get(ship, -1)
			if was == PortSim.Ship.State.ANCHORED and ship.state == PortSim.Ship.State.ARRIVING and last_state.get([ship, "anchor"], false):
				anchored[ship] = (sim.clock.calendar_minutes() - ship.arrived) / 60.0
			if was == PortSim.Ship.State.WORKING and ship.state == PortSim.Ship.State.LEAVING and ship in anchored:
				sailed[ship] = (sim.clock.calendar_minutes() - ship.due) / 60.0
			last_state[ship] = ship.state
			last_state[[ship, "anchor"]] = ship.anchorage != 0
		var waiting := sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.anchorage == 1)
		most = maxi(most, waiting.size())
		var spots := waiting.map(func(s: PortSim.Ship) -> int: return s.spot)
		for spot: int in spots:
			spots_ok = spots_ok and spots.count(spot) == 1
	_expect(most, 4, "the queue at anchor grows to fill the anchorage")
	_expect(spots_ok, true, "each waiting ship has its own spot")
	_expect(sim.events.any(func(e: Dictionary) -> bool: return e.text.contains("no room at anchor")), true, "with the anchorage full, ships wait at sea and go elsewhere")
	var long_waits := sailed.keys().filter(func(ship: PortSim.Ship) -> bool: return anchored[ship] > 1.0)
	_expect(long_waits.is_empty(), false, "ships waited over an hour at anchor and sailed (%s)" % [anchored.values()])
	for ship: PortSim.Ship in long_waits:
		_expect(sailed[ship] >= anchored[ship] - 0.5, true, "a ship's lateness (%.1f h) counts its %.1f h at anchor" % [sailed[ship], anchored[ship]])
