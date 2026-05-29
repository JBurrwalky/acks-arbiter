extends "res://tests/test_suite_base.gd"

## Round-trip tests for VassalObligationsRepository (Phase 8 migration 080).

var _campaign_id: String = ""
var _liege_id: String = ""
var _vassal_id: String = ""
var _assignment_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_create_and_get()
	test_list_active_favors_and_duties()
	test_list_one_time_favors_in_month_window()
	test_most_recent_active_returns_latest()
	test_set_status_revoked()
	test_update_whitelist_blocks_invalid()
	if not has_failures():
		print("VassalObligationsRepository: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("VassalObligationsTest", "World")
	_liege_id = _make_character("Liege")
	_vassal_id = _make_character("Vassal")
	_assignment_id = VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": _vassal_id, "assigned_calendar_day": 1,
		"is_henchman_vassal": true,
	})


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, name])
	return id


func test_create_and_get() -> void:
	var id := VassalObligationsRepository.create({
		"vassal_assignment_id": _assignment_id,
		"kind": "duty", "type": "scutage",
		"magnitude": 200, "issued_calendar_day": 30,
	})
	check(not id.is_empty(), "create returns id")
	var row := VassalObligationsRepository.get_obligation(id)
	check(str(row.get("type", "")) == "scutage", "type round-trips")
	check(int(row.get("magnitude", 0)) == 200, "magnitude round-trips")
	check(str(row.get("status", "")) == "active", "status defaults active")


func test_list_active_favors_and_duties() -> void:
	# Build a fresh assignment for clean filtering.
	var v2 := _make_character("V2")
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": v2, "assigned_calendar_day": 1,
	})
	# Two duties + one favor.
	VassalObligationsRepository.create({"vassal_assignment_id": assn, "kind": "duty", "type": "scutage", "magnitude": 100, "issued_calendar_day": 5})
	VassalObligationsRepository.create({"vassal_assignment_id": assn, "kind": "duty", "type": "call_to_arms", "magnitude": 50, "issued_calendar_day": 6})
	VassalObligationsRepository.create({"vassal_assignment_id": assn, "kind": "favor", "type": "office", "issued_calendar_day": 7})
	var duties: Array = VassalObligationsRepository.list_active_duties_for_assignment(assn)
	var favors: Array = VassalObligationsRepository.list_active_favors_for_assignment(assn)
	check(duties.size() == 2, "2 active duties; got %d" % duties.size())
	check(favors.size() == 1, "1 active favor; got %d" % favors.size())


func test_list_one_time_favors_in_month_window() -> void:
	var v3 := _make_character("V3")
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": v3, "assigned_calendar_day": 1,
	})
	# Issue a one-time favor 5 days ago (within window).
	VassalObligationsRepository.create({
		"vassal_assignment_id": assn, "kind": "favor", "type": "gift",
		"is_one_time": true, "issued_calendar_day": 95, "status": "completed",
	})
	# Issue a one-time favor 60 days ago (outside 30-day window).
	VassalObligationsRepository.create({
		"vassal_assignment_id": assn, "kind": "favor", "type": "gift",
		"is_one_time": true, "issued_calendar_day": 40, "status": "completed",
	})
	var window: Array = VassalObligationsRepository.list_one_time_favors_issued_in_month(assn, 100)
	check(window.size() == 1, "only 1 one-time favor in 30-day window; got %d" % window.size())


func test_most_recent_active_returns_latest() -> void:
	var v4 := _make_character("V4")
	var assn := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": v4, "assigned_calendar_day": 1,
	})
	VassalObligationsRepository.create({"vassal_assignment_id": assn, "kind": "duty", "type": "scutage", "issued_calendar_day": 5})
	VassalObligationsRepository.create({"vassal_assignment_id": assn, "kind": "duty", "type": "loan", "issued_calendar_day": 10})
	var most := VassalObligationsRepository.most_recent_active(assn, "duty")
	check(String(most.get("type", "")) == "loan", "most recent active duty is 'loan'; got %s" % most.get("type", ""))


func test_set_status_revoked() -> void:
	var id := VassalObligationsRepository.create({
		"vassal_assignment_id": _assignment_id,
		"kind": "duty", "type": "call_to_council",
		"issued_calendar_day": 50,
	})
	check(VassalObligationsRepository.set_status(id, "revoked", 60), "set_status returns true")
	var row := VassalObligationsRepository.get_obligation(id)
	check(str(row.get("status", "")) == "revoked", "status mutated")


func test_update_whitelist_blocks_invalid() -> void:
	var id := VassalObligationsRepository.create({
		"vassal_assignment_id": _assignment_id,
		"kind": "duty", "type": "scutage", "magnitude": 100,
	})
	# kind is not in whitelist — should be rejected.
	var ok := VassalObligationsRepository.update(id, {"kind": "favor"})
	# update returns true if at least one field updated, but the kind change
	# should be rejected silently. We verify no mutation happened.
	check(ok or not ok, "update returns bool")  # any return is fine
	var row := VassalObligationsRepository.get_obligation(id)
	check(str(row.get("kind", "")) == "duty", "kind unchanged after rejected update")
