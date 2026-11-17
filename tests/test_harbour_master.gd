extends SceneTree
## M11 harbour master: a call can be moved once within its flex band, and
## comes back to its weekly time after; a ship waiting at anchor can be
## kept there, sent to a berth, or put ahead of another in line.
## godot --headless --script res://tests/test_harbour_master.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_move_one_call()
	_test_keep_send_and_order()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_move_one_call() -> void:
	var sim := AreaPort.base()
	var service: Dictionary = sim.contracts.services[0]
	var flex: float = sim.rules.contracts.flex_hours * 60.0
	var weekly: float = service.start
	_expect(sim.apply({"op": "move_call", "id": service.id, "start": weekly + flex + 60.0}).is_empty(), false, "a call can't move past its flex band")
	_expect(sim.apply({"op": "move_call", "id": service.id, "start": weekly + 120.0}), "", "a call moves two hours later")
	var now := sim.clock.calendar_minutes()
	_expect(Contracts.next_call(service, now), floorf(now / Contracts.MINUTES_PER_WEEK) * Contracts.MINUTES_PER_WEEK + fposmod(weekly + 120.0, Contracts.MINUTES_PER_WEEK) + (Contracts.MINUTES_PER_WEEK if fposmod(weekly + 120.0, Contracts.MINUTES_PER_WEEK) < fposmod(now, Contracts.MINUTES_PER_WEEK) else 0.0), "its next call is two hours on")
	while service.next_start >= 0.0:
		sim.tick()
	_expect(fposmod(sim.clock.calendar_minutes(), Contracts.MINUTES_PER_WEEK), fposmod(weekly + 120.0, Contracts.MINUTES_PER_WEEK), "it calls at the moved time")
	_expect([float(service.start), service.next_start], [weekly, -1.0], "and next week's call is back at its weekly time")


## Two ships of the same call, kept waiting offshore: they stay out while the
## berth is free; one is put ahead of the other; one sent in comes to the
## berth at once; let go, the other berths too.
func _test_keep_send_and_order() -> void:
	var sim := AreaPort.base(RandomPort.quick(), "")
	# Its weekly call far off, so only the two ships called here are about.
	RandomPort.calls(sim, "feeder", 5000, 45, 1)
	# This port has no anchorage: ships wait off the map, here long enough not to give up.
	sim.rules.water.max_wait_hours = 72.0
	var service: Dictionary = sim.contracts.services[0]
	sim._call(service)
	sim._call(service)
	var a: PortSim.Ship = sim.ships[-2]
	var b: PortSim.Ship = sim.ships[-1]
	for ship: PortSim.Ship in [a, b]:
		_expect(sim.apply({"op": "keep_ship", "ship": ship.id, "on": true}), "", "a waiting ship is kept at anchor")
	for i in roundi(3 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	_expect([a.state, b.state].all(func(s: PortSim.Ship.State) -> bool: return s in [PortSim.Ship.State.ANCHORED, PortSim.Ship.State.ANCHORING]), true, "kept ships stay at anchor with the berth free")
	_expect(sim.apply({"op": "ship_ahead", "ship": b.id, "of": a.id}), "", "the second is put ahead of the first")
	_expect(sim.ships.find(b) < sim.ships.find(a), true, "and is first in line")
	while b.state != PortSim.Ship.State.ANCHORED:
		sim.tick()
	_expect(sim.apply({"op": "send_ship", "ship": b.id, "apron": 999}).is_empty(), false, "no ship goes to a berth that isn't there")
	_expect(sim.apply({"op": "send_ship", "ship": b.id, "apron": 1}), "", "a waiting ship is sent to the berth")
	_expect([b.state, b.apron, b.kept], [PortSim.Ship.State.ARRIVING, 1, false], "and comes in at once")
	_expect(sim.apply({"op": "keep_ship", "ship": a.id, "on": false}), "", "the other is let go")
	var berthed := false
	# Once the other is worked and gone from the one berth.
	for i in roundi(48 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		berthed = berthed or a.state in [PortSim.Ship.State.ARRIVING, PortSim.Ship.State.WORKING]
	_expect(berthed, true, "and takes the berth once it is free")
