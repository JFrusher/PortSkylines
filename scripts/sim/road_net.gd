class_name RoadNet
extends RefCounted
## The roads the player draws: nodes on the 4 m grid joined by straight
## segments at 0°, 45° or 90°. Corners are drawn as arcs by the view; in the
## sim a road is the cells along its segments.

## Node id -> its cell.
var nodes := {}
## Segment id -> {"a": node id, "b": node id, "type": a key of road_types}.
var segments := {}
## The data's road types: lanes each way, whether lorries may use them, costs.
var types: Dictionary
var _next_node := 1
var _next_segment := 1


func _init(road_types: Dictionary) -> void:
	types = road_types


## Adds a straight road of `type` from `from` to `to`, reusing a node already
## at either end. Its forward lanes run from `from` to `to` on the drawn line
## and to its right; backward lanes lie to its left. Returns "" or why it
## can't be built.
func add(from: Vector2i, to: Vector2i, type: String) -> String:
	if type not in types:
		return "Unknown road type \"%s\"" % type
	var d := to - from
	if d == Vector2i.ZERO:
		return "A road needs a length"
	if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
		return "Roads run straight or at 45°"
	segments[_next_segment] = {"a": _node_at(from), "b": _node_at(to), "type": type}
	_next_segment += 1
	return ""


## The cells along `segment`, from its a end to its b end.
func cells(segment: int) -> Array[Vector2i]:
	return line(nodes[segments[segment].a], nodes[segments[segment].b])


## `segment`'s lanes from left to right across its drawn direction, each
## {"cells": in driving order, "forward": true if it runs from a to b}.
func lanes(segment: int) -> Array[Dictionary]:
	var road: Dictionary = types[segments[segment].type]
	var a: Vector2i = nodes[segments[segment].a]
	var b: Vector2i = nodes[segments[segment].b]
	var across := right_of(b - a)
	var found: Array[Dictionary] = []
	for i: int in road.backward + road.forward:
		var offset: Vector2i = across * (i - road.backward)
		var forward: bool = i >= road.backward
		found.append({"cells": line(a + offset, b + offset) if forward else line(b + offset, a + offset), "forward": forward})
	return found


## One cell to the right of travel along `d`. On a 45° road that is a step
## straight across, so neighbouring lanes touch with no gap row between them.
static func right_of(d: Vector2i) -> Vector2i:
	var step := d.sign()
	if step.x == 0 or step.y == 0:
		return Vector2i(-step.y, step.x)
	return Vector2i(0, step.x)


## The cells from `from` to `to` inclusive, along a straight or 45° line.
static func line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var d := to - from
	var step := d.sign()
	var found: Array[Vector2i] = []
	for i in maxi(absi(d.x), absi(d.y)) + 1:
		found.append(from + step * i)
	return found


func _node_at(cell: Vector2i) -> int:
	for id: int in nodes:
		if nodes[id] == cell:
			return id
	nodes[_next_node] = cell
	_next_node += 1
	return _next_node - 1
