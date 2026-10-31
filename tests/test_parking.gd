extends SceneTree
## Truck parks: lorries wait off the road there instead of queueing on it
## (M6 steps P1-P3).

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_a_full_gate_sends_lorries_to_the_park()
	_test_booked_slots()
	_test_no_way_through_a_park()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## AreaPort.base's port, imports collected 30 minutes after landing, with a
## gate that checks each lorry for `gate_minutes`, and a truck park on the
## inbound side of the east road, before the gate, when `park` is set.
func _port(gate_minutes: float, park: bool) -> PortSim:
	var rules := RandomPort.rules()
	rules.gate_levels.manual.minutes = gate_minutes
	var sim := AreaPort.base(rules, "")
	if park:
		var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
		sim.creative = true
		_expect(sim.apply({"op": "build_area", "type": "truck_park", "segment": east, "side": -1, "from": 330, "to": 389}), "", "a truck park is built before the gate")
		sim.creative = false
	RandomPort.calls(sim, "feeder", 10, 45, 1)
	return sim


## With a slow gate, a ship's imports bring lorries faster than the gate
## checks them, and they jam the road to it; with a park, it holds some of
## that jam off the road, each parked lorry in one of its slots, and all of
## them go on to the gate once the rush is over.
func _test_a_full_gate_sends_lorries_to_the_park() -> void:
	var jams := []
	for park: bool in [false, true]:
		var sim := _port(8.0, park)
		var room: int = sim.areas.layout(2).slots.size() + sim.areas.layout(2).buffer.size() / AreaLayout.BAY
		var worst := 0
		var parked := 0
		var in_slots := true
		for i in roundi(16 * 60 / SimClock.CALENDAR_MINUTES_PER_TICK):
			sim.tick()
			if i % 200 != 0:
				continue
			# Inbound lorries on the road: driving to or queueing for the gate or the park.
			var on_road := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "lorry" and v.gate_in < 0.0 and v.area != 0 and v.state in ["arriving", "queued"]).size()
			worst = maxi(worst, on_road - room)
			var now_parked := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.state == "parked")
			parked = maxi(parked, now_parked.size())
			if park:
				var slots: Array = sim.areas.layout(sim.areas.list.keys()[-1]).slots
				in_slots = in_slots and now_parked.all(func(v: Vehicle) -> bool: return slots.any(func(slot: Array) -> bool: return v.path[int(v.t)] in slot))
		jams.append([worst, parked, in_slots, sim.vehicles.filter(func(v: Vehicle) -> bool: return v.state == "parked").size()])
	var slots: int = 60 / AreaLayout.BAY
	_expect(jams[0][0] > slots, true, "without a park, the rush jams the road (%d lorries past the gate's room)" % jams[0][0])
	_expect(jams[1][1] > 0 and jams[1][2], true, "with one, lorries wait in its slots (%d at once)" % jams[1][1])
	_expect(jams[1][0] <= jams[0][0] - slots / 2, true, "and fewer wait on the road (%d, from %d)" % [jams[1][0], jams[0][0]])
	_expect(jams[1][3], 0, "every parked lorry has gone on to the gate by the end")


## A gate taking `slots_per_hour` bookings lets each lorry through no sooner
## than its booked hour, and books no more lorries into an hour than that.
func _test_booked_slots() -> void:
	var sim := _port(2.0, true)
	_expect(sim.apply({"op": "set_area", "id": 2, "settings": {"slots_per_hour": 6}}), "", "the gate takes 6 bookings an hour")
	var checked := {}  # booked hour -> lorries checked in for it
	var early := 0
	for i in roundi(6 * 60 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for lorry: Vehicle in sim.vehicles:
			if lorry.kind == "lorry" and lorry.state == "at_gate" and lorry.gate_in == sim.clock.calendar_minutes():
				var hour := floori(lorry.booked / 60.0)
				checked[hour] = checked.get(hour, 0) + 1
				early += 1 if sim.clock.calendar_minutes() < lorry.booked else 0
	_expect(not checked.is_empty(), true, "lorries came through on their bookings")
	_expect(early, 0, "none was checked in before its hour")
	_expect(checked.values().max() if not checked.is_empty() else 0, 6, "an hour holds at most 6, and the rush fills them")


## However jammed the road beside a park, a route past it stays on the road:
## an area's buffer strip is never a way round.
func _test_no_way_through_a_park() -> void:
	var sim := _port(2.0, true)
	var park: int = sim.areas.list.keys()[-1]
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	var jam := {}
	for lane: Dictionary in sim.roads.lanes(east):
		for cell: Vector2i in lane.cells:
			jam[cell] = 30.0
	sim.lanes.set_delays(jam, 100.0, 120.0)
	var route := sim.lanes.route(AreaFlow._entry_cell(sim), AreaFlow._buffer_start(sim, 2), true)
	var inside := sim.areas.cells(park)
	_expect(route.is_empty(), false, "there is still a route to the gate")
	_expect(route.filter(func(cell: Vector2i) -> bool: return cell in inside), [], "and it never enters the park")
	# Waiting in the park's buffer delays it too, yet a lorry leaving one space
	# drives out along the buffer, never through the spaces beside it.
	for cell: Vector2i in sim.areas.layout(park).buffer:
		jam[cell] = 30.0
	sim.lanes.set_delays(jam, 100.0, 120.0)
	var spaces: Array = sim.areas.layout(park).slots
	var out := sim.lanes.route(spaces[-1][1], AreaFlow._buffer_start(sim, 2), true)
	var others := {}
	for space: Array in spaces.slice(0, -1):
		for cell: Vector2i in space:
			others[cell] = true
	_expect(out.is_empty(), false, "a lorry in the last space has a way out")
	_expect(out.filter(func(cell: Vector2i) -> bool: return cell in others), [], "and it never drives through another space")
