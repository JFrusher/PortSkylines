extends SceneTree
## Ships turn off their berth and are pushed in sideways: a ship sails its
## lanes, swings round to lie along the quay well out from it, comes in
## alongside, and leaves the same way backwards, its hull on open water all
## the way. A berth with no water to turn in takes no ship that big.
## godot --headless --script res://tests/test_berthing.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	for kind: String in ["feeder", "panamax"]:
		_test_hull_stays_on_the_water(kind)
	_test_no_room_no_berth()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _port() -> PortSim:
	var rules := RandomPort.quick()
	rules.ship_classes.panamax.pilot = false
	rules.ship_classes.panamax.tugs = 0
	return AreaPort.base(rules, "")


## Cells of `ship`'s hull on land now, sampled every 2 cells bow to stern.
func _aground(sim: PortSim, ship: PortSim.Ship) -> int:
	var at := Marine.point_along(ship.path, ship.sail)
	var bow := Marine.bow(sim, ship, ship.sail)
	var half := AreaFlow.ship_cells(sim, ship.kind) / 2.0
	var edge := sim.areas.coast.size - Vector2i.ONE
	var count := 0
	for k: int in range(-floori(half), floori(half) + 1, 2):
		if not sim.areas.is_water(Vector2i((at + bow * k).floor()).clamp(Vector2i.ZERO, edge)):
			count += 1
	return count


func _test_hull_stays_on_the_water(kind: String) -> void:
	var sim := _port()
	var ship := PortSim.Ship.new(kind, sim.rules.lines.keys()[0], sim.clock.calendar_minutes() + 6000.0, 0, 0)
	ship.id = 100
	sim.ships.append(ship)
	var aground := 0
	var berthed := false
	var turned := false
	for i in roundi(240.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if ship not in sim.ships:
			break
		if ship.apron != 0 and ship.path.size() >= 3:
			aground += _aground(sim, ship)
			var side := sim.areas.out_at(ship.apron, ship.from + (AreaFlow.ship_cells(sim, kind) - 1) / 2.0)
			# On the last leg, pushed in, it lies along the quay.
			if ship.state == PortSim.Ship.State.ARRIVING and ship.sail > 0.99:
				turned = absf(Marine.bow(sim, ship, ship.sail).dot(side)) < 0.01
		berthed = berthed or ship.state == PortSim.Ship.State.WORKING
	_expect(berthed, true, "a %s berths" % kind)
	_expect(turned, true, "lying along the quay as it comes alongside")
	_expect(ship in sim.ships, false, "and sails again")
	_expect(aground, 0, "its hull never over land, in or out")


## Land filled all along the quay line where a Panamax would swing round:
## with nowhere to turn, it no longer reaches the berth.
func _test_no_room_no_berth() -> void:
	var sim := _port()
	var apron: int = sim.areas.list.keys().filter(func(id: int) -> bool: return sim.areas.list[id].type == "quay_apron")[0]
	_expect(Marine.reaches(sim, "panamax", apron), true, "a Panamax reaches the open berth")
	var span := AreaFlow.ship_cells(sim, "panamax")
	var out := Marine._turn_out(sim, "panamax", apron)
	var islands: Array[Vector2i] = []
	for k: int in range(-span - 2, sim.areas.list[apron].columns + span + 2):
		islands.append(Vector2i(Marine._off_quay(sim, apron, k, out).floor()))
	sim.areas.fill(islands)
	_expect(Marine.reaches(sim, "panamax", apron), false, "with land all along where it would swing, no Panamax has room to turn there")
