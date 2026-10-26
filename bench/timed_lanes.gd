extends RefCounted
## Timed stand-ins for the sim's route search and vehicle moves, for the
## benches. Each reports to `profile.add(part, start_usec)`.


class Lanes extends LaneGraph:
	var profile: Object

	func route(from: Vector2i, to: Vector2i, lorry: bool) -> Array[Vector2i]:
		var start := Time.get_ticks_usec()
		var found := super(from, to, lorry)
		profile.add("route (LaneGraph.route)", start)
		return found


class Traffic extends LaneTraffic:
	var profile: Object

	func advance(vehicle: Vehicle, speed: float) -> bool:
		var start := Time.get_ticks_usec()
		var done := super(vehicle, speed)
		profile.add("move (LaneTraffic.advance)", start)
		return done


## Swaps `sim`'s lane graph and traffic for timed ones holding the same state.
static func install(sim: PortSim, profile: Object) -> void:
	var lanes := Lanes.new(sim.roads)
	lanes.areas = sim.areas
	lanes.profile = profile
	var traffic := Traffic.new(lanes)
	traffic.profile = profile
	traffic.cells = sim.lane_traffic.cells
	sim.lanes = lanes
	sim.lane_traffic = traffic
