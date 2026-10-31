class_name PortMap
extends PanelContainer
## The port map, over the whole screen, seen from straight above: sea, land
## (owned or not), roads and areas, with terminals painted over them in
## their colours. Paint mode paints the selected terminal with a round brush,
## erases, or fills a road-bounded block; Buy land mode buys the tile
## clicked. Beside the map, a card per terminal: its name and colour to set,
## what it has and how it does, and what it lacks. Asks for changes through
## `command_issued`; never changes the sim.

signal command_issued(command: Dictionary)
signal closed

const HudDetails := preload("res://scripts/hud_details.gd")
## Terminal colours, by a terminal's colour index (Areas.TERMINAL_COLOURS of them).
const COLOURS: Array[Color] = [Color(0.95, 0.55, 0.15), Color(0.2, 0.6, 0.95), Color(0.35, 0.8, 0.35), Color(0.85, 0.35, 0.75), Color(0.95, 0.85, 0.25), Color(0.3, 0.85, 0.85), Color(0.9, 0.3, 0.3), Color(0.65, 0.55, 0.95)]
## Brush radii in cells: small, medium and large.
const BRUSHES: Array[int] = [2, 5, 10]
const MUTED := Color(0.58, 0.639, 0.722)
const WARN := Color(1, 0.55, 0.4)

var sim: PortSim
## "paint" or "land".
var mode := "paint"
## "brush", "erase" or "fill".
var tool := "brush"
var brush := BRUSHES[1]
## The terminal painted with: one of sim.areas.terminals, or -1 for a new one.
var selected := -1
## Made in _ready, where they join the map.
var _canvas: MapCanvas
var _help: Label
var _cards: VBoxContainer
var _cards_for := []
var _refresh_left := 0.0


func _ready() -> void:
	_help = Label.new()
	_cards = VBoxContainer.new()
	_canvas = MapCanvas.new()
	_canvas.map = self
	add_theme_stylebox_override("panel", _card(Color(0.07, 0.09, 0.12), 16))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		set("offset_" + side, 24.0 if side in ["left", "top"] else -24.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	var title := Label.new()
	title.text = "Port map"
	title.theme_type_variation = "ClockLabel"
	header.add_child(title)
	var modes := ButtonGroup.new()
	for pick: Array in [["paint", "Paint terminals"], ["land", "Buy land"]]:
		var button := _toggle(header, pick[1], modes, func() -> void: mode = pick[0])
		button.button_pressed = pick[0] == mode
		if pick[0] == "land":
			button.set_meta("land", true)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(gap)
	var close := Button.new()
	close.text = "Close  ✕"
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.add_theme_color_override("font_color", MUTED)
	column.add_child(_help)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_canvas)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 340.0
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	var tools := HBoxContainer.new()
	side.add_child(tools)
	var tool_group := ButtonGroup.new()
	for pick: Array in [["brush", "Brush"], ["erase", "Eraser"], ["fill", "Fill block"]]:
		_toggle(tools, pick[1], tool_group, func() -> void: tool = pick[0]).button_pressed = pick[0] == tool
	var sizes := HBoxContainer.new()
	side.add_child(sizes)
	var size_group := ButtonGroup.new()
	for i in BRUSHES.size():
		var radius: int = BRUSHES[i]
		_toggle(sizes, ["Small", "Medium", "Large"][i], size_group, func() -> void: brush = radius).button_pressed = radius == brush
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 8)
	scroll.add_child(_cards)
	side.add_child(scroll)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key and key.pressed and key.keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if not visible or sim == null:
		return
	if selected != -1 and selected not in sim.areas.terminals:
		selected = -1
	var land_locked := sim.lock_error("land")
	for button: Node in find_children("*", "Button", true, false):
		if button.has_meta("land"):
			(button as Button).disabled = land_locked != ""
			(button as Button).tooltip_text = land_locked
	if land_locked != "":
		mode = "paint"
	_help.text = _help_text()
	_refresh_left -= dt
	var now := [sim, sim.areas.terminals.duplicate(true), selected]
	if now != _cards_for or _refresh_left <= 0.0:
		_cards_for = now
		_refresh_left = 0.5
		_build_cards()
	_canvas.queue_redraw()


func _help_text() -> String:
	if mode == "land":
		return "Click a tile to buy it: %s, then %s a day. Owned land is lighter." % [HudDetails.dollars(sim.rules.land.price), HudDetails.dollars(sim.rules.land.upkeep)]
	var painting: String = "a new terminal" if selected == -1 else sim.areas.terminals[selected].name
	return "Painting %s. Drag to paint, right-drag to erase; Fill block paints the ground a road closes in. An area joins the terminal holding most of it; one in no terminal does no work." % painting


## Paints, erases or fills at `cell`, or buys its tile, by mode and tool.
func act(cell: Vector2i, erase: bool) -> void:
	if mode == "land":
		command_issued.emit({"op": "buy_land", "tile": sim.land_tile(cell)})
		return
	if tool == "fill" and not erase:
		command_issued.emit({"op": "fill_terminal", "cell": cell, "terminal": selected})
	else:
		var cells: Array[Vector2i] = []
		for dx in range(-brush, brush + 1):
			for dy in range(-brush, brush + 1):
				if dx * dx + dy * dy <= brush * brush:
					cells.append(cell + Vector2i(dx, dy))
		command_issued.emit({"op": "paint_terminal", "cells": cells, "terminal": 0 if erase or tool == "erase" else selected})
		_canvas.repaint(cells)
	# A new terminal is made by its first stroke; paint on with it.
	if selected == -1 and not sim.areas.terminals.is_empty():
		selected = sim.areas.terminals.keys().max()


func _build_cards() -> void:
	for child in _cards.get_children():
		child.queue_free()
	var add := Button.new()
	add.text = "+ New terminal"
	add.toggle_mode = true
	add.button_pressed = selected == -1
	add.pressed.connect(func() -> void: selected = -1)
	_cards.add_child(add)
	for terminal: int in sim.areas.terminals:
		_cards.add_child(_terminal_card(terminal))


## Terminal `terminal`'s card: pick it to paint with, its colour and name,
## what it has and how it did yesterday, and what it lacks.
func _terminal_card(terminal: int) -> Control:
	var info: Dictionary = sim.areas.terminals[terminal]
	var colour: Color = COLOURS[info.colour]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card(Color(0.12, 0.15, 0.2) if terminal != selected else Color(0.16, 0.2, 0.27), 10, colour))
	var lines := VBoxContainer.new()
	card.add_child(lines)
	var top := HBoxContainer.new()
	lines.add_child(top)
	var swatch := Button.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.add_theme_stylebox_override("normal", _card(colour, 0))
	swatch.add_theme_stylebox_override("hover", _card(colour.lightened(0.2), 0))
	swatch.tooltip_text = "Change colour"
	swatch.pressed.connect(func() -> void: command_issued.emit({"op": "colour_terminal", "terminal": terminal}))
	top.add_child(swatch)
	var name := LineEdit.new()
	name.text = info.name
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_submitted.connect(func(text: String) -> void: command_issued.emit({"op": "name_terminal", "terminal": terminal, "name": text}))
	top.add_child(name)
	var paint := Button.new()
	paint.text = "Painting" if terminal == selected else "Paint"
	paint.disabled = terminal == selected
	paint.pressed.connect(func() -> void: selected = terminal)
	top.add_child(paint)
	var stats := Label.new()
	stats.text = _stats(terminal)
	stats.add_theme_color_override("font_color", MUTED)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(stats)
	var lacks := _lacks(terminal)
	if lacks != "":
		var warn := Label.new()
		warn.text = lacks
		warn.add_theme_color_override("font_color", WARN)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(warn)
	return card


## Terminal `terminal`'s berths, yard fill, gate turn and yesterday's moves.
func _stats(terminal: int) -> String:
	var mine := sim.areas.list.keys().filter(func(id: int) -> bool: return sim.areas.list[id].terminal == terminal)
	var berths := mine.filter(func(id: int) -> bool: return sim.areas.kind_of(sim.areas.list[id]) == "quay_apron").size()
	var fill := Vector2i.ZERO
	for id: int in mine:
		if sim.areas.kind_of(sim.areas.list[id]) == "yard_block":
			fill += sim.block_fill(id)
	var yard := "yard %d%% full" % roundi(100.0 * fill.x / fill.y) if fill.y > 0 else "no yard"
	var turn := sim.terminal_turn_minutes(terminal)
	var gate := "gate turn %.0f min" % turn if turn > 0.0 else "no lorries yet"
	var yesterday: Array = sim.ledger.days[-1].moves.terminals.get(terminal, [0, 0]) if not sim.ledger.days.is_empty() else [0, 0]
	return "%d berth%s · %s · %s\nYesterday %d moves, %s" % [berths, "" if berths == 1 else "s", yard, gate, yesterday[0], HudDetails.dollars(yesterday[1])]


## What terminal `terminal` lacks to work, or "".
func _lacks(terminal: int) -> String:
	var err := sim.areas.terminal_error(terminal)
	if err != "":
		return err
	if not sim.areas.list.values().any(func(a: Dictionary) -> bool: return a.terminal == terminal and sim.areas.kind_of(a) == "yard_block"):
		return "%s needs a yard block" % sim.areas.terminals[terminal].name
	return ""


func _toggle(row: Container, text: String, group: ButtonGroup, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.pressed.connect(on_press)
	row.add_child(button)
	return button


## A rounded box of `color`, with a left stripe of `stripe` when it is given.
static func _card(color: Color, margin: int, stripe := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(8)
	box.border_width_left = 5 if stripe.a > 0.0 else 0
	box.border_color = stripe
	box.set_content_margin_all(margin)
	return box


## The map itself: the port drawn a pixel a cell into an image, scaled to fit
## and kept square, with the paint over it and the brush under the mouse.
class MapCanvas extends Control:
	var map: PortMap
	var _ground := ImageTexture.new()
	var _paint := ImageTexture.new()
	var _paint_pixels: Image
	var _ground_for := []
	var _paint_for := -1
	var _stroke := -1  # mouse button held down, or -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	## The square the site is drawn in.
	func _frame() -> Rect2:
		var site := Vector2(Grid.size(map.sim.rules.site))
		var scale := minf(size.x / site.x, size.y / site.y)
		return Rect2((size - site * scale) / 2.0, site * scale)

	func _cell_at(at: Vector2) -> Vector2i:
		var frame := _frame()
		return Vector2i(((at - frame.position) / frame.size * Vector2(Grid.size(map.sim.rules.site))).floor())

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click and click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_stroke = click.button_index if click.pressed else -1
			if click.pressed:
				map.act(_cell_at(click.position), click.button_index == MOUSE_BUTTON_RIGHT)
			accept_event()
		var move := event as InputEventMouseMotion
		if move and _stroke != -1 and map.mode == "paint" and map.tool != "fill":
			map.act(_cell_at(move.position), _stroke == MOUSE_BUTTON_RIGHT)
			accept_event()

	func _draw() -> void:
		var sim := map.sim
		var key := [sim.roads.version, sim.areas.list.keys(), sim.land.size()]
		if key != _ground_for:
			_ground_for = key
			_ground.set_image(_ground_image())
		if sim.areas.version != _paint_for:
			_paint_for = sim.areas.version
			_paint_pixels = _paint_image()
			_paint.set_image(_paint_pixels)
		var frame := _frame()
		draw_texture_rect(_ground, frame, false)
		draw_texture_rect(_paint, frame, false)
		var mouse := get_local_mouse_position()
		if frame.has_point(mouse):
			var per_cell := frame.size.x / Grid.size(sim.rules.site).x
			if map.mode == "land":
				var tile := sim.land_tile(_cell_at(mouse))
				var metres: int = sim.rules.land.metres
				var cells := metres / Grid.CELL
				draw_rect(Rect2(frame.position + Vector2(tile) * cells * per_cell, Vector2.ONE * cells * per_cell), Color.WHITE, false, 2.0)
			elif map.tool != "fill":
				draw_arc(mouse, (map.brush + 0.5) * per_cell, 0.0, TAU, 32, Color.WHITE, 1.5)

	## Redraws just `cells` of the paint after a brush stroke, rather than all
	## of it: a full redraw of 137,600 painted cells took 101 ms.
	func repaint(cells: Array[Vector2i]) -> void:
		if _paint_pixels == null:
			return
		var sim := map.sim
		var site := Rect2i(Vector2i.ZERO, Grid.size(sim.rules.site))
		for cell in cells:
			if site.has_point(cell):
				var terminal: int = sim.areas.paint.get(cell, 0)
				_paint_pixels.set_pixelv(cell, Color(COLOURS[sim.areas.terminals[terminal].colour], 0.45) if terminal else Color.TRANSPARENT)
		_paint.update(_paint_pixels)
		_paint_for = sim.areas.version

	## Sea, land owned or not, roads and areas, a pixel a cell.
	func _ground_image() -> Image:
		var sim := map.sim
		var site := Grid.size(sim.rules.site)
		var image := Image.create(site.x, site.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.25, 0.2))
		var cells: int = sim.rules.land.metres / Grid.CELL
		for tile: Vector2i in sim.land:
			image.fill_rect(Rect2i(tile * cells, Vector2i.ONE * cells), Color(0.33, 0.4, 0.3))
		image.fill_rect(Rect2i(0, 0, Grid.cells(sim.rules.site.sea_width), site.y), Color(0.12, 0.3, 0.45))
		var kinds := {"yard_block": Color(0.62, 0.62, 0.58), "quay_apron": Color(0.75, 0.74, 0.68), "gate": Color(0.48, 0.56, 0.64), "parking": Color(0.42, 0.44, 0.47), "depot": Color(0.6, 0.55, 0.45)}
		for id: int in sim.areas.list:
			var colour: Color = kinds[sim.areas.kind_of(sim.areas.list[id])]
			for cell in sim.areas.cells(id):
				image.set_pixelv(cell, colour)
		for segment: int in sim.roads.segments:
			for lane: Dictionary in sim.roads.lanes(segment):
				for cell: Vector2i in lane.cells:
					if Rect2i(Vector2i.ZERO, site).has_point(cell):
						image.set_pixelv(cell, Color(0.12, 0.12, 0.14))
		return image

	## Each painted cell in its terminal's colour, see-through.
	func _paint_image() -> Image:
		var sim := map.sim
		var site := Grid.size(sim.rules.site)
		var image := Image.create(site.x, site.y, false, Image.FORMAT_RGBA8)
		for cell: Vector2i in sim.areas.paint:
			image.set_pixelv(cell, Color(COLOURS[sim.areas.terminals[sim.areas.paint[cell]].colour], 0.45))
		return image
