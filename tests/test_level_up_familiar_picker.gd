extends "res://tests/test_suite_base.gd"

## Tests for LevelUpFamiliarPicker — Stage 3d wrapper that surfaces in the
## level-up UI when the master has the Familiar proficiency. Detects which of
## the two cases (A: replacement bonding, B: additional picks on budget growth)
## applies and routes to the right embedded sub-picker.
##
## Tests verify case detection, completion gating, and the shape of
## `get_final_choices()` for the engine's finalize hook to consume.

const TEST_CAMPAIGN := "test_lufp_campaign"
const TEST_MASTER_ID := "test_lufp_master"
const TEST_DEAD_FAMILIAR_ID := "test_lufp_dead_fam"
const TEST_LIVING_FAMILIAR_ID := "test_lufp_living_fam"


func run_all_tests() -> void:
	test_case_none_when_master_has_no_familiar_proficiency()
	test_case_a_first_bonding_no_familiar_history()
	test_case_a_replacement_gate_met_after_most_recent_death()
	test_case_none_when_replacement_gate_not_met()
	test_case_b_living_familiar_and_master_gains_slots()
	test_case_none_when_living_familiar_but_no_new_slots()
	test_case_b_returns_familiar_id_and_picks_in_final_choices()
	test_case_a_returns_form_and_proficiencies_in_final_choices()

	_cleanup()
	if not has_failures():
		print("LevelUpFamiliarPicker: all tests passed.")


# --- Helpers ---

func _make_master(level: int, has_familiar_proficiency: bool, hp_max: int = 14) -> CharacterData:
	var c := CharacterData.new()
	c.id = TEST_MASTER_ID
	c.campaign_id = TEST_CAMPAIGN
	c.name = "LU Master"
	c.character_type = "pc"
	c.character_class = "mage"
	c.combat_progression = "mage"
	c.level = level
	c.hp_max = hp_max
	c.hp_current = hp_max
	c.intelligence = 14
	c.proficiencies = []
	if has_familiar_proficiency:
		c.proficiencies.append(
			{"proficiency_key": "familiar", "rank": 1, "slot_type": "class", "selections_count": 1, "specialization": ""})
	# Add a generic non-spec second pick so the master has count >= 2.
	c.proficiencies.append(
		{"proficiency_key": "adventuring", "rank": 1, "slot_type": "general", "selections_count": 1, "specialization": ""})
	return c


func _setup_db() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Level-up Familiar Picker Test"])
	CampaignRepository.create_character({
		"id": TEST_MASTER_ID,
		"campaign_id": TEST_CAMPAIGN,
		"name": "LU Master",
		"character_type": "pc",
		"persistence_tier": "full",
		"race": "human",
		"character_class": "mage",
		"combat_progression": "mage",
		"level": 4,
		"xp": 0,
		"strength": 10, "intelligence": 14, "wisdom": 10,
		"dexterity": 10, "constitution": 10, "charisma": 10,
		"hp_max": 14, "hp_current": 14,
	})


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM familiars WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_MASTER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _seed_dead_familiar(bonded_at: int) -> void:
	# Insert a row directly with is_alive=0 to bypass the unique-living-per-master
	# index. Then mark it dead post-insert.
	var prog: Dictionary = FamiliarData.compute_progression_for_master_level(bonded_at)
	var fid: String = CampaignRepository.create_familiar({
		"id": TEST_DEAD_FAMILIAR_ID,
		"campaign_id": TEST_CAMPAIGN,
		"master_character_id": TEST_MASTER_ID,
		"form_key": "bat",
		"name": "Twilight",
		"hp_current": 1, "hp_max_cached": 1,
		"hd_dice": int(prog["hd_dice"]),
		"hd_modifier_hp": int(prog["hd_modifier_hp"]),
		"is_half_hd": bool(prog["is_half_hd"]),
		"attack_save_class": String(prog["attack_save_class"]),
		"attack_save_level": int(prog["attack_save_level"]),
		"damage_bonus": int(prog["damage_bonus"]),
		"int_cached": 14, "proficiency_count_cached": 0,
		"is_alive": true, "bonded_at_master_level": bonded_at,
	})
	check(not fid.is_empty(), "seed dead familiar inserted")
	CampaignRepository.kill_familiar(fid)


func _seed_living_familiar(bonded_at: int, prior_picks: Array = []) -> void:
	var prog: Dictionary = FamiliarData.compute_progression_for_master_level(bonded_at)
	var fid: String = CampaignRepository.create_familiar({
		"id": TEST_LIVING_FAMILIAR_ID,
		"campaign_id": TEST_CAMPAIGN,
		"master_character_id": TEST_MASTER_ID,
		"form_key": "hawk",
		"name": "Skyfeather",
		"hp_current": 4, "hp_max_cached": 4,
		"hd_dice": int(prog["hd_dice"]),
		"hd_modifier_hp": int(prog["hd_modifier_hp"]),
		"is_half_hd": bool(prog["is_half_hd"]),
		"attack_save_class": String(prog["attack_save_class"]),
		"attack_save_level": int(prog["attack_save_level"]),
		"damage_bonus": int(prog["damage_bonus"]),
		"int_cached": 14,
		"proficiency_count_cached": prior_picks.size(),
		"proficiencies_chosen": JSON.stringify(prior_picks),
		"is_alive": true, "bonded_at_master_level": bonded_at,
	})
	check(not fid.is_empty(), "seed living familiar inserted")


func _make_picker(master: CharacterData, level_up_result: Dictionary) -> LevelUpFamiliarPicker:
	var p := LevelUpFamiliarPicker.new()
	p.setup(master, level_up_result,
		FamiliarFormRegistry.new(),
		ClassRegistry.new(),
		ProficiencyRegistry.new())
	return p


# --- Tests ---

func test_case_none_when_master_has_no_familiar_proficiency() -> void:
	_setup_db()
	var master := _make_master(4, false)
	var p := _make_picker(master, {"new_class_proficiency_slots": 1, "new_general_proficiency_slots": 0})
	check(p.case_kind() == LevelUpFamiliarPicker.CASE_NONE,
		"no Familiar proficiency → case_kind is NONE")
	check(p.is_complete() == true, "NONE-case picker is trivially complete")


func test_case_a_first_bonding_no_familiar_history() -> void:
	_setup_db()
	# No familiars at all in DB. Replacement gate is a no-op when most_recent is empty.
	var master := _make_master(4, true)
	var p := _make_picker(master, {"new_class_proficiency_slots": 0, "new_general_proficiency_slots": 0})
	check(p.case_kind() == LevelUpFamiliarPicker.CASE_REPLACEMENT,
		"first bonding (no living, no dead) → Case A")


func test_case_a_replacement_gate_met_after_most_recent_death() -> void:
	_setup_db()
	# Most-recent familiar bonded at level 2; master is now level 4 (strictly greater).
	_seed_dead_familiar(2)
	var master := _make_master(4, true)
	var p := _make_picker(master, {"new_class_proficiency_slots": 0, "new_general_proficiency_slots": 0})
	check(p.case_kind() == LevelUpFamiliarPicker.CASE_REPLACEMENT,
		"dead familiar at L2, master now L4 → replacement gate met → Case A")


func test_case_none_when_replacement_gate_not_met() -> void:
	_setup_db()
	# Most-recent familiar bonded at level 4; master is also level 4 (not strictly greater).
	_seed_dead_familiar(4)
	var master := _make_master(4, true)
	var p := _make_picker(master, {"new_class_proficiency_slots": 1, "new_general_proficiency_slots": 0})
	check(p.case_kind() == LevelUpFamiliarPicker.CASE_NONE,
		"dead familiar at L4, master at L4 → replacement gate not met → NONE")


func test_case_b_living_familiar_and_master_gains_slots() -> void:
	_setup_db()
	_seed_living_familiar(2, [])  # familiar bonded at L2 with no prior picks
	var master := _make_master(4, true)
	var p := _make_picker(master, {"new_class_proficiency_slots": 1, "new_general_proficiency_slots": 0})
	check(p.case_kind() == LevelUpFamiliarPicker.CASE_BUDGET_GROWTH,
		"living familiar + master gains 1 class slot → Case B")
	check(p.is_complete() == false,
		"Case B picker requires the player to pick the new slot before is_complete")


func test_case_none_when_living_familiar_but_no_new_slots() -> void:
	_setup_db()
	_seed_living_familiar(2, [])
	var master := _make_master(4, true)
	var p := _make_picker(master, {"new_class_proficiency_slots": 0, "new_general_proficiency_slots": 0})
	check(p.case_kind() == LevelUpFamiliarPicker.CASE_NONE,
		"living familiar but no new slots → no Case B (budget unchanged)")


func test_case_b_returns_familiar_id_and_picks_in_final_choices() -> void:
	_setup_db()
	_seed_living_familiar(2, [
		{"proficiency_key": "adventuring", "specialization": ""},
	])
	var master := _make_master(4, true)
	var p := _make_picker(master, {"new_class_proficiency_slots": 1, "new_general_proficiency_slots": 0})
	check(p.case_kind() == LevelUpFamiliarPicker.CASE_BUDGET_GROWTH, "case is B")
	# Drive the embedded proficiency picker — pick a non-spec proficiency.
	var picker: FamiliarProficiencyPicker = p._proficiency_picker
	for k in picker.get_eligible_keys():
		if not picker._proficiency_registry.is_specialization(k) and not picker._picked_keys_set().has(k):
			picker._on_eligible_pressed(k)
			break
	# is_complete should be true once the new pick is made (budget = 3, picks = 2 prior + 1 new = 2 + ?)
	# Actually budget = master.proficiencies.selections_count (2) + new_slots (1) = 3.
	# Prior picks = 1. Need 2 more to be complete.
	# Pick another non-spec.
	for k in picker.get_eligible_keys():
		if not picker._proficiency_registry.is_specialization(k) and not picker._picked_keys_set().has(k):
			picker._on_eligible_pressed(k)
			break
	check(p.is_complete() == true, "Case B complete after filling budget")
	var choices: Dictionary = p.get_final_choices()
	check(String(choices.get("case", "")) == "B", "choices['case'] == 'B'")
	check(String(choices.get("familiar_id", "")) == TEST_LIVING_FAMILIAR_ID,
		"choices carries the existing familiar_id")
	var picks: Array = choices.get("proficiencies_chosen", [])
	check(picks.size() == 3, "choices includes prior + new picks (3 total), got %d" % picks.size())


func test_case_a_returns_form_and_proficiencies_in_final_choices() -> void:
	_setup_db()
	# No prior familiar — first bonding case.
	var master := _make_master(4, true)
	var p := _make_picker(master, {"new_class_proficiency_slots": 0, "new_general_proficiency_slots": 0})
	check(p.case_kind() == LevelUpFamiliarPicker.CASE_REPLACEMENT, "Case A")

	# Drive the embedded acquisition panel: form, cosmetic (auto), name.
	var acq: FamiliarAcquisitionPanel = p._acquisition_panel
	acq._form_picker._on_form_pressed("hawk")
	acq._form_picker._on_name_changed("Skyfeather")
	# Proficiency budget = master.proficiencies (2) + new_slots (0) = 2.
	# Pick two non-spec procs to satisfy is_complete.
	var picked := 0
	for k in acq._proficiency_picker.get_eligible_keys():
		if picked >= 2:
			break
		if not acq._proficiency_picker._proficiency_registry.is_specialization(k):
			acq._proficiency_picker._on_eligible_pressed(k)
			picked += 1

	check(p.is_complete() == true, "Case A complete after form + name + 2 picks")
	var choices: Dictionary = p.get_final_choices()
	check(String(choices.get("case", "")) == "A", "choices['case'] == 'A'")
	check(String(choices.get("form_key", "")) == "hawk", "form_key 'hawk' captured")
	check(String(choices.get("name", "")) == "Skyfeather", "name captured")
	check((choices.get("proficiencies_chosen", []) as Array).size() == 2,
		"choices['proficiencies_chosen'] has 2 picks")
	check(int(choices.get("proficiency_count_cached", -1)) == 2,
		"proficiency_count_cached stamped to budget (2)")
