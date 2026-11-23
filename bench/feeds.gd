extends SceneTree
## Speeds and feeds: runs a port for some game days and prints where the
## time and money go, to check the game's rates fit together.
## - each call: moves, hours alongside, cranes, moves an hour a crane, late
## - each closed day: income and costs by ledger category, cash, TEU
## - sampled every 10 game minutes: what cranes, tractors, AGVs and lorries
##   are doing, driving split into moving and stood in traffic
## Ports: "showcase" (bench/showcase_port.gd, every system at scale) or
## "starter" (AreaPort.base on the game's rules and milestones, with an
## export block, taking every offer a line makes as a willing player would),
## or "starter_turn" (the same, with a dead-end stub to turn round in just
## past the export block).
## godot --headless --script res://bench/feeds.gd -- <showcase|starter|starter_turn> <days>

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")
const Showcase := preload("res://bench/showcase_port.gd")
const SAMPLE_TICKS := 200  # 10 game minutes
const DRIVING := ["arriving", "to_slot", "returning", "to_crane", "leaving", "to_charge"]

var _samples := {}  # "kind/state" -> count
var _sample_count := 0
var _fetch_minutes := {}  # state -> minutes fetchers (tractors taking an export to a crane) spent in it
var _fetches := 0
var _last_state := {}
var _routes_shown := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2, "usage: -- <showcase|starter|starter_turn> <days>")
	var sim := _port(args[0])
	var days := int(args[1])
	var start := sim.clock.calendar_minutes()
	var log_seen := 0
	var last_day: int = sim.ledger.days[-1].day if not sim.ledger.days.is_empty() else -1
	var passed := sim.milestones_passed
	print("port %s, %d days, start cash %s, milestones passed %d" % [args[0], days, HudDetails.dollars(sim.ledger.cash), passed])
	for tick: int in days * SimClock.TICKS_PER_DAY:
		if args[0].begins_with("starter"):
			for offer: Dictionary in sim.contracts.offers.duplicate():
				sim.apply({"op": "accept_offer", "id": offer.id, "apron": 1})
		sim.tick()
		_time_fetchers(sim)
		if tick % SAMPLE_TICKS == 0:
			_sample(sim)
		for entry: Dictionary in sim.ship_log.slice(log_seen):
			print("CALL day %.2f %-10s %5d moves %5.1f h %d cranes %5.1f /h/crane late %.1f h" % [(sim.clock.calendar_minutes() - start) / 1440.0, entry.kind, entry.moves, entry.hours, entry.cranes, entry.moves / entry.hours / maxi(entry.cranes, 1) if entry.hours > 0.0 else 0.0, entry.late])
		log_seen = sim.ship_log.size()
		if not sim.ledger.days.is_empty() and sim.ledger.days[-1].day != last_day:
			last_day = sim.ledger.days[-1].day
			_day(sim, sim.ledger.days[-1])
		if sim.milestones_passed > passed:
			passed = sim.milestones_passed
			print("MILESTONE %d on day %.2f at %d TEU" % [passed, (sim.clock.calendar_minutes() - start) / 1440.0, sim.teu_handled])
	_report()
	quit()


func _port(name: String) -> PortSim:
	if name == "showcase":
		return Showcase.debug_port()
	var sim := AreaPort.base(RandomPort.strait(), "")
	sim.creative = true
	AreaPort.add_export_block(sim)
	# "starter_turn": a dead-end stub just past the export block, a place to turn round.
	if name == "starter_turn":
		var y := sim.site_entry().y
		var err := sim.apply({"op": "build_road", "from": Vector2i(190, y), "to": Vector2i(190, y - 20), "type": "terminal_1_1"})
		assert(err == "", err)
	sim.creative = false
	sim.ledger.cash = sim.rules.start_money
	return sim


func _day(sim: PortSim, day: Dictionary) -> void:
	var parts: Array[String] = []
	var keys: Array = day.lines.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return absi(day.lines[a]) > absi(day.lines[b]))
	for key: String in keys:
		if day.lines[key] != 0:
			parts.append("%s %s" % [key, HudDetails.dollars(day.lines[key])])
	print("DAY %d net %s cash %s TEU %d | %s" % [day.day, HudDetails.dollars(day.closed - day.opened), HudDetails.dollars(day.closed), sim.teu_handled, ", ".join(parts)])


func _sample(sim: PortSim) -> void:
	_sample_count += 1
	var states := {}
	for vehicle: Vehicle in sim.vehicles:
		states[vehicle.id] = vehicle.state
	for crane: PortSim.Crane in sim.cranes:
		_count("crane/" + _crane_state(sim, crane, states))
	var out := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "tractor" and not v.depot and not v.straddle).size()
	_count("tractor/idle in the pool (%d owned)" % sim.tractors, sim.tractors - out)
	for vehicle: Vehicle in sim.vehicles:
		var kind := "agv" if vehicle.depot else ("straddle" if vehicle.straddle else vehicle.kind)
		var state := vehicle.state
		if state in DRIVING and vehicle.id in sim.traffic.cars:
			state += " (stood)" if sim.traffic.cars[vehicle.id].v < 0.1 else " (moving)"
		_count("%s/%s" % [kind, state])


## Minutes each fetcher spends in each state, and fetches done (one
## arriving under its crane).
func _time_fetchers(sim: PortSim) -> void:
	for vehicle: Vehicle in sim.vehicles:
		if vehicle.kind != "tractor" or vehicle.home == Areas.NO_SPOT or vehicle.straddle:
			continue
		var state := vehicle.state
		if state in DRIVING and vehicle.id in sim.traffic.cars:
			state += " (stood)" if sim.traffic.cars[vehicle.id].v < 0.1 else " (moving)"
		_fetch_minutes[state] = _fetch_minutes.get(state, 0.0) + SimClock.CALENDAR_MINUTES_PER_TICK
		if vehicle.state != _last_state.get(vehicle.id, "") and vehicle.state in ["arriving", "to_crane"] and vehicle.id in sim.traffic.cars and _routes_shown < 40:
			var car: Dictionary = sim.traffic.cars[vehicle.id]
			var route: Array[int] = []
			route.assign(car.route)
			var ends: Array = [sim.network.pieces[route[0]].points[0], sim.network.pieces[route[-1]].points[-1]]
			print("ROUTE %-9s %5.0f m driven, %4.0f m apart, %d pieces, segments %s" % [vehicle.state, sim.network.length(route) * Grid.CELL, ends[0].distance_to(ends[1]) * Grid.CELL, route.size(), route.map(func(p: int) -> int: return sim.network.pieces[p].segment).filter(func(x: int) -> bool: return x != 0)])
			_routes_shown += 1
			if vehicle.state == "to_crane":
				var far: Vector2 = ends[0]
				for piece: int in route:
					for point: Vector2 in sim.network.pieces[piece].points:
						if point.distance_to(ends[0]) > far.distance_to(ends[0]):
							far = point
				print("  farthest point %s, %.0f m from where it set off; site entry %s" % [far, far.distance_to(ends[0]) * Grid.CELL, sim.site_entry()])
		if vehicle.state == "under_crane" and _last_state.get(vehicle.id, "") != "under_crane":
			_fetches += 1
		_last_state[vehicle.id] = vehicle.state


func _crane_state(sim: PortSim, crane: PortSim.Crane, states: Dictionary) -> String:
	if crane.broken:
		return "broken"
	for ship: PortSim.Ship in sim.ships:
		if ship.state == PortSim.Ship.State.WORKING and crane in AreaFlow.cranes_for(sim, ship):
			if states.get(crane.tractor, "") == "under_crane":
				return "discharging, working" if ship.boxes > 0 else "loading, working"
			var phase := "discharging" if ship.boxes > 0 else "loading"
			if phase == "loading" and not crane.tractor:
				var slot := AreaFlow._crane_slot(sim, crane, ship)
				var mine := sim.fetching_to(slot)
				var out := sim.vehicles.filter(func(v: Vehicle) -> bool: return v.kind == "tractor" and not v.depot and not v.straddle).size()
				var why := "%d fetching for it (%s), %s idle in the pool, %s" % [mine.size(), ",".join(mine.map(func(v: Vehicle) -> String: return v.state)), "some" if sim.tractors > out else "none", "an export ready" if AreaFlow._export_box(sim, ship) else "no export ready"]
				_count("loading wait/" + why)
			if not crane.tractor:
				return "%s, waiting: none under it" % phase
			return "%s, waiting: its tractor %s" % [phase, states.get(crane.tractor, "gone")]
	return "no ship"


func _count(key: String, by := 1) -> void:
	_samples[key] = _samples.get(key, 0) + by


func _report() -> void:
	print("\nFETCHES: %d exports brought to a crane; minutes each, by state" % _fetches)
	for state: String in _fetch_minutes:
		print("  %-30s %5.1f" % [state, _fetch_minutes[state] / maxi(_fetches, 1)])
	print("\nSAMPLES (%d, every 10 game minutes): average count in each state" % _sample_count)
	var keys := _samples.keys()
	keys.sort()
	var kind := ""
	for key: String in keys:
		var parts := key.split("/")
		var total := 0
		for other: String in keys:
			if other.begins_with(parts[0] + "/"):
				total += _samples[other]
		print("  %-10s %-40s %6.1f  %3.0f%%" % [parts[0] if parts[0] != kind else "", parts[1], float(_samples[key]) / _sample_count, 100.0 * _samples[key] / total])
		kind = parts[0]
