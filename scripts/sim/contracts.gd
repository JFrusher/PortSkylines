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
## "window_hours", "moves", "apron" (the berth it calls at, 0 for none yet),
## "asked" (the start the line asked for; start stays within flex_hours of
## it), "any_berth" (whether its ship takes another berth when its own is busy)}.
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


## Maybe offers one new service for berth `apron`: from a line whose
## reputation is high enough, for a class `fits` says that berth can take,
## while the berth has fewer than max_services_per_berth services and offers,
## more often as the hinterland's `demand` grows. Returns the offer or {}.
func offer(rng: RandomNumberGenerator, now: float, apron: int, fits: Callable, demand: float) -> Dictionary:
	var terms: Dictionary = rules.contracts
	if offers.size() >= terms.max_offers or booked(apron).size() >= terms.max_services_per_berth:
		return {}
	# A port with no lines yet gets its first offer at the first check.
	if rng.randf() >= (1.0 if services.is_empty() and offers.is_empty() else terms.offer_chance * demand):
		return {}
	var willing: Array = rules.lines.keys().filter(func(line: String) -> bool: return reputation[line] >= rules.reputation.offer_above)
	if willing.is_empty():
		return {}
	var line: String = willing[rng.randi_range(0, willing.size() - 1)]
	# A line offers only classes the berth can take, by its weights among them.
	var classes := {}
	for kind: String in rules.lines[line].classes:
		if fits.call(kind):
			classes[kind] = rules.lines[line].classes[kind]
	if classes.is_empty():
		return {}
	var kind := _pick(rng, classes)
	var spec: Dictionary = rules.ship_classes[kind]
	# Whole hours, so every call starts exactly on a tick.
	var start := _quietest_hour(now, apron) * 60
	var service := {
		"id": _next_id, "line": line, "kind": kind, "start": start,
		"window_hours": spec.window_hours,
		"moves": spec.import_moves + spec.export_moves,
		"apron": apron, "asked": start, "any_berth": false,
		"expires": now + terms.offer_days * SimClock.MINUTES_PER_DAY,
	}
	_next_id += 1
	offers.append(service)
	version += 1
	return service


## The services agreed or on offer for berth `apron`.
func booked(apron: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for service in services + offers:
		if service.apron == apron:
			found.append(service)
	return found


## The hour of the week for a new service's calls at berth `apron`: the one
## furthest from every call already agreed or on offer there, as a terminal
## plans its berth windows, at least 2 h ahead; the soonest of equals, so a
## berth's first service calls soon.
func _quietest_hour(now: float, apron: int) -> int:
	var week := 7 * 24
	var hours := booked(apron).map(func(s: Dictionary) -> int: return s.start / 60)
	var best := 0
	var widest := -1
	for ahead in range(2, week + 2):
		var hour := (floori(now / 60.0) + ahead) % week
		var gap := week
		for other: int in hours:
			gap = mini(gap, mini(absi(hour - other), week - absi(hour - other)))
		if gap > widest:
			best = hour
			widest = gap
	return best


## Where `service`'s calls would start at berth `apron`: the hour nearest the
## line's asked start, within flex_hours of it, whose window overlaps no other
## agreed service there; -1 when none is free.
func place(service: Dictionary, apron: int) -> int:
	var flex: int = rules.contracts.flex_hours
	for step in range(0, flex * 2 + 1):
		# 0, +1 h, -1 h, +2 h, -2 h, ...
		var shift := floori((step + 1) / 2.0) * (1 if step % 2 == 1 else -1)
		var tried := service.duplicate()
		tried.start = posmod(service.asked + shift * 60, MINUTES_PER_WEEK)
		if not services.any(func(other: Dictionary) -> bool: return other.id != service.id and other.apron == apron and windows_overlap(tried, other)):
			return tried.start
	return -1


func accept_error(id: int, apron: int) -> String:
	var service := _offer(id)
	if service.is_empty():
		return "No such offer"
	return "" if place(service, apron) != -1 else _no_window()


## Agrees offer `id` with its calls at berth `apron`, as `place` times them.
func accept(id: int, apron: int) -> String:
	var err := accept_error(id, apron)
	if err == "":
		var service := _offer(id)
		service.start = place(service, apron)
		service.apron = apron
		offers.erase(service)
		service.erase("expires")
		services.append(service)
		version += 1
	return err


func move_error(id: int, apron: int) -> String:
	var service := _service(id)
	if service.is_empty():
		return "No such service"
	return "" if place(service, apron) != -1 else _no_window()


## Moves agreed service `id`'s calls to berth `apron`, as `place` times them.
func move(id: int, apron: int) -> String:
	var err := move_error(id, apron)
	if err == "":
		var service := _service(id)
		service.start = place(service, apron)
		service.apron = apron
		version += 1
	return err


## Whether service `id`'s ship takes another berth when its own is busy.
func set_any_berth(id: int, any: bool) -> String:
	var service := _service(id)
	if service.is_empty():
		return "No such service"
	service.any_berth = any
	version += 1
	return ""


func _no_window() -> String:
	return "No free window on this berth within %d h of the line's time" % rules.contracts.flex_hours


func _service(id: int) -> Dictionary:
	for service in services:
		if service.id == id:
			return service
	return {}


func decline(id: int) -> String:
	var service := _offer(id)
	if service.is_empty():
		return "No such offer"
	offers.erase(service)
	version += 1
	return ""


## Ends agreed service `id` at the port's wish; its line thinks less of the
## port by port_cancels. Returns "" and the line's notice, if that knock makes
## it cancel a service of its own, or ["No such service", ""].
func cancel(id: int) -> Array[String]:
	var service := _service(id)
	if service.is_empty():
		return ["No such service", ""] as Array[String]
	services.erase(service)
	version += 1
	return ["", _change(service.line, rules.reputation.port_cancels)] as Array[String]


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
		if other.id != service.id and windows_overlap(service, other):
			found.append(other)
	return found


## Whether two services' weekly windows overlap, around the week's end too.
static func windows_overlap(a: Dictionary, b: Dictionary) -> bool:
	return fposmod(b.start - a.start, MINUTES_PER_WEEK) < a.window_hours * 60.0 or fposmod(a.start - b.start, MINUTES_PER_WEEK) < b.window_hours * 60.0


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
