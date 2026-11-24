extends SceneTree
## M9 step A: a share of the boxes a line's big ship lands go on with its
## next feeder within the connection window, never by gate or rail; the
## feeder loads them first; a transhipment move pays less. M9 step B: they
## stack in the transhipment block nearest the feeder's berth. M9 step C: a
## box not loaded within its window rolls to the next, fined, and its line
## thinks less of the port, once. Boxes go on only while the line's onward
## calls inside the window have room for them; a check cancels at most one
## of a line's services.
## godot --headless --script res://tests/test_transhipment.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_boxes_go_on_by_feeder()
	_test_they_stack_in_the_nearest_transhipment_block()
	_test_the_role_is_locked_until_transhipment()
	_test_a_missed_connection_rolls_on()
	_test_only_what_onward_calls_can_take()
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
	sim.contracts.services.append(_feeder_service(sim, 24.0))
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
	sim.contracts.services.append(_feeder_service(sim, 24.0))
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


## Aurora's feeder is due inside a two-hour window, so boxes are landed for
## it, but it is dropped before it calls: every box misses and waits on for
## the next window, fined and costing Aurora reputation the first time only,
## and that one check, with Aurora at the brink, cancels one of its two
## other services, not both.
func _test_a_missed_connection_rolls_on() -> void:
	var rules := RandomPort.quick()
	rules.lines.aurora.tranship_share = 0.5
	rules.lines.aurora.connection_hours = 2.0
	var sim := AreaPort.base(rules, "")
	var feeder := _feeder_service(sim, 1.5)
	sim.contracts.services.append(feeder)
	for id: int in [901, 902]:
		sim.contracts.services.append({"id": id, "line": "aurora", "kind": "panamax", "start": 9000 + (id - 901) * 1440, "window_hours": 24.0, "moves": 0, "apron": 1, "any_berth": true, "asked": 9000, "next_start": -1.0})
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
	sim.contracts.services.erase(feeder)
	sim.contracts.reputation.aurora = rules.reputation.cancel_below + 0.5
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
	_expect(is_equal_approx(sim.contracts.reputation.aurora, reputation + rules.transhipment.missed_reputation * landed.size()), true, "Aurora thinks less of the port by every box (%.2f to %.2f)" % [reputation, sim.contracts.reputation.aurora])
	_expect(sim.contracts.services.size(), 1, "and cancels one service in that check, not one a box")
	var after: float = sim.contracts.reputation.aurora
	while sim.clock.calendar_minutes() < start + 6.0 * 60.0:
		sim.tick()
	_expect(range(landed.size()).all(func(i: int) -> bool: return sim.boxes[landed[i]].due == dues[i] + 240.0), true, "each rolls on again")
	_expect(sim.ledger.today.get("connection_fines", 0), -landed.size() * rules.transhipment.missed_fine, "but is not fined again")
	_expect(sim.contracts.reputation.aurora, after, "nor costs Aurora again")
	_expect(sim.contracts.services.size(), 1, "so nothing more is cancelled")


## Aurora's weekly feeder, due `hours` from now.
func _feeder_service(sim: PortSim, hours: float) -> Dictionary:
	var start := fposmod(sim.clock.calendar_minutes() + hours * 60.0, Contracts.MINUTES_PER_WEEK)
	return {"id": 900, "line": "aurora", "kind": "feeder", "start": start, "window_hours": 12.0, "moves": 0, "apron": 1, "any_berth": true, "asked": start, "next_start": -1.0}


## Soak, day 3: Meridian's big ships landed about 1,100 boxes a week for one
## feeder taking 160, mostly after their window. A box goes on only while
## the line's onward calls inside the window have room; the rest land as imports.
func _test_only_what_onward_calls_can_take() -> void:
	for case: Array in [[24.0, 5, 5, "a feeder taking 5 inside the window takes 5"], [72.0, 160, 0, "a feeder due after the window takes none"]]:
		var rules := RandomPort.quick()
		rules.lines.aurora.tranship_share = 1.0
		rules.ship_classes.feeder.export_moves = case[1]
		var sim := AreaPort.base(rules, "")
		sim.contracts.services.append(_feeder_service(sim, case[0]))
		var big := PortSim.Ship.new("panamax", "aurora", sim.clock.calendar_minutes() + 6000.0, 30, 0)
		sim.ships.append(big)
		_expect(AreaFlow.berth(sim, big), true, "the Panamax berths")
		big.state = PortSim.Ship.State.WORKING
		big.sail = 1.0
		big.berthed = sim.clock.calendar_minutes()
		var seen := {}
		while big in sim.ships:
			sim.tick()
			for id: int in sim.boxes:
				if id not in seen:
					seen[id] = sim.boxes[id].kind
		var landed := seen.values().filter(func(k: String) -> bool: return k in ["import", "tranship"]).size()
		_expect(landed > case[2], true, "more boxes land (%d) than go on" % landed)
		_expect(seen.values().count("tranship"), case[2], case[3])
