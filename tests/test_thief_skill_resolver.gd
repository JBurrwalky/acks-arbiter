extends "res://tests/test_suite_base.gd"

## Unit tests for ThiefSkillResolver.

var _class_registry := ClassRegistry.new()
var _spec_registry := SpecializationRegistry.new()
var _prof_registry := ProficiencyRegistry.new(_spec_registry)
var _power_registry := PowerRegistry.new()
var _generator := CharacterGenerator.new(_class_registry, _power_registry, _prof_registry)


func run_all_tests() -> void:
	test_grouped_skill_checks_split_thief_and_adventuring_rows()
	test_base_thief_targets_from_persisted_progression()
	test_thief_split_trap_rows_share_target()
	test_dwarven_delver_only_gets_remove_traps_as_na()
	test_climbing_and_eavesdropping_grant_equivalent_targets()
	test_prestidigitation_uses_half_character_level()
	test_force_door_uses_strength_x4_and_dungeon_bashing()
	test_detect_secret_baselines_for_human_elf_and_dwarf()
	test_hear_noise_baselines_and_upgrades()
	test_find_traps_baselines_and_thief_dex_rule()
	test_foraging_hunting_and_fishing_apply_survival_bonus()
	test_encumbrance_only_modifies_stealth_and_climbing()
	test_hijink_mode_suppresses_dex_and_encumbrance()
	test_assassin_heavy_armor_blocks_conditional_skills()
	test_modifier_only_proficiencies_do_not_grant_open_lock_or_remove_traps_access()
	if not has_failures():
		print("ThiefSkillResolver: all tests passed.")


func _make_resolver() -> ThiefSkillResolver:
	return ThiefSkillResolver.new(_class_registry, _prof_registry, _power_registry)


func _make_bundle(class_id: String, level: int, dexterity: int = 10, strength: int = 10,
		proficiencies: Array = [], inventory: Array = [], race_override: String = "") -> CharacterBundle:
	var character := CharacterData.new()
	character.character_class = class_id
	character.level = level
	character.dexterity = dexterity
	character.strength = strength
	character.race = race_override if not race_override.is_empty() else str(
		_class_registry.get_class_def(class_id).get("race", "human")
	)
	character.proficiencies = proficiencies.duplicate(true)

	var bundle := CharacterBundle.new()
	bundle.character = character
	bundle.proficiencies = proficiencies.duplicate(true)
	bundle.inventory = inventory.duplicate(true)
	bundle.powers = _generator.stamp_powers(character, class_id)
	return bundle


func _prof_row(key: String, slot_type: String = "general",
		specialization: String = "") -> Dictionary:
	return {
		"proficiency_key": key,
		"rank": 1,
		"slot_type": slot_type,
		"selections_count": 1,
		"specialization": specialization,
	}


func _gear_item(encumbrance_units: int) -> Dictionary:
	return {
		"item_key": "test_gear",
		"name": "Test Gear",
		"quantity": 1,
		"encumbrance_units": encumbrance_units,
		"slot": "pack",
		"is_equipped": 0,
		"item_category": "gear",
		"armor_ac_bonus": 0,
	}


func _equipped_body_armor(item_key: String, armor_ac_bonus: int,
		encumbrance_units: int) -> Dictionary:
	return {
		"item_key": item_key,
		"name": item_key.replace("_", " ").capitalize(),
		"quantity": 1,
		"encumbrance_units": encumbrance_units,
		"slot": "body",
		"is_equipped": 1,
		"item_category": "armor",
		"armor_ac_bonus": armor_ac_bonus,
	}


func test_grouped_skill_checks_split_thief_and_adventuring_rows() -> void:
	var resolver := _make_resolver()
	var grouped := resolver.get_grouped_skill_checks(_make_bundle("fighter", 1))

	check(grouped.has(ThiefSkillResolver.THIEF_GROUP_KEY),
		"ThiefSkillResolver: grouped checks should include thief_skills")
	check(grouped.has(ThiefSkillResolver.ADVENTURING_GROUP_KEY),
		"ThiefSkillResolver: grouped checks should include adventuring_skills")
	check((grouped.get(ThiefSkillResolver.THIEF_GROUP_KEY, []) as Array).size()
		== ThiefSkillResolver.THIEF_SKILL_ORDER.size(),
		"ThiefSkillResolver: grouped thief checks should match the thief skill order")
	check((grouped.get(ThiefSkillResolver.ADVENTURING_GROUP_KEY, []) as Array).size()
		== ThiefSkillResolver.ADVENTURING_SKILL_ORDER.size(),
		"ThiefSkillResolver: grouped adventuring checks should match the adventuring skill order")


func test_base_thief_targets_from_persisted_progression() -> void:
	var resolver := _make_resolver()
	var thief_l1 := _make_bundle("thief", 1)
	var thief_l9 := _make_bundle("thief", 9)

	var open_locks_l1 := resolver.get_skill_check(thief_l1, "open_locks")
	var hear_noise_l1 := resolver.get_skill_check(thief_l1, "hear_noise")
	var pick_pockets_l9 := resolver.get_skill_check(thief_l9, "pick_pockets")

	check(open_locks_l1.get("display_target", "") == "18+",
		"ThiefSkillResolver: thief L1 open locks should be 18+, got %s" % open_locks_l1.get("display_target", ""))
	check(hear_noise_l1.get("display_target", "") == "14+",
		"ThiefSkillResolver: thief L1 hear noise should still resolve to 14+, got %s" % hear_noise_l1.get("display_target", ""))
	check(str(hear_noise_l1.get("group_key", "")) == ThiefSkillResolver.ADVENTURING_GROUP_KEY,
		"ThiefSkillResolver: hear noise should now belong to the adventuring group")
	check(pick_pockets_l9.get("display_target", "") == "6+",
		"ThiefSkillResolver: thief L9 pick pockets should be 6+, got %s" % pick_pockets_l9.get("display_target", ""))


func test_thief_split_trap_rows_share_target() -> void:
	var resolver := _make_resolver()
	var bundle := _make_bundle("thief", 1)

	var find_traps := resolver.get_skill_check(bundle, "find_traps")
	var remove_traps := resolver.get_skill_check(bundle, "remove_traps")

	check(find_traps.get("display_target", "") == "18+",
		"ThiefSkillResolver: thief find traps should use the shared trap table")
	check(str(find_traps.get("group_key", "")) == ThiefSkillResolver.ADVENTURING_GROUP_KEY,
		"ThiefSkillResolver: find traps should now render in the adventuring group")
	check(remove_traps.get("display_target", "") == "18+",
		"ThiefSkillResolver: thief remove traps should use the shared trap table")


func test_dwarven_delver_only_gets_remove_traps_as_na() -> void:
	var resolver := _make_resolver()
	var bundle := _make_bundle("dwarven_delver", 1)

	var find_traps := resolver.get_skill_check(bundle, "find_traps")
	var remove_traps := resolver.get_skill_check(bundle, "remove_traps")

	check(find_traps.get("display_target", "") == "14+",
		"ThiefSkillResolver: dwarven delver should show the native find traps target")
	check(remove_traps.get("display_target", "") == "NA",
		"ThiefSkillResolver: dwarven delver should not get remove traps from find_traps only")


func test_climbing_and_eavesdropping_grant_equivalent_targets() -> void:
	var resolver := _make_resolver()
	var bundle := _make_bundle(
		"fighter",
		4,
		10,
		10,
		[_prof_row("climbing"), _prof_row("eavesdropping")],
		[_gear_item(6000)]
	)

	var climb_walls := resolver.get_skill_check(bundle, "climb_walls")
	var hear_noise := resolver.get_skill_check(bundle, "hear_noise")

	check(climb_walls.get("display_target", "") == "4+",
		"ThiefSkillResolver: climbing should grant thief-equivalent climb walls at character level")
	check(hear_noise.get("display_target", "") == "11+",
		"ThiefSkillResolver: eavesdropping should grant thief-equivalent hear noise at character level")


func test_prestidigitation_uses_half_character_level() -> void:
	var resolver := _make_resolver()
	var level_five_bundle := _make_bundle("fighter", 5, 10, 10, [_prof_row("prestidigitation")])
	var level_one_bundle := _make_bundle("fighter", 1, 10, 10, [_prof_row("prestidigitation")])

	var pick_pockets_l5 := resolver.get_skill_check(level_five_bundle, "pick_pockets")
	var pick_pockets_l1 := resolver.get_skill_check(level_one_bundle, "pick_pockets")

	check(pick_pockets_l5.get("display_target", "") == "16+",
		"ThiefSkillResolver: prestidigitation should use half character level (5 -> 2)")
	check(pick_pockets_l1.get("display_target", "") == "NA",
		"ThiefSkillResolver: half-level equivalents below 1 should stay unavailable")


func test_force_door_uses_strength_x4_and_dungeon_bashing() -> void:
	var resolver := _make_resolver()
	var str_thirteen := _make_bundle("fighter", 1, 10, 13)
	var str_sixteen := _make_bundle("fighter", 1, 10, 16)
	var with_bashing := _make_bundle("fighter", 1, 10, 13, [_prof_row("dungeon_bashing")])

	var force_door_str_thirteen := resolver.get_skill_check(str_thirteen, "force_door")
	var force_door_str_sixteen := resolver.get_skill_check(str_sixteen, "force_door")
	var force_door_bashing := resolver.get_skill_check(with_bashing, "force_door")

	check(force_door_str_thirteen.get("display_target", "") == "14+",
		"ThiefSkillResolver: STR 13 should reduce force door from 18+ to 14+")
	check(force_door_str_sixteen.get("display_target", "") == "10+",
		"ThiefSkillResolver: STR 16 should reduce force door from 18+ to 10+")
	check(force_door_bashing.get("display_target", "") == "10+",
		"ThiefSkillResolver: Dungeon Bashing should add another +4 force door bonus")


func test_detect_secret_baselines_for_human_elf_and_dwarf() -> void:
	var resolver := _make_resolver()

	check(resolver.get_skill_check(_make_bundle("fighter", 1), "detect_secrets").get("display_target", "") == "18+",
		"ThiefSkillResolver: humans should default detect secrets to 18+")
	check(resolver.get_skill_check(_make_bundle("elven_ranger", 1), "detect_secrets").get("display_target", "") == "8+",
		"ThiefSkillResolver: elves should resolve detect secrets to 8+")
	check(resolver.get_skill_check(_make_bundle("dwarven_vaultguard", 1), "detect_secrets").get("display_target", "") == "14+",
		"ThiefSkillResolver: dwarves should resolve detect secrets to 14+")


func test_hear_noise_baselines_and_upgrades() -> void:
	var resolver := _make_resolver()

	check(resolver.get_skill_check(_make_bundle("fighter", 1), "hear_noise").get("display_target", "") == "18+",
		"ThiefSkillResolver: humans should default hear noise to 18+")
	check(resolver.get_skill_check(_make_bundle("elven_ranger", 1), "hear_noise").get("display_target", "") == "14+",
		"ThiefSkillResolver: elves should default hear noise to 14+")
	check(resolver.get_skill_check(_make_bundle("fighter", 4, 10, 10, [_prof_row("eavesdropping")]), "hear_noise").get("display_target", "") == "11+",
		"ThiefSkillResolver: eavesdropping should upgrade hear noise beyond the baseline")


func test_find_traps_baselines_and_thief_dex_rule() -> void:
	var resolver := _make_resolver()
	var human_fighter := _make_bundle("fighter", 1, 18)
	var dwarven_vaultguard := _make_bundle("dwarven_vaultguard", 1, 18)
	var thief := _make_bundle("thief", 1, 18)

	var human_find_traps := resolver.get_skill_check(human_fighter, "find_traps")
	var dwarven_find_traps := resolver.get_skill_check(dwarven_vaultguard, "find_traps")
	var thief_find_traps := resolver.get_skill_check(thief, "find_traps")

	check(human_find_traps.get("display_target", "") == "18+",
		"ThiefSkillResolver: humans should default find traps to 18+")
	check(int(human_find_traps.get("dex_modifier", 0)) == 0,
		"ThiefSkillResolver: the universal find traps baseline should not use DEX")
	check(dwarven_find_traps.get("display_target", "") == "14+",
		"ThiefSkillResolver: dwarves should default find traps to 14+")
	check(int(dwarven_find_traps.get("dex_modifier", 0)) == 0,
		"ThiefSkillResolver: stonework detection style find traps should not use DEX")
	check(thief_find_traps.get("display_target", "") == "15+",
		"ThiefSkillResolver: thief-native find traps should still apply DEX")


func test_foraging_hunting_and_fishing_apply_survival_bonus() -> void:
	var resolver := _make_resolver()
	var base_bundle := _make_bundle("fighter", 1)
	var survival_bundle := _make_bundle("fighter", 1, 10, 10, [_prof_row("survival")])

	var foraging_base := resolver.get_skill_check(base_bundle, "foraging")
	var hunting_base := resolver.get_skill_check(base_bundle, "hunting")
	var fishing_base := resolver.get_skill_check(base_bundle, "fishing")
	var foraging_survival := resolver.get_skill_check(survival_bundle, "foraging")
	var hunting_survival := resolver.get_skill_check(survival_bundle, "hunting")
	var fishing_survival := resolver.get_skill_check(survival_bundle, "fishing")

	check(foraging_base.get("display_target", "") == "18+",
		"ThiefSkillResolver: foraging should default to 18+")
	check(hunting_base.get("display_target", "") == "14+",
		"ThiefSkillResolver: hunting should default to 14+")
	check(fishing_base.get("display_target", "") == "14+",
		"ThiefSkillResolver: fishing should default to 14+")
	check(foraging_survival.get("display_target", "") == "14+",
		"ThiefSkillResolver: survival should improve foraging by 4")
	check(hunting_survival.get("display_target", "") == "10+",
		"ThiefSkillResolver: survival should improve hunting by 4")
	check(fishing_survival.get("display_target", "") == "10+",
		"ThiefSkillResolver: survival should improve fishing by 4")
	check(int(foraging_survival.get("proficiency_modifier_subtotal", 0)) == 4,
		"ThiefSkillResolver: survival should contribute +4 to the proficiency subtotal")
	check(str(foraging_survival.get("tooltip_text", "")).contains("automatic self-foraging"),
		"ThiefSkillResolver: foraging tooltip should note survival's automatic self-foraging")


func test_encumbrance_only_modifies_stealth_and_climbing() -> void:
	var resolver := _make_resolver()
	var bundle := _make_bundle("thief", 1)

	var move_silently := resolver.get_skill_check(bundle, "move_silently")
	var hide_in_shadows := resolver.get_skill_check(bundle, "hide_in_shadows")
	var climb_walls := resolver.get_skill_check(bundle, "climb_walls")
	var open_locks := resolver.get_skill_check(bundle, "open_locks")

	check(int(move_silently.get("encumbrance_modifier", 0)) == 4,
		"ThiefSkillResolver: <=2 stone should grant +4 to move silently")
	check(move_silently.get("display_target", "") == "13+",
		"ThiefSkillResolver: move silently should improve from 17+ to 13+ when lightly encumbered")
	check(hide_in_shadows.get("display_target", "") == "15+",
		"ThiefSkillResolver: hide in shadows should receive the same +4 bonus")
	check(climb_walls.get("display_target", "") == "2+",
		"ThiefSkillResolver: climb walls should receive the same +4 bonus")
	check(int(open_locks.get("encumbrance_modifier", 0)) == 0,
		"ThiefSkillResolver: encumbrance should not modify open locks")


func test_hijink_mode_suppresses_dex_and_encumbrance() -> void:
	var resolver := _make_resolver()
	var bundle := _make_bundle("thief", 1, 18)

	var normal := resolver.get_skill_check(bundle, "move_silently")
	var hijink := resolver.get_skill_check(bundle, "move_silently", true)

	check(normal.get("display_target", "") == "10+",
		"ThiefSkillResolver: normal move silently should include DEX and encumbrance bonuses")
	check(int(hijink.get("dex_modifier", 0)) == 0,
		"ThiefSkillResolver: hijink checks should suppress DEX bonuses")
	check(int(hijink.get("encumbrance_modifier", 0)) == 0,
		"ThiefSkillResolver: hijink checks should suppress encumbrance bonuses")
	check(hijink.get("display_target", "") == "17+",
		"ThiefSkillResolver: hijink move silently should revert to the base target")


func test_assassin_heavy_armor_blocks_conditional_skills() -> void:
	var resolver := _make_resolver()
	var bundle := _make_bundle(
		"assassin",
		1,
		10,
		10,
		[],
		[_equipped_body_armor("chain_mail", 4, 4000)]
	)

	var move_silently := resolver.get_skill_check(bundle, "move_silently")
	var hide_in_shadows := resolver.get_skill_check(bundle, "hide_in_shadows")

	check(move_silently.get("display_target", "") == "NA",
		"ThiefSkillResolver: assassin move silently should be unavailable in heavy armor")
	check(str(move_silently.get("unavailability_reason", "")).contains("heavier than leather"),
		"ThiefSkillResolver: blocked assassin skills should explain the armor restriction")
	check(hide_in_shadows.get("display_target", "") == "NA",
		"ThiefSkillResolver: assassin hide in shadows should be unavailable in heavy armor")


func test_modifier_only_proficiencies_do_not_grant_open_lock_or_remove_traps_access() -> void:
	var resolver := _make_resolver()
	var bundle := _make_bundle(
		"fighter",
		1,
		10,
		10,
		[_prof_row("lockpicking"), _prof_row("trap_finding")]
	)

	var open_locks := resolver.get_skill_check(bundle, "open_locks")
	var find_traps := resolver.get_skill_check(bundle, "find_traps")
	var remove_traps := resolver.get_skill_check(bundle, "remove_traps")

	check(open_locks.get("display_target", "") == "NA",
		"ThiefSkillResolver: lockpicking should not grant open locks access by itself")
	check(int(open_locks.get("proficiency_modifier_subtotal", 0)) == 2,
		"ThiefSkillResolver: lockpicking should still contribute its +2 modifier subtotal")
	check(find_traps.get("display_target", "") == "16+",
		"ThiefSkillResolver: trap finding should improve the universal find traps baseline to 16+")
	check(remove_traps.get("display_target", "") == "NA",
		"ThiefSkillResolver: trap finding should not grant remove traps access by itself")
	check(int(remove_traps.get("proficiency_modifier_subtotal", 0)) == 2,
		"ThiefSkillResolver: trap finding should still contribute its +2 remove traps modifier")
