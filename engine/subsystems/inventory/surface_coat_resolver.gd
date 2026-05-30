class_name SurfaceCoatResolver
extends RefCounted

## Shared resolver for items / spells that apply a surface coat — either to a
## creature ("anointed with oil") or to a 10' x 10' floor patch / object
## ("poured out and slicked"). Oil of Slipperiness is the first consumer
## (2026-05-30); future Grease spell, Oil of Sharpness, etc. plug into the
## same `coat_spec` API.
##
## The resolver is intentionally GENERIC over the coat mechanic. The caller
## passes a `coat_spec` Dictionary describing what flag / cell-condition to
## set and the duration; the resolver handles the source_id mint, the
## ActiveEffectTracker registration (so duration ticks unwind cleanly), the
## item consumption (one application per dose, only on success), and the
## per-cell occupancy for the 10' x 10' patch (4 cells of 5'×5' each).
##
## Per the project's reusability target (Jedidiah 2026-05-29):
##   "Oil of slipperiness we will also keep — there should be other oil items
##    and grease/oil spells that need the same kind of surface coat resolver,
##    so as long as its resolvers are re-usable it is worthwhile to build."
##
## RAW anchor for Oil of Slipperiness (Slipperiness spell rules/pc_spell_catalog_f-u.xml:1048-1067):
##   - Range: touch
##   - Duration: 3 turns
##   - Targets: Character, Objects, or one 10' x 10' patch of floor
##   - Creature mode: cannot be restrained / grabbed by grasping attacks
##     (ropes, chains, cuffs, constricting creatures)
##   - Surface mode: anyone moving or standing on the patch makes a
##     proficiency throw of 20+ each round or falls down
##   - Object mode: attack throw vs AC 10 to grab or hold (V1 defers — no
##     object inventory surface that consumes coats yet)
##
## V1 scope:
##   - Creature mode: sets the `is_slippery_self` EntityFlag on the target,
##     sourced by "surface_coat:<item_id>:<target_id>" so the prefix-clear
##     sweeps it on duration expiry. Refreshes (re-apply) update metadata
##     instead of stacking, mirroring how ActiveEffectTracker handles
##     concurrent same-source effects.
##   - Cell mode: applies the spec's condition_key (e.g. "slippery") to the
##     anchor cell + 3 adjacent cells covering the 10' x 10' patch via
##     CellSurfaceConditions. The patch is laid out as a 2x2 square anchored
##     at the requested cell (positive x + positive y); diagnostics return
##     the populated cell list.
##   - Object mode: NOT IMPLEMENTED in V1. The catalog has no surface
##     consumer for coated-weapon items yet (Oil of Sharpness, etc., are
##     deferred). Calling apply_oil_to_object() returns a clear failure.
##
## Out of scope for V1:
##   - Movement-resolver hook for slippery-patch save throws (the cell
##     condition is set; consuming it for save-on-cross is a follow-up).
##   - Grapple-resistance hook for the creature mode (the flag is set; the
##     attack resolver doesn't yet read it).
##   - Per-tick condition re-roll (the spell text says "each round" /
##     "each round" — V1 sets the condition for the duration; the per-tick
##     throw is the consumer's responsibility once the integration lands).
##   - DB persistence — coats live in memory only. Save+reload during an
##     oiled visit drops the coat (deferred). For dungeon visits this is fine
##     because the use-case is mid-combat or mid-room.

# ---------------------------------------------------------------------------
# Public — entry points
# ---------------------------------------------------------------------------

## Apply an oil (or analog surface coat) to a creature.
##
## Returns:
##   {
##     success: bool,
##     message: String,                   — human-readable status line
##     consumed: bool,                    — whether the oil dose was deleted
##     applied_flag_key: String,          — the EntityFlag set on the target
##     effect_id: String,                 — the ActiveEffectTracker id for the
##                                          duration tick. "" on failure.
##     source_id: String,                 — the EntityFlag source_id (used by
##                                          tests + callers to clear manually).
##   }
##
## [param item_id]         the inventory_items.id of the oil being applied. A
##                          successful application deletes the row (oils are
##                          one-dose like potions).
## [param target_creature]  the live entity (CharacterData / Combatant) being
##                          anointed. Must expose `.flags` (EntityFlags).
## [param coat_spec]        the coat mechanic dict. Required keys:
##                          - `flag_key`: String   — EntityFlag to set on target.
##                          - `duration_type`: String — "turns" | "rounds" | etc.
##                          - `duration_remaining`: int — quantity for above.
##                          - `caster_level`: int  — for dispel-check parity
##                            (matches the binding's caster_level convention).
##                          - `spell_key`: String  — diagnostic / tracker label
##                            (e.g. "slipperiness"). Mirrors potion spell_key.
## [param effect_tracker]   ActiveEffectTracker instance — the resolver
##                          registers the effect for duration tick. The
##                          tracker's cleanup_callback (registered by the
##                          CastingResolver) is responsible for clearing the
##                          flag on expiry / dispel by walking the
##                          `applied_flags` list, mirroring spell-effect
##                          unwind.
static func apply_oil_to_creature(
		item_id: String,
		target_creature,
		coat_spec: Dictionary,
		effect_tracker: ActiveEffectTracker) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"consumed": false,
		"applied_flag_key": "",
		"effect_id": "",
		"source_id": "",
	}

	# 1. Validate inputs.
	if item_id.is_empty():
		empty["message"] = "apply_oil_to_creature: item_id is required."
		return empty
	if target_creature == null:
		empty["message"] = "apply_oil_to_creature: target_creature is required."
		return empty
	var target_flags = _get_target_flags(target_creature)
	if target_flags == null:
		empty["message"] = "apply_oil_to_creature: target has no EntityFlags."
		return empty
	var validation := _validate_coat_spec(coat_spec, "creature")
	if not bool(validation["ok"]):
		empty["message"] = str(validation["message"])
		return empty
	if effect_tracker == null:
		empty["message"] = "apply_oil_to_creature: effect_tracker is required."
		return empty

	# 2. Look up the inventory row to confirm the oil exists. We deliberately
	#    DON'T category-check here — the spec dictates which items use this
	#    resolver (oils belong to "potion" category in the catalog but are
	#    applied not drunk; the MagicItemActivator routes based on item_key
	#    prefix, not category).
	var item_row: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	if item_row.is_empty():
		empty["message"] = "Oil not found in inventory (id=%s)." % item_id
		return empty
	var item_name: String = str(item_row.get("name", item_row.get("item_key", item_id)))

	# 3. Mint the source_id + effect_id. Use the item_id as the source_id
	#    salt so re-applying the same oil to the same target REFRESHES the
	#    flag's metadata (set_flag's same-source path) instead of stacking.
	#    Different oils (different item_ids) produce distinct source_ids and
	#    stack as concurrent effect sources, but the FLAG itself stays
	#    boolean — the multi-source semantics means "any active oil = flag is
	#    on".
	var target_id: String = _get_target_id(target_creature)
	var source_id: String = "surface_coat:%s:%s" % [item_id, target_id]
	var effect_id: String = "surface_coat:%s" % item_id
	var flag_key: String = str(coat_spec["flag_key"])
	var spell_key: String = str(coat_spec.get("spell_key", ""))

	# 4. If this exact effect_id is already tracked (re-applying the same
	#    inventory_item row to the same target), remove the prior effect
	#    first so duration restarts cleanly. This is the "no stacking,
	#    refresh duration" semantic.
	if effect_tracker.has_effect(effect_id):
		var prior: Dictionary = effect_tracker.remove_effect(effect_id)
		# Walk the prior's applied_flags to unwind the flag from any targets
		# it touched (paranoid: the same item might have been applied to a
		# different target before).
		for rec in prior.get("applied_flags", []):
			# Best-effort: only the in-memory target_flags is reliably
			# unwound here; cross-target prior application would need a
			# target_lookup. V1 assumes the same item targets the same
			# entity each application.
			if String(rec.get("character_id", "")) == target_id:
				target_flags.clear_flag(
					String(rec.get("flag_key", "")), String(rec.get("source_id", "")))

	# 5. Set the flag with the source_id + metadata.
	var metadata := {
		"source_kind": "surface_coat",
		"item_id": item_id,
		"item_name": item_name,
		"spell_key": spell_key,
		"applied_via": "apply_oil_to_creature",
	}
	target_flags.set_flag(flag_key, source_id, metadata)

	# 6. Register the effect with the tracker so duration ticks unwind cleanly.
	#    The effect's applied_flags list mirrors the CastingResolver convention
	#    so the existing cleanup_callback can sweep it on expiry / dispel.
	var effect := {
		"effect_id": effect_id,
		"spell_key": spell_key,
		"caster_id": "",  # No spell caster — the applier is the item.
		"caster_level": int(coat_spec.get("caster_level", 1)),
		"target_ids": [target_id],
		"effect_type": "flag",
		"applied_modifiers": [],
		"applied_conditions": [],
		"applied_flags": [{
			"character_id": target_id,
			"flag_key": flag_key,
			"source_id": source_id,
		}],
		"duration_type": str(coat_spec["duration_type"]),
		"duration_remaining": int(coat_spec["duration_remaining"]),
		"requires_concentration": false,
		"is_active": true,
		"metadata": {
			"source_kind": "surface_coat",
			"coat_mode": "creature",
			"item_id": item_id,
			"item_name": item_name,
		},
	}
	effect_tracker.add_effect(effect)

	# 7. Consume the dose.
	var consumed: bool = CampaignRepository.remove_inventory_item(item_id)
	return {
		"success": true,
		"message": "Applied %s to %s." % [item_name, _display_name(target_creature)],
		"consumed": consumed,
		"applied_flag_key": flag_key,
		"effect_id": effect_id,
		"source_id": source_id,
	}


## Apply an oil (or analog surface coat) to one 10' x 10' patch of floor.
##
## Returns:
##   {
##     success: bool,
##     message: String,
##     consumed: bool,
##     applied_condition_key: String,    — CellSurfaceConditions key set on cells
##     effect_id: String,
##     source_id: String,                 — the cell-condition source_id prefix
##     coated_cells: Array[Vector3i],    — the cells that received the coat
##   }
##
## [param item_id]              the inventory_items.id of the oil being applied.
## [param map_id]               runtime map identifier the cell belongs to.
## [param anchor_cell]          Vector3i — the corner of the 10' x 10' patch.
##                               The patch lays out as a 2x2 square covering
##                               (anchor.x, anchor.y), (anchor.x+1, anchor.y),
##                               (anchor.x, anchor.y+1), (anchor.x+1, anchor.y+1)
##                               at level = anchor.z.
## [param area_size_ft]         must be 10 in V1 (matches the spell's "one 10' x 10' patch").
##                               Parameterized for future analogs (Grease spell may
##                               have a different footprint).
## [param coat_spec]            mechanic dict — required keys:
##                              - `condition_key`: String — CellSurfaceConditions key.
##                              - `duration_type`: String — "turns" / "rounds".
##                              - `duration_remaining`: int.
##                              - `caster_level`: int — dispel parity.
##                              - `spell_key`: String — diagnostic label.
## [param effect_tracker]       ActiveEffectTracker instance.
## [param surface_conditions]   CellSurfaceConditions instance — the resolver
##                               writes the coat onto every cell of the patch.
static func apply_oil_to_cell(
		item_id: String,
		map_id: String,
		anchor_cell: Vector3i,
		area_size_ft: int,
		coat_spec: Dictionary,
		effect_tracker: ActiveEffectTracker,
		surface_conditions: CellSurfaceConditions) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"consumed": false,
		"applied_condition_key": "",
		"effect_id": "",
		"source_id": "",
		"coated_cells": [] as Array[Vector3i],
	}

	# 1. Validate inputs.
	if item_id.is_empty():
		empty["message"] = "apply_oil_to_cell: item_id is required."
		return empty
	if map_id.is_empty():
		empty["message"] = "apply_oil_to_cell: map_id is required."
		return empty
	if effect_tracker == null:
		empty["message"] = "apply_oil_to_cell: effect_tracker is required."
		return empty
	if surface_conditions == null:
		empty["message"] = "apply_oil_to_cell: surface_conditions is required."
		return empty
	if area_size_ft <= 0 or area_size_ft % 5 != 0:
		empty["message"] = (
			"apply_oil_to_cell: area_size_ft must be a positive multiple of 5 "
			+ "(grid is 5'); got %d." % area_size_ft)
		return empty
	var validation := _validate_coat_spec(coat_spec, "cell")
	if not bool(validation["ok"]):
		empty["message"] = str(validation["message"])
		return empty

	var item_row: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	if item_row.is_empty():
		empty["message"] = "Oil not found in inventory (id=%s)." % item_id
		return empty
	var item_name: String = str(item_row.get("name", item_row.get("item_key", item_id)))

	# 2. Compute the patch cells. Each grid cell is 5' square; an N'xN' patch
	#    covers (N/5) x (N/5) cells. For Oil of Slipperiness V1 this is 2x2.
	var cells_per_side: int = area_size_ft / 5
	var coated_cells: Array[Vector3i] = []
	for dx in range(cells_per_side):
		for dy in range(cells_per_side):
			coated_cells.append(Vector3i(
				anchor_cell.x + dx,
				anchor_cell.y + dy,
				anchor_cell.z))

	# 3. Mint source_id + effect_id. The cell-mode source_id prefix encodes
	#    the effect_id so a prefix-clear sweep can yank every cell at once
	#    on duration expiry.
	var effect_id: String = "surface_coat:%s" % item_id
	var source_id_prefix: String = "surface_coat:%s:cell:" % item_id
	var condition_key: String = str(coat_spec["condition_key"])
	var spell_key: String = str(coat_spec.get("spell_key", ""))

	# 4. If the same effect_id was active (re-applying the same dose to a new
	#    spot), clear the prior cell coats first. The prefix-based sweep on
	#    CellSurfaceConditions cleans up every cell the prior application
	#    touched without needing to know which they were.
	if effect_tracker.has_effect(effect_id):
		effect_tracker.remove_effect(effect_id)
		surface_conditions.clear_all_from_source_prefix(source_id_prefix)

	# 5. Set the condition on each cell.
	var coat_metadata := {
		"source_kind": "surface_coat",
		"item_id": item_id,
		"item_name": item_name,
		"spell_key": spell_key,
		"applied_via": "apply_oil_to_cell",
		"area_size_ft": area_size_ft,
	}
	for cell in coated_cells:
		var source_id: String = source_id_prefix + "%d,%d,%d" % [cell.x, cell.y, cell.z]
		surface_conditions.set_condition(condition_key, map_id, cell, source_id, coat_metadata)

	# 6. Register the effect with the tracker. We attach the coated_cells +
	#    map_id + source_id_prefix on metadata so the CellSurfaceConditions
	#    unwind can run from the cleanup_callback path (a future cleanup
	#    pass will read metadata["coat_mode"]=="cell" and dispatch to
	#    surface_conditions.clear_all_from_source_prefix).
	var effect := {
		"effect_id": effect_id,
		"spell_key": spell_key,
		"caster_id": "",
		"caster_level": int(coat_spec.get("caster_level", 1)),
		"target_ids": [] as Array[String],
		"effect_type": "condition",
		"applied_modifiers": [],
		"applied_conditions": [],
		"applied_flags": [],
		"duration_type": str(coat_spec["duration_type"]),
		"duration_remaining": int(coat_spec["duration_remaining"]),
		"requires_concentration": false,
		"is_active": true,
		"metadata": {
			"source_kind": "surface_coat",
			"coat_mode": "cell",
			"item_id": item_id,
			"item_name": item_name,
			"map_id": map_id,
			"condition_key": condition_key,
			"coated_cells": coated_cells,
			"source_id_prefix": source_id_prefix,
		},
	}
	effect_tracker.add_effect(effect)

	# 7. Consume the dose.
	var consumed: bool = CampaignRepository.remove_inventory_item(item_id)
	return {
		"success": true,
		"message": "Applied %s to %d cells centered at (%d,%d,%d)." % [
			item_name, coated_cells.size(),
			anchor_cell.x, anchor_cell.y, anchor_cell.z],
		"consumed": consumed,
		"applied_condition_key": condition_key,
		"effect_id": effect_id,
		"source_id": source_id_prefix,
		"coated_cells": coated_cells,
	}


## Apply an oil to an object (V1 = NOT IMPLEMENTED). Returns a clear failure
## so callers see this is wired but deferred. The Slipperiness spell's
## "Objects" mode (20 arrows, 2 one-handed weapons, 1 two-handed weapon) is
## a follow-up — there's no inventory surface yet that consumes "coated"
## weapon items in attack throws.
static func apply_oil_to_object(
		item_id: String,
		_target_inventory_item_id: String,
		_coat_spec: Dictionary,
		_effect_tracker: ActiveEffectTracker) -> Dictionary:
	return {
		"success": false,
		"message": (
			"apply_oil_to_object: V1 not implemented — object-coat mode "
			+ "deferred until weapon-item attack-throw path consumes coats. "
			+ "item_id=%s" % item_id),
		"consumed": false,
		"applied_flag_key": "",
		"effect_id": "",
		"source_id": "",
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Validate the shape of a coat_spec dict. Used by both creature + cell paths.
static func _validate_coat_spec(coat_spec: Dictionary, mode: String) -> Dictionary:
	if coat_spec.is_empty():
		return {"ok": false, "message": "coat_spec is empty."}
	if not coat_spec.has("duration_type"):
		return {"ok": false, "message": "coat_spec missing duration_type."}
	if not coat_spec.has("duration_remaining"):
		return {"ok": false, "message": "coat_spec missing duration_remaining."}
	if int(coat_spec["duration_remaining"]) <= 0:
		return {"ok": false, "message": "coat_spec duration_remaining must be > 0."}
	match mode:
		"creature":
			if not coat_spec.has("flag_key"):
				return {"ok": false, "message": "creature coat_spec missing flag_key."}
			if String(coat_spec["flag_key"]).is_empty():
				return {"ok": false, "message": "creature coat_spec flag_key is empty."}
		"cell":
			if not coat_spec.has("condition_key"):
				return {"ok": false, "message": "cell coat_spec missing condition_key."}
			if String(coat_spec["condition_key"]).is_empty():
				return {"ok": false, "message": "cell coat_spec condition_key is empty."}
	return {"ok": true, "message": ""}


## Pull the EntityFlags container off a target (CharacterData OR Combatant).
## Mirrors the multi-type accessor pattern in CastingResolver._get_flags.
static func _get_target_flags(target) -> EntityFlags:
	if target == null:
		return null
	if target is CharacterData:
		return target.flags
	if "flags" in target:
		return target.flags
	return null


## Pull a target's id. CharacterData has `id`; Combatant has `character_id`
## or `id`. Mirrors CastingResolver's dual-shape accessors.
static func _get_target_id(target) -> String:
	if target == null:
		return ""
	if target is CharacterData:
		return target.id
	if "id" in target:
		return str(target.id)
	if "character_id" in target:
		return str(target.character_id)
	return ""


## Display name for the success-message line. Best-effort across shapes.
static func _display_name(target) -> String:
	if target == null:
		return "?"
	if target is CharacterData:
		return target.name if not target.name.is_empty() else target.id
	if "name" in target:
		return str(target.name)
	return _get_target_id(target)


# ---------------------------------------------------------------------------
# Canonical coat specs (factories — keep the activator + tests in sync)
# ---------------------------------------------------------------------------

## Coat spec for Oil of Slipperiness creature mode.
## - flag_key: is_slippery_self (cannot be grappled / restrained / grabbed)
## - duration: 3 turns (matches the Slipperiness spell rules/pc_spell_catalog_f-u.xml:1056)
## - spell_key: slipperiness (for diagnostics + matches the catalog spell entry)
static func oil_of_slipperiness_creature_spec() -> Dictionary:
	return {
		"flag_key": "is_slippery_self",
		"duration_type": "turns",
		"duration_remaining": 3,
		"caster_level": 1,
		"spell_key": "slipperiness",
	}


## Coat spec for Oil of Slipperiness surface mode.
## - condition_key: slippery (cells carrying this condition apply the
##   "proficiency throw 20+ or fall down" rule when entities cross — the
##   movement / combat consumer will read this when wired)
## - duration: 3 turns
static func oil_of_slipperiness_cell_spec() -> Dictionary:
	return {
		"condition_key": "slippery",
		"duration_type": "turns",
		"duration_remaining": 3,
		"caster_level": 1,
		"spell_key": "slipperiness",
	}
