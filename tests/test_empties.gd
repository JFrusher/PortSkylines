extends SceneTree
## Empties: blocks that hold them, their return by lorry, exporters taking
## them out, and lines shipping the surplus (M6 steps E1-E4).

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_empty_blocks()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## Empty handlers work only blocks set to the empty role, and stack their
## data's tiers.
func _test_empty_blocks() -> void:
	var sim := AreaPort.base(RandomPort.quick(), "")
	var block := 3
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"gear": "empty_handler"}}), "Empty handlers only work empty blocks", "an import block can't take empty handlers")
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"role": "empty", "gear": "empty_handler"}}), "", "an empty block can")
	_expect(sim.apply({"op": "set_area", "id": block, "settings": {"role": "import"}}), "Empty handlers only work empty blocks", "and can't be made an import block while they work it")
	sim.tick()
	_expect(AreaFlow._stacks(sim, block).to_dict().tiers, sim.rules.yard_gear.empty_handler.tiers, "its stacks go the handlers' tiers high")
