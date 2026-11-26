extends SceneTree
## The showcase port (bench/showcase_port.gd), the debug menu's port with one
## of nearly everything: it builds with no command refused and its ships work.
## godot --headless --script res://tests/test_showcase.gd

const Showcase := preload("res://bench/showcase_port.gd")

var _failures := 0


func _initialize() -> void:
	var refused: Array[String] = []
	var sim := Showcase.build(refused)
	_expect(refused, [] as Array[String], "every command builds")
	_expect(sim.policies.keys().size(), Showcase.POLICIES.size(), "its policies are on")
	_expect(sim.templates.keys(), ["By departure"], "a template is saved")
	_expect(sim.areas.terminals.values().map(func(t: Dictionary) -> String: return t.name), ["North Terminal", "South Terminal"], "two terminals")
	# M11's AGVs: the North Terminal works its quay with AGVs to transfer blocks.
	var transfer := sim.areas.list.keys().filter(func(id: int) -> bool: return sim.areas.list[id].type == "transfer_block")
	_expect(transfer.size(), 2 * Showcase.AGV_BLOCKS.size() + 1, "the North Terminal's transfer blocks")
	_expect(transfer.filter(func(id: int) -> bool: return AreaFlow.agv_unreachable(sim, id)), [], "AGVs reach every one from the quay")
	_expect(AreaFlow.agv_depots(sim, 1).size(), 1, "from one AGV depot")
	# A start past the week's end never falls due, so that service would never call.
	_expect(sim.contracts.services.filter(func(s: Dictionary) -> bool: return s.start >= Contracts.MINUTES_PER_WEEK).map(func(s: Dictionary) -> String: return s.kind), [], "every weekly service starts inside the week")
	# Each terminal starts with exports for its own ships due, not the port's in one of them.
	_expect(sim.areas.terminals.keys().filter(func(t: int) -> bool: return AreaFlow._exports_at(sim).get(t, 0) == 0), [], "each terminal holds exports for its own ships")
	var agvs := 0
	var waited := 0
	for i: int in roundi(120.0 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		agvs = maxi(agvs, sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "agv").size())
		waited = maxi(waited, sim.vehicles.filter(func(v: Vehicle) -> bool: return v.state == "waiting").size())
	_expect(sim.ledger.moves.total > 0, true, "its ships are worked in the first two hours")
	_expect(agvs > 0, true, "AGVs work the North Terminal's ship (%d at most)" % agvs)
	# A tractor whose crane's slot is taken waits in a free apron slot, off the through lane.
	_expect(waited > 0, true, "tractors wait in free apron slots for a busy crane (%d at most)" % waited)
	_expect(sim.vehicles.filter(func(v: Vehicle) -> bool: return v.state.begins_with("no_route")).size(), 0, "no vehicle is left without a route")
	# With tides off every ship's channel is deep enough for it: none waits for high water.
	_expect(sim.events.filter(func(e: Dictionary) -> bool: return "high water" in e.text).map(func(e: Dictionary) -> String: return e.text), [], "no ship waits for high water with tides off")
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])
