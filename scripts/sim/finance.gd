class_name Finance
extends RefCounted
## Loans and the bailout. Loans come from rules.loans and are paid back
## daily through the ledger. When cash stays below zero for
## rules.bailout.days midnights, a bailout clears the debt at a cost in
## reputation and blocks new loans for a while. There is no game over.

var rules: Dictionary
## Loans being paid back: {"kind", "owed", "payment", "days_left"}.
var loans: Array[Dictionary] = []
## Midnights in a row that ended with cash below zero.
var days_negative := 0
## No new loans before this calendar minute.
var blocked_until := 0.0


func _init(game_rules: Dictionary) -> void:
	rules = game_rules


func loan_error(kind: String, now: float) -> String:
	if not rules.loans.has(kind):
		return "Unknown loan: %s" % kind
	if loans.size() >= rules.max_loans:
		return "Pay back a loan first: %d at once at most" % rules.max_loans
	if now < blocked_until:
		return "No lender will touch the port until day %d after its bailout" % int(blocked_until / SimClock.MINUTES_PER_DAY)
	return ""


## Borrows a loan of `kind` into the ledger. The amount plus interest at the
## yearly rate over the term is paid back in equal daily payments.
func take_loan(kind: String, now: float, ledger: Ledger) -> String:
	var err := loan_error(kind, now)
	if err != "":
		return err
	var terms: Dictionary = rules.loans[kind]
	var owed: int = terms.amount + roundi(terms.amount * terms.yearly_rate * terms.days / 365.0)
	loans.append({"kind": kind, "owed": owed, "payment": ceili(owed / float(terms.days)), "days_left": terms.days})
	ledger.post("loans", terms.amount)
	return ""


## Midnight: pays each loan's instalment (the last one pays what is left),
## then counts the days below zero and bails the port out at the limit.
## Returns events to show. `bailouts` is false in creative mode.
func end_of_day(now: float, ledger: Ledger, contracts: Contracts, bailouts: bool) -> Array[String]:
	var said: Array[String] = []
	for loan: Dictionary in loans.duplicate():
		var pay: int = loan.owed if loan.days_left == 1 else mini(loan.payment, loan.owed)
		ledger.post("loan_payments", -pay)
		loan.owed -= pay
		loan.days_left -= 1
		if loan.days_left == 0:
			loans.erase(loan)
			said.append("A %s loan is paid off" % loan.kind)
	days_negative = days_negative + 1 if ledger.cash < 0 else 0
	if bailouts and days_negative >= rules.bailout.days:
		days_negative = 0
		ledger.post("bailout", -ledger.cash)
		blocked_until = now + rules.bailout.no_loans_days * SimClock.MINUTES_PER_DAY
		for line: String in contracts.reputation:
			var cancelled := contracts.penalise(line, rules.bailout.reputation)
			if cancelled != "":
				said.append(cancelled)
		said.append("The port was bailed out of its debt; lines think less of it, and lenders stay away for %d days" % rules.bailout.no_loans_days)
	return said


func to_dict() -> Dictionary:
	return {"loans": loans.duplicate(true), "days_negative": days_negative, "blocked_until": blocked_until}


static func from_dict(d: Dictionary, game_rules: Dictionary) -> Finance:
	var finance := Finance.new(game_rules)
	finance.loans.assign(d.loans)
	finance.days_negative = d.days_negative
	finance.blocked_until = d.blocked_until
	return finance
