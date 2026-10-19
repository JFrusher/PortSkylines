class_name AreaLayout
extends RefCounted
## What an area holds, laid out from its type and size alone: the player
## sets rules, never places parts. Rows run parallel to the area's road,
## numbered from the road back; positions along it come in bays of BAY cells,
## the length of one 40 ft box or two 20 ft boxes.

## A 40 ft box is 12.2 m: three 4 m cells.
const BAY := 3


## An RTG yard block: row 0 is the buffer strip where vehicles wait, row 1 the
## truck lane, cut into one handover slot per bay, and every row behind it a
## row of stacks, one per bay. {"buffer": cells, "slots": [cells per slot],
## "stacks": [{"row", "bay", "cells"}]}.
static func yard_block(area: Dictionary, depth: int) -> Dictionary:
	var length := _length(area)
	var bays := length / BAY
	var layout := {"buffer": _row(area, 0, 0, length), "slots": [], "stacks": []}
	for bay in bays:
		layout.slots.append(_row(area, 1, bay * BAY, BAY))
		for row in range(2, depth):
			layout.stacks.append({"row": row - 2, "bay": bay, "cells": _row(area, row, bay * BAY, BAY)})
	return layout


## How many cells long `area` is along its road.
static func _length(area: Dictionary) -> int:
	return RoadNet.length(area.start, area.end) + 1


## `count` cells of row `row` from `from` cells along `area`.
static func _row(area: Dictionary, row: int, from: int, count: int) -> Array[Vector2i]:
	var step: Vector2i = (area.end - area.start).sign()
	var found: Array[Vector2i] = []
	for i in range(from, from + count):
		found.append(area.start + step * i + area.out * row)
	return found
