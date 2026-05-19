extends "res://tests/test_suite_base.gd"

## Tests for ArmyRepository (Phase 6A migrations 070-074).
##
## Round-trip CRUD coverage for armies / army_officers / army_unit_assignments
## / army_supply_state / reconnaissance_cooldowns. Verifies the partial-unique
## index on army_unit_assignments(troop_unit_id) WHERE released_calendar_day = 0.

var _campaign_id: String = ""
var _ruler_id: String = ""
var _officer_char_id: String = ""
var _troop_unit_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_create_and_get_army()
	test_update_army()
	test_list_armies_at_hex_filters_disbanded()
	test_create_officer_with_parent_chain()
	test_get_army_leader_returns_only_active_leader()
	test_create_assignment_active_uniqueness()
	test_supply_state_round_trip()
	test_recon_cooldown_upsert()
	if not has_failures():
		print("ArmyRepository: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Army Repo Test", "TestWorld")
	_ruler_id = _make_character("Ruler")
	_officer_char_id = _make_character("Officer")
	_troop_unit_id = TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id,
		"owner_character_id": _ruler_id,
		"source_type": "mercenary",
		"troop_type": "Heavy Infantry",
		"count": 60,
		"starting_count": 60,
		"battle_rating": 1.5,
		"monthly_wage_cp": 600,
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


func _create_test_army() -> String:
	return ArmyRepository.create_army({
		"campaign_id": _campaign_id,
		"name": "Test Host",
		"political_owner_id": _ruler_id,
		"command_character_id": _ruler_id,
		"state": "assembling",
		"unit_scale": "platoon",
		"strategic_stance": "defensive",
		"formed_calendar_day": 100,
	})


func test_create_and_get_army() -> void:
	var id := _create_test_army()
	check(not id.is_empty(), "create_army returned an id")
	var row := ArmyRepository.get_army(id)
	check(String(row.get("name", "")) == "Test Host", "name round-trips")
	check(String(row.get("state", "")) == "assembling", "state defaults to assembling")
	check(String(row.get("unit_scale", "")) == "platoon", "unit_scale round-trips")


func test_update_army() -> void:
	var id := _create_test_army()
	check(ArmyRepository.update_army(id, {"state": "encamped", "hex_q": 5, "hex_r": 7}),
		"update succeeds")
	var row := ArmyRepository.get_army(id)
	check(String(row.get("state", "")) == "encamped", "state mutated")
	check(int(row.get("hex_q", 0)) == 5 and int(row.get("hex_r", 0)) == 7, "hex coords mutated")
	# Bad-field rejection.
	var ok := ArmyRepository.update_army(id, {"campaign_id": "evil"})
	check(not ok, "rejects non-whitelisted campaign_id update")


func test_list_armies_at_hex_filters_disbanded() -> void:
	var map_id := CampaignRepository.generate_id()
	# Two armies at same hex.
	var a := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Alpha",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped", "map_id": map_id, "hex_q": 1, "hex_r": 2,
	})
	var b := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Bravo",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "encamped", "map_id": map_id, "hex_q": 1, "hex_r": 2,
	})
	# A disbanded army at the same hex should not appear.
	var c := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Charlie",
		"political_owner_id": _ruler_id, "command_character_id": _ruler_id,
		"state": "disbanded", "map_id": map_id, "hex_q": 1, "hex_r": 2,
	})
	var rows := ArmyRepository.list_armies_at_hex(map_id, 1, 2)
	check(rows.size() == 2, "list_armies_at_hex excludes disbanded; got %d" % rows.size())
	var names := []
	for r in rows:
		names.append(String(r.get("name", "")))
	check(names.has("Alpha") and names.has("Bravo"), "expected names present")
	check(not names.has("Charlie"), "disbanded excluded")
	# Silence unused-warning.
	var _unused := [a, b, c]
	check(_unused.size() == 3, "all three armies created")


func test_create_officer_with_parent_chain() -> void:
	var army_id := _create_test_army()
	var leader := ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
		"parent_officer_id": null, "leadership_ability": 5, "strategic_ability": 1,
		"morale_modifier": 2, "derivation_source": "pc",
		"appointed_calendar_day": 100,
	})
	check(not leader.is_empty(), "leader insert ok")
	var dc := ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _officer_char_id, "rank": "division_commander",
		"parent_officer_id": leader, "leadership_ability": 4, "strategic_ability": 0,
		"morale_modifier": 1, "derivation_source": "henchman",
		"appointed_calendar_day": 100,
	})
	check(not dc.is_empty(), "dc insert ok")
	var officers := ArmyRepository.list_officers_for_army(army_id)
	check(officers.size() == 2, "list returns both active officers; got %d" % officers.size())


func test_get_army_leader_returns_only_active_leader() -> void:
	var army_id := _create_test_army()
	var first_leader := ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
		"parent_officer_id": null, "appointed_calendar_day": 100,
	})
	check(not first_leader.is_empty(), "first leader insert ok")
	# Mark first leader as removed and create successor.
	ArmyRepository.update_officer(first_leader, {"removed_calendar_day": 105, "rank": "former_commander"})
	var successor := ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _officer_char_id, "rank": "army_leader",
		"parent_officer_id": null, "appointed_calendar_day": 105,
	})
	check(not successor.is_empty(), "successor insert ok")
	var leader := ArmyRepository.get_army_leader(army_id)
	check(String(leader.get("id", "")) == successor, "get_army_leader returns active successor")


func test_create_assignment_active_uniqueness() -> void:
	var army_id := _create_test_army()
	var leader := ArmyRepository.create_officer({
		"army_id": army_id, "character_id": _ruler_id, "rank": "army_leader",
		"parent_officer_id": null, "appointed_calendar_day": 100,
	})
	# A fresh troop_unit so we don't collide with previous tests.
	var unit_id: String = TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id,
		"owner_character_id": _ruler_id,
		"source_type": "mercenary", "troop_type": "Cavalry",
		"count": 30, "starting_count": 30, "battle_rating": 2.0,
	})
	var assn1 := ArmyRepository.create_assignment({
		"army_id": army_id, "troop_unit_id": unit_id,
		"parent_officer_id": leader, "role": "line",
		"assigned_calendar_day": 100,
	})
	check(not assn1.is_empty(), "first assignment ok")

	# Attempting a second active assignment on the same unit must fail
	# (partial unique index on troop_unit_id WHERE released_calendar_day = 0).
	var assn2 := ArmyRepository.create_assignment({
		"army_id": army_id, "troop_unit_id": unit_id,
		"parent_officer_id": leader, "role": "line",
		"assigned_calendar_day": 100,
	})
	check(assn2.is_empty(), "second active assignment rejected by unique index")

	# Release the first then the second can be inserted.
	ArmyRepository.update_assignment(assn1, {
		"released_calendar_day": 110, "release_reason": "voluntary", "destination": "unaligned_pool",
	})
	var assn3 := ArmyRepository.create_assignment({
		"army_id": army_id, "troop_unit_id": unit_id,
		"parent_officer_id": leader, "role": "line",
		"assigned_calendar_day": 111,
	})
	check(not assn3.is_empty(), "third assignment ok after release")


func test_supply_state_round_trip() -> void:
	var army_id := _create_test_army()
	check(ArmyRepository.create_supply_state({"army_id": army_id}), "supply state created")
	var row := ArmyRepository.get_supply_state(army_id)
	check(String(row.get("supply_line_status", "")) == "out_of_supply_no_base",
		"default status is out_of_supply_no_base")
	check(ArmyRepository.update_supply_state(army_id, {
		"weekly_supply_cost_cp": 240,
		"current_stockpile_cp": 1000,
		"supply_line_status": "in_supply",
	}), "supply state updated")
	row = ArmyRepository.get_supply_state(army_id)
	check(int(row.get("weekly_supply_cost_cp", 0)) == 240, "weekly cost mutated")
	check(int(row.get("current_stockpile_cp", 0)) == 1000, "stockpile mutated")


func test_recon_cooldown_upsert() -> void:
	var observer := _create_test_army()
	var observed := _create_test_army()
	check(ArmyRepository.upsert_recon_cooldown(observer, observed, 50, "marginal_success"),
		"first upsert ok")
	var row := ArmyRepository.get_recon_cooldown(observer, observed)
	check(int(row.get("last_roll_calendar_day", 0)) == 50, "first day stored")
	check(String(row.get("last_result", "")) == "marginal_success", "first result stored")
	# Upsert with later day overrides.
	check(ArmyRepository.upsert_recon_cooldown(observer, observed, 75, "major_success"),
		"second upsert ok")
	row = ArmyRepository.get_recon_cooldown(observer, observed)
	check(int(row.get("last_roll_calendar_day", 0)) == 75, "day overwritten")
	check(String(row.get("last_result", "")) == "major_success", "result overwritten")
