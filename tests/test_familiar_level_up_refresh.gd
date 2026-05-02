extends "res://tests/test_suite_base.gd"

## Tests for FamiliarController level-up cache refresh.
##
## When master gains a level, the familiar's cached HD progression / HP / INT
## / proficiency budget all refresh from the new master state. Verified by:
##   - bonding a familiar at master L1 (familiar at 0.5 HD / NM-saves)
##   - bumping the master to L4 in the DB
##   - emitting EventBus.character_leveled_up
##   - reading the familiar row back and verifying it's now 2 HD / fighter-L2
##     with damage_bonus +2 and proficiency budget refreshed.

const TEST_CAMPAIGN := "test_lvl_campaign"
const TEST_MASTER := "test_lvl_master"


func run_all_tests() -> void:
	test_level_up_refreshes_hd_progression()
	test_level_up_refreshes_hp_max_with_bankers_rounding()
	test_level_up_refreshes_proficiency_budget()
	test_level_up_with_no_living_familiar_is_noop()
	test_level_up_with_dead_familiar_does_not_refresh_dead_row()
	test_explicit_refresh_returns_true_when_familiar_exists()

	_cleanup()
	if not has_failures():
		print("FamiliarLevelUpRefresh: all tests passed.")


# --- Setup / teardown ---

func _setup(master_level: int = 1, master_hp_max: int = 4, master_int: int = 13) -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Level-up Refresh Test"])
	CampaignRepository.create_character({
		"id": TEST_MASTER,
		"campaign_id": TEST_CAMPAIGN,
		"name": "LU Master",
		"character_type": "pc",
		"persistence_tier": "full",
		"race": "human",
		"character_class": "mage",
		"combat_progression": "mage",
		"level": master_level,
		"xp": 0,
		"strength": 10, "intelligence": master_int, "wisdom": 10,
		"dexterity": 10, "constitution": 10, "charisma": 10,
		"hp_max": master_hp_max, "hp_current": master_hp_max,
	})


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM familiars WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_proficiencies WHERE character_id = ?", [TEST_MASTER])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_MASTER])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _bond_familiar_at_l1() -> String:
	var prog: Dictionary = FamiliarData.compute_progression_for_master_level(1)
	return CampaignRepository.create_familiar({
		"campaign_id": TEST_CAMPAIGN,
		"master_character_id": TEST_MASTER,
		"form_key": "bat",
		"name": "Echo",
		"hp_current": 2,
		"hp_max_cached": 2,
		"hd_dice": int(prog["hd_dice"]),
		"hd_modifier_hp": int(prog["hd_modifier_hp"]),
		"is_half_hd": bool(prog["is_half_hd"]),
		"attack_save_class": String(prog["attack_save_class"]),
		"attack_save_level": int(prog["attack_save_level"]),
		"damage_bonus": int(prog["damage_bonus"]),
		"int_cached": 13,
		"proficiency_count_cached": 0,
		"is_alive": true,
		"bonded_at_master_level": 1,
	})


func _set_master_level(new_level: int, new_hp_max: int, new_int: int = 14) -> void:
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET level = ?, hp_max = ?, hp_current = ?, intelligence = ? WHERE id = ?",
		[new_level, new_hp_max, new_hp_max, new_int, TEST_MASTER])


# --- Tests ---

func test_level_up_refreshes_hd_progression() -> void:
	_setup(1, 4, 13)
	var fid := _bond_familiar_at_l1()

	# Pre-check: bonded at L1 means 0.5 HD / NM
	var pre := CampaignRepository.get_familiar(fid)
	check(int(pre.get("is_half_hd", 0)) == 1, "pre: is_half_hd 1 at master L1")
	check(String(pre.get("attack_save_class", "")) == "NM", "pre: NM at L1")

	# Master levels up to L4 → expect 2 HD / fighter-L2 / +2 dmg
	_set_master_level(4, 14)
	EventBus.character_leveled_up.emit(TEST_MASTER, 4)

	var post := CampaignRepository.get_familiar(fid)
	check(int(post.get("is_half_hd", 1)) == 0, "post-L4: no longer half-HD")
	check(int(post.get("hd_dice", -1)) == 2, "post-L4: hd_dice=2")
	check(int(post.get("hd_modifier_hp", -1)) == 0, "post-L4: hd_modifier_hp=0")
	check(String(post.get("attack_save_class", "")) == "fighter", "post-L4: fighter")
	check(int(post.get("attack_save_level", -1)) == 2, "post-L4: attack_save_level=2")
	check(int(post.get("damage_bonus", -1)) == 2, "post-L4: damage_bonus=2")


func test_level_up_refreshes_hp_max_with_bankers_rounding() -> void:
	_setup(1, 4, 13)
	var fid := _bond_familiar_at_l1()

	# L4 master with hp_max=14 → familiar hp_max = 14/2 = 7 (no rounding needed)
	_set_master_level(4, 14)
	EventBus.character_leveled_up.emit(TEST_MASTER, 4)

	var post := CampaignRepository.get_familiar(fid)
	check(int(post.get("hp_max_cached", -1)) == 7, "L4 master 14 hp → familiar hp_max 7, got %d" % post.get("hp_max_cached", -1))
	check(int(post.get("int_cached", -1)) == 14, "INT mirrors new master INT 14")

	# Now test banker's rounding: master hp_max = 5 → familiar hp_max = 5/2 = 2.5 → 2 (round-to-even)
	_set_master_level(4, 5)
	EventBus.character_leveled_up.emit(TEST_MASTER, 4)
	post = CampaignRepository.get_familiar(fid)
	check(int(post.get("hp_max_cached", -1)) == 2, "5/2 banker's-round = 2, got %d" % post.get("hp_max_cached", -1))


func test_level_up_refreshes_proficiency_budget() -> void:
	_setup(1, 4, 13)
	var fid := _bond_familiar_at_l1()

	# Seed master with two proficiencies, totaling 3 selections (1 + 2 stacked)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_proficiencies
			(character_id, proficiency_key, rank, slot_type, selections_count, specialization)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [TEST_MASTER, "familiar", 1, "class", 1, ""])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_proficiencies
			(character_id, proficiency_key, rank, slot_type, selections_count, specialization)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [TEST_MASTER, "alchemy", 1, "class", 2, ""])

	_set_master_level(4, 14)
	EventBus.character_leveled_up.emit(TEST_MASTER, 4)

	var post := CampaignRepository.get_familiar(fid)
	check(int(post.get("proficiency_count_cached", -1)) == 3,
		"proficiency_count = sum of selections_count = 1+2 = 3, got %d" % post.get("proficiency_count_cached", -1))


func test_level_up_with_no_living_familiar_is_noop() -> void:
	_setup(1, 4)
	# No familiar bonded at all
	_set_master_level(4, 14)
	EventBus.character_leveled_up.emit(TEST_MASTER, 4)

	var ok := FamiliarController.refresh_familiar_stats_for_master(TEST_MASTER)
	check(ok == false, "refresh returns false when master has no familiar")


func test_level_up_with_dead_familiar_does_not_refresh_dead_row() -> void:
	_setup(1, 4)
	var fid := _bond_familiar_at_l1()
	CampaignRepository.kill_familiar(fid)

	_set_master_level(4, 14)
	EventBus.character_leveled_up.emit(TEST_MASTER, 4)

	var fam_row := CampaignRepository.get_familiar(fid)
	check(String(fam_row.get("attack_save_class", "")) == "NM",
		"dead familiar's stats untouched — still NM (was bonded at L1)")
	check(int(fam_row.get("hd_dice", 99)) == 0,
		"dead familiar's hd_dice still 0 (no refresh)")


func test_explicit_refresh_returns_true_when_familiar_exists() -> void:
	_setup(1, 4)
	_bond_familiar_at_l1()
	_set_master_level(2, 6)
	# Direct API call (not via signal)
	var ok := FamiliarController.refresh_familiar_stats_for_master(TEST_MASTER)
	check(ok == true, "refresh returns true when a living familiar was found and updated")
