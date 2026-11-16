extends SceneTree
## Two game days of a seeded random port on roads and areas, with an RMG
## rail block whose track crosses the east road to the rail entry, and the sim's
## invariants checked as it runs: after every tick, cash moves only through the ledger
## and every closed day adds up to its change in cash (loans, land and
## dredging included); every vehicle second, stacks stay within their tiers, every box is in
## exactly one place (a stack, a vehicle or a machine's spreader), every vehicle holds the cell it is on and no two share
## one, and slots and machine jobs belong to vehicles that are there. Then half a
## game day of the showcase port, with M9's transhipment, barges and
## straddle carriers, where no lorry ever takes a box booked to go on by
## ship or barge.
## godot --headless --script res://tests/test_soak.gd

const RandomPort := preload("res://tests/random_port.gd")
const Invariants := preload("res://tests/invariants.gd")
const Showcase := preload("res://bench/showcase_port.gd")
# Two game days and a bit, so midnight closes the books twice.
const TICKS := SimClock.TICKS_PER_DAY * 2 + 1000
## Ticks between checks of every box, cell and slot, which cost more than
## the sim's own tick: one vehicle second, shorter than any state lasts.
const DEEP_EVERY := 20

var _failures := 0


func _initialize() -> void:
	var calm := _soak(RandomPort.rules())
	_expect(calm.delivered > 0, true, "the calm port delivers boxes (%d)" % calm.delivered)
	_expect(calm.by_rail > 0, true, "and sends boxes off by train (%d)" % calm.by_rail)
	# A lorry every 10 game hours: yards fill up and ships wait, which the calm
	# port never pushes hard enough to test.
	var congested_rules := RandomPort.rules()
	congested_rules.lorry_interval_minutes = 600.0
	var congested := _soak(congested_rules)
	_expect(congested.area_stacks.values().any(func(stacks: AreaStacks) -> bool: return stacks.room() <= 0), true, "the congested port fills a yard block")
	var refused: Array[String] = []
	var show := Showcase.build(refused)
	_expect(refused, [] as Array[String], "the showcase port builds")
	var tranships := 0
	var carriers := 0
	while show.clock.ticks < SimClock.TICKS_PER_DAY / 2 and _failures == 0:
		show.tick()
		_check(show)
		if show.clock.ticks % DEEP_EVERY == 0:
			tranships = maxi(tranships, show.boxes.values().filter(func(b: Dictionary) -> bool: return b.kind == "tranship").size())
			carriers = maxi(carriers, show.vehicles.filter(func(v: Vehicle) -> bool: return v.straddle).size())
	_expect(tranships > 0, true, "the showcase tranships boxes (%d at most)" % tranships)
	_expect(show.by_barge > 0, true, "and sends boxes up the river by barge (%d)" % show.by_barge)
	_expect(carriers > 0, true, "and its straddle carriers go out (%d at most)" % carriers)
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _soak(rules: Dictionary) -> PortSim:
	var sim := PortSim.new(2, rules, true)
	RandomPort.calls(sim)
	var log := RandomPort.command_log(11, TICKS, 400)
	var next := 0
	while sim.clock.ticks < TICKS and _failures == 0:
		while next < log.size() and log[next].tick == sim.clock.ticks:
			sim.apply(log[next].command)
			next += 1
		# The port is built for free, then plays for money.
		if sim.clock.ticks == 0:
			_add_rail(sim)
			sim.creative = false
		sim.tick()
		_check(sim)
	return sim


## An RMG block north of the east road, its siding track running east and
## crossing the road south to the rail entry.
func _add_rail(sim: PortSim) -> void:
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": -1, "from": 92, "to": 121}), "", "the rail block is built")
	var block: int = sim.areas.list.keys().max()
	sim.apply({"op": "set_area", "id": block, "settings": {"gear": "rmg"}})
	var area: Dictionary = sim.areas.list[block]
	var behind: Vector2i = sim.areas.cell_at(block, 0, sim.areas.depth_of(area))
	var entry := sim.site_rail_entry()
	var bend := Vector2i(entry.x - 5, behind.y)
	for leg: Array in [[behind, bend], [bend, Vector2i(bend.x, entry.y)], [Vector2i(bend.x, entry.y), entry]]:
		_expect(sim.apply({"op": "build_rail", "from": leg[0], "to": leg[1]}), "", "track to the rail entry")
	_expect(RailFlow.is_rail_block(sim, block), true, "the block is a rail block")


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _check(sim: PortSim) -> void:
	Invariants.check(sim, _expect, DEEP_EVERY)
