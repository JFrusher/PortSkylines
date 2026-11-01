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
