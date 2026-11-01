class_name AreaShape
extends RefCounted
## An area's own cells, laid along a stretch of a road's curve and turned
## with it, as Cities: Skylines lays zoning cells: column k runs one cell
## along the road's line, row r one cell further out from its edge. Each
## cell is a quad, so on a bend the outer rows stretch and the inner ones
## shrink; inner cells too small to use are left out.

## The shortest edge along the road, in cells, a cell keeps: below this the
## inside of a bend can't hold a stack.
const MIN_SIDE := 0.5

## Each cell kept: {"k": column, "r": row, "centre": Vector2, "corners":
## [near start, near end, far end, far start] as Vector2s in grid units}.
var cells: Array[Dictionary] = []


## The cells beside `curve` on `side` (1 right of its way, -1 left), from
## column `from` to `to` inclusive (one cell along the line each), starting
## `edge` cells off the line and reaching `depth` rows out.
static func along(curve: RoadCurve, side: int, from: int, to: int, edge: float, depth: int) -> AreaShape:
	var shape := AreaShape.new()
	for k in range(to - from + 1):
		var d0 := float(from + k)
		var d1 := d0 + 1.0
		var direction := curve.direction_at(d0 + 0.5)
		for r in depth:
			var near := edge + r
			var far := near + 1.0
			var corners: Array[Vector2] = [_at(curve, d0, near, side), _at(curve, d1, near, side), _at(curve, d1, far, side), _at(curve, d0, far, side)]
			if not (_usable(corners[0], corners[1], direction) and _usable(corners[3], corners[2], direction)):
				continue
			shape.cells.append({"k": k, "r": r, "centre": _at(curve, d0 + 0.5, near + 0.5, side), "corners": corners})
	return shape


## The point `distance` along `curve` and `offset` cells out to `side`.
static func _at(curve: RoadCurve, distance: float, offset: float, side: int) -> Vector2:
	return curve.point_at(distance) + curve.right_at(distance) * offset * side


## Whether an edge from `start` to `end` runs the road's way, `direction`,
## at least MIN_SIDE long: past a tight bend's centre it shrinks or turns back.
static func _usable(start: Vector2, end: Vector2, direction: Vector2) -> bool:
	return (end - start).dot(direction) >= MIN_SIDE
