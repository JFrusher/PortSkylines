extends SceneTree
## Profiles the sim on the endgame port: runs it for a while and prints the
## time spent inside each of the sim's main per-tick functions (inclusive, so
## a function's callees count in it too). Godot has no headless script
## profiler, so a subclass times the functions instead.
## godot --headless --script res://bench/profile_sim.gd -- <ticks>

const EndgamePort := preload("res://bench/endgame_port.gd")


class ProfiledSim extends PortSim:
	var spent := {}  # function -> microseconds
	var calls := {}  # function -> count

	func _time(name: String, start: int) -> void:
		spent[name] = spent.get(name, 0) + Time.get_ticks_usec() - start
		calls[name] = calls.get(name, 0) + 1

	func tick() -> void:
		var start := Time.get_ticks_usec()
		super()
		_time("tick", start)

	func _dispatch_import_lorry() -> bool:
		var start := Time.get_ticks_usec()
		var sent := super()
		_time("_dispatch_import_lorry", start)
		return sent

	func _dispatch_export_lorry() -> bool:
		var start := Time.get_ticks_usec()
		var sent := super()
		_time("_dispatch_export_lorry", start)
		return sent

	func _drive_lorry(lorry: Vehicle) -> void:
		var start := Time.get_ticks_usec()
		super(lorry)
		_time("_drive_lorry", start)

	func _drive_tractor(tractor: Vehicle) -> void:
		var start := Time.get_ticks_usec()
		super(tractor)
		_time("_drive_tractor", start)

	func _work(ship: Ship) -> void:
		var start := Time.get_ticks_usec()
		super(ship)
		_time("_work", start)

	func _route_via_gate(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
		var start := Time.get_ticks_usec()
		var path := super(from, to)
		_time("_route_via_gate", start)
		return path

	func _gate_queues() -> Dictionary:
		var start := Time.get_ticks_usec()
		var counts := super()
		_time("_gate_queues", start)
		return counts

	func _yard_tile_for(role: String, from: Vector2i) -> Vector2i:
		var start := Time.get_ticks_usec()
		var tile := super(role, from)
		_time("_yard_tile_for", start)
		return tile

	func _export_for(from: Vector2i) -> Dictionary:
		var start := Time.get_ticks_usec()
		var found := super(from)
		_time("_export_for", start)
		return found

	func _advance(vehicle: Vehicle, speed: float) -> bool:
		var start := Time.get_ticks_usec()
		var done := super(vehicle, speed)
		_time("_advance", start)
		return done

	func _head_for(vehicle: Vehicle, to: Vector2i) -> void:
		var start := Time.get_ticks_usec()
		super(vehicle, to)
		_time("_head_for", start)


func _initialize() -> void:
	var ticks := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 400
	var sim := ProfiledSim.new(5, EndgamePort.rules(), true)
	EndgamePort.build(sim)
	for i in 300:
		sim.tick()
	EndgamePort.place_lorries(sim, 2000)
	sim.spent.clear()
	sim.calls.clear()
	for i in ticks:
		sim.tick()
	var total: int = sim.spent.tick
	print("%d ticks, %.1f ms a tick, %d vehicles at the end" % [ticks, total / 1000.0 / ticks, sim.vehicles.size()])
	var names: Array = sim.spent.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return sim.spent[a] > sim.spent[b])
	for name: String in names:
		print("%-24s %6.1f%%  %8.1f ms  %7d calls  %8.1f us a call" % [name, 100.0 * sim.spent[name] / total, sim.spent[name] / 1000.0, sim.calls[name], sim.spent[name] / float(sim.calls[name])])
	quit()
