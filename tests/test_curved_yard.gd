extends SceneTree
## M10 step 7: stacks, slots and machines on curved areas. A yard block's
## bays follow its own rows wherever it bends, and machines travel along
## them, so a block bent at its middle works a ship as a straight one does,
## and a box is drawn at its stack's cell wherever that cell has bent to.
## godot --headless --script res://tests/test_curved_yard.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_a_bent_block_works_a_ship()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The working terminal's import block, straight and bent 1.5 cells out at
## its middle (its ends stay beside the road, for its way in and out): each
## stacks all 12 of the ship's imports, and a stacked box is drawn where its
## stack's cell is.
func _test_a_bent_block_works_a_ship() -> void:
	var stacked := []
	var middles := []
	for bent: bool in [false, true]:
		var sim := AreaPort.working_terminal(12, 0)
		var block := 3
		if bent:
			# A curve of the block's own stretch, its control pushed out from the road.
			var area: Dictionary = sim.areas.list[block]
			var road := sim.areas.curve(block)
			var a: Vector2 = road.point_at(area.from)
			var b: Vector2 = road.point_at(area.from + area.columns)
			area.curve = [a, (a + b) / 2.0 + (b - a).normalized().orthogonal() * -area.side * 3.0, b]
			area.from = 0.0
			sim.areas.version += 1
		middles.append(sim.areas.centre(Vector3i(block, 15, 4)))
		for i in 20000:
			sim.tick()
			if AreaFlow._stacks(sim, block).count() == 12:
				break
		stacked.append(AreaFlow._stacks(sim, block).count())
		var stacks: AreaStacks = AreaFlow._stacks(sim, block)
		var box: int = stacks.boxes()[0] if not stacks.boxes().is_empty() else 0
		if box:
			var cell: Vector3i = sim.areas.layout(block).stacks[stacks.position_of(box)].cells[1]
			_expect(AreaFlow.box_cell(sim, box).distance_to(sim.areas.centre(cell) - Vector2(0.5, 0.5)) < 0.01, true, "%s, a stacked box is drawn at its stack's cell" % ("bent" if bent else "straight"))
	_expect(middles[0].distance_to(middles[1]) > 1.0, true, "bent, the block's middle has moved (%.1f cells)" % middles[0].distance_to(middles[1]))
	_expect(stacked, [12, 12], "straight or bent, the block stacks all 12 imports")
