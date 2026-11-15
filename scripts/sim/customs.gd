class_name Customs
extends RefCounted
## Customs (M11). A share of each line's imports is flagged when landed. A
## gate scanner in the terminal clears most of them at once; the rest go by
## tractor to a customs block (a yard block given the customs role), where
## its inspectors each inspect one box at a time. With no customs block a
## flagged box waits a long hold where it stacks. A flagged box never leaves
## the port until it is cleared: box "customs" is "" once clear, "inspect"
## in a customs block (its inspection ending at "customs_until", 0 before it
## starts) or "held" (waiting out the hold until "customs_until").


## Whether import `id`, landed at `terminal`, is flagged, by its line's
## share; flags it, and returns the customs block it goes to (0 when it goes
## on as any import: cleared by the scanner, or held with no customs block).
static func flag(sim: PortSim, id: int, terminal: int) -> int:
	var box: Dictionary = sim.boxes[id]
	if box.kind != "import" or box.to != 0 or _roll(sim, id, "flag") >= sim.rules.lines[box.line].customs_share:
		return 0
	if _scanner(sim, terminal) and _roll(sim, id, "scan") >= sim.rules.customs.inspect_share_after_scan:
		return 0
	box.barge = false
	sim._flagged[id] = true
	var block := AreaFlow._block_for(sim, "customs", terminal)
	if block:
		box.customs = "inspect"
	else:
		box.customs = "held"
		box.customs_until = sim.clock.calendar_minutes() + sim.rules.customs.no_shed_hours * 60.0
	return block


## Clears held boxes whose hold is over, and in each customs block starts an
## inspection for each idle inspector and clears each box whose inspection
## is done.
static func tick(sim: PortSim) -> void:
	if sim._flagged.is_empty():
		return
	var now := sim.clock.calendar_minutes()
	var at := {}  # customs block -> {"inspecting": count, "waiting": ids}
	for id: int in sim._flagged.keys():
		if id not in sim.boxes:
			sim._flagged.erase(id)  # burned, or gone with its block
			continue
		var box: Dictionary = sim.boxes[id]
		if box.customs == "held":
			if now >= box.customs_until:
				box.customs = ""
				sim._flagged.erase(id)
			continue
		var area := _stacked_in(sim, id)
		if area == 0:
			continue  # on its way to the customs block
		var here: Dictionary = at.get_or_add(area, {"inspecting": 0, "waiting": [] as Array[int]})
		if box.customs_until == 0.0:
			here.waiting.append(id)
		elif now >= box.customs_until:
			box.customs = ""
			box.customs_until = 0.0
			sim._flagged.erase(id)
		else:
			here.inspecting += 1
	for area: int in at:
		var block: Dictionary = sim.areas.list[area]
		for id: int in at[area].waiting.slice(0, maxi(0, block.settings.get("inspectors", 0) - at[area].inspecting)):
			var rules: Dictionary = sim.rules.customs
			sim.boxes[id].customs_until = now + lerpf(rules.inspect_hours_min, rules.inspect_hours_max, _roll(sim, id, "hours")) * 60.0


## The yard area box `id` is stacked in, or 0.
static func _stacked_in(sim: PortSim, id: int) -> int:
	for area: int in sim.area_stacks:
		if area in sim.areas.list and sim.area_stacks[area].has(id):
			return area
	return 0


## Hires `count` customs inspectors at customs block `area`.
static func hire(sim: PortSim, area: int, count: int) -> String:
	if count < 1:
		return "Hire at least one"
	if area not in sim.areas.list or sim.areas.list[area].type not in Areas.BLOCK_TYPES or sim.areas.list[area].settings.role != "customs":
		return "No customs block there"
	var cost: int = count * sim.rules.customs.inspector_cost
	if not sim._afford(cost):
		return "Not enough money"
	sim.ledger.post("equipment", -cost)
	sim.areas.list[area].settings.inspectors += count
	return ""


## Buys gate `gate` a scanner.
static func buy_scanner(sim: PortSim, gate: int) -> String:
	if gate not in sim.areas.list or sim.areas.kind_of(sim.areas.list[gate]) != "gate":
		return "No gate there"
	if sim.areas.list[gate].settings.scanner:
		return "This gate has a scanner already"
	if not sim._afford(sim.rules.customs.scanner_cost):
		return "Not enough money"
	sim.ledger.post("equipment", -sim.rules.customs.scanner_cost)
	sim.areas.list[gate].settings.scanner = true
	return ""


static func _scanner(sim: PortSim, terminal: int) -> bool:
	return sim.areas.list.values().any(func(a: Dictionary) -> bool: return a.terminal == terminal and sim.areas.kind_of(a) == "gate" and a.settings.get("scanner", false))


## A number from 0 to 1 for box `id` and `what`, the same every time for a
## game, without drawing on the game's own chances.
static func _roll(sim: PortSim, id: int, what: String) -> float:
	return (hash([sim.rng.seed, id, what]) & 0xFFFFFF) / float(0x1000000)
