extends "res://tests/test_suite_base.gd"

## 2026-06-02 — TamperingWithMortalityResolver tests.
##
## Verifies the Axioms ch.6 Tampering with Mortality table mechanics:
## modifier computation (life span / spellcaster power / state of body /
## state of soul), condition_table lookup, alignment-specific side-effect
## table lookup, and integration with RestoreLifeAndLimbResolver.


func run_all_tests() -> void:
	# Modifier computation
	test_modifier_life_span_youth_is_plus_2()
	test_modifier_life_span_adult_is_0()
	test_modifier_life_span_middle_aged_is_minus_5()
	test_modifier_life_span_old_is_minus_10()
	test_modifier_life_span_ancient_is_minus_20()
	test_modifier_spellcaster_power_caster_level_div_2()
	test_modifier_spellcaster_power_temple_bonus()
	test_modifier_state_of_body_minus_10_for_instant_kill_causes()
	test_modifier_state_of_body_0_for_combat_death()
	test_modifier_state_of_soul_uses_wis_modifier()
	test_modifier_state_of_soul_penalizes_days_dead()
	test_modifier_state_of_soul_penalizes_prior_side_effects()
	# Condition table lookup
	test_condition_table_below_minus_6_fails()
	test_condition_table_minus_5_to_0_fails()
	test_condition_table_1_to_5_restored_at_great_cost()
	test_condition_table_6_to_10_lingering()
	test_condition_table_11_to_15_intense()
	test_condition_table_16_to_20_body_made_whole()
	test_condition_table_21_to_25_health_restored()
	test_condition_table_26_plus_instantly_recovered()
	test_condition_table_bed_rest_days()
	# Alignment-specific side-effect lookup
	test_side_effect_lookup_lawful_row_1_band_16to20()
	test_side_effect_lookup_neutral_row_3_band_1to5()
	test_side_effect_lookup_chaotic_row_2_band_minus_6()
	test_side_effect_unknown_alignment_falls_back_to_neutral()
	# Integration with RestoreLifeAndLimbResolver
	test_resolver_records_tampering_outcome()
	test_resolver_passes_age_category_to_tampering()
	test_resolver_passes_alignment_to_tampering()
	# d20 band edges
	test_d20_band_boundaries()
	if not has_failures():
		print("TamperingWithMortality: all tests passed.")


# ---------------------------------------------------------------------------
# Modifier computation tests
# ---------------------------------------------------------------------------

func test_modifier_life_span_youth_is_plus_2() -> void:
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"age_category": "youth"})
	check(int(m["life_span"]) == 2, "youth: life_span = +2, got %d" % int(m["life_span"]))


func test_modifier_life_span_adult_is_0() -> void:
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"age_category": "adult"})
	check(int(m["life_span"]) == 0, "adult: life_span = 0")


func test_modifier_life_span_middle_aged_is_minus_5() -> void:
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"age_category": "middle_aged"})
	check(int(m["life_span"]) == -5, "middle_aged: life_span = -5")


func test_modifier_life_span_old_is_minus_10() -> void:
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"age_category": "old"})
	check(int(m["life_span"]) == -10, "old: life_span = -10")


func test_modifier_life_span_ancient_is_minus_20() -> void:
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"age_category": "ancient"})
	check(int(m["life_span"]) == -20, "ancient: life_span = -20")


func test_modifier_spellcaster_power_caster_level_div_2() -> void:
	var m9: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"caster_level": 9})
	check(int(m9["spellcaster_power"]) == 4,
		"caster L9: spellcaster_power = 9/2 = 4 (floor)")
	var m12: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"caster_level": 12})
	check(int(m12["spellcaster_power"]) == 6,
		"caster L12: spellcaster_power = 6")


func test_modifier_spellcaster_power_temple_bonus() -> void:
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"caster_level": 10, "in_caster_god_temple": true})
	check(int(m["spellcaster_power"]) == 7,
		"caster L10 in temple: 5 + 2 = 7, got %d" % int(m["spellcaster_power"]))


func test_modifier_state_of_body_minus_10_for_instant_kill_causes() -> void:
	for cause in ["lost_head", "cremated", "disintegrated"]:
		var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
			{"death_cause": cause})
		check(int(m["state_of_body"]) == -10,
			"%s: state_of_body = -10" % cause)


func test_modifier_state_of_body_0_for_combat_death() -> void:
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"death_cause": "combat"})
	check(int(m["state_of_body"]) == 0,
		"combat death: state_of_body = 0")


func test_modifier_state_of_soul_uses_wis_modifier() -> void:
	# WIS 16 → +2 modifier; days_dead = 0; side_effects = 0 → +2.
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"wisdom": 16})
	check(int(m["state_of_soul"]) == 2,
		"WIS 16: state_of_soul = +2, got %d" % int(m["state_of_soul"]))


func test_modifier_state_of_soul_penalizes_days_dead() -> void:
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"wisdom": 12, "days_dead": 4})
	check(int(m["state_of_soul"]) == -4,
		"WIS 12, 4 days dead: 0 - 4 = -4, got %d" % int(m["state_of_soul"]))


func test_modifier_state_of_soul_penalizes_prior_side_effects() -> void:
	var m: Dictionary = TamperingWithMortalityResolver.compute_modifiers(
		{"wisdom": 12, "side_effects_already_suffered": 2})
	check(int(m["state_of_soul"]) == -2,
		"WIS 12, 2 prior side effects: -2, got %d" % int(m["state_of_soul"]))


# ---------------------------------------------------------------------------
# Condition table lookup tests
# ---------------------------------------------------------------------------

func test_condition_table_below_minus_6_fails() -> void:
	var row: Dictionary = TamperingWithMortalityResolver.lookup_condition(-10)
	check(String(row["condition"]) == "spell_fails",
		"-10 d20_total: spell_fails")


func test_condition_table_minus_5_to_0_fails() -> void:
	var row: Dictionary = TamperingWithMortalityResolver.lookup_condition(-3)
	check(String(row["condition"]) == "spell_fails",
		"-3 d20_total: spell_fails")


func test_condition_table_1_to_5_restored_at_great_cost() -> void:
	var row: Dictionary = TamperingWithMortalityResolver.lookup_condition(3)
	check(String(row["condition"]) == "restored_at_great_cost",
		"3 d20_total: restored_at_great_cost")
	check(int(row["bed_rest_days"]) == 30,
		"restored_at_great_cost: 1 month (30 days) bed rest")


func test_condition_table_6_to_10_lingering() -> void:
	var row: Dictionary = TamperingWithMortalityResolver.lookup_condition(8)
	check(String(row["condition"]) == "restored_with_lingering_effects",
		"8 d20_total: restored_with_lingering_effects")
	check(String(row["bed_rest_days"]) == "14+1d20",
		"lingering: 14+1d20 days bed rest")


func test_condition_table_11_to_15_intense() -> void:
	var row: Dictionary = TamperingWithMortalityResolver.lookup_condition(13)
	check(String(row["condition"]) == "restoration_intense",
		"13: restoration_intense")
	check(int(row["bed_rest_days"]) == 14,
		"intense: 14 days bed rest")


func test_condition_table_16_to_20_body_made_whole() -> void:
	var row: Dictionary = TamperingWithMortalityResolver.lookup_condition(18)
	check(String(row["condition"]) == "body_made_whole",
		"18: body_made_whole")


func test_condition_table_21_to_25_health_restored() -> void:
	var row: Dictionary = TamperingWithMortalityResolver.lookup_condition(23)
	check(String(row["condition"]) == "health_restored",
		"23: health_restored")
	check(int(row["bed_rest_days"]) == 7,
		"health_restored: 7 days bed rest")


func test_condition_table_26_plus_instantly_recovered() -> void:
	var row: Dictionary = TamperingWithMortalityResolver.lookup_condition(30)
	check(String(row["condition"]) == "instantly_recovered",
		"30: instantly_recovered")
	check(int(row["bed_rest_days"]) == 0,
		"instantly_recovered: 0 days bed rest")


func test_condition_table_bed_rest_days() -> void:
	# Spot-check that the bed-rest field is the expected type at each tier.
	check(int(TamperingWithMortalityResolver.lookup_condition(3)["bed_rest_days"]) == 30, "30d")
	check(int(TamperingWithMortalityResolver.lookup_condition(13)["bed_rest_days"]) == 14, "14d intense")
	check(int(TamperingWithMortalityResolver.lookup_condition(18)["bed_rest_days"]) == 14, "14d whole")
	check(int(TamperingWithMortalityResolver.lookup_condition(23)["bed_rest_days"]) == 7, "7d")


# ---------------------------------------------------------------------------
# Alignment-specific side-effect lookup tests
# ---------------------------------------------------------------------------

func test_side_effect_lookup_lawful_row_1_band_16to20() -> void:
	var s: String = TamperingWithMortalityResolver.lookup_side_effect(
		"lawful", 1, 18)
	check(s.contains("changes sex"),
		"Lawful d6=1 d20=18 → 'changes sex' outcome (RAW), got: %s" % s)


func test_side_effect_lookup_neutral_row_3_band_1to5() -> void:
	var s: String = TamperingWithMortalityResolver.lookup_side_effect(
		"neutral", 3, 3)
	check(s.contains("body of a Neutral creature"),
		"Neutral d6=3 d20=3 → reincarnation table body, got: %s" % s)


func test_side_effect_lookup_chaotic_row_2_band_minus_6() -> void:
	var s: String = TamperingWithMortalityResolver.lookup_side_effect(
		"chaotic", 2, -8)
	check(s.contains("tormenting ghosts") or s.contains("cold darkness"),
		"Chaotic d6=2 d20=-8 → tormenting ghosts outcome, got: %s" % s)


func test_side_effect_unknown_alignment_falls_back_to_neutral() -> void:
	var s_unknown: String = TamperingWithMortalityResolver.lookup_side_effect(
		"alien", 1, 0)
	var s_neutral: String = TamperingWithMortalityResolver.lookup_side_effect(
		"neutral", 1, 0)
	check(s_unknown == s_neutral,
		"unknown alignment falls back to neutral lookup")


# ---------------------------------------------------------------------------
# Integration with RestoreLifeAndLimbResolver
# ---------------------------------------------------------------------------

const RLR := preload(
	"res://engine/subsystems/spells/custom_resolvers/restore_life_and_limb_resolver.gd")


class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r


class _IntegrationTarget extends RefCounted:
	var id: String = ""
	var hp_max: int = 30
	var hp_current: int = 30
	var is_dead: bool = false
	var day_of_death: int = -1
	var death_cause: String = ""
	var age_category: String = "adult"
	var wisdom: int = 12
	var alignment: String = "neutral"
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_effective_save(_key: String) -> int: return 11
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(_t: String) -> bool: return false


func _make_caster(level: int = 9) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "cleric_twm"
	cd.character_class = "cleric"
	cd.combat_progression = "cleric"
	cd.level = level
	cd.hp_max = 24; cd.hp_current = 24
	return cd


func _make_args(caster: CharacterData, target: Variant,
		dice: _FakeDice, current_day: int = 0) -> Dictionary:
	var ctx := CasterContext.from_character_data(
		caster, "combat_grid", "divine", 1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"
	td.target_ids = [target.id]
	return {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {target.id: target},
		"spell_choice": SpellChoice.new("restore_life_and_limb", 5, false, -1),
		"step_payload": {"resolver_args": {
			"dice": dice,
			"current_day": current_day,
		}},
	}


func test_resolver_records_tampering_outcome() -> void:
	var r = RLR.new()
	var caster := _make_caster(9)
	var tgt := _IntegrationTarget.new(); tgt.id = "tgt_twm"
	var dice := _FakeDice.new()
	dice.fixed["spell_tampering_with_mortality_d20"] = 12
	dice.fixed["spell_tampering_with_mortality_d6"] = 4
	var res: Dictionary = r.resolve(_make_args(caster, tgt, dice))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(outcome.has("tampering_outcome"),
		"per_target.tampering_outcome present")
	var twm: Dictionary = outcome["tampering_outcome"]
	check(twm.has("condition"), "tampering_outcome.condition present")
	check(twm.has("bed_rest"), "tampering_outcome.bed_rest present")
	check(twm.has("side_effect"), "tampering_outcome.side_effect present")
	check(twm.has("d20_modifiers"), "tampering_outcome.d20_modifiers present")
	check(twm.has("d20_total"), "tampering_outcome.d20_total present")


func test_resolver_passes_age_category_to_tampering() -> void:
	var r = RLR.new()
	var caster := _make_caster(9)
	var tgt := _IntegrationTarget.new()
	tgt.id = "tgt_old"; tgt.age_category = "old"
	var dice := _FakeDice.new()
	dice.fixed["spell_tampering_with_mortality_d20"] = 15
	dice.fixed["spell_tampering_with_mortality_d6"] = 3
	var res: Dictionary = r.resolve(_make_args(caster, tgt, dice))
	var twm: Dictionary = res["per_target"][tgt.id]["tampering_outcome"]
	check(int(twm["d20_modifiers"]["life_span"]) == -10,
		"old age → life_span -10 reflected in tampering_outcome")


func test_resolver_passes_alignment_to_tampering() -> void:
	var r = RLR.new()
	var caster := _make_caster(9)
	var tgt := _IntegrationTarget.new()
	tgt.id = "tgt_law"; tgt.alignment = "lawful"
	var dice := _FakeDice.new()
	dice.fixed["spell_tampering_with_mortality_d20"] = 18
	dice.fixed["spell_tampering_with_mortality_d6"] = 1
	var res: Dictionary = r.resolve(_make_args(caster, tgt, dice))
	var twm: Dictionary = res["per_target"][tgt.id]["tampering_outcome"]
	check(String(twm["alignment_used"]) == "lawful",
		"alignment_used=lawful")


# ---------------------------------------------------------------------------
# d20 band boundaries
# ---------------------------------------------------------------------------

func test_d20_band_boundaries() -> void:
	# Spot-check that lookup_side_effect uses the right band at each edge.
	# The band labels are: "-6", "-5to0", "1to5", "6to10", "11to15",
	# "16to20", "21to25", "26+".
	var s_neg6: String = TamperingWithMortalityResolver.lookup_side_effect(
		"neutral", 6, -6)
	check(s_neg6.contains("quest required"),
		"d20=-6 falls in band '-6', not '-5to0': %s" % s_neg6)
	var s_zero: String = TamperingWithMortalityResolver.lookup_side_effect(
		"neutral", 6, 0)
	check(s_zero.contains("smell of the wild"),
		"d20=0 falls in band '-5to0': %s" % s_zero)
	var s_one: String = TamperingWithMortalityResolver.lookup_side_effect(
		"neutral", 6, 1)
	check(s_one.contains("demon or imp becomes familiar"),
		"d20=1 falls in band '1to5': %s" % s_one)
	var s_twenty_six: String = TamperingWithMortalityResolver.lookup_side_effect(
		"lawful", 5, 26)
	check(s_twenty_six.contains("prophecy"),
		"d20=26 falls in band '26+': %s" % s_twenty_six)
