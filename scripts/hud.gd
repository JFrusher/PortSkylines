class_name Hud
extends CanvasLayer
## Toolbar, speed buttons and the money/status readout. Reports the player's
## choices through `tool` and `speed`; never changes the sim.

const BULLDOZE := -1
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
	root.add_child(_outlined(_message))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spacer)

	var tools := ButtonGroup.new()
	var bar := _row(root)
	for kind: int in PortSim.COST:
		var label := "%s  $%d" % [PortMap.Tile.keys()[kind].capitalize(), PortSim.COST[kind]]
		_button(bar, label, tools, kind == tool, func() -> void: tool = kind)
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


func _outlined(label: Label) -> Label:
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	return label
