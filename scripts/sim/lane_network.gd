class_name LaneNetwork
extends RefCounted
## The lanes vehicles drive, built from a RoadNet's curves: each lane is a
## piece along its road's curve, cut back where a junction's shape needs
## room; connection pieces join the lanes across a junction under M7's turn
## rules, each lane on round a bend, and each lane back into the other way at
## a dead end. Routes run over pieces.

## Piece id -> {"points": PackedVector2Array in grid units, in driving order;
## "length": cells; "segment": its road, or 0 for a connection; "lane": its
## lane's index across the road, or -1; "next": the piece ids it leads into;
## "lorries": whether lorries may use it; "node": the node a connection
## crosses, or 0}.
var pieces := {}
var _next_id := 1
## Roads within this many degrees of straight on carry on through a node of
## two with no junction between them.
const STRAIGHT_ON := 10.0


func _init(net: RoadNet, rules: Dictionary) -> void:
	var arms_at := _arms(net)
	var trims := _trims(arms_at, rules)
	var lane_pieces := {}  # [segment, lane] -> piece id
	for segment: int in net.segments:
		var curve := net.curve(segment)
		var road: Dictionary = net.types[net.segments[segment].type]
		var start: float = trims[[segment, "a"]]
		var stop: float = curve.length - trims[[segment, "b"]]
		var lanes := RoadCurve.lanes(road)
		for k in lanes.size():
			var points := _along(curve, lanes[k].offset, start, stop)
			if not lanes[k].forward:
				points.reverse()
			lane_pieces[[segment, k]] = _add(points, segment, k, road.lorries, 0)
	for node: int in arms_at:
		var arms: Array[Dictionary] = arms_at[node]
		var pairs: Array = []
		if arms.size() == 1:
			pairs = _turn_back(arms[0])
		elif arms.size() == 2:
			pairs = _carry_on(arms)
		else:
			for link: Dictionary in RoadJunction.connections(arms, rules):
				pairs.append([link.from, link.to])
		for pair: Array in pairs:
			var into: Dictionary = arms[pair[0][0]]
			var out: Dictionary = arms[pair[1][0]]
			_join(lane_pieces[[into.segment, _segment_lane(into, pair[0][1])]], lane_pieces[[out.segment, _segment_lane(out, pair[1][1])]], node, arms.size() == 1)


## The pieces along a route from piece `from` to piece `to`, both included,
## shortest by length; [] when there is none.
func route(from: int, to: int) -> Array[int]:
	var cost := {from: 0.0}
	var came := {}
	var heap: Array = [[0.0, from]]
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var at: int = top[1]
		if at == to:
			var found: Array[int] = [to]
			while found[0] != from:
				found.push_front(came[found[0]])
			return found
		if top[0] > cost[at]:
			continue
		for next: int in pieces[at].next:
			var through: float = cost[at] + pieces[next].length
			if through < cost.get(next, INF):
				cost[next] = through
				came[next] = at
				_push(heap, [through, next])
	return []


## How long a route of pieces is, in cells.
func length(route: Array[int]) -> float:
	var total := 0.0
	for id in route:
		total += pieces[id].length
	return total


## Each node's arms: {"segment", "end": "a" or "b", "direction": unit vector
## away from the node, "road": its type as drawn away from the node}.
static func _arms(net: RoadNet) -> Dictionary:
	var found := {}
	for segment: int in net.segments:
		var road: Dictionary = net.segments[segment]
		var curve := net.curve(segment)
		var type: Dictionary = net.types[road.type]
		found.get_or_add(road.a, [] as Array[Dictionary]).append({"segment": segment, "end": "a", "direction": curve.direction_at(0.0), "road": type})
		var flipped := type.duplicate()
		flipped.forward = type.backward
		flipped.backward = type.forward
		found.get_or_add(road.b, [] as Array[Dictionary]).append({"segment": segment, "end": "b", "direction": -curve.direction_at(curve.length), "road": flipped})
	return found


## How far each road end is cut back from its node: [segment, end] -> cells.
## A junction of three or more, or a bend, is shaped; a road carrying straight
## on or ending is not cut back.
static func _trims(arms_at: Dictionary, rules: Dictionary) -> Dictionary:
	var found := {}
	for node: int in arms_at:
		var arms: Array[Dictionary] = arms_at[node]
		var trims: Array = []
		trims.resize(arms.size())
		trims.fill(0.0)
		var straight: bool = arms.size() == 2 and absf(arms[0].direction.angle_to(arms[1].direction)) >= deg_to_rad(180.0 - STRAIGHT_ON)
		if arms.size() >= 2 and not straight:
			var shape := RoadJunction.shape(RoadJunction.footprints(arms), rules)
			assert(not shape.has("error"), "roads at node %d part by the junctions' minimum angle" % node)
			trims = shape.trims
		for i in arms.size():
			found[[arms[i].segment, arms[i].end]] = trims[i]
	return found


## Which segment lane is arm lane `k` of `arm`: the same at a road's a end;
## mirrored across the road at its b end, which looks back along it.
static func _segment_lane(arm: Dictionary, k: int) -> int:
	return k if arm.end == "a" else arm.road.forward + arm.road.backward - 1 - k


## At a dead end, every lane coming in turns back into every lane going out.
static func _turn_back(arm: Dictionary) -> Array:
	var lanes := RoadCurve.lanes(arm.road)
	var pairs: Array = []
	for i in lanes.size():
		for j in lanes.size():
			if not lanes[i].forward and lanes[j].forward:
				pairs.append([[0, i], [0, j]])
	return pairs


## Round a bend of two roads, each lane coming in carries on into the lane
## going out that is as far from the middle: left to right, in order.
static func _carry_on(arms: Array[Dictionary]) -> Array:
	var pairs: Array = []
	for i in 2:
		var lanes := RoadCurve.lanes(arms[i].road)
		var out := RoadCurve.lanes(arms[1 - i].road)
		# Coming in, the lane nearest the middle is the driver's left; going out, likewise.
		var inbound := range(lanes.size()).filter(func(k: int) -> bool: return not lanes[k].forward)
		inbound.sort_custom(func(a: int, b: int) -> bool: return lanes[a].offset > lanes[b].offset)
		var outbound := range(out.size()).filter(func(k: int) -> bool: return out[k].forward)
		outbound.sort_custom(func(a: int, b: int) -> bool: return out[a].offset < out[b].offset)
		for n in mini(inbound.size(), outbound.size()):
			pairs.append([[i, inbound[n]], [1 - i, outbound[n]]])
	return pairs


## Joins piece `into` to piece `out` across node `node`: straight on where
## they meet, else along a connection curve from one's end to the other's
## start, its control point where their lines cross (beyond the road's end
## for a turn back at a dead end).
func _join(into: int, out: int, node: int, dead_end: bool) -> void:
	var start: Vector2 = pieces[into].points[-1]
	var end: Vector2 = pieces[out].points[0]
	if start.distance_to(end) < 0.001:
		pieces[into].next.append(out)
		return
	var heading := _direction(pieces[into].points, true)
	var away := _direction(pieces[out].points, false)
	var control := (start + end) / 2.0 + heading * start.distance_to(end) if dead_end else RoadJunction._control(start, heading, end, away)
	var curve := RoadCurve.new(start, control, end)
	var id := _add(_along(curve, 0.0, 0.0, curve.length), 0, -1, pieces[into].lorries and pieces[out].lorries, node)
	pieces[into].next.append(id)
	pieces[id].next.append(out)


func _add(points: PackedVector2Array, segment: int, lane: int, lorries: bool, node: int) -> int:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	pieces[_next_id] = {"points": points, "length": total, "segment": segment, "lane": lane, "next": [] as Array[int], "lorries": lorries, "node": node}
	_next_id += 1
	return _next_id - 1


## Points along `curve` offset `offset` cells right, from `start` to `stop`
## cells along it, about every half cell and at both ends.
static func _along(curve: RoadCurve, offset: float, start: float, stop: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := maxi(1, ceili((stop - start) / 0.5))
	for i in count + 1:
		var d := lerpf(start, stop, float(i) / count)
		points.append(curve.point_at(d) + curve.right_at(d) * offset)
	return points


## The way a piece's points head at their end (`at_end`) or start.
static func _direction(points: PackedVector2Array, at_end: bool) -> Vector2:
	return (points[-1] - points[-2]).normalized() if at_end else (points[1] - points[0]).normalized()


## A binary heap of [cost, piece] on an array, cheapest first.
static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0 and heap[(i - 1) / 2][0] > heap[i][0]:
		var parent := (i - 1) / 2
		var swap: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var smallest := i
		for child: int in [2 * i + 1, 2 * i + 2]:
			if child < heap.size() and heap[child][0] < heap[smallest][0]:
				smallest = child
		if smallest == i:
			return top
		var swap: Array = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = swap
		i = smallest
	return top
