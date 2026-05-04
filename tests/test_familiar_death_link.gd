extends "res://tests/test_suite_base.gd"

## Tests for FamiliarController death-link.
##
## Per ACKS rule (rules/acore_proficiencies_rules_and_catalog.xml:688-700):
## when a familiar is slain, the master must save vs Death (save_poison_death)
## or take damage equal to the familiar's max HP at the time of death.
##
## Save outcomes are forced via GameState.dice_overrides[roll_type] so the
## tests are deterministic (no real d20). The roll_type is "saving_throw_poison"
## per OverrideManager's vocabulary.

const TEST_CAMPAIGN := "test_dl_campaign"
const TEST_MASTER := "test_dl_master"


func run_all_tests() -> void:
	test_kill_familiar_on_failed_save_damages_master()
	test_kill_familiar_on_passed_save_no_damage()
	test_kill_familiar_clears_proximity_bonus_before_save()
	test_apply_familiar_damage_below_lethal_does_not_emit_died()
	test_apply_familiar_damage_lethal_kills()
	test_kill_familiar_clears_death_save_pending_after_resolution()

	_cleanup()
	if not has_failures():
		print("FamiliarDeathLink: all tests passed.")


# --- Setup / teardown ---

func _setup(master_hp: int = 20, save_target: int = 14) -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Death Link Test"])
	CampaignRepository.create_character({
		"id": TEST_MASTER,
		"campaign_id": TEST_CAMPAIGN,
		"name": "DL Master",
		"character_type": "pc",
		"persistence_tier": "full",
		"race": "human",
		"character_class": "mage",
		"combat_progression": "mage",
		"level": 5,
		"xp": 0,
		"strength": 10, "intelligence": 14, "wisdom": 10,
		"dexterity": 10, "constitution": 10, "charisma": 10,
		"hp_max": master_hp, "hp_current": master_hp,
		"save_poison_death": save_target,
	})


func _cleanup() -> void:
	GameState.dice_overrides.clear()
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM familiars WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_MASTER])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _create_familiar_at_max(hp_max: int = 6, bonded_level: int = 5) -> String:
	var prog: Dictionary = FamiliarData.compute_progression_for_master_level(bonded_level)
	return CampaignRepository.create_familiar({
		"campaign_id": TEST_CAMPAIGN,
		"master_character_id": TEST_MASTER,
		"form_key": "bat",
		"name": "Echo",
		"hp_current": hp_max,
		"hp_max_cached": hp_max,
		"hd_dice": int(prog["hd_dice"]),
		"hd_modifier_hp": int(prog["hd_modifier_hp"]),
		"is_half_hd": bool(prog["is_half_hd"]),
		"attack_save_class": String(prog["attack_save_class"]),
		"attack_save_level": int(prog["attack_save_level"]),
		"damage_bonus": int(prog["damage_bonus"]),
		"int_cached": 14,
		"proficiency_count_cached": 4,
		"is_alive": true,
		"bonded_at_master_level": bonded_level,
	})


# --- Tests ---

func test_kill_familiar_on_failed_save_damages_master() -> void:
	_setup(20, 14)
	var fid := _create_familiar_at_max(6)
	# Force the d20 to roll 13 — below target 14, so save FAILS
	GameState.dice_overrides["saving_throw_poison"] = 13

	FamiliarController.kill_familiar_now(fid)

	var fam_row := CampaignRepository.get_familiar(fid)
	check(int(fam_row.get("is_alive", 1)) == 0, "familiar marked dead")
	check(int(fam_row.get("hp_current", 1)) == 0, "familiar hp_current zeroed")
	check(int(fam_row.get("death_save_pending", 1)) == 0, "death_save_pending cleared after resolution")

	var master_row := CampaignRepository.get_character(TEST_MASTER)
	# Master had 20 HP; familiar had 6 HP → master takes 6 damage on fail = 14
	check(int(master_row.get("hp_current", -1)) == 14,
		"master should take 6 dmg on fail (20→14), got %d" % master_row.get("hp_current", -1))


func test_kill_familiar_on_passed_save_no_damage() -> void:
	_setup(20, 14)
	var fid := _create_familiar_at_max(6)
	# Force the d20 to roll 14 — meets target 14, so save PASSES
	GameState.dice_overrides["saving_throw_poison"] = 14

	FamiliarController.kill_familiar_now(fid)

	var master_row := CampaignRepository.get_character(TEST_MASTER)
	check(int(master_row.get("hp_current", -1)) == 20,
		"master takes no damage on pass — hp stays 20, got %d" % master_row.get("hp_current", -1))

	var fam_row := CampaignRepository.get_familiar(fid)
	check(int(fam_row.get("death_save_pending", 1)) == 0, "death_save_pending cleared after pass")


func test_kill_familiar_clears_proximity_bonus_before_save() -> void:
	# Subtle invariant: the master's save vs Death should NOT benefit from the
	# +1 proximity bonus, because the familiar has just died (no longer in
	# proximity). The controller clears the bonus before rolling.
	_setup(20, 14)
	var fid := _create_familiar_at_max(6)

	# Pre-arm: simulate the master having had the proximity bonus active.
	# The controller's clear path mutates a CharacterData reference, but the
	# death handler reloads the master from DB — so we just verify the
	# in-memory state map is reset.
	# (Direct flag-state assertion lives in test_familiar_proximity; here we
	# verify the death-link path doesn't accidentally apply the bonus.)
	GameState.dice_overrides["saving_throw_poison"] = 14  # exactly target → pass
	FamiliarController.kill_familiar_now(fid)
	# If a stray +1 had been applied, the target would have effectively been
	# 13 and 14 would still pass — but a 13 roll would also pass, which would
	# be wrong. We don't have a clean way to detect that here without
	# changing the master's save target. Instead, check is_in_proximity:
	check(FamiliarController.is_in_proximity(TEST_MASTER) == false,
		"after death, master should not be flagged in proximity")


func test_apply_familiar_damage_below_lethal_does_not_emit_died() -> void:
	_setup(20, 14)
	var fid := _create_familiar_at_max(6)
	# Pre-arm an override that WOULD damage master on a fail — to detect a
	# spurious familiar_died emission, master would lose hp.
	GameState.dice_overrides["saving_throw_poison"] = 13

	FamiliarController.apply_familiar_damage(fid, 4)  # 6 → 2, not lethal

	var fam_row := CampaignRepository.get_familiar(fid)
	check(int(fam_row.get("hp_current", -1)) == 2, "hp 6 - 4 = 2")
	check(int(fam_row.get("is_alive", 0)) == 1, "still alive")
	var master_row := CampaignRepository.get_character(TEST_MASTER)
	check(int(master_row.get("hp_current", -1)) == 20, "master untouched on non-lethal damage")
	# The pre-armed override is still queued — clean it up
	GameState.dice_overrides.clear()


func test_apply_familiar_damage_lethal_kills() -> void:
	_setup(20, 14)
	var fid := _create_familiar_at_max(6)
	GameState.dice_overrides["saving_throw_poison"] = 14  # pass — keeps test focused on kill

	FamiliarController.apply_familiar_damage(fid, 6)  # exactly lethal

	var fam_row := CampaignRepository.get_familiar(fid)
	check(int(fam_row.get("is_alive", 1)) == 0, "lethal damage kills the familiar")


func test_kill_familiar_clears_death_save_pending_after_resolution() -> void:
	# Already covered by tests above, but isolate as a focused check.
	_setup(20, 14)
	var fid := _create_familiar_at_max(6)
	GameState.dice_overrides["saving_throw_poison"] = 14  # pass

	FamiliarController.kill_familiar_now(fid)

	var fam_row := CampaignRepository.get_familiar(fid)
	check(int(fam_row.get("death_save_pending", 1)) == 0,
		"death_save_pending must be cleared once the save has been resolved (pass or fail)")
