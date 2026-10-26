extends SceneTree
## M6's cargo: hinterland places for boxes and demand that grows with
## milestones.
## godot --headless --script res://tests/test_cargo.gd

const AreaPort := preload("res://tests/area_port.gd")
const RandomPort := preload("res://tests/random_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_box_mix_over_ten_days()
	_test_demand_grows_with_milestones()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


## Over 10 game days of feeder calls, imports and exports go to and come from
## the hinterland's places in the data's shares.
func _test_box_mix_over_ten_days() -> void:
	var sim := AreaPort.base()
	AreaPort.add_export_block(sim)
	var seen := {}
	var said := ""
	for i in 10 * SimClock.TICKS_PER_DAY:
		sim.tick()
		if said == "":
			for vehicle: Vehicle in sim.vehicles:
				if vehicle.loaded:
					var place: Dictionary = sim.rules.hinterland.places[sim.boxes[vehicle.box].place]
					said = place.name if Inspect.describe(sim, vehicle).any(func(line: String) -> bool: return line.contains(place.name)) else "nothing"
					break
		# Every box lives for minutes at least, so a look every game minute sees each.
		if i % 20 == 0:
			for id: int in sim.boxes:
				seen[id] = sim.boxes[id].place
	_expect(seen.size() > 1500, true, "ten days move a fair sample of boxes (%d)" % seen.size())
	var places: Dictionary = sim.rules.hinterland.places
	for place: String in places:
		var share := seen.values().count(place) / float(seen.size())
		_expect(absf(share - places[place].share) < 0.04, true, "%s gets its share of boxes: %.3f against %.2f" % [place, share, places[place].share])
	_expect(said in places.values().map(func(p: Dictionary) -> String: return p.name), true, "Inspect says where a box goes or comes from (%s)" % said)


## Lines offer services more often as the port reaches milestones.
func _test_demand_grows_with_milestones() -> void:
	var sim := PortSim.new()
	_expect(sim.hinterland_demand(), 1.0, "the port starts at the first milestone's demand")
	var quick := PortSim.new(0, RandomPort.quick())
	_expect(quick.hinterland_demand(), quick.milestones()[-1].demand, "every milestone reached gives the last's")
	var offers := []
	for demand: float in [1.0, 2.0]:
		var contracts := Contracts.new(sim.rules)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var made := 0
		for i in 2000:
			if not contracts.offer(rng, 0.0, 1000, func(_kind: String) -> bool: return true, demand).is_empty():
				made += 1
				contracts.offers.clear()
		offers.append(made)
	_expect(offers[1] > offers[0] * 1.6, true, "twice the demand brings about twice the offers (%d against %d)" % [offers[1], offers[0]])


func _expect(got: Variant, want: Variant, what: String) -> void:
	if got != want:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, got, want])
