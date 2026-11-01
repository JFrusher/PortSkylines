class_name Ledger
extends RefCounted
## The port's books. post() is the only way cash changes, so each game day's
## lines add up to exactly that day's change in cash.

## How many closed days are kept for the ledger panel.
const DAYS_KEPT := 7

## Category key -> label, from rules.ledger_categories.
var categories: Dictionary
var cash := 0
## Cash when the current day opened.
var opened := 0
## Today's totals by category.
var today := {}
## Today's totals by terminal, then category; terminal 0 is the port as a
## whole (roads, land, loans, dredging). They add up to `today`.
var terminals := {}
## Today's crane moves: {"total", "lines": line -> [moves, income],
## "terminals": terminal -> [moves, income]}.
var moves := _no_moves()
## Closed days, newest last: {"day", "opened", "closed", "lines", "terminals", "moves"}.
var days: Array[Dictionary] = []


func _init(category_labels: Dictionary, start_cash: int) -> void:
	categories = category_labels
	cash = start_cash
	opened = start_cash


## Adds `amount` (negative to spend) to cash under `category`, in
## `terminal`'s section (0 for the port as a whole).
func post(category: String, amount: int, terminal := 0) -> void:
	if not categories.has(category):
		push_error("Unknown ledger category: %s" % category)
		assert(false, "Unknown ledger category, see the error above")
	cash += amount
	today[category] = today.get(category, 0) + amount
	var section: Dictionary = terminals.get_or_add(terminal, {})
	section[category] = section.get(category, 0) + amount


## Counts a crane move for `line` in `terminal` that earned `income`.
func count_move(line: String, terminal: int, income: int) -> void:
	moves.total += 1
	for key: Array in [["lines", line], ["terminals", terminal]]:
		var tally: Array = moves[key[0]].get(key[1], [0, 0])
		moves[key[0]][key[1]] = [tally[0] + 1, tally[1] + income]


static func _no_moves() -> Dictionary:
	return {"total": 0, "lines": {}, "terminals": {}}


## Closes the day `day` and opens the next.
func close_day(day: int) -> void:
	days.append({"day": day, "opened": opened, "closed": cash, "lines": today, "terminals": terminals, "moves": moves})
	if days.size() > DAYS_KEPT:
		days.pop_front()
	today = {}
	terminals = {}
	moves = _no_moves()
	opened = cash


## The sum of today's lines; equals cash - opened while all cash goes through post().
func today_total() -> int:
	var total := 0
	for category: String in today:
		total += today[category]
	return total


func to_dict() -> Dictionary:
	return {"cash": cash, "opened": opened, "today": today.duplicate(), "terminals": terminals.duplicate(true), "moves": moves.duplicate(true), "days": days.duplicate(true)}


static func from_dict(d: Dictionary, category_labels: Dictionary) -> Ledger:
	var ledger := Ledger.new(category_labels, d.cash)
	ledger.opened = d.opened
	ledger.today = d.today.duplicate()
	ledger.terminals = d.terminals.duplicate(true)
	ledger.moves = d.moves.duplicate(true)
	ledger.days.assign(d.days)
	return ledger
