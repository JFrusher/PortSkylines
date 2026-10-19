class_name ChunkedMeshes
extends Node3D
## Many copies of a mesh drawn as one MultiMesh per key, where a key names a
## map chunk (plus, say, a tile kind). Each part is one draw call, and parts
## off screen are culled whole, so cost grows with chunks, not tiles.

const CHUNK := 32

## Camera distances to a part's centre between which it is drawn (0: no
## limit), so a view can draw a chunk in less detail as the camera pulls back.
var range_begin := 0.0
var range_end := 0.0
var _parts := {}


static func chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))


## Draws `transforms` copies of `mesh` for `key`, replacing what `key` drew
## before, tinted per copy by `colors` when given (a key always or never has them).
func show_part(key: Variant, mesh: Mesh, transforms: Array[Transform3D], colors := PackedColorArray()) -> void:
	if key not in _parts:
		var part := MultiMeshInstance3D.new()
		part.multimesh = MultiMesh.new()
		part.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		part.multimesh.use_colors = not colors.is_empty()
		part.multimesh.mesh = mesh
		part.visibility_range_begin = range_begin
		part.visibility_range_end = range_end
		add_child(part)
		_parts[key] = part
	var multimesh: MultiMesh = _parts[key].multimesh
	if multimesh.instance_count < transforms.size():
		multimesh.instance_count = transforms.size()
	multimesh.visible_instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		if not colors.is_empty():
			multimesh.set_instance_color(i, colors[i])
