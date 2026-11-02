extends SceneTree
## M10 steps 6b and 6d: areas and roads block each other by overlapping shapes, not
## shared grid cells: an area's cells are quads along its curve, and two
## things block each other where those overlap with any area; edges that
## only touch don't count. Grid layouts are refused as before (test_roads'
## and test_rules' refusals); a bent area blocks where it has bent to. The
## ground an area stands on (for water, land, paint and upkeep) is the grid
## cells its own cells' middles lie in.
## godot --headless --script res://tests/test_area_overlap.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_touching_is_fine()
	_test_a_bent_area_blocks_where_it_bends()
	_test_roads_and_track_keep_off_a_bent_area()
	_test_cells_follow_the_shape()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Two 1+1 roads east along y = 100 and y = 118: a block south of the first
## (rows 101 to 108) and one north of the second (rows 109 to 116) meet back
## to back, and a third runs on from the first's end.
func _port() -> PortSim:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.strait(), true))
	for y: int in [100, 118]:
		_expect(sim.apply({"op": "build_road", "from": Vector2i(100, y), "to": Vector2i(160, y), "type": "terminal_1_1"}), "", "a road along y = %d" % y)
	return sim


func _block(sim: PortSim, y: int, side: int, from: int, to: int) -> String:
	return sim.apply({"op": "build_area", "type": "yard_block", "segment": sim.roads.segment_at(Vector2i(130, y)), "side": side, "from": from, "to": to})


func _test_touching_is_fine() -> void:
	var sim := _port()
	_expect(_block(sim, 100, 1, 10, 29), "", "a block south of the first road")
	_expect(_block(sim, 118, -1, 10, 29), "", "and one back to back with it north of the second: their edges only touch")
	_expect(_block(sim, 100, 1, 30, 49), "", "and one running on from the first's end")


## The first block's road curve bent 3 cells south at its middle: its cells
## sweep into the second's place, which is refused, but a block further
## east, clear of the bend, is still built.
func _test_a_bent_area_blocks_where_it_bends() -> void:
	var sim := _port()
	_expect(_block(sim, 100, 1, 10, 29), "", "a block south of the first road")
	_bend(sim, 1, 3.0)
	_expect(_block(sim, 118, -1, 10, 29), "Something is already built here", "the bent block is in the way of one back to back with it")
	_expect(_block(sim, 118, -1, 40, 59), "", "one clear of the bend is built")


## A road or track laid across the bent block's cells is refused.
func _test_roads_and_track_keep_off_a_bent_area() -> void:
	var sim := _port()
	_expect(_block(sim, 100, 1, 10, 29), "", "a block south of the first road")
	_bend(sim, 1, 3.0)
	var middle := sim.areas.centre(Vector3i(1, 10, 7))
	_expect(sim.areas.area_over(_square(Vector2i(middle.floor()))), 1, "the bent block's far row covers grid cell %s" % Vector2i(middle.floor()))
	_expect(sim.build_road_error(Vector2i(110, int(middle.y)), Vector2i(150, int(middle.y)), "terminal_1_1"), "Something is already built here", "a road across its bent rows is refused")


## Bends area `id`'s road curve `by` cells out from its road at its middle.
func _bend(sim: PortSim, id: int, by: float) -> void:
	var area: Dictionary = sim.areas.list[id]
	var a: Vector2 = area.curve[0]
	var b: Vector2 = area.curve[2]
	var out: Vector2 = (b - a).normalized().orthogonal() * -area.side
	area.curve = [a, (a + b) / 2.0 + out * by * 2.0, b]
	sim.areas.version += 1


func _square(cell: Vector2i) -> PackedVector2Array:
	var at := Vector2(cell)
	return PackedVector2Array([at, at + Vector2(1, 0), at + Vector2(1, 1), at + Vector2(0, 1)])


## A block's ground is the grid cells under its cells' middles: on a
## straight road its rows, bent, where it has bent to.
func _test_cells_follow_the_shape() -> void:
	var sim := _port()
	_expect(_block(sim, 100, 1, 10, 29), "", "a block south of the first road")
	_expect(sim.areas.cells(1).all(func(c: Vector2i) -> bool: return c.y >= 101 and c.y <= 108), true, "straight, it stands on rows 101 to 108")
	_expect(sim.areas.cells(1).size(), 20 * 8, "one grid cell per cell of its own")
	_bend(sim, 1, 3.0)
	var under := {}
	for cell: Dictionary in sim.areas.shape(1).cells:
		under[Vector2i(cell.centre.floor())] = true
	_expect(sim.areas.cells(1).all(func(c: Vector2i) -> bool: return c in under) and under.keys().all(func(c: Vector2i) -> bool: return c in sim.areas.cells(1)), true, "bent, it stands on the grid cells under its cells' middles")
	_expect(sim.areas.cells(1).any(func(c: Vector2i) -> bool: return c.y > 108), true, "which reach where it has bent to")
	_expect(sim.areas.area_at(Vector2i(119, 111)), 1, "and picking finds it there")
