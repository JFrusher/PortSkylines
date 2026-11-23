class_name InspectControls
extends RefCounted
## What the inspect panel offers for a thing, as data: its sections, each
## a list of controls carrying the complete command each choice issues, as
## Cities: Skylines 2's selected info panel. InspectPanel draws them; this
## decides them, so a test can check every one the sim accepts.
##
## A section is {"title", "open", "controls"}. A control is one of:
##   {"kind": "choice", "label", "options": [{"text", "selected", "command", "disabled", "tip"}]}
##   {"kind": "toggle", "label", "on", "command", "tip"}
##   {"kind": "stepper", "label", "value", "minus", "plus", "tip"}  ({} for a side that can't move)
##   {"kind": "checklist", "label", "items": [{"text", "on", "command"}], "tip"}
##   {"kind": "button", "text", "command", "disabled", "tip"}

const ROLE_NAMES := {"import": "Import", "export": "Export", "reefer": "Reefer", "dangerous": "Dangerous goods", "tranship": "Transhipment", "customs": "Customs", "empty": "Empty"}


## The sections for `thing` (from Inspect.pick), or [] when it offers none here.
static func sections(sim: PortSim, thing: Variant) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if thing is Dictionary and thing.has("area") and thing.area in sim.areas.list and sim.areas.list[thing.area].type in Areas.BLOCK_TYPES:
		found.assign(_block(sim, thing.area))
	return found


## A yard or transfer block: what it is and how it is worked, the boxes it
## takes and how it stacks them, templates, and what can be bought for it.
static func _block(sim: PortSim, id: int) -> Array[Dictionary]:
	var area: Dictionary = sim.areas.list[id]
	var settings: Dictionary = area.settings
	var setting := func(rule: Dictionary) -> Dictionary: return {"op": "set_area", "id": id, "settings": rule}
	var found: Array[Dictionary] = []

	# A choice the sim would refuse shows greyed, with its reason.
	var refusal := func(rule: Dictionary) -> String: return sim.set_area_error(id, rule)
	var roles: Array[Dictionary] = []
	for role: String in PortSim.AREA_ROLES:
		var refused: String = refusal.call({"role": role}) if role != settings.role else ""
		roles.append({"text": ROLE_NAMES[role], "selected": role == settings.role, "command": setting.call({"role": role}), "disabled": refused != "", "tip": refused})
	var controls: Array[Dictionary] = [{"kind": "choice", "label": "Role", "options": roles}]
	# A transfer block is worked by its twin ASCs, which work nowhere else.
	if area.type == "yard_block":
		var gears: Array[Dictionary] = []
		for gear: String in sim.rules.yard_gear:
			var spec: Dictionary = sim.rules.yard_gear[gear]
			if gear == "asc" or (spec.empties_only and settings.role != "empty"):
				continue
			var refused: String = refusal.call({"gear": gear}) if gear != settings.gear else ""
			var price := sim.gear_price(id, gear) if gear != settings.gear else 0
			gears.append({"text": spec.name[0].to_upper() + spec.name.substr(1) + (", %s" % HudDetails.dollars(price) if price > 0 else ""), "selected": gear == settings.gear, "command": setting.call({"gear": gear}), "disabled": refused != "", "tip": refused if refused else "Stacks %d high, upkeep %s a machine a day" % [spec.tiers, HudDetails.dollars(spec.upkeep_per_machine)]})
		controls.append({"kind": "choice", "label": "Gear", "options": gears})
	found.append({"title": "Settings", "open": true, "controls": controls})

	var sizes: Array[Dictionary] = []
	for take: Array in [[], [1], [2]]:
		sizes.append({"text": "Every size" if take.is_empty() else "%d ft only" % (take[0] * 20), "selected": take == settings.sizes, "command": setting.call({"sizes": take}), "disabled": false, "tip": "Boxes of another size go to a block that takes them, or stay aboard when none does."})
	var stacking: Array[Dictionary] = [
		{"text": "Lowest first", "selected": settings.stacking == "fill_low", "command": setting.call({"stacking": "fill_low"}), "disabled": false, "tip": "Each box goes on the lowest stack, so stacks stay level."},
		{"text": "By departure", "selected": settings.stacking == "by_departure", "command": setting.call({"stacking": "by_departure"}), "disabled": false, "tip": "Each box goes where it buries nothing leaving sooner, for the fewest re-handles."},
	]
	var gear_tiers: int = sim.rules.yard_gear[settings.gear].tiers
	var high := AreaFlow.tiers(sim, id)
	var lines: Array[Dictionary] = []
	for line: String in sim.rules.lines:
		var taken: Array = settings.lines.duplicate()
		if line in taken:
			taken.erase(line)
		else:
			taken.append(line)
		lines.append({"text": sim.contracts.name_of(line), "on": line in settings.lines, "command": setting.call({"lines": taken})})
	found.append({"title": "Box rules", "open": false, "controls": [
		{"kind": "choice", "label": "Sizes", "options": sizes},
		{"kind": "toggle", "label": "Takes reefers", "on": settings.reefers, "command": setting.call({"reefers": not settings.reefers}), "tip": "Whether reefers may be stacked here."},
		{"kind": "choice", "label": "Stacking", "options": stacking},
		{"kind": "stepper", "label": "Stack height", "value": "%d tiers" % high + ("" if settings.max_tiers > 0 else " (the gear's most)"), "minus": setting.call({"max_tiers": high - 1}) if high > 1 else {}, "plus": setting.call({"max_tiers": 0 if high + 1 >= gear_tiers else high + 1}) if settings.max_tiers > 0 else {}, "tip": "Lower stacks hold less and need fewer re-handles."},
		{"kind": "checklist", "label": "Only these lines (none ticked: every line)", "items": lines, "tip": "A block that names lines takes only their boxes."},
	]})

	var name := "Rules of block %d" % id
	var templates: Array[Dictionary] = [{"kind": "button", "text": "Save these rules as a template", "command": {"op": "save_template", "name": name, "id": id}, "disabled": false, "tip": "Saves the boxes this block takes and how it stacks as \"%s\", to give other blocks." % name}]
	var others: Array[Dictionary] = []
	for template: String in sim.templates:
		if template != name:
			others.append({"text": template, "selected": false, "command": {"op": "apply_template", "name": template, "id": id}, "disabled": false, "tip": "Gives this block the template's rules, keeping its role and gear."})
	if not others.is_empty():
		templates.push_front({"kind": "choice", "label": "Apply", "options": others})
	found.append({"title": "Template", "open": false, "controls": templates})

	var upgrades: Array[Dictionary] = []
	if area.type == "transfer_block" and not settings.racks:
		upgrades.append({"kind": "button", "text": "Racks, %s" % HudDetails.dollars(sim.rules.agv.rack_cost), "command": {"op": "buy_racks", "area": id}, "disabled": false, "tip": "A rack at each AGV slot: AGVs set imports down and go, and pick up exports the ASCs have staged, without waiting for an ASC."})
	if settings.role == "customs":
		upgrades.append({"kind": "stepper", "label": "Inspectors", "value": str(settings.inspectors), "minus": {}, "plus": {"op": "hire_inspectors", "area": id, "count": 1}, "tip": "Hire one for %s." % HudDetails.dollars(sim.rules.customs.inspector_cost)})
	if not upgrades.is_empty():
		found.append({"title": "Upgrades", "open": true, "controls": upgrades})
	return found
