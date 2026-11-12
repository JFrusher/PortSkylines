extends SceneTree
## M10 step 6c-2a: what an area holds, laid out on its own cells: (k, r) is
## column k along the road and row r out from it. Handover slots are two bays
## (24 m) long, so a 16.5 m lorry fits one, with a last odd bay's stacks
## served from the slot beside them; a gate's booths are two bays centred on
## the gate, cut to its length. On a bend, a part any of whose cells the
## shape left out isn't laid out.
## godot --headless --script res://tests/test_area_layout.gd

var _failures := 0


func _initialize() -> void:
	_test_a_yard_block()
	_test_an_odd_bay_is_served_from_the_slot_beside_it()
	_test_a_quay_apron()
	_test_gates()
	_test_a_truck_park()
	_test_missing_cells_drop_their_parts()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Every cell of a `columns` by `depth` area.
func _all(columns: int, depth: int) -> Dictionary:
	var present := {}
	for k in columns:
		for r in depth:
			present[Vector2i(k, r)] = true
	return present


## The cells of row `r` from column `from`, `count` of them.
func _row(r: int, from: int, count: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for k in range(from, from + count):
		found.append(Vector2i(k, r))
	return found


## 30 columns, 8 rows: row 0 the buffer, row 1 five slots of two bays each,
## rows 2 to 7 a stack per bay, each served by the slot beside it.
func _test_a_yard_block() -> void:
	var layout := AreaLayout.local("yard_block", 30, 8, _all(30, 8))
	_expect(layout.buffer, _row(0, 0, 30), "the buffer strip is row 0, all along")
	_expect(layout.slots.size(), 5, "a slot every two bays")
	_expect(layout.slots[1], _row(1, 6, 6), "each two bays (6 cells) of row 1")
	_expect(layout.stacks.size(), 10 * 6, "a stack per bay in each of rows 2 to 7")
	var stack: Dictionary = layout.stacks.filter(func(s: Dictionary) -> bool: return s.row == 3 and s.bay == 5)[0]
	_expect(stack.cells, _row(5, 15, 3), "stack row 3 of bay 5 is row 5's cells 15 to 17")
	_expect(stack.slot, 2, "and is served from slot 2, beside bays 4 and 5")


## 33 columns are 11 bays: five slots, and bay 10's stacks are served from
## slot 4, beside bays 8 and 9.
func _test_an_odd_bay_is_served_from_the_slot_beside_it() -> void:
	var layout := AreaLayout.local("yard_block", 33, 8, _all(33, 8))
	_expect(layout.slots.size(), 5, "five slots for eleven bays")
	_expect(layout.stacks.filter(func(s: Dictionary) -> bool: return s.bay == 10).all(func(s: Dictionary) -> bool: return s.slot == 4), true, "the last bay's stacks go to the last slot")


## A quay apron 24 columns by 10 rows: buffer, landside rail, through lane,
## four slots under the cranes, hatch covers, waterside rail, quay edge.
func _test_a_quay_apron() -> void:
	var layout := AreaLayout.local("quay_apron", 24, 10, _all(24, 10))
	_expect(layout.buffer, _row(0, 0, 24), "the buffer strip is row 0")
	_expect(layout.rails, [_row(1, 0, 24), _row(8, 0, 24)], "the crane rails are rows 1 and 8")
	_expect(layout.lanes, [_row(2, 0, 24)], "the through lane is row 2")
	_expect(layout.slots, [_row(3, 0, 6), _row(3, 6, 6), _row(3, 12, 6), _row(3, 18, 6)], "row 3 is cut into two-bay slots")
	_expect(layout.hatches.size(), 24 * 4, "rows 4 to 7 are for hatch covers")
	_expect(layout.edge, _row(9, 0, 24), "and row 9 is the quay edge")


## A gate's lanes each have a booth two bays long centred on the gate; on a
## 5-cell gate the booth is the gate's whole length.
func _test_gates() -> void:
	var long := AreaLayout.local("gate", 12, 6, _all(12, 6))
	_expect(long.lanes.size(), 4, "a 6-row gate has lanes in rows 1 to 4")
	_expect(long.slots[0], _row(1, 3, 6), "each booth two bays long, centred on the gate")
	_expect(long.kerb, _row(5, 0, 12), "and row 5 is the kerb")
	var short := AreaLayout.local("gate", 5, 6, _all(5, 6))
	_expect(short.slots[2], _row(3, 0, 5), "a 5-cell gate's booth is the gate's whole length")


func _test_a_truck_park() -> void:
	var layout := AreaLayout.local("parking", 14, 2, _all(14, 2))
	_expect(layout.slots, [_row(1, 0, 6), _row(1, 6, 6)], "a parking slot every two bays; the cells past the last are left over")


## Round a bend the shape left out bay 0's cell (1, 2) and (8, 1): the stack
## on that cell and the slot on the other aren't laid out; the rest are.
func _test_missing_cells_drop_their_parts() -> void:
	var present := _all(30, 8)
	present.erase(Vector2i(1, 2))
	present.erase(Vector2i(8, 1))
	var layout := AreaLayout.local("yard_block", 30, 8, present)
	_expect(layout.slots.size(), 4, "the slot with a missing cell isn't laid out")
	_expect(layout.slots.has(_row(1, 6, 6)), false, "that is slot 1, cells 6 to 11")
	_expect(layout.stacks.size(), 59, "nor is the stack with a missing cell")
	_expect(layout.stacks.any(func(s: Dictionary) -> bool: return s.bay == 0 and s.row == 0), false, "that is bay 0's first stack row")
	_expect(layout.buffer.size(), 30, "the buffer strip stays whole")
