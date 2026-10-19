class_name Hud
extends CanvasLayer
## Toolbar, speed buttons and the money/status readout. Reports the player's
## choices through `tool` and `speed`; never changes the sim.

signal save_pressed
signal load_pressed
## A command for PortSim.apply, such as accepting an offer.
signal command_issued(command: Dictionary)
## shortcut: two buttons stand in for the new-game screen until M11 builds it.
signal new_game_pressed(creative: bool)

const BULLDOZE := -1
const CRANE := -2
const EXPORT_YARD := -3
const IMPORT_YARD := -4
const RTG := -5
const BUY_LAND := -6
const SPEEDS: Array[int] = [0, 1, 2, 3, 6]
const FLASH_SECONDS := 2.5
const WEEKDAYS: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

var sim: PortSim
var tool: int = PortMap.Tile.ROAD
var speed := 1

var _readout := Label.new()
var _kpis := Label.new()
var _message := Label.new()
var _ledger := Label.new()
var _borrow := HBoxContainer.new()
## Controls shown only once a milestone unlocks them: name -> controls.
var _gated := {}
var _contracts := VBoxContainer.new()
## The contracts version, sim and storage terms the contracts panel was last built for.
var _contracts_drawn := [-1, null, {}]
var _flash_left := 0.0


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := _row(root)
	top.add_child(_outlined(_readout))
	var speeds := ButtonGroup.new()
	for s: int in SPEEDS:
		_button(top, "%d×" % s if s else "Pause", speeds, s == speed, func() -> void: speed = s)
	var ledger_button := Button.new()
	ledger_button.text = "Ledger"
	ledger_button.toggle_mode = true
	ledger_button.toggled.connect(func(on: bool) -> void:
		_ledger.visible = on
		_borrow.visible = on)
	top.add_child(ledger_button)
	_gate("ledger", ledger_button)
	var contracts_button := Button.new()
	contracts_button.text = "Contracts"
	contracts_button.toggle_mode = true
	contracts_button.toggled.connect(func(on: bool) -> void: _contracts.visible = on)
	top.add_child(contracts_button)
	_gate("contracts", contracts_button)
	var game := _row(root)
	_action(game, "Save", save_pressed)
	_action(game, "Load", load_pressed)
	for creative: bool in [false, true]:
		var button := Button.new()
		button.text = "New creative game" if creative else "New game"
		button.pressed.connect(func() -> void: new_game_pressed.emit(creative))
		game.add_child(button)
	root.add_child(_outlined(_kpis))
	root.add_child(_outlined(_message))
	_ledger.visible = false
	root.add_child(_outlined(_ledger))
	_borrow.visible = false
	root.add_child(_borrow)
	for kind: String in sim.rules.loans:
		var terms: Dictionary = sim.rules.loans[kind]
		var button := Button.new()
		button.text = "Borrow $%d  (%d days, %d%% a year)" % [terms.amount, terms.days, roundi(terms.yearly_rate * 100)]
		button.pressed.connect(func() -> void: command_issued.emit({"op": "take_loan", "kind": kind}))
		_borrow.add_child(button)
		_gate("loans", button)
	_contracts.visible = false
	root.add_child(_contracts)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spacer)

	var tools := ButtonGroup.new()
	var bar := _row(root)
	for name: String in sim.rules.build_cost:
		var kind: int = PortMap.Tile[name.to_upper()]
		var label := "%s $%d" % [name.capitalize(), sim.cost(kind)]
		_button(bar, label, tools, kind == tool, func() -> void: tool = kind)
	_button(bar, "Crane $%d" % sim.rules.sts_crane.cost, tools, false, func() -> void: tool = CRANE)
	_button(bar, "Import", tools, false, func() -> void: tool = IMPORT_YARD)
	_button(bar, "Export", tools, false, func() -> void: tool = EXPORT_YARD)
	_gate("rtg", _button(bar, "RTG $%d" % sim.rules.yard_gear.rtg.cost_per_tile, tools, false, func() -> void: tool = RTG))
	var tractors := Button.new()
	tractors.text = "+2 tractors $%d" % (sim.rules.tractor.cost * 2)
	tractors.pressed.connect(func() -> void: command_issued.emit({"op": "buy_tractors", "count": 2}))
	bar.add_child(tractors)
	_gate("land", _button(bar, "Land $%d" % sim.rules.land.price, tools, false, func() -> void: tool = BUY_LAND))
	var dredge := Button.new()
	dredge.text = "Dredge 1 m $%d" % sim.rules.channel.cost_per_metre
	dredge.pressed.connect(func() -> void: command_issued.emit({"op": "dredge", "metres": 1}))
	bar.add_child(dredge)
	_gate("dredging", dredge)
	_button(bar, "Bulldoze", tools, false, func() -> void: tool = BULLDOZE)


## Shows a short-lived message, such as why a build was refused.
func flash(text: String) -> void:
	_message.text = text
	_flash_left = FLASH_SECONDS


func _process(dt: float) -> void:
	var lorries := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "lorry").size()
	var anchored := sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.state == PortSim.Ship.State.ANCHORED).size()
	_readout.text = "$%d    Boxes %d    Ships %d (%d at anchorage)    Tractors %d/%d    Lorries %d    Channel %.0f m" % [sim.money, sim.delivered, sim.ships.size() - anchored, anchored, sim.vehicles.size() - lorries, sim.tractors, lorries, sim.channel_depth]
	var k := sim.kpis()
	_kpis.text = _milestone_text() + "    Berth %.0f moves/h    Crane %.0f moves/h    Gate turn %.0f min    Yard %d%% full    %d boxes/day    Upkeep $%d/day" % [
		k.berth_moves_per_hour, k.crane_moves_per_hour, k.gate_turn_minutes, roundi(k.yard_use * 100), k.boxes_per_day, k.upkeep_per_day]
	for name: String in _gated:
		for control: Control in _gated[name]:
			control.visible = sim.unlocked(name)
	if _ledger.visible:
		_ledger.text = _ledger_text()
	if _contracts.visible and _contracts_drawn != [sim.contracts.version, sim, sim.storage]:
		_draw_contracts()
	_flash_left -= dt
	if _flash_left <= 0.0:
		_message.text = "\n".join(sim.events.slice(-5).map(func(e: Dictionary) -> String: return "Day %d %02d:%02d  %s" % [int(e.minute / 1440), int(e.minute / 60) % 24, int(e.minute) % 60, e.text]))


func _gate(name: String, control: Control) -> Control:
	if not _gated.has(name):
		_gated[name] = []
	_gated[name].append(control)
	return control


func _milestone_text() -> String:
	var reached := sim.milestones_reached()
	var milestones := sim.milestones()
	if reached >= milestones.size():
		return "Milestone %d/%d  %d TEU" % [reached, milestones.size(), sim.teu_handled]
	return "Milestone %d/%d  %d/%d TEU" % [reached, milestones.size(), sim.teu_handled, milestones[reached].teu]


## Today by category, then each of the last days, all read from the ledger.
func _ledger_text() -> String:
	var ledger := sim.ledger
	var lines: Array[String] = ["Creative mode: cash never limits building" if sim.creative else "Today"]
	for category: String in ledger.categories:
		if ledger.today.has(category):
			lines.append("    %s  %+d" % [ledger.categories[category], ledger.today[category]])
	lines.append("    Net  %+d" % ledger.today_total())
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
				parts.append("%s %+d" % [ledger.categories[category], day.lines[category]])
		lines.append("    Day %d  net %+d   %s" % [day.day, day.closed - day.opened, "   ".join(parts)])
	return "\n".join(lines)


## Reputation per line, the offers with Accept and Decline, and the agreed services.
func _draw_contracts() -> void:
	_contracts_drawn = [sim.contracts.version, sim, sim.storage.duplicate()]
	for child in _contracts.get_children():
		child.queue_free()
	var contracts := sim.contracts
	var standing: Array[String] = []
	for line: String in contracts.reputation:
		standing.append("%s %d" % [contracts.name_of(line), roundi(contracts.reputation[line])])
	_contracts.add_child(_outlined(_label("Reputation   " + "    ".join(standing))))
	var terms := _row(_contracts)
	var free: int = sim.storage.free_days
	var fee: int = sim.storage.fee
	terms.add_child(_outlined(_label("Storage: %d free days, then $%d a box a day" % [free, fee])))
	for change: Array in [["- day", -1, 0], ["+ day", 1, 0], ["- $10", 0, -10], ["+ $10", 0, 10]]:
		var button := Button.new()
		button.text = change[0]
		var free_days: int = free + change[1]
		var new_fee: int = fee + change[2]
		button.pressed.connect(func() -> void: command_issued.emit({"op": "set_storage", "free_days": free_days, "fee": new_fee}))
		terms.add_child(button)
	_contracts.add_child(_outlined(_label("Offers" if not contracts.offers.is_empty() else "No offers: lines offer services while reputation is good and berths have room")))
	for offer in contracts.offers:
		var row := _row(_contracts)
		row.add_child(_outlined(_label("    " + _service_text(offer) + "   offer ends day %d" % int(offer.expires / SimClock.MINUTES_PER_DAY))))
		var id: int = offer.id
		var accept := Button.new()
		accept.text = "Accept"
		accept.pressed.connect(func() -> void: command_issued.emit({"op": "accept_offer", "id": id}))
		row.add_child(accept)
		var decline := Button.new()
		decline.text = "Decline"
		decline.pressed.connect(func() -> void: command_issued.emit({"op": "decline_offer", "id": id}))
		row.add_child(decline)
	_contracts.add_child(_outlined(_label("Services" if not contracts.services.is_empty() else "No services yet")))
	for service in contracts.services:
		_contracts.add_child(_outlined(_label("    " + _service_text(service))))


func _service_text(service: Dictionary) -> String:
	var start: int = service.start
	return "%s: %s every %s %02d:%02d, %d h window, %d moves" % [sim.contracts.name_of(service.line), service.kind, WEEKDAYS[start / SimClock.MINUTES_PER_DAY], start / 60 % 24, start % 60, roundi(service.window_hours), service.moves]


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


func _button(row: HBoxContainer, text: String, group: ButtonGroup, pressed: bool, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = pressed
	button.pressed.connect(on_press)
	row.add_child(button)
	return button


## A plain button that reports a press through `pressed_signal`.
func _action(row: HBoxContainer, text: String, pressed_signal: Signal) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed_signal.emit)
	row.add_child(button)


func _outlined(label: Label) -> Label:
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	return label
