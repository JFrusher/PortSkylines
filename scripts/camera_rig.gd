class_name CameraRig
extends Node3D
## City-builder camera: WASD/arrows pan, Q/E rotate, mouse wheel zooms.

const PAN_SPEED := 20.0
const TURN_SPEED := 1.5
const PITCH := deg_to_rad(55.0)

## Area the camera's focus point may move within.
var bounds := Rect2()
var distance := 40.0
var camera := Camera3D.new()


func _ready() -> void:
	add_child(camera)
	camera.rotation.x = -PITCH
	_place_camera()


func _process(dt: float) -> void:
	rotation.y += (_held(KEY_Q) - _held(KEY_E)) * TURN_SPEED * dt
	var move := Vector3(_held(KEY_D, KEY_RIGHT) - _held(KEY_A, KEY_LEFT), 0, _held(KEY_S, KEY_DOWN) - _held(KEY_W, KEY_UP))
	position += basis * move * PAN_SPEED * dt * distance / 40.0
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance * 0.9, 8.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance * 1.1, 90.0)
		_place_camera()


func _place_camera() -> void:
	camera.position = Vector3(0, sin(PITCH), cos(PITCH)) * distance


func _held(key: Key, alt: Key = KEY_NONE) -> float:
	return 1.0 if Input.is_physical_key_pressed(key) or (alt != KEY_NONE and Input.is_physical_key_pressed(alt)) else 0.0
