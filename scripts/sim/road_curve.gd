class_name RoadCurve
extends RefCounted
## One road segment's line: a quadratic Bézier from `a` through control
## point `c` to `b`, in grid units (a straight road has `c` at its middle).
## Roads, lanes, areas and vehicles measure along it by distance, through a
## table of lengths sampled along the curve.

## Pieces the length table cuts the curve into: within 0.5% of the true
## length for the sharpest bend a road may take.
const SAMPLES := 64
## Halvings the nearest-point search makes between two samples.
const REFINE := 20

var a: Vector2
var c: Vector2
var b: Vector2
## The curve's length, in grid units.
var length := 0.0
## The length from `a` to the curve's point at t = i / SAMPLES.
var _lengths := PackedFloat32Array()


func _init(start: Vector2, control: Vector2, end: Vector2) -> void:
	a = start
	c = control
	b = end
	_lengths.resize(SAMPLES + 1)
	var last := a
	for i in range(1, SAMPLES + 1):
		var p := point(float(i) / SAMPLES)
		_lengths[i] = _lengths[i - 1] + last.distance_to(p)
		last = p
	length = _lengths[SAMPLES]


## A straight segment from `start` to `end`.
static func straight(start: Vector2, end: Vector2) -> RoadCurve:
	return RoadCurve.new(start, (start + end) / 2.0, end)


## The curve's point at parameter `t`, 0 at `a` and 1 at `b`.
func point(t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + c * 2.0 * u * t + b * t * t


## The curve's unit direction at parameter `t`.
func tangent(t: float) -> Vector2:
	return ((c - a) * (1.0 - t) + (b - c) * t).normalized()


## The parameter `distance` along the curve, clamped to its ends.
func t_at(distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	if distance >= length:
		return 1.0
	var low := 0
	var high := SAMPLES
	while high - low > 1:
		var mid := (low + high) / 2
		if _lengths[mid] < distance:
			low = mid
		else:
			high = mid
	var span := _lengths[high] - _lengths[low]
	return (low + (distance - _lengths[low]) / span) / SAMPLES


## The distance along the curve at parameter `t`.
func distance_at(t: float) -> float:
	var at := clampf(t, 0.0, 1.0) * SAMPLES
	var i := mini(int(at), SAMPLES - 1)
	return lerpf(_lengths[i], _lengths[i + 1], at - i)


## The point `distance` along the curve.
func point_at(distance: float) -> Vector2:
	return point(t_at(distance))


## The unit direction `distance` along the curve.
func direction_at(distance: float) -> Vector2:
	return tangent(t_at(distance))


## The distance along the curve of its point nearest `position`: the nearest
## sample, then a ternary search between its neighbours.
func nearest(position: Vector2) -> float:
	var best := 0
	var closest := INF
	for i in SAMPLES + 1:
		var d := point(float(i) / SAMPLES).distance_squared_to(position)
		if d < closest:
			closest = d
			best = i
	var low := float(maxi(best - 1, 0)) / SAMPLES
	var high := float(mini(best + 1, SAMPLES)) / SAMPLES
	for i in REFINE:
		var one := lerpf(low, high, 1.0 / 3.0)
		var two := lerpf(low, high, 2.0 / 3.0)
		if point(one).distance_squared_to(position) < point(two).distance_squared_to(position):
			high = two
		else:
			low = one
	return distance_at((low + high) / 2.0)
