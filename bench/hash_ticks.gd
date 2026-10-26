extends SceneTree
## Prints the state hash of a save after `ticks` ticks, to show a change to
## the sim leaves its behaviour as it was: run it before and after.
## godot --headless --script res://bench/hash_ticks.gd -- <save> <ticks>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var loaded := SaveFile.load_from(args[0])
	if loaded.has("error"):
		push_error(loaded.error)
		quit(1)
		return
	var sim: PortSim = loaded.sim
	for i in int(args[1]):
		sim.tick()
	print("hash after %s ticks: %d (%d vehicles, %d boxes, %d delivered)" % [args[1], sim.state_hash(), sim.vehicles.size(), sim.boxes.size(), sim.delivered])
	quit()
