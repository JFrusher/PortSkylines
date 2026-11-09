class_name Junctions
extends RefCounted
## Signals and priority signs at junctions, by each junction's grid point;
## traffic asks may_enter before a vehicle goes from an approach into a
## junction's box. It asks `lanes` for a junction's arms, and `traffic`
## whether a junction's box (box_busy) or an arm's approach (approach_busy)
## has a vehicle in it, so it works over today's lane graph and the lane
## network alike. A signal lets one phase in at a time: an arm and the one
## opposite it go together, an arm with none opposite alone. A phase gives
## way to the next once its green time is over and the box is empty, so two
## phases are never in the box together. A give-way arm goes in only while
## the box is empty and nothing is on an arm without a sign; a stop arm
## stands at the line for stop_seconds first.

## Point -> {"green": [seconds per phase], "phase": index, "left": seconds of green left}.
var signals := {}
## Point -> {arm: "give_way" or "stop"}.
var signs := {}
## Point -> {arm: {lane coming in, 0 nearest the middle: the turns it takes,
## of "left", "straight" and "right"}}; a lane without takes M7's.
var arrows := {}
## Bumped when arrows change, so the lane network is built again.
var version := 0
const TURNS := ["left", "straight", "right"]
var _rules: Dictionary


func _init(traffic_rules: Dictionary) -> void:
	_rules = traffic_rules


## Puts signals on junction `point`, each phase green for the data's default,
## or takes them off.
func set_signals(lanes: Object, point: Vector2, on: bool) -> String:
	if lanes.arms(point).is_empty():
		return "No junction there"
	if not on:
		signals.erase(point)
		return ""
	var greens := []
	greens.resize(phases(lanes, point).size())
	greens.fill(float(_rules.signal_green_seconds))
	signals[point] = {"green": greens, "phase": 0, "left": greens[0]}
	return ""


## Sets phase `phase`'s green time at junction `point`.
func set_green(point: Vector2, phase: int, seconds: float) -> String:
	if point not in signals or phase < 0 or phase >= signals[point].green.size():
		return "No such signal phase"
	if seconds < _rules.min_green_seconds or seconds > _rules.max_green_seconds:
		return "Green lasts %d to %d s" % [_rules.min_green_seconds, _rules.max_green_seconds]
	signals[point].green[phase] = seconds
	return ""


## Gives arm `arm` of junction `point` a sign: "give_way", "stop" or "" for none.
func set_sign(lanes: Object, point: Vector2, arm: Vector2i, sign: String) -> String:
	if arm not in lanes.arms(point):
		return "No road there"
	if sign not in ["", "give_way", "stop"]:
		return "Unknown sign: %s" % sign
	if sign == "":
		signs.get(point, {}).erase(arm)
	else:
		signs.get_or_add(point, {})[arm] = sign
	return ""


## Junction `point`'s phases, each a list of arms: each arm with the one
## opposite it, if any.
func phases(lanes: Object, point: Vector2) -> Array:
	var found := []
	for arm: Vector2i in lanes.arms(point):
		if not found.any(func(phase: Array) -> bool: return arm in phase):
			found.append([arm, -arm] if -arm in lanes.arms(point) else [arm])
	return found


## Whether vehicle `id`, on arm `arm` and stopped at the line for `waited`
## seconds, may go into junction `point`'s box now.
func may_enter(lanes: Object, traffic: Object, point: Vector2, arm: Vector2i, id: int, waited: float) -> bool:
	if point in signals:
		var at: Dictionary = signals[point]
		if at.left <= 0.0 or arm not in phases(lanes, point)[at.phase]:
			return false
	var sign := sign_at(lanes, point, arm)
	if sign == "":
		return true
	if sign == "stop" and waited < _rules.stop_seconds:
		return false
	if traffic.box_busy(point, id):
		return false
	for other: Vector2i in lanes.arms(point):
		if sign_at(lanes, point, other) == "" and traffic.approach_busy(point, other):
			return false
	return true


## The sign arm `arm` of junction `point` has: its own, else give way where
## it joins a roundabout's ring and isn't the ring.
func sign_at(lanes: Object, point: Vector2, arm: Vector2i) -> String:
	if signs.get(point, {}).has(arm):
		return signs[point][arm]
	return "give_way" if not lanes.ring_arms(point).is_empty() and arm not in lanes.ring_arms(point) else ""


## One tick of every signal, `seconds` of traffic (real seconds, as cars
## drive): green counts down, and once it is over and the
## box is empty the next phase goes green. Forgets junctions that are gone.
func tick(lanes: Object, traffic: Object, seconds: float) -> void:
	for point: Vector2 in signals.keys():
		if lanes.arms(point).is_empty():
			signals.erase(point)
			continue
		var at: Dictionary = signals[point]
		at.left -= seconds
		if at.left <= 0.0 and not traffic.box_busy(point, 0):
			at.phase = (at.phase + 1) % at.green.size()
			at.left = at.green[at.phase]
	for point: Vector2 in signs.keys():
		if lanes.arms(point).is_empty():
			signs.erase(point)
	for point: Vector2 in arrows.keys():
		if lanes.arms(point).is_empty():
			arrows.erase(point)
			version += 1


## Gives lane `lane` (0 nearest the middle) coming into junction `point` by
## arm `arm` the turns `turns`, or with none, M7's again.
func set_arrows(lanes: Object, point: Vector2, arm: Vector2i, lane: int, turns: Array) -> String:
	if arm not in lanes.arms(point):
		return "No road there"
	if lane < 0 or lane >= lanes.approach(point, arm).size():
		return "No such lane"
	if not turns.all(func(turn: Variant) -> bool: return turn in TURNS):
		return "Lanes turn left, straight or right"
	if turns.is_empty():
		arrows.get(point, {}).get(arm, {}).erase(lane)
	else:
		arrows.get_or_add(point, {}).get_or_add(arm, {})[lane] = turns.duplicate()
	version += 1
	return ""


func to_dict() -> Dictionary:
	return {"signals": signals.duplicate(true), "signs": signs.duplicate(true), "arrows": arrows.duplicate(true)}


static func from_dict(d: Dictionary, traffic_rules: Dictionary) -> Junctions:
	var junctions := Junctions.new(traffic_rules)
	junctions.signals = d.signals.duplicate(true)
	junctions.signs = d.signs.duplicate(true)
	junctions.arrows = d.arrows.duplicate(true)
	return junctions
