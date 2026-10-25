extends SceneTree
## A scripted playtest: the guided start's layout built by the commands the
## toolbar sends, on the base rules from the start money (seed 1), roads drawn
## through the road tool's snapping as a mouse would. Plays DAYS game days,
## accepting offers up to Guide.SERVICES, and prints what a player would watch.
## godot --headless --script res://tools/playtest.gd -- one_way|two_way

const DAYS := 7
## Where the gate starts along the terminal road, which is drawn from the
## highway: 20 cells is 80 m in, beside the highway; 420 is by the coast T.
const GATE_FROM := 20

var _sim: PortSim
## Most lorries queued on the road at any gate today.
var _worst_gate_queue := 0
## Game minutes lorries spent in each state between gate in and gate out.
var _turn_minutes := {}
## Each moving lorry's [path, t] at the last sample, and cells and minutes moved.
var _last := {}
var _moved := Vector2.ZERO


func _initialize() -> void:
	var mode: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "two_way"
	assert(mode in ["one_way", "two_way"], "mode is one_way or two_way")
	_sim = PortSim.new(1)
	print("== playtest: %s gate, start $%d" % [mode.replace("_", "-"), _sim.money])
	_build(mode)
	print("built: $%d left, upkeep $%d a day" % [_sim.money, _sim.daily_upkeep()])
	for day in DAYS:
		for i in SimClock.TICKS_PER_DAY:
			_sim.tick()
			if i % 20 == 0:
				_watch()
		_report_day(day)
	var total := 0
	for state: String in _turn_minutes:
		total += _turn_minutes[state]
	print("where gate turns go, of %d lorry minutes:" % total)
	for state: String in _turn_minutes:
		print("  %s: %.0f%%" % [state, 100.0 * _turn_minutes[state] / total])
	print("lorries arriving move %.1f cells a game minute; the data says %.1f" % [_moved.x / _moved.y, _sim.rules.lorry_speed / Grid.CELL])
	_print_routes()
	print("calls:")
	for call: Dictionary in _sim.ship_log:
		print("  %s %s: %d moves in %.1f h, %d cranes, %.1f h late" % [call.line, call.kind, call.moves, call.hours, call.cranes, call.late])
	quit()


## Builds the guide's layout, the gate GATE_FROM cells along the terminal
## road. The coast road is drawn 52 m in from the water, not the exact apron
## distance, and the terminal road is dragged to a point beside the coast
## road, so both the apron's stretch and snapping are played.
func _build(mode: String) -> void:
	var entry := _sim.site_entry()
	_do({"op": "build_road", "from": Vector2i(88, 200), "to": Vector2i(88, 340), "type": "terminal_1_1"})
	var from := _sim.roads.snap_start(entry)
	var to := _sim.roads.snap_end(from, Vector2i(90, entry.y + 1))
	print("snapping: terminal road dragged to (90, %d) ends at %s" % [entry.y + 1, to])
	_do({"op": "build_road", "from": from, "to": to, "type": "terminal_1_1"})
	print("snapping: the meeting is a %d-way junction" % _sim.roads.degree(_sim.roads.nodes.find_key(to)))
	var north := _sim.roads.segment_at(Vector2i(88, 250))
	var south := _sim.roads.segment_at(Vector2i(88, 320))
	var east := _sim.roads.segment_at(Vector2i(300, entry.y))
	var apron := _area({"op": "build_area", "type": "quay_apron", "segment": north, "side": 1, "from": 30, "to": 89})
	print("apron: %d rows deep from a road 52 m in" % _sim.areas.depth_of(_sim.areas.list[apron]))
	var before := _sim.areas.list.keys()
	if mode == "two_way":
		_do({"op": "build_two_way_gate", "type": "gate", "segment": east, "from": GATE_FROM, "to": GATE_FROM + 14})
	else:
		# The terminal road is drawn from the highway, so its right (side 1) is
		# beside the westbound lane lorries come in on, as the guide asks.
		_do({"op": "build_area", "type": "gate", "segment": east, "side": 1, "from": GATE_FROM, "to": GATE_FROM + 14})
	for gate: int in _sim.areas.list.keys().filter(func(id: int) -> bool: return id not in before):
		_do({"op": "set_terminal", "id": gate, "terminal": _sim.areas.list[apron].terminal})
	var imports := _area({"op": "build_area", "type": "yard_block", "segment": north, "side": -1, "from": 50, "to": 79})
	var exports := _area({"op": "build_area", "type": "yard_block", "segment": south, "side": -1, "from": 5, "to": 34})
	_do({"op": "set_area", "id": exports, "settings": {"role": "export"}})
	for id: int in [imports, exports]:
		_do({"op": "set_terminal", "id": id, "terminal": _sim.areas.list[apron].terminal})
	_do({"op": "place_sts", "apron": apron, "along": 30})
	_do({"op": "buy_tractors", "count": 4})


## A lorry's legs through the port, in cells, against the straight-line distance.
func _print_routes() -> void:
	var gates := _sim.areas.list.keys().filter(func(id: int) -> bool: return _sim.areas.kind_of(_sim.areas.list[id]) == "gate")
	var blocks := _sim.areas.list.keys().filter(func(id: int) -> bool: return _sim.areas.kind_of(_sim.areas.list[id]) == "yard_block")
	var entry := AreaFlow._entry_cell(_sim)
	for gate: int in gates:
		print("routes via gate %d (%s side):" % [gate, "north" if _sim.areas.list[gate].out.y < 0 else "south"])
		print("  entry to gate: %d cells" % _sim.lanes.route(entry, AreaFlow._buffer_start(_sim, gate), true).size())
		for block: int in blocks:
			var there := _sim.lanes.route(AreaFlow._buffer_end(_sim, gate), AreaFlow._buffer_start(_sim, block), true)
			var back := _sim.lanes.route(AreaFlow._buffer_end(_sim, block), AreaFlow._buffer_start(_sim, gate), true)
			var straight := RoadNet.length(_sim.areas.list[gate].start, _sim.areas.list[block].start)
			print("  gate to %s block %d: %d cells, back %d cells (straight line %d)" % [_sim.areas.list[block].settings.role, block, there.size(), back.size(), straight])


func _watch() -> void:
	for offer: Dictionary in _sim.contracts.offers.duplicate():
		if _sim.contracts.services.size() < Guide.SERVICES:
			_sim.apply({"op": "accept_offer", "id": offer.id})
	# Sampled every 20 ticks, so each sample is one game minute.
	for v: Vehicle in _sim.vehicles:
		if v.kind == "lorry" and v.gate_in >= 0.0:
			if v.state == "arriving" and v.id in _last and _last[v.id][0] == v.path:
				_moved += Vector2(v.t - _last[v.id][1], 1)
			_last[v.id] = [v.path, v.t]
			var doing := v.state + (" (stopped in traffic)" if v.waited > 0 else "")
			_turn_minutes[doing] = _turn_minutes.get(doing, 0) + 1
	for id: int in _sim.areas.list:
		if _sim.areas.kind_of(_sim.areas.list[id]) == "gate":
			_worst_gate_queue = maxi(_worst_gate_queue, _sim.handovers.waiting(id).road.size())


func _report_day(day: int) -> void:
	var lines: Dictionary = _sim.ledger.days[-1].lines if not _sim.ledger.days.is_empty() else {}
	var exports := _sim.boxes.values().filter(func(b: Dictionary) -> bool: return b.kind == "export").size()
	var imports := _sim.boxes.values().filter(func(b: Dictionary) -> bool: return b.kind == "import").size()
	var kpis := _sim.kpis()
	print("day %d: $%d, moves +$%d, storage +$%d, upkeep %d | services %d, calls %d | yard %d imports, %d exports | gate turn %.0f min, worst gate queue %d, gave up %d" % [
		day, _sim.money, lines.get("moves", 0), lines.get("storage", 0), lines.get("upkeep", 0),
		_sim.contracts.services.size(), _sim.ship_log.size(), imports, exports,
		kpis.gate_turn_minutes, _worst_gate_queue, _sim.gave_up])
	_worst_gate_queue = 0


func _do(command: Dictionary) -> void:
	var err := _sim.apply(command)
	if err:
		print("REFUSED %s: %s" % [command, err])


## Applies a build_area command and returns the new area's id.
func _area(command: Dictionary) -> int:
	_do(command)
	return _sim.areas.list.keys().max()
