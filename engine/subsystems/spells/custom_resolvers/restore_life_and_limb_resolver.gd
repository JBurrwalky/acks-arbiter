class_name RestoreLifeAndLimbResolver
extends RefCounted

## Restore Life and Limb (Divine L5, reversible to Finger of Death).
##
## ACKS RAW (rules/acore_spell_catalog_k-w_summary.xml:669-707):
##   Range: touch (120')   Duration: instantaneous
##   Valid targets: deceased creature truly alive.
##   Invalid targets: constructs, elementals, undead, and other creatures
##     not truly alive.
##   Effects:
##     - Restores life to the dead and repairs permanent bodily damage.
##     - Raises a creature dead no longer than 2 days at 7th level, plus
##       4 additional days per level above 7th.
##     - Repairs lethal damage and permanent wounds such as lost limbs,
##       disfiguring scars, and shattered spines.
##   Scaling: max time dead is 2 days at L7 and increases by 4 days per
##     caster level above 7th.
##   Limits: cannot restore creatures that died of old age, that lost
##     their head, or whose body was cremated.
##   Interactions:
##     - Each time a character benefits from this spell, roll on the
##       Tampering with Mortality table in Chapter 6 and apply the result.
##     - If cast on an undead monster, the monster must save versus Death
##       or be instantly destroyed.
##   Reversed form (Finger of Death):
##     - Creates a death ray against one creature.
##     - Save vs Death negates death.
##     - Lawful clerics may only use against Chaotic foes in life-or-death
##       situations (roleplay constraint, not enforced here).
##
## Energy drain interpretation (Jedidiah 2026-06-02 — per
## rules/ax_mortal_wounds_and_tampering.xml:387 "If a creature suffers a
## permanent wound, repair permanent wound, restore life and limb,
## regeneration, a ring of regeneration, or similar magic can heal the
## wound."): drained levels are a permanent wound of the life-force, so
## Restore Life and Limb clears the `is_energy_drained` flag from valid
## targets alongside its other wound-repair effects.
##
## V1 mechanically wired (this resolver):
##   - vs undead: save vs Death; on fail → `dispel_destroyed` condition
##     (proven destruction pattern, same as Dispel Evil).
##   - Energy drain clear: removes all `is_energy_drained` flag sources
##     from the target.
##   - Raise dead: if target.is_dead = true AND the days-dead-limit
##     accommodates the elapsed days, flip is_dead=false and restore
##     hp_current to 1. (Bed-rest recovery is the consumer's
##     responsibility — Tampering with Mortality `condition_table` says
##     "1 week of bed rest" or similar; recorded as
##     restoration_condition_outcome for the consumer.)
##   - Tampering with Mortality d20 base + d6 column rolls are recorded
##     on per_target so the character-subsystem consumer can apply
##     modifiers (life span, spellcaster power, state of body, state of
##     soul) and look up the alignment-specific side-effect table.
##   - Permanent wound repair: recorded as
##     `permanent_wounds_repair_pending` for the character_subsystem
##     consumer to delete `character_permanent_wounds` rows.
##
## Deferred to follow-up subsystems:
##   - Tampering with Mortality table application (alignment-specific
##     side effects, modifier computation, multi-attempt -N penalties).
##     This resolver records the base d20 + d6 rolls; the runtime
##     character subsystem applies the modifiers and resolves the table.
##   - died-of-old-age / lost-head / cremated rejection (need wound-cause
##     tags on the death record).
##   - Bed-rest recovery scheduling (1 week / 2 weeks / 1 month per
##     condition_table outcome) — Timekeeping subsystem hook.
##   - Finger of Death "lawful cleric vs Chaotic foes" roleplay constraint.

const _DAYS_DEAD_AT_L7: int = 2
const _DAYS_DEAD_PER_LEVEL_ABOVE_7: int = 4


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var targets_by_id: Dictionary = args.get("targets_by_id", {})
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})
	# Tests inject a fake dice via resolver_args; production uses args.dice
	# (forwarded from CastingResolver._dispatch_custom).
	var dice = resolver_args.get("dice", args.get("dice", null))

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "restore_life_and_limb_resolver: missing context"}

	var is_reversed: bool = false
	if spell_choice != null and "is_reversed" in spell_choice:
		is_reversed = bool(spell_choice.is_reversed)
	# `forced_reversed: true` lets the standalone Finger of Death catalog
	# entry (shaman L5) route through the same death-ray branch even though
	# it isn't tagged as a reverse cast at the SpellChoice level.
	if bool(resolver_args.get("forced_reversed", false)):
		is_reversed = true

	# Finger of Death: simple save-vs-Death-or-die against one creature.
	if is_reversed:
		var fod_injected_current_day: int = int(
			resolver_args.get("current_day", -1))
		return _resolve_finger_of_death(
			caster_context, target_descriptor, targets_by_id, spell_choice,
			dice, fod_injected_current_day)

	# Restore Life and Limb forward form.
	var caster_level := int(caster_context.caster_level) if "caster_level" in caster_context else 9
	var days_dead_limit: int = max(
		_DAYS_DEAD_AT_L7,
		_DAYS_DEAD_AT_L7 + (caster_level - 7) * _DAYS_DEAD_PER_LEVEL_ABOVE_7)
	# Tests inject `current_day` via resolver_args to drive deterministic
	# days_dead computations without booting Timekeeping. Production resolvers
	# fall back to the live Timekeeping autoload via _get_current_day.
	var injected_current_day: int = int(resolver_args.get("current_day", -1))

	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		per_target[tid] = _resolve_single_target(
			entity, tid, caster_context, days_dead_limit, dice,
			injected_current_day)

	return {
		"applied": true,
		"per_target": per_target,
		"days_dead_limit_at_caster_level": days_dead_limit,
		"caster_id": caster_context.caster_id,
		"spell_key": (
			spell_choice.spell_key if spell_choice != null else "restore_life_and_limb"),
		"persist_metadata": {
			"days_dead_limit_at_caster_level": days_dead_limit,
		},
	}


# ---------------------------------------------------------------------------
# Forward form — per-target dispatch
# ---------------------------------------------------------------------------

func _resolve_single_target(
		entity: Variant,
		target_id: String,
		caster_context: Variant,
		days_dead_limit: int,
		dice: Variant,
		injected_current_day: int = -1) -> Dictionary:
	if entity == null:
		return {"applied": false, "reason": "target_not_found"}

	# Per RAW, vs-undead branch: save vs Death or be destroyed.
	if _is_undead(entity):
		return _resolve_vs_undead(entity, target_id, caster_context, dice)

	# Per RAW, invalid targets: constructs, elementals, other not-truly-alive.
	if _is_invalid_target_kind(entity):
		return {
			"applied": false,
			"reason": "invalid_target_kind",
			"target_id": target_id,
		}

	# Per RAW limits: cannot restore creatures that died of old age, lost
	# their head, or were cremated. Migration 142 (2026-06-02) adds the
	# death_cause column; the resolver consults it before applying any
	# restoration steps.
	if entity != null and "death_cause" in entity:
		var death_cause: String = String(entity.death_cause)
		if death_cause in REJECTED_DEATH_CAUSES:
			return {
				"applied": false,
				"reason": "death_cause_rejected",
				"death_cause": death_cause,
				"target_id": target_id,
			}

	# Valid living/deceased target — apply the restoration bundle.
	var outcome: Dictionary = {
		"applied": true,
		"target_id": target_id,
		"energy_drain_cleared": false,
		"raised_from_death": false,
		"permanent_wounds_repair_pending": true,
		"tampering_with_mortality_pending": true,
	}

	# (A) Energy drain reversal — clear all is_energy_drained sources.
	if _has_energy_drain(entity):
		_clear_energy_drain(entity)
		outcome["energy_drain_cleared"] = true

	# (B) Raise dead — if the target is dead AND within the days_dead_limit.
	# Migration 142 adds day_of_death tracking; if the entity has a recorded
	# day_of_death, the resolver computes days_dead and gates on the limit.
	# If day_of_death = -1 (untracked, e.g. pre-migration save), we fall
	# back to the V1 "assume within window" behavior so legacy data still
	# raises (RAW gate becomes advisory in that case).
	var was_dead: bool = false
	if entity != null and "is_dead" in entity:
		was_dead = bool(entity.is_dead)
	outcome["was_dead"] = was_dead
	if was_dead:
		var current_day: int = (
			injected_current_day if injected_current_day >= 0
			else _get_current_day(entity, caster_context))
		var days_dead: int = -1
		if entity != null and "day_of_death" in entity \
				and int(entity.day_of_death) >= 0 and current_day >= 0:
			days_dead = current_day - int(entity.day_of_death)
			outcome["days_dead"] = days_dead
		if days_dead >= 0 and days_dead > days_dead_limit:
			# Outside the RAW window — restoration fails.
			outcome["raised_from_death"] = false
			outcome["days_dead_limit_applied"] = days_dead_limit
			outcome["applied"] = false
			outcome["reason"] = "exceeded_days_dead_limit"
			return outcome
		_raise_from_death(entity)
		outcome["raised_from_death"] = true
		outcome["days_dead_limit_applied"] = days_dead_limit

	# (C) Tampering with Mortality — roll the base d20 + d6, then resolve
	# the structured outcome (modifiers + condition_table + alignment-
	# specific side effect) via TamperingWithMortalityResolver. The
	# raw rolls remain available on per_target for the consumer; the
	# resolved outcome is stamped under `tampering_outcome` for the
	# character-subsystem consumer (bed-rest scheduling, side-effect
	# application) to read directly.
	var twm: Dictionary = _roll_tampering_with_mortality(dice)
	outcome["tampering_with_mortality_d20"] = twm.get("d20", 0)
	outcome["tampering_with_mortality_d6"] = twm.get("d6", 0)
	var twm_ctx: Dictionary = _build_tampering_ctx(entity, caster_context, twm, outcome)
	outcome["tampering_outcome"] = TamperingWithMortalityResolver.resolve_tampering(twm_ctx)

	return outcome


## Build the modifier-context dict for TamperingWithMortalityResolver.
## Reads from the entity (age_category, death_cause, wisdom, alignment)
## and the caster (caster_level). `outcome` is the per_target dict that
## already carries the days_dead computed above.
func _build_tampering_ctx(
		entity: Variant,
		caster_context: Variant,
		twm_rolls: Dictionary,
		outcome: Dictionary) -> Dictionary:
	var ctx: Dictionary = {
		"d20_raw": twm_rolls.get("d20", 0),
		"d6_raw": twm_rolls.get("d6", 0),
		"days_dead": int(outcome.get("days_dead", 0)),
	}
	if entity != null:
		if "age_category" in entity:
			ctx["age_category"] = String(entity.age_category)
		if "death_cause" in entity:
			ctx["death_cause"] = String(entity.death_cause)
		if "wisdom" in entity:
			ctx["wisdom"] = int(entity.wisdom)
		if "alignment" in entity:
			ctx["alignment"] = String(entity.alignment)
	if caster_context != null and "caster_level" in caster_context:
		ctx["caster_level"] = int(caster_context.caster_level)
	return ctx


# Death causes per RAW that cannot be restored. Defined alongside Migration 142.
const REJECTED_DEATH_CAUSES: Array = [
	"old_age", "lost_head", "cremated", "disintegrated",
]


## Reads the current absolute day from Timekeeping (autoload) for the
## days_dead computation. Falls back to -1 (untracked) when Timekeeping
## is unavailable (test harnesses without the autoload).
func _get_current_day(_entity: Variant, _caster_context: Variant) -> int:
	# Timekeeping is an autoload; access via Engine.get_singleton when
	# running outside SceneTree (tests without autoloads).
	if Engine.has_singleton("Timekeeping"):
		var tk = Engine.get_singleton("Timekeeping")
		if tk != null and tk.has_method("get_total_days"):
			return int(tk.get_total_days())
	# Direct access — works when the autoload is registered in the
	# running SceneTree.
	if ClassDB.class_exists("Timekeeping"):
		pass  # autoloads are not in ClassDB; fall through to direct ref
	# Try the global-scope autoload identifier. If not present in test
	# context, returns -1.
	var tk_global = _try_global_timekeeping()
	if tk_global != null:
		return int(tk_global.get_total_days())
	return -1


func _try_global_timekeeping() -> Variant:
	# Look up Timekeeping through Engine.get_main_loop() since the
	# resolver isn't a Node and can't traverse the scene tree directly.
	var loop := Engine.get_main_loop()
	if loop == null:
		return null
	if loop is SceneTree:
		var root = (loop as SceneTree).root
		if root != null and root.has_node("Timekeeping"):
			return root.get_node("Timekeeping")
	return null


# ---------------------------------------------------------------------------
# Forward form — vs-undead destruction branch
# ---------------------------------------------------------------------------

func _resolve_vs_undead(
		entity: Variant,
		target_id: String,
		caster_context: Variant,
		dice: Variant) -> Dictionary:
	var save_target: int = 17
	if entity != null and entity.has_method("get_effective_save"):
		save_target = int(entity.get_effective_save("save_poison_death"))
	var roll: int = 17
	if dice != null:
		var r = dice.roll_digital(20, 1, 0, "spell_save_restore_life_and_limb_vs_undead")
		roll = int(r.modified_total) if r != null else 0
	var saved: bool = roll >= save_target
	if not saved:
		if entity != null and entity.has_method("add_condition"):
			entity.add_condition("dispel_destroyed")
		return {
			"applied": true,
			"target_id": target_id,
			"outcome": "destroyed_as_undead",
			"save_roll": roll,
			"save_target": save_target,
		}
	return {
		"applied": true,
		"target_id": target_id,
		"outcome": "undead_saved",
		"save_roll": roll,
		"save_target": save_target,
	}


# ---------------------------------------------------------------------------
# Reverse form — Finger of Death
# ---------------------------------------------------------------------------

func _resolve_finger_of_death(
		caster_context: Variant,
		target_descriptor: Variant,
		targets_by_id: Dictionary,
		spell_choice: Variant,
		dice: Variant,
		injected_current_day: int = -1) -> Dictionary:
	# Per RAW limit: "Lawful clerics may only use finger of death in
	# life-or-death situations against Chaotic foes." This is a roleplay
	# (alignment) constraint, not a mechanical block — Lawful clerics
	# CAN cast it, but doing so against a non-Chaotic target violates
	# their alignment vow and should weigh on tampering / divine favor.
	# We record the violation on per_target so the LLM narration layer
	# (and any future divine-favor / alignment-tracker subsystem) can act.
	var caster_alignment: String = ""
	if caster_context != null and "alignment" in caster_context:
		caster_alignment = String(caster_context.alignment).to_lower()
	var caster_class: String = ""
	if caster_context != null and "caster_class" in caster_context:
		caster_class = String(caster_context.caster_class).to_lower()
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		if entity == null:
			per_target[tid] = {"applied": false, "reason": "target_not_found"}
			continue
		# Scarab of Protection consumer (2026-06-03). Per RAW ACKS Core
		# p.215+: "Possessor gains immunity to any curse and finger of
		# death spells or effects, regardless of source. Upon absorbing
		# 2d6 such attacks, the scarab turns to powder and is destroyed."
		# Scarab fires BEFORE the save (RAW grants immunity, no save
		# rolled), consumes a charge, and (when charges hit 0) destroys
		# the scarab item via inventory_items deletion. The roleplay
		# violation check still fires — the FoD attempt happened, even
		# though absorbed.
		var scarab: Dictionary = _scarab_negate(entity, tid)
		if bool(scarab.get("negated", false)):
			var negated_outcome: Dictionary = {
				"applied": true,
				"target_id": tid,
				"outcome": "negated_by_scarab",
				"scarab_charges_remaining": int(scarab.get("charges_remaining", 0)),
				"scarab_destroyed": bool(scarab.get("destroyed", false)),
				"scarab_item_id": String(scarab.get("item_id", "")),
			}
			var rv: String = _check_finger_of_death_violation(
				caster_alignment, caster_class, entity)
			if not rv.is_empty():
				negated_outcome["roleplay_violation"] = rv
			per_target[tid] = negated_outcome
			continue
		var save_target: int = 17
		if entity.has_method("get_effective_save"):
			save_target = int(entity.get_effective_save("save_poison_death"))
		var roll: int = 17
		if dice != null:
			var r = dice.roll_digital(20, 1, 0, "spell_save_finger_of_death")
			roll = int(r.modified_total) if r != null else 0
		var saved: bool = roll >= save_target
		var roleplay_violation: String = _check_finger_of_death_violation(
			caster_alignment, caster_class, entity)
		var per_t_outcome: Dictionary = {}
		if saved:
			per_t_outcome = {
				"applied": true,
				"target_id": tid,
				"outcome": "saved",
				"save_roll": roll,
				"save_target": save_target,
			}
		else:
			# Slay the target. Apply hp_current = 0 + set is_dead = true if
			# the entity has those fields.
			if "is_dead" in entity:
				entity.is_dead = true
			# Migration 142: stamp death_cause + day_of_death so the slain
			# target cannot be restored by Restore Life and Limb without
			# matching the days-dead-limit window. (Lawful-cleric Finger of
			# Death victims who manage to be raised quickly still go through
			# the days_dead_limit + death_cause checks.)
			if "death_cause" in entity:
				entity.death_cause = "combat"
			if "day_of_death" in entity:
				entity.day_of_death = (
					injected_current_day if injected_current_day >= 0
					else _get_current_day(entity, caster_context))
			if "hp_current" in entity:
				entity.hp_current = 0
			if entity.has_method("add_condition"):
				entity.add_condition("dispel_destroyed")
			per_t_outcome = {
				"applied": true,
				"target_id": tid,
				"outcome": "slain_by_death_ray",
				"save_roll": roll,
				"save_target": save_target,
			}
		if not roleplay_violation.is_empty():
			per_t_outcome["roleplay_violation"] = roleplay_violation
		per_target[tid] = per_t_outcome
	return {
		"applied": true,
		"per_target": per_target,
		"caster_id": caster_context.caster_id,
		"spell_key": (
			spell_choice.spell_key if spell_choice != null else "finger_of_death"),
		"is_reversed": true,
	}


## Detects RAW alignment violations on Finger of Death casts. Records:
##   - "lawful_finger_of_death_vs_non_chaotic" when a Lawful cleric/shaman
##     casts FoD against a Lawful or Neutral target.
## Returns "" when no violation.
func _check_finger_of_death_violation(
		caster_alignment: String,
		caster_class: String,
		target: Variant) -> String:
	# RAW gates this on Lawful clerics specifically. The shaman class is
	# divine-tradition (carries FoD as its restricted L5), so we apply the
	# same vow if the shaman is Lawful. Mages don't have the spell list
	# access RAW gives Lawful-clerics a vow about, so they pass.
	if caster_alignment != "lawful":
		return ""
	if caster_class not in ["cleric", "shaman", "paladin", "bishop", "priestess"]:
		return ""
	var target_alignment: String = _get_target_alignment(target)
	if target_alignment == "chaotic":
		return ""
	return "lawful_finger_of_death_vs_non_chaotic"


func _get_target_alignment(target: Variant) -> String:
	if target == null:
		return ""
	if "alignment" in target:
		return String(target.alignment).to_lower()
	if target.has_method("get_alignment"):
		return String(target.get_alignment()).to_lower()
	return ""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _is_undead(entity: Variant) -> bool:
	if entity == null:
		return false
	# Combatant has is_creature_type() helper (added in magic-swords session).
	if entity.has_method("is_creature_type"):
		return bool(entity.is_creature_type("undead"))
	# CharacterData fallback: check 'creature_type' or 'tags' for "undead".
	if "creature_type" in entity and String(entity.creature_type).to_lower() == "undead":
		return true
	if "tags" in entity:
		var tags = entity.tags
		if tags is Array and "undead" in tags:
			return true
	return false


func _is_invalid_target_kind(entity: Variant) -> bool:
	if entity == null:
		return true
	# RAW: constructs, elementals, and other creatures not truly alive
	# are invalid. We check the helper if present; if not, default to
	# valid (most PCs / NPCs are flesh-and-blood and the target_spec
	# layer can pre-filter).
	if entity.has_method("is_creature_type"):
		if entity.is_creature_type("construct"):
			return true
		if entity.is_creature_type("elemental"):
			return true
		if entity.is_creature_type("not_truly_alive"):
			return true
	if "creature_type" in entity:
		var ck := String(entity.creature_type).to_lower()
		if ck in ["construct", "elemental"]:
			return true
	return false


func _has_energy_drain(entity: Variant) -> bool:
	var flags = _get_flags(entity)
	if flags == null:
		return false
	return flags.has_flag("is_energy_drained")


func _clear_energy_drain(entity: Variant) -> void:
	var flags = _get_flags(entity)
	if flags == null:
		return
	# Clear ALL sources of is_energy_drained — RAW restores the wound
	# regardless of which monster / sword inflicted the drain.
	for source_id in flags.get_flag_sources("is_energy_drained"):
		flags.clear_flag("is_energy_drained", source_id)
	# 2026-06-02 — PC consumer cleanup: refresh modifiers so the attack/save
	# penalties cleared with the flag. Idempotent: with the flag now empty,
	# refresh_modifiers removes all `energy_drain:` modifier entries.
	if entity is CharacterData:
		EnergyDrainConsumer.refresh_modifiers(entity)


func _get_flags(entity: Variant) -> EntityFlags:
	if entity == null:
		return null
	if entity.has_method("get_flags"):
		var f = entity.get_flags()
		if f is EntityFlags:
			return f
	if "flags" in entity and entity.flags is EntityFlags:
		return entity.flags
	return null


func _raise_from_death(entity: Variant) -> void:
	if entity == null:
		return
	if "is_dead" in entity:
		entity.is_dead = false
	if "hp_current" in entity:
		entity.hp_current = max(1, int(entity.hp_current))
	# Note: Tampering with Mortality condition_table side-effect (bed rest)
	# is the consumer's responsibility; this resolver records the base
	# d20+d6 rolls on per_target so the consumer can apply modifiers.


func _roll_tampering_with_mortality(dice: Variant) -> Dictionary:
	# Base d20 + d6 per ax_mortal_wounds_and_tampering.xml:390.
	# Modifiers (life span, spellcaster power, state of body, state of
	# soul) are applied by the consumer because they need entity-specific
	# context (age band, alignment, instantly_killed flag, side effects
	# already suffered) that the resolver shouldn't pull mid-step.
	var d20_raw: int = 10
	var d6_raw: int = 3
	if dice != null:
		var r20 = dice.roll_digital(20, 1, 0, "spell_tampering_with_mortality_d20")
		if r20 != null:
			d20_raw = int(r20.modified_total)
		var r6 = dice.roll_digital(6, 1, 0, "spell_tampering_with_mortality_d6")
		if r6 != null:
			d6_raw = int(r6.modified_total)
	return {"d20": d20_raw, "d6": d6_raw}



## Scarab of Protection consumer (2026-06-03). Per RAW ACKS Core p.215+
## (Jedidiah-supplied 2026-06-02): "Possessor gains immunity to any
## curse and finger of death spells or effects, regardless of source.
## Upon absorbing 2d6 such attacks, the scarab turns to powder and is
## destroyed."
##
## Returns:
##   {"negated": true, "charges_remaining": int, "destroyed": bool,
##    "item_id": String}   when the target carries a scarab with charges
##   {"negated": false}    when no scarab or charges exhausted
##
## Side effects on negation:
##   - Decrements the flag metadata's charges_remaining.
##   - Decrements the inventory_items.uses_remaining via
##     CampaignRepository (when available); silently no-op in test
##     contexts where the autoload isn't wired.
##   - At 0 charges, deletes the inventory item ("turns to powder").
##     The flag will clear naturally on the next WornMagicEffectResolver
##     refresh once the row is gone.
func _scarab_negate(entity: Variant, _target_id: String) -> Dictionary:
	var flags: EntityFlags = _get_flags(entity)
	if flags == null or not flags.has_flag("has_scarab_of_protection"):
		return {"negated": false}
	# Pull the source entry — V1 doesn't support multiple scarabs on the
	# same wearer, so we operate on the first source.
	var sources: Array = flags.get_flag_source_entries("has_scarab_of_protection")
	if sources.is_empty():
		return {"negated": false}
	var entry: Dictionary = sources[0]
	var meta: Dictionary = entry.get("metadata", {})
	var current: int = int(meta.get("charges_remaining", 0))
	if current <= 0:
		# Scarab present but exhausted — no immunity. The flag stays
		# until next refresh clears it (the item row was already removed
		# at the prior 0-charge negation).
		return {"negated": false}
	var item_id: String = String(meta.get("item_id", ""))
	var source_id: String = String(entry.get("source_id", ""))
	var charges_after: int = current - 1
	# Update the flag metadata in place.
	meta["charges_remaining"] = charges_after
	flags.set_flag("has_scarab_of_protection", source_id, meta)
	var destroyed: bool = (charges_after <= 0)
	# Persist the inventory row change so the charge survives save/load
	# and so the next WornMagicEffectResolver refresh sees the new
	# uses_remaining. Skip silently when CampaignRepository / db are
	# unavailable (unit tests of the resolver without DB setup).
	if not item_id.is_empty() and CampaignRepository != null \
			and CampaignRepository.db != null:
		if destroyed:
			# RAW: scarab "turns to powder and is destroyed." Remove the
			# inventory row entirely. The flag will clear on the next
			# worn-magic refresh because the item is gone.
			CampaignRepository.remove_inventory_item(item_id)
		else:
			CampaignRepository.db.query_with_bindings(
				"UPDATE inventory_items SET uses_remaining = ? WHERE id = ?",
				[charges_after, item_id])
	return {
		"negated": true,
		"charges_remaining": charges_after,
		"destroyed": destroyed,
		"item_id": item_id,
	}
