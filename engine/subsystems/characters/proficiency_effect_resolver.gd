class_name ProficiencyEffectResolver
extends RefCounted

## Applies permanent proficiency effects to a CharacterData's ModifierContainer and EntityFlags.
##
## Proficiency effects are PERMANENT (not tracked by ActiveEffectTracker).
## Conditional modifiers (those with a "condition" key) are SKIPPED — the consuming
## system (combat, exploration, etc.) is responsible for evaluating them at runtime.
##
## Call apply_proficiency_effects() on every character load and after any proficiency change.
## The operation is idempotent: it clears all proficiency-source modifiers/flags first, then
## rebuilds from the character's current proficiencies array.
##
## Source ID format:
##   Non-specialization:  "proficiency:divine_blessing"
##   Specialization:      "proficiency:fighting_style:missile"
##
## Usage:
##   var resolver := ProficiencyEffectResolver.new(proficiency_registry)
##   resolver.apply_proficiency_effects(character)

var _registry: ProficiencyRegistry


func _init(registry: ProficiencyRegistry) -> void:
	_registry = registry


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func apply_proficiency_effects(character: CharacterData) -> void:
	## Clears all proficiency-sourced modifiers and flags, then reapplies from
	## the character's current proficiencies array.
	_clear_proficiency_effects(character)
	for prof in character.proficiencies:
		_apply_single_proficiency(character, prof)


func get_unconditional_modifiers(key: String, rank: int, selections: int, level: int) -> Array[Dictionary]:
	## Returns the modifier dicts that would be applied to a character (for UI preview).
	## Conditional modifiers are excluded.
	if not _registry.has_proficiency(key):
		return []
	var effects := _registry.get_effects_for_rank(key, rank)
	return _filter_unconditional_modifiers(effects, key, selections, level)


# ---------------------------------------------------------------------------
# Internal: clear
# ---------------------------------------------------------------------------

func _clear_proficiency_effects(character: CharacterData) -> void:
	## Removes all modifiers and flags whose source_id starts with "proficiency:".
	## Uses prefix-based removal so this works correctly even when character.proficiencies
	## has already been cleared before this method is called.
	character.modifiers.remove_all_with_source_prefix("proficiency:")
	character.flags.clear_all_from_source_prefix("proficiency:")


# ---------------------------------------------------------------------------
# Internal: apply one proficiency
# ---------------------------------------------------------------------------

func _apply_single_proficiency(character: CharacterData, prof: Dictionary) -> void:
	var key: String = prof.get("proficiency_key", "")
	if key.is_empty():
		return
	if not _registry.has_proficiency(key):
		# Unknown proficiency — silently skip rather than crash
		return

	var rank: int = prof.get("rank", 1)
	var selections: int = prof.get("selections_count", 1)
	var specialization: String = prof.get("specialization", "")
	var source_id := _make_source_id(prof)

	var effects: Dictionary
	if _registry.is_specialization(key):
		effects = _registry.get_effects_for_specialization(key, specialization)
		if effects.is_empty():
			# Fallback: specialization proficiencies without per-specialization effects
			# (e.g., Naturalism, Collegiate Wizardry) use rank-based or top-level effects.
			effects = _registry.get_effects_for_rank(key, rank)
	else:
		effects = _registry.get_effects_for_rank(key, rank)

	if effects.is_empty():
		return  # Stub entry — no effects defined yet

	# Apply modifiers (unconditional only)
	var modifiers: Array = effects.get("modifiers", [])
	for mod_def in modifiers:
		if mod_def.has("condition"):
			continue  # Conditional modifier — skip; consuming system evaluates at runtime
		var value: int = mod_def.get("value", 0)
		# Stacking proficiencies multiply value by selections_count
		var rule := _registry.get_selection_rule(key)
		if rule == "stacking" and selections > 1:
			value = value * selections
		# Level-scaled proficiencies override the base value from the catalog
		if _registry.has_level_scaling(key):
			var scaled := _registry.get_scaled_bonus(key, character.level)
			if scaled != 0:
				value = scaled if value > 0 else -scaled
		var modifier := {
			"source_id": source_id,
			"stat": mod_def.get("stat", ""),
			"operation": mod_def.get("operation", "add"),
			"value": value,
			"stacking_group": mod_def.get("stacking_group", ""),
		}
		character.modifiers.add_modifier(mod_def.get("stat", ""), modifier)

	# Apply flags (always unconditional)
	var flag_list: Array = effects.get("flags", [])
	for flag_key in flag_list:
		character.flags.set_flag(flag_key, source_id)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_source_id(prof: Dictionary) -> String:
	var key: String = prof.get("proficiency_key", "")
	var specialization: String = prof.get("specialization", "")
	if not specialization.is_empty():
		return "proficiency:%s:%s" % [key, specialization]
	return "proficiency:%s" % key


func _filter_unconditional_modifiers(effects: Dictionary, _key: String, selections: int, _level: int) -> Array[Dictionary]:
	## Returns modifier dicts from effects that have no "condition" key.
	var result: Array[Dictionary] = []
	for mod_def in effects.get("modifiers", []):
		if not mod_def.has("condition"):
			var m: Dictionary = mod_def.duplicate()
			if selections > 1:
				m["value"] = m.get("value", 0) * selections
			result.append(m)
	return result
