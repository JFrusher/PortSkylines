class_name Coast
extends RefCounted
## The site's land and water, from a map in the data: a land outline,
## islands and rivers as polygons and lines in metres. Each 4 m cell is land
## or water, and water has a depth: the map's shore depth, growing by
## per_metre with the distance to the nearest land up to its max; a river's
## water has the river's own depth. Built once per map and shared; a port's
## own changes (land reclaimed, water dredged) are kept by the port.

## Cells across and down.
var size: Vector2i
var _land: PackedByteArray  # 1 for land
var _depth: PackedFloat32Array  # metres; 0 on land
## Where rivers leave the site inland: {"cell", "radius"} in cells.
var inland_ends: Array[Dictionary] = []

static var _built := {}  # [map's hash, site size] -> Coast


## The coast for `map` (a map from rules.maps) on a site of `site`'s size,
## built the first time it is asked for.
static func of(map: Dictionary, site: Dictionary) -> Coast:
	var key := [map.hash(), Grid.size(site)]
	if key not in _built:
		_built[key] = Coast.new(map, Grid.size(site))
	return _built[key]


func _init(map: Dictionary, cells: Vector2i) -> void:
	size = cells
	_land.resize(size.x * size.y)
	_depth.resize(size.x * size.y)
	_fill(map.land, 1)
	for island: Array in map.islands:
		_fill(island, 1)
	var river := {}  # cell index -> depth
	for line: Dictionary in map.rivers:
		for i: int in line.points.size() - 1:
			_stamp(_point(line.points[i]), _point(line.points[i + 1]), line.width / Grid.CELL / 2.0, line.depth, river)
		# Its first point, on the site's edge, is where it runs inland.
		inland_ends.append({"cell": Vector2i(_point(line.points[0]).clamp(Vector2.ZERO, Vector2(size - Vector2i.ONE))), "radius": line.width / Grid.CELL / 2.0})
	for i: int in river:
		_land[i] = 0
	_shelf(map.depth)
	for i: int in river:
		_depth[i] = river[i]


## Whether `cell` lies in a river's inland end.
func is_inland_end(cell: Vector2i) -> bool:
	return inland_ends.any(func(end: Dictionary) -> bool: return Vector2(cell).distance_to(Vector2(end.cell)) <= end.radius + 1.0)


func is_water(cell: Vector2i) -> bool:
	return inside(cell) and _land[cell.y * size.x + cell.x] == 0


func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## The water's depth at `cell` in metres, 0 on land.
func depth(cell: Vector2i) -> float:
	return _depth[cell.y * size.x + cell.x]


static func _point(metres: Array) -> Vector2:
	return Vector2(metres[0], metres[1]) / Grid.CELL


## Sets every cell whose centre lies inside `polygon` (metres) to `value`,
## row by row: a cell is inside when an odd number of edges cross its row
## left of its centre.
func _fill(polygon: Array, value: int) -> void:
	var points: Array[Vector2] = []
	for p: Array in polygon:
		points.append(_point(p))
	for y: int in size.y:
		var row := y + 0.5
		var crossings: Array[float] = []
		for i: int in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if (a.y <= row) != (b.y <= row):
				crossings.append(a.x + (row - a.y) / (b.y - a.y) * (b.x - a.x))
		crossings.sort()
		for i: int in range(0, crossings.size() - 1, 2):
			for x: int in range(maxi(ceili(crossings[i] - 0.5), 0), mini(floori(crossings[i + 1] - 0.5) + 1, size.x)):
				_land[y * size.x + x] = value


## Marks the cells within `radius` cells of the line from `a` to `b` as river
## of `depth` metres.
func _stamp(a: Vector2, b: Vector2, radius: float, depth: float, river: Dictionary) -> void:
	var low := Vector2i((a.min(b) - Vector2.ONE * radius).floor()).max(Vector2i.ZERO)
	var high := Vector2i((a.max(b) + Vector2.ONE * radius).ceil()).min(size - Vector2i.ONE)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var centre := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_to(centre) <= radius:
				river[y * size.x + x] = depth


## Gives the sea its depth: `rule.shore` metres beside land, `rule.per_metre`
## more for each metre out, up to `rule.max`. The distance to land is a 3-4
## chamfer distance in two passes over the grid, about 4 cells for each 3
## along and across, close enough to Euclidean for a sea floor.
func _shelf(rule: Dictionary) -> void:
	var far := 1 << 30
	var steps := PackedInt32Array()
	steps.resize(size.x * size.y)
	for i: int in steps.size():
		steps[i] = 0 if _land[i] else far
	for y: int in size.y:
		for x: int in size.x:
			var i := y * size.x + x
			if steps[i] == 0:
				continue
			var best := steps[i]
			if x > 0:
				best = mini(best, steps[i - 1] + 3)
			if y > 0:
				best = mini(best, steps[i - size.x] + 3)
				if x > 0:
					best = mini(best, steps[i - size.x - 1] + 4)
				if x < size.x - 1:
					best = mini(best, steps[i - size.x + 1] + 4)
			steps[i] = best
	for y: int in range(size.y - 1, -1, -1):
		for x: int in range(size.x - 1, -1, -1):
			var i := y * size.x + x
			if steps[i] == 0:
				continue
			var best := steps[i]
			if x < size.x - 1:
				best = mini(best, steps[i + 1] + 3)
			if y < size.y - 1:
				best = mini(best, steps[i + size.x] + 3)
				if x < size.x - 1:
					best = mini(best, steps[i + size.x + 1] + 4)
				if x > 0:
					best = mini(best, steps[i + size.x - 1] + 4)
			steps[i] = best
	for i: int in steps.size():
		if not _land[i]:
			# A sea with no land at all is as deep as the rule allows.
			var metres := steps[i] / 3.0 * Grid.CELL if steps[i] < far else INF
			_depth[i] = minf(rule.shore + rule.per_metre * metres, rule.max)
