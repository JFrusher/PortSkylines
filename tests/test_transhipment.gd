extends SceneTree
## M9 step A: a share of the boxes a line's big ship lands go on with its
## next feeder within the connection window, never by gate or rail; the
## feeder loads them first; a transhipment move pays less. M9 step B: they
## stack in the transhipment block nearest the feeder's berth. M9 step C: a
## box not loaded within its window rolls to the next, fined, and its line
## thinks less of the port.
## godot --headless --script res://tests/test_transhipment.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_boxes_go_on_by_feeder()
	_test_they_stack_in_the_nearest_transhipment_block()
	_test_the_role_is_locked_until_transhipment()
	_test_a_missed_connection_rolls_on()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Aurora (half its boxes transhipped) has a feeder service; its Panamax
## lands 200 boxes, then its feeder comes alongside.
func _test_boxes_go_on_by_feeder() -> void:
	var rules := RandomPort.quick()
	rules.lines.aurora.tranship_share = 0.5
	var sim := AreaPort.base(rules, "")
	AreaPort.add_export_block(sim)
	sim.contracts.services.append({"id": 900, "line": "aurora", "kind": "feeder", "start": 9000, "window_hours": 12.0, "moves": 0, "apron": 1, "any_berth": true, "asked": 9000})
	var big := PortSim.Ship.new("panamax", "aurora", sim.clock.calendar_minutes() + 6000.0, 200, 0)
	sim.ships.append(big)
	_expect(AreaFlow.berth(sim, big), true, "the Panamax berths")
	big.state = PortSim.Ship.State.WORKING
	big.sail = 1.0
	big.berthed = sim.clock.calendar_minutes()
	var seen := {}  # box -> kind when first seen
	var on_lorry := 0
	var paid := []
	for i in roundi(8 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for id: int in sim.boxes:
			if id not in seen:
				seen[id] = sim.boxes[id].kind
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.kind == "lorry" and vehicle.box in sim.boxes and sim.boxes[vehicle.box].kind == "tranship":
				on_lorry += 1
		if big not in sim.ships:
			break
	var landed := seen.values().filter(func(k: String) -> bool: return k in ["import", "tranship"])
	var transhipped := seen.values().filter(func(k: String) -> bool: return k == "tranship").size()
	_expect(transhipped > landed.size() * 0.35 and transhipped < landed.size() * 0.65, true, "about half the boxes landed are transhipped (%d of %d)" % [transhipped, landed.size()])
	_expect(on_lorry, 0, "a transhipment box never leaves on a lorry")
	var waiting := sim.boxes.keys().filter(func(id: int) -> bool: return sim.boxes[id].kind == "tranship")
	_expect(waiting.all(func(id: int) -> bool: return sim.boxes[id].onward == "feeder" and sim.boxes[id].line == "aurora"), true, "they wait for Aurora's feeder")
	var box: Dictionary = sim.boxes[waiting[0]]
	_expect(sim.move_price(box), roundi(sim.move_price({"kind": "import", "teu": box.teu, "reefer": false}) * rules.transhipment.price_factor) + (rules.move_price.reefer_premium if box.reefer else 0), "a transhipment move pays the price times the factor")
	# Aurora's feeder comes alongside and loads them first.
	var feeder := PortSim.Ship.new("feeder", "aurora", sim.clock.calendar_minutes() + 6000.0, 0, 20)
	sim.ships.append(feeder)
	_expect(AreaFlow.berth(sim, feeder), true, "Aurora's feeder berths")
	feeder.state = PortSim.Ship.State.WORKING
	feeder.sail = 1.0
	feeder.berthed = sim.clock.calendar_minutes()
	var before := waiting.size()
	for i in roundi(3 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		if feeder.exports == 0:
			break
	var left := sim.boxes.keys().filter(func(id: int) -> bool: return sim.boxes[id].kind == "tranship").size()
	_expect(before - left, mini(20, before), "the feeder loads its line's transhipment boxes first (%d of %d)" % [before - left, before])


## Two transhipment blocks across the road from the import block, one by the
## coast road (and the feeder's berth), one further east: the transhipped
## boxes all go to the near one, and none to the import block.
func _test_they_stack_in_the_nearest_transhipment_block() -> void:
	var rules := RandomPort.quick()
	rules.lines.aurora.tranship_share = 0.5
	var sim := AreaPort.base(rules, "")
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	sim.creative = true
	var blocks: Array[int] = []
	for from: int in [130, 29]:
		_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": -1, "from": from, "to": from + 29}), "", "a transhipment block is built")
		blocks.append(sim.areas.list.keys().max())
		_expect(sim.apply({"op": "set_area", "id": blocks[-1], "settings": {"role": "tranship"}}), "", "and set to transhipment")
	sim.creative = false
	var far := blocks[0]
	var near := blocks[1]
	sim.contracts.services.append({"id": 900, "line": "aurora", "kind": "feeder", "start": 9000, "window_hours": 12.0, "moves": 0, "apron": 1, "any_berth": true, "asked": 9000})
	var big := PortSim.Ship.new("panamax", "aurora", sim.clock.calendar_minutes() + 6000.0, 60, 0)
	sim.ships.append(big)
	_expect(AreaFlow.berth(sim, big), true, "the Panamax berths")
	big.state = PortSim.Ship.State.WORKING
	big.sail = 1.0
	big.berthed = sim.clock.calendar_minutes()
	for i in roundi(4 * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
	var tranship_in := func(block: int) -> int: return AreaFlow._stacks(sim, block).of_kind("tranship", sim.boxes).size()
	_expect(tranship_in.call(near) > 10, true, "transhipment boxes stack in the near transhipment block (%d)" % tranship_in.call(near))
	_expect(tranship_in.call(far), 0, "none in the far one")
	_expect(tranship_in.call(3), 0, "none in the import block")
	_expect(AreaFlow._stacks(sim, near).of_kind("import", sim.boxes).size(), 0, "and no imports in the transhipment block")


func _test_the_role_is_locked_until_transhipment() -> void:
	var sim := AreaPort.base(RandomPort.strait(), "")
	_expect(sim.apply({"op": "set_area", "id": 3, "settings": {"role": "tranship"}}), sim.lock_error("transhipment"), "a transhipment block waits for the transhipment unlock")


## Aurora's feeder never comes in a two-hour window: every box landed for it
## misses, once per window, each fined and costing Aurora reputation, and
## waits on for the next window.
func _test_a_missed_connection_rolls_on() -> void:
	var rules := RandomPort.quick()
	rules.lines.aurora.tranship_share = 0.5
	rules.lines.aurora.connection_hours = 2.0
	var sim := AreaPort.base(rules, "")
	sim.contracts.services.append({"id": 900, "line": "aurora", "kind": "feeder", "start": 9000, "window_hours": 12.0, "moves": 0, "apron": 1, "any_berth": true, "asked": 9000})
	var big := PortSim.Ship.new("panamax", "aurora", sim.clock.calendar_minutes() + 6000.0, 30, 0)
	sim.ships.append(big)
	_expect(AreaFlow.berth(sim, big), true, "the Panamax berths")
	big.state = PortSim.Ship.State.WORKING
	big.sail = 1.0
	big.berthed = sim.clock.calendar_minutes()
	var start := sim.clock.calendar_minutes()
	while sim.clock.calendar_minutes() < start + 60.0:
		sim.tick()
	# Its call is scored as it sails, so the reputation is read after that.
	_expect(big in sim.ships, false, "the Panamax has sailed within the hour")
	var reputation: float = sim.contracts.reputation.aurora
	var landed := sim.boxes.keys().filter(func(id: int) -> bool: return sim.boxes[id].kind == "tranship")
	_expect(landed.size() > 3, true, "boxes are landed for Aurora's feeder (%d)" % landed.size())
	_expect(sim.ledger.today.get("connection_fines", 0), 0, "none has missed yet")
	var dues := landed.map(func(id: int) -> float: return sim.boxes[id].due)
	while sim.clock.calendar_minutes() < start + 4.0 * 60.0:
		sim.tick()
	var missed := landed.filter(func(id: int) -> bool: return id in sim.boxes and sim.boxes[id].kind == "tranship")
	_expect(missed.size(), landed.size(), "they all wait on, none sent by road")
	_expect(sim.ledger.today.get("connection_fines", 0), -landed.size() * rules.transhipment.missed_fine, "each missed connection is fined once")
	_expect(range(landed.size()).all(func(i: int) -> bool: return sim.boxes[landed[i]].due == dues[i] + 120.0), true, "each rolls to the next window")
	_expect(sim.contracts.reputation.aurora < reputation, true, "Aurora thinks less of the port (%.1f to %.1f)" % [reputation, sim.contracts.reputation.aurora])
