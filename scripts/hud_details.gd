class_name HudDetails
extends RefCounted
## Formats numbers and builds structured stat cards and drawer rows for the HUD.
## Every metric here reads directly from the live PortSim state (kpis, finance,
## ledger, area_stacks, roads, vehicles), so no calculation is duplicated.

const GROUP_PORT := "Port"
const GROUP_TRAFFIC := "Traffic"
const GROUP_LOGISTICS := "Logistics"
const GROUP_CONTAINERS := "Containers"
const GROUP_POWER := "Quay & Power"
const GROUP_FINANCE := "Finance"

const GROUPS: Array[String] = [
	GROUP_PORT,
	GROUP_TRAFFIC,
	GROUP_LOGISTICS,
	GROUP_CONTAINERS,
	GROUP_POWER,
	GROUP_FINANCE,
]


## The cards a group shows: label, value, and an optional state (good, warn, danger, or "").
static func cards_for(group: String, sim: PortSim) -> Array[Dictionary]:
	match group:
		GROUP_PORT:
			return port_cards(sim)
		GROUP_TRAFFIC:
			return traffic_cards(sim)
		GROUP_LOGISTICS:
			return logistics_cards(sim)
		GROUP_CONTAINERS:
			return container_cards(sim)
		GROUP_POWER:
			return power_cards(sim)
		GROUP_FINANCE:
			return finance_cards(sim)
	return []


## The detailed rows for a group's drawer.
static func rows_for(group: String, sim: PortSim) -> Array[Dictionary]:
	match group:
		GROUP_PORT:
			return port_rows(sim)
		GROUP_TRAFFIC:
			return traffic_rows(sim)
		GROUP_LOGISTICS:
			return logistics_rows(sim)
		GROUP_CONTAINERS:
			return container_rows(sim)
		GROUP_POWER:
			return power_rows(sim)
		GROUP_FINANCE:
			return finance_rows(sim)
	return []


static func card(label: String, value: String, state := "") -> Dictionary:
	return {"label": label, "value": value, "state": state}


static func row(label: String, value: String) -> Dictionary:
	return {"label": label, "value": value}


## "$12,345" or "-$12,345".
## Dollars and cents, for amounts per move.
static func cents(amount: float) -> String:
	return "%s$%.2f" % ["-" if amount < 0.0 else "", absf(amount)]


static func dollars(amount: int) -> String:
	var digits := str(absi(amount))
	for i in range(digits.length() - 3, 0, -3):
		digits = digits.insert(i, ",")
	return ("-$" if amount < 0 else "$") + digits


## Signed format, e.g. "+$1,234" or "-$1,234".
static func signed(amount: int) -> String:
	var digits := str(absi(amount))
	for i in range(digits.length() - 3, 0, -3):
		digits = digits.insert(i, ",")
	if amount > 0:
		return "+$" + digits
	elif amount < 0:
		return "-$" + digits
	return "$" + digits


static func percent(fraction: float) -> String:
	return "%d%%" % roundi(fraction * 100.0)


static func yard_state(use: float) -> String:
	return "good" if use < 0.7 else ("warn" if use < 0.9 else "danger")


static func speed_state(speed: float) -> String:
	return "good" if speed >= 0.6 else ("warn" if speed >= 0.34 else "danger")


## Main KPI cards for the top status bar.
static func port_kpis(sim: PortSim) -> Array[Dictionary]:
	var k := sim.kpis()
	var lorries := 0
	for v: Vehicle in sim.vehicles:
		if v.kind == "lorry":
			lorries += 1
	var anchored := 0
	for s: PortSim.Ship in sim.ships:
		if s.state == PortSim.Ship.State.ANCHORED:
			anchored += 1
	return [
		card("BERTH RATE", "%.0f/h" % k.berth_moves_per_hour, "good" if k.berth_moves_per_hour >= 15.0 else ""),
		card("CRANE RATE", "%.0f/h" % k.crane_moves_per_hour, "good" if k.crane_moves_per_hour >= 15.0 else ""),
		card("GATE TURN", "%.0f min" % k.gate_turn_minutes, "warn" if k.gate_turn_minutes > 45.0 else ""),
		card("YARD FULL", percent(k.yard_use), yard_state(k.yard_use)),
		card("SHIPS", "%d (%d anc)" % [sim.ships.size(), anchored]),
		card("TRACTORS", "%d/%d" % [sim._tractors_out(), sim.tractors]),
	]


## Traffic figure cards.
## The port overview: its terminals, yesterday's moves and upkeep, then a
## card per terminal with yesterday's moves and its gate turn.
static func port_cards(sim: PortSim) -> Array[Dictionary]:
	var yesterday: int = sim.ledger.days[-1].moves.total if not sim.ledger.days.is_empty() else 0
	var working := sim.areas.terminals.keys().filter(func(t: int) -> bool: return sim.areas.terminal_error(t) == "").size()
	var cards: Array[Dictionary] = [
		card("TERMINALS", "%d of %d working" % [working, sim.areas.terminals.size()], "warn" if working < sim.areas.terminals.size() else ""),
		card("MOVES YESTERDAY", str(yesterday)),
		card("UPKEEP", dollars(sim.daily_upkeep()) + "/day"),
	]
	for terminal: int in sim.areas.terminals:
		var k := sim.terminal_kpis(terminal)
		var lacks := sim.areas.terminal_error(terminal)
		cards.append(card(sim.areas.terminal_name(terminal), "%d moves, %.0f min gate" % [k.moves_yesterday, k.gate_turn_minutes], "danger" if lacks else ""))
	return cards


## The port's totals, then each terminal's numbers.
static func port_rows(sim: PortSim) -> Array[Dictionary]:
	var k := sim.kpis()
	var rows: Array[Dictionary] = [
		row("Port", "%d terminals" % sim.areas.terminals.size()),
		row("    Berth moves / hour (last ship)", "%.1f" % k.berth_moves_per_hour),
		row("    Gate turn", "%.0f min" % k.gate_turn_minutes),
		row("    Yard use", percent(k.yard_use)),
		row("    Upkeep", dollars(k.upkeep_per_day) + " / day"),
	]
	var milestones := sim.milestones()
	if sim.milestones_reached() < milestones.size():
		rows.append(row("Milestone %d needs" % (sim.milestones_reached() + 1), ""))
		for need: String in sim.milestone_needs(milestones[sim.milestones_reached()]):
			rows.append(row("    " + need, ""))
	for key: String in sim.rules.objectives:
		var objective: Dictionary = sim.rules.objectives[key]
		if sim.milestones_reached() >= objective.after:
			rows.append(row(("Done: " if key in sim.objectives_done else "Objective: ") + objective.text, dollars(objective.cash)))
	for terminal: int in sim.areas.terminals:
		var t := sim.terminal_kpis(terminal)
		var lacks := sim.areas.terminal_error(terminal)
		rows.append(row(sim.areas.terminal_name(terminal), lacks if lacks else "working"))
		rows.append(row("    Berth moves / hour (last ship)", "%.1f" % t.berth_moves_per_hour))
		rows.append(row("    Crane moves / hour (last ship)", "%.1f" % t.crane_moves_per_hour))
		rows.append(row("    Gate turn", "%.0f min" % t.gate_turn_minutes))
		rows.append(row("    Yard use", percent(t.yard_use)))
		rows.append(row("    Yesterday", "%d moves, %s in" % [t.moves_yesterday, dollars(t.income_yesterday)]))
		rows.append(row("    Upkeep", dollars(t.upkeep_per_day) + " / day"))
	return rows


static func traffic_cards(sim: PortSim) -> Array[Dictionary]:
	var lorries := 0
	var waiting := 0
	for v: Vehicle in sim.vehicles:
		if v.kind == "lorry":
			lorries += 1
		if v.waited > 0:
			waiting += 1
	var tractors_out := sim._tractors_out()
	return [
		card("Tractors", "%d/%d" % [tractors_out, sim.tractors], "warn" if tractors_out == sim.tractors and sim.tractors > 0 else ""),
		card("Lorries", str(lorries)),
		card("Waiting", str(waiting), "danger" if waiting > 5 else ("warn" if waiting > 0 else "good")),
		card("Roads", "%d segs" % sim.roads.segments.size()),
	]


static func traffic_rows(sim: PortSim) -> Array[Dictionary]:
	var lorries := 0
	var waiting := 0
	for v: Vehicle in sim.vehicles:
		if v.kind == "lorry":
			lorries += 1
		if v.waited > 0:
			waiting += 1
	return [
		row("Active tractors", "%d of %d" % [sim._tractors_out(), sim.tractors]),
		row("External lorries in port", str(lorries)),
		row("Vehicles waiting in traffic", str(waiting)),
		row("Road segments", str(sim.roads.segments.size())),
		row("Road nodes", str(sim.roads.nodes.size())),
	]


## Logistics figure cards.
static func logistics_cards(sim: PortSim) -> Array[Dictionary]:
	var k := sim.kpis()
	return [
		card("Berth rate", "%.0f/h" % k.berth_moves_per_hour, "good" if k.berth_moves_per_hour >= 15.0 else ""),
		card("Crane rate", "%.0f/h" % k.crane_moves_per_hour, "good" if k.crane_moves_per_hour >= 15.0 else ""),
		card("Gate turn", "%.0f min" % k.gate_turn_minutes, "warn" if k.gate_turn_minutes > 45.0 else ""),
		card("Dwell", "%.1f h" % k.import_dwell_hours),
	]


static func logistics_rows(sim: PortSim) -> Array[Dictionary]:
	var k := sim.kpis()
	return [
		row("Berth throughput", "%.1f moves / hour" % k.berth_moves_per_hour),
		row("Crane productivity", "%.1f moves / hour / crane" % k.crane_moves_per_hour),
		row("Average gate turn time", "%.1f minutes" % k.gate_turn_minutes),
		row("Average import dwell", "%.1f hours" % k.import_dwell_hours),
		row("Boxes delivered today", str(sim.delivered)),
		row("Boxes delivered yesterday", str(k.boxes_per_day)),
	]


## Containers figure cards.
static func container_cards(sim: PortSim) -> Array[Dictionary]:
	var k := sim.kpis()
	var held := 0
	var count_20 := 0
	var count_40 := 0
	for area_id: int in sim.area_stacks:
		if area_id in sim.areas.list:
			var stacks: AreaStacks = sim.area_stacks[area_id]
			held += stacks.boxes().size()
			for b: int in stacks.boxes():
				var t: int = stacks._teu.get(b, 1)
				if t == 1:
					count_20 += 1
				else:
					count_40 += 1
	return [
		card("In Yard", str(held)),
		card("Fullness", percent(k.yard_use), yard_state(k.yard_use)),
		card("20 ft", str(count_20)),
		card("40 ft", str(count_40)),
	]


static func container_rows(sim: PortSim) -> Array[Dictionary]:
	var k := sim.kpis()
	var capacity := 0
	var held := 0
	var count_20 := 0
	var count_40 := 0
	for area_id: int in sim.area_stacks:
		if area_id in sim.areas.list:
			var stacks: AreaStacks = sim.area_stacks[area_id]
			var gear: String = sim.areas.list[area_id].settings.gear
			capacity += stacks.stacks.size() * sim.rules.yard_gear[gear].tiers
			held += stacks.boxes().size()
			for b: int in stacks.boxes():
				var t: int = stacks._teu.get(b, 1)
				if t == 1:
					count_20 += 1
				else:
					count_40 += 1
	return [
		row("Boxes stored in yard", str(held)),
		row("Total yard block capacity", str(capacity)),
		row("Yard utilization", percent(k.yard_use)),
		row("20 ft containers", str(count_20)),
		row("40 ft containers", str(count_40)),
		row("Total TEU handled", str(sim.teu_handled)),
		row("Total boxes delivered", str(sim.delivered)),
		row("Of those, by rail", str(sim.by_rail)),
		row("Of those, by barge", str(sim.by_barge)),
	]


## Quay, cranes and ship lane figure cards.
static func power_cards(sim: PortSim) -> Array[Dictionary]:
	var anchored := 0
	for s: PortSim.Ship in sim.ships:
		if s.state == PortSim.Ship.State.ANCHORED:
			anchored += 1
	return [
		card("STS Cranes", str(sim.cranes.size())),
		card("Ship lanes", str(sim.ship_lanes.segments.size()), "warn" if sim.ship_lanes.segments.is_empty() else ""),
		card("Ships", str(sim.ships.size())),
		card("At Anchor", str(anchored), "warn" if anchored > 0 else ""),
	]


static func power_rows(sim: PortSim) -> Array[Dictionary]:
	var anchored := 0
	for s: PortSim.Ship in sim.ships:
		if s.state == PortSim.Ship.State.ANCHORED:
			anchored += 1
	var aprons := 0
	for a: Dictionary in sim.areas.list.values():
		if a.type == "quay_apron":
			aprons += 1
	return [
		row("STS cranes operational", str(sim.cranes.size())),
		row("Quay aprons", str(aprons)),
		row("Ship lanes", "%d, with %d in the open sea" % [sim.ship_lanes.segments.size(), Marine.edge_nodes(sim, false).size()]),
		row("Ships at berth", str(sim.ships.size() - anchored)),
		row("Ships at anchor waiting", str(anchored)),
		row("Estimated power demand", "%d kW" % (sim.cranes.size() * 450)),
		row("Reefers plugged in", str(AreaFlow.plugged_reefers(sim))),
		row("Reefers off a plug, fined after %d min" % sim.rules.reefers.plug_minutes, str(AreaFlow.unplugged_reefers(sim))),
		row("Reefer power now", "%.0f kW%s" % [AreaFlow.plugged_reefers(sim) * sim.reefer_kw(), ", a hot day" if sim.reefer_kw() > sim.rules.reefers.kw else ""]),
		row("Today's reefer peak", "%.0f kW" % sim.power.peak_kw),
	]


## Finance figure cards.
static func finance_cards(sim: PortSim) -> Array[Dictionary]:
	var net := sim.ledger.today_total()
	return [
		card("Cash", dollars(sim.money), "good" if sim.money >= 0 else "danger"),
		card("Today", signed(net), "good" if net >= 0 else "danger"),
		card("Upkeep", dollars(sim.daily_upkeep()) + "/day"),
		card("Loans", "%d active" % sim.finance.loans.size(), "warn" if sim.finance.loans.size() > 0 else ""),
	]


static func finance_rows(sim: PortSim) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		row("Cash balance", dollars(sim.money)),
		row("Today's net", signed(sim.ledger.today_total())),
		row("Daily upkeep", dollars(sim.daily_upkeep()) + " / day"),
		row("Active loans", str(sim.finance.loans.size())),
		row("Consecutive days negative", str(sim.finance.days_negative)),
		row("Storage terms", "%d free days, $%d/box/day" % [sim.storage.free_days, sim.storage.fee]),
	]
	rows.append_array(per_move_rows(sim))
	return rows


## The money per crane move, the port's main lever: over the closed days,
## each ledger line and the net, then each line's and each terminal's.
static func per_move_rows(sim: PortSim) -> Array[Dictionary]:
	var per := per_move(sim)
	if per.moves == 0:
		return [row("Per move", "no moves in the closed days yet")]
	var rows: Array[Dictionary] = [row("Per move, last %d days" % per.days, "%d moves" % per.moves)]
	for category: String in sim.ledger.categories:
		if per.categories.has(category):
			rows.append(row("    " + sim.ledger.categories[category], cents(per.categories[category])))
	rows.append(row("    Net", cents(per.net)))
	for line: String in per.lines:
		rows.append(row(sim.contracts.name_of(line), "%d moves, %s a move" % [per.lines[line].moves, cents(per.lines[line].income)]))
	for terminal: int in per.terminals:
		var t: Dictionary = per.terminals[terminal]
		rows.append(row(sim.areas.terminals[terminal].name if terminal in sim.areas.terminals else "Terminal %d" % terminal, "%d moves, %s in, %s upkeep a move" % [t.moves, cents(t.income), cents(t.upkeep)]))
	return rows


## Over the ledger's closed days: {"days", "moves", "net" and "categories"
## (category -> amount) per move, "lines" (line -> {"moves", "income" per
## move}), "terminals" (terminal -> {"moves", "income" and "upkeep" per
## move, upkeep at today's rate for each day)}.
static func per_move(sim: PortSim) -> Dictionary:
	var days := sim.ledger.days
	var moves := 0
	var net := 0
	var totals := {}
	var tallies := {"lines": {}, "terminals": {}}
	for day: Dictionary in days:
		moves += day.moves.total
		net += day.closed - day.opened
		for category: String in day.lines:
			totals[category] = totals.get(category, 0) + day.lines[category]
		for group: String in tallies:
			for key: Variant in day.moves[group]:
				var sum: Array = tallies[group].get(key, [0, 0])
				tallies[group][key] = [sum[0] + day.moves[group][key][0], sum[1] + day.moves[group][key][1]]
	var per := {"days": days.size(), "moves": moves, "net": 0.0, "categories": {}, "lines": {}, "terminals": {}}
	if moves == 0:
		return per
	per.net = float(net) / moves
	for category: String in totals:
		per.categories[category] = float(totals[category]) / moves
	for line: String in tallies.lines:
		per.lines[line] = {"moves": tallies.lines[line][0], "income": float(tallies.lines[line][1]) / tallies.lines[line][0]}
	var upkeep := sim.upkeep_parts()
	for terminal: int in tallies.terminals:
		var counted: Array = tallies.terminals[terminal]
		per.terminals[terminal] = {"moves": counted[0], "income": float(counted[1]) / counted[0], "upkeep": upkeep.get(terminal, 0.0) * days.size() / counted[0]}
	return per


## Full ledger breakdown text.
static func ledger_text(sim: PortSim) -> String:
	var ledger := sim.ledger
	var lines: Array[String] = ["Creative mode: cash never limits building" if sim.creative else "Today"]
	for category: String in ledger.categories:
		if ledger.today.has(category):
			lines.append("    %s  %s" % [ledger.categories[category], signed(ledger.today[category])])
	lines.append("    Net  %s" % signed(ledger.today_total()))
	if ledger.terminals.size() > 1:
		lines.append("Today by terminal")
		for terminal: int in ledger.terminals:
			var section: Dictionary = ledger.terminals[terminal]
			var net := 0
			var parts: Array[String] = []
			for category: String in ledger.categories:
				if section.has(category):
					net += section[category]
					parts.append("%s %s" % [ledger.categories[category], signed(section[category])])
			lines.append("    %s  net %s   %s" % ["Port-wide" if terminal == 0 else sim.areas.terminal_name(terminal), signed(net), "   ".join(parts)])
	for loan in sim.finance.loans:
		lines.append("Loan (%s): $%d owed, $%d a day for %d days" % [loan.kind, loan.owed, mini(loan.payment, loan.owed), loan.days_left])
	for closed: Dictionary in sim.scoreboard.slice(-2):
		lines.append("Year %d: %.1f h in port per call, %.1f moves an hour, %.0f min gate turn" % [closed.year, closed.port_hours, closed.moves_per_hour, closed.turn_minutes])
	if not ledger.days.is_empty():
		lines.append("Recent days")
	for i in range(ledger.days.size() - 1, -1, -1):
		var day: Dictionary = ledger.days[i]
		var parts: Array[String] = []
		for category: String in ledger.categories:
			if day.lines.has(category):
				parts.append("%s %s" % [ledger.categories[category], signed(day.lines[category])])
		lines.append("    Day %d  net %s   %s" % [day.day, signed(day.closed - day.opened), "   ".join(parts)])
	return "\n".join(lines)
