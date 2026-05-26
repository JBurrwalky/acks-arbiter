extends "res://tests/test_suite_base.gd"

## Phase 11A: verify DepartureLogRecorder.record_monthly_transitions
## writes a morale_tier_dropped entry only when the named tier transitions
## downward. Single-tier moves and intra-tier drops are no-ops.

const TEST_CAMPAIGN := "test_dlog_morale_campaign"
const DOMAIN := "test_dlog_morale_domain"


func run_all_tests() -> void:
	_cleanup()
	_setup()
	test_loyal_to_apathetic_logs()
	test_apathetic_to_demoralized_logs()
	test_rebellious_to_rebellious_intra_tier_drop_no_log()
	test_recovery_no_log()
	test_no_morale_change_no_log()
	test_payload_carries_tier_names_and_morale_values()
	_cleanup()
	if not has_failures():
		print("DepartureLogMoraleTierHook: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "DLog Morale Test"])


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_departure_log WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _no_class_change() -> Dictionary:
	return {
		"advanced": false, "regressed": false,
		"new_classification": "wilderness",
		"reason": "",
	}


func _make_result(prior_morale: int, new_morale: int) -> Dictionary:
	return {
		"classification_change": _no_class_change(),
		"population_growth": 0,
		"current_morale": new_morale,
	}


func _make_domain(prior_morale: int) -> Dictionary:
	return {
		"id": DOMAIN,
		"campaign_id": TEST_CAMPAIGN,
		"territory_type": "wilderness",
		"peasant_families": 100,
		"morale": prior_morale,
	}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_loyal_to_apathetic_logs() -> void:
	_cleanup(); _setup()
	# Loyal (+1) → Apathetic (0): named tier changes, downward → log.
	var domain := _make_domain(1)
	var result := _make_result(1, 0)
	DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN)
	check(rows.size() == 1, "exactly one log entry, got %d" % rows.size())
	check(String(rows[0].get("event_type", "")) == "morale_tier_dropped",
		"event_type=morale_tier_dropped, got %s" % String(rows[0].get("event_type", "")))


func test_apathetic_to_demoralized_logs() -> void:
	_cleanup(); _setup()
	# Apathetic (0) → Demoralized (-1).
	var domain := _make_domain(0)
	var result := _make_result(0, -1)
	DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN)
	check(rows.size() == 1, "exactly one log entry, got %d" % rows.size())


func test_rebellious_to_rebellious_intra_tier_drop_no_log() -> void:
	_cleanup(); _setup()
	# -5 to -6: both Rebellious — no tier transition, no log.
	var domain := _make_domain(-5)
	var result := _make_result(-5, -6)
	var written := DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	check(written == 0, "intra-tier drop writes nothing, got %d" % written)


func test_recovery_no_log() -> void:
	_cleanup(); _setup()
	# Demoralized → Apathetic: tier changes, but UP. No log entry.
	var domain := _make_domain(-1)
	var result := _make_result(-1, 0)
	var written := DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	check(written == 0, "upward tier change writes nothing, got %d" % written)


func test_no_morale_change_no_log() -> void:
	_cleanup(); _setup()
	var domain := _make_domain(0)
	var result := _make_result(0, 0)
	var written := DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	check(written == 0, "no morale change writes nothing, got %d" % written)


func test_payload_carries_tier_names_and_morale_values() -> void:
	_cleanup(); _setup()
	# Loyal (+1) → Apathetic (0).
	var domain := _make_domain(1)
	var result := _make_result(1, 0)
	DepartureLogRecorder.record_monthly_transitions(
		TEST_CAMPAIGN, domain, result, 500)
	var rows: Array = DepartureLogRecorder.list_for_domain(DOMAIN)
	var details: Dictionary = rows[0].get("full_details", {})
	check(String(details.get("prior_tier", "")) == "Loyal",
		"prior_tier=Loyal, got %s" % String(details.get("prior_tier", "")))
	check(String(details.get("new_tier", "")) == "Apathetic",
		"new_tier=Apathetic, got %s" % String(details.get("new_tier", "")))
	check(int(details.get("prior_morale", -99)) == 1,
		"prior_morale=1, got %d" % int(details.get("prior_morale", -99)))
	check(int(details.get("new_morale", -99)) == 0,
		"new_morale=0, got %d" % int(details.get("new_morale", -99)))
