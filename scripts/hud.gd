class_name Hud
extends CanvasLayer
## Toolbar, speed buttons and the money/status readout. Reports the player's
## choices through `tool` and `speed`; never changes the sim.

signal save_pressed
signal load_pressed
## A command for PortSim.apply, such as accepting an offer.
signal command_issued(command: Dictionary)
## shortcut: two buttons stand in for the new-game screen until M12 builds it.
signal new_game_pressed(creative: bool)

const BULLDOZE := -1
const CRANE := -2
const EXPORT_YARD := -3
const IMPORT_YARD := -4
const RTG := -5
const BUY_LAND := -6
const INSPECT := -7
const SPEEDS: Array[int] = [0, 1, 2, 3, 6]
## The build menu's categories, in key order 1-9.
const CATEGORIES: Array[String] = ["Roads", "Quay", "Cranes", "Yard", "Gate", "Land", "Bulldoze", "Inspect"]
const FLASH_SECONDS := 2.5
## UI scales the settings button steps through, and where the choice is kept.
const UI_SCALES: Array[float] = [1.0, 1.25, 1.5]
const SETTINGS_PATH := "user://settings.cfg"
const WEEKDAYS: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

var sim: PortSim
var tool: int = PortMap.Tile.ROAD
var speed := 1

var _money := Label.new()
var _readout := Label.new()
var _kpis := Label.new()
var _milestone := Label.new()
var _milestone_bar := ProgressBar.new()
var _clock := Label.new()
var _message := Label.new()
var _events: PanelContainer
var _ledger := Label.new()
var _borrow := HBoxContainer.new()
## Controls shown only once a milestone unlocks them: name -> controls.
var _gated := {}
var _contracts := VBoxContainer.new()
## The contracts version, sim and storage terms the contracts panel was last built for.
var _contracts_drawn := [-1, null, {}]
var _flash_left := 0.0
var _category_buttons: Array[Button] = []
## What the inspect panel shows, from Inspect.pick.
var _inspected: Variant
var _inspect_name := Label.new()
var _inspect_lines := Label.new()
var _guide_step := Label.new()
var _guide_text := Label.new()


func _ready() -> void:
	# Left column: city stats, then events and the panels the top-right buttons open.
	var left := _corner(Control.PRESET_TOP_LEFT)
	var stats := _panel(left)
	_money.theme_type_variation = "MoneyLabel"
	stats.add_child(_money)
	var progress := HBoxContainer.new()
	stats.add_child(progress)
	progress.add_child(_milestone)
	_milestone_bar.custom_minimum_size = Vector2(160, 8)
	_milestone_bar.show_percentage = false
	_milestone_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress.add_child(_milestone_bar)
	stats.add_child(_readout)
	_kpis.theme_type_variation = "MutedLabel"
	stats.add_child(_kpis)
	_panel(left).add_child(_message)
	_events = _panel_of(_message)
	var ledger_panel := _panel(left, "Ledger")
	ledger_panel.add_child(_ledger)
	ledger_panel.add_child(_borrow)
	for kind: String in sim.rules.loans:
		var terms: Dictionary = sim.rules.loans[kind]
		_gate("loans", _action_button(_borrow, "Borrow %s\n%d days, %d%% a year" % [_dollars(terms.amount), terms.days, roundi(terms.yearly_rate * 100)], {"op": "take_loan", "kind": kind}))
	var contracts_panel := _panel(left, "Contracts")
	contracts_panel.add_child(_contracts)
	var inspect_panel := _panel(left, "Inspect")
	_inspect_name.theme_type_variation = "ClockLabel"
	inspect_panel.add_child(_inspect_name)
	inspect_panel.add_child(_inspect_lines)
	_panel_of(inspect_panel).visible = false

	# Top right: the clock and speeds, then the panels and the game menu.
	var right := _corner(Control.PRESET_TOP_RIGHT)
	var time := _panel(right)
	var speeds_row := _row(time)
	_clock.theme_type_variation = "ClockLabel"
	speeds_row.add_child(_clock)
	var speeds := ButtonGroup.new()
	for s: int in SPEEDS:
		_button(speeds_row, "%d×" % s if s else "Pause", speeds, s == speed, func() -> void: speed = s)
	var menu := _row(time)
	_gate("ledger", _toggle(menu, "Ledger", _panel_of(ledger_panel)))
	_gate("contracts", _toggle(menu, "Contracts", _panel_of(contracts_panel)))
	_action(menu, "Save", save_pressed)
	_action(menu, "Load", load_pressed)
	for creative: bool in [false, true]:
		var button := Button.new()
		button.text = "New creative" if creative else "New game"
		button.pressed.connect(func() -> void: new_game_pressed.emit(creative))
		menu.add_child(button)
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)  # A missing file leaves the defaults.
	var scale_button := Button.new()
	scale_button.tooltip_text = "Interface size"
	scale_button.pressed.connect(func() -> void:
		_set_ui_scale(UI_SCALES[(UI_SCALES.find(get_tree().root.content_scale_factor) + 1) % UI_SCALES.size()], scale_button)
		settings.set_value("ui", "scale", get_tree().root.content_scale_factor)
		settings.save(SETTINGS_PATH))
	menu.add_child(scale_button)
	_set_ui_scale(settings.get_value("ui", "scale", 1.0), scale_button)

	var guide := _panel(right, "Getting started")
	_guide_step.theme_type_variation = "MutedLabel"
	guide.add_child(_guide_step)
	_guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_text.custom_minimum_size.x = 320
	guide.add_child(_guide_text)

	# Bottom centre: the items of the open category above the category bar; keys 1-9 open a category.
	var bottom := _corner(Control.PRESET_CENTER_BOTTOM)
	var items := _panel(bottom)
	var tools := ButtonGroup.new()
	var rows := {}
	for category: String in CATEGORIES:
		rows[category] = _row(items)
	var bar := _row(_panel(bottom))
	_panel_of(bar).theme_type_variation = "Toolbar"
	var categories := ButtonGroup.new()
	for category: String in CATEGORIES:
		var row: HBoxContainer = rows[category]
		row.visible = false
		var open := _button(bar, "%s\n%d" % [category, _category_buttons.size() + 1], categories, false, func() -> void:
			for other: HBoxContainer in rows.values():
				other.visible = other == row
			var first: Button = row.get_children().filter(func(b: Button) -> bool: return b.visible and b.toggle_mode).front()
			if first:
				first.button_pressed = true)
		open.theme_type_variation = "CategoryButton"
		open.custom_minimum_size = Vector2(84, 48)
		_category_buttons.append(open)
	for name: String in sim.rules.build_cost:
		var kind: int = PortMap.Tile[name.to_upper()]
		_item(_button(rows[{"road": "Roads", "quay": "Quay", "yard": "Yard", "gate": "Gate"}[name]], "%s\n$%d" % [name.capitalize(), sim.cost(kind)], tools, kind == tool, func() -> void: tool = kind))
	_gate("dredging", _item(_action_button(rows.Quay, "Dredge 1 m\n$%d" % sim.rules.channel.cost_per_metre, {"op": "dredge", "metres": 1})))
	_item(_button(rows.Cranes, "STS crane\n" + _dollars(sim.rules.sts_crane.cost), tools, false, func() -> void: tool = CRANE))
	_item(_action_button(rows.Cranes, "2 tractors\n$%d" % (sim.rules.tractor.cost * 2), {"op": "buy_tractors", "count": 2}))
	_item(_button(rows.Yard, "Import\nblock", tools, false, func() -> void: tool = IMPORT_YARD))
	_item(_button(rows.Yard, "Export\nblock", tools, false, func() -> void: tool = EXPORT_YARD))
	_gate("rtg", _item(_button(rows.Yard, "RTG\n$%d a tile" % sim.rules.yard_gear.rtg.cost_per_tile, tools, false, func() -> void: tool = RTG)))
	_gate("land", _category_buttons[CATEGORIES.find("Land")])
	_item(_button(rows.Land, "Land tile\n" + _dollars(sim.rules.land.price), tools, false, func() -> void: tool = BUY_LAND))
	_item(_button(rows.Bulldoze, "Bulldoze\ntile", tools, false, func() -> void: tool = BULLDOZE))
	_item(_button(rows.Inspect, "Inspect\nclick anything", tools, false, func() -> void: tool = INSPECT))
	_category_buttons[0].button_pressed = true


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var i := key.keycode - KEY_1
	if key.pressed and not key.echo and i >= 0 and i < _category_buttons.size() and _category_buttons[i].visible:
		_category_buttons[i].button_pressed = true


func _set_ui_scale(factor: float, button: Button) -> void:
	get_tree().root.content_scale_factor = factor
	button.text = "UI %d%%" % roundi(factor * 100)


## Opens the inspect panel on whatever is at `cell`.
func inspect(cell: Vector2i) -> void:
	_inspected = Inspect.pick(sim, cell)
	_panel_of(_inspect_name).visible = true


## Shows a short-lived message, such as why a build was refused.
func flash(text: String) -> void:
	_message.text = text
	_flash_left = FLASH_SECONDS


func _process(dt: float) -> void:
	var lorries := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "lorry").size()
	var anchored := sim.ships.filter(func(s: PortSim.Ship) -> bool: return s.state == PortSim.Ship.State.ANCHORED).size()
	_money.text = _dollars(sim.money)
	_readout.text = "Boxes %d   Ships %d (%d at anchor)   Tractors %d/%d   Lorries %d   Channel %.0f m" % [sim.delivered, sim.ships.size() - anchored, anchored, sim.vehicles.size() - lorries, sim.tractors, lorries, sim.channel_depth]
	var k := sim.kpis()
	_kpis.text = "Berth %.0f moves/h   Crane %.0f moves/h   Gate turn %.0f min\nYard %d%% full   %d boxes/day   Upkeep $%d/day" % [
		k.berth_moves_per_hour, k.crane_moves_per_hour, k.gate_turn_minutes, roundi(k.yard_use * 100), k.boxes_per_day, k.upkeep_per_day]
	_show_milestone()
	var minute := sim.clock.calendar_minutes()
	_clock.text = "%s  Day %d  %02d:%02d" % [WEEKDAYS[sim.clock.game_day() % 7], sim.clock.game_day(), sim.clock.game_hour(), int(minute) % 60]
	for name: String in _gated:
		for control: Control in _gated[name]:
			control.visible = sim.unlocked(name)
	_events.visible = _message.text != ""
	if _ledger.is_visible_in_tree():
		_ledger.text = _ledger_text()
	_show_guide()
	if _inspect_name.is_visible_in_tree():
		var lines := Inspect.describe(sim, _inspected)
		_panel_of(_inspect_name).visible = not lines.is_empty()
		if not lines.is_empty():
			_inspect_name.text = lines[0]
			_inspect_lines.text = "\n".join(lines.slice(1))
			_inspect_lines.visible = lines.size() > 1
	if _contracts.is_visible_in_tree() and _contracts_drawn != [sim.contracts.version, sim, sim.storage]:
		_draw_contracts()
	_flash_left -= dt
	if _flash_left <= 0.0:
		_message.text = "\n".join(sim.events.slice(-5).map(func(e: Dictionary) -> String: return "Day %d %02d:%02d  %s" % [int(e.minute / 1440), int(e.minute / 60) % 24, int(e.minute) % 60, e.text]))


func _gate(name: String, control: Control) -> Control:
	if not _gated.has(name):
		_gated[name] = []
	_gated[name].append(control)
	return control


## "$12,345" or "-$12,345".
static func _dollars(amount: int) -> String:
	var digits := str(absi(amount))
	for i in range(digits.length() - 3, 0, -3):
		digits = digits.insert(i, ",")
	return ("-$" if amount < 0 else "$") + digits


## The guided start's current step; its panel hides once the first ship is worked.
func _show_guide() -> void:
	var step := Guide.current(sim)
	var count := Guide.steps(sim).size()
	if step == count:
		_panel_of(_guide_text).visible = false
		return
	_guide_step.text = "Step %d of %d" % [step + 1, count]
	_guide_text.text = Guide.steps(sim)[step].text


func _show_milestone() -> void:
	var reached := sim.milestones_reached()
	var milestones := sim.milestones()
	_milestone_bar.visible = reached < milestones.size()
	if reached >= milestones.size():
		_milestone.text = "Milestone %d/%d   %d TEU" % [reached, milestones.size(), sim.teu_handled]
		return
	_milestone.text = "Milestone %d/%d   %d/%d TEU" % [reached, milestones.size(), sim.teu_handled, milestones[reached].teu]
	_milestone_bar.max_value = milestones[reached].teu
	_milestone_bar.value = sim.teu_handled


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
	_contracts.add_child(_label("Reputation   " + "    ".join(standing)))
	var terms := _row(_contracts)
	var free: int = sim.storage.free_days
	var fee: int = sim.storage.fee
	terms.add_child(_label("Storage: %d free days, then $%d a box a day" % [free, fee]))
	for change: Array in [["- day", -1, 0], ["+ day", 1, 0], ["- $10", 0, -10], ["+ $10", 0, 10]]:
		var button := Button.new()
		button.text = change[0]
		var free_days: int = free + change[1]
		var new_fee: int = fee + change[2]
		button.pressed.connect(func() -> void: command_issued.emit({"op": "set_storage", "free_days": free_days, "fee": new_fee}))
		terms.add_child(button)
	_contracts.add_child(_label("Offers" if not contracts.offers.is_empty() else "No offers: lines offer services once a crane stands at a berth, while reputation is good and berths have room"))
	for offer in contracts.offers:
		var row := _row(_contracts)
		row.add_child(_label("    " + _service_text(offer) + "   offer ends day %d" % int(offer.expires / SimClock.MINUTES_PER_DAY)))
		var id: int = offer.id
		var accept := Button.new()
		accept.text = "Accept"
		accept.pressed.connect(func() -> void: command_issued.emit({"op": "accept_offer", "id": id}))
		row.add_child(accept)
		var decline := Button.new()
		decline.text = "Decline"
		decline.pressed.connect(func() -> void: command_issued.emit({"op": "decline_offer", "id": id}))
		row.add_child(decline)
	_contracts.add_child(_label("Services" if not contracts.services.is_empty() else "No services yet"))
	for service in contracts.services:
		_contracts.add_child(_label("    " + _service_text(service)))


func _service_text(service: Dictionary) -> String:
	var start: int = service.start
	return "%s: %s every %s %02d:%02d, %d h window, %d moves" % [sim.contracts.name_of(service.line), service.kind, WEEKDAYS[start / SimClock.MINUTES_PER_DAY], start / 60 % 24, start % 60, roundi(service.window_hours), service.moves]


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


## A column pinned to a corner of the screen that grows away from it.
func _corner(preset: Control.LayoutPreset) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	column.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 12)
	column.grow_horizontal = {Control.PRESET_TOP_LEFT: Control.GROW_DIRECTION_END, Control.PRESET_TOP_RIGHT: Control.GROW_DIRECTION_BEGIN, Control.PRESET_CENTER_BOTTOM: Control.GROW_DIRECTION_BOTH}[preset]
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset == Control.PRESET_CENTER_BOTTOM else Control.GROW_DIRECTION_END
	return column


## A themed panel in the corner column `parent`, hugging that corner's side,
## with a header and close button when it has a `title`; returns the column
## inside it to fill.
func _panel(parent: Control, title := "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = {Control.GROW_DIRECTION_END: Control.SIZE_SHRINK_BEGIN, Control.GROW_DIRECTION_BEGIN: Control.SIZE_SHRINK_END, Control.GROW_DIRECTION_BOTH: Control.SIZE_SHRINK_CENTER}[parent.grow_horizontal]
	parent.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	if title == "":
		return column
	panel.theme_type_variation = "TitledPanel"
	var header := PanelContainer.new()
	header.theme_type_variation = "PanelHeader"
	column.add_child(header)
	var heading := HBoxContainer.new()
	header.add_child(heading)
	var label := _label(title)
	label.theme_type_variation = "PanelTitle"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(32, 32)
	close.tooltip_text = "Close " + title
	close.pressed.connect(func() -> void: panel.visible = false)
	heading.add_child(close)
	var body := MarginContainer.new()
	body.theme_type_variation = "PanelBody"
	column.add_child(body)
	var inner := VBoxContainer.new()
	body.add_child(inner)
	return inner


## The PanelContainer that `_panel` put `column` in.
func _panel_of(column: Control) -> PanelContainer:
	while column is not PanelContainer:
		column = column.get_parent() as Control
	return column as PanelContainer


## Styles `button` as a tile of the build menu.
func _item(button: Button) -> Button:
	button.theme_type_variation = "ItemButton"
	button.custom_minimum_size = Vector2(96, 56)
	return button


## A button in `row` that shows and hides `panel`, which starts hidden.
func _toggle(row: HBoxContainer, text: String, panel: Control) -> Button:
	panel.visible = false
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.toggled.connect(func(on: bool) -> void: panel.visible = on)
	panel.visibility_changed.connect(func() -> void: button.set_pressed_no_signal(panel.visible))
	row.add_child(button)
	return button


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
	button.toggled.connect(func(on: bool) -> void:
		if on:
			on_press.call())
	row.add_child(button)
	return button


## A plain button that issues `command` on each press.
func _action_button(row: HBoxContainer, text: String, command: Dictionary) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: command_issued.emit(command))
	row.add_child(button)
	return button


## A plain button that reports a press through `pressed_signal`.
func _action(row: HBoxContainer, text: String, pressed_signal: Signal) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed_signal.emit)
	row.add_child(button)
