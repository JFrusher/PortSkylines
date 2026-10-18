class_name Hud
extends CanvasLayer
## Toolbar, speed buttons and the money/status readout. Reports the player's
## choices through `tool` and `speed`; never changes the sim.

signal save_pressed
signal load_pressed

const BULLDOZE := -1
const CRANE := -2
const SPEEDS: Array[int] = [0, 1, 2, 3, 6]
const FLASH_SECONDS := 2.5

var sim: PortSim
var tool: int = PortMap.Tile.ROAD
var speed := 1

var _readout := Label.new()
var _message := Label.new()
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
	_action(top, "Save", save_pressed)
	_action(top, "Load", load_pressed)
	root.add_child(_outlined(_message))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spacer)

	var tools := ButtonGroup.new()
	var bar := _row(root)
	for name: String in sim.rules.build_cost:
		var kind: int = PortMap.Tile[name.to_upper()]
		var label := "%s  $%d" % [name.capitalize(), sim.cost(kind)]
		_button(bar, label, tools, kind == tool, func() -> void: tool = kind)
	_button(bar, "Crane  $%d" % sim.rules.sts_crane.cost, tools, false, func() -> void: tool = CRANE)
	_button(bar, "Bulldoze", tools, false, func() -> void: tool = BULLDOZE)


## Shows a short-lived message, such as why a build was refused.
func flash(text: String) -> void:
	_message.text = text
	_flash_left = FLASH_SECONDS


func _process(dt: float) -> void:
	_readout.text = "$%d    Boxes delivered %d    Ships %d    Lorries %d" % [sim.money, sim.delivered, sim.ships.size(), sim.lorries.size()]
	_flash_left -= dt
	if _flash_left <= 0.0:
		_message.text = sim.status


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


func _button(row: HBoxContainer, text: String, group: ButtonGroup, pressed: bool, on_press: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = pressed
	button.pressed.connect(on_press)
	row.add_child(button)


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
