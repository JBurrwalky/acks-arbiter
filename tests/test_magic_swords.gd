extends "res://tests/test_suite_base.gd"

## Tests for the 5 Tier-4 magic swords (RAW
## acore_treasure_and_magic_items_rules.xml:273-277):
##   - Flame Tongue (+1 base; +2 vs avian/regenerating, +3 vs undead/plant-like)
##   - Frost Brand (+3 base; +6 total vs hot-environment / fire-based attackers)
##   - Life Drinker (+1 base; on-command drain 1 level; 1d4+4 charges)
##   - Luck Blade (+1 base; passive +1 saves while wielded; 1d4+1 wishes deferred)
##   - Vorpal Sword (+3 base; nat-20 → save vs Death; fail = instant kill, succeed = ×2 damage)
##
## Coverage:
##   - Catalog stamps for all 5 swords (base bonus + metadata + charge dice).
##   - Combatant creature-type helpers (is_avian, has_regeneration, is_plant_like,
##     is_from_hot_environment, has_fire_based_attacks, is_creature_type).
##   - AttackResolver._get_sword_bonus_vs_creature returns the right delta.
##   - WornMagicEffectResolver: Luck Blade passive +1 saves while wielded;
##     unwielded → no bonus. Frost Brand wielder fire resistance.
##   - MagicItemActivator.apply_life_drinker_drain: drain on hit, decrements
##     charges, refuses at 0 charges, becomes "normal +1" at 0.
##   - TreasureInstantiator._roll_charges: parses 1d4+4 style strings.

const _DB_CAMPAIGN := "test_magic_swords_campaign"
const _DB_CHAR := "test_magic_swords_char"


func run_all_tests() -> void:
	# Catalog binding shape.
	test_all_five_swords_in_catalog_with_metadata()
	test_flame_tongue_metadata_shape()
	test_frost_brand_metadata_shape()
	test_life_drinker_default_charges_string()
	test_luck_blade_carries_wish_binding()
	test_vorpal_sword_metadata_shape()
	# Combatant creature-type helpers.
	test_combatant_is_creature_type_undead()
	test_combatant_has_regeneration_via_special_ability()
	test_combatant_is_plant_like_via_sub_type()
	test_combatant_is_avian_via_known_ids()
	test_combatant_is_from_hot_environment_via_fire_sub_type()
	test_combatant_has_fire_based_attacks_via_breath_weapon()
	# AttackResolver vs-creature-type bonus.
	test_flame_tongue_no_bonus_vs_ordinary_target()
	test_flame_tongue_plus_two_vs_regenerating_target()
	test_flame_tongue_plus_three_vs_undead_target()
	test_flame_tongue_plus_three_vs_plant_like_target()
	test_frost_brand_plus_three_vs_hot_environment_target()
	test_frost_brand_no_bonus_vs_ordinary_target()
	# WornMagicEffectResolver.
	test_luck_blade_grants_plus_one_saves_when_wielded()
	test_luck_blade_no_bonus_when_off_hand()
	test_luck_blade_no_bonus_when_unequipped()
	test_frost_brand_grants_fire_resistance_when_wielded()
	# MagicItemActivator.apply_life_drinker_drain.
	test_life_drinker_drains_one_level_and_decrements_charges()
	test_life_drinker_refuses_at_zero_charges()
	test_life_drinker_becomes_normal_plus_one_when_charges_hit_zero()
	test_life_drinker_refuses_wrong_item_key()
	# TreasureInstantiator dice parsing.
	test_roll_charges_int_passthrough()
	test_roll_charges_parses_1d4_plus_4()
	test_roll_charges_parses_1d4_plus_1()
	test_roll_charges_returns_minus_one_for_unparseable()
	# Deferred-consumer wire-up (2026-06-01).
	# Frost Brand environmental glow.
	test_frost_brand_glow_in_tundra_in_winter()
	test_frost_brand_glow_in_tundra_in_spring()
	test_frost_brand_no_glow_in_tundra_in_summer()
	test_frost_brand_glow_in_taiga_in_autumn()
	test_frost_brand_glow_in_glacial_mountain_in_winter()
	test_frost_brand_glow_in_grassland_in_winter()
	test_frost_brand_no_glow_in_grassland_in_summer()
	test_frost_brand_glow_in_forest_in_winter()
	test_frost_brand_glow_in_dense_forest_in_winter()
	test_frost_brand_glow_in_regular_mountain_in_winter()
	test_frost_brand_no_glow_in_volcanic_mountain_in_winter()
	test_frost_brand_no_glow_in_desert_in_winter()
	test_frost_brand_no_glow_when_terrain_null()
	test_frost_brand_update_sets_flag_when_wielded_and_conditions_met()
	test_frost_brand_update_clears_flag_when_conditions_fail()
	test_frost_brand_update_no_effect_when_unequipped()
	# Flame Tongue ignite / douse.
	test_flame_tongue_ignite_sets_wielding_flag()
	test_flame_tongue_ignite_refuses_when_unequipped()
	test_flame_tongue_ignite_refuses_wrong_item_key()
	test_flame_tongue_douse_clears_flag()
	# Life Drinker level reduction (consumer integration).
	test_character_data_get_effective_level_no_drain()
	test_character_data_get_effective_level_with_drain()
	test_character_data_get_effective_level_floor_at_1()
	test_character_data_get_effective_level_stacks_multiple_sources()
	test_combatant_get_effective_level_or_hd_pc_path()
	test_combatant_get_effective_level_or_hd_monster_path()
	test_monster_attack_throw_uses_drained_hd()
	if not has_failures():
		print("MagicSwords: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog binding shape
# ---------------------------------------------------------------------------

func test_all_five_swords_in_catalog_with_metadata() -> void:
	var catalog := MagicItemCatalog.new()
	for key in ["flame_tongue", "frost_brand", "life_drinker", "luck_blade", "vorpal_sword"]:
		var entry: Dictionary = catalog.get_item(key)
		check(not entry.is_empty(), "%s must exist in catalog" % key)
		check(entry.has("sword_metadata"),
			"%s must carry sword_metadata block" % key)
	print("  all_five_swords_in_catalog_with_metadata: OK")


func test_flame_tongue_metadata_shape() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("flame_tongue")
	check(int(entry.get("magical_bonus", 0)) == 1,
		"flame_tongue base magical_bonus should be 1; got %d" %
			int(entry.get("magical_bonus", 0)))
	var meta: Dictionary = entry.get("sword_metadata", {})
	var vs: Dictionary = meta.get("vs_creature_type_bonus", {})
	check(int(vs.get("regenerating", 0)) == 2, "vs regenerating bonus = 2")
	check(int(vs.get("avian", 0)) == 2, "vs avian bonus = 2")
	check(int(vs.get("undead", 0)) == 3, "vs undead bonus = 3")
	check(int(vs.get("plant_like", 0)) == 3, "vs plant_like bonus = 3")
	check(bool(meta.get("ignitable_on_command", false)) == true,
		"flame_tongue should be ignitable_on_command")
	check(int(meta.get("light_radius_cells", 0)) == 6,
		"light_radius_cells = 6 (standard torch radius)")
	print("  flame_tongue_metadata_shape: OK")


func test_frost_brand_metadata_shape() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("frost_brand")
	check(int(entry.get("magical_bonus", 0)) == 3,
		"frost_brand base magical_bonus should be 3 (Sword +3 group); got %d" %
			int(entry.get("magical_bonus", 0)))
	var meta: Dictionary = entry.get("sword_metadata", {})
	var vs: Dictionary = meta.get("vs_creature_type_bonus", {})
	check(int(vs.get("hot_environment", 0)) == 3,
		"vs hot_environment EXTRA bonus = 3 (total +6)")
	check(int(vs.get("fire_based_attacks", 0)) == 3,
		"vs fire_based_attacks EXTRA bonus = 3 (total +6)")
	check(bool(meta.get("wielder_fire_resistance", false)) == true,
		"wielder_fire_resistance = true (Ring of Fire Resistance equivalent)")
	check(int(meta.get("extinguishes_nonmagical_fire_radius_ft", 0)) == 10,
		"extinguish radius 10ft (RAW)")
	print("  frost_brand_metadata_shape: OK")


func test_life_drinker_default_charges_string() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("life_drinker")
	check(str(entry.get("default_charges", "")) == "1d4+4",
		"life_drinker default_charges should be '1d4+4'; got '%s'" %
			str(entry.get("default_charges", "")))
	var meta: Dictionary = entry.get("sword_metadata", {})
	check(bool(meta.get("drain_on_command", false)) == true, "drain_on_command = true")
	check(int(meta.get("drain_levels", 0)) == 1, "drain_levels = 1 (per RAW)")
	check(bool(meta.get("remains_plus_one_after_charges", false)) == true,
		"remains_plus_one_after_charges = true")
	print("  life_drinker_default_charges_string: OK")


func test_luck_blade_carries_wish_binding() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("luck_blade")
	check(str(entry.get("default_charges", "")) == "1d4+1",
		"luck_blade default_charges should be '1d4+1' (wishes)")
	var binding: Dictionary = entry.get("spell_binding", {})
	check(str(binding.get("spell_key", "")) == "wish",
		"luck_blade spell_binding.spell_key should be 'wish' (Wish spell deferred)")
	var meta: Dictionary = entry.get("sword_metadata", {})
	check(int(meta.get("passive_save_bonus", 0)) == 1,
		"passive_save_bonus = 1 (per RAW)")
	check(str(meta.get("wielded_slot_required", "")) == "hands_main",
		"wielded slot gate = hands_main")
	print("  luck_blade_carries_wish_binding: OK")


func test_vorpal_sword_metadata_shape() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("vorpal_sword")
	check(int(entry.get("magical_bonus", 0)) == 3,
		"vorpal_sword base magical_bonus should be 3 (Sword +3 group); got %d" %
			int(entry.get("magical_bonus", 0)))
	var meta: Dictionary = entry.get("sword_metadata", {})
	check(bool(meta.get("natural_20_decapitation", false)) == true,
		"natural_20_decapitation = true")
	check(str(meta.get("save_kind", "")) == "save_poison_death",
		"save_kind = save_poison_death (ACKS 'vs Death')")
	print("  vorpal_sword_metadata_shape: OK")


# ---------------------------------------------------------------------------
# Combatant creature-type helpers
# ---------------------------------------------------------------------------

func test_combatant_is_creature_type_undead() -> void:
	# Build a minimal undead monster Combatant and verify is_creature_type
	# detects "undead" in monster_types.
	var c := _build_monster("test_undead", {
		"monster_types": ["undead"], "hit_dice": {"base": 2, "modifier": 0},
		"armor_class": 7, "morale": 12,
	})
	check(c.is_creature_type("undead") == true, "undead detection via monster_types")
	check(c.is_creature_type("animal") == false, "non-matching type returns false")
	print("  combatant_is_creature_type_undead: OK")


func test_combatant_has_regeneration_via_special_ability() -> void:
	var c := _build_monster("test_troll", {
		"monster_types": ["giant_humanoid"],
		"hit_dice": {"base": 6, "modifier": 3},
		"armor_class": 5, "morale": 9,
		"special_abilities": [
			{"ability_id": "regeneration", "description": "test"},
		],
	})
	check(c.has_regeneration() == true, "troll-style monster has regeneration")
	print("  combatant_has_regeneration_via_special_ability: OK")


func test_combatant_is_plant_like_via_sub_type() -> void:
	var c := _build_monster("test_treant", {
		"monster_types": ["fantastic_creature"], "sub_types": ["plant"],
		"hit_dice": {"base": 8, "modifier": 0}, "armor_class": 3, "morale": 11,
	})
	check(c.is_plant_like() == true, "treant detected via sub_type 'plant'")
	print("  combatant_is_plant_like_via_sub_type: OK")


func test_combatant_is_avian_via_known_ids() -> void:
	var c := _build_monster("harpy", {
		"monster_types": ["fantastic_creature"],
		"hit_dice": {"base": 3, "modifier": 0}, "armor_class": 7, "morale": 7,
	})
	check(c.is_avian() == true, "harpy detected as avian (V1 fallback by id)")
	print("  combatant_is_avian_via_known_ids: OK")


func test_combatant_is_from_hot_environment_via_fire_sub_type() -> void:
	var c := _build_monster("test_salamander_flame", {
		"monster_types": ["elemental"], "sub_types": ["fire"],
		"hit_dice": {"base": 4, "modifier": 0}, "armor_class": 3, "morale": 9,
	})
	check(c.is_from_hot_environment() == true,
		"fire-sub-type creature detected as hot-environment")
	print("  combatant_is_from_hot_environment_via_fire_sub_type: OK")


func test_combatant_has_fire_based_attacks_via_breath_weapon() -> void:
	var c := _build_monster("test_red_dragon", {
		"monster_types": ["fantastic_creature"],
		"hit_dice": {"base": 10, "modifier": 0}, "armor_class": -1, "morale": 10,
		"breath_weapon": {"damage_type": "fire", "damage": "10d6"},
	})
	check(c.has_fire_based_attacks() == true,
		"dragon-style monster with fire breath detected")
	print("  combatant_has_fire_based_attacks_via_breath_weapon: OK")


# ---------------------------------------------------------------------------
# AttackResolver._get_sword_bonus_vs_creature
# ---------------------------------------------------------------------------

func test_flame_tongue_no_bonus_vs_ordinary_target() -> void:
	var attacker := _build_fighter_wielding("flame_tongue")
	var target := _build_monster("ordinary_humanoid", {
		"monster_types": ["humanoid"],
		"hit_dice": {"base": 1, "modifier": 0}, "armor_class": 6, "morale": 7,
	})
	var resolver := AttackResolver.new()
	check(resolver._get_sword_bonus_vs_creature(attacker, target) == 0,
		"flame_tongue vs ordinary humanoid: no extra bonus")
	print("  flame_tongue_no_bonus_vs_ordinary_target: OK")


func test_flame_tongue_plus_two_vs_regenerating_target() -> void:
	var attacker := _build_fighter_wielding("flame_tongue")
	var target := _build_monster("regen_target", {
		"monster_types": ["giant_humanoid"],
		"hit_dice": {"base": 6, "modifier": 3}, "armor_class": 5, "morale": 9,
		"special_abilities": [{"ability_id": "regeneration"}],
	})
	var resolver := AttackResolver.new()
	check(resolver._get_sword_bonus_vs_creature(attacker, target) == 2,
		"flame_tongue vs regenerating: +2 extra")
	print("  flame_tongue_plus_two_vs_regenerating_target: OK")


func test_flame_tongue_plus_three_vs_undead_target() -> void:
	var attacker := _build_fighter_wielding("flame_tongue")
	var target := _build_monster("undead_target", {
		"monster_types": ["undead"],
		"hit_dice": {"base": 2, "modifier": 0}, "armor_class": 7, "morale": 12,
	})
	var resolver := AttackResolver.new()
	check(resolver._get_sword_bonus_vs_creature(attacker, target) == 3,
		"flame_tongue vs undead: +3 extra")
	print("  flame_tongue_plus_three_vs_undead_target: OK")


func test_flame_tongue_plus_three_vs_plant_like_target() -> void:
	var attacker := _build_fighter_wielding("flame_tongue")
	var target := _build_monster("plant_target", {
		"monster_types": ["fantastic_creature"], "sub_types": ["plant"],
		"hit_dice": {"base": 8, "modifier": 0}, "armor_class": 3, "morale": 11,
	})
	var resolver := AttackResolver.new()
	check(resolver._get_sword_bonus_vs_creature(attacker, target) == 3,
		"flame_tongue vs plant-like: +3 extra")
	print("  flame_tongue_plus_three_vs_plant_like_target: OK")


func test_frost_brand_plus_three_vs_hot_environment_target() -> void:
	var attacker := _build_fighter_wielding("frost_brand")
	var target := _build_monster("salamander_target", {
		"monster_types": ["elemental"], "sub_types": ["fire"],
		"hit_dice": {"base": 4, "modifier": 0}, "armor_class": 3, "morale": 9,
	})
	var resolver := AttackResolver.new()
	check(resolver._get_sword_bonus_vs_creature(attacker, target) == 3,
		"frost_brand vs fire-sub-type: +3 extra (base +3 + this +3 = +6 total)")
	print("  frost_brand_plus_three_vs_hot_environment_target: OK")


func test_frost_brand_no_bonus_vs_ordinary_target() -> void:
	var attacker := _build_fighter_wielding("frost_brand")
	var target := _build_monster("ordinary", {
		"monster_types": ["humanoid"],
		"hit_dice": {"base": 1, "modifier": 0}, "armor_class": 6, "morale": 7,
	})
	var resolver := AttackResolver.new()
	check(resolver._get_sword_bonus_vs_creature(attacker, target) == 0,
		"frost_brand vs ordinary humanoid: no extra bonus")
	print("  frost_brand_no_bonus_vs_ordinary_target: OK")


# ---------------------------------------------------------------------------
# WornMagicEffectResolver — Luck Blade + Frost Brand wielded effects
# ---------------------------------------------------------------------------

func test_luck_blade_grants_plus_one_saves_when_wielded() -> void:
	_setup()
	var char_data := _make_char()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "luck_blade",
		"name": "Luck Blade", "magical_bonus": 1,
		"is_equipped": true, "slot": "hands_main",
		"encumbrance_units": 167, "item_category": "weapon", "is_magical": true,
	})
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(sword_id)])
	# Lower save target = better save; +1 RAW → -1 on the save target.
	for save_key in ["save_petrification", "save_poison_death", "save_blast_breath",
			"save_staffs_wands", "save_spells"]:
		var save_mod: int = char_data.modifiers.get_effective_value(save_key, 0)
		check(save_mod == -1,
			"Luck Blade should give -1 on '%s' target (= +1 on d20), got %d" %
				[save_key, save_mod])
	_teardown()
	print("  luck_blade_grants_plus_one_saves_when_wielded: OK")


func test_luck_blade_no_bonus_when_off_hand() -> void:
	_setup()
	var char_data := _make_char()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "luck_blade",
		"name": "Luck Blade", "magical_bonus": 1,
		"is_equipped": true, "slot": "hands_off",  # off-hand, NOT main
		"encumbrance_units": 167, "item_category": "weapon", "is_magical": true,
	})
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(sword_id)])
	check(char_data.modifiers.get_effective_value("save_spells", 0) == 0,
		"Luck Blade in off-hand grants NO save bonus (wielded gate enforced)")
	_teardown()
	print("  luck_blade_no_bonus_when_off_hand: OK")


func test_luck_blade_no_bonus_when_unequipped() -> void:
	_setup()
	var char_data := _make_char()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "luck_blade",
		"name": "Luck Blade", "magical_bonus": 1,
		"is_equipped": false, "slot": "pack",
		"encumbrance_units": 167, "item_category": "weapon", "is_magical": true,
	})
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(sword_id)])
	check(char_data.modifiers.get_effective_value("save_spells", 0) == 0,
		"unequipped Luck Blade grants NO save bonus")
	_teardown()
	print("  luck_blade_no_bonus_when_unequipped: OK")


func test_frost_brand_grants_fire_resistance_when_wielded() -> void:
	_setup()
	var char_data := _make_char()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "frost_brand",
		"name": "Frost Brand", "magical_bonus": 3,
		"is_equipped": true, "slot": "hands_main",
		"encumbrance_units": 167, "item_category": "weapon", "is_magical": true,
	})
	WornMagicEffectResolver.refresh_for_character(
		char_data, [CampaignRepository.get_inventory_item_by_id(sword_id)])
	# Ring of Fire Resistance pattern: -2 on save_blast_breath.
	var save_mod: int = char_data.modifiers.get_effective_value("save_blast_breath", 0)
	check(save_mod == -2,
		"Frost Brand should give Ring of Fire Resistance equivalent (-2 save_blast_breath); got %d" %
			save_mod)
	_teardown()
	print("  frost_brand_grants_fire_resistance_when_wielded: OK")


# ---------------------------------------------------------------------------
# MagicItemActivator.apply_life_drinker_drain
# ---------------------------------------------------------------------------

func test_life_drinker_drains_one_level_and_decrements_charges() -> void:
	_setup()
	var wielder := _make_char()
	var catalog := MagicItemCatalog.new()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "life_drinker",
		"name": "Life Drinker", "is_magical": true, "magical_bonus": 1,
		"uses_remaining": 5,
	})
	var target := _build_monster("drain_target", {
		"monster_types": ["humanoid"],
		"hit_dice": {"base": 4, "modifier": 0}, "armor_class": 6, "morale": 8,
	})
	var result: Dictionary = MagicItemActivator.apply_life_drinker_drain(
		sword_id, wielder, target, catalog)
	check(bool(result["success"]) == true,
		"drain should succeed; message: %s" % str(result["message"]))
	check(int(result["charges_remaining"]) == 4,
		"5 charges - 1 drain = 4 remaining; got %d" % int(result["charges_remaining"]))
	check(int(result["levels_drained"]) == 1, "RAW: drains 1 level per use")
	# Target carries the energy-drained flag with metadata.
	var t_flags: EntityFlags = target.get_flags()
	check(t_flags.has_flag("is_energy_drained"),
		"target should be flagged is_energy_drained")
	var meta: Dictionary = t_flags.get_flag_metadata("is_energy_drained")
	check(int(meta.get("drained_levels", 0)) == 1,
		"flag metadata.drained_levels = 1; got %d" % int(meta.get("drained_levels", 0)))
	_teardown()
	print("  life_drinker_drains_one_level_and_decrements_charges: OK")


func test_life_drinker_refuses_at_zero_charges() -> void:
	_setup()
	var wielder := _make_char()
	var catalog := MagicItemCatalog.new()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "life_drinker",
		"name": "Life Drinker", "is_magical": true, "magical_bonus": 1,
		"uses_remaining": 0,  # spent
	})
	var target := _build_monster("dt", {
		"monster_types": ["humanoid"],
		"hit_dice": {"base": 1, "modifier": 0}, "armor_class": 6, "morale": 7,
	})
	var result: Dictionary = MagicItemActivator.apply_life_drinker_drain(
		sword_id, wielder, target, catalog)
	check(bool(result["success"]) == false,
		"zero-charges Life Drinker should refuse the drain")
	check(str(result["message"]).contains("no charges"),
		"failure message should mention no charges; got: %s" % str(result["message"]))
	# Sword stays magical (still +1 per RAW).
	var sword_post: Dictionary = CampaignRepository.get_inventory_item_by_id(sword_id)
	check(int(sword_post.get("is_magical", 0)) == 1,
		"Life Drinker at 0 charges should still be magical (+1 sword per RAW)")
	_teardown()
	print("  life_drinker_refuses_at_zero_charges: OK")


func test_life_drinker_becomes_normal_plus_one_when_charges_hit_zero() -> void:
	_setup()
	var wielder := _make_char()
	var catalog := MagicItemCatalog.new()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "life_drinker",
		"name": "Life Drinker", "is_magical": true, "magical_bonus": 1,
		"uses_remaining": 1,  # final charge
	})
	var target := _build_monster("dt", {
		"monster_types": ["humanoid"],
		"hit_dice": {"base": 4, "modifier": 0}, "armor_class": 6, "morale": 8,
	})
	var result: Dictionary = MagicItemActivator.apply_life_drinker_drain(
		sword_id, wielder, target, catalog)
	check(bool(result["success"]) == true, "final drain should succeed")
	check(int(result["charges_remaining"]) == 0, "charges drop to 0")
	check(bool(result["became_normal_plus_one"]) == true,
		"sword reports became_normal_plus_one = true when charges hit 0")
	# Sword still magical + still +1 (not cleared to non-magical).
	var sword_post: Dictionary = CampaignRepository.get_inventory_item_by_id(sword_id)
	check(int(sword_post.get("is_magical", 0)) == 1,
		"Life Drinker at 0 charges STILL magical (+1 sword per RAW)")
	check(int(sword_post.get("magical_bonus", 0)) == 1,
		"Life Drinker at 0 charges STILL +1 (RAW preserves +1 status)")
	_teardown()
	print("  life_drinker_becomes_normal_plus_one_when_charges_hit_zero: OK")


func test_life_drinker_refuses_wrong_item_key() -> void:
	_setup()
	var wielder := _make_char()
	var catalog := MagicItemCatalog.new()
	# A different sword in the same slot.
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "sword_1",
		"name": "Sword +1", "is_magical": true, "magical_bonus": 1,
		"uses_remaining": 5,
	})
	var target := _build_monster("dt", {
		"monster_types": ["humanoid"],
		"hit_dice": {"base": 1, "modifier": 0}, "armor_class": 6, "morale": 7,
	})
	var result: Dictionary = MagicItemActivator.apply_life_drinker_drain(
		sword_id, wielder, target, catalog)
	check(bool(result["success"]) == false,
		"wrong item_key should refuse the drain")
	check(str(result["message"]).contains("not a Life Drinker"),
		"failure message should mention 'not a Life Drinker'")
	_teardown()
	print("  life_drinker_refuses_wrong_item_key: OK")


# ---------------------------------------------------------------------------
# TreasureInstantiator._roll_charges
# ---------------------------------------------------------------------------

func test_roll_charges_int_passthrough() -> void:
	check(TreasureInstantiator._roll_charges(5, null) == 5,
		"int input passes through")
	check(TreasureInstantiator._roll_charges(-1, null) == -1,
		"-1 sentinel passes through")
	print("  roll_charges_int_passthrough: OK")


func test_roll_charges_parses_1d4_plus_4() -> void:
	# With a seeded rng, the roll is deterministic. Range: 5-8.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var n := TreasureInstantiator._roll_charges("1d4+4", rng)
	check(n >= 5 and n <= 8,
		"1d4+4 should roll in [5, 8]; got %d" % n)
	print("  roll_charges_parses_1d4_plus_4: OK")


func test_roll_charges_parses_1d4_plus_1() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var n := TreasureInstantiator._roll_charges("1d4+1", rng)
	check(n >= 2 and n <= 5,
		"1d4+1 should roll in [2, 5]; got %d" % n)
	print("  roll_charges_parses_1d4_plus_1: OK")


func test_roll_charges_returns_minus_one_for_unparseable() -> void:
	check(TreasureInstantiator._roll_charges("junk", null) == -1,
		"unparseable string returns -1")
	check(TreasureInstantiator._roll_charges(null, null) == -1,
		"null returns -1")
	print("  roll_charges_returns_minus_one_for_unparseable: OK")


# ---------------------------------------------------------------------------
# Setup / teardown / helpers
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "Magic Swords Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR, _DB_CAMPAIGN, "Sword Wielder", "fighter", 5, 0, 30, 30])
	GameState.campaign_id = _DB_CAMPAIGN
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	GameState.dice_overrides.erase("vorpal_save_vs_death")


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
	GameState.dice_overrides.erase("vorpal_save_vs_death")


func _make_char() -> CharacterData:
	var c := CharacterData.new()
	c.id = _DB_CHAR
	c.name = "Sword Wielder"
	c.character_class = "fighter"
	c.level = 5
	c.hp_max = 30
	c.hp_current = 30
	return c


func _build_monster(id_str: String, monster_data: Dictionary) -> Combatant:
	var base := {
		"id": id_str,
		"name": id_str,
		"attack_routines": [{"sequence": [{"weapon": "claw", "damage": "1d6"}]}],
		"morale": 0,
		"save_as": {"class": "fighter", "level": 1},
		"xp": 10,
		"movement": {"land": {"exploration": 120, "combat": 40}},
	}
	base.merge(monster_data, true)
	return Combatant.from_monster(base, 8, id_str, "test_group")


func _build_fighter_wielding(weapon_item_key: String) -> Combatant:
	var cd := CharacterData.new()
	cd.id = "fighter_test"
	cd.name = "Fighter"
	cd.hp_max = 20
	cd.hp_current = 20
	cd.armor_class = 5
	cd.attack_throw = 8
	cd.strength = 14
	cd.dexterity = 10
	var c := Combatant.from_character(cd)
	c.set_equipped_weapon({
		"item_key": weapon_item_key,
		"weapon_damage": "1d8",
		"magical_bonus": 1,
	})
	return c


# ---------------------------------------------------------------------------
# Deferred-consumer wire-up — Frost Brand environmental glow
# ---------------------------------------------------------------------------

func _make_terrain(biome: String, subtype: String, elevation: String = "flat") -> HexTerrainData:
	var t := HexTerrainData.new()
	t.biome = biome
	t.biome_subtype = subtype
	t.elevation = elevation
	return t


func test_frost_brand_glow_in_tundra_in_winter() -> void:
	var t := _make_terrain(HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_CLEAR_TUNDRA)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.WINTER) == true,
		"tundra in winter: glow")
	print("  frost_brand_glow_in_tundra_in_winter: OK")


func test_frost_brand_glow_in_tundra_in_spring() -> void:
	var t := _make_terrain(HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_CLEAR_TUNDRA)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.SPRING) == true,
		"tundra (always cold) in any non-summer season: glow")
	print("  frost_brand_glow_in_tundra_in_spring: OK")


func test_frost_brand_no_glow_in_tundra_in_summer() -> void:
	var t := _make_terrain(HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_CLEAR_TUNDRA)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.SUMMER) == false,
		"tundra in summer: no glow (RAW excludes summer)")
	print("  frost_brand_no_glow_in_tundra_in_summer: OK")


func test_frost_brand_glow_in_taiga_in_autumn() -> void:
	var t := _make_terrain(HexTerrainData.BIOME_WOODS, HexTerrainData.SUBTYPE_FOREST_TAIGA)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.AUTUMN) == true,
		"taiga in autumn: glow")
	print("  frost_brand_glow_in_taiga_in_autumn: OK")


func test_frost_brand_glow_in_glacial_mountain_in_winter() -> void:
	var t := _make_terrain(
		HexTerrainData.BIOME_CLEAR,
		HexTerrainData.SUBTYPE_MOUNTAINS_GLACIAL,
		HexTerrainData.ELEVATION_MOUNTAINS)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.WINTER) == true,
		"glacial mountain in winter: glow")
	print("  frost_brand_glow_in_glacial_mountain_in_winter: OK")


func test_frost_brand_glow_in_grassland_in_winter() -> void:
	var t := _make_terrain(HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_CLEAR_GRASSLAND)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.WINTER) == true,
		"grassland in winter: glow")
	print("  frost_brand_glow_in_grassland_in_winter: OK")


func test_frost_brand_no_glow_in_grassland_in_summer() -> void:
	var t := _make_terrain(HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_CLEAR_GRASSLAND)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.SUMMER) == false,
		"grassland in summer: no glow")
	print("  frost_brand_no_glow_in_grassland_in_summer: OK")


func test_frost_brand_glow_in_forest_in_winter() -> void:
	# Plain forest = woods biome without a specific subtype.
	var t := _make_terrain(HexTerrainData.BIOME_WOODS, "")
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.WINTER) == true,
		"forest (woods biome, no subtype) in winter: glow")
	print("  frost_brand_glow_in_forest_in_winter: OK")


func test_frost_brand_glow_in_dense_forest_in_winter() -> void:
	var t := _make_terrain(HexTerrainData.BIOME_WOODS, HexTerrainData.SUBTYPE_FOREST_DENSE)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.WINTER) == true,
		"dense forest in winter: glow")
	print("  frost_brand_glow_in_dense_forest_in_winter: OK")


func test_frost_brand_glow_in_regular_mountain_in_winter() -> void:
	# Non-volcanic, non-glacial mountain — just elevation=mountains, no subtype.
	var t := _make_terrain(HexTerrainData.BIOME_CLEAR, "", HexTerrainData.ELEVATION_MOUNTAINS)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.WINTER) == true,
		"non-volcanic non-glacial mountain in winter: glow")
	print("  frost_brand_glow_in_regular_mountain_in_winter: OK")


func test_frost_brand_no_glow_in_volcanic_mountain_in_winter() -> void:
	var t := _make_terrain(
		HexTerrainData.BIOME_CLEAR,
		HexTerrainData.SUBTYPE_MOUNTAINS_VOLCANIC,
		HexTerrainData.ELEVATION_MOUNTAINS)
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.WINTER) == false,
		"volcanic mountain in winter: no glow (RAW excludes volcanic)")
	print("  frost_brand_no_glow_in_volcanic_mountain_in_winter: OK")


func test_frost_brand_no_glow_in_desert_in_winter() -> void:
	var t := _make_terrain(HexTerrainData.BIOME_DESERT, "")
	check(FrostBrandEnvironment.frost_brand_should_glow(t, CalendarSeasons.WINTER) == false,
		"desert in winter: no glow (not on the list)")
	print("  frost_brand_no_glow_in_desert_in_winter: OK")


func test_frost_brand_no_glow_when_terrain_null() -> void:
	check(FrostBrandEnvironment.frost_brand_should_glow(null, CalendarSeasons.WINTER) == false,
		"null terrain: no glow (defensive)")
	print("  frost_brand_no_glow_when_terrain_null: OK")


func test_frost_brand_update_sets_flag_when_wielded_and_conditions_met() -> void:
	var char_data := _make_char()
	char_data.flags = EntityFlags.new()
	var inventory: Array = [{
		"id": "fb_sword_1",
		"item_key": "frost_brand",
		"is_equipped": 1,
		"slot": "hands_main",
	}]
	var t := _make_terrain(HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_CLEAR_TUNDRA)
	FrostBrandEnvironment.update_glow_state_for_character(
		char_data, inventory, t, CalendarSeasons.WINTER)
	check(char_data.flags.has_flag("wielding_glowing_frost_brand"),
		"wielded Frost Brand in glow-conditions: flag set")
	var meta: Dictionary = char_data.flags.get_flag_metadata("wielding_glowing_frost_brand")
	check(int(meta.get("light_radius_cells", 0)) == 6,
		"metadata.light_radius_cells = 6")
	print("  frost_brand_update_sets_flag_when_wielded_and_conditions_met: OK")


func test_frost_brand_update_clears_flag_when_conditions_fail() -> void:
	var char_data := _make_char()
	char_data.flags = EntityFlags.new()
	var inventory: Array = [{
		"id": "fb_sword_2",
		"item_key": "frost_brand",
		"is_equipped": 1,
		"slot": "hands_main",
	}]
	# First: set the flag via glow conditions.
	var cold_terrain := _make_terrain(HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_CLEAR_TUNDRA)
	FrostBrandEnvironment.update_glow_state_for_character(
		char_data, inventory, cold_terrain, CalendarSeasons.WINTER)
	check(char_data.flags.has_flag("wielding_glowing_frost_brand"),
		"precondition: flag set in cold terrain")
	# Then: move to summer tundra — conditions fail; flag should clear.
	FrostBrandEnvironment.update_glow_state_for_character(
		char_data, inventory, cold_terrain, CalendarSeasons.SUMMER)
	check(not char_data.flags.has_flag("wielding_glowing_frost_brand"),
		"flag should clear when conditions fail (summer tundra)")
	print("  frost_brand_update_clears_flag_when_conditions_fail: OK")


func test_frost_brand_update_no_effect_when_unequipped() -> void:
	var char_data := _make_char()
	char_data.flags = EntityFlags.new()
	var inventory: Array = [{
		"id": "fb_sword_3",
		"item_key": "frost_brand",
		"is_equipped": 0,  # NOT equipped
		"slot": "pack",
	}]
	var t := _make_terrain(HexTerrainData.BIOME_CLEAR, HexTerrainData.SUBTYPE_CLEAR_TUNDRA)
	FrostBrandEnvironment.update_glow_state_for_character(
		char_data, inventory, t, CalendarSeasons.WINTER)
	check(not char_data.flags.has_flag("wielding_glowing_frost_brand"),
		"unequipped Frost Brand: no flag even when conditions match")
	print("  frost_brand_update_no_effect_when_unequipped: OK")


# ---------------------------------------------------------------------------
# Flame Tongue ignite / douse
# ---------------------------------------------------------------------------

func test_flame_tongue_ignite_sets_wielding_flag() -> void:
	_setup()
	var wielder := _make_char()
	wielder.flags = EntityFlags.new()
	var catalog := MagicItemCatalog.new()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "flame_tongue",
		"name": "Flame Tongue", "is_magical": true, "magical_bonus": 1,
		"is_equipped": true, "slot": "hands_main",
	})
	var result: Dictionary = MagicItemActivator.apply_flame_tongue_ignite(
		sword_id, wielder, catalog)
	check(bool(result["success"]) == true,
		"ignite succeeds; message: %s" % str(result["message"]))
	check(bool(result["light_active"]) == true, "light_active = true")
	check(int(result["light_radius_cells"]) == 6, "light_radius_cells = 6")
	check(wielder.flags.has_flag("wielding_lit_flame_tongue"),
		"wielder gains wielding_lit_flame_tongue flag")
	_teardown()
	print("  flame_tongue_ignite_sets_wielding_flag: OK")


func test_flame_tongue_ignite_refuses_when_unequipped() -> void:
	_setup()
	var wielder := _make_char()
	wielder.flags = EntityFlags.new()
	var catalog := MagicItemCatalog.new()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "flame_tongue",
		"name": "Flame Tongue", "is_magical": true, "magical_bonus": 1,
		"is_equipped": false, "slot": "pack",  # in pack
	})
	var result: Dictionary = MagicItemActivator.apply_flame_tongue_ignite(
		sword_id, wielder, catalog)
	check(bool(result["success"]) == false,
		"unequipped Flame Tongue refuses ignite")
	check(str(result["message"]).contains("wielded"),
		"message mentions wielding requirement; got: %s" % str(result["message"]))
	check(not wielder.flags.has_flag("wielding_lit_flame_tongue"),
		"no flag set on refuse")
	_teardown()
	print("  flame_tongue_ignite_refuses_when_unequipped: OK")


func test_flame_tongue_ignite_refuses_wrong_item_key() -> void:
	_setup()
	var wielder := _make_char()
	wielder.flags = EntityFlags.new()
	var catalog := MagicItemCatalog.new()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "sword_1",
		"name": "Sword +1", "is_magical": true, "magical_bonus": 1,
		"is_equipped": true, "slot": "hands_main",
	})
	var result: Dictionary = MagicItemActivator.apply_flame_tongue_ignite(
		sword_id, wielder, catalog)
	check(bool(result["success"]) == false,
		"non-Flame-Tongue refuses ignite")
	check(str(result["message"]).contains("not a Flame Tongue"),
		"message mentions wrong-item")
	_teardown()
	print("  flame_tongue_ignite_refuses_wrong_item_key: OK")


func test_flame_tongue_douse_clears_flag() -> void:
	_setup()
	var wielder := _make_char()
	wielder.flags = EntityFlags.new()
	var catalog := MagicItemCatalog.new()
	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "flame_tongue",
		"name": "Flame Tongue", "is_magical": true, "magical_bonus": 1,
		"is_equipped": true, "slot": "hands_main",
	})
	# Ignite first.
	MagicItemActivator.apply_flame_tongue_ignite(sword_id, wielder, catalog)
	check(wielder.flags.has_flag("wielding_lit_flame_tongue"),
		"precondition: ignited")
	# Douse.
	var result: Dictionary = MagicItemActivator.apply_flame_tongue_douse(
		sword_id, wielder)
	check(bool(result["success"]) == true, "douse succeeds")
	check(not wielder.flags.has_flag("wielding_lit_flame_tongue"),
		"flag cleared after douse")
	_teardown()
	print("  flame_tongue_douse_clears_flag: OK")


# ---------------------------------------------------------------------------
# Life Drinker level reduction consumer
# ---------------------------------------------------------------------------

func test_character_data_get_effective_level_no_drain() -> void:
	var cd := CharacterData.new()
	cd.level = 5
	cd.flags = EntityFlags.new()
	check(cd.get_effective_level() == 5,
		"no drain: effective_level == level")
	print("  character_data_get_effective_level_no_drain: OK")


func test_character_data_get_effective_level_with_drain() -> void:
	var cd := CharacterData.new()
	cd.level = 5
	cd.flags = EntityFlags.new()
	cd.flags.set_flag("is_energy_drained", "life_drinker:sword1", {
		"drained_levels": 2,
	})
	check(cd.get_effective_level() == 3,
		"5 - 2 = 3 effective level; got %d" % cd.get_effective_level())
	print("  character_data_get_effective_level_with_drain: OK")


func test_character_data_get_effective_level_floor_at_1() -> void:
	var cd := CharacterData.new()
	cd.level = 2
	cd.flags = EntityFlags.new()
	cd.flags.set_flag("is_energy_drained", "lots_of_wraiths", {
		"drained_levels": 99,  # way more than character has
	})
	check(cd.get_effective_level() == 1,
		"effective level floors at 1; got %d" % cd.get_effective_level())
	print("  character_data_get_effective_level_floor_at_1: OK")


func test_character_data_get_effective_level_stacks_multiple_sources() -> void:
	# Multiple drain sources stack (Life Drinker + Wraith both hit you).
	var cd := CharacterData.new()
	cd.level = 10
	cd.flags = EntityFlags.new()
	cd.flags.set_flag("is_energy_drained", "life_drinker:sword1", {"drained_levels": 1})
	cd.flags.set_flag("is_energy_drained", "wraith:enc1", {"drained_levels": 2})
	check(cd.get_effective_level() == 7,
		"10 - 1 - 2 = 7 effective level; got %d" % cd.get_effective_level())
	print("  character_data_get_effective_level_stacks_multiple_sources: OK")


func test_combatant_get_effective_level_or_hd_pc_path() -> void:
	var cd := CharacterData.new()
	cd.id = "pc_drain_test"
	cd.level = 5
	cd.flags = EntityFlags.new()
	cd.flags.set_flag("is_energy_drained", "life_drinker:sword1", {"drained_levels": 2})
	var c := Combatant.from_character(cd)
	check(c.get_effective_level_or_hd() == 3,
		"PC Combatant.get_effective_level_or_hd routes through character's drain; got %d" %
			c.get_effective_level_or_hd())
	# Base method still reports the un-drained value (caller chooses semantic).
	check(c.get_level_or_hd() == 5,
		"un-effective get_level_or_hd still returns base level (no auto-swap)")
	print("  combatant_get_effective_level_or_hd_pc_path: OK")


func test_combatant_get_effective_level_or_hd_monster_path() -> void:
	# Build an 8 HD monster, apply 3 drained levels via _monster_flags.
	var c := _build_monster("drain_test_monster", {
		"monster_types": ["humanoid"],
		"hit_dice": {"base": 8, "modifier": 0}, "armor_class": 5, "morale": 9,
	})
	check(c.get_effective_level_or_hd() == 8, "baseline 8 HD")
	# Set the drain flag on the monster's _monster_flags via apply_life_drinker_drain.
	var t_flags: EntityFlags = c.get_flags()
	t_flags.set_flag("is_energy_drained", "test_source", {"drained_levels": 3})
	check(c.get_effective_level_or_hd() == 5,
		"8 HD - 3 drain = 5 effective; got %d" % c.get_effective_level_or_hd())
	print("  combatant_get_effective_level_or_hd_monster_path: OK")


func test_monster_attack_throw_uses_drained_hd() -> void:
	# Pin the integration: monster attack throw uses get_effective_level_or_hd,
	# so drain reduces the monster's attack capability.
	var c := _build_monster("attack_drain_monster", {
		"monster_types": ["humanoid"],
		"hit_dice": {"base": 8, "modifier": 0}, "armor_class": 5, "morale": 9,
	})
	var pre_throw := c.get_effective_attack_throw()
	# Drain 3 levels.
	var t_flags: EntityFlags = c.get_flags()
	t_flags.set_flag("is_energy_drained", "test_source", {"drained_levels": 3})
	var post_throw := c.get_effective_attack_throw()
	# 8 HD attack throw < 5 HD attack throw (higher HD = lower target = better).
	# So drain → HIGHER target number = worse attack.
	check(post_throw > pre_throw,
		"drained monster attack throw target should be HIGHER (worse attack); pre=%d post=%d" %
			[pre_throw, post_throw])
	print("  monster_attack_throw_uses_drained_hd: OK")
