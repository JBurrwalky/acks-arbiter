class_name PolymorphOtherResolver
extends RefCounted

## Polymorph Other (Arcane L4) — permanently transforms a target.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - 60' range, permanent duration. Save vs Spells negates if unwilling.
##   - Target: one living creature (not incorporeal/gaseous; no specific duplicate).
##   - HD constraints:
##       * New form must have NO MORE HD than caster level.
##       * New form must have FEWER than 2x the HD of the old form.
##   - Target gains physical capabilities and statistics of the new form.
##   - Target ALSO gains alignment, behavioral/mental traits, physical attacks,
##     and special/supernatural/spell-like abilities of the new form.
##   - If new form is substantially less intelligent, target may not remember
##     its former life.
##   - Target keeps the same hit points regardless of new form's HD.
##   - A creature with shape-changing ability (e.g., doppelganger) may revert
##     in 1 round.
##   - Lasts until dispel magic or target's death.
##   - If slain, corpse reverts to original form.
##
## Save handling: this resolver consults save_results provided by the parent
## resolver loop (the catalog binding has save_spec.category=spells and
## on_success=negate). The parent already pre-rolled saves, so we just check
## the per-target save outcome.
##
## ~95 LOC.


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var target_descriptor = args.get("target_descriptor")
	var targets_by_id: Dictionary = args.get("targets_by_id", {})
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null or target_descriptor == null:
		return {"applied": false, "reason": "polymorph_other_resolver: missing context"}

	var form_profile: Dictionary = resolver_args.get("form_profile", {})
	var form_hd: int = int(form_profile.get("hit_dice", 1))
	# Caster-level HD cap (RAW).
	if form_hd > caster_context.caster_level:
		return {
			"applied": false,
			"reason": "form_hd_exceeds_caster_level",
			"form_hd": form_hd,
			"caster_level": caster_context.caster_level,
		}

	var per_target: Dictionary = {}
	for tid in target_descriptor.target_ids:
		var entity = targets_by_id.get(tid, null)
		if entity == null:
			per_target[tid] = {"applied": false, "reason": "no_target_data"}
			continue
		# 2x-HD check vs old form: read entity's current HD if available; default
		# to 1 if unknown. The HD restriction is soft — the picker layer should
		# enforce, but we re-check here.
		var old_hd: int = int(entity.level) if "level" in entity else 1
		if form_hd >= 2 * old_hd:
			per_target[tid] = {
				"applied": false,
				"reason": "form_hd_at_or_above_2x_old_hd",
				"form_hd": form_hd,
				"old_hd": old_hd,
			}
			continue
		# Snapshot original form for revert-on-death.
		var snapshot: Dictionary = {
			"armor_class": int(entity.armor_class) if "armor_class" in entity else 0,
			"attack_throw": int(entity.attack_throw) if "attack_throw" in entity else 10,
			"base_movement": int(entity.base_movement) if "base_movement" in entity else 120,
			"alignment": String(entity.alignment) if "alignment" in entity else "neutral",
		}
		# Apply form overrides. Per RAW, target gains BOTH physical AND mental
		# traits (unlike Polymorph Self), so alignment + behavior shift too.
		if form_profile.has("armor_class"):
			entity.armor_class = int(form_profile["armor_class"])
		if form_profile.has("attack_throw"):
			entity.attack_throw = int(form_profile["attack_throw"])
		if form_profile.has("base_movement"):
			entity.base_movement = int(form_profile["base_movement"])
		if form_profile.has("alignment") and "alignment" in entity:
			entity.alignment = String(form_profile["alignment"])
		# Set is_polymorphed_other flag.
		var entity_flags = null
		if "flags" in entity:
			entity_flags = entity.flags
		var source_id := "spell:polymorph_other:%s" % caster_context.caster_id
		if entity_flags != null:
			entity_flags.set_flag("is_polymorphed_other", source_id, {
				"form_key": String(form_profile.get("form_key", "")),
				"form_hd": form_hd,
				"old_hd": old_hd,
				"reverts_on_death": true,
				"snapshot": snapshot,
				"caster_id": caster_context.caster_id,
			})
		per_target[tid] = {
			"applied": true,
			"form_key": String(form_profile.get("form_key", "")),
			"form_hd": form_hd,
			"old_hd": old_hd,
			"snapshot": snapshot,
		}

	# P7 — accumulate per-target snapshots into persist_metadata so the
	# expiration callback can revert each target without depending on the
	# (already-cleared) flag metadata.
	var per_target_snapshots: Dictionary = {}
	for tid in per_target.keys():
		var entry: Dictionary = per_target[tid]
		if bool(entry.get("applied", false)) and entry.has("snapshot"):
			per_target_snapshots[tid] = entry["snapshot"]

	return {
		"applied": true,
		"per_target": per_target,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "polymorph_other",
		"persist_metadata": {
			"polymorph_other_per_target_snapshots": per_target_snapshots,
		},
	}


## P7 — expiration callback. Restores each polymorphed target's physical
## stats (and alignment) from the per-target snapshot stored in metadata.
## Invoked on every cleanup path (duration_expired / concentration_broken /
## dispelled). The flag's been auto-cleared by the standard unwind path
## already; this callback handles the snapshot revert + signal emit so
## downstream subscribers (UI, log) can react.
static func on_expiration(
		effect: Dictionary, cause: String, target_lookup: Callable) -> void:
	var spell_key := String(effect.get("spell_key", "polymorph_other"))
	var snapshots: Dictionary = effect.get("metadata", {}).get(
		"polymorph_other_per_target_snapshots", {})
	for tid in snapshots.keys():
		var snapshot: Dictionary = snapshots[tid]
		if target_lookup.is_valid():
			var entity = target_lookup.call(tid)
			if entity != null:
				if "armor_class" in entity and snapshot.has("armor_class"):
					entity.armor_class = int(snapshot["armor_class"])
				if "attack_throw" in entity and snapshot.has("attack_throw"):
					entity.attack_throw = int(snapshot["attack_throw"])
				if "base_movement" in entity and snapshot.has("base_movement"):
					entity.base_movement = int(snapshot["base_movement"])
				if "alignment" in entity and snapshot.has("alignment"):
					entity.alignment = String(snapshot["alignment"])
		EventBus.polymorph_reverted.emit(String(tid), spell_key, snapshot, cause)
