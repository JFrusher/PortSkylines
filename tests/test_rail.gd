extends SceneTree
## M6's on-dock rail: track as a graph of its own, level crossings shared with
## the roads and booked by trains.
## godot --headless --script res://tests/test_rail.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_track_is_its_own_graph()
	_test_level_crossing()
	_test_rmg_siding()
	_test_track_is_locked()
	_test_trains_take_rail_imports()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## A road west to east along y = 100, in a creative port that owns every tile.
func _port() -> PortSim:
	var sim := AreaPort.owned(PortSim.new(0, RandomPort.quick(), true))
	_expect(sim.apply({"op": "build_road", "from": Vector2i(150, 100), "to": Vector2i(250, 100), "type": "terminal_2_2"}), "", "a road is built")
	return sim


func _test_track_is_its_own_graph() -> void:
	var sim := _port()
	var segments := sim.roads.segments.size()
	var route := sim.lanes.route(Vector2i(150, 100), Vector2i(250, 100), true)
	_expect(sim.apply({"op": "build_rail", "from": Vector2i(200, 60), "to": Vector2i(200, 140)}), "", "track is built straight across the road")
	_expect(sim.roads.segments.size(), segments, "track doesn't split the road it crosses")
	_expect(sim.rails.segments.size(), 1, "and the road doesn't split the track")
	_expect(sim.lanes.route(Vector2i(150, 100), Vector2i(250, 100), true), route, "vehicles route as before")
	_expect(sim.lanes.route(Vector2i(200, 60), Vector2i(200, 140), false), [] as Array[Vector2i], "and never along the track")
	_expect(sim.apply({"op": "build_rail", "from": Vector2i(160, 101), "to": Vector2i(190, 101)}), "Road and track cross only straight across", "track can't run along a road")
	_expect(sim.apply({"op": "build_rail", "from": Vector2i(170, 80), "to": Vector2i(190, 100)}), "Road and track cross only straight across", "or cross it at 45°")
	_expect(sim.apply({"op": "build_road", "from": Vector2i(200, 110), "to": Vector2i(200, 130), "type": "terminal_1_1"}), "Road and track cross only straight across", "nor a road be laid along track")
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": sim.roads.segment_at(Vector2i(190, 100)), "side": 1, "from": 40, "to": 60}), "Something is already built here", "no area is built over track")
	_expect(sim.rails.anchors, [sim.site_rail_entry()] as Array[Vector2i], "track snaps onto the main line's end at the site edge")


func _test_level_crossing() -> void:
	var sim := _port()
	sim.apply({"op": "build_rail", "from": Vector2i(200, 60), "to": Vector2i(200, 140)})
	var crossing := sim.lanes.crossings()
	_expect(crossing.size(), 4, "the crossing is the road's four lane cells under the track")
	_expect(crossing.all(func(c: Vector2i) -> bool: return c in sim.rails.cells(sim.rails.segments.keys()[0]) and sim.lanes.is_junction(c)), true, "each is in both graphs, and no vehicle stops on it")
	# Booked by a train, the crossing holds a lorry back until it is freed.
	var lorry := Vehicle.new(1, "lorry", sim.lanes.route(Vector2i(190, 100), Vector2i(210, 100), true))
	_expect(sim.lane_traffic.place(lorry), true, "a lorry waits west of the crossing")
	_expect(sim.lane_traffic.book(-1, crossing), true, "a train books the crossing")
	for i in 100:
		sim.lane_traffic.advance(lorry, 5.0)
	_expect(crossing.any(func(c: Vector2i) -> bool: return sim.lane_traffic.holder(c) == lorry.id), false, "no lorry is on the crossing while the train has it")
	_expect(lorry.at_end(), false, "so the lorry is still short of it")
	sim.lane_traffic.release(-1)
	for i in 100:
		sim.lane_traffic.advance(lorry, 5.0)
	_expect(lorry.at_end(), true, "once the train frees it, the lorry crosses")


## An RMG block works wagons on the track running along all of its back edge.
func _test_rmg_siding() -> void:
	var sim := _port()
	var road := sim.roads.segment_at(Vector2i(160, 100))
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": road, "side": 1, "from": 0, "to": 29}), "", "a yard block south of the road")
	var block: int = sim.areas.list.keys().max()
	var area: Dictionary = sim.areas.list[block]
	var behind: int = area.start.y + sim.areas.depth_of(area) * area.out.y
	sim.apply({"op": "set_area", "id": block, "settings": {"gear": "rmg"}})
	_expect(sim.apply({"op": "build_rail", "from": Vector2i(area.start.x, behind), "to": Vector2i(area.start.x + 20, behind)}), "", "track along part of its back")
	_expect(AreaFlow.siding(sim, block), [] as Array[Vector2i], "covering part of the block is no siding")
	_expect(sim.apply({"op": "build_rail", "from": Vector2i(area.start.x + 20, behind), "to": Vector2i(area.end.x + 10, behind)}), "", "track along the rest")
	_expect(AreaFlow.siding(sim, block).size(), 30, "covering all of it is a siding, a cell per cell of the block")
	_expect(Inspect.describe(sim, {"area": block}).has("Siding for 10 wagons"), true, "a wagon per bay, shown by Inspect")
	sim.apply({"op": "set_area", "id": block, "settings": {"gear": "rtg"}})
	_expect(AreaFlow.siding(sim, block), [] as Array[Vector2i], "only RMGs reach over a siding")
	sim.apply({"op": "set_area", "id": block, "settings": {"gear": "rmg"}})
	sim.tick()
	_expect(sim.machines.list.values().filter(func(m: Dictionary) -> bool: return m.area == block and m.gear == "rmg").size(), 1, "10 bays get one RMG, by the data's bays per machine")


## Track comes with RMGs, at the milestone that unlocks them.
func _test_track_is_locked() -> void:
	var sim := AreaPort.owned(PortSim.new(0, Content.base(), true))
	_expect(sim.apply({"op": "build_rail", "from": Vector2i(200, 60), "to": Vector2i(200, 140)}).begins_with("Unlocked at milestone"), true, "track waits for its milestone")


## Imports booked to rail go to the rail block and leave by train, never by
## the gate; the RMG works each wagon in the data's time.
func _test_trains_take_rail_imports() -> void:
	var rules := RandomPort.rules()
	for line: String in rules.lines:
		rules.lines[line].rail_share = 1.0
	rules.rail.train.interval_minutes = 60.0
	var sim := AreaPort.working_terminal(12, 0, rules)
	var block := AreaPort.add_rail_block(sim)
	_expect(RailFlow.is_rail_block(sim, block), true, "an RMG block with its siding joined to the rail entry is a rail block")
	var booked := {}
	var by_gate := 0
	var worked_ticks := 0
	var loaded := 0
	for i in roundi(6 * 60 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for id: int in sim.boxes:
			if sim.boxes[id].rail:
				booked[id] = true
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.kind == "lorry" and vehicle.box in booked:
				by_gate += 1
		for train: Train in sim.trains:
			if train.state == "working":
				worked_ticks += 1
				loaded = maxi(loaded, train.wagons.filter(func(b: int) -> bool: return b != 0).size())
	_expect(booked.size(), 12, "every import is booked to rail")
	_expect(by_gate, 0, "no lorry ever comes for one")
	_expect([sim.by_rail, sim.boxes.keys().filter(func(b: int) -> bool: return b in booked)], [12, []], "and all 12 left by train")
	# One RMG (10 bays, 8 a machine) works the wagons one at a time: each move is
	# at least a lift and a set-down, at most that plus two trips the block's length.
	var gear: Dictionary = rules.yard_gear.rmg
	var least: float = gear.lift_seconds + gear.set_down_seconds
	var most: float = least + 2 * 30 * Grid.CELL / gear.speed
	var seconds := worked_ticks * Machines.SECONDS_PER_TICK
	_expect(seconds >= 12 * least and seconds <= 12 * most + 2 * Machines.SECONDS_PER_TICK * 10, true, "the train is worked in the data's time: %.0f s for 12 moves, %.0f to %.0f" % [seconds, 12 * least, 12 * most])


func _expect(got: Variant, want: Variant, what: String) -> void:
	if got != want:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, got, want])
