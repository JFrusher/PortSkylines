class_name Hud
extends CanvasLayer
## Toolbar, speed buttons and the KPI/figure dashboard. Reports the player's
## choices through `tool` and `speed`; never changes the sim.

const HudDetails := preload("res://scripts/hud_details.gd")

signal save_pressed
signal load_pressed
## A command for PortSim.apply, such as accepting an offer.
signal command_issued(command: Dictionary)
## shortcut: two buttons stand in for the new-game screen until M14 builds it.
## A new game: creative or not, on the data's map or a generated coast.
signal new_game_pressed(creative: bool, generated: bool)
## Debug builds only: start the big test port with every feature in use.
signal mega_port_pressed
## The showcase port, from the pause menu in debug builds.
signal showcase_port_pressed
## A scenario chosen from the menu: on its own map, or a fresh coast.
signal scenario_pressed(key: String, fresh: bool)
## A recent event was clicked: the camera goes to grid cell `cell`.
signal event_picked(cell: Vector2i)

const BULLDOZE := -1
const CRANE := -2
const INSPECT := -7
## Draws a road of road_type on the 4 m grid by dragging.
const DRAW_ROAD := -8
## Drags an area of area_type out along a road's edge.
const DRAW_AREA := -9
## Places a berth of berth on the coast by clicking.
const BUILD_BERTH := -10
## Draws a ship lane of lane_type on the water by dragging.
const DRAW_LANE := -11
## Drags out an anchorage on the water.
const BUILD_ANCHORAGE := -12
## Places a pilot station or tug depot (marine_base) on the water by clicking.
const BUILD_MARINE := -13
## Drags a breakwater across the water.
const BUILD_BREAKWATER := -14
## Drags a road's node, or the point it bends toward, to reshape it (Move It).
const MOVE_ROAD := -15
## The build menu row each area type sits in.
const AREA_ROWS := {"yard_block": "Yard", "depot": "Yard", "workshop": "Yard", "fire_station": "Yard", "agv_depot": "Yard", "transfer_block": "Yard", "tree_belt": "Yard", "quay_apron": "Quay", "gate": "Gate", "parking": "Gate"}
const SPEEDS: Array[int] = [0, 1, 2, 3, 6]
## The build menu's categories, in key order 1-8.
## The build toolbar's categories, keys 1 to 7, and each one's icon. With
## none open, a click inspects what is under it, as in Cities: Skylines.
const CATEGORIES: Array[String] = ["Roads", "Quay", "Cranes", "Yard", "Gate", "Water", "Bulldoze"]
const CATEGORY_ICONS := {"Roads": "roads", "Quay": "quay", "Cranes": "cranes", "Yard": "yard", "Gate": "gate", "Water": "water", "Bulldoze": "bulldoze"}
## The status bar along the bottom edge, in pixels before the interface scale.
const STATUS_BAR_HEIGHT := 44.0
const FLASH_SECONDS := 2.5
## UI scales the settings button steps through, and where the choice is kept.
const UI_SCALES: Array[float] = [1.0, 1.25, 1.5]
const SETTINGS_PATH := "user://settings.cfg"
## Each event kind's switch in the menu: [label, tooltip].
const EVENT_NAMES := {
	"storms": ["Storms", "Storms come with a day's forecast; strong wind stops cranes."],
	"tides": ["Tides", "The water rises and falls twice a day; the deepest ships wait for high water."],
	"breakdowns": ["Breakdowns", "Quay cranes and yard gear break down now and then; a workshop's mechanics repair them."],
	"fires": ["Fires", "Now and then a yard block or a ship at berth catches fire, likelier by dangerous goods; fire engines and fireboats put it out."],
}
## The menu's switch for each event kind.
var _event_checks := {}
const WEEKDAYS: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const REFRESH_SECONDS := 0.25

var sim: PortSim
var tool := INSPECT
## The road type DRAW_ROAD draws, a key of rules.road_types.
var road_type := ""
## With DRAW_ROAD, clicking a road changes it to road_type instead of drawing.
var upgrade_roads := false
## How DRAW_ROAD lays a road, as Cities: Skylines' road tools: "straight" by
## a drag; "curved" by three clicks, start, control point, end; "freeform"
## by a drag that carries on along the road it starts from; "roundabout" by
## a drag from its centre out to its ring.
var road_mode := "straight"
## The Shape buttons (Roads and Water rows), which show and change road_mode.
var _shapes: Array[Button] = []
const ROAD_MODES := ["straight", "curved", "freeform", "roundabout"]
## Roads snap to the 4 m grid, straight or at 45°, as before M10, when on.
var grid_snap := false
## The area type DRAW_AREA drags out, a key of rules.area_types, and for a
## gate whether it is built on both sides of the road.
var area_type := ""
var two_way := false
## The gate tool builds on both sides of the road when this is on.
## The berth BUILD_BERTH places, a key of rules.berths.
var berth := ""
## The way it faces in degrees, or PortSim.AUTO_ANGLE for the way that fills
## least; and that way where the mouse is, which main sets, for Turn to turn from.
var berth_angle := PortSim.AUTO_ANGLE
var berth_auto := 0.0
## The ship lane DRAW_LANE draws, a key of rules.water.lanes.
var lane_type := ""
## What BUILD_MARINE places: "pilot_station", "tug_depot" or "services_jetty".
var marine_base := ""
## The crane CRANE places, a key of rules.sts_cranes.
var crane_kind := ""
var speed := 1

var _money := Label.new()
var _milestone := Label.new()
var _milestone_bar := ProgressBar.new()
## Today's takings so far, beside the money in the status bar.
var _today := Label.new()
var _clock := Label.new()
## The latest event, or a flash; pressing it lists the recent ones.
var _message := Button.new()
var _events: PanelContainer
var _event_list := VBoxContainer.new()
## The sim, last event and count the event list was last built for.
var _events_drawn := []
var _ledger := Label.new()
var _borrow := HBoxContainer.new()
## A switch per policy, in rules.policies' order.
var _policies := VBoxContainer.new()

## The town next door's fixes, under the Port drawer's rows.
var _town_actions := HBoxContainer.new()
## Controls shown only once a milestone unlocks them: name -> controls.
var _gated := {}
## The berth board, opened by the Contracts button.
var _board := BerthBoard.new()
## The port map, where terminals are painted and land bought, opened by Map.
var _map := PortMap.new()
var _flash_left := 0.0
## How long the newest message stays out beside the news icon, and the
## message it was shown for.
const NEWS_SECONDS := 6.0
## The advisor's button, the guide step it last saw, and whether that step is unread.
var _advisor := Button.new()
var _guide_seen := []
var _advisor_new := false
var _news_left := 0.0
var _news_seen := []
var _refresh_left := 0.0
var _category_buttons: Array[Button] = []
## The build toolbar's flyout, holding the open category's tools.
var _flyout: PanelContainer
## The Statistics window's tabs, by figure group, and the tab it opens on.
var _stats_tabs := {}
## The column the big windows open in, top centre.
var _windows: VBoxContainer
## The inspect panel's column, the cell it is beside, and how main turns a
## grid cell into a point on screen.
var _inspect_column: VBoxContainer
var _inspect_cell := Grid.NONE
var to_screen: Callable
var _last_drawer_group := HudDetails.GROUP_PORT
## The info views popup, the view chosen there ("" for none), and its legend.
var _views: PanelContainer
var _info_mode := ""
var _view_legend: HBoxContainer
## What the inspect panel shows, from Inspect.pick.
var _inspected: Variant
## Where the inspect panel is docked, below the news icon.
const INSPECT_AT := Vector2(8, 72)
## The inspect panel's header label, naming what is inspected.
var _inspect_name: Label
## The inspect panel itself (its header holds _inspect_name, in a panel of its own).
var _inspect_panel: PanelContainer
var _inspect_bulldoze := Button.new()
var _selected: Array[Vector2i] = []
var _selected_for := []
## The inspect panel's body: overview and sections of controls.
var _inspect_view := InspectPanel.new()
## Buttons for the inspected area's terminal, and what they were last built for.
## Actions not yet given controls of their own, in the panel's Actions section.
var _inspect_actions: HFlowContainer = _inspect_view.legacy
var _actions_drawn := []
var _guide_step := Label.new()
var _guide_text := Label.new()

## The details drawer panel and its internal layout.
var _drawer_panel: PanelContainer
var _drawer_cards_container: HBoxContainer
var _drawer_rows_container: VBoxContainer
var _drawer_extra_container: VBoxContainer
var _active_drawer_group := ""
## The open drawer's map colours, from WorldView.INFO_LEGENDS.
var _legend := HBoxContainer.new()
## The bottom column (build menu and toolbar), and the left column's
## scrolling panel bodies, fitted between the stats and the build menu.
var _bottom: Control
var _left_scrolls: Array[ScrollContainer] = []
## The one confirmation dialog, reused for every question.
var _confirm := ConfirmationDialog.new()
## The pause menu (Esc), the speed buttons, and the speed to go back to.
var _menu: PanelContainer
## The scenario list, the scenario's goals as it is played, and the morning
## paper with the last report it showed.
var _scenarios: PanelContainer
var _goals := Label.new()
var _paper: PanelContainer
var _paper_text := RichTextLabel.new()
var _paper_shown := -1
## The game the goals and paper were last shown for: a new game shows them afresh.
var _shown_for: PortSim
var _speed_buttons: Array[Button] = []
## The screen dimmed behind the pause menu.
var _dim := ColorRect.new()
## Whether the sky and lights follow the clock (a setting); off, it stays noon.
var day_night := true
var _speed_before_menu := 1
## Text beside the mouse, such as the road under it.
var _hint := Label.new()


func _ready() -> void:
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.visible = false
	add_child(_hint)
	# Left column: the news, then the inspect panel.
	var left := _corner(Control.PRESET_TOP_LEFT)
	var ticker := _panel(left)
	# The news: an icon, with each new message popping out beside it for a
	# few seconds, as CS's Chirper; the icon opens the recent ones.
	var top := _row(ticker)
	var news := Button.new()
	news.toggle_mode = true
	news.tooltip_text = "Recent news"
	news.custom_minimum_size = Vector2(36, 36)
	var paper_icon := UiIcon.make("news", 22.0)
	paper_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 7)
	news.add_child(paper_icon)
	news.toggled.connect(func(on: bool) -> void: _event_list.visible = on)
	top.add_child(news)
	# The advisor: the guide's current step, opened from its icon, which
	# pulses when there is a new step and never opens over the port by itself.
	_advisor.toggle_mode = true
	_advisor.tooltip_text = "Advisor: what to do next"
	_advisor.custom_minimum_size = Vector2(36, 36)
	var face := UiIcon.make("advisor", 22.0)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 7)
	_advisor.add_child(face)
	top.add_child(_advisor)
	_message.theme_type_variation = "EventLink"
	_message.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_message.tooltip_text = "Show recent news"
	_message.pressed.connect(func() -> void: news.button_pressed = not news.button_pressed)
	top.add_child(_message)
	_event_list.visible = false
	ticker.add_child(_event_list)
	_events = _panel_of(_message)

	# The Statistics window: each figure group's numbers on its own tab.
	# Top centre, a little down, so it ends above the toolbar.
	_windows = _corner(Control.PRESET_CENTER_TOP)
	_windows.offset_top = 12.0
	_build_drawer(_windows)

	# The inspect panel stands beside what was clicked, as in Cities: Skylines.
	_inspect_column = _corner(Control.PRESET_TOP_LEFT)
	_inspect_column.position = INSPECT_AT
	var inspect_panel := _panel(_inspect_column, "Inspect")
	_inspect_panel = _panel_of(inspect_panel)
	# Its header names what is inspected, with locate and bulldoze beside close.
	var inspect_heading: HBoxContainer = _panel_of(inspect_panel).get_child(0).get_child(0).get_child(0)
	_inspect_name = inspect_heading.get_child(0)
	var locate := Button.new()
	locate.tooltip_text = "Move the camera to it"
	locate.pressed.connect(func() -> void: event_picked.emit(_inspect_cell))
	_inspect_bulldoze.tooltip_text = "Bulldoze it"
	for pair: Array in [[locate, "locate"], [_inspect_bulldoze, "bulldoze"]]:
		var button: Button = pair[0]
		button.custom_minimum_size = Vector2(32, 32)
		var icon := UiIcon.make(pair[1], 18.0)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 7)
		button.add_child(icon)
	_inspect_bulldoze.pressed.connect(func() -> void: command_issued.emit({"op": "remove_area", "id": _inspected.area}))
	for button: Button in [locate, _inspect_bulldoze]:
		inspect_heading.add_child(button)
		inspect_heading.move_child(button, inspect_heading.get_child_count() - 2)
	inspect_panel.add_child(_inspect_view)
	_inspect_view.command_issued.connect(func(command: Dictionary) -> void: command_issued.emit(command))
	_panel_of(inspect_panel).visible = false

	# Top right: the scenario and the guide, for now.
	var right := _corner(Control.PRESET_TOP_RIGHT)
	_build_status_bar()
	_build_views()

	# The pause menu: the game's file and settings actions, as CS's Esc menu.
	# The game dims behind it, and it holds the game's actions on the left and
	# its settings on the right.
	var dim := _dim
	dim.color = Color(0, 0, 0, 0.45)
	dim.visible = false
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var middle := _corner(Control.PRESET_CENTER)
	var frame := _panel(middle, "Menu")
	_menu = _panel_of(frame)
	_menu.visible = false
	_menu.visibility_changed.connect(func() -> void:
		dim.visible = _menu.visible
		if not _menu.visible:
			_set_speed(_speed_before_menu))
	var sides := _row(frame)
	sides.add_theme_constant_override("separation", 24)
	var menu := VBoxContainer.new()
	menu.custom_minimum_size.x = 220
	sides.add_child(menu)
	var options := VBoxContainer.new()
	options.custom_minimum_size.x = 220
	sides.add_child(options)
	var heading := _label("Settings")
	heading.theme_type_variation = "CategoryHeader"
	options.add_child(heading)
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
			new_game_pressed.emit(creative, false))
	_ask(menu, "New game, new coast", "Start a new game on a coast drawn for it: its own bays, river and islands. The port you're playing is lost unless it is saved.", func() -> void:
		_menu.visible = false
		new_game_pressed.emit(false, true))
	var scenarios_button := Button.new()
	scenarios_button.text = "Scenarios"
	scenarios_button.pressed.connect(func() -> void: _scenarios.visible = true)
	menu.add_child(scenarios_button)
	if OS.is_debug_build():
		_ask(menu, "Mega port (debug)", "Start the big test port: 6 berths, 18 STS cranes, 80 RTG blocks holding 20,000 boxes, 12 gates and ships in. The port you're playing is lost unless it is saved.", func() -> void:
			_menu.visible = false
			mega_port_pressed.emit())
		_ask(menu, "Showcase port (debug)", "Start the showcase: two terminals on the Estuary with one of nearly everything (every berth and crane, yard roles and gear, rail, gates, lanes, anchorage, pilots, tugs, a breakwater) and ships coming in. The port you're playing is lost unless it is saved.", func() -> void:
			_menu.visible = false
			showcase_port_pressed.emit())

	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	var scale_button := Button.new()
	scale_button.tooltip_text = "Interface size"
	scale_button.pressed.connect(func() -> void:
		_set_ui_scale(UI_SCALES[(UI_SCALES.find(get_tree().root.content_scale_factor) + 1) % UI_SCALES.size()], scale_button)
		settings.set_value("ui", "scale", get_tree().root.content_scale_factor)
		settings.save(SETTINGS_PATH))
	options.add_child(scale_button)
	_set_ui_scale(settings.get_value("ui", "scale", 1.0), scale_button)
	# Day and night is only how the port looks: off, it stays noon.
	var cycle := CheckButton.new()
	cycle.text = "Day and night"
	cycle.tooltip_text = "The sun follows the clock and the port lights up at night. Off, it stays noon; nothing in the game changes."
	day_night = settings.get_value("ui", "day_night", true)
	cycle.button_pressed = day_night
	cycle.toggled.connect(func(on: bool) -> void:
		day_night = on
		settings.set_value("ui", "day_night", on)
		settings.save(SETTINGS_PATH))
	options.add_child(cycle)
	# Events this game has, each switched on or off as a command.
	for kind: String in EVENT_NAMES:
		var check := CheckButton.new()
		check.text = EVENT_NAMES[kind][0]
		check.tooltip_text = EVENT_NAMES[kind][1]
		check.toggled.connect(func(on: bool) -> void:
			if on != sim.event_plan.on[kind]:
				command_issued.emit({"op": "set_event_kind", "kind": kind, "on": on}))
		options.add_child(check)
		_event_checks[kind] = check

	var goals := _panel(right, "Scenario")
	_goals.custom_minimum_size.x = 320
	_goals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goals.add_child(_goals)
	_build_scenarios()
	_build_paper()

	var guide := _panel(left, "Advisor")
	_guide_step.theme_type_variation = "MutedLabel"
	guide.add_child(_guide_step)
	_guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_text.custom_minimum_size.x = 320
	guide.add_child(_guide_text)
	_panel_of(guide).visible = false
	_advisor.toggled.connect(func(on: bool) -> void: _panel_of(guide).visible = on)
	_panel_of(guide).visibility_changed.connect(func() -> void: _advisor.set_pressed_no_signal(_panel_of(guide).visible))

	# Bottom centre, above the status bar: the build toolbar, a row of
	# category icons, and the open category's tools in a flyout above it, as in
	# Cities: Skylines. Clicking the open category again closes it.
	var bottom := _corner(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_top -= STATUS_BAR_HEIGHT
	bottom.offset_bottom -= STATUS_BAR_HEIGHT
	_bottom = bottom
	var items := _panel(bottom)
	_flyout = _panel_of(items)
	_flyout.visible = false
	var tools := ButtonGroup.new()
	var rows := {}
	for category: String in CATEGORIES:
		rows[category] = _row(items)
	var bar := _row(_panel(bottom))
	_panel_of(bar).theme_type_variation = "Toolbar"
	_panel_of(bar).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var categories := ButtonGroup.new()
	categories.allow_unpress = true
	for category: String in CATEGORIES:
		var row: HBoxContainer = rows[category]
		row.visible = false
		var open := _button(bar, "", categories, false, func() -> void: pass)
		open.tooltip_text = "%s (%d)" % [category, _category_buttons.size() + 1]
		open.theme_type_variation = "CategoryButton"
		open.custom_minimum_size = Vector2(52, 52)
		var icon := UiIcon.make(CATEGORY_ICONS[category], 30.0)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 10)
		open.add_child(icon)
		open.toggled.connect(func(on: bool) -> void:
			row.visible = on
			_flyout.visible = rows.values().any(func(r: HBoxContainer) -> bool: return r.visible)
			if not on:
				if not _flyout.visible:
					tool = INSPECT
				return
			var first: Button = row.get_children().filter(func(b: Node) -> bool: return b is Button and b.visible and b.toggle_mode).front()
			if first:
				first.button_pressed = true)
		_category_buttons.append(open)

	# Build tool item buttons
	for key: String in sim.rules.road_types:
		var road: Dictionary = sim.rules.road_types[key]
		# Ring road comes only as a roundabout, from the Shape button.
		if road.ring:
			continue
		_pictured(_item(_button(rows.Roads, "%s\n%s, $%d" % [road.name, _lanes_of(road), road.cost_per_cell], tools, false, func() -> void:
			tool = DRAW_ROAD
			road_type = key)), key).tooltip_text = _road_tip(road)
	var rail: Dictionary = sim.rules.rail
	_pictured(_item(_button(rows.Roads, "%s\n$%d per 4 m" % [rail.name, rail.cost_per_cell], tools, false, func() -> void:
		tool = DRAW_ROAD
		road_type = "track")), "track").tooltip_text = "Rail track, for trains to an RMG block's siding. Draw it from the main line at the east edge, straight or curved (Shape), bending no tighter than %d m; it crosses roads at level crossings. $%d per 4 m, $%.1f a day upkeep." % [roundi(rail.min_radius_cells * Grid.CELL), rail.cost_per_cell, rail.upkeep_per_cell]
	rows.Roads.add_child(VSeparator.new())
	_shape_button(rows.Roads)
	var grid := _item(Button.new())
	grid.text = "Grid snap\noff"
	grid.toggle_mode = true
	grid.tooltip_text = "When on, roads snap to the 4 m grid, straight or at 45°, with guides from road ends. When off, they snap onto roads, guide lines and parallel roads, their angle to 15° steps and their length to whole 4 m cells. Hold Shift to place freely."
	grid.toggled.connect(func(on: bool) -> void:
		grid_snap = on
		grid.text = "Grid snap\n%s" % ("on" if on else "off"))
	rows.Roads.add_child(grid)
	_item(_button(rows.Roads, "Move It\ndrag a node or bend", tools, false, func() -> void: tool = MOVE_ROAD)).tooltip_text = "Drag a road's end or junction to move it, or drag from the middle of a road to bend it. Areas along a road move with it. A move that would cross another road, meet one too sharply or leave an area without room is refused."
	var upgrade := _item(Button.new())
	upgrade.text = "Upgrade mode\nclick a road"
	upgrade.toggle_mode = true
	upgrade.toggled.connect(func(on: bool) -> void: upgrade_roads = on)
	upgrade.tooltip_text = "While on, pick a road type, then click a road to rebuild it as that type, at the new type's price."
	rows.Roads.add_child(upgrade)
	for key: String in sim.rules.area_types:
		var area: Dictionary = sim.rules.area_types[key]
		# shortcut: a depot has no job in the sim yet, so it isn't offered; show it with M11's AGV depot.
		# Quay aprons come as berths, below.
		if area.kind in ["depot", "quay_apron"]:
			continue
		var detail := "%d lanes, $%d a cell" % [area.depth - 2, area.cost_per_cell] if area.kind == "gate" else "$%d per 4 m cell" % area.cost_per_cell
		_pictured(_item(_button(rows[AREA_ROWS[area.kind]], "%s\n%s" % [area.name, detail], tools, false, func() -> void:
			tool = DRAW_AREA
			area_type = key)), key).tooltip_text = _area_tip(area, false)
	rows.Gate.add_child(VSeparator.new())
	var both := _item(Button.new())
	both.text = "Two-way\nboth sides"
	both.toggle_mode = true
	both.toggled.connect(func(on: bool) -> void: two_way = on)
	both.tooltip_text = "While on, a gate is built on both sides of the road, checking lorries in each way, at twice the price."
	rows.Gate.add_child(both)
	for key: String in sim.rules.berths:
		var spec: Dictionary = sim.rules.berths[key]
		var apron: Dictionary = sim.rules.area_types.quay_apron
		_gate(key, _pictured(_item(_button(rows.Quay, "%s\n%d m, %d crane spots" % [spec.name, Grid.metres(spec.length), spec.crane_spots], tools, false, func() -> void:
			tool = BUILD_BERTH
			berth = key)), key)).tooltip_text = "Click the coast to place a %d m quay with its road along the back. It turns to the way that fills the least water, or Turn it. Its quay is one straight wall; water behind it is filled at %s a cell. Cranes stand at its %d spots.\n%s with its road, before any filling." % [Grid.metres(spec.length), HudDetails.dollars(sim.rules.reclaim.cost_per_cell), spec.crane_spots, HudDetails.dollars(spec.length * apron.depth * apron.cost_per_cell + (spec.length + 2) * sim.rules.road_types[PortSim.BERTH_ROAD].cost_per_cell)]
	rows.Quay.add_child(VSeparator.new())
	var turn := _item(Button.new())
	turn.text = "Turn\nauto"
	turn.tooltip_text = "Turns the berth %d° anticlockwise from the way it faces now; Auto turns it back to the way that fills the least water." % PortSim.BERTH_TURN
	turn.pressed.connect(func() -> void:
		berth_angle = fposmod((berth_auto if berth_angle == PortSim.AUTO_ANGLE else berth_angle) - PortSim.BERTH_TURN, 360.0)
		turn.text = "Turn\n%d°" % roundi(berth_angle))
	rows.Quay.add_child(turn)
	var auto := _item(Button.new())
	auto.text = "Auto"
	auto.tooltip_text = turn.tooltip_text
	auto.pressed.connect(func() -> void:
		berth_angle = PortSim.AUTO_ANGLE
		turn.text = "Turn\nauto")
	rows.Quay.add_child(auto)
	for key: String in sim.rules.sts_cranes:
		var crane: Dictionary = sim.rules.sts_cranes[key]
		_gate(key, _pictured(_item(_button(rows.Cranes, "%s\n%s" % [crane.name, HudDetails.dollars(crane.cost)], tools, false, func() -> void:
			tool = CRANE
			crane_kind = key)), key)).tooltip_text = "A ship-to-shore crane on a quay apron. %d moves an hour, reaches %d rows across a ship.\n%s, upkeep $%d a day." % [crane.rate, crane.outreach, HudDetails.dollars(crane.cost), sim.rules.upkeep.sts_crane]
	_item(_action_button(rows.Cranes, "2 tractors\n$%d" % (sim.rules.tractor.cost * 2), {"op": "buy_tractors", "count": 2})).tooltip_text = "Terminal tractors carry boxes between cranes and yard blocks at %d km/h.\n$%d each, upkeep $%d a day each." % [roundi(sim.rules.tractor.speed * 0.06), sim.rules.tractor.cost, sim.rules.upkeep.tractor]
	for key: String in sim.rules.water.lanes:
		var lane: Dictionary = sim.rules.water.lanes[key]
		_pictured(_item(_button(rows.Water, "%s\n%d m wide, $%d a cell" % [lane.name, Grid.metres(lane.half_width * 2 + 1), lane.cost_per_cell], tools, false, func() -> void:
			tool = DRAW_LANE
			lane_type = key)), key).tooltip_text = "Draw a ship lane over open water, straight or curved (Shape), bending no tighter than %d m. Ships sail in from a lane end on the map's edge to a berth whose water a lane ends in, through lanes as deep as their draft (Inspect a lane or berth to dredge it). %s.\n$%d a 4 m cell of water it covers." % [roundi(lane.min_radius_cells * Grid.CELL), "One ship at a time" if key == "narrow" else "Ships pass both ways", lane.cost_per_cell]
	_shape_button(rows.Water)
	rows.Water.add_child(VSeparator.new())
	var anchorage: Dictionary = sim.rules.water.anchorage
	_pictured(_item(_button(rows.Water, "Anchorage\n$%d a cell" % anchorage.cost_per_cell, tools, false, func() -> void: tool = BUILD_ANCHORAGE)), "anchorage").tooltip_text = "Drag out an anchorage over open water, with a ship lane ending in it. Ships that find no free berth wait here, one every %d m each way; with no room at anchor a ship waits out at sea %.0f hours, then goes elsewhere." % [Grid.metres(anchorage.spacing), sim.rules.water.max_wait_hours]
	var water: Dictionary = sim.rules.water
	_pictured(_item(_button(rows.Water, "Pilot station\n%s" % HudDetails.dollars(water.pilots.station_cost), tools, false, func() -> void:
		tool = BUILD_MARINE
		marine_base = "pilot_station")), "pilot_station").tooltip_text = "Click the water near the shore. Panamaxes and bigger take a pilot in and out; the pilot boat comes from the nearest station. Hire pilots by inspecting it: %s each, %s a day." % [HudDetails.dollars(water.pilots.pilot_cost), HudDetails.dollars(water.pilots.upkeep_per_pilot)]
	_pictured(_item(_button(rows.Water, "Tug depot\n%s" % HudDetails.dollars(water.tugs.depot_cost), tools, false, func() -> void:
		tool = BUILD_MARINE
		marine_base = "tug_depot")), "tug_depot").tooltip_text = "Click the water near the shore. Panamaxes and bigger wait for tugs to berth and unberth; tugs sail out from the nearest depot with enough free, so a depot near the berths berths ships sooner. Buy tugs by inspecting it: %s each, %s a day." % [HudDetails.dollars(water.tugs.tug_cost), HudDetails.dollars(water.tugs.upkeep_per_tug)]
	_pictured(_item(_button(rows.Water, "Services jetty\n%s" % HudDetails.dollars(water.services.jetty_cost), tools, false, func() -> void:
		tool = BUILD_MARINE
		marine_base = "services_jetty")), "services_jetty").tooltip_text = "Click the water near the shore. Its boats see to ships at berth or at anchor: a bunker barge fuels them, a supply boat brings provisions and a waste boat takes waste off, each for a fee. A ship never waits for them; one that sails with a need unserved costs a little reputation, but only for a service you offer. Buy boats by inspecting it."
	_pictured(_item(_button(rows.Water, "Breakwater\n%s a cell" % HudDetails.dollars(water.breakwater.cost_per_cell), tools, false, func() -> void: tool = BUILD_BREAKWATER)), "breakwater").tooltip_text = "Drag a breakwater across open water, straight or at 45°: a rock wall 8 m thick that no ship lane crosses, to shelter berths and anchorages."
	_item(_button(rows.Bulldoze, "Bulldoze\nroad, track, crane, area or water", tools, false, func() -> void: tool = BULLDOZE)).tooltip_text = "Click a road, track, crane, area, ship lane or anchorage to remove it. A crane comes down alone, once its ship has sailed. Boxes stored in an area are lost."

	# The berth board, over everything else while it is open.
	_board.visible = false
	_board.sim = sim
	_board.command_issued.connect(func(command: Dictionary) -> void: command_issued.emit(command))
	_board.closed.connect(func() -> void: _board.visible = false)
	add_child(_board)
	_map.visible = false
	_map.sim = sim
	_map.command_issued.connect(func(command: Dictionary) -> void: command_issued.emit(command))
	_map.closed.connect(func() -> void: _map.visible = false)
	add_child(_map)
	# The windows draw over the corner panels, and one is open at a time; the
	# menu, over its dimmed screen, over everything.
	move_child(_windows, -1)
	move_child(_dim, -1)
	move_child(_menu.get_parent(), -1)
	var windows: Array[Control] = [_drawer_panel, _board, _map, _scenarios, _paper]
	for window: Control in windows:
		window.visibility_changed.connect(func() -> void:
			if window.visible:
				for other: Control in windows:
					if other != window:
						other.visible = false)


## The status bar along the bottom edge, as in Cities: Skylines: the big
## windows' buttons, the milestone, money and the day's net, and the clock
## with the speeds and the menu.
func _build_status_bar() -> void:
	var strip := PanelContainer.new()
	strip.theme_type_variation = "Toolbar"
	add_child(strip)
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -STATUS_BAR_HEIGHT
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	strip.add_child(row)
	var window := func(glyph: String, tip: String, open: Callable) -> void:
		var button := Button.new()
		button.tooltip_text = tip
		button.custom_minimum_size = Vector2(36, 36)
		var icon := UiIcon.make(glyph, 22.0)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 7)
		button.add_child(icon)
		button.pressed.connect(open)
		row.add_child(button)
	window.call("views", "Info views: colour the map by traffic, yard fill or town noise", func() -> void: _views.visible = not _views.visible)
	window.call("statistics", "Statistics", func() -> void: _toggle_drawer(_last_drawer_group))
	window.call("map", "Port map: terminals, land and the AGV zone (M)", func() -> void: _map.visible = not _map.visible)
	window.call("harbour", "Berth board and harbour master", func() -> void: _board.visible = not _board.visible)
	_gate("contracts", row.get_child(-1) as Control)
	row.add_child(VSeparator.new())
	_milestone.theme_type_variation = "MutedLabel"
	row.add_child(_milestone)
	_milestone_bar.custom_minimum_size = Vector2(140, 8)
	_milestone_bar.show_percentage = false
	_milestone_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_milestone_bar)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_money.theme_type_variation = "ClockLabel"
	row.add_child(_money)
	_today.theme_type_variation = "MutedLabel"
	row.add_child(_today)
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap2)
	_clock.theme_type_variation = "MutedLabel"
	_clock.tooltip_text = "Day of the week and game day, time, wind and tide"
	_clock.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_clock)
	var speeds := ButtonGroup.new()
	for s: int in SPEEDS:
		_speed_buttons.append(_button(row, "%d×" % s if s else "❚❚", speeds, s == speed, func() -> void: speed = s))
	window.call("menu", "Save, load, new game and settings (Esc)", _toggle_menu)


func _build_drawer(left: Control) -> void:
	var drawer := _panel(left, "Statistics")
	_drawer_panel = _panel_of(drawer)
	_drawer_panel.visible = false
	_drawer_panel.visibility_changed.connect(func() -> void:
		if not _drawer_panel.visible:
			_active_drawer_group = "")
	# A tab per figure group across the top.
	var tabs := _row(drawer)
	var tab_group := ButtonGroup.new()
	for group_name: String in HudDetails.GROUPS:
		_stats_tabs[group_name] = _button(tabs, group_name, tab_group, false, func() -> void:
			if _active_drawer_group != group_name:
				_toggle_drawer(group_name))

	_legend.add_theme_constant_override("separation", 6)
	drawer.add_child(_legend)
	_drawer_cards_container = HBoxContainer.new()
	_drawer_cards_container.add_theme_constant_override("separation", 6)
	drawer.add_child(_drawer_cards_container)

	var div := Panel.new()
	div.theme_type_variation = "Divider"
	div.custom_minimum_size = Vector2(0, 1)
	drawer.add_child(div)

	# The rows scroll, so the window keeps its size from tab to tab.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	drawer.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_drawer_rows_container = VBoxContainer.new()
	_drawer_rows_container.add_theme_constant_override("separation", 4)
	body.add_child(_drawer_rows_container)

	_drawer_extra_container = VBoxContainer.new()
	body.add_child(_drawer_extra_container)
	_ledger.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ledger.custom_minimum_size.x = 340
	_drawer_extra_container.add_child(_ledger)
	_drawer_extra_container.add_child(_borrow)
	_drawer_extra_container.add_child(_town_actions)

	for kind: String in sim.rules.loans:
		var terms: Dictionary = sim.rules.loans[kind]
		_gate("loans", _action_button(_borrow, "Borrow %s\n%d days, %d%% a year" % [HudDetails.dollars(terms.amount), terms.days, roundi(terms.yearly_rate * 100)], {"op": "take_loan", "kind": kind}))
	_drawer_extra_container.add_child(_label("Policies"))
	_drawer_extra_container.add_child(_policies)
	for key: String in sim.rules.policies:
		var policy: Dictionary = sim.rules.policies[key]
		var switch := CheckButton.new()
		switch.text = policy.name if policy.cost_per_day == 0 else "%s, %s a day" % [policy.name, HudDetails.dollars(policy.cost_per_day)]
		switch.tooltip_text = policy.text
		switch.toggled.connect(func(on: bool) -> void: command_issued.emit({"op": "set_policy", "policy": key, "on": on}))
		_policies.add_child(_gate("policies", switch))


## The community fund and the bypass, on the Port drawer only.
func _fill_town_actions(group_name: String) -> void:
	for child in _town_actions.get_children():
		child.queue_free()
	_town_actions.visible = group_name == HudDetails.GROUP_PORT
	if not _town_actions.visible:
		return
	var fund: int = sim.town.fund
	for change: int in [-500, 500]:
		var to := clampi(fund + change, 0, sim.rules.town.max_fund)
		_action_button(_town_actions, "Fund %+d" % change, {"op": "set_town_fund", "per_day": to}).disabled = to == fund
	if not sim.town.bypass:
		_action_button(_town_actions, "Build the bypass, %s" % HudDetails.dollars(sim.rules.town.bypass_cost), {"op": "buy_bypass"}).tooltip_text = "Takes the highway round %s, so its lorries no longer rumble through." % sim.rules.town.name


func _toggle_drawer(group_name: String) -> void:
	if _active_drawer_group == group_name and _drawer_panel.visible:
		_close_drawer()
		return
	_active_drawer_group = group_name
	_last_drawer_group = group_name
	_drawer_panel.visible = true
	(_stats_tabs[group_name] as Button).set_pressed_no_signal(true)
	_fill_drawer(group_name)


## The info view the map should draw: the open drawer's group, or "".
func info_view() -> String:
	if _info_mode != "":
		return _info_mode
	return _active_drawer_group if _drawer_panel.visible else ""


## The info views popup above the status bar, a button per view, and the
## legend of the chosen one in the corner above it, as in Cities: Skylines.
func _build_views() -> void:
	var corner := _corner(Control.PRESET_BOTTOM_LEFT)
	corner.offset_top -= STATUS_BAR_HEIGHT + 4.0
	corner.offset_bottom -= STATUS_BAR_HEIGHT + 4.0
	var legend := _panel(corner)
	_view_legend = _row(legend)
	_panel_of(legend).visible = false
	var list := _panel(corner, "Info views")
	_views = _panel_of(list)
	_views.visible = false
	var group := ButtonGroup.new()
	for view: String in [""] + WorldView.INFO_LEGENDS.keys():
		_button(_row(list), view if view else "None", group, view == "", func() -> void:
			_info_mode = view
			_views.visible = false
			_panel_of(legend).visible = view != ""
			for child: Node in _view_legend.get_children():
				child.queue_free()
			if view == "":
				return
			_view_legend.add_child(_label(view + ":"))
			for entry: Array in WorldView.INFO_LEGENDS[view]:
				var swatch := ColorRect.new()
				swatch.color = entry[1]
				swatch.custom_minimum_size = Vector2(12, 12)
				swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				_view_legend.add_child(swatch)
				_view_legend.add_child(_label(entry[0])))


func _close_drawer() -> void:
	_active_drawer_group = ""
	_drawer_panel.visible = false


func _fill_drawer(group_name: String) -> void:
	for child in _legend.get_children():
		child.queue_free()
	_legend.visible = group_name in WorldView.INFO_LEGENDS
	for entry: Array in WorldView.INFO_LEGENDS.get(group_name, []):
		var swatch := ColorRect.new()
		swatch.color = entry[1]
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_legend.add_child(swatch)
		var label := _label(entry[0] + "  ")
		label.theme_type_variation = "MutedLabel"
		_legend.add_child(label)
	_fill_town_actions(group_name)
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
	if not key.pressed or key.echo:
		return
	# Esc closes the open tool first, as in Cities: Skylines, then opens the menu.
	if key.keycode == KEY_ESCAPE:
		var open := _category_buttons.filter(func(b: Button) -> bool: return b.button_pressed)
		if open.is_empty():
			_toggle_menu()
		else:
			open[0].button_pressed = false
		return
	if key.keycode == KEY_M:
		_map.visible = not _map.visible
		return
	var i := key.keycode - KEY_1
	if i >= 0 and i < _category_buttons.size() and not _category_buttons[i].disabled:
		_category_buttons[i].button_pressed = true


func _set_ui_scale(factor: float, button: Button) -> void:
	get_tree().root.content_scale_factor = factor
	button.text = "UI %d%%" % roundi(factor * 100)


## The cells of what is inspected, for the world to highlight, as Cities:
## Skylines marks what its info panel shows; [] when nothing is.
func selected_cells() -> Array[Vector2i]:
	var shown := _inspect_panel.visible
	var key := [_inspected, sim.areas.version, shown]
	if key != _selected_for:
		_selected_for = key
		_selected = [] as Array[Vector2i]
		if shown and _inspected is Dictionary and _inspected.has("area") and _inspected.area in sim.areas.list:
			_selected.assign(sim.areas.cells(_inspected.area))
		elif shown and _inspected != null:
			_selected = [_inspect_cell] as Array[Vector2i]
	return _selected


## Opens the inspect panel on whatever is at grid cell `cell`.
func inspect(cell: Vector2i) -> void:
	_inspected = Inspect.pick(sim, cell)
	_inspect_cell = cell
	_show_only(_inspect_panel)


## Shows a short-lived message, such as why a build was refused.
## Shows `text` beside the mouse; "" hides it.
func hint(text: String) -> void:
	_hint.text = text
	_hint.visible = text != ""
	_hint.position = _hint.get_viewport().get_mouse_position() + Vector2(18, 18)


func flash(text: String) -> void:
	_message.text = text
	_flash_left = FLASH_SECONDS


func _process(dt: float) -> void:
	_money.text = HudDetails.dollars(sim.money)
	_show_milestone()

	var minute := sim.clock.calendar_minutes()
	_clock.text = "%s %d  %02d:%02d" % [WEEKDAYS[sim.clock.game_day() % 7], sim.clock.game_day(), sim.clock.game_hour(), int(minute) % 60]
	_clock.text += "  %d km/h" % roundi(sim.event_plan.wind(sim.rules, minute))
	if sim.event_plan.on.tides:
		_clock.text += "  %+.1f m" % Marine.tide(sim, minute)

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

	_show_scenario()
	_show_paper()
	_show_guide()
	_fit_left_panels()

	if _inspect_name.is_visible_in_tree():
		var lines := Inspect.describe(sim, _inspected)
		_inspect_panel.visible = not lines.is_empty()
		if not lines.is_empty():
			_inspect_name.text = lines[0]
			_inspect_view.set_overview(lines.slice(1))
		if _actions_drawn != _actions_key():
			_draw_inspect_actions()

	_board.sim = sim
	_map.sim = sim

	# Throttled refresh of the info bar and the open drawer
	_refresh_left -= dt
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		var net := sim.ledger.today_total()
		_today.text = "%s today" % HudDetails.signed(net)
		if _drawer_panel.visible and _active_drawer_group != "":
			_refresh_drawer()

	_flash_left -= dt
	_news_left -= dt
	if [sim, sim.last_event()] != _news_seen:
		_news_seen = [sim, sim.last_event()]
		_news_left = NEWS_SECONDS
	if _flash_left <= 0.0:
		_message.text = "Recent news" if _event_list.visible else _stamp(sim.events[-1]) if not sim.events.is_empty() else ""
	_message.visible = _event_list.visible or _flash_left > 0.0 or (_news_left > 0.0 and _message.text != "")
	if _event_list.visible and _events_drawn != [sim, sim.last_event(), sim.events.size()]:
		_draw_events()


## "Day 2 20:04  text" for a sim event.
static func _stamp(event: Dictionary) -> String:
	return "Day %d %02d:%02d  %s" % [int(event.minute / 1440), int(event.minute / 60) % 24, int(event.minute) % 60, event.text]


## The last ten events, newest first; one that happened somewhere is a link there.
func _draw_events() -> void:
	_events_drawn = [sim, sim.last_event(), sim.events.size()]
	for child in _event_list.get_children():
		child.queue_free()
	for event: Dictionary in sim.events.slice(-10):
		if event.has("at"):
			var link := Button.new()
			link.text = _stamp(event) + "  ›"
			link.theme_type_variation = "EventLink"
			link.alignment = HORIZONTAL_ALIGNMENT_LEFT
			link.tooltip_text = "Go there"
			link.pressed.connect(func() -> void:
				_message.pressed.emit()
				event_picked.emit(event.at))
			_event_list.add_child(link)
		else:
			_event_list.add_child(_label(_stamp(event)))
		_event_list.move_child(_event_list.get_child(-1), 0)


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
		for i in _policies.get_child_count():
			(_policies.get_child(i) as CheckButton).set_pressed_no_signal(sim.rules.policies.keys()[i] in sim.policies)


## Opens the pause menu, pausing the game, or closes it and resumes.
func _toggle_menu() -> void:
	if _menu.visible:
		_menu.visible = false
		return
	_speed_before_menu = speed
	_set_speed(0)
	for kind: String in _event_checks:
		_event_checks[kind].set_pressed_no_signal(sim.event_plan.on[kind])
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
		var room := limit - scroll.get_global_rect().position.y - 16
		scroll.custom_minimum_size.y = clampf(room, 32.0, wanted)


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
## A road type's lanes in a few words, for its button.
static func _lanes_of(road: Dictionary) -> String:
	if not road.lorries:
		return "no lorries"
	if road.backward == 0:
		return "%d lanes" % road.forward
	return "%d each way" % road.forward


## Whether the area tool builds a gate on both sides of the road.
func both_sides() -> bool:
	return two_way and tool == DRAW_AREA and sim.rules.area_types[area_type].kind == "gate"


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
		"parking": "Lorries wait here, off the road, while their terminal's gate is busy, and go on to it in turn. One space per %d m" % Grid.metres(AreaLayout.BAY),
		"transfer_block": "A high-volume yard block for an AGV terminal, laid across its road: AGVs hand boxes over at the front, in the AGV zone, and lorries at the back, off a road behind it (drag along the zone's road; it reaches back to the next road, 48 to 160 m). Twin ASCs, one at each end, stack between them",
		"agv_depot": "Home of AGVs, the driverless carriers: built inside the AGV zone, its terminal moves boxes between quay and yard on its AGVs instead of tractors. Dear to buy, cheap to run. Buy AGVs by inspecting it",
		"fire_station": "Its fire engines drive out to fires in the yard and on ships at berth (switch fires on in the menu); a fire no crew reaches soon burns boxes. Buy engines by inspecting it",
		"tree_belt": "A belt of trees that screens the town next door: noise and floodlight from behind it reach the town at half strength",
		"workshop": "Its mechanics drive out in their vans to repair the quay cranes and yard gear that break down in its terminal (switch breakdowns on in the menu). Hire mechanics by inspecting it",
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


## The scenario list: each scenario's name, best medal and blurb, played on
## its own map or a fresh coast.
func _build_scenarios() -> void:
	var page := _panel(_corner(Control.PRESET_CENTER), "Scenarios")
	_scenarios = _panel_of(page)
	# Scrolled, so a long list stays clear of the toolbar.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	_scenarios.visible = false
	_scenarios.visibility_changed.connect(func() -> void:
		if _scenarios.visible:
			_fill_scenarios(list))


func _fill_scenarios(list: VBoxContainer) -> void:
	for child: Node in list.get_children():
		child.queue_free()
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	for key: String in sim.rules.scenarios:
		var scenario: Dictionary = sim.rules.scenarios[key]
		var medal: String = settings.get_value("medals", key, "")
		var name := _label("%s%s" % [scenario.name, "  (%s)" % medal.capitalize() if medal else ""])
		name.theme_type_variation = "PanelTitle"
		list.add_child(name)
		var blurb := _label("%s %d days." % [scenario.blurb, scenario.days])
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size.x = 460
		list.add_child(blurb)
		var row := _row(list)
		for fresh: bool in [false, true]:
			_ask(row, "Fresh coast" if fresh else "Play", "Start %s%s? The port you're playing is lost unless it is saved." % [scenario.name, " on a coast drawn for it" if fresh else ""], func() -> void:
				_scenarios.visible = false
				_menu.visible = false
				scenario_pressed.emit(key, fresh))


## The scenario's goals and days left; a medal won is kept in the settings.
func _show_scenario() -> void:
	if _shown_for != sim:
		_shown_for = sim
		_paper_shown = -1
		_panel_of(_goals).visible = sim.scenario.key != ""
	if sim.scenario.key == "":
		return
	var scenario: Dictionary = sim.rules.scenarios[sim.scenario.key]
	var lines: Array[String] = ["%s, day %d of %d%s" % [scenario.name, sim.clock.game_day() + 1, scenario.days, " (fresh coast)" if sim.scenario.fresh else ""]]
	for goal: Dictionary in Scenario.progress(sim):
		lines.append("%s %s: %d / %d" % ["✓" if goal.met else "·", goal.text, goal.now, goal.target])
	if sim.scenario.status == "won":
		lines.append("Won: %s medal" % sim.scenario.medal.capitalize())
		_keep_medal()
	elif sim.scenario.status == "lost":
		lines.append("Lost. Try again from the menu.")
	_goals.text = "\n".join(lines)


func _keep_medal() -> void:
	var order := ["", "bronze", "silver", "gold"]
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	var best: String = settings.get_value("medals", sim.scenario.key, "")
	if order.find(sim.scenario.medal) > order.find(best):
		settings.set_value("medals", sim.scenario.key, sim.scenario.medal)
		settings.save(SETTINGS_PATH)


## The morning paper: yesterday's numbers and news, shown from 06:00 unless
## the player stops it.
func _build_paper() -> void:
	var page := _panel(_corner(Control.PRESET_CENTER), "Morning paper")
	_paper = _panel_of(page)
	_paper.visible = false
	_paper_text.bbcode_enabled = true
	_paper_text.fit_content = true
	_paper_text.custom_minimum_size.x = 440
	page.add_child(_paper_text)
	var stop := CheckButton.new()
	stop.text = "Deliver it each morning"
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	stop.button_pressed = settings.get_value("ui", "paper", true)
	stop.toggled.connect(func(on: bool) -> void:
		settings.set_value("ui", "paper", on)
		settings.save(SETTINGS_PATH))
	page.add_child(stop)


func _show_paper() -> void:
	if sim.reports.is_empty() or sim.reports[-1].day == _paper_shown or sim.clock.game_hour() < 6:
		return
	# It waits on the doormat while another window is open.
	if [_drawer_panel, _board, _map, _scenarios].any(func(w: Control) -> bool: return w.visible):
		return
	_paper_shown = sim.reports[-1].day
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	if not settings.get_value("ui", "paper", true):
		return
	var report: Dictionary = sim.reports[-1]
	var text := "[center][b][font_size=22]The %s Gazette[/font_size][/b]\nDay %d[/center]\n" % [sim.rules.town.name, report.day]
	text += "[b]%d[/b] moves across the quay.  [b]%d[/b] calls, %d on time.  %s the day.\n" % [report.moves, report.calls, report.on_time, ("Made " + HudDetails.dollars(report.net)) if report.net >= 0 else ("Lost " + HudDetails.dollars(-report.net))]
	for headline: String in report.headlines:
		text += "\n• " + headline
	_paper_text.text = text
	_paper.visible = true


## The guided start's current step; its panel hides once the first ship is worked.
func _show_guide() -> void:
	var step := Guide.current(sim)
	var count := Guide.steps(sim).size()
	_advisor.visible = step < count
	if step == count:
		_panel_of(_guide_text).visible = false
		return
	# A new step pulses the advisor until it is opened.
	if [sim, step] != _guide_seen:
		_guide_seen = [sim, step]
		_advisor_new = true
	if _panel_of(_guide_text).visible:
		_advisor_new = false
	_advisor.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.8, 0.3), (sin(Time.get_ticks_msec() / 200.0) + 1.0) / 2.0) if _advisor_new else Color.WHITE
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
## For an inspected area: join each other terminal, or split off into a new one.
func _draw_inspect_actions() -> void:
	_draw_legacy_actions()
	_inspect_bulldoze.visible = _inspected is Dictionary and _inspected.has("area")
	_inspect_view.show_sections(InspectControls.sections(sim, _inspected))


## The actions not yet given controls of their own (InspectControls), as buttons.
func _draw_legacy_actions() -> void:
	_actions_drawn = _actions_key()
	for child in _inspect_actions.get_children():
		child.queue_free()
	if _inspected is Dictionary and _inspected.has("junction"):
		_draw_junction_actions(_inspected.junction)
		return
	if _inspected is Dictionary and _inspected.has("base"):
		var id: int = _inspected.base
		if id in sim.pilot_stations:
			_action_button(_inspect_actions, "Hire a pilot, %s" % HudDetails.dollars(sim.rules.water.pilots.pilot_cost), {"op": "hire_pilots", "station": id, "count": 1})
		elif id in sim.tug_depots:
			_action_button(_inspect_actions, "Buy a tug, %s" % HudDetails.dollars(sim.rules.water.tugs.tug_cost), {"op": "buy_tugs", "depot": id, "count": 1})
			_action_button(_inspect_actions, "Buy a fireboat, %s" % HudDetails.dollars(sim.rules.water.fireboats.cost), {"op": "buy_fireboats", "depot": id, "count": 1})
		elif id in sim.service_jetties:
			for service: String in sim.rules.water.services.boats:
				var boat: Dictionary = sim.rules.water.services.boats[service]
				_action_button(_inspect_actions, "Buy a %s, %s" % [boat.name.to_lower(), HudDetails.dollars(boat.cost)], {"op": "buy_service_boats", "jetty": id, "service": service, "count": 1})
		return
	if _inspected is Dictionary and _inspected.has("lane"):
		if _inspected.lane in sim.ship_lanes.segments:
			var lane: Dictionary = sim.ship_lanes.segments[_inspected.lane]
			var cells := sim.ship_lanes.area(_inspected.lane).size()
			_dredge_button(cells, {"op": "dredge_lane", "segment": _inspected.lane, "metres": 1})
			if lane.type == "narrow":
				var widen := _action_button(_inspect_actions, "Widen, %s" % HudDetails.dollars(sim.ship_lane_price(sim.ship_lanes.nodes[lane.a], sim.ship_lanes.nodes[lane.b], "wide", lane.control)), {"op": "widen_ship_lane", "segment": _inspected.lane})
				widen.tooltip_text = "Rebuilds it as a wide lane, %d m across, where ships pass both ways instead of booking it one at a time." % Grid.metres(sim.rules.water.lanes.wide.half_width * 2 + 1)
		return


## A Dredge 1 m button for `cells` cells of water, locked until dredging is.
func _dredge_button(cells: int, command: Dictionary) -> void:
	var dredge: Dictionary = sim.rules.water.dredge
	var button := _action_button(_inspect_actions, "Dredge 1 m, %s" % HudDetails.dollars(cells * dredge.cost_per_cell_metre), command)
	button.disabled = sim.lock_error("dredging") != ""
	button.tooltip_text = sim.lock_error("dredging") if button.disabled else "Deepens this water 1 m, down to %.0f m, so ships of a deeper draft can use it. Then %s every %d days to keep it." % [dredge.max_depth, HudDetails.dollars(cells * dredge.maintenance_per_cell_metre), dredge.maintenance_days]


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


## A column flush against an edge/corner of the screen that grows away from it.
func _corner(preset: Control.LayoutPreset) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	column.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 0)
	column.grow_horizontal = {Control.PRESET_TOP_LEFT: Control.GROW_DIRECTION_END, Control.PRESET_TOP_RIGHT: Control.GROW_DIRECTION_BEGIN, Control.PRESET_CENTER_BOTTOM: Control.GROW_DIRECTION_BOTH, Control.PRESET_CENTER: Control.GROW_DIRECTION_BOTH, Control.PRESET_CENTER_TOP: Control.GROW_DIRECTION_BOTH, Control.PRESET_BOTTOM_LEFT: Control.GROW_DIRECTION_END}[preset]
	column.grow_vertical = {Control.PRESET_TOP_LEFT: Control.GROW_DIRECTION_END, Control.PRESET_TOP_RIGHT: Control.GROW_DIRECTION_END, Control.PRESET_CENTER_BOTTOM: Control.GROW_DIRECTION_BEGIN, Control.PRESET_CENTER: Control.GROW_DIRECTION_BOTH, Control.PRESET_CENTER_TOP: Control.GROW_DIRECTION_END, Control.PRESET_BOTTOM_LEFT: Control.GROW_DIRECTION_BEGIN}[preset]
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


## Gives build-menu tile `button` item `key`'s thumbnail above its name and
## price, as Cities: Skylines' asset tiles (tools/make_thumbnails.gd renders them).
func _pictured(button: Button, key: String) -> Button:
	button.icon = load("res://ui/thumbnails/%s.png" % key)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.custom_minimum_size = Vector2(112, 118)
	button.add_theme_font_size_override("font_size", 12)
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
## What the inspect panel's buttons were drawn for; they are drawn again when it changes.
func _actions_key() -> Array:
	var junctions := Drive.junctions(sim)
	var settings: Variant = [junctions.signals.has(_inspected.junction), junctions.signals.get(_inspected.junction, {}).get("green"), junctions.signs.get(_inspected.junction), junctions.arrows.get(_inspected.junction)] if _inspected is Dictionary and _inspected.has("junction") else null
	return [sim, sim.areas.version, sim.templates.keys(), sim.dredge_version, sim.ship_lanes.version, sim.pilot_stations, sim.tug_depots, sim.service_jetties, sim.boats.list.size(), sim.workshops.vans.size(), sim.fires.engines.size(), sim.serviced.duplicate(), _inspected, settings]


## Junction `point`'s buttons: signals on or off, each phase's green time,
## and each arm's sign, which a press moves on: none, give way, stop.
func _draw_junction_actions(point: Vector2) -> void:
	var junctions := Drive.junctions(sim)
	var signalled := point in junctions.signals
	_action_button(_inspect_actions, "Signals off" if signalled else "Signals on", {"op": "set_signals", "point": point, "on": not signalled})
	if signalled:
		var greens: Array = junctions.signals[point].green
		for i in greens.size():
			for change: int in [-5, 5]:
				var seconds := clampf(greens[i] + change, sim.rules.traffic.min_green_seconds, sim.rules.traffic.max_green_seconds)
				if seconds != greens[i]:
					_action_button(_inspect_actions, "Phase %d %+d s" % [i + 1, change], {"op": "set_green", "point": point, "phase": i, "seconds": seconds})
	var next := {"": "give_way", "give_way": "stop", "stop": ""}
	var label := {"": "no sign", "give_way": "give way", "stop": "stop"}
	for arm: Vector2i in Drive.arms(sim, point):
		var sign: String = junctions.signs.get(point, {}).get(arm, "")
		var button := _action_button(_inspect_actions, "From the %s: %s" % [Inspect.arm_name(arm), label[sign]], {"op": "set_sign", "point": point, "arm": arm, "sign": next[sign]})
		button.tooltip_text = "Press for %s. Give way: traffic from here waits for a gap; stop: it also stops at the line first." % label[next[sign]]
	# Lane arrows, each lane coming in (lane 1 nearest the middle) cycling through the turns it may take.
	var presets := [[], ["left"], ["straight"], ["right"], ["left", "straight"], ["straight", "right"], ["left", "straight", "right"]]
	for arm: Vector2i in Drive.arms(sim, point):
		for lane: int in Drive.junction_lanes(sim).approach(point, arm).size():
			var turns: Array = junctions.arrows.get(point, {}).get(arm, {}).get(lane, [])
			var after: Array = presets[(presets.find(turns) + 1) % presets.size()]
			var button := _action_button(_inspect_actions, "From the %s, lane %d: %s" % [Inspect.arm_name(arm), lane + 1, " + ".join(turns) if not turns.is_empty() else "as usual"], {"op": "set_lane_arrows", "point": point, "arm": arm, "lane": lane, "turns": after})
			button.tooltip_text = "Press for %s. Lane arrows set the turns a lane takes at the junction; as usual, the inner lane turns left and goes straight on, the outer turns right." % (" + ".join(after) if not after.is_empty() else "as usual")


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


## A Shape button in `row`: how roads, track and ship lanes are laid
## (road_mode), the same setting wherever it is shown.
func _shape_button(row: Control) -> void:
	var shape := _item(Button.new())
	shape.text = "Shape\n%s" % road_mode
	shape.tooltip_text = "How roads, track and ship lanes are laid: straight by a drag; curved by three clicks (start, a point the curve bends toward, end); freeform by a drag that carries on smoothly from the end it starts on; roundabout (roads only) by a drag from its centre out to its ring, which roads joining it give way to. Click to change."
	shape.pressed.connect(func() -> void:
		road_mode = ROAD_MODES[(ROAD_MODES.find(road_mode) + 1) % ROAD_MODES.size()]
		for button: Button in _shapes:
			button.text = "Shape\n%s" % road_mode)
	_shapes.append(shape)
	row.add_child(shape)
