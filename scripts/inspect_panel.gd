class_name InspectPanel
extends VBoxContainer
## The inspect panel's body, as Cities: Skylines 2's selected info panel:
## an overview of what is selected, then collapsible sections of controls
## (InspectControls decides them). A choice is a dropdown, a switch a check
## button, a count a stepper, a set of lines a checklist; each issues the
## command it carries.

signal command_issued(command: Dictionary)

## Whether each section, by title, was left open, so a redraw keeps it.
var _open := {}
var _overview := Label.new()
var _sections := VBoxContainer.new()


func _init() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size.x = 340
	_overview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_section("Overview", true).add_child(_overview)
	add_child(_sections)


## The overview's lines of state.
func set_overview(lines: Array[String]) -> void:
	_overview.text = "\n".join(lines)
	_overview.get_parent().get_parent().visible = not lines.is_empty()


## Draws `sections` (see InspectControls) in place of the last ones.
func show_sections(sections: Array[Dictionary]) -> void:
	for child in _sections.get_children():
		child.queue_free()
	for spec: Dictionary in sections:
		var body := _section(spec.title, spec.open, _sections)
		for control: Dictionary in spec.controls:
			body.add_child(_control(control))


## A collapsible section titled `title` in `parent` (this panel when null);
## returns the column to fill.
func _section(title: String, open: bool, parent: Control = null) -> VBoxContainer:
	var box := VBoxContainer.new()
	(parent if parent else self).add_child(box)
	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.theme_type_variation = "PanelTitle"
	box.add_child(header)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	box.add_child(body)
	var shown: bool = _open.get(title, open)
	var draw := func(on: bool) -> void:
		body.visible = on
		header.text = ("▾ " if on else "▸ ") + title
	draw.call(shown)
	header.pressed.connect(func() -> void:
		_open[title] = not body.visible
		draw.call(not body.visible))
	return body


func _control(spec: Dictionary) -> Control:
	match spec.kind:
		"choice":
			var pick := OptionButton.new()
			pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for i: int in spec.options.size():
				var option: Dictionary = spec.options[i]
				pick.add_item(option.text, i)
				pick.set_item_disabled(i, option.disabled)
				pick.set_item_tooltip(i, option.tip)
				if option.selected:
					pick.select(i)
			if not spec.options.any(func(o: Dictionary) -> bool: return o.selected):
				pick.select(-1)
				pick.text = "Choose…"
			pick.item_selected.connect(func(i: int) -> void:
				if not spec.options[i].selected:
					command_issued.emit(spec.options[i].command))
			return _labelled(spec.label, pick)
		"toggle":
			var check := CheckButton.new()
			check.text = spec.label
			check.button_pressed = spec.on
			check.tooltip_text = spec.tip
			check.toggled.connect(func(_on: bool) -> void: command_issued.emit(spec.command))
			return check
		"stepper":
			var row := HBoxContainer.new()
			row.tooltip_text = spec.tip
			var value := Label.new()
			value.text = spec.value
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			for side: Array in [["−", spec.minus], ["+", spec.plus]]:
				var button := Button.new()
				button.text = side[0]
				button.custom_minimum_size = Vector2(32, 0)
				button.disabled = side[1].is_empty()
				button.tooltip_text = spec.tip
				var command: Dictionary = side[1]
				button.pressed.connect(func() -> void: command_issued.emit(command))
				row.add_child(button)
				if side[0] == "−":
					row.add_child(value)
			return _labelled(spec.label, row)
		"checklist":
			var list := VBoxContainer.new()
			list.tooltip_text = spec.tip
			for item: Dictionary in spec.items:
				var box := CheckBox.new()
				box.text = item.text
				box.button_pressed = item.on
				box.toggled.connect(func(_on: bool) -> void: command_issued.emit(item.command))
				list.add_child(box)
			return _labelled(spec.label, list, true)
		_:
			var button := Button.new()
			button.text = spec.text
			button.disabled = spec.disabled
			button.tooltip_text = spec.tip
			button.pressed.connect(func() -> void: command_issued.emit(spec.command))
			return button


## `control` after `label`, on one row, or under it when `stacked`.
func _labelled(label: String, control: Control, stacked := false) -> Control:
	var box: BoxContainer = VBoxContainer.new() if stacked else HBoxContainer.new()
	var text := Label.new()
	text.text = label
	text.custom_minimum_size.x = 0 if stacked else 110
	box.add_child(text)
	box.add_child(control)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box
