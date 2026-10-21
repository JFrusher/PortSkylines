class_name HudDetails
extends RefCounted
## Formats numbers and builds structured stat cards and drawer rows for the HUD.
## Every metric here reads directly from the live PortSim state (kpis, finance,
## ledger, area_stacks, roads, vehicles), so no calculation is duplicated.

const GROUP_TRAFFIC := "Traffic"
const GROUP_LOGISTICS := "Logistics"
const GROUP_CONTAINERS := "Containers"
const GROUP_POWER := "Quay & Power"
const GROUP_FINANCE := "Finance"

const GROUPS: Array[String] = [
	GROUP_TRAFFIC,
	GROUP_LOGISTICS,
	GROUP_CONTAINERS,
	GROUP_POWER,
	GROUP_FINANCE,
]


## The cards a group shows: label, value, and an optional state (good, warn, danger, or "").
static func cards_for(group: String, sim: PortSim) -> Array[Dictionary]:
	match group:
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


## The headline figure a group's tab shows in the toolbar.
static func headline(group: String, sim: PortSim) -> String:
	var cards := cards_for(group, sim)
	return cards[0].value if not cards.is_empty() else ""


static func card(label: String, value: String, state := "") -> Dictionary:
	return {"label": label, "value": value, "state": state}


static func row(label: String, value: String) -> Dictionary:
	return {"label": label, "value": value}


## "$12,345" or "-$12,345".
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
	]


## Quay, cranes and channel figure cards.
static func power_cards(sim: PortSim) -> Array[Dictionary]:
	var anchored := 0
	for s: PortSim.Ship in sim.ships:
		if s.state == PortSim.Ship.State.ANCHORED:
			anchored += 1
	return [
		card("STS Cranes", str(sim.cranes.size())),
		card("Channel", "%.0f m" % sim.channel_depth),
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
		row("Channel depth", "%.1f metres" % sim.channel_depth),
		row("Ships at berth", str(sim.ships.size() - anchored)),
		row("Ships at anchor waiting", str(anchored)),
		row("Estimated power demand", "%d kW" % (sim.cranes.size() * 450)),
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
	return [
		row("Cash balance", dollars(sim.money)),
		row("Today's net", signed(sim.ledger.today_total())),
		row("Daily upkeep", dollars(sim.daily_upkeep()) + " / day"),
		row("Active loans", str(sim.finance.loans.size())),
		row("Consecutive days negative", str(sim.finance.days_negative)),
		row("Storage terms", "%d free days, $%d/box/day" % [sim.storage.free_days, sim.storage.fee]),
	]


## Full ledger breakdown text.
static func ledger_text(sim: PortSim) -> String:
	var ledger := sim.ledger
	var lines: Array[String] = ["Creative mode: cash never limits building" if sim.creative else "Today"]
	for category: String in ledger.categories:
		if ledger.today.has(category):
			lines.append("    %s  %s" % [ledger.categories[category], signed(ledger.today[category])])
	lines.append("    Net  %s" % signed(ledger.today_total()))
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
