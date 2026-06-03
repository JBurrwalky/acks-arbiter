extends "res://tests/test_suite_base.gd"

## 2026-06-03 — Level-boost potions + Giant Strength + Invulnerability.
##
## Covers all four temp-duration potions in one suite:
##   * Potion of Heroism (Fighter-only, +N combat levels, 1 day)
##   * Potion of Super-Heroism (Fighter-only, bigger table, 1 day)
##   * Potion of Giant Strength (any class, 3 turn)
##   * Potion of Invulnerability (any class, +2/-2 with weekly inversion)
##
## RAW supplied by Jedidiah 2026-06-03 from ACKS Core p.215+ (full text in
## PotionDurationService docstring).
##
## Coverage:
##   - Catalog: 4 items have direct_potion_effect with correct effect_kind +
##     no defer_reason.
##   - PotionDurationService direct unit tests for all apply_* + sickened.
##   - MagicItemActivator.drink_potion integration tests with full DB I/O.
##   - Tick-expire cleanup via ActiveEffectTracker dispatch_cleanup_on_tick.
##   - Two-potion sickened gate (RAW: ACore line 224).
##   - Class restriction gate on combat_progression == "fighter".
##   - Invulnerability weekly inversion.
##   - EntityFlags regression (new flags documented).


# ---------------------------------------------------------------------------
# Constants + helpers
# ---------------------------------------------------------------------------

const _CAMPAIGN_ID := "lbp_test_campaign"
const _DRINKER_ID := "lbp_drinker_id"


func _setup_campaign() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_CAMPAIGN_ID, "Level Boost Test", "Test World"])
	GameState.campaign_id = _CAMPAIGN_ID
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DRINKER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DRINKER_ID])
	# Reset Timekeeping clock so deterministic turn/day-based assertions
	# don't drift between tests.
	Timekeeping._on_session_ended()


func _teardown_campaign() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DRINKER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DRINKER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_CAMPAIGN_ID])


func _make_drinker(class_id: String, progression: String, level: int) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = _DRINKER_ID
	cd.campaign_id = _CAMPAIGN_ID
	cd.name = "Test Drinker"
	cd.character_class = class_id
	cd.combat_progression = progression
	cd.level = level
	cd.hp_max = 20; cd.hp_current = 20
	cd.armor_class = 5
	# Set baseline saves to mid-tier so save deltas are observable.
	cd.save_petrification = 15
	cd.save_poison_death = 14
	cd.save_blast_breath = 16
	cd.save_staffs_wands = 16
	cd.save_spells = 17
	cd.attack_throw = 10  # baseline L1-class throw
	return cd


func _make_class_registry() -> ClassRegistry:
	return ClassRegistry.new()


func _add_potion_row(item_key: String) -> String:
	return CampaignRepository.add_inventory_item({
		"character_id": _DRINKER_ID,
		"item_key": item_key,
		"name": item_key.capitalize(),
		"is_magical": true,
		"uses_remaining": 1,
	})


func _make_catalog() -> MagicItemCatalog:
	return MagicItemCatalog.new()


# ---------------------------------------------------------------------------
# Casting resolver fixture (minimal — used only for the tracker handle +
# cleanup-callback registration). All classes used here are class_name-
# registered so we can construct them directly without preloads.
# ---------------------------------------------------------------------------

func _make_casting_resolver(tracker_override: ActiveEffectTracker = null) -> CastingResolver:
	var spell_registry := SpellRegistry.new()
	var effect_registry := SpellEffectRegistry.new(spell_registry)
	var condition_catalog := ConditionCatalog.new()
	var custom_resolvers := CustomResolverRegistry.new()
	var tracker := tracker_override if tracker_override != null else ActiveEffectTracker.new()
	# geometry=null is supported by CastingResolver (uses the static helpers
	# on CastingGeometry directly).
	return CastingResolver.new(
		spell_registry, effect_registry, tracker, condition_catalog,
		custom_resolvers, null, CampaignRepository, DiceSystem)


# ---------------------------------------------------------------------------
# Test loop
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	# Catalog
	test_catalog_heroism_has_temp_combat_levels()
	test_catalog_super_heroism_has_temp_combat_levels()
	test_catalog_giant_strength_has_giant_strength_effect()
	test_catalog_invulnerability_has_weekly_effect()
	test_catalog_items_removed_from_expected_defer()
	# PotionDurationService — table lookups + eligibility predicates
	test_heroism_level_table_lookup()
	test_super_heroism_level_table_lookup()
	test_is_eligible_for_heroism_family_fighter_passes()
	test_is_eligible_for_heroism_family_mage_fails()
	# PotionDurationService — apply_combat_level_boost
	test_heroism_applies_attack_throw_delta_on_fighter()
	test_heroism_applies_save_deltas_on_fighter()
	test_heroism_grants_temp_hp_per_hd_average()
	test_heroism_temp_hp_dice_roll_varies_with_dice_override()
	test_super_heroism_temp_hp_uses_separate_roll_type()
	test_heroism_sets_has_active_potion_flag()
	test_heroism_refused_for_non_fighter_progression()
	test_heroism_refused_at_high_level()
	test_super_heroism_uses_bigger_table()
	# PotionDurationService — apply_giant_strength
	test_giant_strength_sets_attack_throw_ceiling()
	test_giant_strength_sets_has_active_potion_flag_with_metadata()
	test_giant_strength_no_class_restriction()
	# PotionDurationService — apply_invulnerability
	test_invulnerability_first_quaff_applies_bonus()
	test_invulnerability_duration_uses_dice_roll()
	test_invulnerability_duration_clamps_to_1d6_plus_6_range()
	test_invulnerability_duration_respects_override_param()
	test_invulnerability_second_quaff_within_week_inverts()
	test_invulnerability_quaff_after_week_normal()
	test_invulnerability_updates_last_quaff_day_flag()
	# PotionDurationService — apply_sickened
	test_sickened_applies_flag_with_metadata()
	test_sickened_duration_is_three_turns()
	# MagicItemActivator integration
	test_drink_potion_of_heroism_full_flow()
	test_drink_potion_of_giant_strength_full_flow()
	test_drink_potion_of_invulnerability_full_flow()
	test_drink_second_potion_triggers_sickened_gate()
	test_drink_heroism_consumed_even_when_class_restricted()
	# Cleanup-on-tick via ActiveEffectTracker
	test_heroism_cleanup_on_day_expire()
	test_giant_strength_cleanup_on_turn_expire()
	test_invulnerability_cleanup_on_turn_expire()
	# EntityFlags regression
	test_new_flags_documented()
	if not has_failures():
		print("LevelBoostPotions: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog tests
# ---------------------------------------------------------------------------

func _read_items() -> Array:
	var path := "res://data/treasure/magic_item_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return d.get("items", [])


func _find_item(items: Array, key: String) -> Dictionary:
	for v in items:
		if String((v as Dictionary).get("item_key", "")) == key:
			return v
	return {}


func test_catalog_heroism_has_temp_combat_levels() -> void:
	var it: Dictionary = _find_item(_read_items(), "potion_of_heroism")
	check(not it.is_empty(), "potion_of_heroism present")
	check(String(it.get("defer_reason", "")) == "",
		"potion_of_heroism defer_reason cleared (was: temp-effect-level mech needed)")
	var dpe: Dictionary = it.get("direct_potion_effect", {})
	check(String(dpe.get("effect_kind", "")) == "temp_combat_levels",
		"heroism effect_kind=temp_combat_levels")
	check(String(dpe.get("boost_table", "")) == "heroism",
		"heroism boost_table=heroism")
	check(bool(dpe.get("fighter_only", false)) == true,
		"heroism fighter_only=true")
	check(int(dpe.get("duration_days", 0)) == 1, "heroism duration_days=1")


func test_catalog_super_heroism_has_temp_combat_levels() -> void:
	var it: Dictionary = _find_item(_read_items(), "potion_of_super_heroism")
	check(String(it.get("defer_reason", "")) == "", "super-heroism defer cleared")
	var dpe: Dictionary = it.get("direct_potion_effect", {})
	check(String(dpe.get("effect_kind", "")) == "temp_combat_levels",
		"super-heroism effect_kind=temp_combat_levels")
	check(String(dpe.get("boost_table", "")) == "super_heroism",
		"super-heroism boost_table=super_heroism")
	check(bool(dpe.get("fighter_only", false)) == true,
		"super-heroism fighter_only=true")


func test_catalog_giant_strength_has_giant_strength_effect() -> void:
	var it: Dictionary = _find_item(_read_items(), "potion_of_giant_strength")
	check(String(it.get("defer_reason", "")) == "", "giant_strength defer cleared")
	var dpe: Dictionary = it.get("direct_potion_effect", {})
	check(String(dpe.get("effect_kind", "")) == "giant_strength",
		"giant_strength effect_kind=giant_strength")
	check(int(dpe.get("duration_turns", 0)) == 3,
		"giant_strength duration_turns=3 (Giant Strength spell duration)")


func test_catalog_invulnerability_has_weekly_effect() -> void:
	var it: Dictionary = _find_item(_read_items(), "potion_of_invulnerability")
	check(String(it.get("defer_reason", "")) == "",
		"invulnerability defer cleared (RAW resolved 2026-06-03)")
	var dpe: Dictionary = it.get("direct_potion_effect", {})
	check(String(dpe.get("effect_kind", "")) == "weekly_invulnerability",
		"invulnerability effect_kind=weekly_invulnerability")
	check(int(dpe.get("weekly_window_days", 0)) == 7, "weekly_window_days=7")
	check(int(dpe.get("bonus", 0)) == 2, "bonus=+2")
	check(int(dpe.get("inverted_penalty", 0)) == -2, "inverted_penalty=-2")


func test_catalog_items_removed_from_expected_defer() -> void:
	# Regression: the 4 items should NOT appear as bare array members in
	# EXPECTED_DEFER_KEYS anymore.
	var path := "res://tests/test_magic_item_catalog.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "test_magic_item_catalog.gd should be readable")
		return
	var content := f.get_as_text()
	f.close()
	for k: String in ["potion_of_heroism", "potion_of_super_heroism",
			"potion_of_giant_strength", "potion_of_invulnerability"]:
		var bare: String = '"' + k + '",'
		check(not content.contains(bare),
			"%s should NOT appear as bare array member in EXPECTED_DEFER_KEYS" % k)


# ---------------------------------------------------------------------------
# Level table + eligibility tests
# ---------------------------------------------------------------------------

func test_heroism_level_table_lookup() -> void:
	# Per ACKS Core p.215+: 0→4, 1-3→3, 4-7→2, 8-10→1, 11+→0
	check(PotionDurationService.levels_granted_for("potion_of_heroism", 0) == 4,
		"L0 → +4 levels (treated as Fighter)")
	check(PotionDurationService.levels_granted_for("potion_of_heroism", 1) == 3,
		"L1 → +3 levels")
	check(PotionDurationService.levels_granted_for("potion_of_heroism", 3) == 3,
		"L3 → +3 levels (upper bound of 1-3 row)")
	check(PotionDurationService.levels_granted_for("potion_of_heroism", 4) == 2,
		"L4 → +2 levels (lower bound of 4-7 row)")
	check(PotionDurationService.levels_granted_for("potion_of_heroism", 7) == 2,
		"L7 → +2 levels")
	check(PotionDurationService.levels_granted_for("potion_of_heroism", 8) == 1,
		"L8 → +1 level")
	check(PotionDurationService.levels_granted_for("potion_of_heroism", 10) == 1,
		"L10 → +1 level")
	check(PotionDurationService.levels_granted_for("potion_of_heroism", 11) == 0,
		"L11+ → +0 levels (RAW: high-level chars get no benefit)")
	check(PotionDurationService.levels_granted_for("potion_of_heroism", 14) == 0,
		"L14 → +0 levels")


func test_super_heroism_level_table_lookup() -> void:
	# Per ACKS Core p.215+: 0→6, 1-3→5, 4-7→4, 8-10→3, 11-12→2, 13+→0 (V1)
	check(PotionDurationService.levels_granted_for("potion_of_super_heroism", 0) == 6,
		"L0 → +6 levels (treated as Fighter)")
	check(PotionDurationService.levels_granted_for("potion_of_super_heroism", 1) == 5,
		"L1 → +5 levels")
	check(PotionDurationService.levels_granted_for("potion_of_super_heroism", 4) == 4,
		"L4 → +4 levels")
	check(PotionDurationService.levels_granted_for("potion_of_super_heroism", 8) == 3,
		"L8 → +3 levels")
	check(PotionDurationService.levels_granted_for("potion_of_super_heroism", 11) == 2,
		"L11 → +2 levels")
	check(PotionDurationService.levels_granted_for("potion_of_super_heroism", 12) == 2,
		"L12 → +2 levels (upper bound)")
	check(PotionDurationService.levels_granted_for("potion_of_super_heroism", 13) == 0,
		"L13+ → +0 (RAW silent above 12; V1 conservative)")


func test_is_eligible_for_heroism_family_fighter_passes() -> void:
	var cd := _make_drinker("fighter", "fighter", 1)
	check(PotionDurationService.is_eligible_for_heroism_family(cd),
		"fighter progression passes eligibility")
	var paladin := _make_drinker("paladin", "fighter", 1)
	check(PotionDurationService.is_eligible_for_heroism_family(paladin),
		"paladin (fighter progression) passes eligibility")
	var barbarian := _make_drinker("barbarian", "fighter", 1)
	check(PotionDurationService.is_eligible_for_heroism_family(barbarian),
		"barbarian (fighter progression) passes eligibility")


func test_is_eligible_for_heroism_family_mage_fails() -> void:
	var mage := _make_drinker("mage", "mage", 5)
	check(not PotionDurationService.is_eligible_for_heroism_family(mage),
		"mage progression refused")
	var cleric := _make_drinker("cleric", "cleric", 5)
	check(not PotionDurationService.is_eligible_for_heroism_family(cleric),
		"cleric progression refused")
	var thief := _make_drinker("thief", "thief", 5)
	check(not PotionDurationService.is_eligible_for_heroism_family(thief),
		"thief progression refused")


# ---------------------------------------------------------------------------
# apply_combat_level_boost
# ---------------------------------------------------------------------------

func test_heroism_applies_attack_throw_delta_on_fighter() -> void:
	# Fighter L1 attack_throw = 10; +3 levels → L4 attack_throw = 8.
	# Modifier value should be 8 - 10 = -2.
	var cd := _make_drinker("fighter", "fighter", 1)
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_combat_level_boost(
		cd, "potion_heroism_item_id", "potion_of_heroism", reg, tr)
	check(bool(outcome.get("applied", false)) == true, "heroism applied to L1 fighter")
	check(int(outcome.get("extra_levels", 0)) == 3,
		"L1 fighter gets +3 levels from heroism")
	check(int(outcome.get("attack_throw_delta", 0)) == -2,
		"L1→L4 fighter attack_throw delta = -2 (10→8); got %d"
			% int(outcome.get("attack_throw_delta", 0)))
	var eff_throw: int = cd.get_effective_attack_throw()
	check(eff_throw == 8,
		"effective attack_throw after heroism = 8 (was 10); got %d" % eff_throw)


func test_heroism_applies_save_deltas_on_fighter() -> void:
	# Fighter L1 saves: petrification=15, poison_death=14, blast_breath=16,
	# staffs_wands=16, spells=17.
	# L4 saves:          13, 12, 14, 14, 15.
	# Per-save deltas: all -2 (improvement).
	var cd := _make_drinker("fighter", "fighter", 1)
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	PotionDurationService.apply_combat_level_boost(
		cd, "potion_heroism_item_id", "potion_of_heroism", reg, tr)
	check(cd.get_effective_save("save_petrification") == 13,
		"L1→L4 petrification 15→13")
	check(cd.get_effective_save("save_poison_death") == 12,
		"L1→L4 poison_death 14→12")
	check(cd.get_effective_save("save_blast_breath") == 14,
		"L1→L4 blast_breath 16→14")
	check(cd.get_effective_save("save_staffs_wands") == 14,
		"L1→L4 staffs_wands 16→14")
	check(cd.get_effective_save("save_spells") == 15,
		"L1→L4 spells 17→15")


func test_heroism_grants_temp_hp_per_hd_average() -> void:
	# 2026-06-03 V2: Heroism temp_hp = roll(N × hit_die) instead of
	# deterministic average. Tests force the DiceSystem roll via
	# GameState.dice_overrides["heroism_temp_hp"] so the assertion is
	# stable. The mock sets each die to its mid-roll value: d8 mid = 4
	# (post-modifier total), so L1 fighter +3 levels with override
	# = exactly 3 × 4 = 12.
	GameState.dice_overrides["heroism_temp_hp"] = 12
	var cd := _make_drinker("fighter", "fighter", 1)
	check(cd.temp_hp == 0, "baseline temp_hp=0")
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_combat_level_boost(
		cd, "potion_heroism_item_id", "potion_of_heroism", reg, tr)
	check(int(outcome.get("temp_hp_granted", 0)) == 12,
		"L1 fighter (d8) +3 levels, forced d8 mid roll = 12 temp_hp; got %d"
			% int(outcome.get("temp_hp_granted", 0)))
	check(cd.temp_hp == 12, "drinker.temp_hp set to 12; got %d" % cd.temp_hp)
	GameState.dice_overrides.erase("heroism_temp_hp")


func test_heroism_temp_hp_dice_roll_varies_with_dice_override() -> void:
	# Lock the d8 roll high to verify the override path actually drives
	# the value (regression against silent fallback to the average).
	GameState.dice_overrides["heroism_temp_hp"] = 24  # max per L1 fighter +3
	var cd := _make_drinker("fighter", "fighter", 1)
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_combat_level_boost(
		cd, "potion_heroism_item_id", "potion_of_heroism", reg, tr)
	check(int(outcome.get("temp_hp_granted", 0)) == 24,
		"forced max roll → 24 temp_hp; got %d"
			% int(outcome.get("temp_hp_granted", 0)))
	check(cd.temp_hp == 24, "drinker.temp_hp matches roll")
	GameState.dice_overrides.erase("heroism_temp_hp")


func test_super_heroism_temp_hp_uses_separate_roll_type() -> void:
	# super-heroism rolls "super_heroism_temp_hp" so test overrides don't
	# accidentally swap between item types.
	GameState.dice_overrides["super_heroism_temp_hp"] = 18
	GameState.dice_overrides["heroism_temp_hp"] = 999  # MUST NOT be used
	var cd := _make_drinker("fighter", "fighter", 1)
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_combat_level_boost(
		cd, "potion_sh_id", "potion_of_super_heroism", reg, tr)
	check(int(outcome.get("temp_hp_granted", 0)) == 18,
		"super-heroism temp_hp uses super_heroism_temp_hp roll; got %d"
			% int(outcome.get("temp_hp_granted", 0)))
	GameState.dice_overrides.erase("super_heroism_temp_hp")
	GameState.dice_overrides.erase("heroism_temp_hp")


func test_heroism_sets_has_active_potion_flag() -> void:
	# Force the V2 heroism_temp_hp dice roll so the applied_temp_hp
	# metadata assertion below is stable.
	GameState.dice_overrides["heroism_temp_hp"] = 12
	var cd := _make_drinker("fighter", "fighter", 1)
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	PotionDurationService.apply_combat_level_boost(
		cd, "potion_heroism_item_id", "potion_of_heroism", reg, tr)
	check(cd.flags.has_flag("has_active_potion"),
		"has_active_potion flag set after heroism applies")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_active_potion")
	check(String(meta.get("item_key", "")) == "potion_of_heroism",
		"metadata.item_key=potion_of_heroism")
	check(String(meta.get("effect_kind", "")) == "temp_combat_levels",
		"metadata.effect_kind=temp_combat_levels")
	check(int(meta.get("extra_levels", 0)) == 3, "metadata.extra_levels=3")
	check(int(meta.get("applied_temp_hp", 0)) == 12, "metadata.applied_temp_hp=12")
	GameState.dice_overrides.erase("heroism_temp_hp")


func test_heroism_refused_for_non_fighter_progression() -> void:
	var mage := _make_drinker("mage", "mage", 5)
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_combat_level_boost(
		mage, "potion_heroism_item_id", "potion_of_heroism", reg, tr)
	check(bool(outcome.get("applied", false)) == false,
		"heroism refused for mage")
	check(String(outcome.get("refused_reason", "")) == "class_restricted",
		"refused_reason=class_restricted")
	check(not mage.flags.has_flag("has_active_potion"),
		"no active_potion flag set on refusal")
	check(mage.temp_hp == 0, "no temp_hp granted on refusal")


func test_heroism_refused_at_high_level() -> void:
	var fighter := _make_drinker("fighter", "fighter", 12)
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_combat_level_boost(
		fighter, "potion_heroism_item_id", "potion_of_heroism", reg, tr)
	check(bool(outcome.get("applied", false)) == false,
		"heroism refused for L11+ fighter")
	check(String(outcome.get("refused_reason", "")) == "no_bonus_at_level",
		"refused_reason=no_bonus_at_level")
	check(not fighter.flags.has_flag("has_active_potion"),
		"no active_potion flag set when no bonus granted")


func test_super_heroism_uses_bigger_table() -> void:
	# L1 fighter + super-heroism = +5 levels. L1 attack_throw 10 → L6 = 7.
	# Delta = -3.
	var cd := _make_drinker("fighter", "fighter", 1)
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_combat_level_boost(
		cd, "potion_sh_item_id", "potion_of_super_heroism", reg, tr)
	check(int(outcome.get("extra_levels", 0)) == 5,
		"L1 fighter +5 levels from super-heroism; got %d"
			% int(outcome.get("extra_levels", 0)))
	check(int(outcome.get("attack_throw_delta", 0)) == -3,
		"L1→L6 fighter attack_throw delta = -3 (10→7); got %d"
			% int(outcome.get("attack_throw_delta", 0)))


# ---------------------------------------------------------------------------
# apply_giant_strength
# ---------------------------------------------------------------------------

func test_giant_strength_sets_attack_throw_ceiling() -> void:
	var cd := _make_drinker("fighter", "fighter", 5)
	cd.attack_throw = 8  # L5 fighter throw
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_giant_strength(
		cd, "potion_gs_item_id", "potion_of_giant_strength", tr)
	check(bool(outcome.get("applied", false)), "giant_strength applied")
	check(int(outcome.get("duration_turns", 0)) == 3,
		"giant_strength duration_turns=3")
	# Effective attack_throw should be min(8, 3) = 3 via set_ceiling.
	var eff: int = cd.get_effective_attack_throw()
	check(eff == 3,
		"effective attack_throw = min(8, 3) = 3 via Girdle ceiling; got %d" % eff)


func test_giant_strength_sets_has_active_potion_flag_with_metadata() -> void:
	var cd := _make_drinker("fighter", "fighter", 5)
	var tr := ActiveEffectTracker.new()
	PotionDurationService.apply_giant_strength(
		cd, "potion_gs_item_id", "potion_of_giant_strength", tr)
	check(cd.flags.has_flag("has_active_potion"), "active_potion flag set")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_active_potion")
	check(String(meta.get("effect_kind", "")) == "giant_strength",
		"effect_kind=giant_strength")
	check(int(meta.get("attack_throw_ceiling", 0)) == 3,
		"attack_throw_ceiling=3 (8-HD value)")
	check(float(meta.get("damage_multiplier", 1.0)) == 2.0,
		"damage_multiplier=2.0 (RAW: 'double normal damage')")
	check(int(meta.get("throw_rocks_range_feet", 0)) == 200,
		"throw_rocks_range_feet=200 (RAW)")
	check(int(meta.get("force_doors_bonus", 0)) == 16,
		"force_doors_bonus=+16 (RAW)")
	check(bool(meta.get("blocks_other_magical_strength", false)),
		"blocks_other_magical_strength=true (RAW: not combinable with other magical STR)")


func test_giant_strength_no_class_restriction() -> void:
	# RAW: Giant Strength has NO class restriction (unlike Heroism family).
	var mage := _make_drinker("mage", "mage", 5)
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_giant_strength(
		mage, "potion_gs_item_id", "potion_of_giant_strength", tr)
	check(bool(outcome.get("applied", false)),
		"Giant Strength works on a mage (no class gate per RAW)")


# ---------------------------------------------------------------------------
# apply_invulnerability
# ---------------------------------------------------------------------------

func test_invulnerability_first_quaff_applies_bonus() -> void:
	# Tests at day 0. No prior quaff. Expect +2 AC, +2 saves.
	Timekeeping._on_session_ended()  # reset clock
	var cd := _make_drinker("fighter", "fighter", 5)
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_invulnerability(
		cd, "potion_inv_item_id", "potion_of_invulnerability", tr)
	check(bool(outcome.get("applied", false)), "invulnerability applied")
	check(bool(outcome.get("inverted", true)) == false,
		"first quaff NOT inverted")
	check(int(outcome.get("ac_delta", 0)) == 2, "ac_delta=+2")
	check(int(outcome.get("save_delta", 0)) == 2, "save_delta=+2 (improvement)")
	# Effective AC = base 5 + 2 = 7 (higher AC = better in ACKS ascending).
	check(cd.modifiers.get_effective_value("armor_class", cd.armor_class) == 7,
		"effective AC = 5+2 = 7")
	# Effective save_spells = base 17 - 2 = 15 (lower = better).
	check(cd.get_effective_save("save_spells") == 15,
		"effective save_spells = 17-2 = 15 (lower=better)")


func test_invulnerability_duration_uses_dice_roll() -> void:
	# 2026-06-03 V2: duration_turns from DiceSystem 1d6+6 roll instead of
	# deterministic 10-turn V1 constant. Test forces the roll to 7 (low
	# bound) and verifies the outcome reflects it.
	Timekeeping._on_session_ended()
	GameState.dice_overrides["potion_invulnerability_duration"] = 7
	var cd := _make_drinker("fighter", "fighter", 5)
	var tr := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_invulnerability(
		cd, "inv_low_id", "potion_of_invulnerability", tr)
	check(int(outcome.get("duration_turns", 0)) == 7,
		"forced 1d6+6 = 7 → duration_turns=7; got %d"
			% int(outcome.get("duration_turns", 0)))
	GameState.dice_overrides.erase("potion_invulnerability_duration")


func test_invulnerability_duration_clamps_to_1d6_plus_6_range() -> void:
	# Defensive: a misconfigured dice override outside [7, 12] is clamped
	# to the 1d6+6 range. RAW: "1d6+6 turns" → 7-12 turn range.
	Timekeeping._on_session_ended()
	var cd := _make_drinker("fighter", "fighter", 5)
	var tr := ActiveEffectTracker.new()
	GameState.dice_overrides["potion_invulnerability_duration"] = 999
	var hi_outcome: Dictionary = PotionDurationService.apply_invulnerability(
		cd, "inv_hi_id", "potion_of_invulnerability", tr)
	check(int(hi_outcome.get("duration_turns", 0)) == 12,
		"override 999 clamped to 12 (1d6+6 max); got %d"
			% int(hi_outcome.get("duration_turns", 0)))
	GameState.dice_overrides["potion_invulnerability_duration"] = -3
	# Clear the active potion so a second quaff isn't gated by the first.
	cd.flags.clear_all_from_source_prefix(PotionDurationService.SOURCE_PREFIX)
	cd.modifiers.remove_all_from_source("%sinv_hi_id" % PotionDurationService.SOURCE_PREFIX)
	var lo_outcome: Dictionary = PotionDurationService.apply_invulnerability(
		cd, "inv_lo_id", "potion_of_invulnerability", tr)
	check(int(lo_outcome.get("duration_turns", 0)) == 7,
		"override -3 clamped to 7 (1d6+6 min); got %d"
			% int(lo_outcome.get("duration_turns", 0)))
	GameState.dice_overrides.erase("potion_invulnerability_duration")


func test_invulnerability_duration_respects_override_param() -> void:
	# When the apply_invulnerability call passes duration_override_turns,
	# the override BYPASSES the dice roll entirely. Used by tests that
	# need a specific duration without seeding the dice overrides.
	Timekeeping._on_session_ended()
	var cd := _make_drinker("fighter", "fighter", 5)
	var tr := ActiveEffectTracker.new()
	# Dice override would normally drive the duration — verify the param
	# wins.
	GameState.dice_overrides["potion_invulnerability_duration"] = 12
	var outcome: Dictionary = PotionDurationService.apply_invulnerability(
		cd, "inv_param_id", "potion_of_invulnerability", tr, 20)
	check(int(outcome.get("duration_turns", 0)) == 20,
		"duration_override_turns=20 wins over dice override; got %d"
			% int(outcome.get("duration_turns", 0)))
	GameState.dice_overrides.erase("potion_invulnerability_duration")


func test_invulnerability_second_quaff_within_week_inverts() -> void:
	Timekeeping._on_session_ended()
	var cd := _make_drinker("fighter", "fighter", 5)
	var tr1 := ActiveEffectTracker.new()
	# First quaff at day 0.
	PotionDurationService.apply_invulnerability(
		cd, "first_inv_id", "potion_of_invulnerability", tr1)
	check(int(cd.flags.get_flag_metadata("last_invulnerability_quaff_day").get(
		"day_number", -1)) == 0, "first quaff stamps day 0")
	# Clear has_active_potion so the gate doesn't block (simulate first
	# potion's duration ending; the inversion check is independent of
	# has_active_potion).
	cd.flags.clear_all_from_source_prefix(PotionDurationService.SOURCE_PREFIX)
	# Wipe modifiers from first quaff so we can measure the second cleanly.
	cd.modifiers.remove_all_from_source("%sfirst_inv_id" % PotionDurationService.SOURCE_PREFIX)
	# Advance the clock by 3 days (still within the 7-day window).
	Timekeeping.advance_days(3)
	var tr2 := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_invulnerability(
		cd, "second_inv_id", "potion_of_invulnerability", tr2)
	check(bool(outcome.get("inverted", false)) == true,
		"second quaff within 7 days INVERTS to penalty")
	check(int(outcome.get("ac_delta", 0)) == -2,
		"ac_delta=-2 (inverted penalty)")
	check(int(outcome.get("save_delta", 0)) == -2,
		"save_delta=-2 (inverted penalty)")
	# Effective AC = base 5 + (-2) = 3.
	check(cd.modifiers.get_effective_value("armor_class", cd.armor_class) == 3,
		"inverted effective AC = 5-2 = 3")
	# Effective save_spells = 17 - (-2) = 19 (penalty worsens save).
	check(cd.get_effective_save("save_spells") == 19,
		"inverted effective save_spells = 17+2 = 19 (penalty)")


func test_invulnerability_quaff_after_week_normal() -> void:
	Timekeeping._on_session_ended()
	var cd := _make_drinker("fighter", "fighter", 5)
	var tr1 := ActiveEffectTracker.new()
	PotionDurationService.apply_invulnerability(
		cd, "first_inv_id", "potion_of_invulnerability", tr1)
	cd.flags.clear_all_from_source_prefix(PotionDurationService.SOURCE_PREFIX)
	cd.modifiers.remove_all_from_source("%sfirst_inv_id" % PotionDurationService.SOURCE_PREFIX)
	# Advance 7 days (boundary — RAW: "more than once per week" → strict <7
	# inverts; >=7 is normal).
	Timekeeping.advance_days(7)
	var tr2 := ActiveEffectTracker.new()
	var outcome: Dictionary = PotionDurationService.apply_invulnerability(
		cd, "second_inv_id", "potion_of_invulnerability", tr2)
	check(bool(outcome.get("inverted", true)) == false,
		"second quaff after 7+ days NOT inverted")
	check(int(outcome.get("ac_delta", 0)) == 2,
		"ac_delta back to +2 after the cooldown window")


func test_invulnerability_updates_last_quaff_day_flag() -> void:
	Timekeeping._on_session_ended()
	var cd := _make_drinker("fighter", "fighter", 5)
	var tr := ActiveEffectTracker.new()
	PotionDurationService.apply_invulnerability(
		cd, "inv_item_id", "potion_of_invulnerability", tr)
	check(cd.flags.has_flag("last_invulnerability_quaff_day"),
		"last_invulnerability_quaff_day flag set")
	var meta: Dictionary = cd.flags.get_flag_metadata("last_invulnerability_quaff_day")
	check(int(meta.get("day_number", -1)) == 0,
		"day_number=0 (campaign day 0 at quaff time)")
	# Advance + quaff again; the flag should update to the new day.
	cd.flags.clear_all_from_source_prefix(PotionDurationService.SOURCE_PREFIX)
	cd.modifiers.remove_all_from_source("%sinv_item_id" % PotionDurationService.SOURCE_PREFIX)
	Timekeeping.advance_days(10)
	var tr2 := ActiveEffectTracker.new()
	PotionDurationService.apply_invulnerability(
		cd, "second_inv_id", "potion_of_invulnerability", tr2)
	var meta2: Dictionary = cd.flags.get_flag_metadata("last_invulnerability_quaff_day")
	check(int(meta2.get("day_number", -1)) == 10,
		"day_number updates to 10 after second quaff (was 0); got %d"
			% int(meta2.get("day_number", -1)))


# ---------------------------------------------------------------------------
# apply_sickened (two-potion rule)
# ---------------------------------------------------------------------------

func test_sickened_applies_flag_with_metadata() -> void:
	var cd := _make_drinker("fighter", "fighter", 5)
	# Apply an active potion first.
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	PotionDurationService.apply_combat_level_boost(
		cd, "active_potion_id", "potion_of_heroism", reg, tr)
	check(PotionDurationService.has_active_potion(cd), "setup: active potion")
	# Now apply sickened (simulating a second potion drunk).
	var outcome: Dictionary = PotionDurationService.apply_sickened(
		cd, "new_potion_id", "potion_of_giant_strength", tr)
	check(bool(outcome.get("applied", false)), "sickened applied")
	check(cd.flags.has_flag("is_sickened_by_potion"), "is_sickened flag set")
	var meta: Dictionary = cd.flags.get_flag_metadata("is_sickened_by_potion")
	check(String(meta.get("source_item_id", "")) == "new_potion_id",
		"metadata.source_item_id=new_potion_id (the 2nd potion that triggered)")
	check(String(meta.get("active_potion_item_id", "")) == "active_potion_id",
		"metadata.active_potion_item_id=active_potion_id (the 1st potion)")


func test_sickened_duration_is_three_turns() -> void:
	var cd := _make_drinker("fighter", "fighter", 5)
	var reg := _make_class_registry()
	var tr := ActiveEffectTracker.new()
	PotionDurationService.apply_combat_level_boost(
		cd, "active_potion_id", "potion_of_heroism", reg, tr)
	Timekeeping._on_session_ended()
	var outcome: Dictionary = PotionDurationService.apply_sickened(
		cd, "new_potion_id", "potion_of_giant_strength", tr)
	# expires_at_turn = current_turn (0 after reset) + 3 turns.
	check(int(outcome.get("expires_at_turn", 0)) == 3,
		"sickened expires_at_turn = 0 + 3 = 3; got %d"
			% int(outcome.get("expires_at_turn", 0)))


# ---------------------------------------------------------------------------
# MagicItemActivator integration
# ---------------------------------------------------------------------------

func test_drink_potion_of_heroism_full_flow() -> void:
	_setup_campaign()
	var cd := _make_drinker("fighter", "fighter", 1)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_class, level,
			xp, hp_max, hp_current, attack_throw, save_spells, combat_progression)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [cd.id, cd.campaign_id, cd.name, cd.character_class, cd.level,
			0, cd.hp_max, cd.hp_current, cd.attack_throw, cd.save_spells, cd.combat_progression])
	var pot_id := _add_potion_row("potion_of_heroism")
	var catalog := _make_catalog()
	var resolver = _make_casting_resolver()
	var result: Dictionary = MagicItemActivator.drink_potion(
		pot_id, cd, resolver, catalog)
	check(bool(result.get("success", false)), "heroism quaff succeeds")
	check(bool(result.get("consumed", false)), "heroism bottle consumed")
	var outcome: Dictionary = result.get("effect_outcome", {})
	check(int(outcome.get("extra_levels", 0)) == 3,
		"effect_outcome reports +3 levels")
	# Confirm DB row deletion.
	var still_there: Dictionary = CampaignRepository.get_inventory_item_by_id(pot_id)
	check(still_there.is_empty(), "inventory row removed after quaff")
	_teardown_campaign()


func test_drink_potion_of_giant_strength_full_flow() -> void:
	_setup_campaign()
	var cd := _make_drinker("mage", "mage", 5)  # mage proves no class gate
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_class, level,
			xp, hp_max, hp_current, attack_throw, save_spells, combat_progression)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [cd.id, cd.campaign_id, cd.name, cd.character_class, cd.level,
			0, cd.hp_max, cd.hp_current, cd.attack_throw, cd.save_spells, cd.combat_progression])
	var pot_id := _add_potion_row("potion_of_giant_strength")
	var result: Dictionary = MagicItemActivator.drink_potion(
		pot_id, cd, _make_casting_resolver(), _make_catalog())
	check(bool(result.get("success", false)), "Giant Strength quaff succeeds on mage")
	check(bool(result.get("consumed", false)), "bottle consumed")
	check(cd.flags.has_flag("has_active_potion"), "active_potion flag set")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_active_potion")
	check(String(meta.get("effect_kind", "")) == "giant_strength",
		"effect_kind=giant_strength")
	_teardown_campaign()


func test_drink_potion_of_invulnerability_full_flow() -> void:
	_setup_campaign()
	Timekeeping._on_session_ended()
	var cd := _make_drinker("thief", "thief", 5)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_class, level,
			xp, hp_max, hp_current, attack_throw, save_spells, combat_progression)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [cd.id, cd.campaign_id, cd.name, cd.character_class, cd.level,
			0, cd.hp_max, cd.hp_current, cd.attack_throw, cd.save_spells, cd.combat_progression])
	var pot_id := _add_potion_row("potion_of_invulnerability")
	var result: Dictionary = MagicItemActivator.drink_potion(
		pot_id, cd, _make_casting_resolver(), _make_catalog())
	check(bool(result.get("success", false)),
		"Invulnerability succeeds on thief (no class gate)")
	var outcome: Dictionary = result.get("effect_outcome", {})
	check(bool(outcome.get("inverted", true)) == false,
		"first quaff not inverted")
	check(int(outcome.get("ac_delta", 0)) == 2, "+2 AC")
	_teardown_campaign()


func test_drink_second_potion_triggers_sickened_gate() -> void:
	_setup_campaign()
	var cd := _make_drinker("fighter", "fighter", 5)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_class, level,
			xp, hp_max, hp_current, attack_throw, save_spells, combat_progression)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [cd.id, cd.campaign_id, cd.name, cd.character_class, cd.level,
			0, cd.hp_max, cd.hp_current, cd.attack_throw, cd.save_spells, cd.combat_progression])
	var first_id := _add_potion_row("potion_of_giant_strength")
	var second_id := _add_potion_row("potion_of_heroism")
	var resolver = _make_casting_resolver()
	# First quaff lands normally.
	var r1: Dictionary = MagicItemActivator.drink_potion(
		first_id, cd, resolver, _make_catalog())
	check(bool(r1.get("success", false)), "first quaff lands")
	check(cd.flags.has_flag("has_active_potion"), "first quaff sets active_potion")
	# Second quaff triggers sickened.
	var r2: Dictionary = MagicItemActivator.drink_potion(
		second_id, cd, resolver, _make_catalog())
	check(bool(r2.get("success", false)) == false,
		"second quaff fails (sickened)")
	check(bool(r2.get("sickened_applied", false)),
		"sickened_applied=true in response")
	check(bool(r2.get("consumed", false)),
		"second potion bottle is still consumed (RAW: drinker drank it)")
	check(cd.flags.has_flag("is_sickened_by_potion"),
		"is_sickened_by_potion flag set on drinker")
	# The first potion's effects remain active per RAW (we don't proactively
	# strip them in V1).
	check(cd.flags.has_flag("has_active_potion"),
		"first potion's active_potion flag remains")
	_teardown_campaign()


func test_drink_heroism_consumed_even_when_class_restricted() -> void:
	# RAW: "may use" interpretation per Jedidiah ruling = refuse + notify,
	# but the bottle IS consumed (drinker physically drank it).
	_setup_campaign()
	var cd := _make_drinker("mage", "mage", 5)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_class, level,
			xp, hp_max, hp_current, attack_throw, save_spells, combat_progression)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [cd.id, cd.campaign_id, cd.name, cd.character_class, cd.level,
			0, cd.hp_max, cd.hp_current, cd.attack_throw, cd.save_spells, cd.combat_progression])
	var pot_id := _add_potion_row("potion_of_heroism")
	var result: Dictionary = MagicItemActivator.drink_potion(
		pot_id, cd, _make_casting_resolver(), _make_catalog())
	check(bool(result.get("success", false)) == true,
		"potion 'resolves' (success=true) even when no effect — bottle drunk")
	check(String(result.get("refused_reason", "")) == "class_restricted",
		"refused_reason=class_restricted in result")
	# Bottle gone from DB.
	var still_there: Dictionary = CampaignRepository.get_inventory_item_by_id(pot_id)
	check(still_there.is_empty(), "bottle consumed (DB row deleted)")
	check(not cd.flags.has_flag("has_active_potion"),
		"no active_potion flag set on refused quaff")
	_teardown_campaign()


# ---------------------------------------------------------------------------
# Cleanup-on-tick via ActiveEffectTracker
# ---------------------------------------------------------------------------

## Helper: build a fully-wired CastingResolver with the cleanup_callback
## already registered (so dispatch_cleanup_on_tick effects route through
## _unwind_effect_state on expiry). CastingResolver._init auto-installs its
## _on_tracker_removed_effect as the tracker's cleanup_callback, so passing
## the tracker through is enough. We also install a target_lookup that
## returns the in-memory drinker (so the cleanup callback can find it
## without going through CampaignRepository's CharacterData.from_dict).
func _wire_resolver_with_tracker(tr: ActiveEffectTracker, drinker: CharacterData) -> CastingResolver:
	var resolver: CastingResolver = _make_casting_resolver(tr)
	var lookup := func(tid: String) -> Variant:
		return drinker if tid == drinker.id else null
	resolver.set_default_target_lookup(lookup)
	return resolver


func test_heroism_cleanup_on_day_expire() -> void:
	# Wire a resolver so dispatch_cleanup_on_tick fires the unwind path.
	# IMPORTANT: capture the resolver in a local variable to keep it alive
	# across the tracker tick — otherwise the cleanup_callback Callable
	# (bound to resolver._on_tracker_removed_effect) is invalidated when
	# the resolver is RefCounted-freed. Production code holds the resolver
	# persistently on SessionRunner, so this isn't a production concern.
	# Force the V2 heroism_temp_hp roll to a known value so the temp_hp
	# assertion below is stable (V2 rolls 3d8 for L1 fighter +3 levels).
	GameState.dice_overrides["heroism_temp_hp"] = 12
	Timekeeping._on_session_ended()
	var cd := _make_drinker("fighter", "fighter", 1)
	var tr := ActiveEffectTracker.new()
	var resolver: CastingResolver = _wire_resolver_with_tracker(tr, cd)
	assert(resolver != null)  # silence "unused" warning + lifetime check
	var reg := _make_class_registry()
	PotionDurationService.apply_combat_level_boost(
		cd, "potion_heroism_item_id", "potion_of_heroism", reg, tr)
	check(cd.get_effective_attack_throw() == 8, "attack throw improved to 8 (L1→L4)")
	check(cd.temp_hp == 12, "temp_hp=12 from heroism")
	check(cd.flags.has_flag("has_active_potion"), "flag set")
	# Tick 1 day. Effect should expire + cleanup.
	tr.tick_days(1)
	check(cd.get_effective_attack_throw() == 10,
		"attack_throw modifier swept after day-expire; back to base 10")
	check(cd.get_effective_save("save_spells") == 17,
		"save_spells modifier swept; back to base 17")
	check(cd.temp_hp == 0,
		"temp_hp deducted on cleanup; should be 0 again, got %d" % cd.temp_hp)
	check(not cd.flags.has_flag("has_active_potion"),
		"has_active_potion flag cleared after expire")
	GameState.dice_overrides.erase("heroism_temp_hp")


func test_giant_strength_cleanup_on_turn_expire() -> void:
	Timekeeping._on_session_ended()
	var cd := _make_drinker("fighter", "fighter", 5)
	cd.attack_throw = 8
	var tr := ActiveEffectTracker.new()
	var resolver: CastingResolver = _wire_resolver_with_tracker(tr, cd)
	assert(resolver != null)  # keep resolver alive across tick
	PotionDurationService.apply_giant_strength(
		cd, "potion_gs_item_id", "potion_of_giant_strength", tr)
	check(cd.get_effective_attack_throw() == 3, "set_ceiling clamps to 3 active")
	# Tick 3 turns → expire.
	tr.tick_turns(3)
	check(cd.get_effective_attack_throw() == 8,
		"attack_throw ceiling lifted after expire; back to base 8")
	check(not cd.flags.has_flag("has_active_potion"),
		"active_potion flag cleared after expire")


func test_invulnerability_cleanup_on_turn_expire() -> void:
	Timekeeping._on_session_ended()
	# Force the 2026-06-03 V2 duration dice roll to a known value so the
	# tick_turns call below matches the actual rolled duration. Without
	# the override, apply_invulnerability rolls 1d6+6 (7-13 turns).
	GameState.dice_overrides["potion_invulnerability_duration"] = 10
	var cd := _make_drinker("thief", "thief", 5)
	var tr := ActiveEffectTracker.new()
	var resolver: CastingResolver = _wire_resolver_with_tracker(tr, cd)
	assert(resolver != null)  # keep resolver alive across tick
	var outcome: Dictionary = PotionDurationService.apply_invulnerability(
		cd, "potion_inv_item_id", "potion_of_invulnerability", tr)
	check(int(outcome.get("duration_turns", 0)) == 10,
		"forced dice override → duration_turns=10")
	check(cd.modifiers.get_effective_value("armor_class", cd.armor_class) == 7,
		"AC active during invulnerability")
	tr.tick_turns(int(outcome.get("duration_turns", 0)))
	check(cd.modifiers.get_effective_value("armor_class", cd.armor_class) == 5,
		"AC modifier swept; back to base 5")
	check(cd.get_effective_save("save_spells") == 17,
		"save_spells back to base 17 after expire")
	check(not cd.flags.has_flag("has_active_potion"),
		"active_potion flag cleared")
	# The persistent last_invulnerability_quaff_day flag should NOT be cleared
	# (it's a long-term tracker, not part of the duration unwind).
	check(cd.flags.has_flag("last_invulnerability_quaff_day"),
		"last_invulnerability_quaff_day tracker remains after duration expires")
	GameState.dice_overrides.erase("potion_invulnerability_duration")


# ---------------------------------------------------------------------------
# EntityFlags regression
# ---------------------------------------------------------------------------

func test_new_flags_documented() -> void:
	var path := "res://engine/shared_types/entity_flags.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "entity_flags.gd should be readable")
		return
	var content := f.get_as_text()
	f.close()
	check(content.contains("has_active_potion"),
		"entity_flags.gd documents has_active_potion")
	check(content.contains("is_sickened_by_potion"),
		"entity_flags.gd documents is_sickened_by_potion")
	check(content.contains("last_invulnerability_quaff_day"),
		"entity_flags.gd documents last_invulnerability_quaff_day")
