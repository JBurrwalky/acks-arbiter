extends "res://tests/test_suite_base.gd"

## Round-trip tests for VassalRepository (Phase 7 migration 079).
## Covers create / get / list_active_for_liege / update_status /
## record_loyalty_roll / partial-unique-index on (liege, vassal) WHERE active.

var _campaign_id: String = ""
var _liege_id: String = ""
var _vassal_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_create_and_get_assignment()
	test_list_active_for_liege()
	test_record_loyalty_roll_persists()
	test_update_status_transitions()
	test_partial_unique_index_only_one_active_per_pair()
	test_get_active_assignment_for_vassal()
	if not has_failures():
		print("VassalRepository: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Vassal Repo Test", "TestWorld")
	_liege_id = _make_character("Liege")
	_vassal_id = _make_character("Vassal")


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


func _create_assignment(opts: Dictionary = {}) -> String:
	var data := {
		"campaign_id": _campaign_id,
		"liege_character_id": _liege_id,
		"vassal_character_id": opts.get("vassal", _vassal_id),
		"assigned_calendar_day": 100,
		"is_henchman_vassal": opts.get("is_henchman", true),
		"base_loyalty_modifier": opts.get("base_mod", 0),
	}
	return VassalRepository.create_assignment(data)


func test_create_and_get_assignment() -> void:
	var id := _create_assignment()
	check(not id.is_empty(), "create returned id")
	var row := VassalRepository.get_assignment(id)
	check(String(row.get("liege_character_id", "")) == _liege_id, "liege round-trips")
	check(String(row.get("vassal_character_id", "")) == _vassal_id, "vassal round-trips")
	check(String(row.get("status", "")) == "active", "default status active")
	check(int(row.get("is_henchman_vassal", 0)) == 1, "henchman flag default 1")
	# Cleanup
	VassalRepository.update_status(id, "departed", 200)


func test_list_active_for_liege() -> void:
	var fresh_liege := _make_character("FreshLiege")
	var v1 := _make_character("V1")
	var v2 := _make_character("V2")
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id,
		"liege_character_id": fresh_liege,
		"vassal_character_id": v1,
		"assigned_calendar_day": 1,
	})
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id,
		"liege_character_id": fresh_liege,
		"vassal_character_id": v2,
		"assigned_calendar_day": 2,
	})
	var rows := VassalRepository.list_active_for_liege(fresh_liege)
	check(rows.size() == 2, "2 active vassals listed; got %d" % rows.size())


func test_record_loyalty_roll_persists() -> void:
	var fresh_liege := _make_character("LoyaltyLiege")
	var fresh_vassal := _make_character("LoyaltyVassal")
	var id := VassalRepository.create_assignment({
		"campaign_id": _campaign_id,
		"liege_character_id": fresh_liege,
		"vassal_character_id": fresh_vassal,
		"assigned_calendar_day": 1,
	})
	check(VassalRepository.record_loyalty_roll(id, "loyal", 30), "record returns true")
	var row := VassalRepository.get_assignment(id)
	check(String(row.get("last_loyalty_outcome", "")) == "loyal", "outcome persisted")
	check(int(row.get("last_loyalty_roll_day", 0)) == 30, "day persisted")


func test_update_status_transitions() -> void:
	var fresh_liege := _make_character("StatusLiege")
	var fresh_vassal := _make_character("StatusVassal")
	var id := VassalRepository.create_assignment({
		"campaign_id": _campaign_id,
		"liege_character_id": fresh_liege,
		"vassal_character_id": fresh_vassal,
		"assigned_calendar_day": 1,
	})
	check(VassalRepository.update_status(id, "revolted", 50), "update returns true")
	var row := VassalRepository.get_assignment(id)
	check(String(row.get("status", "")) == "revolted", "status mutated to revolted")


func test_partial_unique_index_only_one_active_per_pair() -> void:
	var fresh_liege := _make_character("UniqLiege")
	var fresh_vassal := _make_character("UniqVassal")
	var id1 := VassalRepository.create_assignment({
		"campaign_id": _campaign_id,
		"liege_character_id": fresh_liege,
		"vassal_character_id": fresh_vassal,
		"assigned_calendar_day": 1,
	})
	check(not id1.is_empty(), "first active row inserts")
	# Second active insert should be blocked by the partial-unique index.
	var id2 := VassalRepository.create_assignment({
		"campaign_id": _campaign_id,
		"liege_character_id": fresh_liege,
		"vassal_character_id": fresh_vassal,
		"assigned_calendar_day": 2,
	})
	check(id2.is_empty(), "duplicate active row rejected by partial unique index")
	# Marking the first inactive should now permit a new active row.
	VassalRepository.update_status(id1, "departed", 50)
	var id3 := VassalRepository.create_assignment({
		"campaign_id": _campaign_id,
		"liege_character_id": fresh_liege,
		"vassal_character_id": fresh_vassal,
		"assigned_calendar_day": 100,
	})
	check(not id3.is_empty(), "new active row succeeds after first marked departed")


func test_get_active_assignment_for_vassal() -> void:
	var fresh_liege := _make_character("LookupLiege")
	var fresh_vassal := _make_character("LookupVassal")
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id,
		"liege_character_id": fresh_liege,
		"vassal_character_id": fresh_vassal,
		"assigned_calendar_day": 1,
	})
	var found := VassalRepository.get_active_assignment_for_vassal(fresh_vassal)
	check(not found.is_empty(), "found by vassal id")
	check(String(found.get("liege_character_id", "")) == fresh_liege, "liege matches")
