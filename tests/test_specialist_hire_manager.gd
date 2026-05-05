extends "res://tests/test_suite_base.gd"

## End-to-end test of SpecialistHireManager + CampaignRepository helpers
## (Wilderness closure Phase 6).
##
## Exercises the DB roundtrip — open / list / dismiss — against migration
## 053. Wages are tested through SpecialistHireManager.process_monthly_wages
## with a stub event-bus so we can verify the signal payload.


const PARTY_PREFIX := "test_phase6_specialist_"
const CAMPAIGN_ID := "test_phase6_specialist_campaign"


# ---------------------------------------------------------------------------
# Real-EventBus signal recorder. Connects each Phase 6 signal to a Callable
# that appends to `_emitted`. We can't subclass EventBus and override
# emit_signal (Godot 4 forbids overriding the native method), so we connect
# instead — same observable contract, no type-system fight.
# ---------------------------------------------------------------------------

var _emitted: Array = []


func _record_hired(party_id: String, data: Dictionary) -> void:
	_emitted.append({"signal": "specialist_hired", "args": [party_id, data]})


func _record_dismissed(party_id: String, data: Dictionary) -> void:
	_emitted.append({"signal": "specialist_dismissed", "args": [party_id, data]})


func _record_wages(party_id: String, summary: Dictionary) -> void:
	_emitted.append({"signal": "specialist_wages_processed", "args": [party_id, summary]})


func _connect_recorders() -> void:
	_emitted = []
	if not EventBus.specialist_hired.is_connected(_record_hired):
		EventBus.specialist_hired.connect(_record_hired)
	if not EventBus.specialist_dismissed.is_connected(_record_dismissed):
		EventBus.specialist_dismissed.connect(_record_dismissed)
	if not EventBus.specialist_wages_processed.is_connected(_record_wages):
		EventBus.specialist_wages_processed.connect(_record_wages)


func _disconnect_recorders() -> void:
	if EventBus.specialist_hired.is_connected(_record_hired):
		EventBus.specialist_hired.disconnect(_record_hired)
	if EventBus.specialist_dismissed.is_connected(_record_dismissed):
		EventBus.specialist_dismissed.disconnect(_record_dismissed)
	if EventBus.specialist_wages_processed.is_connected(_record_wages):
		EventBus.specialist_wages_processed.disconnect(_record_wages)


func run_all_tests() -> void:
	test_hire_unknown_kind_returns_empty()
	test_hire_pathfinder_creates_row_and_emits()
	test_hire_then_dismiss_closes_row_and_emits()
	test_list_active_excludes_closed()
	test_bonus_for_db_path_aggregates()
	test_wages_processed_emits_summary_when_no_specialists()
	if not has_failures():
		print("SpecialistHireManager: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _setup_fixture(party_id: String) -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM specialists WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "test phase6 specialists"])
	db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[party_id, CAMPAIGN_ID, "Test Phase 6 Party"])


func _cleanup_fixture(party_id: String) -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM specialists WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_hire_unknown_kind_returns_empty() -> void:
	var pid := PARTY_PREFIX + "unknown"
	_setup_fixture(pid)
	_connect_recorders()
	var manager := SpecialistHireManager.new(CampaignRepository, EventBus)
	var sid: String = manager.hire(CAMPAIGN_ID, pid, "settlement_x", "alchemist")
	check(sid.is_empty(), "unknown kind → empty id, no row created")
	check(_emitted.is_empty(), "unknown kind → no signal emitted")
	_cleanup_fixture(pid)


func test_hire_pathfinder_creates_row_and_emits() -> void:
	var pid := PARTY_PREFIX + "hire"
	_setup_fixture(pid)
	_connect_recorders()
	var manager := SpecialistHireManager.new(CampaignRepository, EventBus)
	var sid: String = manager.hire(CAMPAIGN_ID, pid, "test_settlement",
		"pathfinder", "Sneakytoes", 100)
	check(not sid.is_empty(), "hire returns specialist_id")

	var row: Dictionary = CampaignRepository.get_specialist(sid)
	check(String(row.get("kind", "")) == "pathfinder", "kind persisted")
	check(int(row.get("monthly_wage_gp", 0)) == 25, "wage from catalog")
	check(int(row.get("hired_at_round", -1)) == 100, "hired_at_round persisted")
	check(int(row.get("closed", 1)) == 0, "row open by default")

	check(_emitted.size() == 1, "exactly one signal emitted")
	check(String(_emitted[0]["signal"]) == "specialist_hired",
		"signal name = specialist_hired")
	_cleanup_fixture(pid)


func test_hire_then_dismiss_closes_row_and_emits() -> void:
	var pid := PARTY_PREFIX + "dismiss"
	_setup_fixture(pid)
	_connect_recorders()
	var manager := SpecialistHireManager.new(CampaignRepository, EventBus)
	var sid: String = manager.hire(CAMPAIGN_ID, pid, "settlement", "land_surveyor")
	check(manager.dismiss(sid, pid), "dismiss returns true")

	var row: Dictionary = CampaignRepository.get_specialist(sid)
	check(int(row.get("closed", 0)) == 1, "row closed")
	check(String(row.get("closed_reason", "")) == "dismissed",
		"closed_reason = dismissed")

	# Two signals: hired then dismissed.
	check(_emitted.size() == 2, "two signals emitted")
	check(String(_emitted[1]["signal"]) == "specialist_dismissed",
		"second signal = specialist_dismissed")
	_cleanup_fixture(pid)


func test_list_active_excludes_closed() -> void:
	var pid := PARTY_PREFIX + "list"
	_setup_fixture(pid)
	_connect_recorders()
	var manager := SpecialistHireManager.new(CampaignRepository, EventBus)
	var s1: String = manager.hire(CAMPAIGN_ID, pid, "x", "pathfinder")
	var s2: String = manager.hire(CAMPAIGN_ID, pid, "x", "land_surveyor")
	manager.dismiss(s1, pid)

	var active: Array = CampaignRepository.list_active_specialists(CAMPAIGN_ID, pid)
	check(active.size() == 1, "only 1 active after dismissing one")
	check(String(active[0].get("specialist_id", "")) == s2,
		"surviving specialist is the land_surveyor")
	_cleanup_fixture(pid)


func test_bonus_for_db_path_aggregates() -> void:
	var pid := PARTY_PREFIX + "bonus"
	_setup_fixture(pid)
	_connect_recorders()
	var manager := SpecialistHireManager.new(CampaignRepository, EventBus)
	manager.hire(CAMPAIGN_ID, pid, "x", "pathfinder")
	manager.hire(CAMPAIGN_ID, pid, "x", "land_surveyor")
	manager.hire(CAMPAIGN_ID, pid, "x", "pathfinder")

	# 2 pathfinders → +8 lair_search; 1 land_surveyor → +4 surveying.
	check(SpecialistBonusResolver.bonus_for(CAMPAIGN_ID, pid,
		SpecialistCatalog.KIND_LAIR_SEARCH) == 8,
		"2 pathfinders aggregate to +8")
	check(SpecialistBonusResolver.bonus_for(CAMPAIGN_ID, pid,
		SpecialistCatalog.KIND_SURVEYING) == 4,
		"1 land_surveyor → +4")
	_cleanup_fixture(pid)


func test_wages_processed_emits_summary_when_no_specialists() -> void:
	var pid := PARTY_PREFIX + "wages_empty"
	_setup_fixture(pid)
	_connect_recorders()
	var manager := SpecialistHireManager.new(CampaignRepository, EventBus)
	var summary: Dictionary = manager.process_monthly_wages(pid, "employer_x", 1000)
	check(int(summary["total_deducted_gp"]) == 0, "no specialists → 0 deducted")
	check((summary["unpaid_specialists"] as Array).is_empty(),
		"no specialists → empty unpaid list")
	check((summary["dismissed_specialists"] as Array).is_empty(),
		"no specialists → no dismissals")
	# Summary signal still emits.
	var found: bool = false
	for entry in _emitted:
		if String(entry["signal"]) == "specialist_wages_processed":
			found = true
			break
	check(found, "specialist_wages_processed emitted even when empty")
	_cleanup_fixture(pid)
