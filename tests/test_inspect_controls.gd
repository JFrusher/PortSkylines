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
func _all_taken(sim: PortSim, sections: Array[Dictionary], what: String) -> void:
	var commands := _commands(sections)
	_expect(commands.size() > 5, true, "%s offers its choices (%d)" % [what, commands.size()])
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
	_expect(InspectControls.sections(sim, {"area": 1}), [] as Array[Dictionary], "a quay offers none of a block's")


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
