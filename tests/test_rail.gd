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
	_test_discount()
	_test_rail_cuts_the_gate_queue()
	_test_trains_book_crossings()
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
	# Leaving once nothing is due, so the time worked is the RMG's alone.
	rules.rail.train.dwell_minutes = 0.0
	var sim := AreaPort.working_terminal(12, 0, rules)
	var block := AreaPort.add_rail_block(sim)
	_expect(RailFlow.is_rail_block(sim, block), true, "an RMG block with its siding joined to the rail entry is a rail block")
	var booked := {}
	var placed := {}
	var by_gate := 0
	var worked_ticks := 0
	var loaded := 0
	for i in roundi(6 * 60 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		for id: int in sim.boxes:
			placed[id] = sim.boxes[id].place
			if sim.boxes[id].rail:
				booked[id] = true
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.kind == "lorry" and vehicle.box in booked:
				by_gate += 1
		for train: Train in sim.trains:
			if train.state == "working":
				if worked_ticks == 30:
					_expect(SaveFile.save("user://rail.bin", sim), "", "a port with a train being worked saves")
					var reloaded: Dictionary = SaveFile.load_from("user://rail.bin")
					_expect(reloaded.get("error", ""), "", "and loads")
					if reloaded.has("sim"):
						_expect(reloaded.sim.to_dict(), sim.to_dict(), "to the same state")
				if worked_ticks == 0:
					_expect(Inspect.describe(sim, Inspect.pick(sim, train.path[int(train.t)]))[1], "At its siding, being worked", "Inspect picks a train and says what it is doing")
				worked_ticks += 1
				loaded = maxi(loaded, train.wagons.filter(func(b: int) -> bool: return b != 0).size())
	_expect(booked.size() > 0 and booked.keys().all(func(b: int) -> bool: return sim.rules.hinterland.places[placed[b]].rail_km > 0.0), true, "the imports for places with a rail link are booked to rail (%d of 12)" % booked.size())
	_expect(by_gate, 0, "no lorry ever comes for one")
	_expect([sim.by_rail, sim.boxes.keys().filter(func(b: int) -> bool: return b in booked)], [booked.size(), []], "and all left by train")
	# One RMG (10 bays, 8 a machine) works the wagons one at a time: each move is
	# at least a lift and a set-down, at most that plus two trips the block's length.
	var gear: Dictionary = rules.yard_gear.rmg
	var least: float = gear.lift_seconds + gear.set_down_seconds
	var most: float = least + 2 * 30 * Grid.CELL / gear.speed
	var seconds := worked_ticks * Machines.SECONDS_PER_TICK
	var moves := booked.size()
	_expect(seconds >= moves * least and seconds <= moves * most + 2 * Machines.SECONDS_PER_TICK * 10, true, "the train is worked in the data's time: %.0f s for %d moves, %.0f to %.0f" % [seconds, moves, moves * least, moves * most])


## The rail discount buys every line a share of rail, at a cost per box.
func _test_discount() -> void:
	var sim := AreaPort.base()
	var line: String = sim.rules.lines.keys()[0]
	var base: float = sim.rules.lines[line].rail_share
	_expect(sim.apply({"op": "set_rail_discount", "dollars": 50}), "", "a discount is offered")
	_expect(is_equal_approx(sim.rail_share(line), base + 50 * sim.rules.rail.discount.share_per_dollar), true, "it adds share_per_dollar a dollar")
	_expect(sim.apply({"op": "set_rail_discount", "dollars": 100}), "", "up to the most")
	_expect(is_equal_approx(sim.rail_share(line), minf(base + 100 * sim.rules.rail.discount.share_per_dollar, sim.rules.rail.discount.max_share)), true, "the most buys its share, never past max_share")
	_expect(sim.apply({"op": "set_rail_discount", "dollars": 101}), "The rail discount runs from $0 to $100 a box", "and no more")


## M6's exit scenario: with 30% of boxes by rail, the gate queue is shorter.
## Half the boxes go to places with a rail link, so lines book 60% of those.
func _test_rail_cuts_the_gate_queue() -> void:
	var queued := []
	var rail_share := []
	for share: float in [0.0, 0.6]:
		var rules := RandomPort.rules()
		rules.lorry_interval_minutes = 0.25
		for line: String in rules.lines:
			rules.lines[line].rail_share = share
		var sim := AreaPort.base(rules)
		AreaPort.add_export_block(sim)
		AreaPort.add_rail_block(sim)
		var gates: Array = sim.areas.list.keys().filter(func(id: int) -> bool: return sim.areas.kind_of(sim.areas.list[id]) == "gate")
		var total := 0
		var imports := {}
		for i in SimClock.TICKS_PER_DAY:
			sim.tick()
			for gate: int in gates:
				total += sim.lorries_bound_for(gate)
			for id: int in sim.boxes:
				if sim.boxes[id].kind == "import":
					imports[id] = sim.boxes[id].rail
		queued.append(total / float(SimClock.TICKS_PER_DAY))
		rail_share.append(imports.values().count(true) / float(imports.size()))
	print("  a day of calls: %.1f lorries at the gate on average with no rail, %.1f with %.0f%% of imports booked to rail" % [queued[0], queued[1], rail_share[1] * 100])
	_expect(rail_share[1] > 0.2 and rail_share[1] < 0.4, true, "about 30%% of imports go by rail (%.2f)" % rail_share[1])
	_expect(queued[1] < queued[0] * 0.85, true, "and the gate queue is measurably shorter (%.1f against %.1f)" % [queued[1], queued[0]])


## A train's track crosses the road every lorry takes: while the train has
## the crossing booked, no lorry is on it, and both still get through.
func _test_trains_book_crossings() -> void:
	var rules := RandomPort.rules()
	rules.lorry_interval_minutes = 0.25
	for line: String in rules.lines:
		rules.lines[line].rail_share = 0.5
	rules.rail.train.interval_minutes = 30.0
	var sim := AreaPort.working_terminal(40, 0, rules)
	sim.creative = true
	var east := sim.roads.segment_at(Vector2i(200, sim.site_entry().y))
	# North of the east road, its siding behind it; the track turns south across the road.
	_expect(sim.apply({"op": "build_area", "type": "yard_block", "segment": east, "side": -1, "from": 92, "to": 121}), "", "a rail block north of the road")
	var block: int = sim.areas.list.keys().max()
	sim.apply({"op": "set_area", "id": block, "settings": {"gear": "rmg"}})
	var area: Dictionary = sim.areas.list[block]
	var behind: Vector2i = area.start + area.out * sim.areas.depth_of(area)
	var entry := sim.site_rail_entry()
	var bend := Vector2i(entry.x - 5, behind.y)
	for leg: Array in [[behind, bend], [bend, Vector2i(bend.x, entry.y)], [Vector2i(bend.x, entry.y), entry]]:
		_expect(sim.apply({"op": "build_rail", "from": leg[0], "to": leg[1]}), "", "track across the road to the rail entry")
	var crossing := sim.lanes.crossings()
	_expect(crossing.size() > 0 and RailFlow.is_rail_block(sim, block), true, "the track crosses the road on its way to the rail block")
	var booked_ticks := 0
	var on_while_booked := 0
	var lorries_across := 0
	for i in roundi(4 * 60 / SimClock.CALENDAR_MINUTES_PER_TICK):
		sim.tick()
		var train_has := crossing.filter(func(c: Vector2i) -> bool: return sim.lane_traffic.holder(c) < 0)
		for vehicle: Vehicle in sim.vehicles:
			if vehicle.kind == "lorry" and vehicle.path[int(vehicle.t)] in crossing:
				lorries_across += 1
				on_while_booked += 1 if not train_has.is_empty() else 0
		booked_ticks += 1 if not train_has.is_empty() else 0
	_expect(booked_ticks > 0, true, "trains booked the crossing (%d ticks)" % booked_ticks)
	_expect(lorries_across > 0, true, "lorries crossed it too (%d lorry ticks)" % lorries_across)
	_expect(on_while_booked, 0, "but never while a train had it")
	_expect(sim.by_rail > 0, true, "and boxes still left by train (%d)" % sim.by_rail)


func _expect(got: Variant, want: Variant, what: String) -> void:
	if got != want:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, got, want])
