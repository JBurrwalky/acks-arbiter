class_name CastingResolver
extends RefCounted

## Deterministic spell resolution pipeline. Reads the active branch's effect
## payload from SpellEffectRegistry, walks the `resolution: [...]` step array,
## and applies mechanical mutations to the caster + targets. Returns a
## ResolutionResult that the UI / narration / log layers consume.
##
## Session 1 covers DSL pipeline stages 4 (validation), 7 (resolution), 8
## (slot expenditure), 9 (effect registration), 10 (event emission). Stages 1
## (selection), 2 (target picking), 3 (range/AoE preview) live in Session 2's
## UI work. Stage 11 (out-of-combat 10s + encounter check) lives in Session 3.
##
## ACKS rule: a slot is consumed for a *disrupted* cast (declared then broken
## by damage/save-fail) but NOT for a cast that never started (validation
## failure: unknown spell, no effect bound, missing disjunctive branch, etc.).
##
## The resolver is RefCounted, not an autoload (class_name forbidden on
## autoloads). SessionRunner constructs one with the active session's
## registries.

var _spell_registry: SpellRegistry = null
var _effect_registry: SpellEffectRegistry = null
## Access to the underlying tracker for combat-loop ticking. CombatController
## reads this in _end_round to call tick_rounds(1); other surfaces (the
## scheduler for out-of-combat turn/hour/day cadences) tick via separate calls.
var _effect_tracker: ActiveEffectTracker = null
var _condition_catalog = null  # ConditionCatalog
var _custom_resolvers: CustomResolverRegistry = null
var _geometry = null  # CastingGeometry — passed for testability; uses statics
var _campaign_repo = null  # CampaignRepository
var _dice_system = null  # DiceSystem autoload


func _init(
		spell_registry: SpellRegistry,
		effect_registry: SpellEffectRegistry,
		effect_tracker: ActiveEffectTracker,
		condition_catalog,
		custom_resolvers: CustomResolverRegistry,
		geometry,
		campaign_repo,
		dice_system) -> void:
	_spell_registry = spell_registry
	_effect_registry = effect_registry
	_effect_tracker = effect_tracker
	_condition_catalog = condition_catalog
	_custom_resolvers = custom_resolvers
	_geometry = geometry
	_campaign_repo = campaign_repo
	_dice_system = dice_system


func get_effect_tracker() -> ActiveEffectTracker:
	## Public accessor for the tracker. Combat / scheduler surfaces call
	## `tick_and_cleanup` (preferred) or tick the tracker directly.
	return _effect_tracker


func get_spell_registry() -> SpellRegistry:
	## Public accessor for UI surfaces (DeclarationOverlay, SpellPickerPanel)
	## that need to look up spell metadata.
	return _spell_registry


func get_effect_registry() -> SpellEffectRegistry:
	## Public accessor for UI surfaces that need to query effect payloads
	## (e.g., SpellPickerPanel filtering rows by target_spec.kind).
	return _effect_registry


func tick_and_cleanup(unit: String, n: int, target_lookup: Callable) -> Array:
	## Tick `n` units of duration on the given bucket ("rounds" / "turns" /
	## "hours" / "days") and unwind state on every expired effect's targets.
	## `target_lookup(character_id) -> Variant` returns the live entity (or
	## null) so per-target cleanup can run.
	##
	## Returns an Array of expired effect Dictionaries, in the order they
	## expired. Caller can use this to emit log entries or fire UI updates.
	if _effect_tracker == null:
		return []
	# Snapshot effects matching the bucket BEFORE ticking, so we can capture
	# their modifier/flag/condition records before tick_* removes them.
	var pre_tick: Dictionary = {}  # effect_id -> effect dict
	for effect_dict in _effect_tracker.get_all_effects():
		if String(effect_dict.get("duration_type", "")) == unit:
			pre_tick[String(effect_dict.get("effect_id", ""))] = effect_dict
	var expired_ids: Array = []
	match unit:
		"rounds": expired_ids = _effect_tracker.tick_rounds(n)
		"turns":  expired_ids = _effect_tracker.tick_turns(n)
		"hours":  expired_ids = _effect_tracker.tick_hours(n)
		"days":   expired_ids = _effect_tracker.tick_days(n)
	var expired_effects: Array = []
	for eid_v in expired_ids:
		var eid := String(eid_v)
		var snapshot: Dictionary = pre_tick.get(eid, {})
		if snapshot.is_empty():
			continue
		_unwind_effect_state(snapshot, target_lookup)
		EventBus.spell_effect_removed.emit(eid, String(snapshot.get("spell_key", "")))
		EventBus.active_effect_expired.emit("", eid)
		expired_effects.append(snapshot)
	return expired_effects


func _unwind_effect_state(effect: Dictionary, target_lookup: Callable) -> void:
	## Strip modifiers / flags / damage_resistances applied by `effect` from
	## each target's runtime state. Conditions are emitted as condition_changed
	## (applied=false) so the condition manager can untrack.
	for mod_rec in effect.get("applied_modifiers", []):
		var entity = _resolve_target_entity(mod_rec, target_lookup)
		var mods := _get_modifier_container(entity)
		if mods != null:
			mods.remove_all_from_source(String(mod_rec.get("source_id", "")))
	for flag_rec in effect.get("applied_flags", []):
		var entity = _resolve_target_entity(flag_rec, target_lookup)
		var flags := _get_flags(entity)
		if flags != null:
			flags.clear_flag(String(flag_rec.get("flag_key", "")), String(flag_rec.get("source_id", "")))
	for cond_rec in effect.get("applied_conditions", []):
		var tid: String = String(cond_rec.get("character_id", ""))
		var ckey: String = String(cond_rec.get("condition_key", ""))
		EventBus.condition_changed.emit(tid, {"condition": ckey, "applied": false})


func _resolve_target_entity(record: Dictionary, target_lookup: Callable) -> Variant:
	if not target_lookup.is_valid():
		return null
	var tid := String(record.get("character_id", ""))
	if tid.is_empty():
		return null
	return target_lookup.call(tid)


# ---------------------------------------------------------------------------
# Entity-type-agnostic accessors. Spell effects target either CharacterData
# (PCs/henchmen) or Combatant wrappers (combat-time spells include monsters).
# Both expose ModifierContainer / EntityFlags / DamageResistance, but via
# slightly different APIs:
#   CharacterData has fields:    modifiers, flags, damage_resistances
#   Combatant has methods:       get_modifiers(), get_flags(), get_damage_resistances()
# These helpers smooth that over so the resolver dispatches uniformly.
# ---------------------------------------------------------------------------

func _get_modifier_container(entity: Variant) -> ModifierContainer:
	if entity is CharacterData:
		return entity.modifiers
	if entity != null and entity.has_method("get_modifiers"):
		return entity.get_modifiers()
	return null


func _get_flags(entity: Variant) -> EntityFlags:
	if entity is CharacterData:
		return entity.flags
	if entity != null and entity.has_method("get_flags"):
		return entity.get_flags()
	return null


func _get_damage_resistances(entity: Variant) -> DamageResistance:
	if entity is CharacterData:
		return entity.damage_resistances
	if entity != null and entity.has_method("get_damage_resistances"):
		return entity.get_damage_resistances()
	return null


func _entity_apply_condition(entity: Variant, condition_key: String) -> bool:
	## Returns true if the condition was registered on the entity. CharacterData
	## has no condition tracking; only Combatant does (which uses
	## CombatConditionManager's apply_condition for full tracking).
	if entity == null:
		return false
	if entity.has_method("add_condition"):
		entity.add_condition(condition_key)
		return true
	return false


# ---------------------------------------------------------------------------
# Public — main entry
# ---------------------------------------------------------------------------

func resolve(
		caster_context: CasterContext,
		spell_choice: SpellChoice,
		target_descriptor: TargetDescriptor,
		caster_entity: Variant = null,
		targets_by_id: Dictionary = {}) -> ResolutionResult:
	## Entry point. `caster_entity` is the live CharacterData (or dict) for
	## self/touch_creature spells that mutate the caster. `targets_by_id` maps
	## target_id (from target_descriptor.target_ids) to the live entity for
	## mutation. Tests pass these directly; UI layer constructs them from the
	## party + roster lookup.
	var result := ResolutionResult.new()

	# --- Stage 4: validation ---
	if _spell_registry == null or not _spell_registry.has_spell(spell_choice.spell_key):
		result.success = false
		result.slot_consumed = false
		result.failures.append("unknown spell_key: %s" % spell_choice.spell_key)
		return result

	if not _effect_registry.has_effect(spell_choice.spell_key):
		result.success = false
		result.slot_consumed = false
		result.failures.append("spell not yet implemented: %s" % spell_choice.spell_key)
		return result

	var payload := _effect_registry.get_effect_payload(
		spell_choice.spell_key,
		spell_choice.is_reversed,
		spell_choice.chosen_disjunctive_index)
	if payload.is_empty():
		result.success = false
		result.slot_consumed = false
		result.failures.append("could not resolve effect payload")
		return result

	# Disjunctive branch must be chosen up front. The registry leaves a
	# disjunctive structure intact when disjunctive_index is out of range; we
	# detect that here and bounce.
	var target_spec: Dictionary = payload.get("target_spec", {})
	if target_spec.get("kind", "") == "disjunctive":
		result.success = false
		result.slot_consumed = false
		result.failures.append("disjunctive branch not chosen")
		return result

	# --- Stage 7: walk resolution steps ---
	var resolution_steps: Array = payload.get("resolution", [])
	var save_spec: Dictionary = payload.get("save_spec", {"category": "none"})

	# Pre-roll the save once per target (where applicable). save_results maps
	# target_id -> {rolled, succeeded}.
	var save_results: Dictionary = _roll_saves_for_targets(target_descriptor, targets_by_id, save_spec, caster_context)

	# Track step outcomes for the result + active_effect aggregation.
	var step_outcomes: Array = []
	var aggregated_modifiers: Array = []
	var aggregated_flags: Array = []
	var aggregated_conditions: Array = []
	var attack_hit_targets: Dictionary = {}  # target_id -> bool (set by attack_throw_vs_target)

	for step_raw in resolution_steps:
		if not (step_raw is Dictionary):
			continue
		var step: Dictionary = step_raw
		var kind: String = step.get("kind", "")
		var outcome: Dictionary = {}
		match kind:
			"damage":
				outcome = _apply_damage(step, target_descriptor, targets_by_id, save_spec, save_results, attack_hit_targets)
			"damage_per_level":
				outcome = _apply_damage_per_level(step, caster_context, target_descriptor, targets_by_id, save_spec, save_results)
			"heal":
				outcome = _apply_heal(step, target_descriptor, targets_by_id, caster_entity, caster_context)
			"heal_fixed":
				outcome = _apply_heal_fixed(step, target_descriptor, targets_by_id, caster_entity, caster_context)
			"apply_modifier":
				outcome = _apply_modifier(step, spell_choice, target_descriptor, targets_by_id, caster_entity, caster_context, save_results, save_spec)
				aggregated_modifiers.append_array(outcome.get("records", []))
			"apply_flag":
				outcome = _apply_flag(step, spell_choice, target_descriptor, targets_by_id, caster_entity, caster_context)
				aggregated_flags.append_array(outcome.get("records", []))
			"apply_condition":
				outcome = _apply_condition(step, target_descriptor, targets_by_id, save_results, save_spec)
				aggregated_conditions.append_array(outcome.get("records", []))
			"apply_damage_resistance":
				outcome = _apply_damage_resistance(step, spell_choice, target_descriptor, targets_by_id, caster_entity, caster_context)
			"grant_temp_hp":
				outcome = _grant_temp_hp(step, target_descriptor, targets_by_id, caster_entity)
			"grant_mirror_images":
				outcome = _grant_mirror_images(step, caster_context, caster_entity)
			"attack_throw_vs_target":
				outcome = _attack_throw_vs_target(step, caster_context, target_descriptor, targets_by_id, attack_hit_targets)
			"movement_mode_grant":
				outcome = _movement_mode_grant(step, target_descriptor, targets_by_id, caster_entity)
			"query_game_state":
				outcome = _query_game_state(step, caster_context, target_descriptor)
			"modify_cell_state":
				outcome = {"kind": kind, "applied": false, "reason": "deferred to Session 2 dungeon-grid wiring"}
			"spawn_entity":
				outcome = {"kind": kind, "applied": false, "reason": "deferred to per-spell custom resolver session"}
			"stub":
				outcome = {"kind": kind, "applied": false, "reason": step.get("reason", ""), "message": step.get("placeholder_message", "")}
			"custom":
				outcome = _dispatch_custom(step, caster_context, spell_choice, target_descriptor, targets_by_id, caster_entity)
			_:
				outcome = {"kind": kind, "applied": false, "reason": "unknown resolution step kind"}
		outcome["step_kind"] = kind
		step_outcomes.append(outcome)

	# --- Stage 8: slot expenditure (success path always consumes) ---
	if _campaign_repo != null:
		_campaign_repo.increment_expended_slot(caster_context.caster_id, spell_choice.level)
		var remaining := _compute_remaining_slots(caster_context.caster_id, spell_choice.level)
		EventBus.spell_slot_expended.emit(caster_context.caster_id, spell_choice.level, remaining)
	result.slot_consumed = true

	# --- Stage 9: register active_effect (non-instantaneous) ---
	var duration_model: Dictionary = payload.get("duration_model", {"kind": "instantaneous"})
	var duration_kind := String(duration_model.get("kind", "instantaneous"))
	if duration_kind != "instantaneous" and _effect_tracker != null:
		var effect_id := _make_effect_id(caster_context.caster_id, spell_choice.spell_key)
		var active_effect := _build_active_effect(
			effect_id,
			caster_context,
			spell_choice,
			target_descriptor,
			payload,
			duration_model,
			aggregated_modifiers,
			aggregated_flags,
			aggregated_conditions)
		_effect_tracker.add_effect(active_effect)
		result.active_effect_ids.append(effect_id)
		EventBus.spell_effect_applied.emit(effect_id, spell_choice.spell_key, target_descriptor.target_ids)

	# --- Stage 10: event emission ---
	EventBus.spell_cast.emit(
		caster_context.caster_id,
		spell_choice.spell_key,
		target_descriptor.target_ids)

	result.success = true
	result.disrupted = false
	result.effects_applied = step_outcomes
	result.narration_payload = {
		"caster_id": caster_context.caster_id,
		"caster_name": caster_context.caster_name,
		"spell_key": spell_choice.spell_key,
		"is_reversed": spell_choice.is_reversed,
		"target_count": target_descriptor.target_ids.size(),
	}
	return result


# ---------------------------------------------------------------------------
# Disrupted-cast path — caller invokes when declared cast was broken.
# ---------------------------------------------------------------------------

func resolve_disrupted(
		caster_context: CasterContext,
		spell_choice: SpellChoice,
		reason: String) -> ResolutionResult:
	## Called when a declared cast is broken before resolution (damage taken,
	## save failed, silenced, etc.). Slot is still consumed per ACKS.
	var result := ResolutionResult.new()
	result.success = false
	result.disrupted = true
	result.failures.append("cast disrupted: %s" % reason)

	if _campaign_repo != null:
		_campaign_repo.increment_expended_slot(caster_context.caster_id, spell_choice.level)
		var remaining := _compute_remaining_slots(caster_context.caster_id, spell_choice.level)
		EventBus.spell_slot_expended.emit(caster_context.caster_id, spell_choice.level, remaining)
	result.slot_consumed = true

	EventBus.spell_interrupted.emit(caster_context.caster_id, spell_choice.spell_key)
	return result


# ---------------------------------------------------------------------------
# Per-step handlers
# ---------------------------------------------------------------------------

func _apply_damage(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		_save_spec: Dictionary,
		_save_results: Dictionary,
		attack_hit_targets: Dictionary) -> Dictionary:
	var dice_expr := String(step.get("dice", ""))
	var damage_type := String(step.get("damage_type", "untyped"))
	var on_hit_only := bool(step.get("on_hit_only", false))
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		if on_hit_only and not attack_hit_targets.get(tid, true):
			per_target[tid] = {"applied": false, "reason": "missed"}
			continue
		var roll = _dice_system.roll_expression(dice_expr, "spell_damage")
		var amount: int = int(roll.modified_total) if roll != null else 0
		_apply_damage_to_target(tid, targets_by_id, amount, damage_type, "spell")
		per_target[tid] = {"applied": true, "amount": amount}
	return {"per_target": per_target, "damage_type": damage_type}


func _apply_damage_per_level(
		step: Dictionary,
		caster_context: CasterContext,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		save_spec: Dictionary,
		save_results: Dictionary) -> Dictionary:
	var dice_per_level := String(step.get("dice_per_level", ""))
	var damage_type := String(step.get("damage_type", "untyped"))
	var max_level := int(step.get("max_level", 0))
	var effective_level := caster_context.caster_level
	if max_level > 0 and effective_level > max_level:
		effective_level = max_level

	# Magic Missile's missile-count formula is computed first; if present, we
	# roll the dice expression that many times rather than caster_level times.
	var per_count_spec: Dictionary = step.get("caster_level_to_missile_count", {})
	var roll_count := effective_level
	if per_count_spec.has("formula"):
		roll_count = _eval_level_formula(String(per_count_spec["formula"]), caster_context.caster_level)
		if roll_count < 0:
			roll_count = 0

	var on_save_half: bool = String(save_spec.get("on_success", "")) == "half_damage"
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var total_dmg: int = 0
		var rolls_log: Array = []
		for i in range(roll_count):
			var roll = _dice_system.roll_expression(dice_per_level, "spell_damage")
			var n := int(roll.modified_total) if roll != null else 0
			rolls_log.append(n)
			total_dmg += n
		var saved := bool((save_results.get(tid, {}) as Dictionary).get("succeeded", false))
		if saved and on_save_half:
			total_dmg = int(round(float(total_dmg) / 2.0))
		_apply_damage_to_target(tid, targets_by_id, total_dmg, damage_type, "spell")
		per_target[tid] = {"applied": true, "amount": total_dmg, "rolls": rolls_log, "saved": saved}
	return {"per_target": per_target, "damage_type": damage_type, "roll_count": roll_count}


func _apply_heal(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant,
		caster_context: CasterContext) -> Dictionary:
	var dice_expr := String(step.get("dice", ""))
	var per_target: Dictionary = {}
	for tid in _resolve_heal_target_ids(target_descriptor, caster_context):
		var entity = _resolve_entity(tid, targets_by_id, caster_entity, caster_context)
		var roll = _dice_system.roll_expression(dice_expr, "spell_healing")
		var amount: int = int(roll.modified_total) if roll != null else 0
		var actual: int = 0
		if entity != null and entity.has_method("apply_healing"):
			actual = int(entity.apply_healing(amount))
		EventBus.healing_applied.emit(tid, actual, "spell")
		per_target[tid] = {"applied": true, "rolled": amount, "actual": actual}
	return {"per_target": per_target}


func _apply_heal_fixed(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant,
		caster_context: CasterContext) -> Dictionary:
	var amount := int(step.get("amount", 0))
	var per_target: Dictionary = {}
	for tid in _resolve_heal_target_ids(target_descriptor, caster_context):
		var entity = _resolve_entity(tid, targets_by_id, caster_entity, caster_context)
		var actual: int = 0
		if entity != null and entity.has_method("apply_healing"):
			actual = int(entity.apply_healing(amount))
		EventBus.healing_applied.emit(tid, actual, "spell")
		per_target[tid] = {"applied": true, "actual": actual}
	return {"per_target": per_target}


func _apply_modifier(
		step: Dictionary,
		spell_choice: SpellChoice,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant,
		caster_context: CasterContext,
		save_results: Dictionary,
		save_spec: Dictionary) -> Dictionary:
	# `override_to: N` maps to ModifierStack `set_floor` semantics — sets the
	# stat to at least N if not already higher (matches Shield's "AC if better").
	# `value: N` maps to additive modifier with the given stacking_group.
	var attribute := String(step.get("attribute", ""))
	var stacking_group := String(step.get("stacking_group", ""))
	var override_to: Variant = step.get("override_to", null)
	var value: Variant = step.get("value", null)
	var on_save_negate: bool = String(save_spec.get("on_success", "")) == "negate"
	var per_target_save: bool = bool(save_spec.get("per_target", false))
	var records: Array = []
	var per_target: Dictionary = {}
	var source_id := _make_modifier_source_id(spell_choice.spell_key, caster_context.caster_id)
	for tid in target_descriptor.target_ids:
		# Per-target save-negates: skip targets whose save succeeded.
		if per_target_save and on_save_negate and bool((save_results.get(tid, {}) as Dictionary).get("succeeded", false)):
			per_target[tid] = {"applied": false, "reason": "saved"}
			continue
		var entity = _resolve_entity(tid, targets_by_id, caster_entity, caster_context)
		var mods := _get_modifier_container(entity)
		if mods == null:
			per_target[tid] = {"applied": false, "reason": "no_target_data"}
			continue
		var mod := {
			"source_id": source_id,
			"source_type": "spell",
			"stacking_group": stacking_group,
			"priority": 0,
		}
		if override_to != null:
			mod["operation"] = "set_floor"
			mod["value"] = override_to
		else:
			mod["operation"] = "add"
			mod["value"] = value if value != null else 0
		mods.add_modifier(attribute, mod)
		records.append({"character_id": tid, "stat_key": attribute, "source_id": source_id})
		per_target[tid] = {"applied": true, "stat_key": attribute, "operation": mod["operation"], "value": mod["value"]}
	return {"per_target": per_target, "records": records}


func _apply_flag(
		step: Dictionary,
		spell_choice: SpellChoice,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant,
		caster_context: CasterContext) -> Dictionary:
	var flag_key := String(step.get("flag_key", ""))
	var source_id := _make_modifier_source_id(spell_choice.spell_key, caster_context.caster_id)
	var records: Array = []
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = _resolve_entity(tid, targets_by_id, caster_entity, caster_context)
		var flags := _get_flags(entity)
		if flags == null:
			per_target[tid] = {"applied": false, "reason": "no_target_data"}
			continue
		flags.set_flag(flag_key, source_id, {})
		records.append({"character_id": tid, "flag_key": flag_key, "source_id": source_id})
		per_target[tid] = {"applied": true, "flag_key": flag_key}
	return {"per_target": per_target, "records": records}


func _apply_condition(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		save_results: Dictionary,
		save_spec: Dictionary) -> Dictionary:
	var condition_key := String(step.get("condition_key", ""))
	var on_save_negate: bool = String(save_spec.get("on_success", "")) == "negate"
	var records: Array = []
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		if on_save_negate and bool((save_results.get(tid, {}) as Dictionary).get("succeeded", false)):
			per_target[tid] = {"applied": false, "reason": "saved"}
			continue
		# Apply the condition to the entity if it supports condition tracking
		# (Combatants do; raw CharacterData doesn't track conditions itself).
		var entity = targets_by_id.get(tid, null)
		_entity_apply_condition(entity, condition_key)
		records.append({"character_id": tid, "condition_key": condition_key})
		EventBus.condition_changed.emit(tid, {"condition": condition_key, "applied": true})
		per_target[tid] = {"applied": true, "condition_key": condition_key}
	return {"per_target": per_target, "records": records}


func _apply_damage_resistance(
		step: Dictionary,
		spell_choice: SpellChoice,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant,
		caster_context: CasterContext) -> Dictionary:
	var damage_type := String(step.get("damage_type", ""))
	var mode := String(step.get("mode", "resistance"))
	var factor := float(step.get("factor", 0.5))
	var source_id := _make_modifier_source_id(spell_choice.spell_key, caster_context.caster_id)
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = _resolve_entity(tid, targets_by_id, caster_entity, caster_context)
		var dr := _get_damage_resistances(entity)
		if dr == null:
			per_target[tid] = {"applied": false, "reason": "no_target_data"}
			continue
		match mode:
			"immunity":
				dr.add_immunity(damage_type, source_id)
			"resistance":
				dr.add_resistance(damage_type, factor, source_id)
			"vulnerability":
				dr.add_vulnerability(damage_type, source_id)
		per_target[tid] = {"applied": true, "mode": mode, "damage_type": damage_type}
	return {"per_target": per_target}


func _grant_temp_hp(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant) -> Dictionary:
	var amount := int(step.get("amount", 0))
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = _resolve_entity(tid, targets_by_id, caster_entity, null)
		if entity != null and "temp_hp" in entity:
			entity.temp_hp = maxi(int(entity.temp_hp), amount)
		per_target[tid] = {"applied": true, "amount": amount}
	return {"per_target": per_target}


func _grant_mirror_images(
		step: Dictionary,
		caster_context: CasterContext,
		caster_entity: Variant) -> Dictionary:
	var count := int(step.get("count", 0))
	var per_level := int(step.get("count_per_level", 0))
	if per_level > 0:
		count += per_level * caster_context.caster_level
	if caster_entity != null and "mirror_images" in caster_entity:
		caster_entity.mirror_images = int(caster_entity.mirror_images) + count
	return {"applied": true, "count": count}


func _attack_throw_vs_target(
		step: Dictionary,
		caster_context: CasterContext,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		attack_hit_targets: Dictionary) -> Dictionary:
	var profile := String(step.get("attack_profile", "caster_as_fighter_of_caster_level"))
	var auto_hit := bool(step.get("auto_hit", false))
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		# `auto_hit` short-circuits the attack roll (Magic Missile-style).
		if auto_hit:
			attack_hit_targets[tid] = true
			per_target[tid] = {"applied": true, "auto_hit": true, "hit": true, "profile": profile}
			continue
		var entity = _resolve_entity(tid, targets_by_id, null, caster_context)
		# Per acore_combat fighter attack progression. Profile
		# "caster_as_fighter_of_caster_level" reads attack throw at
		# caster_level on the fighter table; future profiles can vary class.
		var target_ac := 0
		if entity != null and entity.has_method("get_effective_ac"):
			target_ac = int(entity.get_effective_ac())
		var attack_target := _approximate_fighter_attack_throw(caster_context.caster_level) + target_ac
		var roll = _dice_system.roll_digital(20, 1, 0, "spell_attack_throw")
		var hit := int(roll.modified_total) >= attack_target
		attack_hit_targets[tid] = hit
		per_target[tid] = {"applied": true, "roll": int(roll.modified_total), "target": attack_target, "hit": hit, "profile": profile}
	return {"per_target": per_target}


func _movement_mode_grant(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant) -> Dictionary:
	# Recorded on each target's ModifierContainer as a movement_rate adjustment
	# layered on top of the flag (so the flag enables the mode and the modifier
	# sets the rate). Source_id ties them together for cleanup.
	var rate_feet := int(step.get("rate_feet", 0))
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = _resolve_entity(tid, targets_by_id, caster_entity, null)
		if entity == null or not (entity is CharacterData):
			per_target[tid] = {"applied": false, "reason": "no_target_data"}
			continue
		# Don't add a stacking modifier — Fly typically replaces base movement.
		# We just record the rate in metadata on the active_effect; the actual
		# movement-rate consumer reads the flag + active_effect for the rate.
		per_target[tid] = {"applied": true, "rate_feet": rate_feet}
	return {"per_target": per_target, "rate_feet": rate_feet}


func _query_game_state(
		step: Dictionary,
		caster_context: CasterContext,
		_target_descriptor: TargetDescriptor) -> Dictionary:
	# Session 1 produces a structured query result without consulting any map
	# state; the consuming UI will fill in the actual aura list once the map
	# wiring lands. The resolver's job is to produce the contract.
	var query_kind := String(step.get("query_kind", ""))
	return {
		"applied": true,
		"query_kind": query_kind,
		"caster_id": caster_context.caster_id,
		"reveals": step.get("reveals", []),
		"response_format": step.get("response_format", ""),
		"results": [],
	}


func _dispatch_custom(
		step: Dictionary,
		caster_context: CasterContext,
		spell_choice: SpellChoice,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant) -> Dictionary:
	var resolver_id := String(step.get("resolver_id", ""))
	if not _custom_resolvers.has_resolver(resolver_id):
		return {"applied": false, "reason": "no custom resolver registered for '%s'" % resolver_id}
	var resolver := _custom_resolvers.get_resolver(resolver_id)
	var args: Dictionary = {
		"caster_context": caster_context,
		"spell_choice": spell_choice,
		"target_descriptor": target_descriptor,
		"targets_by_id": targets_by_id,
		"caster_entity": caster_entity,
		"step_payload": step,
	}
	if resolver.has_method("resolve"):
		return resolver.resolve(args)
	return {"applied": false, "reason": "custom resolver missing resolve()"}


# ---------------------------------------------------------------------------
# Save handling
# ---------------------------------------------------------------------------

func _roll_saves_for_targets(
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		save_spec: Dictionary,
		_caster_context: CasterContext) -> Dictionary:
	var category := String(save_spec.get("category", "none"))
	if category == "none":
		return {}
	var save_key := _save_category_to_key(category)
	if save_key.is_empty():
		return {}
	var modifier := int(save_spec.get("modifier", 0))
	var out: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		var target_value := 17  # safe default for entities without saves
		if entity != null and entity.has_method("get_effective_save"):
			target_value = int(entity.get_effective_save(save_key))
		var roll = _dice_system.roll_digital(20, 1, modifier, "spell_save_" + category)
		var roll_total := int(roll.modified_total) if roll != null else 0
		# ACKS save rules: roll d20 + modifier ≥ save target → success.
		var succeeded := roll_total >= target_value
		out[tid] = {"rolled": roll_total, "target": target_value, "succeeded": succeeded, "category": category}
	return out


func _save_category_to_key(category: String) -> String:
	match category:
		"blast":
			return "save_blast_breath"
		"poison_death":
			return "save_poison_death"
		"paralysis_petrification":
			return "save_petrification"
		"staffs_wands":
			return "save_staffs_wands"
		"spells":
			return "save_spells"
	return ""


# ---------------------------------------------------------------------------
# Active-effect construction
# ---------------------------------------------------------------------------

func _build_active_effect(
		effect_id: String,
		caster_context: CasterContext,
		spell_choice: SpellChoice,
		target_descriptor: TargetDescriptor,
		payload: Dictionary,
		duration_model: Dictionary,
		modifier_records: Array,
		flag_records: Array,
		condition_records: Array) -> Dictionary:
	var duration_type := _duration_kind_to_type(duration_model)
	var duration_remaining: int = _resolve_duration_amount(duration_model, caster_context.caster_level)
	var concentration_mode := String(duration_model.get("concentration_mode", "none"))
	var requires_concentration := 1 if concentration_mode != "none" else 0
	var effect_type := _infer_effect_type(payload, modifier_records, flag_records, condition_records)
	return {
		"effect_id": effect_id,
		"campaign_id": "",  # caller may set
		"spell_key": spell_choice.spell_key,
		"caster_id": caster_context.caster_id,
		"caster_level": caster_context.caster_level,
		"target_ids": target_descriptor.target_ids.duplicate(),
		"effect_type": effect_type,
		"applied_modifiers": modifier_records,
		"applied_conditions": condition_records,
		"applied_flags": flag_records,
		"duration_type": duration_type,
		"duration_remaining": duration_remaining,
		"requires_concentration": requires_concentration,
		"concentration_mode": concentration_mode,
		"is_active": 1,
		"metadata": {
			"is_reversed": spell_choice.is_reversed,
			"disjunctive_index": spell_choice.chosen_disjunctive_index,
		},
		"created_at_round": 0,
	}


func _duration_kind_to_type(duration_model: Dictionary) -> String:
	# Maps DSL `duration_model` to the active_effects.duration_type CHECK
	# domain ('rounds'|'turns'|'hours'|'days'|'permanent'|'concentration').
	# For `fixed` and `per_level` durations, the `unit` field carries the
	# bucket: Bless `unit: "turns"` ticks on turn cadence (every 60 rounds),
	# Magic Missile is instantaneous (caller skips this path), Fly's per_level
	# turns is 1 turn per level. Defaults to rounds when no unit is given.
	var kind := String(duration_model.get("kind", "fixed"))
	match kind:
		"concentration":
			return "concentration"
	var unit := String(duration_model.get("unit", "rounds"))
	match unit:
		"rounds", "turns", "hours", "days":
			return unit
		_:
			return "rounds"


func _resolve_duration_amount(duration_model: Dictionary, caster_level: int) -> int:
	var kind := String(duration_model.get("kind", "fixed"))
	var unit := String(duration_model.get("unit", "rounds"))
	var amount: int = 0
	if duration_model.has("amount"):
		amount = int(duration_model["amount"])
	elif duration_model.has("amount_formula"):
		var roll = _dice_system.roll_expression(String(duration_model["amount_formula"]), "spell_duration")
		amount = int(roll.modified_total) if roll != null else 0
	if kind == "per_level":
		amount *= caster_level
	# Convert duration to the caller's preferred unit. ActiveEffectTracker
	# tracks rounds/turns/hours/days as separate buckets; for v1 we store the
	# unit-native amount and mark the duration_type accordingly. Caller
	# infers duration_type from `unit`.
	return amount


func _infer_effect_type(
		_payload: Dictionary,
		modifier_records: Array,
		flag_records: Array,
		condition_records: Array) -> String:
	if not condition_records.is_empty():
		return "condition"
	if not flag_records.is_empty():
		return "flag"
	if not modifier_records.is_empty():
		return "modifier"
	return "instant"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _apply_damage_to_target(
		tid: String,
		targets_by_id: Dictionary,
		amount: int,
		damage_type: String,
		source_id: String) -> void:
	var entity = targets_by_id.get(tid, null)
	if entity == null:
		return
	var actual_amount: int = amount
	if entity.has_method("apply_damage"):
		var result = entity.apply_damage(amount, damage_type)
		if result is Dictionary:
			actual_amount = int(result.get("hp_damage", amount))
	EventBus.damage_dealt.emit(tid, actual_amount, damage_type, source_id)


func _resolve_heal_target_ids(target_descriptor: TargetDescriptor, caster_context: CasterContext) -> Array:
	# touch_ally with no explicit targets defaults to caster_id (self-cast).
	if target_descriptor.target_ids.is_empty():
		return [caster_context.caster_id]
	return target_descriptor.target_ids


func _resolve_entity(
		tid: String,
		targets_by_id: Dictionary,
		caster_entity: Variant,
		caster_context: Variant):
	if targets_by_id.has(tid):
		return targets_by_id[tid]
	if caster_context != null and caster_context is CasterContext and tid == caster_context.caster_id:
		return caster_entity
	return null


func _make_effect_id(caster_id: String, spell_key: String) -> String:
	# Stable-but-unique. Tests can predict the prefix; runtime uses ticks for
	# the suffix to avoid collisions on rapid casts.
	return "spell:%s:%s:%d" % [spell_key, caster_id, Time.get_ticks_usec()]


func _make_modifier_source_id(spell_key: String, caster_id: String) -> String:
	return "spell:%s:%s" % [spell_key, caster_id]


func _compute_remaining_slots(caster_id: String, level: int) -> int:
	## Returns the number of EXPENDED slots at `level` for this caster.
	## Convention: this is the count of slots used, not the count remaining —
	## the resolver doesn't know spells_per_day (which lives in class
	## progression tables, not the campaign repo). UI consumers compute
	## `total_slots_at_level - this_value` for the displayed "remaining" count.
	## The signal payload param is named `remaining_at_level` for historical
	## reasons (the GDD spec); v1 emits expended-count, callers interpret.
	var expended: Dictionary = _campaign_repo.get_expended_slots(caster_id) if _campaign_repo else {}
	return int(expended.get(level, 0))


func _approximate_fighter_attack_throw(level: int) -> int:
	# ACKS fighter attack throw progression from data/classes/fighter.json
	# attack_progression: 10, 9, 9, 8, 7, 7, 6, 5, 5, 4, 3, 3, 2, 1.
	# Used by `attack_throw_vs_target` for spells with `attack_profile:
	# "caster_as_fighter_of_caster_level"` (Cause Light Wounds, Cause Serious
	# Wounds, etc.). Reads via Combatant.get_class_registry() on demand.
	var class_registry: ClassRegistry = Combatant.get_class_registry()
	var clamped_level: int = clampi(level, 1, 14)
	var throw_value: int = class_registry.get_attack_throw("fighter", clamped_level)
	# get_attack_throw returns 0 if class/level missing; fall back to the
	# constant baseline for safety.
	if throw_value <= 0:
		return 10
	return throw_value


func _eval_level_formula(formula: String, level: int) -> int:
	# Safe-ish evaluator for caster_level → integer formulas. Uses Godot's
	# Expression class with `level` as the only allowed input variable.
	var expr := Expression.new()
	var err := expr.parse(formula, ["level"])
	if err != OK:
		push_error("CastingResolver._eval_level_formula: parse failed for '%s'" % formula)
		return 0
	var value = expr.execute([level])
	if expr.has_execute_failed():
		push_error("CastingResolver._eval_level_formula: execute failed for '%s'" % formula)
		return 0
	return int(value)
