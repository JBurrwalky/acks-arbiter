extends "res://tests/test_suite_base.gd"

## Tests for FamiliarController.apply_proximity_for_master — Stage 2.x
## caller-driven proximity refresh that auto-detects the master's living
## familiar in the DB and applies/clears the +1 saves bonus on the live
## CharacterData. Called from SessionRunner.load_session,
## CharacterCreationScreen._persist_familiar_if_bonded, and
## cs_tab_advancement._on_confirm_level_up.

const TEST_CAMPAIGN := "test_auto_prox_campaign"
const TEST_MASTER := "test_auto_prox_master"


func run_all_tests() -> void:
	test_no_familiar_means_no_bonus()
	test_living_familiar_applies_bonus()
	test_idempotent_no_stacking_on_repeated_apply()
	test_kill_familiar_then_apply_clears_bonus()
	test_two_masters_independent_state()

	_cleanup()
	if not has_failures():
		print("FamiliarAutoProximity: all tests passed.")


# --- Setup / teardown ---

func _setup() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Auto-Prox Test"])
	CampaignRepository.create_character({
		"id": TEST_MASTER,
		"campaign_id": TEST_CAMPAIGN,
		"name": "Auto-Prox Master",
		"character_type": "pc",
		"persistence_tier": "full",
		"race": "human",
		"character_class": "mage",
		"combat_progression": "mage",
		"level": 3,
		"xp": 0,
		"strength": 10, "intelligence": 14, "wisdom": 10,
		"dexterity": 10, "constitution": 10, "charisma": 10,
		"hp_max": 12, "hp_current": 12,
		"save_poison_death": 14,
	})


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM familiars WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id LIKE ?", ["test_auto_prox_%"])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _make_live_master(master_id: String = TEST_MASTER) -> CharacterData:
	var c := CharacterData.new()
	c.id = master_id
	c.campaign_id = TEST_CAMPAIGN
	c.name = "Master"
	c.character_class = "mage"
	c.combat_progression = "mage"
	c.level = 3
	c.hp_max = 12
	c.hp_current = 12
	c.intelligence = 14
	# Defaults from CharacterData (NM/L0 baseline): save_poison_death = 14.
	# Reset the controller's per-master state map — single autoload instance
	# leaks state across tests reusing the same id.
	FamiliarController.clear_proximity_for_master(c)
	return c


func _create_living_familiar(master_id: String = TEST_MASTER) -> String:
	var prog: Dictionary = FamiliarData.compute_progression_for_master_level(3)
	return CampaignRepository.create_familiar({
		"campaign_id": TEST_CAMPAIGN,
		"master_character_id": master_id,
		"form_key": "bat",
		"name": "Echo",
		"hp_current": 4, "hp_max_cached": 4,
		"hd_dice": int(prog["hd_dice"]),
		"hd_modifier_hp": int(prog["hd_modifier_hp"]),
		"is_half_hd": bool(prog["is_half_hd"]),
		"attack_save_class": String(prog["attack_save_class"]),
		"attack_save_level": int(prog["attack_save_level"]),
		"damage_bonus": int(prog["damage_bonus"]),
		"int_cached": 14, "proficiency_count_cached": 0,
		"is_alive": true, "bonded_at_master_level": 1,
	})


# --- Tests ---

func test_no_familiar_means_no_bonus() -> void:
	_setup()
	var master := _make_live_master()
	# No familiar in DB for this master.
	FamiliarController.apply_proximity_for_master(master)
	check(master.get_effective_save("save_poison_death") == 14,
		"baseline save (14) preserved when no familiar exists")
	check(FamiliarController.is_in_proximity(master.id) == false,
		"is_in_proximity reports false")


func test_living_familiar_applies_bonus() -> void:
	_setup()
	_create_living_familiar()
	var master := _make_live_master()
	FamiliarController.apply_proximity_for_master(master)
	check(master.get_effective_save("save_poison_death") == 13,
		"save target drops by 1 to 13 with living familiar")
	check(FamiliarController.is_in_proximity(master.id) == true,
		"is_in_proximity reports true")


func test_idempotent_no_stacking_on_repeated_apply() -> void:
	_setup()
	_create_living_familiar()
	var master := _make_live_master()
	FamiliarController.apply_proximity_for_master(master)
	FamiliarController.apply_proximity_for_master(master)
	FamiliarController.apply_proximity_for_master(master)
	check(master.get_effective_save("save_poison_death") == 13,
		"three applies still give a single -1 (idempotent), got %d" % master.get_effective_save("save_poison_death"))


func test_kill_familiar_then_apply_clears_bonus() -> void:
	_setup()
	var fid := _create_living_familiar()
	var master := _make_live_master()
	FamiliarController.apply_proximity_for_master(master)
	check(master.get_effective_save("save_poison_death") == 13, "pre: bonus active")

	# Kill the familiar in the DB and re-apply — the helper should detect no
	# living familiar and clear the bonus.
	CampaignRepository.kill_familiar(fid)
	FamiliarController.apply_proximity_for_master(master)
	check(master.get_effective_save("save_poison_death") == 14,
		"post-death + re-apply: save target back to 14, got %d" % master.get_effective_save("save_poison_death"))
	check(FamiliarController.is_in_proximity(master.id) == false,
		"is_in_proximity flips to false after kill + re-apply")


func test_two_masters_independent_state() -> void:
	_setup()
	# Seed a second master with their own living familiar.
	var second_id := "test_auto_prox_master_b"
	CampaignRepository.create_character({
		"id": second_id,
		"campaign_id": TEST_CAMPAIGN,
		"name": "Other Master",
		"character_type": "pc",
		"persistence_tier": "full",
		"race": "human",
		"character_class": "mage",
		"combat_progression": "mage",
		"level": 1,
		"xp": 0,
		"strength": 10, "intelligence": 12, "wisdom": 10,
		"dexterity": 10, "constitution": 10, "charisma": 10,
		"hp_max": 4, "hp_current": 4,
	})
	# First master gets a familiar; second master does not.
	_create_living_familiar(TEST_MASTER)
	var master_a := _make_live_master(TEST_MASTER)
	var master_b := _make_live_master(second_id)

	FamiliarController.apply_proximity_for_master(master_a)
	FamiliarController.apply_proximity_for_master(master_b)

	check(master_a.get_effective_save("save_poison_death") == 13,
		"master A (with familiar) has bonus")
	check(master_b.get_effective_save("save_poison_death") == 14,
		"master B (no familiar) has no bonus")
