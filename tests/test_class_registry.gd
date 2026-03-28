extends Node

## Unit tests for ClassRegistry.
## Run via test_runner.tscn. Uses plain assert() — no external framework.


func run_all_tests() -> void:
	test_all_classes_load()
	test_fighter_basics()
	test_class_eligibility_human_fighter()
	test_class_eligibility_race_filter()
	test_attack_throw_progression()
	test_saving_throws_lookup()
	test_xp_table()
	test_level_titles()
	test_spell_slots_mage()
	test_spell_slots_non_caster()
	print("ClassRegistry: all tests passed.")


# ---------------------------------------------------------------------------
# Class loading
# ---------------------------------------------------------------------------

func test_all_classes_load() -> void:
	var reg := ClassRegistry.new()
	assert(reg.get_class_count() == 25,
		"ClassRegistry should load 25 classes, got %d" % reg.get_class_count())
	print("  all_classes_load: OK")


# ---------------------------------------------------------------------------
# Fighter basics
# ---------------------------------------------------------------------------

func test_fighter_basics() -> void:
	var reg := ClassRegistry.new()
	var fighter := reg.get_class_def("fighter")
	assert(not fighter.is_empty(), "fighter class should exist")
	assert(fighter.get("combat_progression", "") == "fighter",
		"fighter combat_progression should be 'fighter'")
	assert(fighter.get("hit_die", "") == "1d8",
		"fighter hit_die should be '1d8'")
	assert(int(fighter.get("max_level", 0)) == 14,
		"fighter max_level should be 14")
	print("  fighter_basics: OK")


# ---------------------------------------------------------------------------
# Class eligibility
# ---------------------------------------------------------------------------

func test_class_eligibility_human_fighter() -> void:
	var reg := ClassRegistry.new()
	# STR 9+ human qualifies for fighter (prime req is STR)
	var good_scores := {"STR": 12, "INT": 10, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10}
	var eligible := reg.get_eligible_classes(good_scores, "human")
	assert("fighter" in eligible,
		"human with STR 12 should qualify for fighter")

	# STR 8 human does NOT qualify
	var bad_scores := {"STR": 8, "INT": 10, "WIS": 10, "DEX": 10, "CON": 10, "CHA": 10}
	var ineligible := reg.get_eligible_classes(bad_scores, "human")
	assert("fighter" not in ineligible,
		"human with STR 8 should NOT qualify for fighter")
	print("  class_eligibility_human_fighter: OK")


func test_class_eligibility_race_filter() -> void:
	var reg := ClassRegistry.new()
	# All 18s human should not get dwarf classes
	var human_scores := {"STR": 18, "INT": 18, "WIS": 18, "DEX": 18, "CON": 18, "CHA": 18}
	var human_eligible := reg.get_eligible_classes(human_scores, "human")
	assert("dwarf_vaultguard" not in human_eligible,
		"human should not qualify for dwarf_vaultguard")
	assert("dwarven_delver" not in human_eligible,
		"human should not qualify for dwarven_delver")

	# All 18s dwarf should not get human classes
	var dwarf_eligible := reg.get_eligible_classes(human_scores, "dwarf")
	assert("fighter" not in dwarf_eligible,
		"dwarf should not qualify for fighter (human class)")
	assert("mage" not in dwarf_eligible,
		"dwarf should not qualify for mage (human class)")
	# Dwarf should get dwarf classes
	assert("dwarf_vaultguard" in dwarf_eligible,
		"dwarf with all 18s should qualify for dwarf_vaultguard")
	print("  class_eligibility_race_filter: OK")


# ---------------------------------------------------------------------------
# Attack throw progression
# ---------------------------------------------------------------------------

func test_attack_throw_progression() -> void:
	var reg := ClassRegistry.new()
	# Fighter L1 = 10, L7 = 6, L14 = 1
	assert(reg.get_attack_throw("fighter", 1) == 10,
		"fighter L1 attack throw should be 10")
	assert(reg.get_attack_throw("fighter", 7) == 6,
		"fighter L7 attack throw should be 6")
	assert(reg.get_attack_throw("fighter", 14) == 1,
		"fighter L14 attack throw should be 1")
	print("  attack_throw_progression: OK")


# ---------------------------------------------------------------------------
# Saving throws
# ---------------------------------------------------------------------------

func test_saving_throws_lookup() -> void:
	var reg := ClassRegistry.new()
	var saves_l1 := reg.get_saving_throws("fighter", 1)
	assert(int(saves_l1.get("petrification", 0)) == 15,
		"fighter L1 petrification should be 15, got %d" % int(saves_l1.get("petrification", 0)))

	var saves_l14 := reg.get_saving_throws("fighter", 14)
	assert(int(saves_l14.get("petrification", 0)) == 6,
		"fighter L14 petrification should be 6, got %d" % int(saves_l14.get("petrification", 0)))
	assert(int(saves_l14.get("poison_death", 0)) == 5,
		"fighter L14 poison_death should be 5")
	print("  saving_throws_lookup: OK")


# ---------------------------------------------------------------------------
# XP table
# ---------------------------------------------------------------------------

func test_xp_table() -> void:
	var reg := ClassRegistry.new()
	# Fighter L2 = 2000, Thief L2 = 1250
	assert(reg.get_xp_for_level("fighter", 2) == 2000,
		"fighter L2 XP should be 2000, got %d" % reg.get_xp_for_level("fighter", 2))
	assert(reg.get_xp_for_level("thief", 2) == 1250,
		"thief L2 XP should be 1250, got %d" % reg.get_xp_for_level("thief", 2))
	# Level 1 is always 0
	assert(reg.get_xp_for_level("fighter", 1) == 0,
		"fighter L1 XP should be 0")
	print("  xp_table: OK")


# ---------------------------------------------------------------------------
# Level titles
# ---------------------------------------------------------------------------

func test_level_titles() -> void:
	var reg := ClassRegistry.new()
	assert(reg.get_level_title("fighter", 1) == "Man-at-Arms",
		"fighter L1 title should be 'Man-at-Arms'")
	assert(reg.get_level_title("fighter", 4) == "Hero",
		"fighter L4 title should be 'Hero'")
	assert(reg.get_level_title("fighter", 14) == "Overlord",
		"fighter L14 title should be 'Overlord'")
	print("  level_titles: OK")


# ---------------------------------------------------------------------------
# Spell slots
# ---------------------------------------------------------------------------

func test_spell_slots_mage() -> void:
	var reg := ClassRegistry.new()
	var slots_l1 := reg.get_spell_slots("mage", 1)
	assert(slots_l1 == [1, 0, 0, 0, 0, 0],
		"mage L1 spell slots should be [1,0,0,0,0,0], got %s" % str(slots_l1))
	var slots_l3 := reg.get_spell_slots("mage", 3)
	assert(slots_l3 == [2, 1, 0, 0, 0, 0],
		"mage L3 spell slots should be [2,1,0,0,0,0], got %s" % str(slots_l3))
	print("  spell_slots_mage: OK")


func test_spell_slots_non_caster() -> void:
	var reg := ClassRegistry.new()
	var slots := reg.get_spell_slots("fighter", 5)
	assert(slots.is_empty(),
		"fighter should have empty spell slots, got %s" % str(slots))
	print("  spell_slots_non_caster: OK")
