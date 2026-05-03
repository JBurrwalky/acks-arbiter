extends "res://tests/test_suite_base.gd"

## Tests for the Normal Man (level 0) class. Phase 1 of the henchman game-loop
## closure plan — confirms the class JSON loads, ClassRegistry returns the
## right saves/HD/attack-throw, and CharacterGenerator produces a proper
## level-0 NM via generate_henchman("normal_man", 0, ...).


func run_all_tests() -> void:
	test_normal_man_class_loads()
	test_normal_man_basics()
	test_normal_man_disabled_for_player_roster()
	test_normal_man_saves()
	test_normal_man_attack_throw()
	test_normal_man_hd()
	test_normal_man_xp_table()
	test_generate_henchman_produces_normal_man()
	test_generated_normal_man_has_no_adventuring()
	test_generated_normal_man_hp_is_1d4_range()
	test_no_placeholder_flag_in_class_metadata()
	if not has_failures():
		print("NormalManClass: all tests passed.")


func test_normal_man_class_loads() -> void:
	var reg := ClassRegistry.new()
	check(reg.has_class("normal_man"),
		"ClassRegistry must load data/classes/normal_man.json")


func test_normal_man_basics() -> void:
	var reg := ClassRegistry.new()
	var nm := reg.get_class_def("normal_man")
	check(not nm.is_empty(), "normal_man class def must not be empty")
	check(String(nm.get("combat_progression", "")) == "normal_man",
		"combat_progression should be 'normal_man'")
	check(String(nm.get("hit_die", "")) == "1d4",
		"hit_die should be '1d4'")
	check(int(nm.get("max_hd_count", 99)) == 1,
		"max_hd_count should be 1")
	check((nm.get("prime_requisites", [1]) as Array).is_empty(),
		"prime_requisites should be empty (no class minimums for NMs)")
	check((nm.get("class_proficiency_list", [1]) as Array).is_empty(),
		"class_proficiency_list should be empty")


func test_normal_man_disabled_for_player_roster() -> void:
	# normal_man should be hidden from player class selection but still loaded
	# so existing save data referencing it resolves via get_class_def().
	var reg := ClassRegistry.new()
	var scores := {"STR": 14, "INT": 14, "WIS": 14, "DEX": 14, "CON": 14, "CHA": 14}
	var eligible := reg.get_eligible_classes(scores, "human")
	check(not ("normal_man" in eligible),
		"normal_man must NOT appear in eligible classes for player creation")


func test_normal_man_saves() -> void:
	# acore worst-tier NM saves (matches the historical hardcoded table at
	# engine/subsystems/combat/combatant.gd:961-969).
	var reg := ClassRegistry.new()
	var saves := reg.get_saving_throws("normal_man", 0)
	check(int(saves.get("petrification", 0)) == 16, "petrification should be 16")
	check(int(saves.get("poison_death", 0)) == 14, "poison_death should be 14")
	check(int(saves.get("blast_breath", 0)) == 17, "blast_breath should be 17")
	check(int(saves.get("staffs_wands", 0)) == 16, "staffs_wands should be 16")
	check(int(saves.get("spells", 0)) == 18, "spells should be 18")


func test_normal_man_attack_throw() -> void:
	var reg := ClassRegistry.new()
	check(reg.get_attack_throw("normal_man", 0) == 11,
		"NM attack throw at level 0 should be 11")


func test_normal_man_hd() -> void:
	var reg := ClassRegistry.new()
	check(reg.get_hit_die("normal_man") == "1d4",
		"NM hit die should be 1d4")


func test_normal_man_xp_table() -> void:
	# NM XP threshold is 100 per acore_adventures_and_encounters.xml:713.
	# That's enforced by level_up_engine.gd:48 directly. The xp_table[0] is
	# the L1 entry (always 0 by convention).
	var reg := ClassRegistry.new()
	check(reg.get_xp_for_level("normal_man", 1) == 0,
		"normal_man L1 entry should be 0 XP (engine hardcodes 100 advance threshold)")


func test_generate_henchman_produces_normal_man() -> void:
	var class_reg := ClassRegistry.new()
	var power_reg := PowerRegistry.new()
	var gen := CharacterGenerator.new(class_reg, power_reg)
	var nm: CharacterData = gen.generate_henchman("normal_man", 0, "test_campaign")
	check(nm != null, "generate_henchman should produce a CharacterData")
	if nm == null:
		return
	check(nm.character_class == "normal_man",
		"generated character_class should be 'normal_man', got %s" % nm.character_class)
	check(nm.level == 0, "generated level should be 0, got %d" % nm.level)
	check(nm.character_type == "henchman",
		"character_type should be 'henchman', got %s" % nm.character_type)
	check(nm.combat_progression == "normal_man",
		"combat_progression should be 'normal_man', got %s" % nm.combat_progression)
	check(int(nm.wage_gp_per_month) == 12,
		"NM monthly wage should be 12 gp, got %d" % nm.wage_gp_per_month)


func test_generated_normal_man_has_no_adventuring() -> void:
	# acore_adventures_and_encounters.xml:723 — Adventuring is granted at L4
	# of the post-NM track, NOT to NMs themselves.
	var class_reg := ClassRegistry.new()
	var power_reg := PowerRegistry.new()
	var gen := CharacterGenerator.new(class_reg, power_reg)
	var profs := gen.auto_select_proficiencies("normal_man", 0)
	for p: Dictionary in profs:
		check(String(p.get("proficiency_key", "")) != "adventuring",
			"NM at level 0 must NOT have adventuring proficiency")


func test_generated_normal_man_hp_is_1d4_range() -> void:
	# 1d4 + CON mod, minimum 1. With average CON 10 (mod 0): hp_max in [1, 4].
	# Using a fixed-CON character to avoid CON-mod variance.
	var class_reg := ClassRegistry.new()
	var power_reg := PowerRegistry.new()
	var gen := CharacterGenerator.new(class_reg, power_reg)
	var nm: CharacterData = gen.generate_henchman("normal_man", 0, "test_campaign")
	check(nm != null, "generate_henchman returned null")
	if nm == null:
		return
	var con_mod := CharacterData.ability_modifier(nm.constitution)
	# d4 roll range [1..4] + con_mod, minimum 1.
	var min_hp: int = max(1 + con_mod, 1)
	var max_hp: int = max(4 + con_mod, 1)
	check(nm.hp_max >= min_hp and nm.hp_max <= max_hp,
		"NM hp_max (%d) outside expected 1d4+CON range [%d..%d]" % [nm.hp_max, min_hp, max_hp])


func test_no_placeholder_flag_in_class_metadata() -> void:
	# The normal_man_placeholder flag is gone — newly generated NMs do not
	# carry it on class_metadata.
	var class_reg := ClassRegistry.new()
	var power_reg := PowerRegistry.new()
	var gen := CharacterGenerator.new(class_reg, power_reg)
	var nm: CharacterData = gen.generate_henchman("normal_man", 0, "test_campaign")
	check(nm != null, "generate_henchman returned null")
	if nm == null:
		return
	check(not nm.class_metadata.contains("normal_man_placeholder"),
		"class_metadata must not contain the legacy placeholder flag")
