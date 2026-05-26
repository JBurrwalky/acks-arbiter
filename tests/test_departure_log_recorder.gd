extends "res://tests/test_suite_base.gd"

## Phase 11A unit tests for DepartureLogRecorder (migration 121).
##
## Covers: record / get_entry / list_for_domain / list_for_campaign,
## ordering (most-recent first), invalid event_type rejection,
## campaign/domain isolation, JSON normalization on read, and the
## three export formats.

const TEST_CAMPAIGN := "test_dlog_campaign"
const OTHER_CAMPAIGN := "test_dlog_other_campaign"
const DOMAIN_A := "test_dlog_domain_a"
const DOMAIN_B := "test_dlog_domain_b"


func run_all_tests() -> void:
	_cleanup()
	_setup_campaigns()
	test_record_roundtrip()
	test_record_rejects_invalid_event_type()
	test_record_rejects_empty_campaign_or_domain()
	test_list_for_domain_orders_most_recent_first()
	test_list_for_domain_limit_caps_results()
	test_list_for_campaign_isolates_other_campaign()
	test_get_entry_normalizes_json()
	test_emits_departure_log_entry_recorded_signal()
	test_export_markdown_includes_summary_and_details()
	test_export_json_is_valid()
	test_export_txt_is_tab_separated()
	test_valid_event_types_matches_check_constraint()
	_cleanup()
	if not has_failures():
		print("DepartureLogRecorder: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup_campaigns() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "DLog Test"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[OTHER_CAMPAIGN, "DLog Test — Other"])


func _cleanup() -> void:
	for c in [TEST_CAMPAIGN, OTHER_CAMPAIGN]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_departure_log WHERE campaign_id = ?", [c])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM campaigns WHERE id = ?", [c])


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_record_roundtrip() -> void:
	var id := DepartureLogRecorder.record(
		TEST_CAMPAIGN, DOMAIN_A, 100, "established",
		"Founded by grant", {"founder_id": "pc_1", "method": "grant"})
	check(not id.is_empty(), "record returned an id")
	var row: Dictionary = DepartureLogRecorder.get_entry(id)
	check(not row.is_empty(), "get_entry returned the row")
	check(String(row.get("domain_id", "")) == DOMAIN_A,
		"domain_id roundtripped, got %s" % String(row.get("domain_id", "")))
	check(int(row.get("calendar_day", 0)) == 100,
		"calendar_day roundtripped, got %d" % int(row.get("calendar_day", 0)))
	check(String(row.get("event_type", "")) == "established",
		"event_type roundtripped, got %s" % String(row.get("event_type", "")))
	check(String(row.get("summary", "")) == "Founded by grant",
		"summary roundtripped, got %s" % String(row.get("summary", "")))
	var details: Dictionary = row.get("full_details", {})
	check(String(details.get("founder_id", "")) == "pc_1",
		"detail founder_id roundtripped, got %s" % String(details.get("founder_id", "")))


func test_record_rejects_invalid_event_type() -> void:
	var id := DepartureLogRecorder.record(
		TEST_CAMPAIGN, DOMAIN_A, 101, "not_a_real_event_type",
		"Should fail", {})
	check(id.is_empty(), "invalid event_type returns empty id (got '%s')" % id)


func test_record_rejects_empty_campaign_or_domain() -> void:
	check(DepartureLogRecorder.record("", DOMAIN_A, 102, "established", "x", {}).is_empty(),
		"empty campaign_id rejected")
	check(DepartureLogRecorder.record(TEST_CAMPAIGN, "", 102, "established", "x", {}).is_empty(),
		"empty domain_id rejected")


func test_list_for_domain_orders_most_recent_first() -> void:
	var d := "test_dlog_order_domain"
	DepartureLogRecorder.record(TEST_CAMPAIGN, d, 100, "established", "Day 100", {})
	DepartureLogRecorder.record(TEST_CAMPAIGN, d, 300, "calamity", "Day 300", {})
	DepartureLogRecorder.record(TEST_CAMPAIGN, d, 200, "morale_tier_dropped", "Day 200", {})
	var rows: Array = DepartureLogRecorder.list_for_domain(d)
	check(rows.size() == 3, "list returned 3 rows, got %d" % rows.size())
	check(int(rows[0].get("calendar_day", 0)) == 300,
		"most-recent first: row 0 is day 300, got %d" % int(rows[0].get("calendar_day", 0)))
	check(int(rows[1].get("calendar_day", 0)) == 200,
		"day 200 second, got %d" % int(rows[1].get("calendar_day", 0)))
	check(int(rows[2].get("calendar_day", 0)) == 100,
		"day 100 last, got %d" % int(rows[2].get("calendar_day", 0)))


func test_list_for_domain_limit_caps_results() -> void:
	var d := "test_dlog_limit_domain"
	for day in [100, 200, 300, 400, 500]:
		DepartureLogRecorder.record(TEST_CAMPAIGN, d, day, "calamity", "Day %d" % day, {})
	var rows: Array = DepartureLogRecorder.list_for_domain(d, 2)
	check(rows.size() == 2, "limit=2 caps results, got %d" % rows.size())
	check(int(rows[0].get("calendar_day", 0)) == 500,
		"limit keeps most-recent, got day %d" % int(rows[0].get("calendar_day", 0)))


func test_list_for_campaign_isolates_other_campaign() -> void:
	DepartureLogRecorder.record(TEST_CAMPAIGN, "test_dlog_iso_d1", 100,
		"established", "in TEST", {})
	DepartureLogRecorder.record(OTHER_CAMPAIGN, "test_dlog_iso_d2", 100,
		"established", "in OTHER", {})
	var test_rows: Array = DepartureLogRecorder.list_for_campaign(TEST_CAMPAIGN)
	var other_rows: Array = DepartureLogRecorder.list_for_campaign(OTHER_CAMPAIGN)
	# All test_rows must reference TEST_CAMPAIGN.
	var test_ok := true
	for r in test_rows:
		if String(r.get("campaign_id", "")) != TEST_CAMPAIGN:
			test_ok = false
			break
	check(test_ok, "list_for_campaign(TEST) does not leak OTHER rows")
	var other_ok := true
	for r in other_rows:
		if String(r.get("campaign_id", "")) != OTHER_CAMPAIGN:
			other_ok = false
			break
	check(other_ok, "list_for_campaign(OTHER) does not leak TEST rows")


func test_get_entry_normalizes_json() -> void:
	var id := DepartureLogRecorder.record(
		TEST_CAMPAIGN, "test_dlog_norm_domain", 100, "established",
		"normalize me", {"a": 1, "b": "two"},
		["led_1", "led_2"], ["enc_1"])
	var row: Dictionary = DepartureLogRecorder.get_entry(id)
	var details: Dictionary = row.get("full_details", {})
	check(int(details.get("a", 0)) == 1, "details.a=1 normalized")
	check(String(details.get("b", "")) == "two", "details.b='two' normalized")
	var ledger_ids: Array = row.get("related_ledger_entry_ids_array", [])
	check(ledger_ids.size() == 2 and String(ledger_ids[0]) == "led_1",
		"related_ledger_entry_ids_array normalized")
	var enc_ids: Array = row.get("related_encounter_ids_array", [])
	check(enc_ids.size() == 1 and String(enc_ids[0]) == "enc_1",
		"related_encounter_ids_array normalized")


var _signal_received_count: int = 0
var _signal_last_payload: Dictionary = {}

func test_emits_departure_log_entry_recorded_signal() -> void:
	_signal_received_count = 0
	_signal_last_payload = {}
	if not EventBus.departure_log_entry_recorded.is_connected(_on_recorded_for_test):
		EventBus.departure_log_entry_recorded.connect(_on_recorded_for_test)
	var id := DepartureLogRecorder.record(
		TEST_CAMPAIGN, "test_dlog_signal_d", 100, "established",
		"signal test", {})
	check(_signal_received_count == 1, "signal fired once, got %d" % _signal_received_count)
	check(String(_signal_last_payload.get("domain_id", "")) == "test_dlog_signal_d",
		"signal carried domain_id")
	check(String(_signal_last_payload.get("entry_id", "")) == id,
		"signal carried the new entry_id")
	check(String(_signal_last_payload.get("event_type", "")) == "established",
		"signal carried event_type")
	EventBus.departure_log_entry_recorded.disconnect(_on_recorded_for_test)


func _on_recorded_for_test(domain_id: String, entry_id: String, event_type: String) -> void:
	_signal_received_count += 1
	_signal_last_payload = {
		"domain_id": domain_id, "entry_id": entry_id, "event_type": event_type,
	}


func test_export_markdown_includes_summary_and_details() -> void:
	var d := "test_dlog_md_domain"
	DepartureLogRecorder.record(TEST_CAMPAIGN, d, 100, "established",
		"My great founding", {"founder_id": "pc_1"})
	var md := DepartureLogRecorder.export_as_markdown(d)
	check(md.contains("# Domain Departure Log"), "markdown has header")
	check(md.contains("Day 100"), "markdown has day")
	check(md.contains("established"), "markdown has event_type")
	check(md.contains("My great founding"), "markdown has summary")
	check(md.contains("founder_id"), "markdown has detail key")


func test_export_json_is_valid() -> void:
	var d := "test_dlog_json_domain"
	DepartureLogRecorder.record(TEST_CAMPAIGN, d, 100, "established", "x", {})
	var json_str := DepartureLogRecorder.export_as_json(d)
	var parsed: Variant = JSON.parse_string(json_str)
	check(parsed is Array, "export_as_json returns valid JSON array")
	check((parsed as Array).size() >= 1, "export contains at least one row")


func test_export_txt_is_tab_separated() -> void:
	var d := "test_dlog_txt_domain"
	DepartureLogRecorder.record(TEST_CAMPAIGN, d, 100, "established", "x", {})
	var txt := DepartureLogRecorder.export_as_txt(d)
	check(txt.contains("calendar_day\tevent_type\tsummary"),
		"txt has tab-separated header")
	check(txt.contains("100\testablished\tx"),
		"txt has tab-separated row")


func test_valid_event_types_matches_check_constraint() -> void:
	# Smoke: every value in VALID_EVENT_TYPES must actually be acceptable to
	# the migration 121 CHECK constraint. We can't read the constraint
	# directly, but we can try to insert each and verify success.
	for et in DepartureLogRecorder.VALID_EVENT_TYPES:
		var id := DepartureLogRecorder.record(
			TEST_CAMPAIGN, "test_dlog_etype_d", 1, String(et), "", {})
		check(not id.is_empty(),
			"VALID_EVENT_TYPES '%s' accepted by CHECK constraint" % String(et))
