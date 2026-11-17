extends SceneTree
## M11 the town next door: its mood eases towards jobs and the fund less
## noise and light; light counts only at night; a tree belt halves what is
## behind it; shore power silences a quay's ships; the bypass takes the
## highway's lorries away; the fund is paid daily; the news says when the
## town turns sour.
## godot --headless --script res://tests/test_town.gd

const AreaPort := preload("res://tests/area_port.gd")

var _failures := 0


func _initialize() -> void:
	_test_near_is_louder()
	_test_light_only_at_night()
	_test_belt()
	_test_fixes()
	_test_mood_eases_and_the_news()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


## The base port, its town `offset` cells from the site entry, at `hour`.
func _port(offset: Array, hour := 12.0) -> PortSim:
	var sim := AreaPort.base()
	sim.rules.town.offset_cells = offset
	sim.ledger.cash = 100000000
	_at(sim, hour)
	return sim


## Runs `sim` to the next `hour` of the day.
func _at(sim: PortSim, hour: float) -> void:
	while absf(fmod(sim.clock.calendar_minutes() / 60.0, 24.0) - hour) > 0.01:
		sim.tick()


func _test_near_is_louder() -> void:
	var far := Town.parts(_port([60, -90]))
	var near := Town.parts(_port([-300, -60]))
	_expect(near.noise > far.noise, true, "a town by the port hears more (%.1f vs %.1f)" % [near.noise, far.noise])
	_expect(near.jobs > 0.0, true, "the port's jobs count")
	_expect(near.target < far.target, true, "and likes it less")


func _test_light_only_at_night() -> void:
	_expect(Town.parts(_port([-300, -60], 12.0)).light, 0.0, "no floodlight by day")
	_expect(Town.parts(_port([-300, -60], 23.0)).light > 0.0, true, "floodlight at night")


func _test_belt() -> void:
	var belt := {Vector2i(5, 0): true, Vector2i(5, 1): true}
	_expect(Town._behind_belt(Vector2(0, 0), Vector2(10, 0), belt), true, "a belt in the way screens")
	_expect(Town._behind_belt(Vector2(0, 5), Vector2(10, 5), belt), false, "one off to the side doesn't")


func _test_fixes() -> void:
	var sim := _port([-300, -60])
	var apron := 0
	for id: int in sim.areas.list:
		if sim.areas.kind_of(sim.areas.list[id]) == "quay_apron":
			apron = id
	for i in 20000:
		if sim.ships.any(func(ship: PortSim.Ship) -> bool: return ship.state == PortSim.Ship.State.WORKING) and sim.vehicles.any(func(v: Vehicle) -> bool: return v.kind == "lorry"):
			break
		sim.tick()
	var before: float = Town.parts(sim).noise
	_expect(sim.apply({"op": "buy_shore_power", "area": apron}), "", "shore power bought")
	_expect(sim.apply({"op": "buy_shore_power", "area": apron}), "This quay has shore power already", "only once")
	var powered: float = Town.parts(sim).noise
	_expect(powered < before, true, "a ship on shore power is quiet (%.1f vs %.1f)" % [powered, before])
	_expect(sim.apply({"op": "buy_bypass"}), "", "bypass bought")
	_expect(Town.parts(sim).noise < powered, true, "the bypass takes the highway's lorries away")
	_expect(sim.apply({"op": "set_area", "id": apron, "settings": {"shore_power": true}}).is_empty(), false, "shore power isn't free")
	_expect(sim.apply({"op": "set_town_fund", "per_day": -1}).is_empty(), false, "no negative fund")
	_expect(sim.apply({"op": "set_town_fund", "per_day": 1000}), "", "a fund set")
	_expect(Town.parts(sim).fund, 1000.0 / sim.rules.town.fund_per_point, "the fund lifts the mood")
	var day := sim.clock.game_day()
	while sim.clock.game_day() == day:
		sim.tick()
	_expect(sim.ledger.days[-1].lines.get("town", 0), -1000, "and is paid each day")


func _test_mood_eases_and_the_news() -> void:
	var sim := _port([-300, -60])
	sim.rules.town.base_mood = -100.0
	sim.town.mood = 60.0
	for hour in 30:
		_at(sim, fmod(hour + 13.0, 24.0))
	_expect(sim.town.mood < sim.rules.town.sour_below, true, "the mood falls towards its target (%.1f)" % sim.town.mood)
	_expect(sim.events.any(func(event: Dictionary) -> bool: return "complain" in event.text), true, "the news says so")
