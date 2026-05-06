class_name PolymorphSelfResolver
extends RefCounted

## Polymorph Self (Arcane L4) — caster transforms into another living creature.
##
## ACKS RAW (acore_spell_catalog_k-w_summary.xml):
##   - Self-only target. Range: self.
##   - Duration: 6 turns plus 1 turn per level.
##   - Assumed form must be a living creature with no more HD than caster level.
##   - Caster gains physical capabilities and statistics of the new form.
##   - Caster RETAINS own mental abilities (INT, WIS, CHA, spellcasting).
##   - Caster gains all physical attacks of the form.
##   - If slain, caster reverts to original form (corpse is original).
##   - Caster may end the spell early.
##   - Cannot assume incorporeal or gaseous form.
##   - Does NOT grant special, supernatural, or spell-like abilities (no breath
##     weapon, no gaze attacks, no innate spellcasting from form).
##
## Resolver responsibilities:
##   - Snapshot caster's original physical stats (HP, AC, attack throw, movement,
##     attacks per round, damage dice) onto persist_metadata.
##   - Apply the form's physical stat overrides (held in resolver_args.form_profile).
##   - Set is_polymorphed_self flag with metadata.form_key + reverts_on_death=true.
##   - Active_effect tracker reverts on duration expire / break / death by
##     restoring the snapshot.
##
## ~95 LOC.


func resolve(args: Dictionary) -> Dictionary:
	var caster_context = args.get("caster_context")
	var caster_entity = args.get("caster_entity")
	var spell_choice = args.get("spell_choice")
	var step_payload: Dictionary = args.get("step_payload", {})
	var resolver_args: Dictionary = step_payload.get("resolver_args", {})

	if caster_context == null:
		return {"applied": false, "reason": "polymorph_self_resolver: missing caster_context"}

	# Form profile (picked by the targeting UI; resolver_args holds the form's
	# physical stats). Required HD-cap check: form HD ≤ caster level per RAW.
	var form_profile: Dictionary = resolver_args.get("form_profile", {})
	var form_hd: int = int(form_profile.get("hit_dice", 1))
	if form_hd > caster_context.caster_level:
		return {
			"applied": false,
			"reason": "form_hd_exceeds_caster_level",
			"form_hd": form_hd,
			"caster_level": caster_context.caster_level,
		}

	# Snapshot the caster's original physical stats so the active_effect can
	# revert them at expiration / death. CharacterData carries these directly.
	var snapshot: Dictionary = {}
	if caster_entity != null:
		snapshot = {
			"armor_class": int(caster_entity.armor_class) if "armor_class" in caster_entity else 0,
			"attack_throw": int(caster_entity.attack_throw) if "attack_throw" in caster_entity else 10,
			"base_movement": int(caster_entity.base_movement) if "base_movement" in caster_entity else 120,
			"hp_max": int(caster_entity.hp_max) if "hp_max" in caster_entity else 1,
		}

	# Apply form's physical overrides. Per RAW the caster keeps mental abilities,
	# so we touch only physical fields.
	if caster_entity != null:
		if form_profile.has("armor_class"):
			caster_entity.armor_class = int(form_profile["armor_class"])
		if form_profile.has("attack_throw"):
			caster_entity.attack_throw = int(form_profile["attack_throw"])
		if form_profile.has("base_movement"):
			caster_entity.base_movement = int(form_profile["base_movement"])

	# Set flag with metadata for the runtime form layer to render + apply
	# physical attacks.
	var entity_flags = null
	if caster_entity != null and "flags" in caster_entity:
		entity_flags = caster_entity.flags
	var source_id := "spell:polymorph_self:%s" % caster_context.caster_id
	if entity_flags != null:
		entity_flags.set_flag("is_polymorphed_self", source_id, {
			"form_key": String(form_profile.get("form_key", "")),
			"form_hd": form_hd,
			"reverts_on_death": true,
			"snapshot": snapshot,
			"caster_id": caster_context.caster_id,
		})

	return {
		"applied": true,
		"form_key": String(form_profile.get("form_key", "")),
		"form_hd": form_hd,
		"snapshot": snapshot,
		"caster_id": caster_context.caster_id,
		"spell_key": spell_choice.spell_key if spell_choice != null else "polymorph_self",
		"persist_metadata": {
			"polymorph_self_snapshot": snapshot,
			"form_profile": form_profile,
		},
	}
