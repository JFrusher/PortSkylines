extends SceneTree
## M11 customs: flagged imports never leave the port before they are cleared;
## with no customs block they wait out a long hold, with one they go there
## and its inspectors clear them; a gate scanner clears most at once; paid
## things can't be set for free.
## godot --headless --script res://tests/test_customs.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_held_without_a_shed()
	_test_inspected_in_the_shed()
	_test_the_scanner_clears_most()
	_test_paid_things_are_not_free()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The base port with `share` of every line's imports flagged.
func _port(share := 1.0) -> PortSim:
	var sim := AreaPort.base()
	for line: String in sim.rules.lines:
		sim.rules.lines[line].customs_share = share
	sim.ledger.cash = 10000000
	return sim


## Runs `sim` `hours`; returns {"flagged": ids ever flagged, "imports": ids
## of every import seen, "states": every customs state seen, "early": boxes
## that left still flagged}.
func _run(sim: PortSim, hours: float) -> Dictionary:
	var seen := {"flagged": {}, "imports": {}, "states": {}, "early": 0}
	var last := {}
	for i in roundi(hours * 60.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for id: int in last:
			if id not in sim.boxes and last[id] != "":
				seen.early += 1
		last.clear()
		for id: int in sim.boxes:
			var box: Dictionary = sim.boxes[id]
			if box.kind != "import" or box.to != 0:
				continue
			last[id] = box.customs
			seen.imports[id] = true
			seen.states[box.customs] = true
			if box.customs != "":
				seen.flagged[id] = true
	return seen


func _test_held_without_a_shed() -> void:
	var seen := _run(_port(), 72.0)
	_expect(seen.flagged.is_empty(), false, "imports are flagged")
	_expect("held" in seen.states, true, "with no customs block they are held")
	_expect(seen.early, 0, "no flagged box leaves before it is cleared")


func _test_inspected_in_the_shed() -> void:
	# Few enough flagged that two inspectors keep up: a full shed holds them.
	var sim := _port(0.1)
	var block := AreaPort.add_export_block(sim)
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"role": "customs"}}), "", "a customs block")
	_expect(sim.apply({"op": "hire_inspectors", "area": block, "count": 2}), "", "two inspectors hired")
	var in_shed := false
	var seen := {"early": 0, "states": {}}
	for day in 3:
		var part := _run(sim, 24.0)
		seen.early += part.early
		seen.states.merge(part.states)
		if block in sim.area_stacks:
			for id: int in sim.area_stacks[block].boxes():
				in_shed = in_shed or sim.boxes[id].customs == "inspect"
	_expect(in_shed, true, "flagged boxes go to the customs block")
	_expect("held" in seen.states, false, "none are held")
	_expect("" in seen.states, true, "and inspected boxes are cleared")
	_expect(seen.early, 0, "no flagged box leaves before it is cleared")


func _test_the_scanner_clears_most() -> void:
	var sim := _port()
	var gate := 0
	for id: int in sim.areas.list:
		if sim.areas.kind_of(sim.areas.list[id]) == "gate":
			gate = id
	_expect(sim.apply({"op": "buy_scanner", "gate": gate}), "", "a scanner bought")
	_expect(sim.apply({"op": "buy_scanner", "gate": gate}), "This gate has a scanner already", "only one")
	var seen := _run(sim, 72.0)
	var share: float = float(seen.flagged.size()) / seen.imports.size()
	_expect(share > 0.0 and share < 0.5, true, "the scanner clears most (%.2f still flagged)" % share)


func _test_paid_things_are_not_free() -> void:
	var sim := _port()
	_expect(sim.apply({"op": "hire_inspectors", "area": 3, "count": 1}), "No customs block there", "inspectors only at a customs block")
	for key: String in ["inspectors", "scanner"]:
		var id: int = 3 if key == "inspectors" else sim.areas.list.keys().filter(func(a: int) -> bool: return sim.areas.kind_of(sim.areas.list[a]) == "gate")[0]
		_expect(sim.apply({"op": "set_area", "id": id, "settings": {key: 5 if key == "inspectors" else true}}).is_empty(), false, "set_area refuses %s" % key)
