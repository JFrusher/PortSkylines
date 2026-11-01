extends SceneTree
## Tests for HudDetails formatting, KPI cards and figure groups.
## godot --headless --script res://tests/test_hud_details.gd

const RandomPort := preload("res://tests/random_port.gd")
const HudDetails := preload("res://scripts/hud_details.gd")

var _failures := 0


func _initialize() -> void:
	_test_formatters()
	_test_figure_groups()
	_test_port_kpis()
	print("tests: %d failure(s)" % _failures)
	quit(1 if _failures else 0)


func _expect(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL %s: got %s, want %s" % [what, actual, expected])


func _test_formatters() -> void:
	_expect(HudDetails.dollars(1250000), "$1,250,000", "dollars positive")
	_expect(HudDetails.dollars(-450), "-$450", "dollars negative")
	_expect(HudDetails.dollars(0), "$0", "dollars zero")
	_expect(HudDetails.signed(500), "+$500", "signed positive")
	_expect(HudDetails.signed(-250), "-$250", "signed negative")
	_expect(HudDetails.signed(0), "$0", "signed zero")
	_expect(HudDetails.percent(0.854), "85%", "percent")
	_expect(HudDetails.yard_state(0.5), "good", "yard good")
	_expect(HudDetails.yard_state(0.75), "warn", "yard warn")
	_expect(HudDetails.yard_state(0.95), "danger", "yard danger")


func _test_figure_groups() -> void:
	var sim := PortSim.new(42, RandomPort.strait())
	for group: String in HudDetails.GROUPS:
		var cards := HudDetails.cards_for(group, sim)
		_expect(cards.size() >= 3, true, "%s has cards (%d)" % [group, cards.size()])
		var rows := HudDetails.rows_for(group, sim)
		_expect(rows.size() >= 3, true, "%s has rows (%d)" % [group, rows.size()])
	var ledger := HudDetails.ledger_text(sim)
	_expect(ledger.contains("Today") or ledger.contains("Creative"), true, "ledger text has Today/Creative")


func _test_port_kpis() -> void:
	var sim := PortSim.new(42, RandomPort.strait())
	var kpis: Array[Dictionary] = HudDetails.port_kpis(sim)
	_expect(kpis.size(), 6, "port_kpis returns 6 cards")
	for card: Dictionary in kpis:
		_expect(card.has("label") and card.has("value"), true, "kpi card has label and value")
