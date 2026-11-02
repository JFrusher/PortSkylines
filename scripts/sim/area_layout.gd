class_name AreaLayout
extends RefCounted
## What an area holds, laid out from its type and size alone: the player
## sets rules, never places parts. Rows run parallel to the area's road,
## numbered from the road back; positions along it come in bays of BAY cells,
## the length of one 40 ft box or two 20 ft boxes.

## A 40 ft box is 12.2 m: three 4 m cells.
const BAY := 3
## A handover slot is two bays (24 m) long, so a 16.5 m lorry fits one.
const SLOT := 2 * BAY


## What an area of `kind` holds, laid out on its own cells: Vector2i(k, r)
## is column k along its road and row r out from it, `columns` by `depth`,
## of which only the cells in `present` (its shape's) exist. A part any of
## whose cells is missing isn't laid out; the buffer and lane rows keep the
## cells they have, as vehicles drive them as lanes. Each stack names the
## slot that serves it, the nearest to its bay. The same keys as the grid
## layouts below, which the switch (M10 6c-2c) replaces with these.
static func local(kind: String, columns: int, depth: int, present: Dictionary) -> Dictionary:
	var row := func(r: int, from: int, count: int) -> Array[Vector2i]:
		var found: Array[Vector2i] = []
		for k in range(from, mini(from + count, columns)):
			found.append(Vector2i(k, r))
		return found
	var whole := func(cells: Array[Vector2i]) -> bool: return cells.all(func(cell: Vector2i) -> bool: return cell in present)
	var kept := func(cells: Array[Vector2i]) -> Array[Vector2i]: return cells.filter(func(cell: Vector2i) -> bool: return cell in present)
	var slots_in := func(r: int) -> Array:
		var found := []
		for n in columns / BAY / 2:
			var cells: Array[Vector2i] = row.call(r, n * SLOT, SLOT)
			if whole.call(cells):
				found.append(cells)
		return found
	match kind:
		"yard_block":
			var layout := {"buffer": kept.call(row.call(0, 0, columns)), "slots": slots_in.call(1), "stacks": []}
			for bay in columns / BAY:
				for r in range(2, depth):
					var cells: Array[Vector2i] = row.call(r, bay * BAY, BAY)
					if whole.call(cells):
						layout.stacks.append({"row": r - 2, "bay": bay, "cells": cells, "slot": _nearest_slot(layout.slots, bay)})
			return layout
		"quay_apron":
			var hatches: Array[Vector2i] = []
			for r in range(4, depth - 2):
				hatches.append_array(kept.call(row.call(r, 0, columns)))
			return {"buffer": kept.call(row.call(0, 0, columns)), "rails": [kept.call(row.call(1, 0, columns)), kept.call(row.call(depth - 2, 0, columns))], "lanes": [kept.call(row.call(2, 0, columns))], "slots": slots_in.call(3), "hatches": hatches, "edge": kept.call(row.call(depth - 1, 0, columns))}
		"gate":
			var layout := {"buffer": kept.call(row.call(0, 0, columns)), "lanes": [], "slots": [], "kerb": kept.call(row.call(depth - 1, 0, columns))}
			var from := maxi(0, (columns - SLOT) / 2)
			for r in range(1, depth - 1):
				layout.lanes.append(kept.call(row.call(r, 0, columns)))
				var booth: Array[Vector2i] = row.call(r, from, SLOT)
				if whole.call(booth):
					layout.slots.append(booth)
			return layout
		"parking":
			return {"buffer": kept.call(row.call(0, 0, columns)), "slots": slots_in.call(1)}
	return {}


## The index in `slots` of the one whose middle is nearest bay `bay`'s, or -1.
static func _nearest_slot(slots: Array, bay: int) -> int:
	var best := -1
	var middle := bay * BAY + BAY / 2.0
	for i in slots.size():
		var cells: Array = slots[i]
		var centre: float = (cells[0].x + cells[-1].x) / 2.0
		if best < 0 or absf(centre - middle) < absf((slots[best][0].x + slots[best][-1].x) / 2.0 - middle):
			best = i
	return best


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
## landside crane rail, row 2 the tractors' through lane, row 3 the working
## lane under the cranes cut into a handover slot per bay, the rows up to the
## waterside rail where hatch covers are laid, and the last row the quay edge.
## {"buffer", "rails": [landside, waterside], "lanes": [through], "slots",
## "hatches", "edge"}.
static func quay_apron(area: Dictionary, depth: int) -> Dictionary:
	var length := _length(area)
	var layout := {
		"buffer": _row(area, 0, 0, length),
		"rails": [_row(area, 1, 0, length), _row(area, depth - 2, 0, length)],
		"lanes": [_row(area, 2, 0, length)],
		"slots": [],
		"hatches": [],
		"edge": _row(area, depth - 1, 0, length),
	}
	for bay in length / BAY:
		layout.slots.append(_row(area, 3, bay * BAY, BAY))
	for row in range(4, depth - 2):
		layout.hatches.append_array(_row(area, row, 0, length))
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


## A truck park: row 0 the buffer strip, row 1 a parking slot per bay,
## entered and left sideways from the buffer as a yard block's slots are.
## {"buffer", "slots"}.
# shortcut: one row of slots, so a park's room grows only with its length; add rows when parks need to be compact.
static func parking(area: Dictionary) -> Dictionary:
	var length := _length(area)
	var layout := {"buffer": _row(area, 0, 0, length), "slots": []}
	for bay in length / BAY:
		layout.slots.append(_row(area, 1, bay * BAY, BAY))
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
