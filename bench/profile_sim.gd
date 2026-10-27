extends SceneTree
## Profiles the sim on bench/endgame.bin (from make_endgame.gd): runs it for
## `ticks` ticks and prints the time spent in each part of a tick, routes and
## vehicle moves included, largest first. Godot has no headless script
## profiler, so this runs PortSim.tick's and AreaFlow.tick's steps itself with
## a timer around each, then checks the state hash against a plain run of the
## same ticks: a tick that changed without this script following fails here.
## godot --headless --script res://bench/profile_sim.gd -- <ticks>

const PATH := "res://bench/endgame.bin"
const TimedLanes := preload("res://bench/timed_lanes.gd")
const EndgamePort := preload("res://bench/endgame_port.gd")

var spent := {}  # part -> microseconds
var calls := {}  # part -> count


func _initialize() -> void:
	var ticks := int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 300
	var sim := _load()
	var plain := _load()
	if sim == null:
		return
	print("loaded: %d vehicles, %d boxes, %d ships, %d areas" % [sim.vehicles.size(), sim.boxes.size(), sim.ships.size(), sim.areas.list.size()])
	TimedLanes.install(sim, self)
	for i in ticks:
		var start := Time.get_ticks_usec()
		_tick(sim)
		add("tick", start)
		start = Time.get_ticks_usec()
		plain.tick()
		add("untimed tick", start)
	if sim.state_hash() != plain.state_hash():
		push_error("the profiled ticks differ from PortSim.tick: update _tick to match it")
		quit(1)
		return
	var tick_us: float = spent.tick
	print("%d ticks: %.2f ms a tick untimed, %.2f profiled (the timed overrides cost the difference)" % [ticks, spent["untimed tick"] / 1000.0 / ticks, tick_us / 1000.0 / ticks])
	spent.erase("untimed tick")
	print("%d ticks: %.2f ms a tick, %d vehicles at the end; shares are inclusive, so route and move also count in the steps that call them" % [ticks, tick_us / 1000.0 / ticks, sim.vehicles.size()])
	var parts := spent.keys()
	parts.sort_custom(func(a: String, b: String) -> bool: return spent[a] > spent[b])
	for part: String in parts:
		print("  %-40s %5.1f%%  %8d calls  %8.1f us a call" % [part, 100.0 * spent[part] / tick_us, calls[part], spent[part] / float(calls[part])])
	quit()


func add(part: String, start: int) -> void:
	spent[part] = spent.get(part, 0) + Time.get_ticks_usec() - start
	calls[part] = calls.get(part, 0) + 1


func _load() -> PortSim:
	var loaded := SaveFile.load_from(PATH)
	if loaded.has("error"):
		push_error(loaded.error + " (run bench/make_endgame.gd first)")
		quit(1)
		return null
	# Rules are data, not saved: put the bench's back.
	loaded.sim.rules = EndgamePort.bench_rules()
	return loaded.sim


## PortSim.tick and AreaFlow.tick, step by step, each step timed.
func _tick(sim: PortSim) -> void:
	var start := Time.get_ticks_usec()
	sim.clock.tick()
	if sim.clock.ticks % SimClock.TICKS_PER_DAY == 0:
		sim._end_of_day()
	if not sim.crane_orders.is_empty():
		sim._deliver_cranes()
	for service in sim.contracts.due(sim.clock.ticks % (SimClock.TICKS_PER_DAY * 7)):
		sim._call(service)
	if sim.clock.ticks % roundi(sim.rules.contracts.offer_check_minutes / SimClock.CALENDAR_MINUTES_PER_TICK) == 0:
		sim._offer_service()
		AreaFlow.fine_unplugged(sim, sim.clock.calendar_minutes())
	add("calendar (days, calls, offers)", start)
	start = Time.get_ticks_usec()
	sim._draw_power()
	add("reefer power (PortSim._draw_power)", start)
	start = Time.get_ticks_usec()
	var berths_now := Vector2i(sim._departures, sim.areas.version + sim.roads.version)
	for ship: PortSim.Ship in sim.ships.duplicate():
		if ship.state == PortSim.Ship.State.ANCHORED and berths_now == sim._berths_seen:
			continue
		sim._work(ship)
	sim._berths_seen = berths_now
	add("ships (PortSim._work)", start)
	start = Time.get_ticks_usec()
	sim._until_lorry -= SimClock.CALENDAR_MINUTES_PER_TICK
	if sim._until_lorry <= 0.0 and AreaFlow.dispatch_import_lorry(sim):
		sim._until_lorry = sim.rules.lorry_interval_minutes
	add("dispatch_import_lorry", start)
	start = Time.get_ticks_usec()
	sim._until_export -= SimClock.CALENDAR_MINUTES_PER_TICK
	if sim._until_export <= 0.0 and AreaFlow.dispatch_export_lorry(sim):
		sim._until_export = sim.rules.export_lorry_interval_minutes
	add("dispatch_export_lorry", start)
	start = Time.get_ticks_usec()
	AreaFlow._fit_machines(sim)
	add("_fit_machines", start)
	start = Time.get_ticks_usec()
	for machine: int in sim.machines.tick():
		AreaFlow._machine_done(sim, machine)
	add("machines (tick, _machine_done)", start)
	start = Time.get_ticks_usec()
	for vehicle: Vehicle in sim.vehicles.duplicate():
		AreaFlow._drive(sim, vehicle)
	add("vehicles (AreaFlow._drive)", start)
	start = Time.get_ticks_usec()
	RailFlow.tick(sim)
	add("trains (RailFlow.tick)", start)
