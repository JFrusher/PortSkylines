class_name Scenario
extends RefCounted
## Scenarios (M11): a set game, from the data's "scenarios": a map (fixed,
## or a fresh coast drawn for the go), start money, a few rules patched,
## goals to reach within so many days, and conditions to keep all the way.
## Checked as each day closes: won when every goal is reached, lost when a
## kept condition breaks or time runs out. The medal is the day it was won
## by: gold, silver, or bronze within the time. A sim's "scenario" is
## {"key" ("" in the sandbox), "fresh", "status" ("playing", "won" or
## "lost"), "medal", "moves", "on_time_calls"}.

const GOALS := ["moves", "on_time_calls", "agvs", "mood"]


## The sandbox's scenario: none.
static func none() -> Dictionary:
	return {"key": "", "fresh": false, "status": "", "medal": "", "moves": 0, "on_time_calls": 0}


## The rules scenario `key` plays by; on a fresh coast from `fresh_seed`
## when it is not -1.
static func rules_for(key: String, fresh_seed := -1) -> Dictionary:
	var rules := Content.base().duplicate(true)
	if key == "":
		return rules
	var scenario: Dictionary = rules.scenarios[key]
	for change: Dictionary in scenario.patch:
		var parts: PackedStringArray = change.path.split(".")
		var at: Dictionary = rules
		for part in parts.slice(0, parts.size() - 1):
			at = at[part]
		at[parts[-1]] = change.value
	rules.start_money = scenario.start_money
	rules.map = scenario.map if fresh_seed == -1 else MapGen.PREFIX + str(fresh_seed)
	return rules


## A new game of scenario `key`.
static func start(key: String, seed_value: int, fresh: bool) -> PortSim:
	var sim := PortSim.new(seed_value, rules_for(key, seed_value if fresh else -1))
	sim.scenario = none()
	sim.scenario.key = key
	sim.scenario.fresh = fresh
	sim.scenario.status = "playing"
	return sim


## Each goal and kept condition: {"text", "now", "target", "keep", "met"}.
static func progress(sim: PortSim) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if sim.scenario.key == "":
		return found
	var scenario: Dictionary = sim.rules.scenarios[sim.scenario.key]
	for keep: bool in [false, true]:
		for goal: Dictionary in scenario.keep if keep else scenario.goals:
			var now := _value(sim, goal.kind)
			found.append({"text": _text(goal.kind, goal.count, keep), "now": now, "target": goal.count, "keep": keep, "met": now >= goal.count})
	return found


## As day `day` (counted from 0) closes: counts its moves, then wins or loses.
static func close_day(sim: PortSim, day: int, moves: int) -> void:
	if sim.scenario.status != "playing":
		return
	sim.scenario.moves += moves
	var scenario: Dictionary = sim.rules.scenarios[sim.scenario.key]
	var all := progress(sim)
	var played := day + 1
	if all.any(func(p: Dictionary) -> bool: return p.keep and not p.met):
		_end(sim, "lost", "")
	elif all.all(func(p: Dictionary) -> bool: return p.met):
		_end(sim, "won", "gold" if played <= scenario.medals.gold else "silver" if played <= scenario.medals.silver else "bronze")
	elif played >= scenario.days:
		_end(sim, "lost", "")


## Counts a call that sailed inside its window.
static func sailed_on_time(sim: PortSim) -> void:
	if sim.scenario.status == "playing":
		sim.scenario.on_time_calls += 1


static func _end(sim: PortSim, status: String, medal: String) -> void:
	sim.scenario.status = status
	sim.scenario.medal = medal
	var name: String = sim.rules.scenarios[sim.scenario.key].name
	sim._event("%s won: %s medal" % [name, medal.capitalize()] if status == "won" else "%s lost" % name)


static func _value(sim: PortSim, kind: String) -> float:
	match kind:
		"moves":
			return sim.scenario.moves
		"on_time_calls":
			return sim.scenario.on_time_calls
		"agvs":
			var count := 0
			for area: Dictionary in sim.areas.list.values():
				count += area.settings.get("agvs", 0)
			return count
		"mood":
			return sim.town.mood
	assert(false, "no scenario goal %s" % kind)
	return 0.0


static func _text(kind: String, count: float, keep: bool) -> String:
	var text: String = {"moves": "Move %d boxes across the quay", "on_time_calls": "Work %d calls inside their windows", "agvs": "Run %d AGVs", "mood": "Town mood %d or more"}[kind] % count
	return ("Keep: " if keep else "") + text
