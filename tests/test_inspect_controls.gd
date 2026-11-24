extends SceneTree
## The inspect panel's controls (InspectControls): a few grouped controls
## instead of a button per value, and every command they offer is one the
## sim takes.
## godot --headless --script res://tests/test_inspect_controls.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_yard_block()
	_test_transfer_block()
	_test_other_areas()
	_test_junction()
	_test_water()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Every command `sections` offers that isn't disabled or already chosen.
func _commands(sections: Array[Dictionary]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for section: Dictionary in sections:
		for control: Dictionary in section.controls:
			match control.kind:
				"choice":
					for option: Dictionary in control.options:
						if not option.disabled and not option.selected:
							found.append(option.command)
				"toggle":
					found.append(control.command)
				"stepper":
					for side: Dictionary in [control.minus, control.plus]:
						if not side.is_empty():
							found.append(side)
				"checklist":
					for item: Dictionary in control.items:
						found.append(item.command)
				"button":
					if not control.disabled:
						found.append(control.command)
	return found


## Each of `sim`'s offered commands taken on a fresh copy of it.
func _all_taken(sim: PortSim, sections: Array[Dictionary], what: String, least := 6) -> void:
	var commands := _commands(sections)
	_expect(commands.size() >= least, true, "%s offers its choices (%d)" % [what, commands.size()])
	for command: Dictionary in commands:
		var copy := PortSim.from_dict(sim.to_dict())
		_expect(copy.apply(command), "", "%s: %s is taken" % [what, command])


func _test_yard_block() -> void:
	var sim := AreaPort.base(RandomPort.quick())
	sim.milestones_passed = 5
	sim.ledger.cash = 10_000_000
	sim.apply({"op": "save_template", "name": "Forties", "id": 3})
	var sections := InspectControls.sections(sim, {"area": 3})
	_expect(sections.map(func(s: Dictionary) -> String: return s.title), ["Settings", "Box rules", "Template"], "a yard block's sections")
	var controls := 0
	for section: Dictionary in sections:
		controls += section.controls.size()
	_expect(controls <= 10, true, "a handful of controls, not a button per value (%d)" % controls)
	_all_taken(sim, sections, "a yard block")
	sim.apply({"op": "set_area", "id": 3, "settings": {"role": "customs"}})
	var upgrades: Array = InspectControls.sections(sim, {"area": 3}).filter(func(s: Dictionary) -> bool: return s.title == "Upgrades")
	_expect(upgrades.size(), 1, "a customs block can hire inspectors")


func _test_transfer_block() -> void:
	var sim := AreaPort.base(RandomPort.quick())
	sim.creative = true
	sim.milestones_passed = 5
	sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(200, 300), "to": Vector2i(200, 270)})
	sim.apply({"op": "build_road", "type": "terminal_1_1", "from": Vector2i(200, 270), "to": Vector2i(130, 270)})
	var east := sim.roads.segment_at(Vector2i(150, 300))
	_expect(sim.apply({"op": "build_area", "type": "transfer_block", "segment": east, "side": -1, "from": 55, "to": 66}), "", "a transfer block")
	sim.creative = false
	sim.ledger.cash = 10_000_000
	var block: int = sim.areas.list.keys().max()
	var sections := InspectControls.sections(sim, {"area": block})
	var settings: Dictionary = sections.filter(func(s: Dictionary) -> bool: return s.title == "Settings")[0]
	_expect(settings.controls.map(func(c: Dictionary) -> String: return c.label), ["Role"], "its gear is its ASCs: no gear choice")
	_expect(sections.any(func(s: Dictionary) -> bool: return s.title == "Upgrades"), true, "racks can be bought")
	_all_taken(sim, sections, "a transfer block")


## Gates, quays, AGV depots, fire stations and workshops: their own
## sections, and every command they offer taken.
func _test_other_areas() -> void:
	var sim := AreaPort.base(RandomPort.quick())
	sim.creative = true
	sim.milestones_passed = 5
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	var built := {}
	for spec: Array in [["workshop", 62, 70], ["fire_station", 72, 80], ["agv_depot", 82, 95]]:
		_expect(sim.apply({"op": "build_area", "type": spec[0], "segment": east, "side": 1, "from": spec[1], "to": spec[2]}), "", "a %s" % spec[0])
		built[spec[0]] = sim.areas.list.keys().max()
	sim.creative = false
	sim.ledger.cash = 100_000_000
	var gate: int = sim.areas.list.keys().filter(func(id: int) -> bool: return sim.areas.kind_of(sim.areas.list[id]) == "gate")[0]
	for case: Array in [[gate, ["Settings", "Upgrades"], 3], [1, ["Upgrades"], 2], [built.workshop, ["Staff", "Servicing"], 2], [built.fire_station, ["Fleet"], 1], [built.agv_depot, ["Fleet"], 2]]:
		var kind := sim.areas.kind_of(sim.areas.list[case[0]])
		var sections := InspectControls.sections(sim, {"area": case[0]})
		_expect(sections.map(func(s: Dictionary) -> String: return s.title), case[1], "a %s's sections" % kind)
		_all_taken(sim, sections, "a %s" % kind, case[2])


## A junction: lights, then each phase's green, signs and lane arrows as
## dropdowns, every one taken.
func _test_junction() -> void:
	var sim := AreaPort.terminal(80)
	var point := Vector2i(86, sim.site_entry().y)
	sim.creative = true
	_expect(sim.apply({"op": "build_road", "from": point, "to": point + Vector2i(0, 20), "type": "terminal_1_1"}), "", "a stub road south makes the bend a T")
	var junction := {"junction": Vector2(point)}
	var sections := InspectControls.sections(sim, junction)
	_expect(sections.map(func(s: Dictionary) -> String: return s.title), ["Signals", "Signs", "Lane arrows"], "a junction's sections")
	_expect(sections[1].controls.size(), 3, "a sign dropdown for each of its 3 roads in")
	_all_taken(sim, sections, "a junction without lights", 4)
	sim.apply({"op": "set_signals", "point": Vector2(point), "on": true})
	sections = InspectControls.sections(sim, junction)
	_expect(sections[0].controls.filter(func(c: Dictionary) -> bool: return c.kind == "stepper").size() >= 2, true, "a green stepper for each phase")
	_all_taken(sim, sections, "a junction with lights", 4)


## Pilot stations, tug depots, services jetties and ship lanes.
func _test_water() -> void:
	var sim := AreaPort.base(RandomPort.quick(), "")
	sim.creative = true
	sim.milestones_passed = 5
	_expect(sim.apply({"op": "build_pilot_station", "cell": Vector2i(66, 180)}), "", "a pilot station")
	_expect(sim.apply({"op": "build_tug_depot", "cell": Vector2i(66, 520)}), "", "a tug depot")
	_expect(sim.apply({"op": "build_services_jetty", "cell": Vector2i(66, 400)}), "", "a services jetty")
	sim.creative = false
	sim.ledger.cash = 100_000_000
	for base: int in [1, 2, 3]:
		var sections := InspectControls.sections(sim, {"base": base})
		_expect(sections.map(func(s: Dictionary) -> String: return s.title), ["Fleet"], "marine base %d's sections" % base)
		_all_taken(sim, sections, "marine base %d" % base, 1)
	var lane: int = sim.ship_lanes.segments.keys()[0]
	var sections := InspectControls.sections(sim, {"lane": lane})
	_expect(sections[0].controls.size(), 2, "a narrow lane can be dredged and widened")
	_all_taken(sim, sections, "a ship lane", 1)
	sim.ship_lanes.segments[lane].dredged = 100
	_expect(InspectControls.sections(sim, {"lane": lane})[0].controls[0].disabled, true, "dredging greys out at the deepest")
