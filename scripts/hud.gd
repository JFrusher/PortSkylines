class_name Hud
extends CanvasLayer
## Toolbar, speed buttons and the KPI/figure dashboard. Reports the player's
## choices through `tool` and `speed`; never changes the sim.

const HudDetails := preload("res://scripts/hud_details.gd")

signal save_pressed
signal load_pressed
## A command for PortSim.apply, such as accepting an offer.
signal command_issued(command: Dictionary)
## shortcut: two buttons stand in for the new-game screen until M12 builds it.
signal new_game_pressed(creative: bool)

const BULLDOZE := -1
const CRANE := -2
const BUY_LAND := -6
const INSPECT := -7
## Draws a road of road_type on the 4 m grid by dragging.
const DRAW_ROAD := -8
## Drags an area of area_type out along a road's edge.
const DRAW_AREA := -9
## The build menu row each area type sits in.
const AREA_ROWS := {"yard_block": "Yard", "depot": "Yard", "quay_apron": "Quay", "gate": "Gate"}
const SPEEDS: Array[int] = [0, 1, 2, 3, 6]
## The build menu's categories, in key order 1-8.
const CATEGORIES: Array[String] = ["Roads", "Quay", "Cranes", "Yard", "Gate", "Land", "Bulldoze", "Inspect"]
const FLASH_SECONDS := 2.5
## UI scales the settings button steps through, and where the choice is kept.
const UI_SCALES: Array[float] = [1.0, 1.25, 1.5]
const SETTINGS_PATH := "user://settings.cfg"
const WEEKDAYS: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const REFRESH_SECONDS := 0.25

var sim: PortSim
var tool := DRAW_ROAD
## The road type DRAW_ROAD draws, a key of rules.road_types.
var road_type := ""
## The area type DRAW_AREA drags out, a key of rules.area_types, and for a
## gate whether it is built on both sides of the road.
var area_type := ""
var two_way := false
var speed := 1

var _money := Label.new()
var _milestone := Label.new()
var _milestone_bar := ProgressBar.new()
var _kpi_cards: Array[Dictionary] = []
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
var _refresh_left := 0.0
var _category_buttons: Array[Button] = []
var _figure_buttons := {}
## What the inspect panel shows, from Inspect.pick.
var _inspected: Variant
var _inspect_name := Label.new()
var _inspect_lines := Label.new()
## Buttons for the inspected area's terminal, and what they were last built for.
var _inspect_actions := HFlowContainer.new()
var _actions_drawn := []
var _guide_step := Label.new()
var _guide_text := Label.new()

## The details drawer panel and its internal layout.
var _drawer_panel: PanelContainer
var _drawer_title_label: Label
var _drawer_cards_container: HBoxContainer
var _drawer_rows_container: VBoxContainer
var _drawer_extra_container: VBoxContainer
var _active_drawer_group := ""
## The bottom column (build menu and toolbar), and the left column's
## scrolling panel bodies, fitted between the stats and the build menu.
var _bottom: Control
var _left_scrolls: Array[ScrollContainer] = []
## The one confirmation dialog, reused for every question.
var _confirm := ConfirmationDialog.new()
## The pause menu (Esc), the speed buttons, and the speed to go back to.
var _menu: PanelContainer
var _speed_buttons: Array[Button] = []
var _speed_before_menu := 1


func _ready() -> void:
	# Left column: city stats, headline KPI cards, detail drawer, and panels.
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

	# Headline KPI cards row across the top of the port status panel.
	var kpi_row := HBoxContainer.new()
	kpi_row.add_theme_constant_override("separation", 6)
	stats.add_child(kpi_row)
	_build_kpi_cards(kpi_row)

	_panel(left).add_child(_message)
	_events = _panel_of(_message)

	# The Details Drawer: shows detailed metrics for whichever figure group is open.
	_build_drawer(left)

	var contracts_panel := _panel(left, "Contracts")
	contracts_panel.add_child(_contracts)

	var inspect_panel := _panel(left, "Inspect")
	_inspect_name.theme_type_variation = "ClockLabel"
	inspect_panel.add_child(_inspect_name)
	inspect_panel.add_child(_inspect_lines)
	inspect_panel.add_child(_inspect_actions)
	_panel_of(inspect_panel).visible = false

	# Top right: the clock and speeds, then the panels and the game menu.
	var right := _corner(Control.PRESET_TOP_RIGHT)
	var time := _panel(right)
	var speeds_row := _row(time)
	_clock.theme_type_variation = "ClockLabel"
	speeds_row.add_child(_clock)
	var speeds := ButtonGroup.new()
	for s: int in SPEEDS:
		_speed_buttons.append(_button(speeds_row, "%d×" % s if s else "Pause", speeds, s == speed, func() -> void: speed = s))
	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.tooltip_text = "Save, load, new game and settings (Esc)"
	menu_button.pressed.connect(_toggle_menu)
	speeds_row.add_child(menu_button)

	# The pause menu: the game's file and settings actions, as CS's Esc menu.
	var middle := _corner(Control.PRESET_CENTER)
	var menu := _panel(middle, "Menu")
	_menu = _panel_of(menu)
	_menu.visible = false
	_menu.visibility_changed.connect(func() -> void:
		if not _menu.visible:
			_set_speed(_speed_before_menu))
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func() -> void: _menu.visible = false)
	menu.add_child(resume)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(func() -> void:
		save_pressed.emit()
		_menu.visible = false)
	menu.add_child(save)
	add_child(_confirm)
	_ask(menu, "Load", "Load the saved game? The port you're playing is lost unless it is saved.", func() -> void:
		_menu.visible = false
		load_pressed.emit())
	for creative: bool in [false, true]:
		_ask(menu, "New creative game" if creative else "New game", "Start a new %s? The port you're playing is lost unless it is saved." % ("creative game" if creative else "game"), func() -> void:
			_menu.visible = false
			new_game_pressed.emit(creative))

	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
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

	# Bottom centre: unified toolbar containing build menu categories and figure groups.
	var bottom := _corner(Control.PRESET_CENTER_BOTTOM)
	_bottom = bottom
	var items := _panel(bottom)
	var tools := ButtonGroup.new()
	var rows := {}
	for category: String in CATEGORIES:
		rows[category] = _row(items)

	var bar_container := _panel(bottom)
	var bar := _row(bar_container)
	_panel_of(bar).theme_type_variation = "Toolbar"

	# Group 1: Build Menu Categories
	var build_group := PanelContainer.new()
	build_group.theme_type_variation = "ToolbarGroup"
	bar.add_child(build_group)
	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 4)
	build_group.add_child(cat_row)

	var categories := ButtonGroup.new()
	for category: String in CATEGORIES:
		var row: HBoxContainer = rows[category]
		row.visible = false
		var open := _button(cat_row, "%s\n%d" % [category, _category_buttons.size() + 1], categories, false, func() -> void:
			for other: HBoxContainer in rows.values():
				other.visible = other == row
			var first: Button = row.get_children().filter(func(b: Button) -> bool: return b.visible and b.toggle_mode).front()
			if first:
				first.button_pressed = true)
		open.theme_type_variation = "CategoryButton"
		open.custom_minimum_size = Vector2(72, 48)
		_category_buttons.append(open)

	# Group 2: Figure / Info-Views Group
	var figures_group := PanelContainer.new()
	figures_group.theme_type_variation = "ToolbarGroup"
	bar.add_child(figures_group)
	var fig_row := HBoxContainer.new()
	fig_row.add_theme_constant_override("separation", 4)
	figures_group.add_child(fig_row)

	# Names only: the numbers live in the info bar and in each panel.
	for group_name: String in HudDetails.GROUPS:
		var fig_btn := Button.new()
		fig_btn.theme_type_variation = "CategoryButton"
		fig_btn.custom_minimum_size = Vector2(72, 48)
		fig_btn.toggle_mode = true
		fig_btn.text = group_name
		fig_btn.pressed.connect(func() -> void: _toggle_drawer(group_name))
		fig_row.add_child(fig_btn)
		_figure_buttons[group_name] = fig_btn
	var contracts_button := _toggle(fig_row, "Contracts", _panel_of(contracts_panel))
	contracts_button.theme_type_variation = "CategoryButton"
	contracts_button.custom_minimum_size = Vector2(72, 48)
	contracts_button.toggled.connect(func(on: bool) -> void:
		if on:
			_show_only(_panel_of(contracts_panel)))
	_gate("contracts", contracts_button)

	# Build tool item buttons
	for key: String in sim.rules.road_types:
		var road: Dictionary = sim.rules.road_types[key]
		_item(_button(rows.Roads, "%s\n$%d per 4 m" % [road.name, road.cost_per_cell], tools, false, func() -> void:
			tool = DRAW_ROAD
			road_type = key)).tooltip_text = _road_tip(road)
	for key: String in sim.rules.area_types:
		var area: Dictionary = sim.rules.area_types[key]
		# shortcut: a depot has no job in the sim yet, so it isn't offered; show it with M11's AGV depot.
		if area.kind == "depot":
			continue
		var detail := "%d lanes, $%d a cell" % [area.depth - 2, area.cost_per_cell] if area.kind == "gate" else "$%d per 4 m cell" % area.cost_per_cell
		_item(_button(rows[AREA_ROWS[area.kind]], "%s\n%s" % [area.name, detail], tools, false, func() -> void:
			tool = DRAW_AREA
			area_type = key
			two_way = false)).tooltip_text = _area_tip(area, false)
		if area.kind == "gate":
			_item(_button(rows.Gate, "Two-way %s\n%d lanes each way" % [area.name.to_lower(), area.depth - 2], tools, false, func() -> void:
				tool = DRAW_AREA
				area_type = key
				two_way = true)).tooltip_text = _area_tip(area, true)
	var dredge := _gate("dredging", _item(_action_button(rows.Quay, "Dredge 1 m\n" + HudDetails.dollars(sim.rules.channel.cost_per_metre), {"op": "dredge", "metres": 1})))
	dredge.tooltip_text = "Deepens the channel 1 m, so ships with a deeper draft can call.\n%s a metre, then %s a metre every %d days to keep it." % [HudDetails.dollars(sim.rules.channel.cost_per_metre), HudDetails.dollars(sim.rules.channel.maintenance_per_metre), sim.rules.channel.maintenance_days]
	var crane: Dictionary = sim.rules.sts_crane
	_item(_button(rows.Cranes, "STS crane\n" + HudDetails.dollars(crane.cost), tools, false, func() -> void: tool = CRANE)).tooltip_text = "A ship-to-shore crane on a quay apron. %d moves an hour, reaches %d rows across a ship.\n%s, upkeep $%d a day, arrives %d day after ordering." % [crane.rate, crane.outreach, HudDetails.dollars(crane.cost), sim.rules.upkeep.sts_crane, crane.lead_days]
	_item(_action_button(rows.Cranes, "2 tractors\n$%d" % (sim.rules.tractor.cost * 2), {"op": "buy_tractors", "count": 2})).tooltip_text = "Terminal tractors carry boxes between cranes and yard blocks at %d km/h.\n$%d each, upkeep $%d a day each." % [roundi(sim.rules.tractor.speed * 0.06), sim.rules.tractor.cost, sim.rules.upkeep.tractor]
	_gate("land", _category_buttons[CATEGORIES.find("Land")])
	_item(_button(rows.Land, "Land tile\n" + HudDetails.dollars(sim.rules.land.price), tools, false, func() -> void: tool = BUY_LAND)).tooltip_text = "Buys an %d m square of land to build on.\n%s, upkeep $%d a day." % [sim.rules.land.metres, HudDetails.dollars(sim.rules.land.price), sim.rules.land.upkeep]
	_item(_button(rows.Bulldoze, "Bulldoze\nroad or area", tools, false, func() -> void: tool = BULLDOZE)).tooltip_text = "Click a road or area to remove it. Boxes stored in an area are lost."
	_item(_button(rows.Inspect, "Inspect\nclick anything", tools, false, func() -> void: tool = INSPECT)).tooltip_text = "Click a ship, crane, vehicle or area to see what it's doing. Click a box to follow it."
	_category_buttons[0].button_pressed = true


func _build_kpi_cards(row: HBoxContainer) -> void:
	for kpi: Dictionary in HudDetails.port_kpis(sim):
		var card := PanelContainer.new()
		card.theme_type_variation = "StatCard"
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		card.add_child(col)

		var lbl := Label.new()
		lbl.theme_type_variation = "StatLabel"
		lbl.text = kpi.label
		col.add_child(lbl)

		var val := Label.new()
		val.theme_type_variation = "StatValue"
		val.add_theme_font_size_override("font_size", 16)
		val.text = kpi.value
		col.add_child(val)

		row.add_child(card)
		_kpi_cards.append({"panel": card, "label": lbl, "value": val, "state": ""})


func _build_drawer(left: Control) -> void:
	var drawer := _panel(left, "Details")
	_drawer_panel = _panel_of(drawer)
	_drawer_panel.visible = false

	# Find the panel title label so we can change it dynamically
	for child in _drawer_panel.find_children("", "Label", true, false):
		if (child as Label).theme_type_variation == "PanelTitle":
			_drawer_title_label = child as Label
			break

	# When the drawer is closed via the '×' button, deselect the figure buttons
	_drawer_panel.visibility_changed.connect(func() -> void:
		if not _drawer_panel.visible:
			_active_drawer_group = ""
			for g: String in _figure_buttons:
				(_figure_buttons[g] as Button).set_pressed_no_signal(false))

	_drawer_cards_container = HBoxContainer.new()
	_drawer_cards_container.add_theme_constant_override("separation", 6)
	drawer.add_child(_drawer_cards_container)

	var div := Panel.new()
	div.theme_type_variation = "Divider"
	div.custom_minimum_size = Vector2(0, 1)
	drawer.add_child(div)

	_drawer_rows_container = VBoxContainer.new()
	_drawer_rows_container.add_theme_constant_override("separation", 4)
	drawer.add_child(_drawer_rows_container)

	_drawer_extra_container = VBoxContainer.new()
	drawer.add_child(_drawer_extra_container)
	_ledger.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ledger.custom_minimum_size.x = 340
	_drawer_extra_container.add_child(_ledger)
	_drawer_extra_container.add_child(_borrow)

	for kind: String in sim.rules.loans:
		var terms: Dictionary = sim.rules.loans[kind]
		_gate("loans", _action_button(_borrow, "Borrow %s\n%d days, %d%% a year" % [HudDetails.dollars(terms.amount), terms.days, roundi(terms.yearly_rate * 100)], {"op": "take_loan", "kind": kind}))


func _toggle_drawer(group_name: String) -> void:
	if _active_drawer_group == group_name and _drawer_panel.visible:
		_close_drawer()
		return
	_active_drawer_group = group_name
	_show_only(_drawer_panel)
	if _drawer_title_label:
		_drawer_title_label.text = "%s Details" % group_name
	_drawer_panel.visible = true
	for g: String in _figure_buttons:
		(_figure_buttons[g] as Button).set_pressed_no_signal(g == group_name)
	_fill_drawer(group_name)


func _close_drawer() -> void:
	_active_drawer_group = ""
	_drawer_panel.visible = false
	for g: String in _figure_buttons:
		(_figure_buttons[g] as Button).set_pressed_no_signal(false)


func _fill_drawer(group_name: String) -> void:
	# Populate cards
	for child in _drawer_cards_container.get_children():
		child.queue_free()
	for c: Dictionary in HudDetails.cards_for(group_name, sim):
		var card := PanelContainer.new()
		card.theme_type_variation = _card_style(c.get("state", ""))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		card.add_child(col)

		var lbl := Label.new()
		lbl.theme_type_variation = "StatLabel"
		lbl.text = c.label
		col.add_child(lbl)

		var val := Label.new()
		val.theme_type_variation = "StatValue"
		val.add_theme_font_size_override("font_size", 16)
		val.text = c.value
		col.add_child(val)
		_drawer_cards_container.add_child(card)

	# Populate detail rows
	for child in _drawer_rows_container.get_children():
		child.queue_free()
	for r: Dictionary in HudDetails.rows_for(group_name, sim):
		var line := HBoxContainer.new()
		_drawer_rows_container.add_child(line)

		var lbl := Label.new()
		lbl.text = r.label
		lbl.theme_type_variation = "MutedLabel"
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(lbl)

		var val := Label.new()
		val.text = r.value
		val.theme_type_variation = "StatValue"
		val.add_theme_font_size_override("font_size", 14)
		line.add_child(val)

	# Extra content for Finance (ledger text + loan borrowing)
	_drawer_extra_container.visible = (group_name == HudDetails.GROUP_FINANCE)
	if group_name == HudDetails.GROUP_FINANCE:
		_ledger.text = HudDetails.ledger_text(sim)


func _card_style(state: String) -> String:
	match state:
		"good":
			return "GoodCard"
		"warn":
			return "WarnCard"
		"danger":
			return "DangerCard"
	return "StatCard"


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_toggle_menu()
		return
	var i := key.keycode - KEY_1
	if key.pressed and not key.echo and i >= 0 and i < _category_buttons.size() and not _category_buttons[i].disabled:
		_category_buttons[i].button_pressed = true


func _set_ui_scale(factor: float, button: Button) -> void:
	get_tree().root.content_scale_factor = factor
	button.text = "UI %d%%" % roundi(factor * 100)


## Opens the inspect panel on whatever is at grid cell `cell`.
func inspect(cell: Vector2i) -> void:
	_inspected = Inspect.pick(sim, cell)
	_show_only(_panel_of(_inspect_name))


## Shows a short-lived message, such as why a build was refused.
func flash(text: String) -> void:
	_message.text = text
	_flash_left = FLASH_SECONDS


func _process(dt: float) -> void:
	_money.text = HudDetails.dollars(sim.money)
	_show_milestone()

	var minute := sim.clock.calendar_minutes()
	_clock.text = "%s  Day %d  %02d:%02d" % [WEEKDAYS[sim.clock.game_day() % 7], sim.clock.game_day(), sim.clock.game_hour(), int(minute) % 60]

	# Locked controls show greyed, their tooltip naming the milestone.
	for name: String in _gated:
		var locked := sim.lock_error(name)
		for control: Control in _gated[name]:
			if not is_instance_valid(control):
				continue
			if not control.has_meta("tip"):
				control.set_meta("tip", control.tooltip_text)
			(control as BaseButton).disabled = locked != ""
			control.tooltip_text = locked if locked else control.get_meta("tip")

	_events.visible = _message.text != ""
	_show_guide()
	_fit_left_panels()

	if _inspect_name.is_visible_in_tree():
		var lines := Inspect.describe(sim, _inspected)
		_panel_of(_inspect_name).visible = not lines.is_empty()
		if not lines.is_empty():
			_inspect_name.text = lines[0]
			_inspect_lines.text = "\n".join(lines.slice(1))
			_inspect_lines.visible = lines.size() > 1
		if _actions_drawn != [sim, sim.areas.version, _inspected]:
			_draw_inspect_actions()

	if _contracts.is_visible_in_tree() and _contracts_drawn != [sim.contracts.version, sim, sim.storage]:
		_draw_contracts()

	# Throttled refresh of the info bar and the open drawer
	_refresh_left -= dt
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		_update_kpis()
		if _drawer_panel.visible and _active_drawer_group != "":
			_refresh_drawer()

	_flash_left -= dt
	if _flash_left <= 0.0:
		_message.text = "\n".join(sim.events.slice(-5).map(func(e: Dictionary) -> String: return "Day %d %02d:%02d  %s" % [int(e.minute / 1440), int(e.minute / 60) % 24, int(e.minute) % 60, e.text]))


func _update_kpis() -> void:
	var kpis := HudDetails.port_kpis(sim)
	for i in mini(kpis.size(), _kpi_cards.size()):
		var data: Dictionary = kpis[i]
		var item: Dictionary = _kpi_cards[i]
		(item.value as Label).text = data.value
		var state: String = data.state
		if item.state != state:
			item.state = state
			(item.panel as PanelContainer).theme_type_variation = _card_style(state)


func _refresh_drawer() -> void:
	# Update values of drawer cards without reallocating when counts match
	var current_cards := HudDetails.cards_for(_active_drawer_group, sim)
	var card_nodes := _drawer_cards_container.get_children()
	if card_nodes.size() == current_cards.size():
		for i in card_nodes.size():
			var card_panel := card_nodes[i] as PanelContainer
			var col := card_panel.get_child(0) as VBoxContainer
			var val_lbl := col.get_child(1) as Label
			val_lbl.text = current_cards[i].value
			card_panel.theme_type_variation = _card_style(current_cards[i].get("state", ""))
	else:
		_fill_drawer(_active_drawer_group)

	# Update values of drawer rows without reallocating when counts match
	var current_rows := HudDetails.rows_for(_active_drawer_group, sim)
	var row_nodes := _drawer_rows_container.get_children()
	if row_nodes.size() == current_rows.size():
		for i in row_nodes.size():
			var line := row_nodes[i] as HBoxContainer
			var val_lbl := line.get_child(1) as Label
			val_lbl.text = current_rows[i].value

	if _active_drawer_group == HudDetails.GROUP_FINANCE:
		_ledger.text = HudDetails.ledger_text(sim)


## Opens the pause menu, pausing the game, or closes it and resumes.
func _toggle_menu() -> void:
	if _menu.visible:
		_menu.visible = false
		return
	_speed_before_menu = speed
	_set_speed(0)
	_menu.visible = true


func _set_speed(value: int) -> void:
	_speed_buttons[SPEEDS.find(value)].button_pressed = true


## Shows `panel`, one of the left column's titled panels, and hides the
## others, so one detail panel is open at a time, as in Cities: Skylines.
func _show_only(panel: PanelContainer) -> void:
	for scroll in _left_scrolls:
		_panel_of(scroll).visible = _panel_of(scroll) == panel


## Gives each open left-column panel the height left above the build menu,
## scrolling what doesn't fit.
func _fit_left_panels() -> void:
	for scroll in _left_scrolls:
		var panel := _panel_of(scroll)
		if not panel.visible:
			continue
		# Down to the first bottom panel beside it, so a narrow build-item row
		# to its right doesn't cut it short.
		var limit := get_viewport().get_visible_rect().size.y
		var across := panel.get_global_rect()
		for below: Control in _bottom.get_children():
			var rect := below.get_global_rect()
			if below.visible and rect.position.x < across.end.x and rect.end.x > across.position.x:
				limit = minf(limit, rect.position.y)
		var wanted := (scroll.get_child(0) as Control).get_combined_minimum_size().y
		var room := limit - 12 - scroll.get_global_rect().position.y - 16
		scroll.custom_minimum_size.y = clampf(room, 48.0, wanted)


## A button in `row` that asks `question` and calls `then` if confirmed.
func _ask(row: Container, text: String, question: String, then: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void:
		_confirm.title = text
		_confirm.dialog_text = question
		_confirm.ok_button_text = text
		for c: Dictionary in _confirm.confirmed.get_connections():
			_confirm.confirmed.disconnect(c.callable)
		_confirm.confirmed.connect(then, CONNECT_ONE_SHOT)
		_confirm.popup_centered())
	row.add_child(button)


## A road type's tooltip: lanes, who may use it, cost and upkeep.
func _road_tip(road: Dictionary) -> String:
	var lanes := "%d lanes one way" % road.forward if road.backward == 0 else "%d lane%s each way" % [road.forward, "" if road.forward == 1 else "s"]
	var who := "Lorries and tractors" if road.lorries else "Tractors only, no lorries"
	return "%s. %s.\n$%d per 4 m, upkeep $%.2f per 4 m a day." % [lanes, who, road.cost_per_cell, road.upkeep_per_cell]


## An area type's tooltip: what it does, its size, cost and upkeep.
func _area_tip(area: Dictionary, both_sides: bool) -> String:
	var what: String = {
		"yard_block": "Stores boxes in stacks behind a truck lane where vehicles hand them over",
		"quay_apron": "Where ships berth and STS cranes work. Reaches the water from a road %d–%d m in" % [Grid.metres(area.depth + 1), Grid.metres(area.max_depth + 1)],
		"gate": "Checks lorries in and out: %d lanes, each a booth" % (area.depth - 2),
	}[area.kind]
	if both_sides:
		what += ", built on both sides of the road so lorries check in and out without turning round"
	var deep := "%d m deep" % Grid.metres(area.depth) if area.max_depth == area.depth else "%d–%d m deep" % [Grid.metres(area.depth), Grid.metres(area.max_depth)]
	return "%s.\n%s, at least %d m long. $%d per 4 m cell, upkeep $%.2f per cell a day." % [what, deep, Grid.metres(area.min_length), area.cost_per_cell, area.upkeep_per_cell]


func _gate(name: String, control: Control) -> Control:
	if not _gated.has(name):
		_gated[name] = []
	_gated[name].append(control)
	return control


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


## For an inspected area: join each other terminal, or split off into a new one.
func _draw_inspect_actions() -> void:
	_actions_drawn = [sim, sim.areas.version, _inspected]
	for child in _inspect_actions.get_children():
		child.queue_free()
	if not (_inspected is Dictionary and _inspected.area in sim.areas.list):
		return
	var id: int = _inspected.area
	var own: int = sim.areas.list[id].terminal
	for terminal: int in sim.areas.terminals:
		if terminal != own:
			_action_button(_inspect_actions, "Join %s" % sim.areas.terminals[terminal].name, {"op": "set_terminal", "id": id, "terminal": terminal})
	if sim.areas.list.values().filter(func(a: Dictionary) -> bool: return a.terminal == own).size() > 1:
		_action_button(_inspect_actions, "New terminal", {"op": "set_terminal", "id": id, "terminal": 0})
	if sim.areas.kind_of(sim.areas.list[id]) == "yard_block":
		var settings: Dictionary = sim.areas.list[id].settings
		for role: String in ["import", "export"]:
			if role != settings.role:
				_action_button(_inspect_actions, "Make %s block" % role, {"op": "set_area", "id": id, "settings": {"role": role}})
		for gear: String in sim.rules.yard_gear:
			if gear != settings.gear:
				var button := _action_button(_inspect_actions, "Use %s" % sim.rules.yard_gear[gear].name, {"op": "set_area", "id": id, "settings": {"gear": gear}})
				button.disabled = sim.lock_error(gear) != ""
				button.tooltip_text = sim.lock_error(gear) if button.disabled else "Stacks %d high, upkeep $%d a machine a day" % [sim.rules.yard_gear[gear].tiers, sim.rules.yard_gear[gear].upkeep_per_machine]
	if sim.areas.kind_of(sim.areas.list[id]) == "gate":
		for level: String in sim.rules.gate_levels:
			if level != sim.areas.list[id].settings.level and sim.lock_error(level) == "":
				_action_button(_inspect_actions, "Make %s" % sim.rules.gate_levels[level].name, {"op": "set_area", "id": id, "settings": {"level": level}})


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
	column.grow_horizontal = {Control.PRESET_TOP_LEFT: Control.GROW_DIRECTION_END, Control.PRESET_TOP_RIGHT: Control.GROW_DIRECTION_BEGIN, Control.PRESET_CENTER_BOTTOM: Control.GROW_DIRECTION_BOTH, Control.PRESET_CENTER: Control.GROW_DIRECTION_BOTH}[preset]
	column.grow_vertical = {Control.PRESET_TOP_LEFT: Control.GROW_DIRECTION_END, Control.PRESET_TOP_RIGHT: Control.GROW_DIRECTION_END, Control.PRESET_CENTER_BOTTOM: Control.GROW_DIRECTION_BEGIN, Control.PRESET_CENTER: Control.GROW_DIRECTION_BOTH}[preset]
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
	if parent.grow_horizontal != Control.GROW_DIRECTION_END:
		body.add_child(inner)
		return inner
	# Left-column panels scroll inside the room above the build menu.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	_left_scrolls.append(scroll)
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
func _action_button(row: Container, text: String, command: Dictionary) -> Button:
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
