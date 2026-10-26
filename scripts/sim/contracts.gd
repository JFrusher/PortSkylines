class_name Contracts
extends RefCounted
## Shipping lines, the weekly services the port has agreed with them, the
## services they are offering, and each line's reputation of the port. Lines
## offer services while their reputation and the port's berths allow, and
## cancel one when the port lets them down too often.

const MINUTES_PER_WEEK := SimClock.MINUTES_PER_DAY * 7

var rules: Dictionary
## Line key -> 0..100.
var reputation := {}
## Agreed weekly calls: {"id", "line", "kind", "start" (minute of the week),
## "window_hours", "moves"}.
var services: Array[Dictionary] = []
## Services on offer: as above, plus "expires" (a calendar minute).
var offers: Array[Dictionary] = []
## Goes up on every change, so a panel knows when to redraw.
var version := 0

var _next_id := 1


func _init(game_rules: Dictionary) -> void:
	rules = game_rules
	for line: String in rules.lines:
		reputation[line] = float(rules.reputation.start)


## Maybe offers one new service: from a line whose reputation is high enough,
## for a class `fits` says the port can berth, while there are fewer than
## `berths` × max_services_per_berth services, more often as the
## hinterland's `demand` grows. Returns the offer or {}.
func offer(rng: RandomNumberGenerator, now: float, berths: int, fits: Callable, demand: float) -> Dictionary:
	var terms: Dictionary = rules.contracts
	if offers.size() >= terms.max_offers or services.size() + offers.size() >= berths * terms.max_services_per_berth:
		return {}
	if rng.randf() >= terms.offer_chance * demand:
		return {}
	var willing: Array = rules.lines.keys().filter(func(line: String) -> bool: return reputation[line] >= rules.reputation.offer_above)
	if willing.is_empty():
		return {}
	var line: String = willing[rng.randi_range(0, willing.size() - 1)]
	var kind := _pick(rng, rules.lines[line].classes)
	if not fits.call(kind):
		return {}
	var spec: Dictionary = rules.ship_classes[kind]
	var service := {
		"id": _next_id, "line": line, "kind": kind,
		# Whole hours, so every call starts exactly on a tick.
		"start": _quietest_hour(now) * 60,
		"window_hours": spec.window_hours,
		"moves": spec.import_moves + spec.export_moves,
		"expires": now + terms.offer_days * SimClock.MINUTES_PER_DAY,
	}
	_next_id += 1
	offers.append(service)
	version += 1
	return service


## The hour of the week for a new service's calls: the one furthest from
## every call already agreed or on offer, as a terminal plans its berth
## windows, at least 2 h ahead; the soonest of equals, so a port's first
## service calls soon.
func _quietest_hour(now: float) -> int:
	var week := 7 * 24
	var booked := (services + offers).map(func(s: Dictionary) -> int: return s.start / 60)
	var best := 0
	var widest := -1
	for ahead in range(2, week + 2):
		var hour := (floori(now / 60.0) + ahead) % week
		var gap := week
		for other: int in booked:
			gap = mini(gap, mini(absi(hour - other), week - absi(hour - other)))
		if gap > widest:
			best = hour
			widest = gap
	return best


func accept_error(id: int) -> String:
	return "" if _offer(id) else "No such offer"


func accept(id: int) -> String:
	var err := accept_error(id)
	if err == "":
		var service := _offer(id)
		offers.erase(service)
		service.erase("expires")
		services.append(service)
		version += 1
	return err


func decline(id: int) -> String:
	var service := _offer(id)
	if service.is_empty():
		return "No such offer"
	offers.erase(service)
	version += 1
	return ""


func expire(now: float) -> void:
	var before := offers.size()
	offers = offers.filter(func(o: Dictionary) -> bool: return o.expires > now)
	if offers.size() != before:
		version += 1


## The services whose call starts on tick `tick_of_week` of the week.
func due(tick_of_week: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for service in services:
		if roundi(service.start / SimClock.CALENDAR_MINUTES_PER_TICK) == tick_of_week:
			found.append(service)
	return found


## What one call of `service` earns on average, from move prices and the box mix.
func call_value(service: Dictionary) -> int:
	var price: Dictionary = rules.move_price
	var per_move: float = price.per_20ft * lerpf(1.0, price.forty_factor, rules.box_mix.forty_share) + price.reefer_premium * rules.box_mix.reefer_share
	return roundi(service.moves * per_move)


## The agreed services, other than `service`, whose weekly window overlaps its own.
func overlaps(service: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for other in services:
		var ahead := fposmod(other.start - service.start, MINUTES_PER_WEEK)
		var behind := fposmod(service.start - other.start, MINUTES_PER_WEEK)
		if other.id != service.id and (ahead < service.window_hours * 60.0 or behind < other.window_hours * 60.0):
			found.append(other)
	return found


## Scores a finished call for its line, plus `other` (such as shippers'
## view of storage fees). Returns an event to show, or "".
func called(line: String, late_hours: float, moves_per_hour: float, turn_minutes: float, other := 0.0) -> String:
	var weights: Dictionary = rules.reputation
	var change: float = other + (weights.on_time if late_hours == 0.0 else weights.late_per_hour * late_hours)
	change += weights.per_move_per_hour * (moves_per_hour - weights.moves_per_hour_target)
	if turn_minutes > 0.0:
		change += weights.per_turn_minute * (turn_minutes - weights.turn_target_minutes)
	return _change(line, change)


## A call the port could not take at all.
func missed(line: String) -> String:
	return _change(line, rules.reputation.missed)


## Any other knock to a line's opinion, such as a bailout.
func penalise(line: String, change: float) -> String:
	return _change(line, change)


func name_of(line: String) -> String:
	return rules.lines[line].name


func to_dict() -> Dictionary:
	return {"reputation": reputation.duplicate(), "services": services.duplicate(true), "offers": offers.duplicate(true), "next_id": _next_id}


static func from_dict(d: Dictionary, game_rules: Dictionary) -> Contracts:
	var contracts := Contracts.new(game_rules)
	# Lines added to the data since the save keep their starting reputation.
	for line: String in d.reputation:
		if contracts.reputation.has(line):
			contracts.reputation[line] = d.reputation[line]
	contracts.services.assign(d.services)
	contracts.offers.assign(d.offers)
	contracts._next_id = d.next_id
	return contracts


func _change(line: String, change: float) -> String:
	reputation[line] = clampf(reputation[line] + change * rules.lines[line].sensitivity, 0.0, 100.0)
	version += 1
	if reputation[line] >= rules.reputation.cancel_below:
		return ""
	var theirs := services.filter(func(s: Dictionary) -> bool: return s.line == line)
	if theirs.is_empty():
		return ""
	services.erase(theirs[-1])
	return "%s cancelled a weekly %s service: its reputation of the port fell to %d" % [name_of(line), theirs[-1].kind, roundi(reputation[line])]


func _offer(id: int) -> Dictionary:
	for service in offers:
		if service.id == id:
			return service
	return {}


static func _pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for key: String in weights:
		total += weights[key]
	var pick := rng.randf() * total
	for key: String in weights:
		pick -= weights[key]
		if pick < 0.0:
			return key
	return weights.keys()[-1]
