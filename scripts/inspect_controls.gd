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
	if thing is Dictionary and thing.has("junction"):
		found.assign(_junction(sim, thing.junction))
	elif thing is Dictionary and thing.has("base"):
		found.assign(_marine_base(sim, thing.base))
	elif thing is Dictionary and thing.has("lane") and thing.lane in sim.ship_lanes.segments:
		found.assign(_ship_lane(sim, thing.lane))
	if not (thing is Dictionary and thing.has("area") and thing.area in sim.areas.list):
		return found
	var id: int = thing.area
	if sim.areas.list[id].type in Areas.BLOCK_TYPES:
		found.assign(_block(sim, id))
		return found
	match sim.areas.kind_of(sim.areas.list[id]):
		"gate":
			found.assign(_gate(sim, id))
		"quay_apron":
			found.assign(_quay(sim, id))
		"agv_depot":
			found.assign(_agv_depot(sim, id))
		"fire_station":
			found.assign([_section("Fleet", [_buy("Fire engines", sim.areas.list[id].settings.engines, {"op": "buy_engines", "area": id, "count": 1}, "Buy one for %s." % HudDetails.dollars(sim.rules.events.fires.engine_cost))])])
		"workshop":
			found.assign(_workshop(sim, id))
	return found


static func _upper(text: String) -> String:
	return text[0].to_upper() + text.substr(1)


static func _section(title: String, controls: Array[Dictionary], open := true) -> Dictionary:
	return {"title": title, "open": open, "controls": controls}


## A count that only goes up, by buying one more.
static func _buy(label: String, count: int, command: Dictionary, tip: String) -> Dictionary:
	return {"kind": "stepper", "label": label, "value": str(count), "minus": {}, "plus": command, "tip": tip}


## A gate: how it checks lorries, how many it books an hour, and a scanner.
static func _gate(sim: PortSim, id: int) -> Array[Dictionary]:
	var settings: Dictionary = sim.areas.list[id].settings
	var levels: Array[Dictionary] = []
	for level: String in sim.rules.gate_levels:
		var refused: String = sim.set_area_error(id, {"level": level}) if level != settings.level else ""
		levels.append({"text": sim.rules.gate_levels[level].name, "selected": level == settings.level, "command": {"op": "set_area", "id": id, "settings": {"level": level}}, "disabled": refused != "", "tip": refused})
	var slots: int = settings.slots_per_hour
	var booking := func(to: int) -> Dictionary: return {"op": "set_area", "id": id, "settings": {"slots_per_hour": to}} if to != slots else {}
	var found: Array[Dictionary] = [_section("Settings", [
		{"kind": "choice", "label": "Level", "options": levels},
		{"kind": "stepper", "label": "Bookings", "value": "%d an hour" % slots if slots > 0 else "None", "minus": booking.call(maxi(slots - 5, 0)), "plus": booking.call(mini(slots + 5, PortSim.MAX_SLOTS_PER_HOUR)), "tip": "Lorries book an hour and are let in no sooner (none: lorries come in as they arrive). Early lorries wait in a truck park, else in a booth."},
	])]
	if not settings.scanner:
		found.append(_section("Upgrades", [{"kind": "button", "text": "Scanner, %s" % HudDetails.dollars(sim.rules.customs.scanner_cost), "command": {"op": "buy_scanner", "gate": id}, "disabled": false, "tip": "Scans the boxes customs picks in this terminal, clearing most of them at once; the rest still go to a customs block."}]))
	return found


## A quay: deepening its berth and shore power.
static func _quay(sim: PortSim, id: int) -> Array[Dictionary]:
	var controls: Array[Dictionary] = [_dredge(sim, Marine.pocket_depth(sim, id), Marine.pocket_size(sim, id), {"op": "dredge_berth", "apron": id, "metres": 1})]
	if not sim.areas.list[id].settings.shore_power:
		controls.append({"kind": "button", "text": "Shore power, %s" % HudDetails.dollars(sim.rules.town.shore_power_cost), "command": {"op": "buy_shore_power", "area": id}, "disabled": false, "tip": "Ships at this quay plug in and stop their engines, so %s no longer hears them." % sim.rules.town.name})
	return [_section("Upgrades", controls)]


## An AGV depot: its AGVs and chargers.
static func _agv_depot(sim: PortSim, id: int) -> Array[Dictionary]:
	var settings: Dictionary = sim.areas.list[id].settings
	var agv: Dictionary = sim.rules.agv
	var charger := _buy("Chargers", settings.chargers, {"op": "buy_chargers", "area": id, "count": 1} if settings.chargers < agv.max_chargers else {}, "Buy one for %s, up to %d. One AGV at home charges on each, flat to full in %.1f hours; a full battery lasts %d hours of work." % [HudDetails.dollars(agv.charger_cost), agv.max_chargers, agv.charge_hours, roundi(agv.battery_hours)])
	return [_section("Fleet", [_buy("AGVs", settings.agvs, {"op": "buy_agvs", "area": id, "count": 1}, "Buy one for %s." % HudDetails.dollars(agv.cost)), charger])]


## A workshop: its mechanics, and which kinds of equipment are serviced.
static func _workshop(sim: PortSim, id: int) -> Array[Dictionary]:
	var kinds := {}
	for crane: PortSim.Crane in sim.cranes:
		kinds[crane.kind] = sim.rules.sts_cranes[crane.kind].name
	for machine: Dictionary in sim.machines.list.values():
		kinds[machine.gear] = sim.rules.yard_gear[machine.gear].name
	var items: Array[Dictionary] = []
	for kind: String in kinds:
		var on: bool = sim.serviced.get(kind, false)
		items.append({"text": _upper(kinds[kind]) + "s", "on": on, "command": {"op": "set_serviced", "kind": kind, "on": not on}})
	var breakdowns: Dictionary = sim.rules.events.breakdowns
	var found: Array[Dictionary] = [_section("Staff", [_buy("Mechanics", sim.areas.list[id].settings.mechanics, {"op": "hire_mechanics", "area": id, "count": 1}, "Hire one for %s." % HudDetails.dollars(breakdowns.mechanic_cost))])]
	if not items.is_empty():
		found.append(_section("Servicing", [{"kind": "checklist", "label": "Service these", "items": items, "tip": "Serviced every %d working hours, out of work %d minutes each time, it breaks down %.0f times less often." % [roundi(breakdowns.service_every_hours), roundi(breakdowns.service_hours * 60.0), breakdowns.serviced_mtbf_factor]}]))
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
			gears.append({"text": _upper(spec.name) + (", %s" % HudDetails.dollars(price) if price > 0 else ""), "selected": gear == settings.gear, "command": setting.call({"gear": gear}), "disabled": refused != "", "tip": refused if refused else "Stacks %d high, upkeep %s a machine a day" % [spec.tiers, HudDetails.dollars(spec.upkeep_per_machine)]})
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


## Dredge 1 m off `cells` cells of water `depth` m deep, greyed with the
## sim's reason when it would refuse.
static func _dredge(sim: PortSim, depth: float, cells: int, command: Dictionary) -> Dictionary:
	var dredge: Dictionary = sim.rules.water.dredge
	var refused := sim.dredge_error(depth, 1, cells)
	return {"kind": "button", "text": "Dredge 1 m, %s" % HudDetails.dollars(cells * dredge.cost_per_cell_metre), "command": command, "disabled": refused != "", "tip": refused if refused else "Deepens this water 1 m, down to %.0f m, so ships of a deeper draft can use it. Then %s every %d days to keep it." % [dredge.max_depth, HudDetails.dollars(cells * dredge.maintenance_per_cell_metre), dredge.maintenance_days]}


## A ship lane: dredging it, and widening a narrow one.
static func _ship_lane(sim: PortSim, id: int) -> Array[Dictionary]:
	var lane: Dictionary = sim.ship_lanes.segments[id]
	var controls: Array[Dictionary] = [_dredge(sim, sim.ship_lanes.depth(id, sim.areas.coast), sim.ship_lanes.area(id).size(), {"op": "dredge_lane", "segment": id, "metres": 1})]
	if lane.type == "narrow":
		controls.append({"kind": "button", "text": "Widen, %s" % HudDetails.dollars(sim.ship_lane_price(sim.ship_lanes.nodes[lane.a], sim.ship_lanes.nodes[lane.b], "wide", lane.control)), "command": {"op": "widen_ship_lane", "segment": id}, "disabled": false, "tip": "Rebuilds it as a wide lane, %d m across, where ships pass both ways instead of booking it one at a time." % Grid.metres(sim.rules.water.lanes.wide.half_width * 2 + 1)})
	return [_section("Upgrades", controls)]


## A pilot station, tug depot or services jetty: the craft it keeps.
static func _marine_base(sim: PortSim, id: int) -> Array[Dictionary]:
	var water: Dictionary = sim.rules.water
	var craft: Array[Dictionary] = []
	if id in sim.pilot_stations:
		craft.append(_buy("Pilots", sim.pilot_stations[id].pilots, {"op": "hire_pilots", "station": id, "count": 1}, "Hire one for %s." % HudDetails.dollars(water.pilots.pilot_cost)))
	elif id in sim.tug_depots:
		craft.append(_buy("Tugs", sim.tug_depots[id].tugs, {"op": "buy_tugs", "depot": id, "count": 1}, "Buy one for %s." % HudDetails.dollars(water.tugs.tug_cost)))
		craft.append(_buy("Fireboats", _boats(sim, id, "fireboat"), {"op": "buy_fireboats", "depot": id, "count": 1}, "Buy one for %s." % HudDetails.dollars(water.fireboats.cost)))
	elif id in sim.service_jetties:
		for service: String in water.services.boats:
			var boat: Dictionary = water.services.boats[service]
			craft.append(_buy(boat.name + "s", _boats(sim, id, service), {"op": "buy_service_boats", "jetty": id, "service": service, "count": 1}, "Buy one for %s." % HudDetails.dollars(boat.cost)))
	return [_section("Fleet", craft)] if not craft.is_empty() else [] as Array[Dictionary]


static func _boats(sim: PortSim, base: int, kind: String) -> int:
	return sim.boats.of(base).filter(func(b: int) -> bool: return sim.boats.list[b].kind == kind).size()


## A junction: its signals and each phase's green, each arm's sign, and
## each lane's arrows.
static func _junction(sim: PortSim, point: Vector2) -> Array[Dictionary]:
	var junctions := Drive.junctions(sim)
	var signalled := point in junctions.signals
	var traffic: Dictionary = sim.rules.traffic
	var signals: Array[Dictionary] = [{"kind": "toggle", "label": "Traffic lights", "on": signalled, "command": {"op": "set_signals", "point": point, "on": not signalled}, "tip": "Lights give each way in turn a green; without them, signs and the rule of the road decide."}]
	if signalled:
		var greens: Array = junctions.signals[point].green
		for i: int in greens.size():
			var green := func(change: float) -> Dictionary:
				var seconds := clampf(greens[i] + change, traffic.min_green_seconds, traffic.max_green_seconds)
				return {"op": "set_green", "point": point, "phase": i, "seconds": seconds} if seconds != greens[i] else {}
			signals.append({"kind": "stepper", "label": "Phase %d green" % (i + 1), "value": "%d s" % roundi(greens[i]), "minus": green.call(-5.0), "plus": green.call(5.0), "tip": "How long this phase's green lasts, %d to %d s." % [traffic.min_green_seconds, traffic.max_green_seconds]})
	var found: Array[Dictionary] = [_section("Signals", signals)]

	var sign_names := {"": "No sign", "give_way": "Give way", "stop": "Stop"}
	var signs: Array[Dictionary] = []
	var arrows: Array[Dictionary] = []
	var presets := [[], ["left"], ["straight"], ["right"], ["left", "straight"], ["straight", "right"], ["left", "straight", "right"]]
	for arm: Vector2i in Drive.arms(sim, point):
		var sign: String = junctions.signs.get(point, {}).get(arm, "")
		var options: Array[Dictionary] = []
		for each: String in sign_names:
			options.append({"text": sign_names[each], "selected": each == sign, "command": {"op": "set_sign", "point": point, "arm": arm, "sign": each}, "disabled": false, "tip": "Give way: traffic from here waits for a gap; stop: it also stops at the line first."})
		signs.append({"kind": "choice", "label": "From the %s" % Inspect.arm_name(arm), "options": options})
		for lane: int in Drive.junction_lanes(sim).approach(point, arm).size():
			var turns: Array = junctions.arrows.get(point, {}).get(arm, {}).get(lane, [])
			var choices: Array[Dictionary] = []
			for preset: Array in presets:
				choices.append({"text": _upper(" + ".join(preset) if not preset.is_empty() else "as usual"), "selected": preset == turns, "command": {"op": "set_lane_arrows", "point": point, "arm": arm, "lane": lane, "turns": preset}, "disabled": false, "tip": "The turns this lane takes; as usual, the inner lane turns left and goes straight on, the outer turns right."})
			arrows.append({"kind": "choice", "label": "%s, lane %d" % [_upper(Inspect.arm_name(arm)), lane + 1], "options": choices})
	found.append(_section("Signs", signs, not signalled))
	found.append(_section("Lane arrows", arrows, false))
	return found
