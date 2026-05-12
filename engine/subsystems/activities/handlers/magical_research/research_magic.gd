class_name ResearchMagicHandler
extends RefCounted

## research_magic handler — spell target only (Phase 10B.1b).
##
## Major Ongoing activity. Per acore-campaign-general-and-magic-research.xml
## §researching_spells L64-89 + ax_campaign_play.xml §research_magic L744-754.
##
## Duration: 2 weeks (14 days) per spell level. Computed in
## `ActivityTimeCostExecutor._compute_ticks_required` via the
## `research_magic_duration` formula.
##
## Cost: 1,000 gp per spell level, debited at LAUNCH from caster/domain treasury
## (the launcher owns the debit). On failure the gp is lost per RAW L79.
##
## Eligibility (re-checked at on_complete defensively, per coding_conventions
## §50 "Activity eligibility checks live in the handler's on_complete, NOT only
## at UI launch time"):
##   - Caster level >= 5 (RAW L18-19; L0-4 may only ASSIST).
##   - Caster is arcane (has arcane_casting or arcane_casting_in_armor power).
##     v1 10B.1b: divine spell research (Witch / Cleric / etc.) is OUT OF SCOPE
##     even though those classes carry the magical_research bucket (Q11 stack).
##     A future wave adds the divine branch — for v1 the handler rejects with
##     a clear summary.
##   - Caster has at least one operational library that supports the target
##     spell level (max_spell_level_supported >= target_spell_level).
##   - Per Q17 [RESOLVED 2026-05-11]: target_spell_key must exist in the
##     SpellRegistry (no custom-spell builder in v1).
##   - The caster must be able to learn spells of target_spell_level — i.e.,
##     `ClassRegistry.get_spell_slots(class_id, level)[target_spell_level - 1] > 0`.
##
## Magic Research Throw (per RAW §general_magic_research_throw L53-61):
##   - Target = MagicResearchThrowUtil.target_for_level(caster_level)
##              + floor(target_spell_level / 2)   (RAW L77: "1/2 spell level rounded down")
##   - Modifier = INT bonus + Magical Engineering rank + library bonus
##   - d20; 1-3 always fails; success if modified >= target.
##
## On success:
##   - Add target_spell_key to character_spell_formulas (idempotent via UNIQUE).
##   - Add target_spell_key to character_spells (in repertoire).
##   - Library auto-grows: gp_invested += round(0.1 * gp_committed) per RAW L107.
##   - INSERT magic_research_projects row with status='completed'.
##
## On failure:
##   - Time + gp lost (gp already debited at launch; nothing to refund).
##   - INSERT magic_research_projects row with status='failed'.
##
## Per Q21 [RESOLVED 2026-05-11]: state.location_kind='at_library',
## state.location_ref='library:<library_id>'. Executor's absence-accumulator
## enforces presence; this handler does NOT re-check travel — but it DOES
## re-fetch the library row to confirm it still exists, is operational, and is
## owned by the caster (catches destroyed / transferred libraries mid-project).


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "research_magic: no character_id"}

	var character := _get_character(character_id)
	if character.is_empty():
		return {"summary": "research_magic: character not found"}

	var params := _parse_params(state)
	var project_kind: String = String(params.get("project_kind", "spell"))
	match project_kind:
		"spell":
			return _handle_spell_branch(state, params, character)
		"magic_item":
			return _handle_magic_item_branch(state, params, character)
		"construct":
			return _handle_construct_branch(state, params, character)
		"monster":
			return _handle_monster_branch(state, params, character)
		_:
			return {
				"summary": "research_magic: unknown project_kind '%s'" % project_kind,
			}


# ---------------------------------------------------------------------------
# Spell-research branch (Phase 10B.1b)
# ---------------------------------------------------------------------------

static func _handle_spell_branch(
	state: Dictionary,
	params: Dictionary,
	character: Dictionary,
) -> Dictionary:
	var character_id: String = String(character.get("id", ""))
	var target_spell_key: String = String(params.get("target_spell_key", ""))
	var target_spell_level: int = int(params.get("target_spell_level", 0))
	var gp_committed: int = int(params.get("gp_committed", 0))
	var library_id: String = String(params.get("library_id", ""))
	# Fallback: extract library_id from location_ref ("library:<id>") if not
	# in params (older launches that wrote it only into state.location_ref).
	if library_id.is_empty():
		var location_ref: String = String(state.get("location_ref", ""))
		if location_ref.begins_with("library:"):
			library_id = location_ref.substr(8)

	# Validate inputs.
	if target_spell_key.is_empty():
		return {"summary": "research_magic: target_spell_key required"}
	if target_spell_level <= 0:
		return {"summary": "research_magic: target_spell_level must be 1+"}
	if gp_committed < 1000 * target_spell_level:
		return {
			"summary": "research_magic: insufficient gp_committed (need %d, have %d)" % [
				1000 * target_spell_level, gp_committed,
			],
		}

	# Eligibility (re-check at on_complete defensively).
	# Phase 10B.1g.1 (2026-05-11): widened from arcane-only to any class
	# carrying the magical_research bucket per Q11. ClassBucketResolver
	# is the canonical Q11 encoding: arcane_casting / arcane_casting_in_armor
	# / spell_research (full, not the restricted Bladedancer form). Cleric /
	# Priestess / Shaman / Dwarven Craftpriest / Witch get the bucket via
	# their spell_research power and CAN research spells. Bladedancer's
	# restricted spell_research_and_minor_item_creation power does NOT grant
	# the bucket per Q11, so they're correctly rejected. Per RAW L68 a
	# divine caster researches "with permission of his deity" — v1
	# simplification: the Judge's permission is assumed; the divine "deity
	# removes one spell of same level from the list" mechanic (RAW L69) is
	# NOT enforced in v1 (documented gap).
	var caster_level: int = int(character.get("level", 1))
	if caster_level < 5:
		return {"summary": "research_magic failed: caster must be L5+ (was L%d)" % caster_level}
	if not ClassBucketResolver.buckets_for_character(character).has("magical_research"):
		return {
			"summary": "research_magic failed: class lacks magical_research bucket per Q11 (needs arcane_casting / arcane_casting_in_armor / spell_research)",
		}
	if not _can_learn_spell_level(character, target_spell_level):
		return {
			"summary": "research_magic failed: caster cannot learn spells of level %d at level %d" % [
				target_spell_level, caster_level,
			],
		}

	# SpellRegistry check (per Q17).
	var spell_registry := _get_spell_registry()
	if not spell_registry.has_spell(target_spell_key):
		return {
			"summary": "research_magic failed: spell '%s' not in registry (v1: arcane/cleric catalogs only per Q17)" % target_spell_key,
		}

	# Spell-list eligibility (Phase 10B.1g). The caster must be able to
	# research this spell — i.e., it must appear on at least one of their
	# class's spell lists at the target level. For most arcane casters this
	# means the arcane list; for Lightblessed Wonderworker this means
	# EITHER the arcane OR the cleric divine list (their JSON declares
	# both arcane_casting and divine_casting powers with their respective
	# spell_list values).
	var research_lists: Array[String] = _researchable_spell_lists_for(character)
	if not _is_spell_on_research_list(character, target_spell_key, target_spell_level, research_lists):
		return {
			"summary": "research_magic failed: '%s' (L%d) is not on caster's research lists %s" % [
				target_spell_key, target_spell_level, str(research_lists),
			],
		}

	# Library check.
	var library := CampaignRepository.get_library(library_id)
	if library.is_empty():
		return {"summary": "research_magic failed: library not found (id=%s)" % library_id}
	if String(library.get("owner_character_id", "")) != character_id:
		return {"summary": "research_magic failed: library not owned by caster"}
	if String(library.get("status", "")) != "operational":
		return {
			"summary": "research_magic failed: library not operational (status=%s)" % library.get("status", ""),
		}
	if int(library.get("max_spell_level_supported", 0)) < target_spell_level:
		return {
			"summary": "research_magic failed: library supports up to level %d spells (target was level %d)" % [
				int(library.get("max_spell_level_supported", 0)), target_spell_level,
			],
		}

	# Magic Research Throw.
	var int_mod: int = MagicResearchThrowUtil.int_mod_for_character(character)
	var magical_engineering_rank: int = _get_magical_engineering_rank(character_id)
	var library_bonus: int = int(library.get("magic_research_throw_bonus", 0))
	var combined_modifier: int = int_mod + magical_engineering_rank + library_bonus

	# RAW L77: target value increased by 1/2 spell level rounded down for
	# existing spells (vs. full level for newly invented — out of scope per Q17).
	var base_target: int = MagicResearchThrowUtil.target_for_level(caster_level)
	var spell_level_penalty: int = int(target_spell_level / 2)
	var effective_target: int = base_target + spell_level_penalty

	var roll_result: RollResult = DiceSystem.roll_digital(20, 1, 0, "research_magic_throw")
	var raw_roll: int = roll_result.modified_total
	var modified_total: int = raw_roll + combined_modifier
	var natural_1_3: bool = raw_roll <= 3
	var success: bool = (not natural_1_3) and (modified_total >= effective_target)

	# Persist the project row (status='completed' or 'failed').
	var project_id: String = String(params.get("project_id", ""))
	var now_day: int = _calendar_day()
	if project_id.is_empty():
		project_id = CampaignRepository.create_magic_research_project({
			"campaign_id": String(character.get("campaign_id", "")),
			"character_id": character_id,
			"project_kind": "spell",
			"target_spell_key": target_spell_key,
			"target_spell_level": target_spell_level,
			"gp_committed": gp_committed,
			"days_total": 14 * target_spell_level,
			"days_completed": 14 * target_spell_level,
			"target_value": effective_target,
			"library_id": library_id,
			"status": "completed" if success else "failed",
			"started_calendar_day": int(state.get("started_calendar_day", now_day)),
			"completed_calendar_day": now_day,
			"params_json": "{}",
		})
	else:
		CampaignRepository.update_magic_research_project(project_id, {
			"status": "completed" if success else "failed",
			"days_completed": 14 * target_spell_level,
			"completed_calendar_day": now_day,
			"target_value": effective_target,
		})

	# Apply success effects.
	if success:
		_add_spell_to_formulas_and_repertoire(character_id, target_spell_key, target_spell_level)
		# Library auto-grows by 10% of gp spent per RAW L107.
		var growth_gp: int = int(roundi(0.1 * float(gp_committed)))
		if growth_gp > 0:
			CampaignRepository.update_library(library_id, {
				"gp_invested": int(library.get("gp_invested", 0)) + growth_gp,
			})

	EventBus.magic_research_project_completed.emit(project_id, character_id, success)

	var summary: String
	if success:
		summary = "Magical Research success: %s researched (L%d). d20=%d + %d = %d vs target %d. Library +%d gp." % [
			target_spell_key, target_spell_level, raw_roll, combined_modifier,
			modified_total, effective_target, int(roundi(0.1 * float(gp_committed))),
		]
	else:
		summary = "Magical Research failed: %s (L%d). d20=%d + %d = %d vs target %d. %d gp lost." % [
			target_spell_key, target_spell_level, raw_roll, combined_modifier,
			modified_total, effective_target, gp_committed,
		]
	return {
		"summary": summary,
		"presentation": {
			"type": "toast",
			"text": "Researched %s" % target_spell_key if success else "Research failed",
		},
	}


# ---------------------------------------------------------------------------
# Magic-item-enchanting branch (Phase 10B.1c)
# ---------------------------------------------------------------------------
#
# Per acore-campaign-general-and-magic-research.xml §creating_magic_items
# L112-248 + §workshops L174-183 + §formulas_and_samples L142-158.
#
# Params shape (caller / launcher supplies):
#   {
#     project_kind:               "magic_item"
#     item_name:                  "Wand of Magic Missile"
#     item_category:               "weapon" | "armor" | "shield" | "scroll" |
#                                  "potion" | "wand" | "rod" | "staff" |
#                                  "ring" | "wondrous"
#     effect_kind:                 one of the RAW table rows
#     primary_spell_key:           the imbued spell (must be in character_spell_formulas)
#     primary_spell_level:         the imbued spell's level
#     charges:                     for "charged" effect; ignored otherwise
#     magical_bonus:               for weapon/armor; 1-3
#     base_item_key:               for weapon/armor — the mundane base (FK to
#                                  data/equipment/base_equipment.json)
#     base_item_cost_gp_override:  optional override for cost-based time calc
#                                  (used when base_item_key isn't in the
#                                  EquipmentCatalog — tests bypass via this)
#     base_item_ac_override:       optional override for armor enchantments
#     precious_materials_gp:       optional, +1 throw per 10,000gp, cap = base cost
#     special_components_xp:       optional, in addition to base cost
#     gp_committed:                total gp debited at launch (base + precious materials)
#     workshop_id:                 FK to workshops; required for magic item enchanting
#     weapon_damage_override:      for weapon_plus_N items, propagate the
#                                  base item's damage (test convenience)
#   }
static func _handle_magic_item_branch(
	state: Dictionary,
	params: Dictionary,
	character: Dictionary,
) -> Dictionary:
	var character_id: String = String(character.get("id", ""))
	var item_name: String = String(params.get("item_name", "")).strip_edges()
	var item_category: String = String(params.get("item_category", "wondrous"))
	var effect_kind: String = String(params.get("effect_kind", ""))
	var primary_spell_key: String = String(params.get("primary_spell_key", ""))
	var primary_spell_level: int = int(params.get("primary_spell_level", 0))
	var charges: int = int(params.get("charges", 1))
	var magical_bonus: int = int(params.get("magical_bonus", 0))
	var base_item_key: String = String(params.get("base_item_key", ""))
	var base_item_cost_gp_override: int = int(params.get("base_item_cost_gp_override", 0))
	var base_item_ac_override: int = int(params.get("base_item_ac_override", 0))
	var precious_materials_gp: int = int(params.get("precious_materials_gp", 0))
	var special_components_xp: int = int(params.get("special_components_xp", 0))
	var gp_committed: int = int(params.get("gp_committed", 0))
	var workshop_id: String = String(params.get("workshop_id", ""))
	# Fallback: extract workshop_id from location_ref ("workshop:<id>").
	if workshop_id.is_empty():
		var location_ref: String = String(state.get("location_ref", ""))
		if location_ref.begins_with("workshop:"):
			workshop_id = location_ref.substr(9)

	# Basic input validation.
	if effect_kind.is_empty():
		return {"summary": "research_magic[magic_item]: effect_kind required"}
	if not (MagicItemEnchanting.EFFECT_TABLE.has(effect_kind)
			or effect_kind.begins_with("weapon_plus_")
			or effect_kind.begins_with("armor_plus_")):
		return {"summary": "research_magic[magic_item]: unknown effect_kind '%s'" % effect_kind}
	if item_name.is_empty():
		return {"summary": "research_magic[magic_item]: item_name required"}

	# Caster level gate per RAW §creating_magic_items L114-117.
	var caster_level: int = int(character.get("level", 1))
	var min_level: int = MagicItemEnchanting.min_caster_level(effect_kind)
	if caster_level < min_level:
		return {
			"summary": "research_magic[magic_item] failed: requires caster L%d+ for effect_kind '%s' (was L%d)" % [
				min_level, effect_kind, caster_level,
			],
		}

	# Phase 10B.1g.1 (2026-05-11): widened from arcane-only to any class
	# carrying the magical_research bucket per Q11 + RAW L116-117 which
	# allows "A divine spellcaster may create any item his class is
	# eligible to use." Bladedancer's restricted greater_item_creation
	# power is NOT yet surfaced in v1; their MR bucket exclusion (Q11)
	# still applies via ClassBucketResolver here. The arcane-only
	# restriction on "items exclusive to divine spellcasters" (RAW L116
	# inverse) is NOT enforced in v1 — we don't currently track
	# divine-exclusive item types.
	if not ClassBucketResolver.buckets_for_character(character).has("magical_research"):
		return {"summary": "research_magic[magic_item] failed: class lacks magical_research bucket per Q11"}

	# RAW L121: "the spellcaster must know the spell or spells that replicate
	# the item's effect, or possess a sample or formula." v1 enforces the
	# spell-knowledge path. For weapon_plus_N / armor_plus_N, the primary
	# spell is implicit (per RAW L137 "+1 = 1st-level spell effect" but the
	# caster doesn't need to know a specific spell — the bonus is the spell).
	# Tests may pass primary_spell_key="" for weapon/armor enchantments.
	var requires_spell_knowledge: bool = (
		not effect_kind.begins_with("weapon_plus_")
		and not effect_kind.begins_with("armor_plus_")
	)
	if requires_spell_knowledge:
		if primary_spell_key.is_empty():
			return {"summary": "research_magic[magic_item] failed: primary_spell_key required for effect_kind '%s'" % effect_kind}
		if not _character_knows_spell_formula(character_id, primary_spell_key):
			return {
				"summary": "research_magic[magic_item] failed: caster does not know formula for '%s' (scribe or research it first)" % primary_spell_key,
			}

	# Workshop check.
	if workshop_id.is_empty():
		return {"summary": "research_magic[magic_item] failed: workshop required (no workshop_id in params or location_ref)"}
	var workshop := CampaignRepository.get_workshop(workshop_id)
	var workshop_err: String = MagicItemEnchanting.validate_workshop(
		workshop, character_id, effect_kind, primary_spell_level)
	if not workshop_err.is_empty():
		return {"summary": "research_magic[magic_item] failed: %s" % workshop_err}

	# Formula reduction check (RAW L155-156): if the caster has previously
	# crafted an item with the same (category, effect_kind, primary_spell)
	# signature, -50% cost/time + half-level target modifier instead of full.
	var used_formula: bool = CampaignRepository.character_has_item_formula(
		character_id, item_category, effect_kind, primary_spell_key)

	# Cost and time.
	var base_cost: int = MagicItemEnchanting.base_gp_cost(effect_kind, primary_spell_level, charges)
	# Weapon/armor time uses the base item's gp cost / 10 (weapon) or AC (armor).
	var time_arg: int = charges
	if effect_kind.begins_with("weapon_plus_"):
		time_arg = _resolve_weapon_base_cost_gp(base_item_key, base_item_cost_gp_override)
	elif effect_kind.begins_with("armor_plus_"):
		time_arg = _resolve_armor_ac(base_item_key, base_item_ac_override)
	var base_time_days: int = MagicItemEnchanting.base_days(
		effect_kind, primary_spell_level, time_arg)

	var final_cost: int = base_cost
	var final_days: int = base_time_days
	if used_formula:
		final_cost = MagicItemEnchanting.apply_formula_reduction(final_cost)
		final_days = MagicItemEnchanting.apply_formula_reduction(final_days)

	# gp_committed must at least cover base_cost (precious materials are
	# in addition to base cost). RAW: special components are also IN
	# ADDITION. The launcher is responsible for the actual debit; we just
	# verify the player committed enough.
	var required_gp: int = final_cost + precious_materials_gp
	if gp_committed < required_gp:
		return {
			"summary": "research_magic[magic_item] failed: insufficient gp_committed (need %d, have %d)" % [
				required_gp, gp_committed,
			],
		}

	# Magic Research Throw.
	var int_mod: int = MagicResearchThrowUtil.int_mod_for_character(character)
	var magical_engineering_rank: int = _get_magical_engineering_rank(character_id)
	var workshop_bonus: int = MagicItemEnchanting.workshop_throw_bonus(
		workshop, effect_kind, primary_spell_level)
	var precious_bonus: int = MagicItemEnchanting.precious_materials_throw_bonus(
		precious_materials_gp, base_cost)
	var combined_modifier: int = int_mod + magical_engineering_rank + workshop_bonus + precious_bonus

	var base_target: int = MagicResearchThrowUtil.target_for_level(caster_level)
	var target_modifier: int = MagicItemEnchanting.target_modifier_for_effect(
		effect_kind, primary_spell_level, used_formula)
	var effective_target: int = base_target + target_modifier

	var roll_result: RollResult = DiceSystem.roll_digital(20, 1, 0, "magic_item_throw")
	var raw_roll: int = roll_result.modified_total
	var modified_total: int = raw_roll + combined_modifier
	var natural_1_3: bool = raw_roll <= 3
	var success: bool = (not natural_1_3) and (modified_total >= effective_target)

	# Persist the project row.
	var project_id: String = String(params.get("project_id", ""))
	var now_day: int = _calendar_day()
	if project_id.is_empty():
		project_id = CampaignRepository.create_magic_research_project({
			"campaign_id": String(character.get("campaign_id", "")),
			"character_id": character_id,
			"project_kind": "magic_item",
			"target_item_kind": item_category,
			"target_spell_key": primary_spell_key,
			"target_spell_level": primary_spell_level,
			"gp_committed": gp_committed,
			"days_total": final_days,
			"days_completed": final_days,
			"target_value": effective_target,
			"workshop_id": workshop_id,
			"status": "completed" if success else "failed",
			"started_calendar_day": int(state.get("started_calendar_day", now_day)),
			"completed_calendar_day": now_day,
			"params_json": JSON.stringify({
				"effect_kind": effect_kind,
				"used_formula": used_formula,
				"charges": charges,
				"magical_bonus": magical_bonus,
				"base_item_key": base_item_key,
				"item_name": item_name,
			}),
		})
	else:
		CampaignRepository.update_magic_research_project(project_id, {
			"status": "completed" if success else "failed",
			"days_completed": final_days,
			"completed_calendar_day": now_day,
			"target_value": effective_target,
		})

	# Success effects.
	var crafted_id: String = ""
	var inventory_item_id: String = ""
	if success:
		var crafted_data: Dictionary = {
			"campaign_id": String(character.get("campaign_id", "")),
			"creator_character_id": character_id,
			"name": item_name,
			"item_category": item_category,
			"base_item_key": base_item_key,
			"effect_kind": effect_kind,
			"primary_spell_key": primary_spell_key,
			"primary_spell_level": primary_spell_level,
			"spell_keys_json": JSON.stringify([primary_spell_key] if not primary_spell_key.is_empty() else []),
			"magical_bonus": magical_bonus,
			"weapon_damage": String(params.get("weapon_damage_override", "")),
			"armor_ac_bonus": int(params.get("armor_ac_override", 0)),
			"encumbrance_units": int(params.get("encumbrance_units", 100)),
			"gp_cost_base": final_cost,
			"gp_cost_precious_materials": precious_materials_gp,
			"special_components_xp": special_components_xp,
			"days_to_create": final_days,
			"used_formula": used_formula,
			"workshop_id": workshop_id,
			"notes": String(params.get("notes", "")),
			"created_calendar_day": now_day,
		}
		# Charged-effect items track charges.
		if effect_kind == "charged":
			crafted_data["charges_max"] = max(1, charges)
			crafted_data["charges_remaining"] = max(1, charges)
		crafted_id = CampaignRepository.create_crafted_magic_item(crafted_data)

		# Spawn an inventory_items instance for the crafter. item_key uses the
		# 'crafted:<id>' convention so downstream lookups can resolve full
		# metadata via CampaignRepository.get_crafted_magic_item.
		if not crafted_id.is_empty():
			inventory_item_id = _spawn_inventory_instance(character_id, crafted_id, crafted_data)

	EventBus.magic_research_project_completed.emit(project_id, character_id, success)

	var summary: String
	if success:
		summary = "Magic Item enchanted: '%s' (%s, %s). d20=%d + %d = %d vs target %d. Cost %d gp, %d days%s." % [
			item_name, item_category, effect_kind, raw_roll, combined_modifier,
			modified_total, effective_target, final_cost, final_days,
			" (formula -50%%)" if used_formula else "",
		]
	else:
		summary = "Magic Item enchanting failed: '%s'. d20=%d + %d = %d vs target %d. %d gp lost." % [
			item_name, raw_roll, combined_modifier, modified_total,
			effective_target, gp_committed,
		]
	return {
		"summary": summary,
		"presentation": {
			"type": "toast",
			"text": ("Enchanted " + item_name) if success else "Enchanting failed",
		},
	}


# ---------------------------------------------------------------------------
# Construct branch (Phase 10B.1e)
# ---------------------------------------------------------------------------
#
# Per acore-campaign-general-and-magic-research.xml §constructs L373-415.
#
# Params shape:
#   {
#     project_kind:           "construct"
#     name:                    "Iron Sentinel" (or similar)
#     hit_dice:                int (>= 1, <= 2 × caster_level)
#     attacks_per_round:       int (1-4 per RAW L410)
#     max_damage_per_round:    int (<= 3 × HD per RAW L411)
#     damage_expression:       String (e.g. "1d8")
#     special_abilities:       Array[String] (each name is one ability;
#                              the standard immunity package counts as one
#                              ability per RAW L408-409)
#     armor_class:             int (optional; defaults to floor(HD/2)
#                              per RAW L407)
#     workshop_id:             String (FK to workshops; required)
#     library_id:              String (optional; if present, used for
#                              the design step's library check)
#     gp_committed:            int (must >= base_gp_cost)
#     location_kind:           "stronghold" | "with_owner" | etc.
#     location_ref:            String
#   }
#
# v1 simplification: design+create combined into one project. The handler
# creates BOTH a construct_designs row AND a construct_instances row on
# success. Future polish: split into two activities so a caster can design
# once and create multiple instances cheaply.
static func _handle_construct_branch(
	state: Dictionary,
	params: Dictionary,
	character: Dictionary,
) -> Dictionary:
	var character_id: String = String(character.get("id", ""))
	var name: String = String(params.get("name", "")).strip_edges()
	var hit_dice: int = int(params.get("hit_dice", 0))
	var attacks_per_round: int = int(params.get("attacks_per_round", 1))
	var max_damage_per_round: int = int(params.get("max_damage_per_round", 1))
	var damage_expression: String = String(params.get("damage_expression", "1d6"))
	var special_abilities_v: Variant = params.get("special_abilities", [])
	var special_abilities: Array = special_abilities_v if special_abilities_v is Array else []
	var armor_class: int = int(params.get("armor_class",
		MagicalResearchConstruct.default_armor_class(hit_dice)))
	var workshop_id: String = String(params.get("workshop_id", ""))
	var library_id: String = String(params.get("library_id", ""))
	var gp_committed: int = int(params.get("gp_committed", 0))
	var location_kind: String = String(params.get("location_kind", "stronghold"))
	var location_ref: String = String(params.get("location_ref", ""))
	# Fallback: extract workshop_id from state.location_ref.
	if workshop_id.is_empty():
		var loc_ref: String = String(state.get("location_ref", ""))
		if loc_ref.begins_with("workshop:"):
			workshop_id = loc_ref.substr(9)

	# Basic input validation.
	if name.is_empty():
		return {"summary": "research_magic[construct]: name required"}
	if hit_dice <= 0:
		return {"summary": "research_magic[construct]: hit_dice must be 1+"}

	# Caster-level + class gates per RAW L375-376.
	var caster_level: int = int(character.get("level", 1))
	var class_id: String = String(character.get("character_class", ""))
	var min_level: int = MagicalResearchConstruct.min_caster_level(class_id)
	if caster_level < min_level:
		return {
			"summary": "research_magic[construct] failed: %s must be L%d+ (was L%d). RAW: arcane/divine L11+, Dwarven Craftpriest L9+." % [
				class_id, min_level, caster_level,
			],
		}
	# Only arcane casters OR divine casters OR Dwarven Craftpriest qualify.
	# v1 simplification: accept any caster who passes the level gate AND has
	# arcane_casting / arcane_casting_in_armor / divine_casting power, OR
	# class_id == "dwarven_craftpriest".
	if not (_is_arcane_caster(character) or _has_divine_casting(character) or class_id == "dwarven_craftpriest"):
		return {
			"summary": "research_magic[construct] failed: requires arcane or divine spellcaster (or Dwarven Craftpriest)",
		}

	# HD cap per RAW L388.
	var hd_err: String = MagicalResearchConstruct.validate_hd(hit_dice, caster_level)
	if not hd_err.is_empty():
		return {"summary": "research_magic[construct] failed: %s" % hd_err}

	# Attack / damage limits per RAW L410-411.
	var atk_err: String = MagicalResearchConstruct.validate_attacks_and_damage(
		attacks_per_round, max_damage_per_round, hit_dice)
	if not atk_err.is_empty():
		return {"summary": "research_magic[construct] failed: %s" % atk_err}

	# Cost / time.
	var ability_count: int = special_abilities.size()
	var gp_cost: int = MagicalResearchConstruct.base_gp_cost(hit_dice, ability_count)
	var days: int = MagicalResearchConstruct.base_days(gp_cost)
	if gp_committed < gp_cost:
		return {
			"summary": "research_magic[construct] failed: insufficient gp_committed (need %d, have %d)" % [
				gp_cost, gp_committed,
			],
		}

	# Workshop check per RAW L384.
	if workshop_id.is_empty():
		return {"summary": "research_magic[construct] failed: workshop required (RAW L384)"}
	var workshop := CampaignRepository.get_workshop(workshop_id)
	var ws_err: String = MagicalResearchConstruct.validate_workshop(
		workshop, character_id, gp_cost)
	if not ws_err.is_empty():
		return {"summary": "research_magic[construct] failed: %s" % ws_err}

	# Magic Research Throw.
	var int_mod: int = MagicResearchThrowUtil.int_mod_for_character(character)
	var magical_engineering_rank: int = _get_magical_engineering_rank(character_id)
	var workshop_bonus: int = MagicalResearchConstruct.workshop_throw_bonus(workshop, gp_cost)
	var combined_modifier: int = int_mod + magical_engineering_rank + workshop_bonus

	var base_target: int = MagicResearchThrowUtil.target_for_level(caster_level)
	var target_modifier: int = MagicalResearchConstruct.target_modifier_for_cost(gp_cost)
	var effective_target: int = base_target + target_modifier

	var roll_result: RollResult = DiceSystem.roll_digital(20, 1, 0, "construct_throw")
	var raw_roll: int = roll_result.modified_total
	var modified_total: int = raw_roll + combined_modifier
	var natural_1_3: bool = raw_roll <= 3
	var success: bool = (not natural_1_3) and (modified_total >= effective_target)

	# Persist the project audit row.
	var now_day: int = _calendar_day()
	var special_abilities_json: String = JSON.stringify(special_abilities)
	var project_id := CampaignRepository.create_magic_research_project({
		"campaign_id": String(character.get("campaign_id", "")),
		"character_id": character_id,
		"project_kind": "construct",
		"target_item_kind": "construct",
		"gp_committed": gp_committed,
		"days_total": days,
		"days_completed": days,
		"target_value": effective_target,
		"workshop_id": workshop_id,
		"library_id": library_id if not library_id.is_empty() else null,
		"status": "completed" if success else "failed",
		"started_calendar_day": int(state.get("started_calendar_day", now_day)),
		"completed_calendar_day": now_day,
		"params_json": JSON.stringify({
			"name": name,
			"hit_dice": hit_dice,
			"attacks_per_round": attacks_per_round,
			"max_damage_per_round": max_damage_per_round,
			"damage_expression": damage_expression,
			"special_abilities": special_abilities,
			"armor_class": armor_class,
		}),
	})

	var design_id: String = ""
	var instance_id: String = ""
	if success:
		# Design step: dedupe via find_matching_construct_design.
		var existing := CampaignRepository.find_matching_construct_design(
			character_id, name, hit_dice, attacks_per_round, max_damage_per_round,
			special_abilities_json)
		if existing.is_empty():
			design_id = CampaignRepository.create_construct_design({
				"campaign_id": String(character.get("campaign_id", "")),
				"creator_character_id": character_id,
				"name": name,
				"hit_dice": hit_dice,
				"armor_class": armor_class,
				"attacks_per_round": attacks_per_round,
				"max_damage_per_round": max_damage_per_round,
				"damage_expression": damage_expression,
				"special_abilities_json": special_abilities_json,
				"gp_cost_total": gp_cost,
				"days_to_design": days,
				"library_id": library_id if not library_id.is_empty() else null,
				"designed_calendar_day": now_day,
			})
		else:
			design_id = String(existing.get("id", ""))

		# Create step: spawn the instance.
		var hp_max: int = MagicalResearchConstruct.default_hp_max(hit_dice)
		instance_id = CampaignRepository.create_construct_instance({
			"campaign_id": String(character.get("campaign_id", "")),
			"design_id": design_id,
			"creator_character_id": character_id,
			"name": name,
			"hp_max": hp_max,
			"hp_current": hp_max,
			"location_kind": location_kind,
			"location_ref": location_ref,
			"workshop_id": workshop_id,
			"gp_cost_total": gp_cost,
			"days_to_create": days,
			"status": "active",
			"created_calendar_day": now_day,
		})

	EventBus.magic_research_project_completed.emit(project_id, character_id, success)

	var summary: String
	if success:
		summary = "Construct '%s' built: %d HD, %d attacks/round (max %d dmg), AC %d, %d abilities. d20=%d + %d = %d vs target %d. Cost %d gp, %d days." % [
			name, hit_dice, attacks_per_round, max_damage_per_round,
			armor_class, ability_count,
			raw_roll, combined_modifier, modified_total, effective_target,
			gp_cost, days,
		]
	else:
		summary = "Construct '%s' creation failed. d20=%d + %d = %d vs target %d. %d gp lost." % [
			name, raw_roll, combined_modifier, modified_total,
			effective_target, gp_committed,
		]
	return {
		"summary": summary,
		"presentation": {
			"type": "toast",
			"text": ("Built " + name) if success else "Construct failed",
		},
		"design_id": design_id,
		"instance_id": instance_id,
		"project_id": project_id,
	}


# ---------------------------------------------------------------------------
# Cross-breeding branch (Phase 10B.1f) — project_kind='monster'
# ---------------------------------------------------------------------------
#
# Per acore-campaign-general-and-magic-research.xml §crossbreeds L417-484.
# Per Q19 [RESOLVED 2026-05-11]: v1 scope is CROSS-BREEDING only;
# monster-from-scratch deferred to v1.1.
#
# Params shape:
#   {
#     project_kind:                "monster"
#     monster_action:              "crossbreed" (v1 only value; future:
#                                  "scratch" for monster-from-scratch)
#     name:                        "Owlbear" (or similar)
#     progenitor_a_name:           String (free-text for v1)
#     progenitor_b_name:           String
#     progenitor_a_hd:             int (>= 1, <= caster level per RAW L423)
#     progenitor_b_hd:             int
#     progenitor_a_alignment:      "lawful" | "neutral" | "chaotic"
#     progenitor_b_alignment:      "lawful" | "neutral" | "chaotic"
#     hit_dice:                    int (must be in [min(pA, pB), max(pA, pB)]
#                                  per RAW L443)
#     armor_class:                 int (RAW L438-441: pick from progenitors
#                                  per movement choice)
#     attacks_per_round:           int (1-6)
#     max_damage_per_round:        int
#     damage_expression:           String (e.g. "1d10")
#     morale:                      int (RAW L451: better of two progenitors)
#     movement_kind:               "progenitor_a" | "progenitor_b" | "both"
#                                  (RAW L434-436; "both" counts as 1 ability)
#     special_abilities:           Array[String] — each name = 1 ability
#     additional_types:            Array[String] — Judge-discretion types
#                                  (beastman / enchanted_creature / etc.).
#                                  'fantastic' is always included.
#     laboratory_id:               String (FK; required per RAW L471)
#     gp_committed:                int (must >= base_gp_cost)
#     initial_reaction:            "hostile" | "unfriendly" | "neutral" |
#                                  "friendly" | "helpful" (optional; v1
#                                  caller supplies the Judge's reaction roll
#                                  result per RAW L482; future polish: roll
#                                  here)
#     location_kind:               for instance row
#     location_ref:                for instance row
#   }
#
# v1 simplification: design + create combined into one project. Creates
# BOTH crossbreed_species (deduped) + crossbreed_instances rows. The
# split-create-from-existing-species path is a future polish.
static func _handle_monster_branch(
	state: Dictionary,
	params: Dictionary,
	character: Dictionary,
) -> Dictionary:
	var character_id: String = String(character.get("id", ""))
	var monster_action: String = String(params.get("monster_action", "crossbreed"))
	if monster_action != "crossbreed":
		return {
			"summary": "research_magic[monster]: action '%s' not yet supported (v1 10B.1f ships crossbreeding only; monster-from-scratch deferred per Q19)" % monster_action,
		}

	var name: String = String(params.get("name", "")).strip_edges()
	var prog_a_name: String = String(params.get("progenitor_a_name", "")).strip_edges()
	var prog_b_name: String = String(params.get("progenitor_b_name", "")).strip_edges()
	var prog_a_hd: int = int(params.get("progenitor_a_hd", 0))
	var prog_b_hd: int = int(params.get("progenitor_b_hd", 0))
	var prog_a_align: String = String(params.get("progenitor_a_alignment", "neutral"))
	var prog_b_align: String = String(params.get("progenitor_b_alignment", "neutral"))
	var hit_dice: int = int(params.get("hit_dice", 0))
	var armor_class: int = int(params.get("armor_class", 0))
	var attacks_per_round: int = int(params.get("attacks_per_round", 1))
	var max_damage_per_round: int = int(params.get("max_damage_per_round", 1))
	var damage_expression: String = String(params.get("damage_expression", "1d6"))
	var morale: int = int(params.get("morale", 0))
	var movement_kind: String = String(params.get("movement_kind", "progenitor_a"))
	var special_abilities_v: Variant = params.get("special_abilities", [])
	var special_abilities: Array = special_abilities_v if special_abilities_v is Array else []
	var additional_types_v: Variant = params.get("additional_types", [])
	var additional_types: Array = additional_types_v if additional_types_v is Array else []
	var laboratory_id: String = String(params.get("laboratory_id", ""))
	var gp_committed: int = int(params.get("gp_committed", 0))
	var location_kind: String = String(params.get("location_kind", "laboratory"))
	var location_ref: String = String(params.get("location_ref", ""))
	var initial_reaction_v: Variant = params.get("initial_reaction", null)

	# Fallback: extract laboratory_id from state.location_ref ("laboratory:<id>").
	if laboratory_id.is_empty():
		var loc_ref: String = String(state.get("location_ref", ""))
		if loc_ref.begins_with("laboratory:"):
			laboratory_id = loc_ref.substr(11)

	# Basic input validation.
	if name.is_empty():
		return {"summary": "research_magic[monster]: name required"}
	if prog_a_name.is_empty() or prog_b_name.is_empty():
		return {"summary": "research_magic[monster]: both progenitor_a_name and progenitor_b_name required"}

	# Eligibility (RAW L419 — arcane L11+).
	var caster_level: int = int(character.get("level", 1))
	if caster_level < MagicalResearchCrossbreed.min_caster_level():
		return {
			"summary": "research_magic[monster] failed: cross-breeding requires arcane caster L%d+ (was L%d) per RAW L419" % [
				MagicalResearchCrossbreed.min_caster_level(), caster_level,
			],
		}
	if not _is_arcane_caster(character):
		return {"summary": "research_magic[monster] failed: arcane caster required (Dwarven Craftpriests NOT eligible for cross-breeding per RAW)"}

	# Progenitor HD limits.
	var prog_hd_err: String = MagicalResearchCrossbreed.validate_progenitor_hd(
		prog_a_hd, prog_b_hd, caster_level)
	if not prog_hd_err.is_empty():
		return {"summary": "research_magic[monster] failed: %s" % prog_hd_err}

	# Crossbreed HD must be in progenitor range.
	var hd_err: String = MagicalResearchCrossbreed.validate_crossbreed_hd(
		hit_dice, prog_a_hd, prog_b_hd)
	if not hd_err.is_empty():
		return {"summary": "research_magic[monster] failed: %s" % hd_err}

	# Special-ability soft cap (RAW L424 per-progenitor + L454 inheritance).
	# Effective ability count includes the +1 for "both movements" per
	# RAW L436.
	var int_mod: int = MagicResearchThrowUtil.int_mod_for_character(character)
	var ability_count: int = special_abilities.size()
	if MagicalResearchCrossbreed.movement_costs_ability(movement_kind):
		ability_count += 1
	var ability_err: String = MagicalResearchCrossbreed.validate_crossbreed_ability_count(
		ability_count, int_mod)
	if not ability_err.is_empty():
		return {"summary": "research_magic[monster] failed: %s" % ability_err}

	# Cost / time.
	var gp_cost: int = MagicalResearchCrossbreed.base_gp_cost(hit_dice, ability_count)
	var days: int = MagicalResearchCrossbreed.base_days(gp_cost)
	if gp_committed < gp_cost:
		return {
			"summary": "research_magic[monster] failed: insufficient gp_committed (need %d, have %d)" % [
				gp_cost, gp_committed,
			],
		}

	# Laboratory check.
	if laboratory_id.is_empty():
		return {"summary": "research_magic[monster] failed: laboratory required (RAW L471)"}
	var laboratory := CampaignRepository.get_laboratory(laboratory_id)
	var lab_err: String = MagicalResearchCrossbreed.validate_laboratory(
		laboratory, character_id, gp_cost)
	if not lab_err.is_empty():
		return {"summary": "research_magic[monster] failed: %s" % lab_err}

	# Derived stats.
	var derived_alignment: String = MagicalResearchCrossbreed.derive_alignment(
		prog_a_align, prog_b_align)
	var derived_types: Array[String] = MagicalResearchCrossbreed.compute_types(additional_types)

	# Magic Research Throw.
	var magical_engineering_rank: int = _get_magical_engineering_rank(character_id)
	var lab_bonus: int = MagicalResearchCrossbreed.laboratory_throw_bonus(laboratory, gp_cost)
	var combined_modifier: int = int_mod + magical_engineering_rank + lab_bonus

	var base_target: int = MagicResearchThrowUtil.target_for_level(caster_level)
	var target_modifier: int = MagicalResearchCrossbreed.target_modifier_for_cost(gp_cost)
	var effective_target: int = base_target + target_modifier

	var roll_result: RollResult = DiceSystem.roll_digital(20, 1, 0, "crossbreed_throw")
	var raw_roll: int = roll_result.modified_total
	var modified_total: int = raw_roll + combined_modifier
	var natural_1_3: bool = raw_roll <= 3
	var success: bool = (not natural_1_3) and (modified_total >= effective_target)

	# Persist the project audit row.
	var now_day: int = _calendar_day()
	var special_abilities_json: String = JSON.stringify(special_abilities)
	var types_json: String = JSON.stringify(derived_types)
	var project_id := CampaignRepository.create_magic_research_project({
		"campaign_id": String(character.get("campaign_id", "")),
		"character_id": character_id,
		"project_kind": "monster",
		"target_item_kind": "crossbreed",
		"gp_committed": gp_committed,
		"days_total": days,
		"days_completed": days,
		"target_value": effective_target,
		"status": "completed" if success else "failed",
		"started_calendar_day": int(state.get("started_calendar_day", now_day)),
		"completed_calendar_day": now_day,
		"params_json": JSON.stringify({
			"name": name,
			"progenitor_a_name": prog_a_name,
			"progenitor_b_name": prog_b_name,
			"hit_dice": hit_dice,
			"laboratory_id": laboratory_id,
		}),
	})

	var species_id: String = ""
	var instance_id: String = ""
	if success:
		# Dedupe species via find_matching_crossbreed_species.
		var existing := CampaignRepository.find_matching_crossbreed_species(
			character_id, name, prog_a_name, prog_b_name,
			hit_dice, attacks_per_round, max_damage_per_round,
			special_abilities_json)
		if existing.is_empty():
			species_id = CampaignRepository.create_crossbreed_species({
				"campaign_id": String(character.get("campaign_id", "")),
				"creator_character_id": character_id,
				"name": name,
				"progenitor_a_name": prog_a_name,
				"progenitor_b_name": prog_b_name,
				"progenitor_a_hd": prog_a_hd,
				"progenitor_b_hd": prog_b_hd,
				"progenitor_a_alignment": prog_a_align,
				"progenitor_b_alignment": prog_b_align,
				"hit_dice": hit_dice,
				"armor_class": armor_class,
				"attacks_per_round": attacks_per_round,
				"max_damage_per_round": max_damage_per_round,
				"damage_expression": damage_expression,
				"morale": morale,
				"movement_kind": movement_kind,
				"special_abilities_json": special_abilities_json,
				"alignment": derived_alignment,
				"types_json": types_json,
				"gp_cost_total": gp_cost,
				"days_to_create": days,
				"laboratory_id": laboratory_id,
				"designed_calendar_day": now_day,
			})
		else:
			species_id = String(existing.get("id", ""))

		# Instance.
		var hp_max: int = MagicalResearchCrossbreed.default_hp_max(hit_dice)
		var initial_reaction_val: Variant = initial_reaction_v
		if initial_reaction_val is String and (initial_reaction_val as String).is_empty():
			initial_reaction_val = null
		instance_id = CampaignRepository.create_crossbreed_instance({
			"campaign_id": String(character.get("campaign_id", "")),
			"species_id": species_id,
			"creator_character_id": character_id,
			"name": name,
			"hp_max": hp_max,
			"hp_current": hp_max,
			"location_kind": location_kind,
			"location_ref": location_ref if not location_ref.is_empty() else ("laboratory:" + laboratory_id),
			"laboratory_id": laboratory_id,
			"initial_reaction": initial_reaction_val,
			"status": "alive",
			"gp_cost_total": gp_cost,
			"days_to_create": days,
			"created_calendar_day": now_day,
		})

	EventBus.magic_research_project_completed.emit(project_id, character_id, success)

	var summary: String
	if success:
		summary = "Crossbreed '%s' created from %s × %s. HD %d, %d attacks (max %d dmg), AC %d, alignment %s, types %s. d20=%d + %d = %d vs target %d. Cost %d gp, %d days." % [
			name, prog_a_name, prog_b_name,
			hit_dice, attacks_per_round, max_damage_per_round, armor_class,
			derived_alignment, types_json,
			raw_roll, combined_modifier, modified_total, effective_target,
			gp_cost, days,
		]
	else:
		summary = "Crossbreed '%s' creation failed. d20=%d + %d = %d vs target %d. %d gp + progenitor creatures lost." % [
			name, raw_roll, combined_modifier, modified_total,
			effective_target, gp_committed,
		]
	return {
		"summary": summary,
		"presentation": {
			"type": "toast",
			"text": ("Bred " + name) if success else "Crossbreed failed",
		},
		"species_id": species_id,
		"instance_id": instance_id,
		"project_id": project_id,
	}


# ---------------------------------------------------------------------------
# Magic-item helpers
# ---------------------------------------------------------------------------

static func _has_divine_casting(character: Dictionary) -> bool:
	var class_id: String = String(character.get("character_class", ""))
	if class_id.is_empty():
		return false
	var registry := _get_class_registry()
	var powers: Array = registry.get_class_powers(class_id)
	for entry in powers:
		if entry is Dictionary:
			var pid: String = String(entry.get("power_id", ""))
			if pid == "divine_casting" or pid == "spell_research_and_minor_item_creation":
				return true
	return false


static func _character_knows_spell_formula(character_id: String, spell_key: String) -> bool:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM character_spell_formulas WHERE character_id = ? AND spell_key = ? LIMIT 1",
		[character_id, spell_key]
	):
		return false
	if CampaignRepository.db.query_result.is_empty():
		# Fallback: some classes auto-have a spell in repertoire without an
		# explicit formula row. Check character_spells too.
		if not CampaignRepository.db.query_with_bindings(
			"SELECT id FROM character_spells WHERE character_id = ? AND spell_key = ? LIMIT 1",
			[character_id, spell_key]
		):
			return false
		return not CampaignRepository.db.query_result.is_empty()
	return true


static func _resolve_weapon_base_cost_gp(base_item_key: String, override: int) -> int:
	if override > 0:
		return override
	if base_item_key.is_empty():
		return 10  # default to 10gp = sword baseline if no key supplied
	var equipment_catalog := _get_equipment_catalog()
	var item: Dictionary = equipment_catalog.get_item(base_item_key)
	if item.is_empty():
		return 10
	# cost_cp → gp.
	var cost_cp: int = int(item.get("cost_cp", 1000))
	return max(1, int(cost_cp / 100))


static func _resolve_armor_ac(base_item_key: String, override: int) -> int:
	if override > 0:
		return override
	if base_item_key.is_empty():
		return 3  # default to chain (AC 4 - 1 = 3) — placeholder
	var equipment_catalog := _get_equipment_catalog()
	var item: Dictionary = equipment_catalog.get_item(base_item_key)
	if item.is_empty():
		return 3
	# ACKS descending AC = armor_ac_bonus from the item entry.
	return max(1, int(item.get("armor_ac_bonus", 3)))


## Inserts an inventory_items row for the just-crafted item. item_key is
## 'crafted:<id>' so future lookups resolve back to crafted_magic_items.
static func _spawn_inventory_instance(
	character_id: String, crafted_id: String, crafted_data: Dictionary,
) -> String:
	var inv_id: String = CampaignRepository.generate_id()
	var item_key: String = "crafted:%s" % crafted_id
	var magical_bonus: int = int(crafted_data.get("magical_bonus", 0))
	var weapon_damage: String = String(crafted_data.get("weapon_damage", ""))
	var armor_ac_bonus: int = int(crafted_data.get("armor_ac_bonus", 0))
	var encumbrance_units: int = int(crafted_data.get("encumbrance_units", 100))
	var item_category: String = String(crafted_data.get("item_category", "misc"))
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, notes, item_category,
			 is_magical, magical_bonus, weapon_damage, armor_ac_bonus, is_heavy)
		VALUES (?, ?, ?, ?, 1, ?, 'pack', 0, '', ?, 1, ?, ?, ?, 0)
	""", [
		inv_id, character_id, item_key,
		String(crafted_data.get("name", "Crafted Magic Item")),
		encumbrance_units, item_category,
		magical_bonus, weapon_damage, armor_ac_bonus,
	]):
		push_error("research_magic[magic_item]: inventory_items insert failed for crafted=%s" % crafted_id)
		return ""
	return inv_id


# ---------------------------------------------------------------------------
# Eligibility helpers
# ---------------------------------------------------------------------------

static func _is_arcane_caster(character: Dictionary) -> bool:
	var class_id: String = String(character.get("character_class", ""))
	if class_id.is_empty():
		return false
	var registry := _get_class_registry()
	var powers: Array = registry.get_class_powers(class_id)
	for entry in powers:
		if entry is Dictionary:
			var pid: String = String(entry.get("power_id", ""))
			if pid == "arcane_casting" or pid == "arcane_casting_in_armor":
				return true
	return false


static func _can_learn_spell_level(character: Dictionary, target_level: int) -> bool:
	if target_level <= 0:
		return false
	var class_id: String = String(character.get("character_class", ""))
	var caster_level: int = int(character.get("level", 1))
	if class_id.is_empty():
		return false
	var registry := _get_class_registry()
	var slots: Array = registry.get_spell_slots(class_id, caster_level)
	if slots.is_empty():
		return false
	# slots is 1-indexed conceptually (slots[0] = L1 slots, slots[1] = L2, ...).
	# Caster can learn spells up to the highest level for which they have at
	# least one slot.
	if target_level > slots.size():
		return false
	return int(slots[target_level - 1]) > 0


## Extracts the arcane-tradition level for a spell from its classifications
## array. Returns 0 if the spell has no arcane classification. Used by
## replace_spell to verify equal-level swaps.
static func _get_arcane_spell_level(spell_def: Dictionary) -> int:
	var classifications: Array = spell_def.get("classifications", [])
	for entry in classifications:
		if entry is Dictionary and String(entry.get("tradition", "")) == "arcane":
			return int(entry.get("level", 0))
	return 0


# ---------------------------------------------------------------------------
# Researchable spell lists (Phase 10B.1g — Lightblessed dual-list)
# ---------------------------------------------------------------------------
#
# Per pc_classes_5.xml §spell_research L121-123 + Q2 / roadmap RESOLVED:
# Lightblessed Wonderworker may research targets on EITHER the arcane spell
# list OR the cleric divine spell list. The dual-list eligibility is data-
# driven: any class with multiple `class_powers` carrying a `spell_list`
# field can research across all those lists.
#
# For most casters this returns a single-element array. For Lightblessed
# (arcane_casting + divine_casting in their class JSON) it returns
# ["arcane", "divine_cleric"].
static func _researchable_spell_lists_for(character: Dictionary) -> Array[String]:
	var class_id: String = String(character.get("character_class", ""))
	if class_id.is_empty():
		return []
	var registry := _get_class_registry()
	var class_powers: Array = registry.get_class_powers(class_id)
	var result: Array[String] = []
	const CASTING_POWERS: Array[String] = [
		"arcane_casting", "arcane_casting_in_armor",
		"divine_casting", "spell_research",
		"spell_research_and_minor_item_creation",
	]
	for power in class_powers:
		if not (power is Dictionary):
			continue
		var pid: String = String(power.get("power_id", ""))
		if not (pid in CASTING_POWERS):
			continue
		var list_id: String = String(power.get("spell_list", ""))
		if list_id.is_empty():
			# spell_research / spell_research_and_minor_item_creation often
			# share a list with the class's primary casting power; if the
			# list is unspecified we skip and rely on the primary power.
			continue
		if not (list_id in result):
			result.append(list_id)
	return result


## Returns true if [param spell_key] is researchable by the character at
## [param target_level]. Used to validate research targets against the
## caster's accessible spell lists (per the Lightblessed dual-list rule and
## Q17 v1 constraint that research targets come from existing catalogs).
##
## Phase 10B.1g.1 (2026-05-11): rewritten to use
## SpellRegistry.get_available_spells_for_class, which walks both the base
## indexed list AND the per-spell `restricted_to` array. The earlier helper
## used only get_spells_for_list (base list only) and would miss class-
## specific spells declared via `restricted_to` (e.g., spells unique to
## Witch / Priestess / Shaman are in the catalog but not the base
## divine_cleric indexed list).
##
## For Lightblessed Wonderworker: get_class_spell_list_id returns the
## list_id of the FIRST casting power found, so the class-aware lookup
## sees only one list. We still iterate the full `_researchable_spell_lists_for`
## set to ensure both arcane and divine_cleric are checked; for each list
## we synthesize a sentinel class_id query via get_spells_for_list (which
## returns the base indexed list) AND for the caster's primary class we
## also check get_available_spells_for_class (which adds the restricted_to
## additions).
static func _is_spell_on_research_list(
	character: Dictionary,
	spell_key: String,
	target_level: int,
	list_ids: Array[String],
) -> bool:
	if spell_key.is_empty() or target_level <= 0:
		return false
	var spell_registry := _get_spell_registry()
	var class_registry := _get_class_registry()
	# (1) Check each list's base indexed entries.
	for list_id in list_ids:
		var spells: Array[String] = spell_registry.get_spells_for_list(list_id, target_level)
		if spell_key in spells:
			return true
	# (2) Also check the caster's class-restricted additions (the
	# `restricted_to` mechanism in spell_catalog.json). This is the path
	# that surfaces spells unique to Witch / Priestess / Shaman /
	# Bladedancer that aren't on the base indexed list. For arcane casters
	# this lookup is a no-op (arcane spells don't currently use
	# restricted_to); for divine casters it's the actual filter.
	var class_id: String = String(character.get("character_class", ""))
	if not class_id.is_empty():
		var per_class: Array[String] = spell_registry.get_available_spells_for_class(
			class_id, target_level, class_registry)
		if spell_key in per_class:
			return true
	return false


static func _get_magical_engineering_rank(character_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(MAX(rank), 0) AS max_rank
		FROM character_proficiencies
		WHERE character_id = ? AND proficiency_key = 'magical_engineering'
	""", [character_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("max_rank", 0))


# ---------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------

static func _add_spell_to_formulas_and_repertoire(
	character_id: String, spell_key: String, spell_level: int,
) -> void:
	# Add to formulas (UNIQUE on character_id + spell_key, so duplicates no-op).
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO character_spell_formulas
			(character_id, spell_key, spell_level)
		VALUES (?, ?, ?)
	""", [character_id, spell_key, spell_level])
	# Add to active repertoire (character_spells). Skip if already present.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM character_spells
		WHERE character_id = ? AND spell_key = ?
		LIMIT 1
	""", [character_id, spell_key]):
		return
	if CampaignRepository.db.query_result.is_empty():
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO character_spells
				(character_id, spell_key, spell_level, is_memorized, is_in_repertoire, memorized_slots)
			VALUES (?, ?, ?, 0, 1, 0)
		""", [character_id, spell_key, spell_level])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _get_character(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ? LIMIT 1", [character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get("params_json", "{}")
	if raw is Dictionary:
		return raw
	if not (raw is String):
		return {}
	var parsed: Variant = JSON.parse_string(raw as String)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day


# ---------------------------------------------------------------------------
# Singleton caches (mirror ClassBucketResolver pattern)
# ---------------------------------------------------------------------------

static var _class_registry_cache: ClassRegistry = null
static var _spell_registry_cache: SpellRegistry = null
static var _equipment_catalog_cache: EquipmentCatalog = null


static func _get_class_registry() -> ClassRegistry:
	if _class_registry_cache == null:
		_class_registry_cache = ClassRegistry.new()
	return _class_registry_cache


static func _get_spell_registry() -> SpellRegistry:
	if _spell_registry_cache == null:
		_spell_registry_cache = SpellRegistry.new()
	return _spell_registry_cache


static func _get_equipment_catalog() -> EquipmentCatalog:
	if _equipment_catalog_cache == null:
		_equipment_catalog_cache = EquipmentCatalog.new()
	return _equipment_catalog_cache
