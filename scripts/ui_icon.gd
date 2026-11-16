class_name UiIcon
extends Control
## A flat line icon drawn in code, for the toolbar and the status bar: the
## game has no icon art, and drawn icons stay sharp at every interface size.
## Set `glyph` to one of GLYPHS; it fills its rect, centred, in `color`.

const GLYPHS := ["roads", "quay", "cranes", "yard", "gate", "water", "bulldoze", "inspect", "map", "statistics", "harbour", "menu", "news", "advisor", "scenario", "views"]

@export var glyph := "roads"
var color := Color(0.92, 0.95, 1.0)


static func make(name: String, side := 28.0) -> UiIcon:
	assert(name in GLYPHS, "no icon %s" % name)
	var icon := UiIcon.new()
	icon.glyph = name
	icon.custom_minimum_size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) / 2.0
	var w := maxf(1.5, s / 14.0)
	# Points in a 0..1 box, placed in the icon's square.
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var line := func(a: Vector2, b: Vector2) -> void: draw_line(p.call(a.x, a.y), p.call(b.x, b.y), color, w, true)
	var box := func(x: float, y: float, bw: float, bh: float, filled := false) -> void: draw_rect(Rect2(p.call(x, y), Vector2(bw, bh) * s), color, filled, -1.0 if filled else w)
	match glyph:
		"roads":
			line.call(Vector2(0.3, 0.05), Vector2(0.15, 0.95))
			line.call(Vector2(0.7, 0.05), Vector2(0.85, 0.95))
			for y: float in [0.15, 0.45, 0.75]:
				line.call(Vector2(0.5, y), Vector2(0.5, y + 0.15))
		"quay":
			box.call(0.08, 0.3, 0.84, 0.25, true)
			for y: float in [0.68, 0.85]:
				for x: float in [0.08, 0.38, 0.68]:
					draw_arc(p.call(x + 0.12, y), s * 0.12, PI, TAU, 8, color, w, true)
		"cranes":
			line.call(Vector2(0.3, 0.95), Vector2(0.3, 0.2))
			line.call(Vector2(0.55, 0.95), Vector2(0.55, 0.2))
			line.call(Vector2(0.05, 0.2), Vector2(0.95, 0.2))
			line.call(Vector2(0.3, 0.45), Vector2(0.55, 0.45))
			line.call(Vector2(0.85, 0.2), Vector2(0.85, 0.55))
			box.call(0.77, 0.55, 0.16, 0.1, true)
		"yard":
			for r: Array in [[0.08, 0.62], [0.52, 0.62], [0.3, 0.32]]:
				box.call(r[0], r[1], 0.4, 0.26)
		"gate":
			box.call(0.08, 0.35, 0.16, 0.6, true)
			line.call(Vector2(0.24, 0.45), Vector2(0.95, 0.45))
			for x: float in [0.4, 0.6, 0.8]:
				line.call(Vector2(x, 0.38), Vector2(x, 0.52))
		"water":
			for y: float in [0.35, 0.6, 0.85]:
				for x: float in [0.05, 0.37, 0.69]:
					draw_arc(p.call(x + 0.13, y), s * 0.13, PI, TAU, 8, color, w, true)
		"bulldoze":
			box.call(0.15, 0.35, 0.45, 0.3, true)
			box.call(0.3, 0.18, 0.2, 0.17)
			line.call(Vector2(0.75, 0.25), Vector2(0.75, 0.75))
			line.call(Vector2(0.6, 0.5), Vector2(0.75, 0.5))
			for x: float in [0.25, 0.5]:
				draw_circle(p.call(x, 0.78), s * 0.1, color)
		"inspect":
			draw_arc(p.call(0.42, 0.42), s * 0.27, 0.0, TAU, 20, color, w, true)
			line.call(Vector2(0.62, 0.62), Vector2(0.92, 0.92))
		"map":
			draw_polyline(PackedVector2Array([p.call(0.05, 0.2), p.call(0.35, 0.08), p.call(0.65, 0.2), p.call(0.95, 0.08), p.call(0.95, 0.8), p.call(0.65, 0.92), p.call(0.35, 0.8), p.call(0.05, 0.92), p.call(0.05, 0.2)]), color, w, true)
			line.call(Vector2(0.35, 0.08), Vector2(0.35, 0.8))
			line.call(Vector2(0.65, 0.2), Vector2(0.65, 0.92))
		"statistics":
			line.call(Vector2(0.08, 0.92), Vector2(0.92, 0.92))
			box.call(0.15, 0.55, 0.16, 0.33, true)
			box.call(0.42, 0.3, 0.16, 0.58, true)
			box.call(0.69, 0.12, 0.16, 0.76, true)
		"harbour":
			draw_arc(p.call(0.5, 0.2), s * 0.1, 0.0, TAU, 12, color, w, true)
			line.call(Vector2(0.5, 0.3), Vector2(0.5, 0.92))
			line.call(Vector2(0.3, 0.42), Vector2(0.7, 0.42))
			draw_arc(p.call(0.5, 0.6), s * 0.32, 0.15 * PI, 0.85 * PI, 12, color, w, true)
		"menu":
			for y: float in [0.25, 0.5, 0.75]:
				line.call(Vector2(0.15, y), Vector2(0.85, y))
		"news":
			box.call(0.1, 0.18, 0.8, 0.64)
			line.call(Vector2(0.2, 0.35), Vector2(0.8, 0.35))
			line.call(Vector2(0.2, 0.5), Vector2(0.55, 0.5))
			line.call(Vector2(0.2, 0.65), Vector2(0.55, 0.65))
			box.call(0.62, 0.47, 0.18, 0.2, true)
		"advisor":
			draw_arc(p.call(0.5, 0.42), s * 0.36, 0.0, TAU, 20, color, w, true)
			line.call(Vector2(0.32, 0.72), Vector2(0.22, 0.95))
			draw_circle(p.call(0.5, 0.58), s * 0.05, color)
			line.call(Vector2(0.5, 0.25), Vector2(0.5, 0.45))
		"views":
			# Three stacked map layers.
			for y: float in [0.3, 0.5, 0.7]:
				draw_polyline(PackedVector2Array([p.call(0.1, y), p.call(0.5, y - 0.15), p.call(0.9, y), p.call(0.5, y + 0.15), p.call(0.1, y)]), color, w, true)
		"scenario":
			line.call(Vector2(0.22, 0.95), Vector2(0.22, 0.08))
			draw_colored_polygon(PackedVector2Array([p.call(0.24, 0.1), p.call(0.85, 0.25), p.call(0.24, 0.42)]), color)
