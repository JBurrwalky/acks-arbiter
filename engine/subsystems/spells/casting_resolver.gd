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

## P6 — default target lookup used by the cleanup_callback path
## (concentration break + dispel). Combat layer / session runner sets this
## to a roster-based lookup before triggering the relevant signals. Falls
## back to a campaign_repo-based character lookup if unset.
var _default_target_lookup: Callable = Callable()


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
	# P6 — register as the tracker's cleanup callback so concentration break +
	# dispel paths route modifier/flag/condition unwinding through the same
	# code path as duration-tick expiry, plus emit spell_effect_removed and
	# invoke any per-spell expiration callback.
	if _effect_tracker != null:
		_effect_tracker.set_cleanup_callback(_on_tracker_removed_effect)


## Sets the default target lookup used by the tracker cleanup path. Combat
## controllers wire a roster-based lookup at combat start; out-of-combat
## consumers can install a campaign-repo lookup. Idempotent.
func set_default_target_lookup(lookup: Callable) -> void:
	_default_target_lookup = lookup


## ActiveEffectTracker cleanup callback. Invoked from the break_concentration
## and dispel_check paths BEFORE erasure with cause ∈
## {"concentration_broken", "dispelled"}. Unwinds modifier/flag/condition
## state via the standard `_unwind_effect_state` helper, fires
## spell_effect_removed, and invokes any per-spell expiration callback.
##
## Note: `active_effect_expired` is reserved for duration-tick expiry only,
## per the semantic distinction the design brief preserves. Subscribers
## treat spell_effect_removed as the universal "this effect ended" channel.
func _on_tracker_removed_effect(effect: Dictionary, cause: String) -> void:
	if effect.is_empty():
		return
	var lookup: Callable = _default_target_lookup if _default_target_lookup.is_valid() \
			else _build_fallback_target_lookup()
	_unwind_effect_state(effect, lookup)
	var eid := String(effect.get("effect_id", ""))
	var spell_key := String(effect.get("spell_key", ""))
	EventBus.spell_effect_removed.emit(eid, spell_key)
	if _custom_resolvers != null and _custom_resolvers.has_expiration_callback(spell_key):
		_custom_resolvers.invoke_expiration_callback(spell_key, effect, cause, lookup)


## Builds a Callable that resolves character_id → CharacterData via the
## campaign_repo. Used when no explicit lookup is set on the resolver
## (out-of-combat / scheduler contexts).
func _build_fallback_target_lookup() -> Callable:
	return func(tid: String) -> Variant:
		if _campaign_repo == null:
			return null
		if _campaign_repo.has_method("get_character"):
			return _campaign_repo.get_character(tid)
		return null


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
		var spell_key := String(snapshot.get("spell_key", ""))
		EventBus.spell_effect_removed.emit(eid, spell_key)
		EventBus.active_effect_expired.emit("", eid)
		# P6 — per-spell expiration callback (cause="duration_expired"). Concentration
		# break + dispel route through the tracker cleanup_callback above.
		if _custom_resolvers != null and _custom_resolvers.has_expiration_callback(spell_key):
			_custom_resolvers.invoke_expiration_callback(spell_key, snapshot, "duration_expired", target_lookup)
		expired_effects.append(snapshot)
	return expired_effects


func _unwind_effect_state(effect: Dictionary, target_lookup: Callable) -> void:
	## Strip modifiers / flags / damage_resistances applied by `effect` from
	## each target's runtime state. Conditions are emitted as condition_changed
	## (applied=false) so the condition manager can untrack. Side flips
	## (Charm side-flip introduced 2026-06-01) revert target.side to the
	## original_side recorded at apply time.
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
	# Side-flip revert (Charm side-flip, Tier 4 follow-up 2026-06-01).
	# Each record carries the original_side so cleanup can restore the
	# pre-charm allegiance. Targets that no longer exist (lookup returns
	# null) or no longer have a .side property no-op gracefully.
	for side_rec in effect.get("applied_side_flips", []):
		var entity = _resolve_target_entity(side_rec, target_lookup)
		if entity == null:
			continue
		if not ("side" in entity):
			continue
		var orig_side: int = int(side_rec.get("original_side", -1))
		if orig_side < 0:
			continue
		entity.side = orig_side


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
	# Phase 10B.3 #6: hard-block spellcasting if the caster has a wound that
	# prevents speech (RAW acore-campaign-hijinks.xml L354: tongue cut off —
	# "cannot speak, cast spells, use magic items, or use speech-based
	# proficiencies"). MW outcomes that destroy the tongue / jaw produce the
	# same wound_kind and thus the same block.
	if caster_context != null and not String(caster_context.caster_id).is_empty():
		var wound_agg: Dictionary = WoundEffectAggregator.compute(caster_context.caster_id)
		if bool(wound_agg.get("cannot_cast_spells", false)):
			result.success = false
			result.slot_consumed = false
			result.failures.append(
				"caster cannot cast spells (permanent wound: tongue/speech disabled)")
			return result

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

	# --- Stage 6: anti-magic / globe-of-invulnerability pre-resolve gates ---
	# Anti-Magic Shell (acore_spell_catalog_a-i_summary.xml: blocks spells +
	# spell-like effects entering/leaving the shell). Globe of Invulnerability
	# (pc_spell_catalog_f-u.xml: blocks spells of level ≤ N from penetrating).
	# Self-cast on the protected creature itself is NOT blocked per RAW.
	var blocked_targets: Array = _filter_targets_blocked_by_protections(
		target_descriptor, targets_by_id, spell_choice, caster_context)
	if not blocked_targets.is_empty():
		# Drop blocked targets from the descriptor; record the block reason.
		var allowed: Array = []
		for tid in target_descriptor.target_ids:
			if tid not in blocked_targets:
				allowed.append(tid)
		target_descriptor.target_ids = allowed
		# All targets blocked → cast fizzles, slot still consumed per ACKS.
		if allowed.is_empty():
			if _campaign_repo != null:
				_campaign_repo.increment_expended_slot(caster_context.caster_id, spell_choice.level)
				EventBus.spell_slot_expended.emit(
					caster_context.caster_id, spell_choice.level,
					_compute_remaining_slots(caster_context.caster_id, spell_choice.level))
			result.slot_consumed = true
			result.success = false
			result.failures.append("all targets blocked by anti-magic / globe of invulnerability")
			result.effects_applied = [{
				"step_kind": "blocked_by_protection",
				"applied": false,
				"blocked_targets": blocked_targets,
				"reason": "anti_magic_or_globe",
			}]
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
	var aggregated_side_flips: Array = []  # Charm side-flip records (Tier 4, 2026-06-01)
	var aggregated_item_modifiers: Dictionary = {}  # item_id → {item_attribute, value/value_dice, source_id}
	var attack_hit_targets: Dictionary = {}  # target_id -> bool (set by attack_throw_vs_target)

	for step_raw in resolution_steps:
		if not (step_raw is Dictionary):
			continue
		var step: Dictionary = step_raw
		var kind: String = step.get("kind", "")
		var outcome: Dictionary = {}
		match kind:
			"damage":
				outcome = _apply_damage(step, target_descriptor, targets_by_id, save_spec, save_results, attack_hit_targets, caster_context)
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
				outcome = _apply_flag(step, spell_choice, target_descriptor, targets_by_id, caster_entity, caster_context, save_results, save_spec)
				aggregated_flags.append_array(outcome.get("records", []))
			"apply_condition":
				outcome = _apply_condition(step, target_descriptor, targets_by_id, save_results, save_spec)
				aggregated_conditions.append_array(outcome.get("records", []))
			"flip_to_caster_team":
				# Tier 4 follow-up (2026-06-01): Charm side-flip per Jedidiah
				# ruling — Charmed creatures switch team allegiance to the
				# caster's side while still under AI control. Distinguishes
				# Charmed from Controlled (which adds direct-action UI on
				# top, wired by magic-item Control items). The step honors
				# save_spec.on_success == "negate" so a successful save
				# leaves the target's side unchanged.
				outcome = _flip_to_caster_team(
					step, target_descriptor, targets_by_id, caster_entity,
					save_results, save_spec)
				aggregated_side_flips.append_array(outcome.get("records", []))
			"remove_condition":
				outcome = _remove_condition(step, target_descriptor, targets_by_id)
			"remove_modifier":
				outcome = _remove_modifier(step, target_descriptor, targets_by_id, caster_context)
			"apply_modifier_to_item":
				outcome = _apply_modifier_to_item(step, spell_choice, target_descriptor, targets_by_id, caster_context)
				# Aggregate item-targeted modifier outcomes for the active_effect
				# metadata, so SpellCombatHooks.get_item_attack_bonuses can look
				# them up at attack-damage time. Keyed by item_id.
				for tid in (outcome.get("per_target", {}) as Dictionary).keys():
					var entry: Dictionary = (outcome["per_target"] as Dictionary)[tid]
					if not aggregated_item_modifiers.has(tid):
						aggregated_item_modifiers[tid] = []
					aggregated_item_modifiers[tid].append(entry)
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
				outcome = _modify_cell_state(step, target_descriptor, caster_context)
			"open_close_lock":
				outcome = _open_close_lock(step, target_descriptor, caster_context)
			"spawn_entity":
				outcome = {"kind": kind, "applied": false, "reason": "deferred to per-spell custom resolver session"}
			"teleport":
				outcome = _teleport(step, target_descriptor, targets_by_id, caster_entity, caster_context, save_results, save_spec)
			"destroy_undead_by_hd_budget":
				outcome = _destroy_undead_by_hd_budget(
					step, target_descriptor, targets_by_id, save_spec,
					save_results, caster_context)
				aggregated_conditions.append_array(outcome.get("records", []))
			"stub":
				outcome = {"kind": kind, "applied": false, "reason": step.get("reason", ""), "message": step.get("placeholder_message", "")}
			"custom":
				outcome = _dispatch_custom(step, caster_context, spell_choice, target_descriptor, targets_by_id, caster_entity)
				# Custom resolvers may emit `persist_metadata` to splice extra
				# fields into the active_effect's metadata (e.g., Spiritual
				# Weapon's weapon_profile for round-tick consumption by
				# SpellCombatHooks). Aggregate them here; spliced into the
				# active_effect dict at registration below.
				var pm: Dictionary = outcome.get("persist_metadata", {})
				if not pm.is_empty():
					if not aggregated_item_modifiers.has("__persist_metadata__"):
						aggregated_item_modifiers["__persist_metadata__"] = {}
					(aggregated_item_modifiers["__persist_metadata__"] as Dictionary).merge(pm, true)
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
			aggregated_conditions,
			aggregated_side_flips)
		# Splice item-modifier outcomes into the active_effect metadata so
		# SpellCombatHooks.get_item_attack_bonuses can consume Striking-style
		# bonuses at attack-damage time. Keyed by item_id → array of per-step
		# outcome dicts (item_attribute, value/value_dice, source_id).
		if not aggregated_item_modifiers.is_empty():
			var meta: Dictionary = active_effect.get("metadata", {})
			# Splice custom-resolver persist_metadata first (from `__persist_metadata__`
			# bucket emitted by custom resolvers like Spiritual Weapon).
			var custom_persist: Dictionary = aggregated_item_modifiers.get("__persist_metadata__", {})
			if not custom_persist.is_empty():
				meta.merge(custom_persist, true)
				aggregated_item_modifiers.erase("__persist_metadata__")
			# Remaining keys are item_id → Array[entry] for apply_modifier_to_item.
			if not aggregated_item_modifiers.is_empty():
				meta["per_target"] = aggregated_item_modifiers
				# Also append item_ids to target_ids so SpellCombatHooks's
				# `if item_id in effect.target_ids` check fires correctly.
				var tids: Array = active_effect.get("target_ids", [])
				for item_id in aggregated_item_modifiers.keys():
					if not (item_id in tids):
						tids.append(item_id)
				active_effect["target_ids"] = tids
			active_effect["metadata"] = meta
		_effect_tracker.add_effect(active_effect)
		result.active_effect_ids.append(effect_id)
		EventBus.spell_effect_applied.emit(effect_id, spell_choice.spell_key, target_descriptor.target_ids)

	# --- Stage 10: event emission ---
	EventBus.spell_cast.emit(
		caster_context.caster_id,
		spell_choice.spell_key,
		target_descriptor.target_ids)

	# P5 — teleport family emits a per-target dispatch signal so the
	# TeleportRuntimeConsumer can snap the targets, validate destinations,
	# and apply solid-matter / falling / lost outcomes. Consolidates outcomes
	# from any "teleport" step kind OR a custom resolver returning per_target
	# entries with a `destination_cell` field.
	if spell_choice.spell_key == "dimension_door" or spell_choice.spell_key == "teleport":
		var combined_per_target: Dictionary = {}
		for outcome_dict in step_outcomes:
			var pt: Dictionary = outcome_dict.get("per_target", {})
			for tid in pt.keys():
				var entry = pt[tid]
				if entry is Dictionary and (entry as Dictionary).has("destination_cell"):
					combined_per_target[tid] = entry
		if not combined_per_target.is_empty():
			EventBus.teleport_resolved.emit(
				caster_context.caster_id,
				spell_choice.spell_key,
				combined_per_target)

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
# Async resolve path (Session 2.9 — infrastructure for DicePrompt integration)
# ---------------------------------------------------------------------------

func resolve_async(
		caster_context: CasterContext,
		spell_choice: SpellChoice,
		target_descriptor: TargetDescriptor,
		caster_entity: Variant = null,
		targets_by_id: Dictionary = {}) -> ResolutionResult:
	## Async variant of [method resolve]. When dice_mode is DIGITAL (the default
	## and test/CI mode), resolves synchronously and returns the same result.
	##
	## When dice_mode is HYBRID or PHYSICAL and a target is a PC that would roll
	## a saving throw, the async path will defer to DicePrompt. That integration
	## is deferred to the dice-mode UX work — for now this is synchronous-only.
	## Callers should still use [method resolve_async] rather than [method resolve]
	## if they expect to be called from the combat UI path, so the async hand-off
	## can drop in without changing call sites.
	var dice_mode: int = GameState.dice_mode if GameState != null else GameState.DiceMode.DIGITAL
	if dice_mode != GameState.DiceMode.DIGITAL:
		# Deferred: DicePrompt integration. For now, fall through to synchronous
		# resolution. When the dice-mode UX work adds DicePrompt to the combat
		# UI, this path will branch into a coroutine that awaits manual save rolls
		# and returns ResolutionResult after the player completes each throw.
		push_warning("CastingResolver.resolve_async: non-DIGITAL dice mode not yet integrated — resolving synchronously (Session 2.9 deferred item)")
	return resolve(caster_context, spell_choice, target_descriptor, caster_entity, targets_by_id)


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
		attack_hit_targets: Dictionary,
		caster_context: CasterContext = null) -> Dictionary:
	var dice_expr := String(step.get("dice", ""))
	var damage_type := String(step.get("damage_type", "untyped"))
	var on_hit_only := bool(step.get("on_hit_only", false))
	# Per-caster-level flat bonus (Cause Serious Wounds: 2d6 + caster_level).
	var bonus_per_level := int(step.get("bonus_per_caster_level", 0))
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		if on_hit_only and not attack_hit_targets.get(tid, true):
			per_target[tid] = {"applied": false, "reason": "missed"}
			continue
		var roll = _dice_system.roll_expression(dice_expr, "spell_damage")
		var amount: int = int(roll.modified_total) if roll != null else 0
		var level_bonus: int = bonus_per_level * (caster_context.caster_level if caster_context != null else 1)
		amount += level_bonus
		_apply_damage_to_target(tid, targets_by_id, amount, damage_type, "spell")
		per_target[tid] = {"applied": true, "amount": amount, "level_bonus": level_bonus}
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
	# Per-caster-level flat bonus (Cure Serious Wounds: 2d6 + caster_level).
	var bonus_per_level := int(step.get("bonus_per_caster_level", 0))
	var per_target: Dictionary = {}
	for tid in _resolve_heal_target_ids(target_descriptor, caster_context):
		var entity = _resolve_entity(tid, targets_by_id, caster_entity, caster_context)
		# Diseased magic-heal block per RAW (acore_spell_catalog_a-i_summary.xml,
		# Cause Disease reverse: "The target cannot be magically healed while
		# afflicted"). Cure Disease must be cast first to clear the condition.
		if _entity_has_condition(entity, "diseased"):
			per_target[tid] = {"applied": false, "reason": "diseased_magic_heal_blocked"}
			continue
		var roll = _dice_system.roll_expression(dice_expr, "spell_healing")
		var amount: int = int(roll.modified_total) if roll != null else 0
		var level_bonus: int = bonus_per_level * (caster_context.caster_level if caster_context != null else 1)
		amount += level_bonus
		var actual: int = 0
		if entity != null and entity.has_method("apply_healing"):
			actual = int(entity.apply_healing(amount))
		EventBus.healing_applied.emit(tid, actual, "spell")
		per_target[tid] = {"applied": true, "rolled": amount, "actual": actual, "level_bonus": level_bonus}
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
		# Diseased magic-heal block (see _apply_heal for the RAW citation).
		if _entity_has_condition(entity, "diseased"):
			per_target[tid] = {"applied": false, "reason": "diseased_magic_heal_blocked"}
			continue
		var actual: int = 0
		if entity != null and entity.has_method("apply_healing"):
			actual = int(entity.apply_healing(amount))
		EventBus.healing_applied.emit(tid, actual, "spell")
		per_target[tid] = {"applied": true, "actual": actual}
	return {"per_target": per_target}


## True if the entity exposes a `has_condition(key)` method and reports the
## given condition. Returns false defensively for entities without condition
## tracking (raw CharacterData; Combatants do).
func _entity_has_condition(entity: Variant, condition_key: String) -> bool:
	if entity == null:
		return false
	if entity.has_method("has_condition"):
		return bool(entity.has_condition(condition_key))
	# CharacterData fallback — read the condition list directly if present.
	if "conditions" in entity:
		var conds = entity.conditions
		if conds is Array:
			return condition_key in conds
	return false


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
		caster_context: CasterContext,
		save_results: Dictionary = {},
		save_spec: Dictionary = {}) -> Dictionary:
	var flag_key := String(step.get("flag_key", ""))
	var source_id := _make_modifier_source_id(spell_choice.spell_key, caster_context.caster_id)
	var records: Array = []
	var per_target: Dictionary = {}
	# 2026-06-02 (Tier 4 sweep — Growth/Diminution reverse): save-vs-X negate
	# now gates apply_flag the same way it gates apply_condition. When
	# save_spec.on_success == "negate" AND the target rolled a saved=true,
	# the flag application is skipped for that target. Backward-compatible:
	# spells with save_spec.category=="none" pass an empty save_results
	# dictionary, so the gate is a no-op for them. For spells whose
	# save_spec carries `applies_only_to_unwilling*` flags, the convention
	# is that the PICKER LAYER filters out willing targets before calling
	# resolve(); the resolver always honors save_results when present.
	var on_save_negate: bool = String(save_spec.get("on_success", "")) == "negate"
	# `target_caster_only: true` overrides target_descriptor.target_ids and
	# applies the flag to caster_entity. Used by spells that need to set a
	# constraint flag on the caster (e.g. Telekinesis sets is_telekinesis_caster
	# on the caster while is_telekinetically_held lands on the lifted target).
	var ids_to_walk: Array = target_descriptor.target_ids
	if bool(step.get("target_caster_only", false)) and caster_context != null:
		ids_to_walk = [caster_context.caster_id]
	for tid in ids_to_walk:
		if on_save_negate and bool(save_results.get(tid, {}).get("succeeded", false)):
			per_target[tid] = {"applied": false, "reason": "saved"}
			continue
		var entity = _resolve_entity(tid, targets_by_id, caster_entity, caster_context)
		var flags := _get_flags(entity)
		if flags == null:
			per_target[tid] = {"applied": false, "reason": "no_target_data"}
			continue
		# Build flag metadata: step-supplied metadata merged with the caster's
		# level. Sanctuary (Session 5) consumes metadata.caster_level when the
		# attack resolver fires the per-attacker save check; future spells can
		# read other step.metadata fields the same way.
		var meta: Dictionary = (step.get("metadata", {}) as Dictionary).duplicate()
		meta["caster_level"] = caster_context.caster_level
		meta["caster_id"] = caster_context.caster_id
		meta["spell_key"] = spell_choice.spell_key
		flags.set_flag(flag_key, source_id, meta)
		records.append({"character_id": tid, "flag_key": flag_key, "source_id": source_id, "metadata": meta})
		per_target[tid] = {"applied": true, "flag_key": flag_key}
		# Side effect: drop carried items on apply (Tier 4 follow-up, 2026-06-01).
		# Gaseous Form's RAW (pc_spell_catalog_f-u.xml:90-126): "All worn or
		# carried items drop immediately." V1 simplification — items unequip
		# (is_equipped → 0, slot → "pack", container_id → ""); they stay in
		# the target's inventory rather than literally hitting the floor.
		# Gameplay equivalence: the wielder loses access to equipped gear
		# while gaseous. True ground-drop tracking is a follow-up.
		# Gated on `drops_carried_items_on_apply: true` in the flag's
		# metadata so future spells with the same semantic plug in without
		# touching this method.
		if bool(meta.get("drops_carried_items_on_apply", false)):
			_drop_carried_items_for_target(tid)
	return {"per_target": per_target, "records": records}


## Unequips every equipped inventory item for the target character. Used
## by spells whose flag metadata carries `drops_carried_items_on_apply: true`
## (Gaseous Form V1). No-op for targets without a corresponding inventory
## (monsters whose loot is on a creature row, not a character row — the
## _campaign_repo lookup just returns nothing).
func _drop_carried_items_for_target(target_id: String) -> void:
	if _campaign_repo == null or not _campaign_repo.has_method("get_inventory_items"):
		return
	var items: Array = _campaign_repo.get_inventory_items(target_id)
	for item in items:
		if int(item.get("is_equipped", 0)) != 1:
			continue
		var iid: String = str(item.get("id", ""))
		if iid.is_empty():
			continue
		if _campaign_repo.has_method("update_inventory_item_equip_state"):
			_campaign_repo.update_inventory_item_equip_state(iid, false, "pack", "")


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


## Flips each non-saved target's `.side` to the caster's side. Per Jedidiah
## ruling 2026-06-01, this is the Charmed half of the Charmed/Controlled
## distinction: Charmed switches team allegiance but leaves the target
## under AI control. The Controlled mechanic (magic-item Control items)
## does the same side flip + grants direct-action UI (V1 sets a flag for
## the UI; UI wiring is a follow-up).
##
## Honors save_spec.on_success == "negate" — targets that succeeded their
## save keep their original side. Targets without a `.side` property
## (out-of-combat CharacterData, etc.) no-op gracefully.
##
## Each successful flip emits a record into the outcome's `records` array:
## `{character_id, original_side, new_side, caster_id}`. The
## CastingResolver's `_unwind_effect_state` reads `applied_side_flips` on
## the effect dict and restores original_side on duration expiry / dispel
## / concentration break.
##
## Wired by charm_person + charm_monster spell-effect blocks. Future
## charm-like spells (charm_animal when its effect block lands, command
## spells, etc.) reuse the same step kind.
func _flip_to_caster_team(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant,
		save_results: Dictionary,
		save_spec: Dictionary) -> Dictionary:
	var on_save_negate: bool = String(save_spec.get("on_success", "")) == "negate"
	# Determine caster's side. If the caster doesn't expose a `.side`
	# property (e.g., out-of-combat cast), we can't compute a target side
	# to flip to — return a no-op outcome.
	var caster_side: int = -1
	if caster_entity != null and ("side" in caster_entity):
		caster_side = int(caster_entity.get("side"))
	var per_target: Dictionary = {}
	var records: Array = []
	if caster_side < 0:
		# Caster has no side — skip every target.
		for tid in target_descriptor.target_ids:
			per_target[tid] = {"applied": false, "reason": "caster has no side"}
		return {"per_target": per_target, "records": records}
	for tid in target_descriptor.target_ids:
		# Save-negate gate.
		if on_save_negate and bool((save_results.get(tid, {}) as Dictionary).get("succeeded", false)):
			per_target[tid] = {"applied": false, "reason": "saved"}
			continue
		var entity = targets_by_id.get(tid, null)
		if entity == null:
			per_target[tid] = {"applied": false, "reason": "no entity"}
			continue
		if not ("side" in entity):
			# Target can't be flipped (no side property).
			per_target[tid] = {"applied": false, "reason": "target has no side"}
			continue
		var original_side: int = int(entity.get("side"))
		if original_side == caster_side:
			# Already on the caster's side — nothing to do, but record the
			# no-op so the cleanup path doesn't accidentally revert.
			per_target[tid] = {"applied": false, "reason": "already on caster's side"}
			continue
		# Flip!
		entity.side = caster_side
		records.append({
			"character_id": tid,
			"original_side": original_side,
			"new_side": caster_side,
		})
		per_target[tid] = {
			"applied": true,
			"original_side": original_side,
			"new_side": caster_side,
		}
	return {"per_target": per_target, "records": records}


## Removes a condition from each target (Remove Fear, Cure Disease, etc.).
## If the entity exposes `remove_condition`, that path is used; otherwise
## `clear_condition` is tried; otherwise the call no-ops gracefully.
##
## Session 5 (Remove Fear): the spell may carry `save_modifier_per_caster_level`
## for active fear-effect re-saves; that bonus is recorded in the outcome
## metadata for the active_effect tracker to consume when computing the
## resave (deferred to Session 8 dispel-magic-style mechanic).
func _remove_condition(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary) -> Dictionary:
	var condition_key := String(step.get("condition_key", ""))
	var save_modifier_per_level := int(step.get("save_modifier_per_caster_level", 0))
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		var removed := false
		if entity != null:
			if entity.has_method("remove_condition"):
				entity.remove_condition(condition_key)
				removed = true
			elif entity.has_method("clear_condition"):
				entity.clear_condition(condition_key)
				removed = true
		if removed:
			EventBus.condition_changed.emit(tid, {
				"condition": condition_key, "applied": false, "removed_by": "spell"
			})
			per_target[tid] = {
				"applied": true,
				"condition_key": condition_key,
				"save_modifier_per_caster_level": save_modifier_per_level,
			}
		else:
			per_target[tid] = {
				"applied": false,
				"reason": "no_remove_condition_method",
				"condition_key": condition_key,
			}
	return {"per_target": per_target}


## Removes modifiers matching a source pattern from each target.
## Step payload:
##   {
##     "kind": "remove_modifier",
##     "source_pattern": "curse:*"   ← removes all sources beginning with "curse:"
##                                     (uses ModifierContainer.remove_all_with_source_prefix)
##     "caster_level_check": true    ← if true, ACKS Remove Curse rule:
##                                     5% per-level fail when original cursing
##                                     caster's level exceeds this caster's level.
##                                     For Session 9: level data isn't tracked
##                                     on the modifier source, so we always
##                                     succeed at removal (deferred polish).
##   }
func _remove_modifier(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		_caster_context: CasterContext) -> Dictionary:
	var source_pattern := String(step.get("source_pattern", ""))
	if source_pattern.is_empty():
		return {"applied": false, "reason": "remove_modifier: empty source_pattern"}
	var prefix := source_pattern.replace("*", "")
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		if entity == null or not ("modifiers" in entity):
			per_target[tid] = {"applied": false, "reason": "no_modifiers"}
			continue
		var stats_before: Array = entity.modifiers.get_stats_with_modifiers()
		entity.modifiers.remove_all_with_source_prefix(prefix)
		var stats_after: Array = entity.modifiers.get_stats_with_modifiers()
		var removed_count: int = stats_before.size() - stats_after.size()
		per_target[tid] = {
			"applied": true,
			"source_prefix": prefix,
			"stats_affected_count": removed_count,
		}
	return {"per_target": per_target}


## Applies a modifier to an inventory item rather than to the carrier.
## Used by Striking (1d6 weapon damage bonus). The targeting controller is
## responsible for resolving the target_descriptor.target_ids[0] to an item id;
## the resolver looks up the item and applies the modifier to its `modifiers`
## container (or records the item-side effect for future inventory polish).
##
## Step payload:
##   {
##     "kind": "apply_modifier_to_item",
##     "item_attribute": "damage_bonus_dice",   ← stat key on the item
##     "value_dice": "1d6"                       ← dice expression for the bonus
##     OR "value": 1                             ← fixed-int alternative
##     "stacking_group": "striking"
##   }
##
## Production note: InventoryItem doesn't yet expose a ModifierContainer (it
## carries its own static stats). Session 9 records the contract per-target;
## the inventory subsystem reads the active_effect on tick to apply the
## bonus during attack damage rolls (parallel to modify_cell_state's pattern).
func _apply_modifier_to_item(
		step: Dictionary,
		spell_choice: SpellChoice,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_context: CasterContext) -> Dictionary:
	var item_attribute := String(step.get("item_attribute", ""))
	var value_dice := String(step.get("value_dice", ""))
	var value := int(step.get("value", 0))
	var stacking_group := String(step.get("stacking_group", ""))
	var source_id := _make_modifier_source_id(spell_choice.spell_key, caster_context.caster_id)
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		# Item resolution is via targets_by_id (item id → InventoryItem) when
		# available; fall back to recording the contract by target_id alone.
		var item = targets_by_id.get(tid, null)
		per_target[tid] = {
			"applied": true,
			"target_item_id": tid,
			"item_attribute": item_attribute,
			"value_dice": value_dice,
			"value": value,
			"stacking_group": stacking_group,
			"source_id": source_id,
			"item_present": item != null,
		}
	return {
		"per_target": per_target,
		"item_modifier_source": source_id,
	}


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
	## Per ACKS RAW (acore_spell_catalog_k-w_summary.xml): Mirror Image creates
	## 1d4 figments. Step may carry `count` (fixed), `count_dice` (expression
	## like "1d4"), and `count_per_level`. All three sum.
	var count := int(step.get("count", 0))
	var dice_expr := String(step.get("count_dice", ""))
	if not dice_expr.is_empty() and _dice_system != null:
		var roll = _dice_system.roll_expression(dice_expr, "spell_mirror_images")
		count += int(roll.modified_total) if roll != null else 0
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


## Resolves a `modify_cell_state` resolution step. The step payload follows
## the GDD §15.3 cell-mutation schema:
##
##   {
##     "kind": "modify_cell_state",
##     "cell_mutation": {
##       "shape": "add_light_source" | "add_darkness_source" | "add_lock" | ...,
##       "radius_feet": int  (light/darkness),
##       "lock_strength": "magical" | "mundane" (lock variants),
##       ...
##     }
##   }
##
## The resolver records the mutation as a structured outcome and binds it to
## the target cell from `target_descriptor` (origin_cell for area_at_point or
## the first target_cell otherwise). Active map application is consumed
## downstream — DungeonLightManager / dungeon door subsystem read the mutation
## off the active_effect when it lands. Session 4 wires the contract; the
## per-shape map handlers land in their own polish session (per the roadmap
## §15.4 — MapMutationDispatcher integration).
func _modify_cell_state(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		caster_context: CasterContext) -> Dictionary:
	var mutation: Dictionary = step.get("cell_mutation", {})
	var shape := String(mutation.get("shape", ""))
	if shape.is_empty():
		return {"applied": false, "reason": "modify_cell_state: empty cell_mutation.shape"}
	var target_cell: Vector3i = target_descriptor.origin_cell
	if target_descriptor.target_cells.size() > 0:
		target_cell = target_descriptor.target_cells[0]
	return {
		"applied": true,
		"shape": shape,
		"target_cell": target_cell,
		"map_context": caster_context.map_context,
		"mutation": mutation,
	}


## Resolves an `open_close_lock` resolution step (Knock + Wizard Lock).
## Knock opens stuck/barred/locked/held/wizard-locked doors and similar
## fastenings. Wizard Lock secures a portal magically. The step payload:
##
##   {
##     "kind": "open_close_lock",
##     "operation": "open" | "lock_magical",
##     "defeats": ["mundane_lock", "stuck", "wizard_lock_for_1_turn", "held"],
##     "wizard_lock_suspended_turns": 1  (Knock-only; suspends wizard lock)
##   }
##
## The resolver records the structured outcome — the dungeon door subsystem
## reads the active_effect on tick to apply the actual lock state mutation.
## Session 6 wires the contract; per-shape map handlers (door state changes,
## Pick Lock gating against magical locks) integrate when the dungeon door
## subsystem reads spell effects.
func _open_close_lock(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		caster_context: CasterContext) -> Dictionary:
	var operation := String(step.get("operation", "open"))
	var defeats: Array = step.get("defeats", [])
	var target_cell: Vector3i = target_descriptor.origin_cell
	if target_descriptor.target_cells.size() > 0:
		target_cell = target_descriptor.target_cells[0]
	return {
		"applied": true,
		"operation": operation,
		"defeats": defeats,
		"target_cell": target_cell,
		"map_context": caster_context.map_context,
		"caster_level": caster_context.caster_level,
		"wizard_lock_suspended_turns": int(step.get("wizard_lock_suspended_turns", 0)),
	}


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


## Teleports each target in target_descriptor.target_ids to the destination
## cell carried on target_descriptor.origin_cell (or step.destination_cell as
## an explicit override). Supports two error_profiles:
##   "precise"   — always lands exactly on the chosen cell (Dimension Door RAW).
##   "imprecise" — can scatter 1d10 cells off in a random direction (Teleport RAW).
##
## Per Dimension Door RAW (acore_spell_catalog_a-i_summary.xml):
##   - Subject is transported instantly up to 360' from the caster.
##   - "If the destination lies within a solid object, the spell fails automatically."
##   - Unwilling targets save vs Spells to avoid transport.
##
## Step payload:
##   {
##     "kind": "teleport",
##     "max_range_feet": 360,                    ← cap; resolver does NOT enforce
##                                                 here (target picker should clamp);
##                                                 stored in outcome for log/UI.
##     "error_profile": "precise" | "imprecise",
##     "destination_cell": [x, y, z]             ← optional override; otherwise
##                                                 read from target_descriptor.
##                                                 origin_cell.
##     "fail_on_solid_object": true              ← per Dimension Door RAW.
##   }
##
## Outcome per_target:
##   { applied: bool, destination_cell: Vector3i, scatter_offset: Vector3i,
##     error_profile: String, saved: bool, reason?: String }
##
## On save success (unwilling target), the per-target entry has applied=false
## with reason="saved". On solid-object failure, applied=false reason="solid_object".
## The actual movement of the entity is delegated to the runtime layer (combat
## controller / map state), reading the destination_cell from the outcome — the
## resolver records the contract (parallel to modify_cell_state).
func _teleport(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		caster_entity: Variant,
		caster_context: CasterContext,
		save_results: Dictionary,
		save_spec: Dictionary) -> Dictionary:
	var max_range_feet := int(step.get("max_range_feet", 360))
	var error_profile := String(step.get("error_profile", "precise"))
	var fail_on_solid := bool(step.get("fail_on_solid_object", true))
	var dest_override = step.get("destination_cell", null)
	var on_save_negate := String(save_spec.get("on_success", "")) == "negate"
	# Resolve destination cell: explicit step override, else target_descriptor.
	var destination: Vector3i = target_descriptor.origin_cell
	if dest_override is Array and (dest_override as Array).size() == 3:
		destination = Vector3i(int(dest_override[0]), int(dest_override[1]), int(dest_override[2]))
	# Imprecise scatter (1d10 cells off in a random direction). Deterministic via
	# DiceSystem so test seeds reproduce; precise profile leaves offset zero.
	var scatter_offset: Vector3i = Vector3i.ZERO
	if error_profile == "imprecise" and _dice_system != null:
		var dx := int(_dice_system.roll_digital(10, 1, -5, "spell_teleport_dx").modified_total)
		var dy := int(_dice_system.roll_digital(10, 1, -5, "spell_teleport_dy").modified_total)
		scatter_offset = Vector3i(dx, dy, 0)
		destination += scatter_offset
	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		# Unwilling target save check (Dimension Door RAW).
		if on_save_negate and bool((save_results.get(tid, {}) as Dictionary).get("succeeded", false)):
			per_target[tid] = {
				"applied": false, "reason": "saved",
				"destination_cell": destination, "error_profile": error_profile,
				"saved": true,
			}
			continue
		# Solid-object check (the runtime map layer must short-circuit here when
		# destination is impassable; resolver records the contract). For Session 10
		# the resolver records `solid_object_check_pending: true` and the consumer
		# can flip to applied=false with reason="solid_object" if appropriate.
		per_target[tid] = {
			"applied": true,
			"destination_cell": destination,
			"scatter_offset": scatter_offset,
			"error_profile": error_profile,
			"max_range_feet": max_range_feet,
			"fail_on_solid_object": fail_on_solid,
			"saved": false,
		}
	return {
		"per_target": per_target,
		"destination_cell": destination,
		"scatter_offset": scatter_offset,
		"error_profile": error_profile,
		"max_range_feet": max_range_feet,
	}


## Smite Undead destruction routine (P9).
##
## Step payload:
##   {
##     "kind": "destroy_undead_by_hd_budget",
##     "hd_budget_formula": "<caster_level>",   # currently only "caster_level" supported
##     "hd_immunity_threshold": 8,              # 8+ HD undead are immune (vampire untouched)
##     "exempt_creature_keys": ["skeleton", "zombie"],  # skip the save (auto-fail)
##   }
##
## Walks target_descriptor.target_ids in HD-ascending order (weakest first
## per RAW), pre-rolled saves consulted from `save_results`. For exempt
## creature keys, the save is treated as auto-failed (per RAW skeletons /
## zombies have no save vs Smite Undead). Failed save → spend the target's
## HD from the budget; if budget allows, mark `dispel_destroyed` so
## SpellCombatHooks._sweep_destroyed_entities drops hp at end of round
## (parallel to Death Spell / Disintegrate from S9.7).
##
## Outcome per_target:
##   { destroyed: bool, hd_cost: int, saved: bool, exempt: bool, reason?: String }
## Outcome top-level:
##   { hd_budget: int, hd_spent: int, hd_immunity_threshold: int }
func _destroy_undead_by_hd_budget(
		step: Dictionary,
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		_save_spec: Dictionary,
		save_results: Dictionary,
		caster_context: CasterContext) -> Dictionary:
	var hd_budget: int = caster_context.caster_level if caster_context != null else 1
	if step.has("hd_budget_override"):
		hd_budget = int(step["hd_budget_override"])
	var hd_immunity_threshold: int = int(step.get("hd_immunity_threshold", 8))
	var exempt_keys: Array = step.get("exempt_creature_keys", [])
	# Build (target_id, entity, hd) tuples and sort weakest first.
	var ranked: Array = []
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		var hd: int = _get_entity_hd(entity)
		ranked.append({"tid": tid, "entity": entity, "hd": hd})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.hd) < int(b.hd))
	var per_target: Dictionary = {}
	var condition_records: Array = []
	var hd_spent: int = 0
	for entry in ranked:
		var tid: String = String(entry.tid)
		var entity = entry.entity
		var hd: int = int(entry.hd)
		# 8+ HD immune per RAW.
		if hd >= hd_immunity_threshold:
			per_target[tid] = {
				"destroyed": false, "hd_cost": hd, "saved": false,
				"exempt": false, "reason": "hd_immunity",
			}
			continue
		# Skeleton / zombie skip the save (auto-fail).
		var creature_key: String = _entity_creature_key(entity)
		var skips_save: bool = creature_key in exempt_keys
		var saved: bool = false
		if not skips_save:
			saved = bool((save_results.get(tid, {}) as Dictionary).get("succeeded", false))
		if saved:
			per_target[tid] = {
				"destroyed": false, "hd_cost": hd, "saved": true,
				"exempt": false, "reason": "save_succeeded",
			}
			continue
		# Failed save (or no-save creature) — spend the budget if affordable.
		if hd_spent + hd > hd_budget:
			per_target[tid] = {
				"destroyed": false, "hd_cost": hd, "saved": false,
				"exempt": skips_save, "reason": "budget_exhausted",
			}
			continue
		hd_spent += hd
		per_target[tid] = {
			"destroyed": true, "hd_cost": hd, "saved": false,
			"exempt": skips_save,
		}
		# Apply dispel_destroyed condition; the destruction sweep at end of
		# round drops hp to 0 (parallel to Death Spell + Disintegrate).
		if entity != null and entity.has_method("add_condition"):
			entity.add_condition("dispel_destroyed")
		condition_records.append({
			"character_id": tid, "condition_key": "dispel_destroyed",
		})
		EventBus.condition_changed.emit(tid, {
			"condition": "dispel_destroyed", "applied": true,
			"source": "smite_undead",
		})
	return {
		"per_target": per_target,
		"records": condition_records,
		"hd_budget": hd_budget,
		"hd_spent": hd_spent,
		"hd_immunity_threshold": hd_immunity_threshold,
	}


## Returns the catalog creature key for [param entity] when known, else "".
## Used by Smite Undead to apply the skeleton/zombie no-save exemption.
func _entity_creature_key(entity: Variant) -> String:
	if entity == null:
		return ""
	# Combatant exposes monster_group_id matching the catalog id.
	if "monster_group_id" in entity:
		var mgid: String = String(entity.monster_group_id)
		if not mgid.is_empty():
			return mgid
	# Combatant._monster_data.id (legacy / direct access).
	if "_monster_data" in entity:
		var md = entity._monster_data
		if md is Dictionary:
			var mid: String = String((md as Dictionary).get("id", ""))
			if not mid.is_empty():
				return mid
	# Test fixture: bare `creature_key` field.
	if "creature_key" in entity:
		return String(entity.creature_key)
	return ""


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
	# 2026-06-02 (Elemental Commanders cluster): SpellChoice carries
	# per-resolver resolver_args overrides for magic items that reuse a
	# spell catalog entry but supply different per-item resolver_args
	# (Bowl/Brazier/Censer/Stone of <element>-elementals reuse
	# conjure_elemental but supply per-item elemental_type + tier). When
	# the SpellChoice's resolver_args_overrides has an entry for THIS
	# resolver_id, we shallow-merge it into the step's resolver_args
	# (override values win). Pure-spell casts leave overrides empty so
	# the catalog's resolver_args pass through unchanged.
	var effective_step: Dictionary = step
	if spell_choice != null and not spell_choice.resolver_args_overrides.is_empty():
		var override_for_resolver: Variant = spell_choice.resolver_args_overrides.get(
			resolver_id, null)
		if override_for_resolver is Dictionary:
			effective_step = step.duplicate(true)
			var existing_args: Dictionary = effective_step.get("resolver_args", {})
			# Shallow-merge: override keys win.
			for k in (override_for_resolver as Dictionary).keys():
				existing_args[k] = (override_for_resolver as Dictionary)[k]
			effective_step["resolver_args"] = existing_args
	var args: Dictionary = {
		"caster_context": caster_context,
		"spell_choice": spell_choice,
		"target_descriptor": target_descriptor,
		"targets_by_id": targets_by_id,
		"caster_entity": caster_entity,
		"step_payload": effective_step,
		# Session 8: pass the active_effect tracker so resolvers like
		# DispelMagicResolver can call dispel_check directly. Resolvers that
		# don't need it can ignore.
		"effect_tracker": _effect_tracker,
		# Session 38 (2026-06-02): forward DiceSystem so resolvers that need
		# to roll dice (Restore Life and Limb's vs-undead save vs Death and
		# Tampering with Mortality d20+d6 roll) can do so against the live
		# RNG in production. Test harnesses still inject a fake dice via
		# step.resolver_args.dice (resolvers prefer resolver_args.dice when
		# present and fall back to args.dice otherwise).
		"dice": _dice_system,
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
		caster_context: CasterContext) -> Dictionary:
	var category := String(save_spec.get("category", "none"))
	if category == "none":
		return {}
	var save_key := _save_category_to_key(category)
	if save_key.is_empty():
		return {}
	var modifier := int(save_spec.get("modifier", 0))
	# Tagged-save bonuses — each one stacks on the d20 roll:
	#
	#   is_fear_save: true   → consults save_vs_fear (Bless +1, Bane -1, plus
	#                          fear-immunity auto-success for berserkers etc.)
	#   damage_type: <type>  → consults save_vs_<type> (Resist Cold +2 vs cold,
	#                          Resist Fire +2 vs fire, etc.)
	#   attacker_alignment:  → consults save_vs_<alignment> (Protection from Evil
	#     <alignment>          +1 vs chaotic, Protection from Good +1 vs lawful).
	#                          Defaults to caster_context.alignment when not
	#                          explicitly set; spells can override (e.g., a
	#                          chaotic creature's spell carries the tag implicitly).
	#
	# All bonuses sum into the d20 roll modifier. Each tag is independently
	# unit-tested; modifier write side is each spell's apply_modifier step.
	var is_fear_save := bool(save_spec.get("is_fear_save", false))
	var damage_type := String(save_spec.get("damage_type", ""))
	var attacker_alignment := String(save_spec.get("attacker_alignment", ""))
	# Auto-fill attacker_alignment from caster context when the save_spec asks
	# for alignment-tagged stacking but doesn't pin a specific alignment. This
	# lets spell catalog entries say `consult_caster_alignment: true` once and
	# get correct chaotic/lawful tagging at cast time.
	if attacker_alignment.is_empty() and bool(save_spec.get("consult_caster_alignment", false)):
		if caster_context != null:
			attacker_alignment = String(caster_context.alignment)
	# HD-threshold exemption: some spells (Confusion: HD<3 no save, only HD>2 may
	# save). exempt_under_hd=N means creatures with HD<N get no save (auto-fail
	# → effect applies).
	var exempt_under_hd := int(save_spec.get("exempt_under_hd", 0))
	var out: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		# HD-exemption auto-fail: low-HD creatures get no save (Confusion RAW).
		if exempt_under_hd > 0:
			var entity_hd := _get_entity_hd(entity)
			if entity_hd < exempt_under_hd:
				out[tid] = {
					"rolled": 0, "target": 0, "succeeded": false,
					"category": category, "auto_fail_reason": "below_hd_threshold",
					"entity_hd": entity_hd, "exempt_under_hd": exempt_under_hd}
				continue
		# Auto-success: fear-immune target on a fear-tagged save.
		if is_fear_save and _entity_is_immune_to_fear(entity):
			out[tid] = {
				"rolled": 0, "target": 0, "succeeded": true,
				"category": category, "auto_success_reason": "fear_immune"}
			continue
		var target_value := 17  # safe default for entities without saves
		if entity != null and entity.has_method("get_effective_save"):
			target_value = int(entity.get_effective_save(save_key))
		var fear_bonus := 0
		var element_bonus := 0
		var alignment_bonus := 0
		if entity != null and entity.has_method("get_effective_save"):
			if is_fear_save:
				fear_bonus = int(entity.get_effective_save("save_vs_fear"))
			if not damage_type.is_empty():
				element_bonus = int(entity.get_effective_save("save_vs_" + damage_type))
			if not attacker_alignment.is_empty():
				alignment_bonus = int(entity.get_effective_save("save_vs_" + attacker_alignment))
		var total_modifier := modifier + fear_bonus + element_bonus + alignment_bonus
		var roll = _dice_system.roll_digital(20, 1, total_modifier, "spell_save_" + category)
		var roll_total := int(roll.modified_total) if roll != null else 0
		var succeeded := roll_total >= target_value
		out[tid] = {
			"rolled": roll_total, "target": target_value, "succeeded": succeeded,
			"category": category,
			"fear_bonus": fear_bonus, "is_fear_save": is_fear_save,
			"element_bonus": element_bonus, "damage_type": damage_type,
			"alignment_bonus": alignment_bonus, "attacker_alignment": attacker_alignment,
		}
	return out


func _get_entity_hd(entity: Variant) -> int:
	## Returns the entity's HD/level for HD-threshold checks. CharacterData uses
	## `level`; Combatants and monster fixtures may expose `hit_dice` or
	## `get_hit_dice()`. Defaults to 1 when unknown — the safe permissive choice
	## for save logic (avoids accidentally exempting unknown entities).
	if entity == null:
		return 1
	if entity.has_method("get_hit_dice"):
		return int(entity.get_hit_dice())
	if "hit_dice" in entity:
		return int(entity.hit_dice)
	if "level" in entity:
		return int(entity.level)
	return 1


## Walks target_descriptor.target_ids; returns the subset blocked by Anti-Magic
## Shell or Globe of Invulnerability per RAW. Self-cast (caster targets self
## while the caster is the protected entity) is NOT blocked — RAW: "Self-range
## and touch-range spells used by the caster on himself are not blocked."
##
## Anti-Magic Shell: any creature inside the shell is blocked unless caster ==
## target. (RAW: shell blocks spells entering OR leaving; self-on-self exempt.)
##
## Globe of Invulnerability: blocks if target has the flag AND spell_level ≤
## metadata.blocks_spell_levels_up_to (Minor: ≤3, Major: ≤4). Self-cast exempt.
func _filter_targets_blocked_by_protections(
		target_descriptor: TargetDescriptor,
		targets_by_id: Dictionary,
		spell_choice: SpellChoice,
		caster_context: CasterContext) -> Array:
	var blocked: Array = []
	var caster_id: String = caster_context.caster_id if caster_context != null else ""
	for tid in target_descriptor.target_ids:
		# Self-cast exemption — caster targeting self bypasses both shells.
		if String(tid) == caster_id:
			continue
		var entity = targets_by_id.get(tid, null)
		var flags = _get_flags(entity)
		if flags == null:
			continue
		# Anti-Magic Shell: any spell that crosses the shell boundary is blocked.
		if flags.has_flag("has_anti_magic_shell"):
			blocked.append(tid)
			continue
		# Globe of Invulnerability: blocks ≤ N-level spells.
		if flags.has_flag("has_globe_of_invulnerability"):
			var entries: Array = flags.get_flag_source_entries("has_globe_of_invulnerability")
			if entries.size() > 0:
				var meta: Dictionary = entries[0].get("metadata", {})
				var blocks_up_to: int = int(meta.get("blocks_spell_levels_up_to", 0))
				if spell_choice.level <= blocks_up_to:
					blocked.append(tid)
					continue
	return blocked


func _entity_is_immune_to_fear(entity: Variant) -> bool:
	## Routes the immunity check by entity type. Combatants expose
	## `is_immune_to_fear()` directly; CharacterData has no condition state of
	## its own (conditions live on the Combatant wrapper at combat time and
	## on a future condition tracker for out-of-combat). Unknown entities
	## default to not-immune (the safe permissive choice).
	if entity == null:
		return false
	if entity.has_method("is_immune_to_fear"):
		return entity.is_immune_to_fear()
	return false


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
		condition_records: Array,
		side_flip_records: Array = []) -> Dictionary:
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
		# Charm side-flip records (Tier 4 follow-up, 2026-06-01). The
		# cleanup callback restores target.side to original_side on
		# duration expiry / dispel / concentration break.
		"applied_side_flips": side_flip_records,
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
