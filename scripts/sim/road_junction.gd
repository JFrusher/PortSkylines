class_name RoadJunction
extends RefCounted
## The shape of a node where roads meet: how far each road is trimmed back
## from the node so that no two roads' edges overlap, with a corner between
## them, as Cities: Skylines shapes its junctions from the roads' widths.

## Roads within this many degrees of straight on carry on through a node
## and don't trim each other.
const STRAIGHT_ON := 10.0


## For `roads`, each {"direction": unit vector away from the node,
## "half_width": cells either side of its line}: {"trims": cells each is
## cut back from the node}, or {"error"} when two meet at less than
## rules.min_angle degrees.
static func shape(roads: Array[Dictionary], rules: Dictionary) -> Dictionary:
	var trims: Array[float] = []
	for i in roads.size():
		var trim := 0.0
		for j in roads.size():
			if i == j:
				continue
			var angle := rad_to_deg(roads[i].direction.angle_to(roads[j].direction))
			var apart := absf(angle)
			if apart < rules.min_angle - 0.001:
				return {"error": "Roads meet at %d°; a junction needs at least %d°" % [roundi(apart), roundi(rules.min_angle)]}
			trim = maxf(trim, _clear(roads[i].half_width, roads[j].half_width, apart))
		trims.append(trim + rules.corner_cells if trim > 0.0 else 0.0)
	return {"trims": trims}


## How far along a road `mine` cells half-wide its edge must run from the
## node to clear the near edge of a road `theirs` half-wide leaving
## `apart` degrees away: where the two edges cross.
static func _clear(mine: float, theirs: float, apart: float) -> float:
	if apart >= 180.0 - STRAIGHT_ON:
		return 0.0
	var theta := deg_to_rad(apart)
	return maxf(0.0, (theirs + mine * cos(theta)) / sin(theta))


## The shape's input for `arms`, each {"direction": unit vector away from
## the node, "road": its road type, drawn away from the node}.
static func footprints(arms: Array[Dictionary]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for arm: Dictionary in arms:
		found.append({"direction": arm.direction, "half_width": (arm.road.forward + arm.road.backward) / 2.0})
	return found


## Where lane `lane` of `arm` meets the junction, `trim` cells from the
## node (at the origin): its offset across the arm, drawn away from the node.
static func lane_point(arm: Dictionary, lane: int, trim: float) -> Vector2:
	var right := Vector2(-arm.direction.y, arm.direction.x)
	return arm.direction * trim + right * RoadCurve.lanes(arm.road)[lane].offset


## How lanes join across a junction of `arms` (as footprints takes them):
## [{"from": [arm, lane] arriving, "to": [arm, lane] leaving, "curve"}], by
## M7's turn rules. A turn joins every lane leaving by its road; straight on
## joins the lane in line with it, so the curve leaves and arrives straight.
static func connections(arms: Array[Dictionary], rules: Dictionary) -> Array[Dictionary]:
	var shape := shape(footprints(arms), rules)
	assert(not shape.has("error"), "a junction's arms part by its minimum angle")
	var trims: Array = shape.trims
	var found: Array[Dictionary] = []
	for i in arms.size():
		var heading: Vector2 = -arms[i].direction
		var inbound := _lanes(arms[i], false)
		# From the driver's left to right: the lane nearest the middle first.
		inbound.sort_custom(func(a: int, b: int) -> bool: return RoadCurve.lanes(arms[i].road)[a].offset > RoadCurve.lanes(arms[i].road)[b].offset)
		var kinds := {}
		for j in arms.size():
			kinds[_kind(heading, arms, i, j)] = true
		for n in inbound.size():
			var lane: int = inbound[n]
			var start := lane_point(arms[i], lane, trims[i])
			for j in arms.size():
				var kind := _kind(heading, arms, i, j)
				if not _may(kind, n, inbound.size() - 1, kinds):
					continue
				var outbound := _lanes(arms[j], true)
				if kind == "straight":
					outbound.sort_custom(func(a: int, b: int) -> bool: return lane_point(arms[j], a, trims[j]).distance_to(start + heading * (trims[i] + trims[j])) < lane_point(arms[j], b, trims[j]).distance_to(start + heading * (trims[i] + trims[j])))
					outbound = [outbound[0]]
				for out: int in outbound:
					var end := lane_point(arms[j], out, trims[j])
					found.append({"from": [i, lane], "to": [j, out], "curve": RoadCurve.new(start, _control(start, heading, end, arms[j].direction), end)})
	return found


## The lanes of `arm` leaving the node (`outbound`) or coming in to it.
static func _lanes(arm: Dictionary, outbound: bool) -> Array:
	var lanes := RoadCurve.lanes(arm.road)
	return range(lanes.size()).filter(func(k: int) -> bool: return lanes[k].forward == outbound)


## Which way a vehicle heading `heading` in on arm `from` goes out on arm
## `to`: "back", or "straight", "left" or "right" by the angle, as M7's.
static func _kind(heading: Vector2, arms: Array[Dictionary], from: int, to: int) -> String:
	if from == to:
		return "back"
	var angle := heading.angle_to(arms[to].direction)
	if absf(angle) < PI / 3.0:
		return "straight"
	# y grows south, so a negative angle turns to the driver's left.
	return "left" if angle < 0.0 else "right"


## M7's turn rules for lane `n` of `last` + 1 coming in, left to right: with
## one lane, any turn; else the leftmost turns left or back, the rightmost
## right, and straight on is for the lanes between, both of two lanes, and
## an outer lane when no road turns its way. `kinds` are the turns there are.
static func _may(kind: String, n: int, last: int, kinds: Dictionary) -> bool:
	if last == 0:
		return true
	match kind:
		"left", "back":
			return n == 0
		"right":
			return n == last
	return (n > 0 and n < last) or last == 1 or (n == 0 and "left" not in kinds) or (n == last and "right" not in kinds)


## A connection's control point: where the arriving lane's line, on from
## `start` along `heading`, meets the leaving lane's line back from `end`
## against `away`; the midpoint where they run parallel or meet behind.
static func _control(start: Vector2, heading: Vector2, end: Vector2, away: Vector2) -> Vector2:
	var middle := (start + end) / 2.0
	var denominator := heading.cross(away)
	if absf(denominator) < 0.000001:
		return middle
	var along := (end - start).cross(away) / denominator
	var back := -(end - start).cross(heading) / denominator
	return start + heading * along if along > 0.0 and back > 0.0 else middle
