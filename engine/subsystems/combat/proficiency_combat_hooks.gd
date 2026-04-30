class_name ProficiencyCombatHooks
extends RefCounted

## Catalog-driven evaluation of CONDITIONAL proficiency effects at runtime.
##
## ProficiencyEffectResolver applies UNCONDITIONAL modifiers to the
## character's modifier container at character-load time and explicitly
## skips anything carrying a "condition" key (see proficiency_effect_resolver.gd:95).
## This module is the consumer that the catalog comment refers to: it
## evaluates the conditional bits at combat time.
##
## Layered design:
## - data/proficiencies/proficiency_catalog.json — declares effects
##   (modifiers / flags / enablers) with optional condition strings
## - ProficiencyEffectResolver — applies unconditional bits at load time
## - ProficiencyCombatHooks (this file) — applies conditional bits at
##   query time; single canonical place where catalog "requires:" strings
##   resolve into runtime predicates
##
## Adding a new proficiency that uses an existing condition is a pure-data
## change to the catalog. Adding a new condition adds one match arm to
## _evaluate_condition() below.

const _LOG_TAG := "ProficiencyCombatHooks"

static var _registry_cache: ProficiencyRegistry = null


static func _registry() -> ProficiencyRegistry:
	if _registry_cache == null:
		_registry_cache = ProficiencyRegistry.new()
	return _registry_cache


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Sums conditional proficiency modifiers matching [param stat_key].
##
## Iterates the combatant's aggregated proficiencies, looks up each
## proficiency's effects (per specialization or per rank), and for every
## modifier that has a "condition" block whose predicate evaluates true
## against [param context], adds the modifier's value to a running total.
## Unconditional modifiers are skipped here because ProficiencyEffectResolver
## already folded them into the modifier container at character-load time.
##
## Recognized [param stat_key] values:
##   "attack_throw"        — +/- to attack throw target number
##   "damage_bonus"        — flat damage bonus
##   "armor_class"         — flat AC bonus
##   "initiative_modifier" — flat initiative bonus
##
## Recognized [param context] keys (caller-dependent):
##   "phase":         "melee_attack" | "ranged_attack" | "ac" | "initiative"
##   "weapon_data":   Dictionary (the equipped weapon row), when relevant
##
## Returns the summed integer bonus (positive or negative).
static func aggregate_modifier(combatant, stat_key: String, context: Dictionary) -> int:
	if combatant == null or not combatant.is_character or combatant._character == null:
		return 0
	var character = combatant._character
	var profs: Array = character.get_aggregated_proficiencies()
	var total: int = 0
	for prof in profs:
		var key: String = prof.get("proficiency_key", "")
		if key.is_empty():
			continue
		var effects := _get_effects(prof)
		if effects.is_empty():
			continue
		for mod_def in effects.get("modifiers", []):
			if mod_def.get("stat", "") != stat_key:
				continue
			if not mod_def.has("condition"):
				continue  # unconditional; already in modifier container
			if not _evaluate_condition(combatant, mod_def["condition"], context):
				continue
			var op: String = mod_def.get("operation", "add")
			if op != "add":
				push_warning(
					"%s: unsupported operation '%s' on %s.%s" % [
						_LOG_TAG, op, key, stat_key])
				continue
			total += _resolved_value(mod_def, prof, character.level)
	return total


## Returns true if any of [param combatant]'s active proficiencies grants
## an enabler whose "action" matches [param action] AND whose context
## fields (e.g. weapon_category) match the supplied [param context].
##
## Recognized [param action] values:
##   "natural_20_double_damage" — Weapon Focus: doubles damage on raw nat-20
##                                with weapons in the matching family.
##                                Required context: "weapon_category".
##
## Adding a new enabler action: extend _enabler_matches_context() if the
## new action introduces additional context fields beyond weapon_category.
static func has_active_enabler(combatant, action: String, context: Dictionary) -> bool:
	if combatant == null or not combatant.is_character or combatant._character == null:
		return false
	var character = combatant._character
	var profs: Array = character.get_aggregated_proficiencies()
	for prof in profs:
		var effects := _get_effects(prof)
		if effects.is_empty():
			continue
		for enabler in effects.get("enablers", []):
			if enabler.get("action", "") != action:
				continue
			if _enabler_matches_context(enabler, context):
				return true
	return false


# ---------------------------------------------------------------------------
# Internal — effect lookup
# ---------------------------------------------------------------------------

static func _get_effects(prof: Dictionary) -> Dictionary:
	var key: String = prof.get("proficiency_key", "")
	var reg := _registry()
	if not reg.has_proficiency(key):
		return {}
	var spec: String = prof.get("specialization", "")
	var rank: int = int(prof.get("rank", 1))
	var effects: Dictionary
	if reg.is_specialization(key):
		effects = reg.get_effects_for_specialization(key, spec)
		if effects.is_empty():
			effects = reg.get_effects_for_rank(key, rank)
	else:
		effects = reg.get_effects_for_rank(key, rank)
	return effects


## Resolves the integer value of a modifier, applying selection-stacking
## and level-scaling rules consistently with ProficiencyEffectResolver.
static func _resolved_value(mod_def: Dictionary, prof: Dictionary, character_level: int) -> int:
	var key: String = prof.get("proficiency_key", "")
	var value: int = int(mod_def.get("value", 0))
	var rule := _registry().get_selection_rule(key)
	var selections: int = int(prof.get("selections_count", 1))
	if rule == "stacking" and selections > 1:
		value = value * selections
	if _registry().has_level_scaling(key):
		var scaled := _registry().get_scaled_bonus(key, character_level)
		if scaled != 0:
			# Preserve sign convention from the catalog's static value.
			value = scaled if value > 0 else -scaled
	return value


# ---------------------------------------------------------------------------
# Internal — enabler matching
# ---------------------------------------------------------------------------

static func _enabler_matches_context(enabler: Dictionary, context: Dictionary) -> bool:
	if enabler.has("weapon_category"):
		if String(enabler["weapon_category"]) != String(context.get("weapon_category", "")):
			return false
	return true


# ---------------------------------------------------------------------------
# Internal — condition predicates
# ---------------------------------------------------------------------------

## Maps a catalog "requires:" string to a runtime predicate against the
## combatant + caller-supplied context. Single source of truth for the
## condition vocabulary.
static func _evaluate_condition(combatant, condition: Dictionary, context: Dictionary) -> bool:
	var requires: String = String(condition.get("requires", ""))
	if requires.is_empty():
		return true
	match requires:
		"shield_equipped":
			return combatant.has_shield_equipped()
		"pole_weapon_equipped":
			return combatant.is_wielding_pole_weapon()
		"two_handed_weapon":
			return combatant.is_wielding_two_handed()
		"single_weapon_style":
			return context.get("phase", "") == "melee_attack" \
				and combatant.is_wielding_one_handed_melee() \
				and not combatant.is_dual_wielding() \
				and not combatant.has_shield_equipped()
		"two_weapon_style":
			return context.get("phase", "") == "melee_attack" \
				and combatant.is_dual_wielding()
		"missile_style_active":
			return context.get("phase", "") == "ranged_attack"
		"armor_leather_or_lighter_and_unencumbered":
			return combatant.get_equipped_body_armor_ac_bonus() <= 2 \
				and combatant.can_move_freely()
		"not_casting_spell":
			# Combat Reflexes excludes spell-casting initiative. Spell-cast
			# tracking is not yet wired round-by-round; the helper returns
			# false today, so the bonus always applies. When per-round
			# casting declarations land, only the helper changes.
			return not combatant.is_casting_spell_this_round()
		"target_is_kin":
			# Kin-Slaying. Context must supply "target" Combatant.
			var target = context.get("target", null)
			return target != null and CreatureFamily.is_kin(target)
		"target_is_goblinoid":
			# Goblin-Slaying. Context must supply "target" Combatant.
			var target_g = context.get("target", null)
			return target_g != null and CreatureFamily.is_goblinoid(target_g)
		"firing_into_melee":
			# Precise Shooting catalog modifier; the resolver currently
			# computes the rank-based penalty directly, so this is reserved
			# for a future migration. Returning false keeps the catalog
			# entry inert in the hooks pipeline (no double-application).
			return false
		"using_disarm", "using_force_back", "using_incapacitate", \
		"using_knock_down", "using_overrun", "using_sunder", "using_wrestle":
			# Combat Trickery per-specialization. The maneuver_resolver checks
			# proficiency-with-specialization directly rather than through the
			# hooks aggregator, so these are reserved for future migration to
			# the catalog-driven path. Returning false keeps the catalog
			# entries inert here (no double-application against the resolver).
			return false
		_:
			push_warning("%s: unknown condition '%s'" % [_LOG_TAG, requires])
			return false
