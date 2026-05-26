extends "res://tests/test_suite_base.gd"

## Phase 11A: verify DepartureLogRecorder.record_monthly_transitions
## writes the right log entry for a classification advancement / regression
## detected by the monthly tick.
##
## The hook is driven by the result-dict shape returned by
## DomainHandlers._resolve_domain_month, not by running the whole monthly
## tick — we synthesize a result dict to keep the test fast and focused.

const TEST_CAMPAIGN := "test_dlog_class_campaign"
const DOMAIN := "test_dlog_class_domain"


func run_all_tests() -> void:
	_cleanup()
	_setup()
	test_advance_writes_log_entry()
	test_regress_writes_log_entry()
	test_no_change_writes_nothing()
	test_payload_carries_from_to_reason()
	_cleanup()
	if not has_failures():
		print("DepartureLogClassificationHook: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "DLog Class Test"])


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _make_domain(territory_type: String) -> Dictionary:
	return {
		"id": DOMAIN,
		"campaign_id": TEST_CAMPAIGN,
		"territory_type": territory_type,
		"peasant_families": 2000,
		"morale": 1,
	}


func _make_advancement_result(new_class: String, reason: String) -> Dictionary:
	return {
		"classification_change": {
			"advanced": true, "regressed": false,
			"new_classification": new_class,
			"reason": reason,
		},
		"population_growth": 0,
		"current_morale": 1,
	}


func _make_regression_result(new_class: String, reason: String) -> Dictionary:
	return {
		"classification_change": {
			"advanced": false, "regressed": true,
			"new_classification": new_class,
			"reason": reason,
		},
		"population_growth": 0,
		"current_morale": 1,
	}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_advance_writes_log_entry() -> void:
	var domain := _make_domain("wilderness")
	var result := _make_advancement_result("borderlands", "Saturation + 72mi range.")
	var written := DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	check(written >= 1, "at least one entry written, got %d" % written)
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN)
	var advance_count := 0
	for r in rows:
		if String(r.get("event_type", "")) == "classification_advanced":
			advance_count += 1
	check(advance_count == 1, "exactly one classification_advanced row, got %d" % advance_count)


func test_regress_writes_log_entry() -> void:
	_cleanup()
	_setup()
	var domain := _make_domain("civilized")
	var result := _make_regression_result("borderlands", "Outside 48mi range.")
	DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN)
	var regress_count := 0
	for r in rows:
		if String(r.get("event_type", "")) == "classification_regressed":
			regress_count += 1
	check(regress_count == 1, "exactly one classification_regressed row, got %d" % regress_count)


func test_no_change_writes_nothing() -> void:
	_cleanup()
	_setup()
	var domain := _make_domain("wilderness")
	var result := {
		"classification_change": {
			"advanced": false, "regressed": false,
			"new_classification": "wilderness",
			"reason": "",
		},
		"population_growth": 0,
		"current_morale": 1,
	}
	var written := DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	check(written == 0, "no entry for no-change month, got %d" % written)


func test_payload_carries_from_to_reason() -> void:
	_cleanup()
	_setup()
	var domain := _make_domain("wilderness")
	var result := _make_advancement_result("borderlands", "Hexes saturated.")
	DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN)
	check(rows.size() >= 1, "row written, got %d rows" % rows.size())
	var row: Dictionary = rows[0]
	var details: Dictionary = row.get("full_details", {})
	check(String(details.get("from", "")) == "wilderness",
		"detail.from carries old class, got %s" % String(details.get("from", "")))
	check(String(details.get("to", "")) == "borderlands",
		"detail.to carries new class, got %s" % String(details.get("to", "")))
	check(String(details.get("reason", "")) == "Hexes saturated.",
		"detail.reason carries reason, got %s" % String(details.get("reason", "")))
