class_name ThiefSkillResolver
extends RefCounted

## Resolves grouped thief and adventuring skill throws for the character sheet
## and future roll prompts.

const THIEF_ROLL_TYPE := "thief_skill_throw"
const ADVENTURING_ROLL_TYPE := "adventuring_skill_throw"
const ROLL_TYPE := THIEF_ROLL_TYPE

const THIEF_CLASS_ID := "thief"
const THIEF_GROUP_KEY := "thief_skills"
const ADVENTURING_GROUP_KEY := "adventuring_skills"
const CONDITION_ARMOR_LEATHER_OR_LIGHTER := "armor_leather_or_lighter"
const GENERIC_UNAVAILABLE_REASON := "No class power or proficiency equivalent grants this skill."

const THIEF_SKILL_ORDER: Array[String] = [
	"open_locks",
	"remove_traps",
	"pick_pockets",
	"move_silently",
	"climb_walls",
	"hide_in_shadows",
]

const ADVENTURING_SKILL_ORDER: Array[String] = [
	"force_door",
	"detect_secrets",
	"hear_noise",
	"find_traps",
	"foraging",
	"hunting",
	"fishing",
]

const ALL_SKILL_ORDER: Array[String] = [
	"open_locks",
	"remove_traps",
	"pick_pockets",
	"move_silently",
	"climb_walls",
	"hide_in_shadows",
	"force_door",
	"detect_secrets",
	"hear_noise",
	"find_traps",
	"foraging",
	"hunting",
	"fishing",
]

const SKILL_ORDER := ALL_SKILL_ORDER

const SKILL_DISPLAY_NAMES := {
	"open_locks": "Open Locks",
	"remove_traps": "Remove Traps",
	"pick_pockets": "Pick Pockets",
	"move_silently": "Move Silently",
	"climb_walls": "Climb Walls",
	"hide_in_shadows": "Hide in Shadows",
	"force_door": "Force Door",
	"detect_secrets": "Detect Secrets",
	"hear_noise": "Hear Noise",
	"find_traps": "Find Traps",
	"foraging": "Foraging",
	"hunting": "Hunting",
	"fishing": "Fishing",
}

const SKILL_GROUPS := {
	"open_locks": THIEF_GROUP_KEY,
	"remove_traps": THIEF_GROUP_KEY,
	"pick_pockets": THIEF_GROUP_KEY,
	"move_silently": THIEF_GROUP_KEY,
	"climb_walls": THIEF_GROUP_KEY,
	"hide_in_shadows": THIEF_GROUP_KEY,
	"force_door": ADVENTURING_GROUP_KEY,
	"detect_secrets": ADVENTURING_GROUP_KEY,
	"hear_noise": ADVENTURING_GROUP_KEY,
	"find_traps": ADVENTURING_GROUP_KEY,
	"foraging": ADVENTURING_GROUP_KEY,
	"hunting": ADVENTURING_GROUP_KEY,
	"fishing": ADVENTURING_GROUP_KEY,
}

const SKILL_ROLL_TYPES := {
	"open_locks": THIEF_ROLL_TYPE,
	"remove_traps": THIEF_ROLL_TYPE,
	"pick_pockets": THIEF_ROLL_TYPE,
	"move_silently": THIEF_ROLL_TYPE,
	"climb_walls": THIEF_ROLL_TYPE,
	"hide_in_shadows": THIEF_ROLL_TYPE,
	"force_door": ADVENTURING_ROLL_TYPE,
	"detect_secrets": ADVENTURING_ROLL_TYPE,
	"hear_noise": ADVENTURING_ROLL_TYPE,
	"find_traps": ADVENTURING_ROLL_TYPE,
	"foraging": ADVENTURING_ROLL_TYPE,
	"hunting": ADVENTURING_ROLL_TYPE,
	"fishing": ADVENTURING_ROLL_TYPE,
}

const ADVENTURING_BASE_TARGETS := {
	"force_door": 18,
	"detect_secrets": 18,
	"hear_noise": 18,
	"find_traps": 18,
	"foraging": 18,
	"hunting": 14,
	"fishing": 14,
}

const NATIVE_POWER_IDS := {
	"open_locks": ["open_locks"],
	"remove_traps": ["find_remove_traps"],
	"pick_pockets": ["pick_pockets"],
	"move_silently": ["move_silently"],
	"climb_walls": ["climb_walls"],
	"hide_in_shadows": ["hide_in_shadows"],
	"hear_noise": ["hear_noise"],
	"find_traps": ["find_traps", "find_remove_traps", "stonework_detection"],
	"detect_secrets": ["detect_secret_doors", "stonework_detection"],
}

const THIEF_POWER_FOR_SKILL := {
	"open_locks": "open_locks",
	"find_traps": "find_remove_traps",
	"remove_traps": "find_remove_traps",
	"pick_pockets": "pick_pockets",
	"move_silently": "move_silently",
	"climb_walls": "climb_walls",
	"hide_in_shadows": "hide_in_shadows",
	"hear_noise": "hear_noise",
}

const SKILL_MODIFIER_STATS := {
	"open_locks": "open_lock_modifier",
	"find_traps": "find_trap_modifier",
	"remove_traps": "remove_trap_modifier",
	"move_silently": "move_silently_modifier",
	"hide_in_shadows": "hide_in_shadows_modifier",
	"climb_walls": "climb_walls_modifier",
	"hear_noise": "hear_noise_modifier",
	"force_door": "force_door_modifier",
	"detect_secrets": "detect_secret_doors_modifier",
}

const EQUIVALENT_ACTION_TO_SKILL := {
	"open_locks": "open_locks",
	"find_traps": "find_traps",
	"remove_traps": "remove_traps",
	"pick_pockets": "pick_pockets",
	"move_silently": "move_silently",
	"climb_walls": "climb_walls",
	"hide_in_shadows": "hide_in_shadows",
	"hear_noise": "hear_noise",
}

const DEX_THIEF_SKILLS := {
	"open_locks": true,
	"find_traps": true,
	"remove_traps": true,
	"pick_pockets": true,
	"move_silently": true,
	"climb_walls": true,
	"hide_in_shadows": true,
}

const ENCUMBRANCE_THIEF_SKILLS := {
	"move_silently": true,
	"climb_walls": true,
	"hide_in_shadows": true,
}

const SURVIVAL_BONUS_SKILLS := {
	"foraging": true,
	"hunting": true,
	"fishing": true,
}

const THIEF_BONUS_POWER_IDS := {
	"open_locks": true,
	"find_traps": true,
	"find_remove_traps": true,
	"pick_pockets": true,
	"move_silently": true,
	"climb_walls": true,
	"hide_in_shadows": true,
	"hear_noise": true,
}

var _class_registry: ClassRegistry
var _proficiency_registry: ProficiencyRegistry
var _power_registry: PowerRegistry
var _thief_progressions: Dictionary = {}


func _init(class_registry: ClassRegistry, proficiency_registry: ProficiencyRegistry,
		power_registry: PowerRegistry = null) -> void:
	_class_registry = class_registry
	_proficiency_registry = proficiency_registry
	_power_registry = power_registry
	_cache_thief_progressions()


func get_all_skill_checks(bundle: CharacterBundle, is_hijink: bool = false) -> Array[Dictionary]:
	var context := _build_context(bundle, is_hijink)
	return _build_checks_for_order(context, ALL_SKILL_ORDER)


func get_grouped_skill_checks(bundle: CharacterBundle,
		is_hijink: bool = false) -> Dictionary:
	var context := _build_context(bundle, is_hijink)
	return {
		THIEF_GROUP_KEY: _build_checks_for_order(context, THIEF_SKILL_ORDER),
		ADVENTURING_GROUP_KEY: _build_checks_for_order(context, ADVENTURING_SKILL_ORDER),
	}


func get_skill_check(bundle: CharacterBundle, skill_key: String,
		is_hijink: bool = false) -> Dictionary:
	return _build_skill_check(_build_context(bundle, is_hijink), skill_key)


func player_roll_skill(bundle: CharacterBundle, skill_key: String,
		is_hijink: bool = false, description: String = "") -> RollResult:
	var skill_check := get_skill_check(bundle, skill_key, is_hijink)
	if not bool(skill_check.get("is_available", false)):
		push_error("ThiefSkillResolver.player_roll_skill: skill '%s' is not available" % skill_key)
		return RollResult.new()
	var prompt: String = description if not description.is_empty() else str(
		skill_check.get("display_name", skill_key)
	)
	var roll_type: String = str(skill_check.get("roll_type", THIEF_ROLL_TYPE))
	var result: RollResult = await DiceSystem.player_roll(
		20,
		1,
		int(skill_check.get("total_roll_modifier", 0)),
		roll_type,
		prompt
	)
	result.description = prompt
	return result


func roll_skill_digital(bundle: CharacterBundle, skill_key: String,
		is_hijink: bool = false) -> RollResult:
	var skill_check := get_skill_check(bundle, skill_key, is_hijink)
	if not bool(skill_check.get("is_available", false)):
		push_error("ThiefSkillResolver.roll_skill_digital: skill '%s' is not available" % skill_key)
		return RollResult.new()
	var roll_type: String = str(skill_check.get("roll_type", THIEF_ROLL_TYPE))
	var result: RollResult = DiceSystem.roll_digital(
		20,
		1,
		int(skill_check.get("total_roll_modifier", 0)),
		roll_type
	)
	result.description = str(skill_check.get("display_name", skill_key))
	return result


func _build_checks_for_order(context: Dictionary, order: Array[String]) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for skill_key in order:
		results.append(_build_skill_check(context, skill_key))
	return results


func _build_context(bundle: CharacterBundle, is_hijink: bool) -> Dictionary:
	var character: CharacterData = bundle.character if bundle != null else null
	var aggregated := _get_aggregated_proficiencies(bundle)
	return {
		"bundle": bundle,
		"character": character,
		"aggregated_proficiencies": aggregated,
		"is_hijink": is_hijink,
		"skill_modifiers": _build_skill_modifier_container(character, aggregated),
		"encumbrance_stone": _get_encumbrance_stone(bundle),
	}


func _build_skill_check(context: Dictionary, skill_key: String) -> Dictionary:
	var display_name: String = _display_name_for_skill(skill_key)
	var character: CharacterData = context.get("character")
	if character == null:
		return _make_unavailable_result(display_name, skill_key, "No character data.")

	var aggregated_proficiencies: Array = context.get("aggregated_proficiencies", [])
	var baseline := _select_baseline_source(context.get("bundle"), skill_key, aggregated_proficiencies)
	var strength_modifier := _get_strength_modifier(character, skill_key)
	var dex_modifier := _get_dex_modifier(
		character,
		skill_key,
		baseline,
		bool(context.get("is_hijink", false))
	)
	var encumbrance_modifier := _get_encumbrance_modifier(
		float(context.get("encumbrance_stone", 0.0)),
		skill_key,
		baseline,
		bool(context.get("is_hijink", false))
	)
	var proficiency_modifier := _get_proficiency_modifier_subtotal(
		context.get("skill_modifiers"),
		aggregated_proficiencies,
		skill_key
	)
	# 2026-06-03 (Engine-extension batch): worn-magic bonus on the skill.
	# Elven Cloak / Elven Boots add an `<skill_key>_magical_bonus` add
	# modifier to character.modifiers; we read it here. Other worn items
	# can plug into the same stat key with their own source_id.
	var magical_bonus: int = 0
	if character.modifiers != null:
		var bonus_key: String = "%s_magical_bonus" % skill_key
		magical_bonus = int(character.modifiers.get_effective_value(bonus_key, 0))
	var total_roll_modifier := strength_modifier + dex_modifier + encumbrance_modifier + proficiency_modifier + magical_bonus
	var base_target = baseline.get("base_target", null)
	var is_available: bool = bool(baseline.get("is_available", false))
	var effective_target = null
	var display_target := "NA"
	if is_available and base_target != null:
		effective_target = int(base_target) - total_roll_modifier
		# 2026-06-03: ceiling on the throw target — Elven Cloak / Elven
		# Boots make the wearer "always succeed on 12+" (the throw target
		# is capped at 12). Read via `<skill_key>_ceiling_target` modifier
		# stack. Default 99 = no ceiling. Lower target is better, so the
		# ceiling is a min() clamp.
		if character.modifiers != null:
			var ceiling_key: String = "%s_ceiling_target" % skill_key
			var ceiling: int = int(character.modifiers.get_effective_value(ceiling_key, 99))
			if ceiling < 99:
				effective_target = min(int(effective_target), ceiling)
		display_target = _format_target(int(effective_target))

	var result := {
		"skill_key": skill_key,
		"display_name": display_name,
		"group_key": _group_key_for_skill(skill_key),
		"roll_type": _roll_type_for_skill(skill_key),
		"is_available": is_available,
		"base_target": base_target,
		"effective_target": effective_target,
		"display_target": display_target,
		"total_roll_modifier": total_roll_modifier,
		"source_label": baseline.get("source_label", "None"),
		"source_kind": baseline.get("source_kind", ""),
		"strength_modifier": strength_modifier,
		"dex_modifier": dex_modifier,
		"encumbrance_modifier": encumbrance_modifier,
		"proficiency_modifier_subtotal": proficiency_modifier,
		"equivalent_thief_level": baseline.get("equivalent_thief_level", null),
		"unavailability_reason": baseline.get("unavailability_reason", ""),
		"show_strength_breakdown": skill_key == "force_door",
		"show_dex_breakdown": _should_show_dex_breakdown(skill_key, baseline),
		"show_encumbrance_breakdown": _should_show_encumbrance_breakdown(skill_key, baseline),
		"special_notes": _build_special_notes(aggregated_proficiencies, skill_key),
	}
	result["tooltip_text"] = _build_tooltip_text(result)
	return result


func _make_unavailable_result(display_name: String, skill_key: String,
		reason: String) -> Dictionary:
	var result := {
		"skill_key": skill_key,
		"display_name": display_name,
		"group_key": _group_key_for_skill(skill_key),
		"roll_type": _roll_type_for_skill(skill_key),
		"is_available": false,
		"base_target": null,
		"effective_target": null,
		"display_target": "NA",
		"total_roll_modifier": 0,
		"source_label": "None",
		"source_kind": "",
		"strength_modifier": 0,
		"dex_modifier": 0,
		"encumbrance_modifier": 0,
		"proficiency_modifier_subtotal": 0,
		"equivalent_thief_level": null,
		"unavailability_reason": reason,
		"show_strength_breakdown": skill_key == "force_door",
		"show_dex_breakdown": false,
		"show_encumbrance_breakdown": false,
		"special_notes": [],
	}
	result["tooltip_text"] = _build_tooltip_text(result)
	return result


func _select_baseline_source(bundle: CharacterBundle, skill_key: String,
		aggregated_proficiencies: Array) -> Dictionary:
	var character: CharacterData = bundle.character if bundle != null else null
	var candidates: Array = []
	candidates.append_array(_collect_default_baseline_candidates(character, skill_key))
	candidates.append_array(_collect_native_power_candidates(bundle, skill_key))
	candidates.append_array(_collect_proficiency_equivalent_candidates(
		character,
		aggregated_proficiencies,
		skill_key
	))

	var best_available := {}
	for candidate_var in candidates:
		var candidate: Dictionary = candidate_var
		if not bool(candidate.get("is_available", false)):
			continue
		if best_available.is_empty() or _is_better_candidate(candidate, best_available):
			best_available = candidate
	if not best_available.is_empty():
		return best_available

	var blocked_by_condition := _find_first_candidate_with_reason(
		candidates,
		"Unavailable while wearing armor heavier than leather."
	)
	if not blocked_by_condition.is_empty():
		return blocked_by_condition

	var blocked_by_level := _find_first_candidate_with_reason(
		candidates,
		"Equivalent thief level is below 1."
	)
	if not blocked_by_level.is_empty():
		return blocked_by_level

	if not candidates.is_empty():
		return candidates[0]

	return {
		"is_available": false,
		"base_target": null,
		"source_label": "None",
		"equivalent_thief_level": null,
		"unavailability_reason": GENERIC_UNAVAILABLE_REASON,
		"source_kind": "",
		"uses_thief_bonus_rules": false,
	}


func _collect_default_baseline_candidates(character: CharacterData, skill_key: String) -> Array:
	var results: Array = []
	if character == null or not ADVENTURING_BASE_TARGETS.has(skill_key):
		return results

	results.append(_make_baseline_candidate(
		int(ADVENTURING_BASE_TARGETS.get(skill_key, 0)),
		"Adventuring baseline",
		"adventuring_baseline",
		false
	))

	match skill_key:
		"detect_secrets":
			match character.race:
				"elf":
					results.append(_make_baseline_candidate(
						8,
						"Racial ability: Detect Secret Doors",
						"racial_power",
						false
					))
				"dwarf":
					results.append(_make_baseline_candidate(
						14,
						"Racial ability: Stonework Detection",
						"racial_power",
						false
					))
		"hear_noise":
			match character.race:
				"elf":
					results.append(_make_baseline_candidate(
						14,
						"Racial baseline: Elven Hearing",
						"racial_power",
						false
					))
				"dwarf":
					results.append(_make_baseline_candidate(
						14,
						"Racial baseline: Dwarven Hearing",
						"racial_power",
						false
					))
		"find_traps":
			if character.race == "dwarf":
				results.append(_make_baseline_candidate(
					14,
					"Racial ability: Stonework Detection",
					"racial_power",
					false
				))

	return results


func _make_baseline_candidate(base_target: int, source_label: String,
		source_kind: String, uses_thief_bonus_rules: bool) -> Dictionary:
	return {
		"is_available": true,
		"base_target": base_target,
		"source_label": source_label,
		"equivalent_thief_level": null,
		"unavailability_reason": "",
		"source_kind": source_kind,
		"uses_thief_bonus_rules": uses_thief_bonus_rules,
	}


func _collect_native_power_candidates(bundle: CharacterBundle, skill_key: String) -> Array:
	var results: Array = []
	if bundle == null or bundle.character == null:
		return results
	var native_power_ids: Array = NATIVE_POWER_IDS.get(skill_key, [])
	for power_var in bundle.powers:
		var power_row: Dictionary = power_var
		var power_id: String = str(power_row.get("power_id", ""))
		if not native_power_ids.has(power_id):
			continue
		var unlock_level: int = int(power_row.get("unlock_level", 1))
		if unlock_level > bundle.character.level:
			continue
		var base_target = _extract_throw_target_for_skill(
			power_row,
			power_id,
			skill_key,
			bundle.character.level
		)
		var condition_result := _evaluate_conditions(
			bundle.inventory,
			_parse_json_array(power_row.get("conditions", []))
		)
		results.append({
			"is_available": bool(condition_result.get("allowed", true)),
			"base_target": base_target,
			"source_label": "Class power: %s" % _display_name_for_power(power_id),
			"equivalent_thief_level": null,
			"unavailability_reason": condition_result.get("reason", ""),
			"source_kind": "class_power",
			"uses_thief_bonus_rules": bool(THIEF_BONUS_POWER_IDS.get(power_id, false)),
		})
	return results


func _collect_proficiency_equivalent_candidates(character: CharacterData, aggregated_proficiencies: Array,
		skill_key: String) -> Array:
	var results: Array = []
	if character == null or _proficiency_registry == null:
		return results
	if not THIEF_POWER_FOR_SKILL.has(skill_key):
		return results

	for prof_var in aggregated_proficiencies:
		var prof: Dictionary = prof_var
		var effects := _get_proficiency_effects(prof)
		for enabler_var in effects.get("enablers", []):
			var enabler: Dictionary = enabler_var
			if str(enabler.get("equivalent_class", "")) != THIEF_CLASS_ID:
				continue
			var mapped_skill: String = EQUIVALENT_ACTION_TO_SKILL.get(str(enabler.get("action", "")), "")
			if mapped_skill != skill_key:
				continue
			var equivalent_level := _resolve_equivalent_level(
				character.level,
				str(enabler.get("equivalent_level", ""))
			)
			var source_label := "Proficiency: %s" % _display_name_for_proficiency(prof)
			if equivalent_level < 1:
				results.append({
					"is_available": false,
					"base_target": null,
					"source_label": source_label,
					"equivalent_thief_level": equivalent_level,
					"unavailability_reason": "Equivalent thief level is below 1.",
					"source_kind": "proficiency_equivalent",
					"uses_thief_bonus_rules": true,
				})
				continue
			var base_target = _get_thief_base_target(skill_key, equivalent_level)
			results.append({
				"is_available": base_target != null,
				"base_target": base_target,
				"source_label": source_label,
				"equivalent_thief_level": equivalent_level,
				"unavailability_reason": "" if base_target != null else GENERIC_UNAVAILABLE_REASON,
				"source_kind": "proficiency_equivalent",
				"uses_thief_bonus_rules": true,
			})
	return results


func _find_first_candidate_with_reason(candidates: Array, reason: String) -> Dictionary:
	for candidate_var in candidates:
		var candidate: Dictionary = candidate_var
		if candidate.get("unavailability_reason", "") == reason:
			return candidate
	return {}


func _is_better_candidate(candidate: Dictionary, current_best: Dictionary) -> bool:
	var candidate_target = candidate.get("base_target", null)
	var current_target = current_best.get("base_target", null)
	if current_target == null:
		return true
	if candidate_target == null:
		return false
	if int(candidate_target) != int(current_target):
		return int(candidate_target) < int(current_target)
	return _source_priority(candidate) < _source_priority(current_best)


func _source_priority(candidate: Dictionary) -> int:
	match str(candidate.get("source_kind", "")):
		"class_power":
			return 0
		"proficiency_equivalent":
			return 1
		"racial_power":
			return 2
		"adventuring_baseline":
			return 3
		_:
			return 4


func _get_proficiency_effects(prof: Dictionary) -> Dictionary:
	if _proficiency_registry == null:
		return {}
	var key: String = str(prof.get("proficiency_key", ""))
	var rank: int = int(prof.get("rank", 1))
	var specialization: String = str(prof.get("specialization", ""))
	if key.is_empty() or not _proficiency_registry.has_proficiency(key):
		return {}
	if _proficiency_registry.is_specialization(key):
		var spec_effects := _proficiency_registry.get_effects_for_specialization(key, specialization)
		if not spec_effects.is_empty():
			return spec_effects
	return _proficiency_registry.get_effects_for_rank(key, rank)


func _build_skill_modifier_container(character: CharacterData,
		aggregated_proficiencies: Array) -> ModifierContainer:
	var container := ModifierContainer.new()
	if character == null or _proficiency_registry == null:
		return container

	for prof_var in aggregated_proficiencies:
		var prof: Dictionary = prof_var
		var key: String = str(prof.get("proficiency_key", ""))
		if key.is_empty() or not _proficiency_registry.has_proficiency(key):
			continue
		var effects := _get_proficiency_effects(prof)
		var modifiers: Array = effects.get("modifiers", [])
		var selections: int = int(prof.get("selections_count", 1))
		var source_id := _make_proficiency_source_id(prof)
		for mod_var in modifiers:
			var mod_def: Dictionary = mod_var
			if mod_def.has("condition"):
				continue
			var stat: String = str(mod_def.get("stat", ""))
			if stat not in SKILL_MODIFIER_STATS.values():
				continue
			var value: int = int(mod_def.get("value", 0))
			if _proficiency_registry.get_selection_rule(key) == "stacking" and selections > 1:
				value *= selections
			if _proficiency_registry.has_level_scaling(key):
				var scaled := _proficiency_registry.get_scaled_bonus(key, character.level)
				if scaled != 0:
					value = scaled if value >= 0 else -scaled
			container.add_modifier(stat, {
				"source_id": source_id,
				"stat": stat,
				"operation": str(mod_def.get("operation", "add")),
				"value": value,
				"stacking_group": str(mod_def.get("stacking_group", "")),
			})
	return container


func _make_proficiency_source_id(prof: Dictionary) -> String:
	var key: String = str(prof.get("proficiency_key", ""))
	var specialization: String = str(prof.get("specialization", ""))
	if specialization.is_empty():
		return "proficiency:%s" % key
	return "proficiency:%s:%s" % [key, specialization]


func _get_proficiency_modifier_subtotal(container: ModifierContainer,
		aggregated_proficiencies: Array, skill_key: String) -> int:
	var total := 0
	if container != null:
		var stat_key: String = SKILL_MODIFIER_STATS.get(skill_key, "")
		if not stat_key.is_empty():
			total += int(container.get_effective_value(stat_key, 0))
	if SURVIVAL_BONUS_SKILLS.has(skill_key) and _has_proficiency(aggregated_proficiencies, "survival"):
		total += 4
	return total


func _get_strength_modifier(character: CharacterData, skill_key: String) -> int:
	if character == null or skill_key != "force_door":
		return 0
	return CharacterData.ability_modifier(character.get_effective_ability_score("strength")) * 4


func _get_dex_modifier(character: CharacterData, skill_key: String, baseline: Dictionary,
		is_hijink: bool) -> int:
	if character == null or is_hijink:
		return 0
	if not bool(baseline.get("uses_thief_bonus_rules", false)):
		return 0
	if not DEX_THIEF_SKILLS.has(skill_key):
		return 0
	return CharacterData.ability_modifier(character.get_effective_ability_score("dexterity"))


func _get_encumbrance_modifier(encumbrance_stone: float, skill_key: String,
		baseline: Dictionary, is_hijink: bool) -> int:
	if is_hijink or not bool(baseline.get("uses_thief_bonus_rules", false)):
		return 0
	if not ENCUMBRANCE_THIEF_SKILLS.has(skill_key):
		return 0
	if encumbrance_stone <= 2.0:
		return 4
	if encumbrance_stone <= 5.0:
		return 2
	return 0


func _get_encumbrance_stone(bundle: CharacterBundle) -> float:
	if bundle == null:
		return 0.0
	return float(EncumbranceCalculator.calculate_encumbrance(bundle.inventory).get("total_stone", 0.0))


func _build_special_notes(aggregated_proficiencies: Array, skill_key: String) -> Array[String]:
	var notes: Array[String] = []
	if skill_key == "foraging" and _has_proficiency(aggregated_proficiencies, "survival"):
		notes.append("Survival also grants automatic self-foraging in fairly fertile areas.")
	return notes


func _has_proficiency(aggregated_proficiencies: Array, proficiency_key: String) -> bool:
	for prof_var in aggregated_proficiencies:
		var prof: Dictionary = prof_var
		if str(prof.get("proficiency_key", "")) == proficiency_key:
			return true
	return false


func _should_show_dex_breakdown(skill_key: String, baseline: Dictionary) -> bool:
	return bool(baseline.get("uses_thief_bonus_rules", false)) and DEX_THIEF_SKILLS.has(skill_key)


func _should_show_encumbrance_breakdown(skill_key: String, baseline: Dictionary) -> bool:
	return bool(baseline.get("uses_thief_bonus_rules", false)) and ENCUMBRANCE_THIEF_SKILLS.has(skill_key)


func _evaluate_conditions(inventory: Array, conditions: Array) -> Dictionary:
	for condition_var in conditions:
		var condition: String = str(condition_var)
		match condition:
			CONDITION_ARMOR_LEATHER_OR_LIGHTER:
				if not _is_wearing_leather_or_lighter(inventory):
					return {
						"allowed": false,
						"reason": "Unavailable while wearing armor heavier than leather.",
					}
	return {"allowed": true, "reason": ""}


func _is_wearing_leather_or_lighter(inventory: Array) -> bool:
	var body_armor_bonus := 0
	for item_var in inventory:
		var item = item_var
		if not _is_equipped(item):
			continue
		if _item_category(item) != "armor":
			continue
		if _item_slot(item) != "body":
			continue
		body_armor_bonus = maxi(body_armor_bonus, _armor_ac_bonus(item))
	return body_armor_bonus <= 2


func _is_equipped(item) -> bool:
	if item is InventoryItem:
		return item.is_equipped
	return int(item.get("is_equipped", 0)) == 1


func _item_category(item) -> String:
	if item is InventoryItem:
		return item.item_category
	return str(item.get("item_category", ""))


func _item_slot(item) -> String:
	if item is InventoryItem:
		return item.slot
	return str(item.get("slot", ""))


func _armor_ac_bonus(item) -> int:
	if item is InventoryItem:
		return item.armor_ac_bonus
	return int(item.get("armor_ac_bonus", 0))


func _resolve_equivalent_level(character_level: int, equivalent_level: String) -> int:
	match equivalent_level:
		"character_level":
			return character_level
		"half_character_level":
			return int(floor(character_level / 2.0))
		_:
			return int(equivalent_level) if equivalent_level.is_valid_int() else 0


func _get_thief_base_target(skill_key: String, equivalent_level: int):
	var power_id: String = THIEF_POWER_FOR_SKILL.get(skill_key, "")
	if power_id.is_empty():
		return null
	var progression: Dictionary = _thief_progressions.get(power_id, {})
	if progression.is_empty():
		return null
	return _lookup_progression_target(progression, equivalent_level)


func _cache_thief_progressions() -> void:
	_thief_progressions.clear()
	if _class_registry == null or not _class_registry.has_class(THIEF_CLASS_ID):
		return
	for power_var in _class_registry.get_class_powers(THIEF_CLASS_ID):
		var power: Dictionary = power_var
		var power_id: String = str(power.get("power_id", ""))
		if power_id.is_empty():
			continue
		_thief_progressions[power_id] = _extract_progression_dict(power)


func _extract_throw_target_for_skill(power_row: Dictionary, power_id: String, skill_key: String, level: int):
	var target = _extract_throw_target(power_row, level)
	if target != null:
		return target
	match power_id:
		"detect_secret_doors":
			if skill_key == "detect_secrets":
				return 8
		"stonework_detection":
			if skill_key == "detect_secrets" or skill_key == "find_traps":
				return 14
	return null


func _extract_throw_target(power_row: Dictionary, level: int):
	var progression := _extract_progression_dict(power_row)
	if not progression.is_empty():
		return _lookup_progression_target(progression, level)
	if power_row.has("throw_target"):
		return int(power_row.get("throw_target", 0))
	return null


func _extract_progression_dict(power_row: Dictionary) -> Dictionary:
	if power_row.has("progression") and power_row.get("progression") is Dictionary:
		return (power_row.get("progression") as Dictionary).duplicate(true)
	if power_row.has("progression_data"):
		return _parse_json_dictionary(power_row.get("progression_data", "{}"))
	return {}


func _lookup_progression_target(progression: Dictionary, level: int):
	if progression.is_empty():
		return null
	var levels: Array[int] = []
	for level_key_var in progression.keys():
		var level_key := str(level_key_var)
		if level_key.is_valid_int():
			levels.append(int(level_key))
	if levels.is_empty():
		return null
	levels.sort()
	var selected_level := levels[0]
	for candidate_level in levels:
		if level >= candidate_level:
			selected_level = candidate_level
	return int(progression.get(str(selected_level), progression.get(selected_level, 0)))


func _get_aggregated_proficiencies(bundle: CharacterBundle) -> Array:
	if bundle == null:
		return []
	if bundle.character != null and not bundle.character.proficiencies.is_empty():
		return bundle.character.get_aggregated_proficiencies()
	return CharacterData.aggregate_proficiencies(bundle.proficiencies)


func _parse_json_dictionary(raw_value) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	if raw_value is String:
		var text: String = raw_value.strip_edges()
		if text.is_empty():
			return {}
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			return parsed
	return {}


func _parse_json_array(raw_value) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	if raw_value is String:
		var text: String = raw_value.strip_edges()
		if text.is_empty():
			return []
		var parsed = JSON.parse_string(text)
		if parsed is Array:
			return parsed
	return []


func _group_key_for_skill(skill_key: String) -> String:
	return str(SKILL_GROUPS.get(skill_key, THIEF_GROUP_KEY))


func _roll_type_for_skill(skill_key: String) -> String:
	return str(SKILL_ROLL_TYPES.get(skill_key, THIEF_ROLL_TYPE))


func _display_name_for_skill(skill_key: String) -> String:
	return str(SKILL_DISPLAY_NAMES.get(skill_key, skill_key.replace("_", " ").capitalize()))


func _display_name_for_power(power_id: String) -> String:
	if _power_registry != null and _power_registry.has_power(power_id):
		var power_def := _power_registry.get_power(power_id)
		return str(power_def.get("power_name", power_def.get("name", _display_name_for_skill(power_id))))
	return _display_name_for_skill(power_id)


func _display_name_for_proficiency(prof: Dictionary) -> String:
	var key: String = str(prof.get("proficiency_key", ""))
	var specialization: String = str(prof.get("specialization", ""))
	var display_name := key.replace("_", " ").capitalize()
	if _proficiency_registry != null and _proficiency_registry.has_proficiency(key):
		var prof_def := _proficiency_registry.get_proficiency(key)
		display_name = str(prof_def.get("name", display_name))
		if not specialization.is_empty():
			display_name += " [%s]" % _proficiency_registry.get_specialization_display_name(
				key,
				specialization
			)
	elif not specialization.is_empty():
		display_name += " [%s]" % specialization.replace("_", " ").capitalize()
	return display_name


func _build_tooltip_text(skill_check: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Source: %s" % str(skill_check.get("source_label", "None")))
	if skill_check.get("base_target", null) != null:
		lines.append("Base target: %s" % _format_target(int(skill_check.get("base_target", 0))))
	var equivalent_level = skill_check.get("equivalent_thief_level", null)
	if equivalent_level != null:
		lines.append("Equivalent thief level: %d" % int(equivalent_level))
	if bool(skill_check.get("show_strength_breakdown", false)):
		lines.append("Strength modifier: %s" % _format_modifier(
			int(skill_check.get("strength_modifier", 0))
		))
	if bool(skill_check.get("show_dex_breakdown", false)):
		lines.append("DEX modifier: %s" % _format_modifier(int(skill_check.get("dex_modifier", 0))))
	if bool(skill_check.get("show_encumbrance_breakdown", false)):
		lines.append("Encumbrance modifier: %s" % _format_modifier(
			int(skill_check.get("encumbrance_modifier", 0))
		))
	lines.append("Proficiency modifier subtotal: %s" % _format_modifier(
		int(skill_check.get("proficiency_modifier_subtotal", 0))
	))
	for note_var in skill_check.get("special_notes", []):
		lines.append("Note: %s" % str(note_var))
	if bool(skill_check.get("is_available", false)):
		lines.append("Effective target: %s" % str(skill_check.get("display_target", "NA")))
	else:
		lines.append("Unavailable: %s" % str(
			skill_check.get("unavailability_reason", GENERIC_UNAVAILABLE_REASON)
		))
	return "\n".join(lines)


func _format_target(target: int) -> String:
	return "%d+" % target


func _format_modifier(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)
