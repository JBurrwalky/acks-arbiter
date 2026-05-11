extends "res://tests/test_suite_base.gd"

## Tests for ArmyComposer (Phase 6A).
##
## Covers the Step 1-5 formation flow plus the §3.3 RAW officer-derivation
## formulas. Verifies:
##   - PC charisma-driven Leadership Ability (4 + Cha mod, capped 8)
##   - Strategic Ability formula (max int-or-wis + min int-or-wis + military strategy)
##   - Mercenary officer fixed table (Lt/Capt/Col/Gen)
##   - Monster derivation (3 + HD/4)
##   - <3 unit minimum rejection per RAW §divisions L737

var _campaign_id: String = ""
var _ruler_id: String = ""
var _henchman_id: String = ""
var _troop_unit_ids: Array = []


func run_all_tests() -> void:
	_setup()
	test_too_few_units_rejected()
	test_pc_leadership_from_charisma()
	test_pc_leadership_with_proficiency()
	test_strategic_ability_int_wis_split()
	test_mercenary_officer_table_lieutenant()
	test_mercenary_officer_table_general()
	test_monster_derivation_hd_based()
	test_compose_inserts_full_hierarchy()
	test_compose_default_name_uses_owner_first_name()
	if not has_failures():
		print("ArmyComposer: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Composer Test", "World")
	# Helper signature: (name, intelligence, wisdom, charisma, level)
	_ruler_id = _make_character("Wymar Stormrider", 12, 12, 14)  # cha 14 → mod +1
	_henchman_id = _make_character("Bran the Bold", 12, 12, 10)  # cha 10 → mod 0
	# Three troop units owned by the ruler.
	for i in range(4):
		_troop_unit_ids.append(TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id,
			"owner_character_id": _ruler_id,
			"source_type": "mercenary",
			"troop_type": "Test Troop",
			"count": 60, "starting_count": 60, "battle_rating": 1.5,
			"monthly_wage_gp": 500,
		}))


func _make_character(name: String, intelligence: int = 12, wisdom: int = 12, charisma: int = 12, level: int = 9) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', ?,
			14, ?, ?, 12, 12, ?, 60, 60)
	""", [id, _campaign_id, name, level, intelligence, wisdom, charisma])
	return id


func _add_proficiency(character_id: String, key: String, rank: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_proficiencies (character_id, proficiency_key, rank, slot_type)
		VALUES (?, ?, ?, 'general')
	""", [character_id, key, rank])


func test_too_few_units_rejected() -> void:
	var result := ArmyComposer.compose({
		"campaign_id": _campaign_id,
		"political_owner_id": _ruler_id,
		"command_character_id": _ruler_id,
		"unit_scale": "platoon",
		"units": [{"troop_unit_id": _troop_unit_ids[0], "parent_character_id": _ruler_id}],
	})
	check(not bool(result.get("success", true)), "<3 units rejected")
	var has_min_msg := false
	for e in result.get("errors", []):
		if String(e).contains("≥3 troop_units") or String(e).contains("requires"):
			has_min_msg = true
			break
	check(has_min_msg, "errors mention minimum")


func test_pc_leadership_from_charisma() -> void:
	# Cha 14 → mod +1 → Leadership 5
	var abilities := ArmyComposer.derive_abilities(_ruler_id, "pc", false, {})
	check(int(abilities.get("leadership", 0)) == 5, "Leadership 5 for Cha 14")


func test_pc_leadership_with_proficiency() -> void:
	# Add Leadership proficiency → +1 → Leadership 6
	var leader_id := _make_character("Lead Test", 12, 12, 14)
	_add_proficiency(leader_id, "leadership", 1)
	var abilities := ArmyComposer.derive_abilities(leader_id, "pc", false, {})
	check(int(abilities.get("leadership", 0)) == 6, "Leadership 6 with proficiency, got %d" % abilities.get("leadership", 0))


func test_strategic_ability_int_wis_split() -> void:
	# INT 16 (+2), WIS 9 (0), no Military Strategy → max(0, 2) + min(0, 0) = 2
	var c := _make_character("Stratos", 16, 9, 12)
	var abilities := ArmyComposer.derive_abilities(c, "pc", false, {})
	check(int(abilities.get("strategic", 99)) == 2, "Strategic 2, got %d" % abilities.get("strategic", 99))
	# INT 16 (+2), WIS 6 (-1) → max(0, 2) + min(0, -1) = 1
	var c2 := _make_character("MixedSage", 16, 6, 12)
	var abilities2 := ArmyComposer.derive_abilities(c2, "pc", false, {})
	check(int(abilities2.get("strategic", 99)) == 1, "Strategic 1 with INT16/WIS6, got %d" % abilities2.get("strategic", 99))


func test_mercenary_officer_table_lieutenant() -> void:
	var abilities := ArmyComposer.derive_abilities("", "mercenary_officer", false, {"rank_label": "lieutenant"})
	check(int(abilities.get("leadership", 0)) == 4, "Lt Leadership 4")
	check(int(abilities.get("strategic", 0)) == 1, "Lt Strategic +1")
	check(int(abilities.get("morale", 0)) == 3, "Lt Morale +3")
	check(int(abilities.get("wage", 0)) == 400, "Lt wage 400 gp/mo")


func test_mercenary_officer_table_general() -> void:
	var abilities := ArmyComposer.derive_abilities("", "mercenary_officer", false, {"rank_label": "general"})
	check(int(abilities.get("leadership", 0)) == 5, "Gen Leadership 5")
	check(int(abilities.get("strategic", 0)) == 3, "Gen Strategic +3")
	check(int(abilities.get("wage", 0)) == 32000, "Gen wage 32000 gp/mo")


func test_monster_derivation_hd_based() -> void:
	var monster_id := _make_character("Big Beast", 8, 8, 8, 12)  # level/HD 12
	var abilities := ArmyComposer.derive_abilities(
		monster_id, "monster", false, {"int_tier_modifier": 0, "morale_modifier": 0}
	)
	# Leadership = 3 + (12/4) = 6
	check(int(abilities.get("leadership", 0)) == 6, "monster Leadership 3 + HD/4 = 6, got %d" % abilities.get("leadership", 0))
	# Strategic = 0 + (12/5)floor = 2
	check(int(abilities.get("strategic", 0)) == 2, "monster Strategic = HD/5 floor = 2, got %d" % abilities.get("strategic", 0))


func test_compose_inserts_full_hierarchy() -> void:
	var plan := {
		"campaign_id": _campaign_id,
		"political_owner_id": _ruler_id,
		"command_character_id": _ruler_id,
		"unit_scale": "platoon",
		"strategic_stance": "defensive",
		"formed_calendar_day": 100,
		"leader_derivation": "pc",
		"division_commanders": [
			{"character_id": _henchman_id, "derivation_source": "henchman"},
		],
		"lieutenants": [],
		"units": [
			{"troop_unit_id": _troop_unit_ids[1], "parent_character_id": _henchman_id},
			{"troop_unit_id": _troop_unit_ids[2], "parent_character_id": _henchman_id},
			{"troop_unit_id": _troop_unit_ids[3], "parent_character_id": _henchman_id},
		],
	}
	var result := ArmyComposer.compose(plan)
	check(bool(result.get("success", false)),
		"compose succeeded; errors=%s" % [result.get("errors", [])])
	var army_id := String(result.get("army_id", ""))
	check(not army_id.is_empty(), "army_id non-empty")
	var officers := ArmyRepository.list_officers_for_army(army_id)
	check(officers.size() == 2, "2 officers (leader + DC), got %d" % officers.size())
	var assignments := ArmyRepository.list_active_assignments_for_army(army_id)
	check(assignments.size() == 3, "3 unit assignments, got %d" % assignments.size())
	var supply := ArmyRepository.get_supply_state(army_id)
	check(not supply.is_empty(), "supply state row created")


func test_compose_default_name_uses_owner_first_name() -> void:
	# Need fresh units (the previous test consumed three).
	var fresh_units := []
	for i in range(3):
		fresh_units.append(TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id,
			"owner_character_id": _ruler_id,
			"source_type": "mercenary",
			"troop_type": "Fresh Troop",
			"count": 60, "starting_count": 60, "battle_rating": 1.0,
		}))
	var fresh_henchman := _make_character("Other Henchman", 12, 12, 12)
	var plan := {
		"campaign_id": _campaign_id,
		"political_owner_id": _ruler_id,
		"command_character_id": _ruler_id,
		"unit_scale": "platoon",
		"formed_calendar_day": 101,
		"leader_derivation": "pc",
		"division_commanders": [{"character_id": fresh_henchman, "derivation_source": "henchman"}],
		"units": [
			{"troop_unit_id": fresh_units[0], "parent_character_id": fresh_henchman},
			{"troop_unit_id": fresh_units[1], "parent_character_id": fresh_henchman},
			{"troop_unit_id": fresh_units[2], "parent_character_id": fresh_henchman},
		],
	}
	var result := ArmyComposer.compose(plan)
	check(bool(result.get("success", false)), "compose ok")
	var army := ArmyRepository.get_army(String(result.get("army_id", "")))
	check(String(army.get("name", "")).contains("Wymar"), "default name uses 'Wymar' (first name); got '%s'" % army.get("name", ""))
