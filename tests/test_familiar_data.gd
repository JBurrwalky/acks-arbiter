extends "res://tests/test_suite_base.gd"

## Unit tests for FamiliarData.
##
## Covers stat derivation from master (HD progression, HP halving with banker's
## rounding, fighter attack/save level, damage bonus), serialization round-trip,
## replacement gating, form-stat read-through, and proficiency-count
## aggregation. The HD-progression rule is documented in
## generation/gdd-familiars.md §3.3.


func run_all_tests() -> void:
	# HD progression — comprehensive table-driven test
	test_progression_master_l1_half_hd_normal_man()
	test_progression_master_l2_one_hd_fighter_l1()
	test_progression_master_l3_one_plus_two_hd_still_fighter_l1()
	test_progression_master_l4_two_hd_fighter_l2()
	test_progression_master_l5_two_plus_two_hd_still_fighter_l2()
	test_progression_master_l6_three_hd_fighter_l3()
	test_progression_master_l7_three_plus_two_hd_still_fighter_l3()
	test_progression_master_l8_four_hd_fighter_l4()

	# Stat derivation against an actual CharacterData
	test_derive_stats_at_master_l1_half_hd_nm()
	test_derive_stats_at_master_l2_writes_fighter_l1()
	test_derive_stats_at_master_l3_writes_fighter_l1_with_hp_modifier()
	test_derive_stats_at_master_l4_writes_fighter_l2()

	# HP halving with banker's rounding
	test_derive_stats_bankers_rounding_even()
	test_derive_stats_bankers_rounding_odd()
	test_derive_stats_caps_current_hp_at_new_max()

	# Display + INT + proficiencies
	test_hd_display_strings()
	test_derive_stats_proficiency_count_aggregates_selections()

	# Serialization
	test_to_dict_serializes_proficiencies_chosen_as_json()
	test_to_dict_serializes_is_half_hd_as_int()
	test_from_db_round_trip()

	# Replacement gate
	test_can_replace_at_blocked_when_alive()
	test_can_replace_at_strict_inequality()

	# Form read-through
	test_form_stat_readthrough_defaults()
	test_form_stat_readthrough_populated()

	if not has_failures():
		print("FamiliarData: all tests passed.")


# --- Helpers ---

func _make_master(level: int, hp_max: int, intelligence: int = 12) -> CharacterData:
	var c := CharacterData.new()
	c.id = "test_master"
	c.campaign_id = "test_campaign"
	c.name = "Master"
	c.character_type = "pc"
	c.character_class = "mage"
	c.combat_progression = "mage"
	c.level = level
	c.hp_max = hp_max
	c.hp_current = hp_max
	c.intelligence = intelligence
	c.proficiencies = []
	return c


func _check_progression(p: Dictionary, hd_dice: int, mod_hp: int, half: bool,
		cls: String, lvl: int, dmg: int, label: String) -> void:
	check(int(p["hd_dice"]) == hd_dice, "%s: hd_dice expected %d, got %d" % [label, hd_dice, p["hd_dice"]])
	check(int(p["hd_modifier_hp"]) == mod_hp, "%s: hd_modifier_hp expected %d, got %d" % [label, mod_hp, p["hd_modifier_hp"]])
	check(bool(p["is_half_hd"]) == half, "%s: is_half_hd expected %s, got %s" % [label, half, p["is_half_hd"]])
	check(String(p["attack_save_class"]) == cls, "%s: attack_save_class expected %s, got %s" % [label, cls, p["attack_save_class"]])
	check(int(p["attack_save_level"]) == lvl, "%s: attack_save_level expected %d, got %d" % [label, lvl, p["attack_save_level"]])
	check(int(p["damage_bonus"]) == dmg, "%s: damage_bonus expected %d, got %d" % [label, dmg, p["damage_bonus"]])


# --- HD progression tests (pure static) ---

func test_progression_master_l1_half_hd_normal_man() -> void:
	_check_progression(FamiliarData.compute_progression_for_master_level(1),
		0, 0, true, "NM", 0, 0, "L1")


func test_progression_master_l2_one_hd_fighter_l1() -> void:
	_check_progression(FamiliarData.compute_progression_for_master_level(2),
		1, 0, false, "fighter", 1, 1, "L2")


func test_progression_master_l3_one_plus_two_hd_still_fighter_l1() -> void:
	_check_progression(FamiliarData.compute_progression_for_master_level(3),
		1, 2, false, "fighter", 1, 1, "L3")


func test_progression_master_l4_two_hd_fighter_l2() -> void:
	_check_progression(FamiliarData.compute_progression_for_master_level(4),
		2, 0, false, "fighter", 2, 2, "L4")


func test_progression_master_l5_two_plus_two_hd_still_fighter_l2() -> void:
	_check_progression(FamiliarData.compute_progression_for_master_level(5),
		2, 2, false, "fighter", 2, 2, "L5")


func test_progression_master_l6_three_hd_fighter_l3() -> void:
	_check_progression(FamiliarData.compute_progression_for_master_level(6),
		3, 0, false, "fighter", 3, 3, "L6")


func test_progression_master_l7_three_plus_two_hd_still_fighter_l3() -> void:
	_check_progression(FamiliarData.compute_progression_for_master_level(7),
		3, 2, false, "fighter", 3, 3, "L7")


func test_progression_master_l8_four_hd_fighter_l4() -> void:
	_check_progression(FamiliarData.compute_progression_for_master_level(8),
		4, 0, false, "fighter", 4, 4, "L8")


# --- derive_stats_from_master writes the right fields ---

func test_derive_stats_at_master_l1_half_hd_nm() -> void:
	var master := _make_master(1, 6, 13)
	var f := FamiliarData.new()
	f.derive_stats_from_master(master)
	check(f.is_half_hd == true, "L1 master: familiar should be half-HD")
	check(f.attack_save_class == "NM", "L1: attacks/saves as NM")
	check(f.attack_save_level == 0, "L1: NM at level 0")
	check(f.damage_bonus == 0, "L1: no damage bonus")
	check(f.hp_max_cached == 3, "L1: hp_max = 6/2 = 3, got %d" % f.hp_max_cached)
	check(f.int_cached == 13, "INT mirrors master")


func test_derive_stats_at_master_l2_writes_fighter_l1() -> void:
	var master := _make_master(2, 8)
	var f := FamiliarData.new()
	f.derive_stats_from_master(master)
	check(f.is_half_hd == false, "L2: not half-HD")
	check(f.hd_dice == 1 and f.hd_modifier_hp == 0, "L2: 1 HD no modifier")
	check(f.attack_save_class == "fighter", "L2: attacks/saves as fighter")
	check(f.attack_save_level == 1, "L2: fighter level 1")
	check(f.damage_bonus == 1, "L2: +1 damage")


func test_derive_stats_at_master_l3_writes_fighter_l1_with_hp_modifier() -> void:
	var master := _make_master(3, 12)
	var f := FamiliarData.new()
	f.derive_stats_from_master(master)
	check(f.hd_dice == 1, "L3: still 1 dice")
	check(f.hd_modifier_hp == 2, "L3: +2 hp modifier")
	check(f.attack_save_level == 1, "L3: still fighter L1")
	check(f.damage_bonus == 1, "L3: still +1 damage (matches fighter level)")


func test_derive_stats_at_master_l4_writes_fighter_l2() -> void:
	var master := _make_master(4, 14)
	var f := FamiliarData.new()
	f.derive_stats_from_master(master)
	check(f.hd_dice == 2 and f.hd_modifier_hp == 0, "L4: 2 HD")
	check(f.attack_save_level == 2, "L4: fighter L2")
	check(f.damage_bonus == 2, "L4: +2 damage")
	check(f.hp_max_cached == 7, "L4: hp_max = 14/2 = 7")


# --- HP halving / banker's rounding ---

func test_derive_stats_bankers_rounding_even() -> void:
	# 5 / 2 = 2.5 → banker's-round to 2 (nearest even)
	var master := _make_master(1, 5)
	var f := FamiliarData.new()
	f.derive_stats_from_master(master)
	check(f.hp_max_cached == 2, "5/2 banker's-round to even should be 2, got %d" % f.hp_max_cached)


func test_derive_stats_bankers_rounding_odd() -> void:
	# 7 / 2 = 3.5 → banker's-round to 4 (nearest even)
	var master := _make_master(1, 7)
	var f := FamiliarData.new()
	f.derive_stats_from_master(master)
	check(f.hp_max_cached == 4, "7/2 banker's-round to even should be 4, got %d" % f.hp_max_cached)


func test_derive_stats_caps_current_hp_at_new_max() -> void:
	var f := FamiliarData.new()
	f.hp_current = 10  # carry-over wound state
	var master := _make_master(2, 8)  # new max = 4
	f.derive_stats_from_master(master)
	check(f.hp_current == 4, "hp_current should be capped to new hp_max=4, got %d" % f.hp_current)


# --- Display, INT, proficiencies ---

func test_hd_display_strings() -> void:
	var f := FamiliarData.new()
	f.is_half_hd = true
	check(f.hd_display() == "0.5", "Half-HD displays as '0.5', got '%s'" % f.hd_display())

	f.is_half_hd = false
	f.hd_dice = 1
	f.hd_modifier_hp = 0
	check(f.hd_display() == "1", "1 HD displays as '1'")

	f.hd_dice = 1
	f.hd_modifier_hp = 2
	check(f.hd_display() == "1+2", "1+2 displays as '1+2'")

	f.hd_dice = 4
	f.hd_modifier_hp = 0
	check(f.hd_display() == "4", "4 HD displays as '4'")


func test_derive_stats_proficiency_count_aggregates_selections() -> void:
	var master := _make_master(5, 14)
	master.proficiencies = [
		{"proficiency_key": "familiar", "rank": 1, "selections_count": 1},
		{"proficiency_key": "fighting_style", "rank": 1, "selections_count": 2},
		{"proficiency_key": "engineering", "rank": 1, "selections_count": 3},
	]
	var f := FamiliarData.new()
	f.derive_stats_from_master(master)
	check(f.proficiency_count_cached == 6, "Should sum selections_count = 1+2+3 = 6, got %d" % f.proficiency_count_cached)


# --- Serialization ---

func test_to_dict_serializes_proficiencies_chosen_as_json() -> void:
	var f := FamiliarData.new()
	f.proficiencies_chosen = ["alchemy", "magical_engineering"]
	var d := f.to_dict()
	check(d["proficiencies_chosen"] is String, "proficiencies_chosen should serialize to a JSON string")
	var parsed = JSON.parse_string(d["proficiencies_chosen"])
	check(parsed is Array and parsed.size() == 2, "JSON round-trip should yield a 2-item array")


func test_to_dict_serializes_is_half_hd_as_int() -> void:
	var f := FamiliarData.new()
	f.is_half_hd = true
	check(int(f.to_dict()["is_half_hd"]) == 1, "is_half_hd=true serializes to 1")
	f.is_half_hd = false
	check(int(f.to_dict()["is_half_hd"]) == 0, "is_half_hd=false serializes to 0")


func test_from_db_round_trip() -> void:
	var row := {
		"id": "fam_xyz",
		"campaign_id": "camp_1",
		"master_character_id": "char_1",
		"form_key": "bat",
		"cosmetic_species": "Bat",
		"name": "Echo",
		"hp_current": 3,
		"hp_max_cached": 4,
		"hd_dice": 1,
		"hd_modifier_hp": 0,
		"is_half_hd": 0,
		"attack_save_class": "fighter",
		"attack_save_level": 1,
		"damage_bonus": 1,
		"int_cached": 14,
		"proficiency_count_cached": 5,
		"proficiencies_chosen": '["alchemy"]',
		"is_alive": 1,
		"bonded_at_master_level": 1,
		"death_save_pending": 0,
		"position_voxel_x": 3,
		"position_voxel_y": 4,
		"position_voxel_z": 0,
	}
	var f := FamiliarData.from_db(row)
	check(f.id == "fam_xyz", "id round-trips")
	check(f.form_key == "bat", "form_key round-trips")
	check(f.is_alive == true, "is_alive 1 → true")
	check(f.is_half_hd == false, "is_half_hd 0 → false")
	check(f.attack_save_class == "fighter", "attack_save_class round-trips")
	check(f.attack_save_level == 1, "attack_save_level round-trips")
	check(f.damage_bonus == 1, "damage_bonus round-trips")
	check(f.proficiencies_chosen == ["alchemy"], "proficiencies_chosen JSON-parsed correctly")


# --- Replacement gate ---

func test_can_replace_at_blocked_when_alive() -> void:
	var f := FamiliarData.new()
	f.is_alive = true
	f.bonded_at_master_level = 1
	check(f.can_replace_at(5) == false, "Can't replace a living familiar even at higher level")


func test_can_replace_at_strict_inequality() -> void:
	var f := FamiliarData.new()
	f.is_alive = false
	f.bonded_at_master_level = 3
	check(f.can_replace_at(3) == false, "Same level: cannot replace (must be strictly greater)")
	check(f.can_replace_at(4) == true, "Level 4 > bonded_at 3: can replace")


# --- Form read-through ---

func test_form_stat_readthrough_defaults() -> void:
	var f := FamiliarData.new()
	# form_stats not populated → defaults
	check(f.get_armor_class() == 9, "Unpopulated form_stats AC defaults to 9 (worst-case unarmored)")
	check(f.get_attack_routines() == [], "No attack routines by default")
	check(f.get_special_abilities() == [], "No special abilities by default")
	check(f.get_size_category() == "tiny", "size_category defaults to tiny")


func test_form_stat_readthrough_populated() -> void:
	var f := FamiliarData.new()
	f.form_stats = {
		"armor_class": 3,
		"size_category": "tiny",
		"movement": {"fly": {"exploration": 120, "combat": 40}},
		"attack_routines": [{"routine_name": "melee", "attacks": [{"damage": "1"}]}],
		"special_abilities": [{"ability_id": "echolocation"}],
	}
	check(f.get_armor_class() == 3, "AC reads through from form_stats")
	check(f.get_size_category() == "tiny", "size_category reads through")
	check(f.get_movement().has("fly"), "movement reads through")
	check(f.get_attack_routines().size() == 1, "attack_routines read through")
	check(f.get_special_abilities()[0]["ability_id"] == "echolocation", "special_abilities read through")
