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


## A quay apron, from its road to the water: row 0 the buffer strip, row 1 the
## landside crane rail, the rows up to the waterside rail tractor lanes under
## the cranes, cut into a handover slot per bay, and the last row the quay
## edge. {"buffer", "rails": [landside, waterside], "slots", "edge"}.
static func quay_apron(area: Dictionary, depth: int) -> Dictionary:
	var length := _length(area)
	var layout := {
		"buffer": _row(area, 0, 0, length),
		"rails": [_row(area, 1, 0, length), _row(area, depth - 2, 0, length)],
		"slots": [],
		"edge": _row(area, depth - 1, 0, length),
	}
	for bay in length / BAY:
		for row in range(2, depth - 2):
			layout.slots.append(_row(area, row, bay * BAY, BAY))
	return layout


## A gate: row 0 the buffer strip, then lanes running along the road with a
## booth slot at each lane's middle bay, where lorries stop to be checked,
## and the last row a kerb. {"buffer", "lanes", "slots", "kerb"}.
static func gate(area: Dictionary, depth: int) -> Dictionary:
	var length := _length(area)
	var middle := (length / BAY / 2) * BAY
	var layout := {"buffer": _row(area, 0, 0, length), "lanes": [], "slots": [], "kerb": _row(area, depth - 1, 0, length)}
	for row in range(1, depth - 1):
		layout.lanes.append(_row(area, row, 0, length))
		layout.slots.append(_row(area, row, middle, BAY))
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
