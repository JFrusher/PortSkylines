class_name BerthBoard
extends PanelContainer
## The berth board, over the whole screen, like a controller's strip board:
## lines' offers come in as strips on the left; drag one onto a berth's week
## to agree it there, and the sim times it at the line's hour or the nearest
## free one within its flex band. Agreed calls sit on their berth's week:
## drag one to move it, click it to let its ship take any free berth when its
## own is busy. Asks for changes through `command_issued`; never changes the sim.

signal command_issued(command: Dictionary)
signal closed

const HudDetails := preload("res://scripts/hud_details.gd")
const WEEKDAYS: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const ROW_HEIGHT := 36.0
## A colour per line, in rules.lines order.
const LINE_COLORS: Array[Color] = [Color(0.0, 0.44, 0.87), Color(0.87, 0.47, 0.1), Color(0.2, 0.66, 0.36), Color(0.62, 0.32, 0.78), Color(0.78, 0.22, 0.32), Color(0.1, 0.62, 0.66)]
const MUTED := Color(0.58, 0.639, 0.722)
const OK := Color(0.3, 1, 0.4)
const REFUSED := Color(1, 0.3, 0.25)

var sim: PortSim
## What the board was last built for.
var _drawn := []
## Made in _ready, where they join the board.
var _reputation: Label
var _help: Label
var _inbox: VBoxContainer
var _rows: VBoxContainer
var _footer: VBoxContainer
var _timelines: Array[Timeline] = []


func _ready() -> void:
	_reputation = Label.new()
	_help = Label.new()
	_inbox = VBoxContainer.new()
	_rows = VBoxContainer.new()
	_footer = VBoxContainer.new()
	add_theme_stylebox_override("panel", _card(Color(0.07, 0.09, 0.12), Color.TRANSPARENT, 16))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		set("offset_" + side, 24.0 if side in ["left", "top"] else -24.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Berth board"
	title.theme_type_variation = "ClockLabel"
	header.add_child(title)
	_reputation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reputation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_reputation)
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
	body.add_child(_scrolled(_inbox, 300.0))
	var rows := _scrolled(_rows, 0.0)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rows)
	column.add_child(_footer)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()


func _process(_dt: float) -> void:
	if not visible or sim == null:
		return
	var now := [sim, sim.contracts.version, sim.areas.version, sim.cranes.size(), sim.storage.duplicate(), sim.rail_discount, sim.barge_discount, roundi(sim.clock.calendar_minutes() / 60.0)]
	if now != _drawn:
		_drawn = now
		_build()
	for timeline in _timelines:
		timeline.queue_redraw()


## The offer or agreed service with id `id`, or {}.
func service(id: int) -> Dictionary:
	for found: Dictionary in sim.contracts.offers + sim.contracts.services:
		if found.id == id:
			return found
	return {}


## Where dragged service `data` would land on berth `apron`: {"start" (minute
## of the week, -1 if refused), "service", "why" (the refusal, or "")}.
func landing(data: Dictionary, apron: int) -> Dictionary:
	var dragged := service(data.id)
	var why: String = sim.accept_offer_error(data.id, apron) if data.offer else sim.move_service_error(data.id, apron)
	return {"start": sim.contracts.place(dragged, apron) if why == "" else -1, "service": dragged, "why": why}


func drop(data: Dictionary, apron: int) -> void:
	command_issued.emit({"op": "accept_offer" if data.offer else "move_service", "id": data.id, "apron": apron})


func toggle_any_berth(id: int) -> void:
	command_issued.emit({"op": "set_any_berth", "id": id, "any_berth": not service(id).any_berth})


## Asks before ending agreed service `id`, since its line holds it against the port.
func ask_cancel(id: int) -> void:
	var found := service(id)
	var line: String = found.line
	var confirm := ConfirmationDialog.new()
	confirm.title = "Cancel this service?"
	confirm.dialog_text = "End %s's weekly %s service? Their reputation of the port drops by %d." % [
		sim.contracts.name_of(line), found.kind, roundi(-sim.rules.reputation.port_cancels * sim.rules.lines[line].sensitivity)]
	confirm.ok_button_text = "Cancel service"
	confirm.cancel_button_text = "Keep it"
	confirm.confirmed.connect(func() -> void: command_issued.emit({"op": "cancel_service", "id": id}))
	confirm.visibility_changed.connect(func() -> void: if not confirm.visible: confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()


func color_of(line: String) -> Color:
	return LINE_COLORS[sim.rules.lines.keys().find(line) % LINE_COLORS.size()]


## "Mon 06:00" for minute `minute` of the week.
static func when(minute: int) -> String:
	return "%s %02d:%02d" % [WEEKDAYS[minute / SimClock.MINUTES_PER_DAY], minute / 60 % 24, minute % 60]


func _build() -> void:
	_help.text = "Drag an offer onto a berth to agree it there: it calls at the line's time, or the nearest free hour within %d h of it. Drag a call to move it; click it to let its ship take any free berth when its own is busy (a white top edge); right-click it to cancel it." % sim.rules.contracts.flex_hours
	var standing: Array[String] = []
	for line: String in sim.contracts.reputation:
		standing.append("%s %d" % [sim.contracts.name_of(line), roundi(sim.contracts.reputation[line])])
	_reputation.text = "Reputation   " + "    ".join(standing)
	for box: Container in [_inbox, _rows, _footer]:
		for child in box.get_children():
			child.queue_free()
	_timelines.clear()
	_build_inbox()
	_build_rows()
	_build_footer()


func _build_inbox() -> void:
	var heading := Label.new()
	heading.text = "Offers (%d)" % sim.contracts.offers.size()
	heading.theme_type_variation = "CategoryHeader"
	_inbox.add_child(heading)
	if sim.contracts.offers.is_empty():
		_inbox.add_child(_note("Lines offer services once a crane stands at a berth, while their reputation of the port is good and berths have room."))
	for offer: Dictionary in sim.contracts.offers:
		var strip := Strip.new()
		strip.add_theme_stylebox_override("panel", _card(Color(1, 1, 1, 0.06), color_of(offer.line), 8))
		strip.board = self
		strip.id = offer.id
		_inbox.add_child(strip)
		var lines := VBoxContainer.new()
		strip.add_child(lines)
		var top := HBoxContainer.new()
		lines.add_child(top)
		var name := Label.new()
		name.text = "%s · %s" % [sim.contracts.name_of(offer.line), offer.kind.capitalize()]
		name.add_theme_color_override("font_color", color_of(offer.line).lightened(0.35))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name)
		var decline := Button.new()
		decline.text = "✕"
		decline.tooltip_text = "Decline this offer"
		var id: int = offer.id
		decline.pressed.connect(func() -> void: command_issued.emit({"op": "decline_offer", "id": id}))
		top.add_child(decline)
		lines.add_child(_note("Asks %s for %d h, weekly" % [when(offer.asked), roundi(offer.window_hours)]))
		lines.add_child(_note("%d moves, %s a call" % [offer.moves, HudDetails.dollars(sim.contracts.call_value(offer))]))
		lines.add_child(_note("Offered ends day %d" % int(offer.expires / SimClock.MINUTES_PER_DAY)))
		strip.tooltip_text = "Drag onto a berth to agree it there"


func _build_rows() -> void:
	var aprons := AreaFlow.ready_aprons(sim)
	if aprons.is_empty():
		_rows.add_child(_note("No working berths yet: a berth needs a crane, and a gate and road in its terminal."))
	var axis := Timeline.new()
	axis.board = self
	axis.apron = -1
	axis.custom_minimum_size.y = 18.0
	_rows.add_child(_row("", axis))
	var by_terminal := {}
	for apron in aprons:
		var terminal: int = sim.areas.list[apron].terminal
		by_terminal[terminal] = by_terminal.get(terminal, []) + [apron]
	var number := 0
	for terminal: int in by_terminal:
		var heading := Label.new()
		heading.text = sim.areas.terminals[terminal].name
		heading.theme_type_variation = "CategoryHeader"
		_rows.add_child(heading)
		for apron: int in by_terminal[terminal]:
			number += 1
			var timeline := Timeline.new()
			timeline.board = self
			timeline.apron = apron
			_rows.add_child(_row("Berth %d · %d m" % [number, Grid.metres(AreaFlow._length(sim, apron))], timeline))
	# Services from before berths were chosen, until they are dragged onto one.
	if sim.contracts.services.any(func(s: Dictionary) -> bool: return s.apron == 0):
		var waiting := Timeline.new()
		waiting.board = self
		waiting.apron = 0
		_rows.add_child(_row("No berth yet", waiting))


func _build_footer() -> void:
	var terms := HBoxContainer.new()
	_footer.add_child(terms)
	var free: int = sim.storage.free_days
	var fee: int = sim.storage.fee
	terms.add_child(_plain("Storage: %d free days, then $%d a box a day" % [free, fee]))
	for change: Array in [["- day", -1, 0], ["+ day", 1, 0], ["- $10", 0, -10], ["+ $10", 0, 10]]:
		var button := Button.new()
		button.text = change[0]
		var free_days: int = free + change[1]
		var new_fee: int = fee + change[2]
		button.pressed.connect(func() -> void: command_issued.emit({"op": "set_storage", "free_days": free_days, "fee": new_fee}))
		terms.add_child(button)
	var rail := HBoxContainer.new()
	_footer.add_child(rail)
	var discount := sim.rail_discount
	var locked := sim.lock_error("rmg")
	var shares: Array = sim.rules.lines.keys().map(func(line: String) -> String: return "%s %d%%" % [sim.contracts.name_of(line), roundi(sim.rail_share(line) * 100)])
	rail.add_child(_plain("Rail discount: $%d a box by train. By rail where a rail block can take it: %s" % [discount, ", ".join(shares)]))
	for change: Array in [["- $10", -10], ["+ $10", 10]]:
		var button := Button.new()
		button.text = change[0]
		var dollars: int = discount + change[1]
		button.disabled = locked != ""
		button.tooltip_text = locked if locked else "Each box carried by train costs the discount; each dollar moves %.1f%% more of every line's boxes onto rail, up to %d%%" % [sim.rules.rail.discount.share_per_dollar * 100, roundi(sim.rules.rail.discount.max_share * 100)]
		button.pressed.connect(func() -> void: command_issued.emit({"op": "set_rail_discount", "dollars": dollars}))
		rail.add_child(button)
	_footer.add_child(_barge_row(sim))


## The barge discount, its buttons, and how each line's imports for places
## up the river split between road, rail and barge: barge first while
## barges call, rail of the rest, road the remainder.
func _barge_row(sim: PortSim) -> HBoxContainer:
	var row := HBoxContainer.new()
	var calling := sim.contracts.services.any(func(s: Dictionary) -> bool: return sim.rules.ship_classes[s.kind].inland)
	var split := func(line: String) -> String:
		var barge := sim.barge_share(line) if calling else 0.0
		var rail := sim.rail_share(line) * (1.0 - barge)
		return "%s road %d%%, rail %d%%, barge %d%%" % [sim.contracts.name_of(line), roundi((1.0 - barge - rail) * 100), roundi(rail * 100), roundi(barge * 100)]
	var lines: Array = sim.rules.lines.keys().filter(func(line: String) -> bool: return not sim.rules.lines[line].classes.has("barge"))
	var text := _plain("Barge discount: $%d a box by barge. Imports for places up the river: %s" % [sim.barge_discount, "; ".join(lines.map(split))])
	# Wrapped in the room beside its buttons, so it never widens the board.
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var locked := sim.lock_error("barge")
	for change: Array in [["- $10", -10], ["+ $10", 10]]:
		var button := Button.new()
		button.text = change[0]
		var dollars: int = sim.barge_discount + change[1]
		button.disabled = locked != ""
		button.tooltip_text = locked if locked else "Each box carried by barge costs the discount; each dollar moves %.1f%% more of every line's boxes for places up the river onto barges, from road and rail alike, up to %d%%" % [sim.rules.barge.discount.share_per_dollar * 100, roundi(sim.rules.barge.discount.max_share * 100)]
		button.pressed.connect(func() -> void: command_issued.emit({"op": "set_barge_discount", "dollars": dollars}))
		row.add_child(button)
	return row


func _row(text: String, timeline: Timeline) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 150.0
	label.add_theme_color_override("font_color", MUTED)
	row.add_child(label)
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if timeline.custom_minimum_size.y == 0.0:
		timeline.custom_minimum_size.y = ROW_HEIGHT
	row.add_child(timeline)
	_timelines.append(timeline)
	return row


## A label that keeps to one line.
func _plain(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED)
	return label


## A rounded box of `color`, with a stripe of `stripe` down its left edge.
static func _card(color: Color, stripe: Color, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(8)
	box.border_width_left = 4 if stripe.a > 0.0 else 0
	box.border_color = stripe
	box.set_content_margin_all(margin)
	return box


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED)
	return label


func _scrolled(content: Control, width: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = width
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	return scroll


## An offer in the inbox, dragged onto a berth's week.
class Strip extends PanelContainer:
	var board: BerthBoard
	var id: int

	func _get_drag_data(_at: Vector2) -> Variant:
		var offer := board.service(id)
		var preview := Label.new()
		preview.text = "%s · %s" % [board.sim.contracts.name_of(offer.line), offer.kind.capitalize()]
		set_drag_preview(preview)
		return {"id": id, "offer": true}


## One berth's week, Monday to Sunday, with its agreed calls; apron 0 holds
## the calls with no berth yet, -1 is the day axis above the rows.
class Timeline extends Control:
	var board: BerthBoard
	var apron := 0
	## Where the strip being dragged over would land, from BerthBoard.landing.
	var _ghost := {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS if apron == -1 else Control.MOUSE_FILTER_STOP

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if apron <= 0 or not (data is Dictionary and data.has("offer")):
			return false
		_ghost = board.landing(data, apron)
		queue_redraw()
		return _ghost.why == ""

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_ghost = {}
		board.drop(data, apron)

	func _notification(what: int) -> void:
		if what in [NOTIFICATION_DRAG_END, NOTIFICATION_MOUSE_EXIT]:
			_ghost = {}
			queue_redraw()

	func _get_drag_data(at: Vector2) -> Variant:
		var found := _call_at(at)
		if found.is_empty():
			return null
		var preview := Label.new()
		preview.text = "%s · %s" % [board.sim.contracts.name_of(found.line), found.kind.capitalize()]
		set_drag_preview(preview)
		return {"id": found.id, "offer": false}

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if not click or click.pressed:
			return
		var found := _call_at(click.position)
		if found.is_empty():
			return
		if click.button_index == MOUSE_BUTTON_LEFT:
			board.toggle_any_berth(found.id)
		elif click.button_index == MOUSE_BUTTON_RIGHT:
			board.ask_cancel(found.id)

	func _get_tooltip(at: Vector2) -> String:
		var found := _call_at(at)
		if found.is_empty():
			return ""
		return "%s %s: %s for %d h, %d moves, %s a call\nThe line asked for %s.\n%s\nDrag to move; click to %s; right-click to cancel." % [
			board.sim.contracts.name_of(found.line), found.kind, BerthBoard.when(found.start), roundi(found.window_hours), found.moves,
			HudDetails.dollars(board.sim.contracts.call_value(found)), BerthBoard.when(found.asked),
			"Takes any free berth when its own is busy." if found.any_berth else "Waits for its own berth when it is busy.",
			"make it wait for its own berth" if found.any_berth else "let it take any free berth"]

	## The agreed call on this row under `at`, or {}.
	func _call_at(at: Vector2) -> Dictionary:
		if apron < 0:
			return {}
		var minute := floori(at.x / size.x * Contracts.MINUTES_PER_WEEK)
		for service: Dictionary in board.sim.contracts.services:
			if service.apron == apron and fposmod(minute - service.start, Contracts.MINUTES_PER_WEEK) < service.window_hours * 60.0:
				return service
		return {}

	func _draw() -> void:
		var font := get_theme_default_font()
		var hour := size.x / (7 * 24.0)
		if apron == -1:
			for day in 7:
				draw_string(font, Vector2(day * 24 * hour + 3, 13), BerthBoard.WEEKDAYS[day], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, BerthBoard.MUTED)
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.05))
		for day in range(1, 7):
			draw_line(Vector2(day * 24 * hour, 0), Vector2(day * 24 * hour, size.y), Color(1, 1, 1, 0.12))
		for service: Dictionary in board.sim.contracts.services:
			if service.apron != apron:
				continue
			var color := board.color_of(service.line)
			_span(service.start, service.window_hours * 60.0, color, true)
			if service.any_berth:
				_span(service.start, service.window_hours * 60.0, Color.WHITE, true, 3.0)
			var label := "%s %s" % [board.sim.contracts.name_of(service.line), service.kind]
			draw_string(font, Vector2(service.start / 60.0 * hour + 4, size.y / 2 + 5), label, HORIZONTAL_ALIGNMENT_LEFT, service.window_hours * hour - 6, 12, Color.WHITE)
		if not _ghost.is_empty():
			var dragged: Dictionary = _ghost.service
			var flex: int = board.sim.rules.contracts.flex_hours
			# The band the line agrees to, then where the call would land in it.
			_span(posmod(dragged.asked - flex * 60, Contracts.MINUTES_PER_WEEK), (flex * 2 + dragged.window_hours) * 60.0, Color(1, 1, 1, 0.08), true)
			if _ghost.start >= 0:
				_span(_ghost.start, dragged.window_hours * 60.0, BerthBoard.OK, false)
				draw_string(font, Vector2(_ghost.start / 60.0 * hour + 4, size.y - 3), BerthBoard.when(_ghost.start), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BerthBoard.OK)
			else:
				draw_rect(Rect2(Vector2.ZERO, size), BerthBoard.REFUSED, false, 2.0)
				draw_string(font, Vector2(6, size.y / 2 + 5), _ghost.why, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, 12, BerthBoard.REFUSED)
		# Now, on the berth's week.
		var now := fmod(board.sim.clock.calendar_minutes(), Contracts.MINUTES_PER_WEEK) / 60.0 * hour
		draw_line(Vector2(now, 0), Vector2(now, size.y), Color(1, 0.85, 0.3), 2.0)

	## A span of `minutes` from minute `start` of the week, wrapping past
	## Sunday back to Monday; filled, or outlined; `tall` pixels tall at the
	## top of the row when set, else the row's height.
	func _span(start: int, minutes: float, color: Color, filled: bool, tall := 0.0) -> void:
		var hour := size.x / (7 * 24.0)
		var minute := start
		var remaining := roundi(minutes)
		while remaining > 0:
			var piece := mini(remaining, Contracts.MINUTES_PER_WEEK - minute)
			# A pixel short, so back-to-back calls read as two.
			draw_rect(Rect2(minute / 60.0 * hour, 3, piece / 60.0 * hour - 1.0, tall if tall > 0.0 else size.y - 6), color, filled, -1.0 if filled else 2.0)
			minute = (minute + piece) % Contracts.MINUTES_PER_WEEK
			remaining -= piece
