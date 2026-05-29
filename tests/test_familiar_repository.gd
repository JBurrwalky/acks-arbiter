extends "res://tests/test_suite_base.gd"

## Tests for the familiars table CRUD methods on CampaignRepository.
## Verifies: insert, fetch (living/most-recent/by-id), update whitelist,
## kill_familiar, the unique-living-per-master constraint, and
## clear_familiar_death_save.

const TEST_CAMPAIGN := "test_fam_campaign"
const TEST_MASTER := "test_fam_master"
const TEST_MASTER_B := "test_fam_master_b"


func run_all_tests() -> void:
	test_create_and_fetch()
	test_unique_living_per_master_rejects_second()
	test_kill_then_create_replacement_succeeds()
	test_get_most_recent_prefers_living()
	test_get_most_recent_after_death()
	test_update_familiar_whitelist()
	test_clear_death_save_pending()
	test_kill_clears_hp_and_sets_death_save_pending()
	test_two_masters_each_have_living_familiar()

	_cleanup()
	if not has_failures():
		print("FamiliarRepository: all tests passed.")


# --- Setup / teardown ---

func _setup() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Familiar Test"])
	for master_id in [TEST_MASTER, TEST_MASTER_B]:
		CampaignRepository.create_character({
			"id": master_id,
			"campaign_id": TEST_CAMPAIGN,
			"name": "Master_" + master_id,
			"character_type": "pc",
			"persistence_tier": "full",
			"race": "human",
			"character_class": "mage",
			"combat_progression": "mage",
			"level": 3,
			"xp": 0,
			"strength": 10, "intelligence": 14, "wisdom": 10,
			"dexterity": 10, "constitution": 10, "charisma": 10,
		})


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM familiars WHERE campaign_id = ?", [TEST_CAMPAIGN])
	for master_id in [TEST_MASTER, TEST_MASTER_B]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [master_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _make_familiar_data(master_id: String, form_key: String = "bat",
		bonded_level: int = 1, hp_max: int = 4) -> Dictionary:
	var prog: Dictionary = FamiliarData.compute_progression_for_master_level(bonded_level)
	return {
		"campaign_id": TEST_CAMPAIGN,
		"master_character_id": master_id,
		"form_key": form_key,
		"cosmetic_species": form_key.capitalize(),
		"name": "Test_" + form_key,
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
		"proficiencies_chosen": "[]",
		"is_alive": true,
		"bonded_at_master_level": bonded_level,
		"death_save_pending": false,
	}


# --- Tests ---

func test_create_and_fetch() -> void:
	_setup()
	var fid := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER))
	check(not fid.is_empty(), "create_familiar should return a non-empty id")

	var row := CampaignRepository.get_familiar(fid)
	check(not row.is_empty(), "get_familiar should return the inserted row")
	check(str(row.get("master_character_id", "")) == TEST_MASTER, "master_character_id round-trips")
	check(str(row.get("form_key", "")) == "bat", "form_key round-trips")
	check(int(row.get("is_alive", 0)) == 1, "is_alive defaults to 1")


func test_unique_living_per_master_rejects_second() -> void:
	_setup()
	var fid_1 := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER))
	check(not fid_1.is_empty(), "first familiar inserts")

	# Suppress the expected push_error from the partial-unique-index conflict.
	# create_familiar pushes an error on conflict but should return "".
	var fid_2 := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER, "hawk"))
	check(fid_2.is_empty(), "second living familiar for the same master should be rejected by the unique partial index")

	var living := CampaignRepository.get_living_familiar_for_master(TEST_MASTER)
	check(String(living.get("id", "")) == fid_1, "the original familiar is still the living one")


func test_kill_then_create_replacement_succeeds() -> void:
	_setup()
	var fid_1 := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER, "bat", 1))
	check(CampaignRepository.kill_familiar(fid_1), "kill_familiar should succeed")

	# After kill, the unique partial index no longer covers the dead row,
	# so a new familiar can be bonded.
	var fid_2 := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER, "hawk", 2))
	check(not fid_2.is_empty(), "replacement familiar should insert after the original is dead")

	var living := CampaignRepository.get_living_familiar_for_master(TEST_MASTER)
	check(String(living.get("id", "")) == fid_2, "the new familiar is now the living one")
	check(String(living.get("form_key", "")) == "hawk", "the new form is the replacement")


func test_get_most_recent_prefers_living() -> void:
	_setup()
	var fid_1 := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER, "bat", 1))
	CampaignRepository.kill_familiar(fid_1)
	var fid_2 := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER, "hawk", 2))

	var recent := CampaignRepository.get_most_recent_familiar_for_master(TEST_MASTER)
	check(String(recent.get("id", "")) == fid_2, "most-recent should prefer the living one over the dead one")


func test_get_most_recent_after_death() -> void:
	_setup()
	var fid_1 := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER, "bat", 1))
	CampaignRepository.kill_familiar(fid_1)
	# No replacement yet — most-recent should return the dead one.
	var recent := CampaignRepository.get_most_recent_familiar_for_master(TEST_MASTER)
	check(String(recent.get("id", "")) == fid_1, "most-recent returns the dead familiar when nothing else exists")
	check(int(recent.get("bonded_at_master_level", 0)) == 1, "dead familiar's bonded_at_master_level is preserved")


func test_update_familiar_whitelist() -> void:
	_setup()
	var fid := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER))
	# Allowed field
	check(CampaignRepository.update_familiar(fid, {"hp_current": 2}),
		"update_familiar should accept whitelisted hp_current")
	var row := CampaignRepository.get_familiar(fid)
	check(int(row.get("hp_current", -1)) == 2, "hp_current was updated")

	# Disallowed field — silently ignored, no UPDATE issued
	check(CampaignRepository.update_familiar(fid, {"master_character_id": "spoofed"}),
		"update_familiar accepts the call but should ignore non-whitelisted fields")
	row = CampaignRepository.get_familiar(fid)
	check(str(row.get("master_character_id", "")) == TEST_MASTER,
		"master_character_id is NOT mutable via update_familiar")


func test_clear_death_save_pending() -> void:
	_setup()
	var fid := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER))
	CampaignRepository.kill_familiar(fid)
	var row := CampaignRepository.get_familiar(fid)
	check(int(row.get("death_save_pending", 0)) == 1, "kill sets death_save_pending=1")

	check(CampaignRepository.clear_familiar_death_save(fid), "clear_familiar_death_save should succeed")
	row = CampaignRepository.get_familiar(fid)
	check(int(row.get("death_save_pending", 1)) == 0, "death_save_pending cleared")


func test_kill_clears_hp_and_sets_death_save_pending() -> void:
	_setup()
	var fid := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER, "bat", 1, 4))
	check(CampaignRepository.kill_familiar(fid), "kill_familiar succeeds")
	var row := CampaignRepository.get_familiar(fid)
	check(int(row.get("is_alive", 1)) == 0, "is_alive flipped to 0")
	check(int(row.get("hp_current", 1)) == 0, "hp_current zeroed on kill")
	check(int(row.get("death_save_pending", 0)) == 1, "death_save_pending set on kill")


func test_two_masters_each_have_living_familiar() -> void:
	_setup()
	var fid_a := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER, "bat"))
	var fid_b := CampaignRepository.create_familiar(_make_familiar_data(TEST_MASTER_B, "hawk"))
	check(not fid_a.is_empty() and not fid_b.is_empty(), "both inserts succeed (different masters)")
	check(String(CampaignRepository.get_living_familiar_for_master(TEST_MASTER).get("id", "")) == fid_a,
		"master A has its own familiar")
	check(String(CampaignRepository.get_living_familiar_for_master(TEST_MASTER_B).get("id", "")) == fid_b,
		"master B has its own familiar — the unique constraint is per-master, not global")
