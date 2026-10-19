extends SceneTree
## The guided start, played by commands on the base rules: each command group
## completes the next step, in order, and the guide ends once a ship is worked.
## godot --headless --script res://tests/test_guide.gd

const ROAD := PortMap.Tile.ROAD
const GATE := PortMap.Tile.GATE
const QUAY := PortMap.Tile.QUAY
const YARD := PortMap.Tile.YARD
## Calendar days the test waits at most for an offer and then for a ship.
const DAYS := 7

var _failures := 0


func _initialize() -> void:
	var sim := PortSim.new(1)
	var row := sim.map.entry.y
	var coast := sim.map.sea_width
	var steps: Array[Array] = [
		_line(ROAD, Vector2i(coast + 1, row), Vector2i(sim.map.entry.x - 1, row)),
		[{"op": "bulldoze", "cell": Vector2i(sim.map.entry.x - 3, row)}, {"op": "build", "kind": GATE, "cell": Vector2i(sim.map.entry.x - 3, row)}],
		_line(QUAY, Vector2i(coast, row - 4), Vector2i(coast, row + 4)) + _line(ROAD, Vector2i(coast + 1, row - 4), Vector2i(coast + 1, row - 1)) + _line(ROAD, Vector2i(coast + 1, row + 1), Vector2i(coast + 1, row + 4)),
		[{"op": "place_crane", "cell": Vector2i(coast, row)}],
		[{"op": "buy_tractors", "count": 2}],
		_line(YARD, Vector2i(coast + 2, row - 3), Vector2i(coast + 4, row - 2)),
	]
	_expect(Guide.current(sim), 0, "a new game starts at the first step")
	for i in steps.size():
		for command: Dictionary in steps[i]:
			_expect(sim.apply(command), "", "step %d: %s" % [i, command])
		_expect(Guide.current(sim), i + 1, "step %d's commands finish it" % i)
	var accepted := _run_until(sim, func() -> bool:
		for offer in sim.contracts.offers:
			return sim.apply({"op": "accept_offer", "id": offer.id}) == ""
		return false)
	_expect(accepted, true, "a line offers a service and it is accepted")
	_expect(Guide.current(sim), steps.size() + 1, "accepting the offer finishes its step")
	_expect(_run_until(sim, func() -> bool: return not sim.ship_log.is_empty()), true, "the first ship is worked")
	_expect(Guide.current(sim), Guide.steps(sim).size(), "the guide ends with the first ship worked")
	_expect(sim.apply({"op": "bulldoze", "cell": Vector2i(sim.map.entry.x - 3, row)}), "", "bulldoze the gate")
	_expect(Guide.current(sim), Guide.steps(sim).size(), "a finished guide stays finished")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## Build commands for every cell of the rectangle from `a` to `b`.
func _line(kind: int, a: Vector2i, b: Vector2i) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			commands.append({"op": "build", "kind": kind, "cell": Vector2i(x, y)})
	return commands


## Ticks `sim` until `done` returns true, for at most DAYS days.
func _run_until(sim: PortSim, done: Callable) -> bool:
	for i in DAYS * SimClock.TICKS_PER_DAY:
		sim.tick()
		if i % 20 == 0 and done.call():
			return true
	return false


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
