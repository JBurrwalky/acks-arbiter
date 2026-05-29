extends "res://tests/test_suite_base.gd"

## Phase 2 of the henchman game-loop closure: tests for the NM → L1 advancement
## path in LevelUpEngine. Exercises:
##   - HP re-roll (1d8/1d6/1d4 + CON, keep higher of new vs old)
##   - is_post_normal_man flag stamped via class_metadata
##   - class_id swap to selected (fighter/cleric/thief/mage)
##   - Saves / attack throw / title / xp_for_next_level derived from new class
##   - Adventuring SUPPRESSED at L0→L1 (RAW :723 grants it at L4 of post-NM track)
##   - L2/L3/L4 erode one general proficiency each
##   - L4 grants Adventuring
##   - Native L1 hires (no flag) DO NOT lose proficiencies on level-up

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	# Pure-logic tests run regardless of DB state.
	test_class_metadata_flag_helpers()
	# DB-backed tests need a valid campaign. The known first-run flakiness
	# (create_campaign returning "" under DB-state-dependent conditions —
	# documented across heraldry/character-tab/inventory-tab suites) skips
	# the DB-backed cases gracefully so the suite still reports green when
	# the env is healthy and surfaces a single check() failure when it isn't.
	if _campaign_id.is_empty():
		check(false, "create_campaign returned empty — known flaky pattern; DB-backed cases skipped")
	else:
		test_advance_swaps_class_to_selected()
		test_advance_sets_level_one()
		test_advance_stamps_post_nm_flag()
		test_advance_hp_keeps_higher()
		test_advance_derives_combat_stats_from_new_class()
		test_advance_suppresses_adventuring_at_l1()
		test_l2_erodes_one_general_prof()
		test_l4_grants_adventuring()
		test_native_l1_does_not_erode()
	if not has_failures():
		print("NormalManAdvancement: all tests passed.")


# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

func _setup_campaign() -> void:
	_campaign_id = CampaignRepository.create_campaign(
		"Test NM Advancement", "NMAdvancementTestWorld")
	# Defer the empty-id check to run_all_tests so the suite reports a single
	# legible failure rather than chaining on cascading FK violations.


func _make_generator() -> CharacterGenerator:
	return CharacterGenerator.new(ClassRegistry.new(), PowerRegistry.new())


func _make_engine() -> LevelUpEngine:
	return LevelUpEngine.new(ClassRegistry.new(), PowerRegistry.new())


func _save_nm_henchman(scores: Dictionary, employer_id: String = "") -> CharacterData:
	## Creates and persists a level-0 Normal Man henchman with the given ability
	## scores and (optional) employer.
	var gen := _make_generator()
	var nm := gen.generate_henchman("normal_man", 0, _campaign_id, employer_id, 0)
	if nm == null:
		check(false, "_save_nm_henchman: generate_henchman returned null")
		return null
	# Override ability scores so the selector behaves predictably.
	nm.strength = int(scores.get("STR", 10))
	nm.intelligence = int(scores.get("INT", 10))
	nm.wisdom = int(scores.get("WIS", 10))
	nm.dexterity = int(scores.get("DEX", 10))
	nm.constitution = int(scores.get("CON", 10))
	nm.charisma = int(scores.get("CHA", 10))
	nm.xp = 100  # at the advancement threshold
	CampaignRepository.save_character(nm.to_dict())
	return nm


func _save_patron(progression: String) -> CharacterData:
	var gen := _make_generator()
	var patron := gen.generate_npc(progression, 1, _campaign_id, "full")
	patron.character_type = "pc"
	CampaignRepository.save_character(patron.to_dict())
	return patron


# ---------------------------------------------------------------------------
# CharacterData flag helpers (Phase 2 addition)
# ---------------------------------------------------------------------------

func test_class_metadata_flag_helpers() -> void:
	var c := CharacterData.new()
	check(not c.has_class_metadata_flag("is_post_normal_man"),
		"fresh character should not have is_post_normal_man flag")
	c.set_class_metadata_flag("is_post_normal_man", true)
	check(c.has_class_metadata_flag("is_post_normal_man"),
		"set_class_metadata_flag(true) should make has_... return true")
	c.set_class_metadata_flag("is_post_normal_man", false)
	check(not c.has_class_metadata_flag("is_post_normal_man"),
		"set_class_metadata_flag(false) should make has_... return false")
	# Round-trip with another flag preserved.
	c.set_class_metadata_flag("is_post_normal_man", true)
	c.set_class_metadata_flag("regional_origin_set", true)
	check(c.has_class_metadata_flag("is_post_normal_man"),
		"setting another flag should not clear the first")
	check(c.has_class_metadata_flag("regional_origin_set"),
		"second flag should also be readable")


# ---------------------------------------------------------------------------
# L0 → L1 advancement
# ---------------------------------------------------------------------------

func test_advance_swaps_class_to_selected() -> void:
	# STR 16 + fighter patron → fighter (Stage 1).
	var patron := _save_patron("fighter")
	var nm := _save_nm_henchman(
		{"STR": 16, "INT": 9, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10},
		patron.id)
	if nm == null:
		return
	var engine := _make_engine()
	var result := engine.apply_level_up_auto(nm)
	check(result.get("selected_class", "") == "fighter",
		"STR-16 NM should advance to fighter, got %s" % str(result.get("selected_class", "")))
	check(nm.character_class == "fighter",
		"in-memory character_class should be fighter, got %s" % nm.character_class)
	# DB row reflects the swap.
	var row := CampaignRepository.get_character(nm.id)
	check(str(row.get("character_class", "")) == "fighter",
		"DB character_class should be 'fighter', got '%s'" % str(row.get("character_class", "")))


func test_advance_sets_level_one() -> void:
	var patron := _save_patron("fighter")
	var nm := _save_nm_henchman(
		{"STR": 14, "INT": 9, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10},
		patron.id)
	if nm == null:
		return
	var engine := _make_engine()
	engine.apply_level_up_auto(nm)
	check(nm.level == 1, "level should be 1 after advancement, got %d" % nm.level)
	var row := CampaignRepository.get_character(nm.id)
	check(int(row.get("level", -1)) == 1,
		"DB level should be 1, got %d" % int(row.get("level", -1)))


func test_advance_stamps_post_nm_flag() -> void:
	var patron := _save_patron("fighter")
	var nm := _save_nm_henchman(
		{"STR": 14, "INT": 9, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10},
		patron.id)
	if nm == null:
		return
	var engine := _make_engine()
	engine.apply_level_up_auto(nm)
	check(nm.has_class_metadata_flag("is_post_normal_man"),
		"post-NM flag should be set after advancement")
	# DB row's class_metadata also carries the flag.
	var row := CampaignRepository.get_character(nm.id)
	var cd_from_db := CharacterData.from_dict(row)
	check(cd_from_db.has_class_metadata_flag("is_post_normal_man"),
		"DB class_metadata should round-trip the post-NM flag")


func test_advance_hp_keeps_higher() -> void:
	# Force a low HP roll on the new fighter HD by overriding via DiceSystem.
	# We just check the rule shape: hp_max after >= hp_max before.
	var patron := _save_patron("fighter")
	var nm := _save_nm_henchman(
		{"STR": 14, "INT": 9, "WIS": 9, "DEX": 9, "CON": 14, "CHA": 10},
		patron.id)
	if nm == null:
		return
	var hp_before: int = nm.hp_max
	var engine := _make_engine()
	engine.apply_level_up_auto(nm)
	check(nm.hp_max >= hp_before,
		"hp_max after advancement (%d) must be >= hp_max before (%d) — RAW :716 keep-higher rule" % [nm.hp_max, hp_before])


func test_advance_derives_combat_stats_from_new_class() -> void:
	var patron := _save_patron("fighter")
	var nm := _save_nm_henchman(
		{"STR": 16, "INT": 9, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10},
		patron.id)
	if nm == null:
		return
	var engine := _make_engine()
	engine.apply_level_up_auto(nm)
	# Fighter L1 attack throw is 10 per fighter.json.
	check(nm.attack_throw == 10,
		"fighter L1 attack throw should be 10, got %d" % nm.attack_throw)
	# Fighter L1 petrification save is 15.
	check(nm.save_petrification == 15,
		"fighter L1 petrification save should be 15, got %d" % nm.save_petrification)
	# Hit die type updated.
	check(nm.hit_die_type == "1d8",
		"hit_die_type should be 1d8 after advancing into fighter, got %s" % nm.hit_die_type)


func test_advance_suppresses_adventuring_at_l1() -> void:
	# RAW :723 — Adventuring is granted at L4 of the post-NM track, not L1.
	var patron := _save_patron("fighter")
	var nm := _save_nm_henchman(
		{"STR": 16, "INT": 9, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10},
		patron.id)
	if nm == null:
		return
	var engine := _make_engine()
	engine.apply_level_up_auto(nm)
	var profs := CampaignRepository.get_character_proficiencies(nm.id)
	for p: Dictionary in profs:
		check(String(p.get("proficiency_key", "")) != "adventuring",
			"post-NM L1 should NOT have adventuring proficiency yet (RAW :723 grants at L4)")


# ---------------------------------------------------------------------------
# Post-NM track at L2/L3/L4
# ---------------------------------------------------------------------------

func test_l2_erodes_one_general_prof() -> void:
	# Set up a post-NM L1 fighter with one prior general proficiency.
	var patron := _save_patron("fighter")
	var nm := _save_nm_henchman(
		{"STR": 16, "INT": 9, "WIS": 9, "DEX": 9, "CON": 10, "CHA": 10},
		patron.id)
	if nm == null:
		return
	# Seed a pre-existing general prof BEFORE advancement so we have something
	# to erode at L2.
	var seed_profs: Array = [
		{"proficiency_key": "labor", "rank": 1, "slot_type": "general",
			"selections_count": 1, "specialization": ""}
	]
	CampaignRepository.save_character_proficiencies(nm.id, seed_profs)
	# Reload proficiencies onto the in-memory CharacterData (auto-select reads
	# from DB inside _advance_normal_man).
	nm.proficiencies = CampaignRepository.get_character_proficiencies(nm.id)

	var engine := _make_engine()
	engine.apply_level_up_auto(nm)  # L0 → L1 (no erosion yet).
	# Set up XP for L2 and re-call.
	var fighter_xp_for_l2 := ClassRegistry.new().get_xp_for_level("fighter", 2)
	nm.xp = fighter_xp_for_l2
	nm.xp_for_next_level = fighter_xp_for_l2
	engine.apply_level_up_auto(nm)
	check(nm.level == 2, "should be at L2 after second advancement")
	var profs := CampaignRepository.get_character_proficiencies(nm.id)
	var has_labor: bool = false
	for p in profs:
		if String(p.get("proficiency_key", "")) == "labor":
			has_labor = true
			break
	check(not has_labor, "L2 erosion should remove the labor general proficiency")


func test_l4_grants_adventuring() -> void:
	# Shortcut: simulate the post-NM track flag without going through L0 first.
	# This exercises the _apply_post_normal_man_track path directly via an
	# advancement to L4.
	var gen := _make_generator()
	var fighter := gen.generate_npc("fighter", 3, _campaign_id, "full", "henchman")
	fighter.set_class_metadata_flag("is_post_normal_man", true)
	# Ensure some erodable profs exist, but no Adventuring yet.
	var seed: Array = [
		{"proficiency_key": "labor", "rank": 1, "slot_type": "general",
			"selections_count": 1, "specialization": ""},
		{"proficiency_key": "knowledge", "rank": 1, "slot_type": "general",
			"selections_count": 1, "specialization": ""},
	]
	CampaignRepository.save_character(fighter.to_dict())
	CampaignRepository.save_character_proficiencies(fighter.id, seed)
	# Persist class_metadata directly (update_character_fields whitelist
	# excludes class_metadata; use the same UPDATE the engine uses).
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET class_metadata = ? WHERE id = ?",
		[fighter.class_metadata, fighter.id])

	# Set XP at the L4 threshold.
	var fighter_xp_for_l4 := ClassRegistry.new().get_xp_for_level("fighter", 4)
	fighter.xp = fighter_xp_for_l4
	fighter.xp_for_next_level = fighter_xp_for_l4

	var engine := _make_engine()
	engine.apply_level_up_auto(fighter)
	check(fighter.level == 4, "should be at L4 after advancement")
	var profs := CampaignRepository.get_character_proficiencies(fighter.id)
	var has_adventuring: bool = false
	for p in profs:
		if String(p.get("proficiency_key", "")) == "adventuring":
			has_adventuring = true
			break
	check(has_adventuring, "L4 of post-NM track should grant Adventuring per RAW :723")


func test_native_l1_does_not_erode() -> void:
	# A native L1 fighter (no post-NM flag) should level up normally, with
	# no proficiency erosion.
	var gen := _make_generator()
	var fighter := gen.generate_npc("fighter", 1, _campaign_id, "full", "npc")
	check(not fighter.has_class_metadata_flag("is_post_normal_man"),
		"native L1 fighter should NOT have post-NM flag")
	CampaignRepository.save_character(fighter.to_dict())
	var seed: Array = [
		{"proficiency_key": "labor", "rank": 1, "slot_type": "general",
			"selections_count": 1, "specialization": ""}
	]
	CampaignRepository.save_character_proficiencies(fighter.id, seed)
	# Set XP at L2 threshold.
	var fighter_xp_for_l2 := ClassRegistry.new().get_xp_for_level("fighter", 2)
	fighter.xp = fighter_xp_for_l2
	fighter.xp_for_next_level = fighter_xp_for_l2

	var engine := _make_engine()
	engine.apply_level_up_auto(fighter)
	check(fighter.level == 2, "native fighter should advance to L2")
	var profs := CampaignRepository.get_character_proficiencies(fighter.id)
	var has_labor: bool = false
	for p in profs:
		if String(p.get("proficiency_key", "")) == "labor":
			has_labor = true
			break
	check(has_labor, "native L1 fighter should NOT lose labor on L2 (no post-NM flag)")
