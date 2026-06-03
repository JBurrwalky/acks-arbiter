class_name MagicItemActivator
extends RefCounted

## Bridges magic-item activation ("drink potion", "use wand", "tap staff",
## later "wear ring", etc.) into the existing spell-effect pipeline
## (`CastingResolver`).
##
## V1 covers THREE consumption models, all keyed on the catalog's
## `spell_binding` field (`data/treasure/magic_item_catalog.json`):
##
##   1. **Potions** (one-shot, `drink_potion`): the bottle is deleted from
##      inventory on a successful cast. A failed cast doesn't waste the dose
##      (RAW item-activation interpretation: a magic-system failure shouldn't
##      drain the bottle).
##
##   2. **Charged items — wands, staves, rods** (charge-per-use,
##      `activate_charged_item`): one charge per cast via the
##      `inventory_items.uses_remaining` column. When charges reach 0 the item
##      becomes useless and non-magical
##      (acore_treasure_and_magic_items_rules.xml identification_and_use:
##      "An item with no charges remaining becomes useless and non-magical").
##      Initial charge count is the binding's `default_charges` (set on the
##      inventory_items row at treasure-instantiation time).
##
##   3. **Worn-triggered items — rings, helms, boots, brooms, etc.**
##      (`activate_worn_item`): activated on demand while equipped. V1 thin
##      slice = unlimited uses (no charge decrement); per-day cooldowns +
##      RAW per-item-charge limits (e.g. Helm of Teleportation's once-per-day)
##      land in a follow-up pass. Persistent-while-equipped items (Ring of
##      Protection, Cloak of Protection, Ring of Water Walking, Ring of Fire
##      Resistance) are a DIFFERENT mechanism — handled by
##      `WornMagicEffectResolver` at equip-state change, not through this
##      activator.
##
## Design — why this lives here:
##   - It's PURE composition of existing services: MagicItemCatalog +
##     CastingResolver + CampaignRepository. No new game-rule logic.
##   - All static methods (matches the TreasureLootService / Treasure-
##     PlacementService pattern; not an autoload).
##   - Injected dependencies (casting_resolver, magic_item_catalog) so tests
##     can pass stubs without standing up the full autoload graph.
##
## Out of scope (deferred follow-ups):
##   - Wands / staves: charge tracking via uses_remaining decrement;
##     designated-target casting; per-item caster_level.
##   - Rings / boots / cloaks: persistent-while-equipped effects via
##     WornMagicEffectResolver; on-equip / on-unequip hooks.
##   - Found scrolls: per-scroll spell list materialization + identify flow.
##   - Cursed potions: drinking a Potion of Poison etc. is a separate
##     resolver (no spell mapping).
##   - Identification gate: the drinker doesn't know what the potion does
##     until tasted (RAW :184-195). V1 assumes identified — the
##     identification subsystem layers on top.
##
##   4. **Applied oils (Oil of Slipperiness, future Oil of Sharpness,
##      grease/oil spells)** — items in the catalog's `potion` category that
##      are APPLIED (poured onto a surface or anointed onto a creature),
##      not drunk. Routed through `apply_oil` → `SurfaceCoatResolver`,
##      which composes the same "spec-driven mechanic" pattern used for
##      future grease-like spells.


# ---------------------------------------------------------------------------
# Public — entry points
# ---------------------------------------------------------------------------

## Drink a potion. Returns:
##   {
##     success: bool,
##     message: String,         — human-readable status line
##     consumed: bool,          — whether the potion was deleted from inventory
##     spell_key: String,       — the spell that was cast (or "" on lookup failure)
##     casting_result: ResolutionResult — the resolver's full output (or null)
##   }
##
## [param item_id]         the inventory_items.id of the potion the drinker is
##                          consuming.
## [param drinker]          the live CharacterData drinking the potion. Becomes
##                          the caster_id + caster_name on the CasterContext.
## [param casting_resolver] a constructed CastingResolver. Tests pass a
##                          minimal-graph instance; production calls pass the
##                          live singleton.
## [param magic_item_catalog] a loaded MagicItemCatalog. Tests can pass a
##                          freshly-instantiated one.
## [param target_id]        (single_creature target_mode only) the entity id
##                          the drinker designates as the spell target.
## [param target_entity]    (single_creature target_mode only) the live entity
##                          object for the designated target (used by spells
##                          that mutate the target).
## [param map_context]      defaults to "combat_grid"; pass the drinker's
##                          current context so the resolver dispatches geometry
##                          against the right map.
## [param origin_cell]      drinker's voxel position. For self-targeted spells
##                          this is the spell's origin too.
static func drink_potion(
		item_id: String,
		drinker: CharacterData,
		casting_resolver: CastingResolver,
		magic_item_catalog: MagicItemCatalog,
		target_id: String = "",
		target_entity = null,
		map_context: String = "combat_grid",
		origin_cell: Vector3i = Vector3i.ZERO) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"consumed": false,
		"spell_key": "",
		"casting_result": null,
	}

	# 1. Look up the inventory row to get the item_key (the catalog index).
	var item_row: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	if item_row.is_empty():
		empty["message"] = "Potion not found in inventory (id=%s)." % item_id
		return empty
	var item_key: String = str(item_row.get("item_key", ""))

	# 2. Look up the catalog entry for the spell_binding.
	var catalog_entry: Dictionary = magic_item_catalog.get_item(item_key)
	if catalog_entry.is_empty():
		empty["message"] = "Item '%s' has no catalog entry." % item_key
		return empty
	if str(catalog_entry.get("category", "")) != "potion":
		empty["message"] = "Item '%s' is not a potion (category=%s)." % [
			item_key, catalog_entry.get("category", "?")]
		return empty
	# Tier 4 Cluster A (2026-06-01): potions whose effect bypasses the spell
	# pipeline (Potion of Poison, Potion of *_Control). The catalog stamps
	# `direct_potion_effect` with an `effect_kind` field; route to the
	# per-effect resolver. Returns early — these never fall through to the
	# spell_binding path. target_id + target_entity are forwarded for
	# control-creature effects (the Control batch); poison ignores them.
	var direct_v: Variant = catalog_entry.get("direct_potion_effect", null)
	if direct_v is Dictionary:
		# Thread the tracker through (Option 1 migration 2026-06-01) so the
		# Control resolver can register with the unified cleanup chain.
		var tracker: ActiveEffectTracker = null
		if casting_resolver != null:
			tracker = casting_resolver.get_effect_tracker()
		return _resolve_direct_potion_effect(
			item_id, item_key, catalog_entry, drinker, direct_v as Dictionary,
			target_id, target_entity, tracker)
	var binding_v: Variant = catalog_entry.get("spell_binding", null)
	if not (binding_v is Dictionary):
		empty["message"] = "Potion '%s' has no spell_binding (effect not yet implemented)." % item_key
		return empty
	var binding: Dictionary = binding_v
	empty["spell_key"] = str(binding.get("spell_key", ""))

	# 3. Validate target params + cast via the shared pipeline.
	var target_v: Dictionary = _validate_target(
		binding, "Potion '%s'" % item_key, target_id, target_entity, Vector3i.ZERO)
	if not bool(target_v["ok"]):
		empty["message"] = str(target_v["message"])
		return empty

	var result: ResolutionResult = _cast_via_binding(
		binding, drinker, casting_resolver,
		target_id, target_entity, Vector3i.ZERO,
		map_context, origin_cell)

	# 4. Consume the potion ONLY on success. The hand-drained-bottle rule: a
	# failed cast doesn't waste the dose. Consumed = inventory row deleted
	# (quantity == 1 always for potions in V1; stacks not modeled).
	var consumed: bool = false
	var message: String = ""
	if result != null and result.success:
		consumed = CampaignRepository.remove_inventory_item(item_id)
		message = "Drank '%s' — cast %s." % [str(catalog_entry.get("name", item_key)), binding.get("spell_key", "")]
	else:
		var failures: Array = result.failures if result != null else []
		message = "Failed to activate '%s': %s" % [
			str(catalog_entry.get("name", item_key)),
			"; ".join(failures) if not failures.is_empty() else "unknown error"]

	return {
		"success": result != null and result.success,
		"message": message,
		"consumed": consumed,
		"spell_key": binding.get("spell_key", ""),
		"casting_result": result,
	}


## Use a charged item (wand, staff, rod). Returns:
##   {
##     success: bool,
##     message: String,
##     charges_remaining: int,    — uses_remaining AFTER the activation
##     became_inert: bool,        — true when charges reached 0 and the item
##                                  was cleared of is_magical (RAW: "no
##                                  charges remaining → useless and
##                                  non-magical").
##     spell_key: String,
##     casting_result: ResolutionResult
##   }
##
## [param item_id]         the inventory_items.id of the wand / staff / rod.
## [param wielder]          the live CharacterData using the item. Becomes
##                          caster_id + caster_name on the CasterContext.
## [param target_id]        creature-target id (when target_mode is
##                          "single_creature" or "single_target" with a
##                          creature target).
## [param target_entity]    the live entity for the creature target.
## [param target_cell]      cell-target Vector3i (when target_mode is
##                          "single_target" with an area / cell anchor —
##                          fireball, lightning_bolt, etc.). Vector3i.ZERO
##                          treated as "no cell supplied".
## [param map_context]      "combat_grid" by default; pass the wielder's
##                          current context so geometry dispatches correctly.
## [param origin_cell]      wielder's voxel position (origin for area /
##                          line spells).
##
## A wand with 0 charges remaining fails with "no charges remaining" and the
## item is NOT activated. A failed cast does NOT decrement charges
## (consistent with the potion "failure doesn't waste the dose" rule).
static func activate_charged_item(
		item_id: String,
		wielder: CharacterData,
		casting_resolver: CastingResolver,
		magic_item_catalog: MagicItemCatalog,
		target_id: String = "",
		target_entity = null,
		target_cell: Vector3i = Vector3i.ZERO,
		map_context: String = "combat_grid",
		origin_cell: Vector3i = Vector3i.ZERO) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"charges_remaining": -1,
		"became_inert": false,
		"spell_key": "",
		"casting_result": null,
	}

	# 1. Lookup chain.
	var item_row: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	if item_row.is_empty():
		empty["message"] = "Charged item not found in inventory (id=%s)." % item_id
		return empty
	var item_key: String = str(item_row.get("item_key", ""))
	var catalog_entry: Dictionary = magic_item_catalog.get_item(item_key)
	if catalog_entry.is_empty():
		empty["message"] = "Item '%s' has no catalog entry." % item_key
		return empty
	if str(catalog_entry.get("category", "")) != "rod_staff_wand":
		empty["message"] = "Item '%s' is not a wand / staff / rod (category=%s)." % [
			item_key, catalog_entry.get("category", "?")]
		return empty
	var binding_v: Variant = catalog_entry.get("spell_binding", null)
	if not (binding_v is Dictionary):
		empty["message"] = (
			"Charged item '%s' has no spell_binding (effect not yet implemented)." % item_key)
		return empty
	var binding: Dictionary = binding_v
	empty["spell_key"] = str(binding.get("spell_key", ""))

	# 2. Charge gate — RAW: an item with no charges is useless and non-magical.
	# We treat -1 (catalog default for non-charged items) as "infinite uses"
	# only if the item lacks default_charges; if default_charges WAS set on
	# the binding and the row carries -1, that's a materialization bug and
	# we refuse to fire.
	var current_charges: int = int(item_row.get("uses_remaining", -1))
	empty["charges_remaining"] = current_charges
	if current_charges == 0:
		empty["message"] = (
			"'%s' has no charges remaining (item is useless and non-magical)." %
			str(catalog_entry.get("name", item_key)))
		return empty
	if current_charges < 0 and binding.has("default_charges"):
		empty["message"] = (
			"'%s' is uncharged at the inventory layer (materialization didn't stamp default_charges)." %
			item_key)
		return empty

	# 3. Validate target params against the binding's target_mode.
	var target_v: Dictionary = _validate_target(
		binding, "Charged item '%s'" % item_key, target_id, target_entity, target_cell)
	if not bool(target_v["ok"]):
		empty["message"] = str(target_v["message"])
		return empty

	# 4. Cast.
	var result: ResolutionResult = _cast_via_binding(
		binding, wielder, casting_resolver,
		target_id, target_entity, target_cell,
		map_context, origin_cell)

	# 5. Charge accounting on success only.
	var charges_after: int = current_charges
	var became_inert: bool = false
	var message: String = ""
	if result != null and result.success:
		# Decrement uses_remaining. -1 (unbounded) stays untouched (V1 doesn't
		# yet have unbounded-charge items in the binding map, but defensive).
		if current_charges > 0:
			charges_after = current_charges - 1
			CampaignRepository.db.query_with_bindings(
				"UPDATE inventory_items SET uses_remaining = ? WHERE id = ?",
				[charges_after, item_id])
			if charges_after == 0:
				# RAW: useless and non-magical. Clear is_magical so combat code
				# stops treating the item as enchanted (the +N / magic-required
				# checks read this column).
				CampaignRepository.db.query_with_bindings(
					"UPDATE inventory_items SET is_magical = 0 WHERE id = ?",
					[item_id])
				became_inert = true
		message = "Used '%s' — cast %s (%d charge%s remaining)." % [
			str(catalog_entry.get("name", item_key)),
			binding.get("spell_key", ""),
			charges_after,
			"" if charges_after == 1 else "s",
		]
	else:
		var failures: Array = result.failures if result != null else []
		message = "Failed to activate '%s': %s" % [
			str(catalog_entry.get("name", item_key)),
			"; ".join(failures) if not failures.is_empty() else "unknown error"]

	return {
		"success": result != null and result.success,
		"message": message,
		"charges_remaining": charges_after,
		"became_inert": became_inert,
		"spell_key": binding.get("spell_key", ""),
		"casting_result": result,
	}


## Activate a worn-triggered magic item (ring, helm, boots, broom, etc.).
## The item must currently be equipped — if `is_equipped == 0` the activation
## fails with a clear message (no consumption, no cast).
##
## Returns:
##   {
##     success: bool,
##     message: String,
##     spell_key: String,
##     casting_result: ResolutionResult
##   }
##
## [param item_id]         the inventory_items.id of the worn item.
## [param wielder]          the live CharacterData wearing the item. Becomes
##                          caster_id + caster_name on the CasterContext.
## [param target_id], [param target_entity]
##                          for single_creature / single_target bindings — the
##                          designated creature (and its live entity).
## [param target_cell]      for single_target bindings whose spell takes a
##                          cell anchor (Chime of Opening → knock at a cell;
##                          Helm of Teleportation → destination cell).
##
## V1 = UNLIMITED USES. The activator does not decrement charges and the row
## is not deleted on success. Per-day cooldowns + RAW per-item-charge limits
## (e.g. Helm of Teleportation's once-per-day) are a follow-up — V1 keeps the
## scope tight and lets the player spam-activate. A future pass can add
## `uses_per_day` to the binding + a `cooldown_until_day` column on
## inventory_items + a daily-reset hook.
##
## NOT to be confused with `WornMagicEffectResolver.refresh_for_character`,
## which handles PERSISTENT-while-equipped effects (Ring of Protection,
## Cloak of Protection, Ring of Water Walking, Ring of Fire Resistance).
## Persistent items apply continuously while worn; worn-triggered items
## are USED on demand.
static func activate_worn_item(
		item_id: String,
		wielder: CharacterData,
		casting_resolver: CastingResolver,
		magic_item_catalog: MagicItemCatalog,
		target_id: String = "",
		target_entity = null,
		target_cell: Vector3i = Vector3i.ZERO,
		map_context: String = "combat_grid",
		origin_cell: Vector3i = Vector3i.ZERO) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"spell_key": "",
		"casting_result": null,
	}

	# 1. Lookup chain.
	var item_row: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	if item_row.is_empty():
		empty["message"] = "Worn item not found in inventory (id=%s)." % item_id
		return empty
	# 2. Equipped-state check — the wielder must be wearing the item to trigger it.
	if int(item_row.get("is_equipped", 0)) != 1:
		empty["message"] = "Worn item is not equipped — cannot activate."
		return empty
	var item_key: String = str(item_row.get("item_key", ""))
	var catalog_entry: Dictionary = magic_item_catalog.get_item(item_key)
	if catalog_entry.is_empty():
		empty["message"] = "Item '%s' has no catalog entry." % item_key
		return empty
	# Tier 4 Control batch (2026-06-01): worn-active items whose effect
	# bypasses the spell pipeline (Ring of Command Animal/Plant). Routed
	# through `_apply_control_effect`; returns the same shape as the
	# spell-binding path (with `consumed: false` because rings are
	# multi-use). Mirrors drink_potion's direct_potion_effect branch.
	var direct_worn_v: Variant = catalog_entry.get("direct_worn_active_effect", null)
	if direct_worn_v is Dictionary:
		# Pass the casting_resolver's tracker through so the Control effect
		# registers with the unified cleanup chain (Option 1 migration,
		# 2026-06-01). Cleanup on duration expiry / dispel reverts the
		# side flip, clears the is_controlled_by_caster flag, and
		# emits condition_changed(applied:false) via the existing
		# CastingResolver._unwind_effect_state path.
		var tracker: ActiveEffectTracker = null
		if casting_resolver != null:
			tracker = casting_resolver.get_effect_tracker()
		var control_outcome: Dictionary = _apply_control_effect(
			wielder, target_id, target_entity,
			direct_worn_v as Dictionary,
			str(catalog_entry.get("name", item_key)),
			item_id, "worn_active", tracker)
		return control_outcome
	var binding_v: Variant = catalog_entry.get("spell_binding", null)
	if not (binding_v is Dictionary):
		empty["message"] = (
			"Worn item '%s' has no spell_binding (effect not yet implemented)." % item_key)
		return empty
	var binding: Dictionary = binding_v
	empty["spell_key"] = str(binding.get("spell_key", ""))

	# 3. Validate target params against the binding's target_mode.
	var target_v: Dictionary = _validate_target(
		binding, "Worn item '%s'" % item_key, target_id, target_entity, target_cell)
	if not bool(target_v["ok"]):
		empty["message"] = str(target_v["message"])
		return empty

	# 4. Cast via the shared pipeline.
	var result: ResolutionResult = _cast_via_binding(
		binding, wielder, casting_resolver,
		target_id, target_entity, target_cell,
		map_context, origin_cell)

	# 5. No consumption in V1 — worn items don't decrement.
	var message: String = ""
	if result != null and result.success:
		message = "Activated '%s' — cast %s." % [
			str(catalog_entry.get("name", item_key)),
			binding.get("spell_key", ""),
		]
	else:
		var failures: Array = result.failures if result != null else []
		message = "Failed to activate '%s': %s" % [
			str(catalog_entry.get("name", item_key)),
			"; ".join(failures) if not failures.is_empty() else "unknown error"]

	return {
		"success": result != null and result.success,
		"message": message,
		"spell_key": binding.get("spell_key", ""),
		"casting_result": result,
	}


## Apply an oil to a creature or a cell (Oil of Slipperiness V1; future grease
## spell and other oils plug into the same flow). Routes through
## `SurfaceCoatResolver` with a coat_spec selected from the item's catalog
## entry. The item must be in the inventory at the time of application; the
## dose is consumed only on success.
##
## Oils belong to the catalog's `potion` category (the ACKS random magic
## table groups them with potions), but you APPLY rather than DRINK them, so
## they MUST NOT go through `drink_potion`. The router for "is this a drink
## or an apply?" is the item_key: oils have an `oil_` prefix and are
## detected here. (Future oils with non-prefixed item_keys can opt in via a
## catalog field; V1 just uses the prefix because Oil of Slipperiness and
## Oil of Sharpness — the two RAW oils — both start with "oil_".)
##
## Returns:
##   {
##     success: bool,
##     message: String,
##     consumed: bool,
##     mode: String,                  — "creature" | "cell"
##     applied_flag_key: String,      — (creature mode) the EntityFlag set
##     applied_condition_key: String, — (cell mode) the CellSurfaceConditions key
##     effect_id: String,
##     source_id: String,
##     coated_cells: Array[Vector3i], — (cell mode only) the patch
##   }
##
## [param item_id]              the inventory_items.id of the oil being applied.
## [param magic_item_catalog]   a loaded MagicItemCatalog (for the catalog entry
##                               lookup that selects the coat_spec).
## [param effect_tracker]       ActiveEffectTracker for duration management.
## [param mode]                  "creature" | "cell" — determines which spec is
##                               selected and which path runs.
## [param target_creature]       (creature mode) live entity (must expose .flags).
## [param map_id]                (cell mode) runtime map identifier.
## [param anchor_cell]           (cell mode) anchor Vector3i for the patch.
## [param surface_conditions]   (cell mode) CellSurfaceConditions instance.
static func apply_oil(
		item_id: String,
		magic_item_catalog: MagicItemCatalog,
		effect_tracker: ActiveEffectTracker,
		mode: String,
		target_creature = null,
		map_id: String = "",
		anchor_cell: Vector3i = Vector3i.ZERO,
		surface_conditions: CellSurfaceConditions = null) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"consumed": false,
		"mode": mode,
		"applied_flag_key": "",
		"applied_condition_key": "",
		"effect_id": "",
		"source_id": "",
		"coated_cells": [] as Array[Vector3i],
	}

	# 1. Look up the inventory row to confirm the item exists + get item_key.
	var item_row: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	if item_row.is_empty():
		empty["message"] = "Oil not found in inventory (id=%s)." % item_id
		return empty
	var item_key: String = str(item_row.get("item_key", ""))

	# 2. Catalog entry check + oil-prefix routing. The category is "potion"
	#    (catalog grouping) so we DON'T fail on that; we DO require the
	#    item_key to start with "oil_" so the activator doesn't accidentally
	#    apply a Potion of Healing.
	if not item_key.begins_with("oil_"):
		empty["message"] = (
			"Item '%s' is not an oil (item_key must begin with 'oil_'). "
			% item_key
			+ "Use drink_potion for drinkable potions.")
		return empty
	var catalog_entry: Dictionary = magic_item_catalog.get_item(item_key)
	if catalog_entry.is_empty():
		empty["message"] = "Item '%s' has no catalog entry." % item_key
		return empty

	# 3. Select the coat_spec based on item_key + mode.
	var spec: Dictionary = _select_oil_coat_spec(item_key, mode)
	if spec.is_empty():
		empty["message"] = (
			"Item '%s' has no coat_spec for mode '%s' (item not yet wired or "
			% [item_key, mode]
			+ "mode not supported by this item).")
		return empty

	# 4. Dispatch to the resolver.
	match mode:
		"creature":
			var creature_result: Dictionary = SurfaceCoatResolver.apply_oil_to_creature(
				item_id, target_creature, spec, effect_tracker)
			creature_result["mode"] = "creature"
			# Ensure result Dict carries the same shape regardless of mode.
			if not creature_result.has("applied_condition_key"):
				creature_result["applied_condition_key"] = ""
			if not creature_result.has("coated_cells"):
				creature_result["coated_cells"] = [] as Array[Vector3i]
			return creature_result
		"cell":
			var cell_result: Dictionary = SurfaceCoatResolver.apply_oil_to_cell(
				item_id, map_id, anchor_cell, int(spec.get("area_size_ft", 10)),
				spec, effect_tracker, surface_conditions)
			cell_result["mode"] = "cell"
			if not cell_result.has("applied_flag_key"):
				cell_result["applied_flag_key"] = ""
			return cell_result
		_:
			empty["message"] = (
				"apply_oil: unsupported mode '%s' (use 'creature' or 'cell')." % mode)
			return empty


## Use a misc_magic active item (consumable or charged) that activates by
## "you use it" — Dust of Disappearance (sprinkle on self → invisibility),
## Dust of Appearance (toss into the air → detect_invisible area), Drums of
## Panic (sound them → panic area), and future similar items.
##
## Routes through the same `spell_binding` pipeline as drink_potion /
## activate_charged_item / activate_worn_item. Differs from drink_potion in
## that the item lives in the misc_magic category (not "potion"), and
## differs from activate_worn_item in that the item need NOT be equipped
## (you toss / sprinkle / sound it; you don't wear it). Differs from
## activate_charged_item in that the default consumption model here is
## "consumed on success" (like a potion) rather than "decrement charges."
## Per-item consumption is governed by the catalog flag `misc_magic_consumable`
## stamped via MISC_MAGIC_ACTIVE_CONFIG (true for dusts; false for drums and
## anything else that's a multi-use device).
##
## Returns:
##   {
##     success: bool,
##     message: String,
##     consumed: bool,
##     spell_key: String,
##     casting_result: ResolutionResult,
##   }
##
## [param item_id]            the inventory_items.id of the misc_magic active item.
## [param user]                the live CharacterData using the item (caster_id +
##                             caster_name on the CasterContext).
## [param casting_resolver]    a constructed CastingResolver.
## [param magic_item_catalog]  a loaded MagicItemCatalog.
## [param target_id]           (single_creature target_mode only) entity id.
## [param target_entity]       (single_creature target_mode only) live entity.
## [param target_cell]         (area_at_point / single_target target_mode) cell anchor.
## [param map_context]         defaults to "combat_grid".
## [param origin_cell]         user's voxel position. For self-targeted / area-
##                             centered-on-self items this is also the spell's origin.
static func use_misc_magic_active(
		item_id: String,
		user: CharacterData,
		casting_resolver: CastingResolver,
		magic_item_catalog: MagicItemCatalog,
		target_id: String = "",
		target_entity = null,
		target_cell: Vector3i = Vector3i.ZERO,
		map_context: String = "combat_grid",
		origin_cell: Vector3i = Vector3i.ZERO) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"consumed": false,
		"spell_key": "",
		"casting_result": null,
	}

	# 1. Lookup chain.
	var item_row: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	if item_row.is_empty():
		empty["message"] = "Misc-magic item not found in inventory (id=%s)." % item_id
		return empty
	var item_key: String = str(item_row.get("item_key", ""))
	var catalog_entry: Dictionary = magic_item_catalog.get_item(item_key)
	if catalog_entry.is_empty():
		empty["message"] = "Item '%s' has no catalog entry." % item_key
		return empty
	if str(catalog_entry.get("category", "")) != "misc_magic":
		empty["message"] = (
			"Item '%s' is not a misc_magic item (category=%s)." %
			[item_key, catalog_entry.get("category", "?")])
		return empty
	var binding_v: Variant = catalog_entry.get("spell_binding", null)
	if not (binding_v is Dictionary):
		empty["message"] = (
			"Misc-magic item '%s' has no spell_binding (effect not yet implemented)." % item_key)
		return empty
	var binding: Dictionary = binding_v
	empty["spell_key"] = str(binding.get("spell_key", ""))

	# 2. Validate target params against the binding's target_mode. Uses the
	# shared validator; misc_magic actives can target "self" (dust on self),
	# "area_at_point" (drums sound origin = user, or dust thrown to a cell),
	# or "single_creature" / "single_target" depending on the binding.
	var target_v: Dictionary = _validate_target(
		binding, "Misc-magic item '%s'" % item_key, target_id, target_entity, target_cell)
	if not bool(target_v["ok"]):
		empty["message"] = str(target_v["message"])
		return empty

	# 2a. Charge gate (2026-06-02 — Elemental Commanders cluster). An item
	# that has `default_charges` stamped AND `misc_magic_consumable: false`
	# is a reusable-with-charges item (e.g. Elemental Commanders'
	# once-per-day model V1: 1 charge that exhausts until a future
	# daily-reset subsystem refills misc_magic items at sunrise). Refuse
	# activation when charges are 0. Items WITHOUT default_charges are
	# unlimited-use (uses_remaining = -1, the catalog default) and skip
	# this gate entirely.
	var is_consumable: bool = bool(catalog_entry.get("misc_magic_consumable", true))
	var has_default_charges: bool = catalog_entry.has("default_charges")
	var current_charges: int = int(item_row.get("uses_remaining", -1))
	if has_default_charges and not is_consumable and current_charges == 0:
		empty["message"] = (
			"'%s' has no charges remaining (refills when the daily-reset subsystem lands)." %
			str(catalog_entry.get("name", item_key)))
		return empty

	# 3. Cast via the shared pipeline.
	var result: ResolutionResult = _cast_via_binding(
		binding, user, casting_resolver,
		target_id, target_entity, target_cell,
		map_context, origin_cell)

	# 4. Consumption / charge accounting. Three modes:
	#   - misc_magic_consumable = true (default) → remove from inventory on
	#     success (dusts; matches potion semantics).
	#   - misc_magic_consumable = false + has default_charges → decrement
	#     uses_remaining on success. Reaching 0 charges refuses subsequent
	#     activations until daily-reset (no is_magical clear — RAW for
	#     once-per-day items doesn't strip the magic itself).
	#   - misc_magic_consumable = false + no default_charges → unlimited
	#     uses (Drums of Panic, Medallions of ESP).
	var consumed: bool = false
	var charges_after: int = current_charges
	var message: String = ""
	if result != null and result.success:
		if is_consumable:
			consumed = CampaignRepository.remove_inventory_item(item_id)
		elif has_default_charges and current_charges > 0:
			charges_after = current_charges - 1
			CampaignRepository.db.query_with_bindings(
				"UPDATE inventory_items SET uses_remaining = ? WHERE id = ?",
				[charges_after, item_id])
		message = "Used '%s' — cast %s." % [
			str(catalog_entry.get("name", item_key)),
			binding.get("spell_key", ""),
		]
	else:
		var failures: Array = result.failures if result != null else []
		message = "Failed to activate '%s': %s" % [
			str(catalog_entry.get("name", item_key)),
			"; ".join(failures) if not failures.is_empty() else "unknown error"]

	return {
		"success": result != null and result.success,
		"message": message,
		"consumed": consumed,
		"charges_remaining": charges_after,
		"spell_key": binding.get("spell_key", ""),
		"casting_result": result,
	}


## Apply a Rod of Cancellation to a target magic item. The rod drains the
## target of all magical power on touch — `is_magical` cleared, `magical_bonus`
## zeroed, `uses_remaining` zeroed, `is_cursed` cleared (per RAW the curse
## itself is magical and would be drained). The rod itself consumes one
## charge on success; reaching 0 charges makes the rod useless and non-magical.
##
## RAW: `pc_magic_experimentation.xml:244-246, 327-329` describes the effect
## as "Drain one magic item of all power, as if touched by a rod of
## cancellation." `acore_treasure_and_magic_items_rules.xml:213` lists the
## rod in the rods_staffs_wands table without a dedicated mechanic entry —
## the mishap-table phrasing is the most explicit RAW we have.
##
## Returns:
##   {
##     success: bool,
##     message: String,
##     charges_remaining: int,    — rod's uses_remaining AFTER the activation
##     became_inert: bool,        — true if the rod hit 0 charges
##     target_drained: bool,      — true if the target item was successfully drained
##     target_id: String,
##   }
##
## [param rod_id]      the inventory_items.id of the Rod of Cancellation.
## [param wielder]     the live CharacterData using the rod (for logging /
##                     future per-wielder constraints).
## [param target_item_id] the inventory_items.id of the magic item to be
##                     drained. Must be `is_magical = 1`; non-magical items
##                     refuse the touch (no charge consumed).
## [param magic_item_catalog] a loaded MagicItemCatalog (for the rod's
##                     catalog entry lookup).
static func apply_rod_of_cancellation(
		rod_id: String,
		wielder: CharacterData,
		target_item_id: String,
		magic_item_catalog: MagicItemCatalog) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"charges_remaining": -1,
		"became_inert": false,
		"target_drained": false,
		"target_id": target_item_id,
	}

	# 1. Rod lookup.
	var rod_row: Dictionary = CampaignRepository.get_inventory_item_by_id(rod_id)
	if rod_row.is_empty():
		empty["message"] = "Rod of Cancellation not found (id=%s)." % rod_id
		return empty
	var rod_key: String = str(rod_row.get("item_key", ""))
	var rod_entry: Dictionary = magic_item_catalog.get_item(rod_key)
	if rod_entry.is_empty():
		empty["message"] = "Rod '%s' has no catalog entry." % rod_key
		return empty
	var special_v: Variant = rod_entry.get("special_charged_effect", null)
	if not (special_v is Dictionary) \
			or str((special_v as Dictionary).get("effect_kind", "")) != "cancel_magic_item":
		empty["message"] = (
			"Item '%s' is not a Rod of Cancellation (no cancel_magic_item effect)." % rod_key)
		return empty

	# 2. Rod charge gate — same semantics as activate_charged_item.
	var current_charges: int = int(rod_row.get("uses_remaining", -1))
	empty["charges_remaining"] = current_charges
	if current_charges == 0:
		empty["message"] = (
			"'%s' has no charges remaining (item is useless and non-magical)." %
				str(rod_entry.get("name", rod_key)))
		return empty

	# 3. Target lookup + validation.
	if target_item_id.is_empty():
		empty["message"] = "Rod of Cancellation requires a target magic item."
		return empty
	var target_row: Dictionary = CampaignRepository.get_inventory_item_by_id(target_item_id)
	if target_row.is_empty():
		empty["message"] = "Target item not found (id=%s)." % target_item_id
		return empty
	# A non-magical item refuses the touch — no charge consumed (the rod
	# doesn't expend on a mundane object, per the RAW "drain magic item of
	# all power" phrasing — there's no magic to drain).
	if int(target_row.get("is_magical", 0)) != 1:
		empty["message"] = (
			"Target '%s' is not magical — Rod of Cancellation has no effect." %
				str(target_row.get("name", target_item_id)))
		return empty
	if str(target_row.get("id", "")) == rod_id:
		empty["message"] = "The Rod of Cancellation refuses to drain itself."
		return empty

	# 4. Drain target + decrement rod charges in one transaction.
	# RAW (per mishap phrasing): "drain magic item of all power." Set
	# is_magical = 0, magical_bonus = 0, uses_remaining = 0, is_cursed = 0
	# (the curse mechanic IS magical; a fully-drained item shouldn't
	# remain cursed).
	CampaignRepository.db.query("BEGIN TRANSACTION")
	CampaignRepository.db.query_with_bindings(
		"""UPDATE inventory_items
		   SET is_magical = 0, magical_bonus = 0, uses_remaining = 0, is_cursed = 0
		   WHERE id = ?""",
		[target_item_id])
	var charges_after: int = current_charges - 1 if current_charges > 0 else current_charges
	CampaignRepository.db.query_with_bindings(
		"UPDATE inventory_items SET uses_remaining = ? WHERE id = ?",
		[charges_after, rod_id])
	var became_inert: bool = (current_charges > 0 and charges_after == 0)
	if became_inert:
		# Rod ran out of charges — clear is_magical per the same RAW that
		# governs wands ("useless and non-magical").
		CampaignRepository.db.query_with_bindings(
			"UPDATE inventory_items SET is_magical = 0 WHERE id = ?", [rod_id])
	CampaignRepository.db.query("COMMIT")

	var message: String = "Drained '%s' with Rod of Cancellation (%d charge%s remaining)." % [
		str(target_row.get("name", target_item_id)),
		charges_after,
		"" if charges_after == 1 else "s",
	]
	return {
		"success": true,
		"message": message,
		"charges_remaining": charges_after,
		"became_inert": became_inert,
		"target_drained": true,
		"target_id": target_item_id,
	}


## Apply a Life Drinker sword's level drain to a target struck in combat.
## RAW (acore_treasure_and_magic_items_rules.xml:274): "On command drains
## 1 HD or 1 life level from any struck target. Has 1d4+4 charges; each
## drain uses 1 charge. After charges are spent it is a normal sword +1."
##
## V1 implementation: separate entry point (called by the combat
## controller when the wielder issues the "drain" command on a hit).
## The combat-side wiring (UI affordance + hit-time trigger) is the
## consumer follow-up; this entry point lives here for unit testing +
## eventual combat integration.
##
## Charge accounting mirrors `apply_rod_of_cancellation`: refuses on
## zero charges (returns "no charges remaining"); decrements one charge
## on success; at 0 charges the sword loses its drain ability but
## remains a +1 magic sword (NOT cleared to non-magical, unlike Rod of
## Cancellation — RAW explicitly preserves the +1 status).
##
## Level drain mechanic: V1 sets the `is_energy_drained` EntityFlag on
## the target with metadata `{drained_levels: N, source: "life_drinker"}`.
## Forward-looking — when the energy-drain consumer integration lands
## (level reduction on CharacterData; HD reduction on monster catalog
## row), the flag's metadata documents the contract.
##
## Returns:
##   {
##     success: bool,
##     message: String,
##     charges_remaining: int,
##     became_normal_plus_one: bool,  - true when charges hit 0; sword
##                                      drops drain but stays +1
##     levels_drained: int,
##   }
static func apply_life_drinker_drain(
		sword_id: String,
		wielder: CharacterData,
		target_entity,
		magic_item_catalog: MagicItemCatalog) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"charges_remaining": -1,
		"became_normal_plus_one": false,
		"levels_drained": 0,
	}
	# 1. Sword lookup.
	var sword_row: Dictionary = CampaignRepository.get_inventory_item_by_id(sword_id)
	if sword_row.is_empty():
		empty["message"] = "Life Drinker sword not found (id=%s)." % sword_id
		return empty
	var key: String = str(sword_row.get("item_key", ""))
	if key != "life_drinker":
		empty["message"] = "Item '%s' is not a Life Drinker." % key
		return empty
	# 2. Charge gate.
	var current_charges: int = int(sword_row.get("uses_remaining", -1))
	empty["charges_remaining"] = current_charges
	if current_charges == 0:
		empty["message"] = "Life Drinker has no charges remaining — drain inert; still a Sword +1."
		return empty
	# 3. Target check + level-drain application.
	if target_entity == null:
		empty["message"] = "Life Drinker requires a struck target."
		return empty
	# Apply 1 drained level (RAW: 1 HD or 1 life level per use). Mark
	# via flag for the future consumer to honor.
	var levels_drained: int = 1
	if target_entity != null and target_entity.has_method("get_flags"):
		var t_flags = target_entity.get_flags()
		if t_flags != null:
			var source_id: String = "life_drinker:%s" % sword_id
			# If the target was already drained by this same sword, stack
			# the level count in metadata.
			var existing_meta: Dictionary = t_flags.get_flag_metadata("is_energy_drained")
			var prior_levels: int = int(existing_meta.get("drained_levels", 0))
			t_flags.set_flag("is_energy_drained", source_id, {
				"drained_levels": prior_levels + levels_drained,
				"source_kind": "life_drinker",
				"source_id": sword_id,
				"wielder_id": wielder.id if wielder != null else "",
			})
			# 2026-06-02 — PC consumer: refresh attack/save modifiers from
			# the flag state so the drain actually penalizes the PC's rolls
			# (monster HD path was already wired via
			# Combatant.get_effective_level_or_hd). Idempotent — re-derives
			# from current flag total. CharacterData-only; monster targets
			# don't have a modifier_container.
			if target_entity is CharacterData:
				EnergyDrainConsumer.refresh_modifiers(target_entity)
	# 4. Decrement charges.
	var charges_after: int = current_charges - 1
	CampaignRepository.db.query_with_bindings(
		"UPDATE inventory_items SET uses_remaining = ? WHERE id = ?",
		[charges_after, sword_id])
	var became_normal_plus_one: bool = (charges_after == 0)
	# Note: NOT clearing is_magical here — RAW explicitly preserves the
	# +1 status when charges are spent. The sword stays magical; only
	# the drain ability is exhausted.
	return {
		"success": true,
		"message": "Life Drinker drained 1 level from target (%d charge%s remaining)." % [
			charges_after,
			"" if charges_after == 1 else "s",
		],
		"charges_remaining": charges_after,
		"became_normal_plus_one": became_normal_plus_one,
		"levels_drained": levels_drained,
	}


## Ignite the Flame Tongue sword on command. RAW
## (acore_treasure_and_magic_items_rules.xml:273): "On command it ignites,
## sheds torchlight, and can ignite flammables." V1 wires the "sheds
## torchlight" half — sets the `wielding_lit_flame_tongue` EntityFlag on
## the wielder with metadata carrying the light radius (6 cells = 30',
## matches torch radius per LightSourceTracker.LIGHT_SOURCES["torch"]
## scaled to ACKS Core). The "can ignite flammables" half remains a
## deferred consumer integration until cell-level fire state lands.
##
## The flag is set on the WIELDER (not the sword inventory row) so the
## existing `worn_magic:` prefix-clear pattern doesn't accidentally
## sweep it on unrelated equip-state changes. Source_id is keyed by
## sword item_id so multiple Flame Tongues wielded simultaneously (a
## dual-wielding fighter) each get their own flag entry.
##
## Returns:
##   {
##     success: bool,
##     message: String,
##     light_active: bool,
##     light_radius_cells: int,
##   }
static func apply_flame_tongue_ignite(
		sword_id: String,
		wielder: CharacterData,
		magic_item_catalog: MagicItemCatalog) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"light_active": false,
		"light_radius_cells": 0,
	}
	# 1. Sword lookup.
	var sword_row: Dictionary = CampaignRepository.get_inventory_item_by_id(sword_id)
	if sword_row.is_empty():
		empty["message"] = "Flame Tongue sword not found (id=%s)." % sword_id
		return empty
	var key: String = str(sword_row.get("item_key", ""))
	if key != "flame_tongue":
		empty["message"] = "Item '%s' is not a Flame Tongue." % key
		return empty
	# 2. Wielded gate — sword must be equipped in hands_main to ignite.
	if int(sword_row.get("is_equipped", 0)) != 1 \
			or str(sword_row.get("slot", "")) != "hands_main":
		empty["message"] = "Flame Tongue must be wielded (hands_main) to ignite."
		return empty
	# 3. Read the catalog metadata for the light radius (V1 default 6 cells).
	var catalog_entry: Dictionary = magic_item_catalog.get_item(key)
	var meta: Dictionary = catalog_entry.get("sword_metadata", {})
	var radius_cells: int = int(meta.get("light_radius_cells", 6))
	# 4. Set the flag on the wielder.
	var source_id: String = "flame_tongue:%s" % sword_id
	if wielder != null and wielder.flags != null:
		wielder.flags.set_flag("wielding_lit_flame_tongue", source_id, {
			"sword_id": sword_id,
			"light_radius_cells": radius_cells,
			"can_ignite_flammables": bool(meta.get("can_ignite_flammables", true)),
		})
	return {
		"success": true,
		"message": "Flame Tongue ignites — sheds torchlight (%d cells)." % radius_cells,
		"light_active": true,
		"light_radius_cells": radius_cells,
	}


## Douse (extinguish on command) a previously-ignited Flame Tongue. RAW
## doesn't specify a douse command explicitly, but the "on command" phrasing
## implies the wielder controls the ignite state. V1 clears the
## `wielding_lit_flame_tongue` flag for this specific sword.
static func apply_flame_tongue_douse(
		sword_id: String,
		wielder: CharacterData) -> Dictionary:
	if wielder == null or wielder.flags == null:
		return {"success": false, "message": "No wielder flags container.", "light_active": false}
	var source_id: String = "flame_tongue:%s" % sword_id
	wielder.flags.clear_flag("wielding_lit_flame_tongue", source_id)
	return {
		"success": true,
		"message": "Flame Tongue is doused.",
		"light_active": wielder.flags.has_flag("wielding_lit_flame_tongue"),
	}


## Resolve a direct-effect potion (Potion of Poison and future similar items).
## Called from `drink_potion` when the catalog entry carries
## `direct_potion_effect` instead of (or in addition to) a spell_binding.
##
## Returns the same shape as `drink_potion`. The potion is consumed in BOTH
## success-saves-on-poison and failure-dies-on-poison outcomes (unlike spell-
## binding potions, where a magic-system failure preserves the dose). The
## rationale: by the time the drinker is rolling the save, the bottle is
## empty.
##
## RAW: `acore_treasure_and_magic_items_rules.xml:253` poison_potion rule —
## "Poison effect resolves according to the source potion description and
## relevant saves." Project default for V1 Potion of Poison: save vs Poison
## & Death; failure = drinker dies (HP set to negative max-HP per the
## standard "instantly killed" interpretation), success = no effect. The
## standard ACKS "save vs Poison or die" pattern appears across the corpus
## (e.g. `acore_monster_catalog_a-dop.xml:258`).
static func _resolve_direct_potion_effect(
		item_id: String,
		item_key: String,
		catalog_entry: Dictionary,
		drinker: CharacterData,
		direct_cfg: Dictionary,
		target_id: String = "",
		target_entity = null,
		effect_tracker: ActiveEffectTracker = null) -> Dictionary:
	var effect_kind: String = str(direct_cfg.get("effect_kind", ""))
	var name: String = str(catalog_entry.get("name", item_key))
	var base := {
		"success": false,
		"message": "",
		"consumed": false,
		"spell_key": "",
		"casting_result": null,
	}
	match effect_kind:
		"control_creature":
			# Tier 4 Control batch (2026-06-01). RAW per Jedidiah ruling:
			# Charmed switches team allegiance but leaves AI in control;
			# Controlled switches team AND grants the controller direct
			# action-selection over the target. V1 implementation: apply
			# `controlled` condition + set is_controlled_by_caster flag on
			# target + flip Combatant.side if the target supports it. The
			# direct-action-selection UI is a follow-up. 5 potions
			# (Animal/Dragon/Giant/Plant/Undead Control) all use this branch.
			var control_outcome: Dictionary = _apply_control_effect(
				drinker, target_id, target_entity,
				direct_cfg, name, item_id, "potion", effect_tracker)
			# Potion is consumed on success only — the drinker drank the
			# potion to attempt the control; failure means it didn't take
			# hold but the dose is consumed (unlike spell-binding potions
			# where a magic-system failure preserves the dose). Project
			# decision: this matches Potion of Poison's "consumed in both
			# outcomes" pattern since the drinker physically drank the
			# liquid in both cases.
			CampaignRepository.remove_inventory_item(item_id)
			control_outcome["consumed"] = true
			return control_outcome
		"save_or_die_poison":
			# Roll save vs Poison & Death — drinker's effective save target,
			# d20, no modifier (the save itself uses the entity's save value).
			# DiceSystem patterns: lower is better, drinker wants
			# `modified_total >= save_target`.
			var save_target: int = int(drinker.get_effective_save("save_poison_death"))
			var roll: RollResult = DiceSystem.roll_digital(
				20, 1, 0, "save_vs_poison_potion")
			var passed: bool = roll.modified_total >= save_target
			# Consume the bottle in both cases — see docstring.
			CampaignRepository.remove_inventory_item(item_id)
			if passed:
				return {
					"success": true,
					"message": "Drank '%s' — saved vs Poison (rolled %d vs target %d). No effect." %
						[name, roll.modified_total, save_target],
					"consumed": true,
					"spell_key": "",
					"casting_result": null,
				}
			else:
				# Drinker dies. Standard ACKS "instantly killed" handling —
				# set HP to -max_hp (well below the -10 mortal-wounds floor
				# so the combat / mortal-wounds path treats this as
				# "instantly killed"). RAW: ax_mortal_wounds_and_tampering.xml:396
				# "state of the creature's body: -10 if instantly killed"
				# — the magnitude marker on the mortal-wounds table for
				# poison-deaths.
				var max_hp: int = drinker.hp_max
				var new_hp: int = -max_hp
				var old_hp: int = drinker.hp_current
				drinker.hp_current = new_hp
				CampaignRepository.update_character_hp(drinker.id, new_hp)
				EventBus.hp_changed.emit(drinker.id, old_hp, new_hp)
				EventBus.damage_dealt.emit(
					drinker.id, max(1, old_hp - new_hp),
					"potion_of_poison", "potion_of_poison")
				return {
					"success": true,  # the potion resolved successfully — the drinker dies
					"message": "Drank '%s' — failed save vs Poison (rolled %d vs target %d). Drinker dies." %
						[name, roll.modified_total, save_target],
					"consumed": true,
					"spell_key": "",
					"casting_result": null,
				}
		_:
			base["message"] = "Unknown direct_potion_effect kind '%s' on '%s'." % [
				effect_kind, item_key]
			return base
	return base  # unreachable; satisfies the type checker


## Shared Control resolver — applied by both potion (drink_potion) and worn-
## active (activate_worn_item) entry points. Implements the Control mechanic
## per Jedidiah ruling 2026-06-01:
##   * Charmed (existing): switches team allegiance, target stays AI-controlled
##   * Controlled (new):   switches team allegiance AND grants controller
##                         direct action-selection over the target
##
## V1 implementation:
##   1. Validate target presence + creature-type filter match.
##   2. Roll save vs the configured save kind (default: spells). Lower is
##      better — target wants `modified_total >= save_target`.
##   3. On save success: no effect (control failed).
##   4. On save failure:
##      a. Apply the `controlled` condition to the target (if target supports
##         add_condition — Combatants do; raw CharacterData doesn't).
##      b. Set the `is_controlled_by_caster` EntityFlag on the target with
##         source_id "magic_item:<item_id>:<caster_id>" + metadata recording
##         {caster_id, original_side, controller_kind, creature_type_filter,
##         duration_turns, hostile_on_expiry}.
##      c. If the target has a `.side` property (Combatants), flip it to the
##         caster's side. The flag's metadata preserves original_side so a
##         future cleanup callback can revert.
##
## V1 deferred (documented in build_log):
##   * Duration-based revert (on tick expiry, restore original_side + clear
##     flag). The condition + flag are durable; combat-spawn code can read
##     them. Cleanup callback wiring is a follow-up.
##   * Direct-action UI (caster picks target's combat actions like a henchman).
##   * Hostility-on-expiry (Undead Control specifically — hostile when control
##     ends per Jedidiah-supplied RAW).
##   * HD cap enforcement for Potion of Undead Control (3d6 for ≤4 HD vs 1
##     for >4 HD — needs monster catalog enumeration in range).
##   * Intelligent vs unintelligent undead distinction (unintelligent get no
##     save — needs a `mindless_undead` flag on monster catalog).
##
## [param caster]              live CharacterData casting the effect (the
##                              drinker / ring-wielder; becomes the controller).
## [param target_id]            id of the target creature.
## [param target_entity]        live Combatant or CharacterData for the target.
##                              For combat use it should be a Combatant (has
##                              .side property + add_condition method).
## [param config]               the direct_potion_effect or
##                              direct_worn_active_effect Dictionary from the
##                              catalog (creature_type_filter, save_kind, etc.).
## [param item_name]            human-readable name for log messages.
## [param item_id]              source item id for flag.source_id uniqueness.
## [param invocation_kind]      "potion" | "worn_active" — log discriminator.
static func _apply_control_effect(
		caster: CharacterData,
		target_id: String,
		target_entity,
		config: Dictionary,
		item_name: String,
		item_id: String,
		invocation_kind: String,
		effect_tracker: ActiveEffectTracker = null) -> Dictionary:
	var base := {
		"success": false,
		"message": "",
		"consumed": false,
		"spell_key": "",
		"casting_result": null,
	}
	# 1. Target presence check.
	if target_id.is_empty() or target_entity == null:
		base["message"] = "%s requires a target creature." % item_name
		return base
	# 2. Creature-type filter check. The target_entity may be a Combatant
	#    (which exposes monster_type / category) or a CharacterData. V1 best-
	#    effort: read a `creature_type` / `category` / `monster_type` property
	#    if present; if absent, skip the filter (forward-compatible for when
	#    the type is wired). The filter strings match common ACKS creature-
	#    type categories ("animal", "dragon", "giant", "plant", "undead").
	var creature_type_filter: String = str(config.get("creature_type_filter", ""))
	if not creature_type_filter.is_empty():
		var target_type: String = _get_target_creature_type(target_entity)
		# If the engine doesn't yet expose creature_type on this target,
		# we let it through (V1 forward-compat). Once monster catalog
		# wires creature_type onto all combatants, this becomes a hard
		# refusal. Documented in build_log as a [NEEDS-MONSTER-CATALOG-WORK]
		# follow-up.
		if not target_type.is_empty() and target_type != creature_type_filter:
			base["message"] = (
				"%s only controls %s creatures; target is %s." %
				[item_name, creature_type_filter, target_type])
			return base
	# 3. Roll save against the configured save kind.
	var save_kind: String = str(config.get("save_kind", "spells"))
	var save_key: String = "save_%s" % save_kind  # e.g. save_spells
	var save_target: int = _get_target_save(target_entity, save_key)
	var roll: RollResult = DiceSystem.roll_digital(
		20, 1, 0, "save_vs_control_effect")
	var passed: bool = roll.modified_total >= save_target
	if passed:
		# Save succeeded — no effect.
		return {
			"success": true,  # the resolution ran successfully; the EFFECT was negated by save
			"message": "%s — target saved (rolled %d vs %s target %d). No effect." %
				[item_name, roll.modified_total, save_key, save_target],
			"consumed": false,  # caller (drink_potion / activate_worn_item) sets this
			"spell_key": "",
			"casting_result": null,
		}
	# 4. Save failed — apply control.
	#    (a) Condition.
	if target_entity != null and target_entity.has_method("add_condition"):
		target_entity.add_condition("controlled")
	#    (b) Set is_controlled_by_caster flag with metadata.
	var caster_id: String = caster.id if caster != null else ""
	var source_id: String = "magic_item:%s:%s" % [item_id, caster_id]
	var caster_side: int = _get_target_side(caster)  # caster's combat side
	var original_target_side: int = _get_target_side(target_entity)
	var metadata := {
		"source_kind": "magic_item_control",
		"caster_id": caster_id,
		"item_id": item_id,
		"item_name": item_name,
		"invocation_kind": invocation_kind,
		"creature_type_filter": str(config.get("creature_type_filter", "")),
		"original_side": original_target_side,
		"caster_side": caster_side,
		"controller_kind": "player",  # V1 assumes the caster is the player; future: distinguish
		"duration_turns": int(config.get("duration_turns", -1)),
		"hostile_on_expiry": bool(config.get("hostile_on_expiry", false)),
	}
	var target_flags = _get_entity_flags(target_entity)
	if target_flags != null:
		target_flags.set_flag("is_controlled_by_caster", source_id, metadata)
	#    (c) Flip target side if the target has a side and the caster has one.
	var side_flipped: bool = false
	if caster_side >= 0 and original_target_side >= 0 and caster_side != original_target_side:
		if target_entity != null and ("side" in target_entity):
			target_entity.side = caster_side
			side_flipped = true
	#    (d) Register an active effect with the tracker (Option 1 migration,
	#        2026-06-01). Mirrors the records the spell pipeline writes for
	#        Charm — applied_conditions + applied_flags + applied_side_flips —
	#        so CastingResolver._unwind_effect_state on duration expiry /
	#        dispel reverts all three mutations through the unified cleanup
	#        chain (no parallel cleanup logic in MagicItemActivator). The
	#        tracker is optional (default null) so the helper still works
	#        when called from a path without a tracker — in that case the
	#        mutations persist until manually cleared (matches pre-migration
	#        behavior for callers that don't pass it).
	if effect_tracker != null:
		var effect_id: String = "magic_item_control:%s:%s" % [item_id, target_id]
		var duration_turns: int = int(config.get("duration_turns", -1))
		# duration_turns == -1 means "indefinite (until dispel)" — V1 ring
		# pattern. For potions the materializer rolls 1d6+6 turns at
		# activation time and overrides config; for now we accept -1 as
		# "no auto-expiry" and let the tracker hold the effect until dispel.
		var duration_type: String = "turns" if duration_turns > 0 else "indefinite"
		var duration_remaining: int = duration_turns if duration_turns > 0 else 9999
		var effect_dict: Dictionary = {
			"effect_id": effect_id,
			"spell_key": "magic_item_control:%s" % item_id,
			"caster_id": caster_id,
			"caster_level": 1,
			"target_ids": [target_id],
			"effect_type": "control",
			"applied_modifiers": [],
			"applied_flags": [{
				"character_id": target_id,
				"flag_key": "is_controlled_by_caster",
				"source_id": source_id,
			}],
			"applied_conditions": [{
				"character_id": target_id,
				"condition_key": "controlled",
			}],
			"applied_side_flips": ([] if not side_flipped else [{
				"character_id": target_id,
				"original_side": original_target_side,
				"new_side": caster_side,
			}]),
			"duration_type": duration_type,
			"duration_remaining": duration_remaining,
			"requires_concentration": 0,
			"is_active": 1,
			"metadata": {
				"source_kind": "magic_item_control",
				"item_id": item_id,
				"item_name": item_name,
				"invocation_kind": invocation_kind,
				"hostile_on_expiry": bool(config.get("hostile_on_expiry", false)),
			},
		}
		effect_tracker.add_effect(effect_dict)
	return {
		"success": true,
		"message": "%s — target FAILED save (rolled %d vs %s target %d). Target is now controlled%s." %
			[item_name, roll.modified_total, save_key, save_target,
			 " and switched to your side" if side_flipped else ""],
		"consumed": false,
		"spell_key": "",
		"casting_result": null,
	}


## Best-effort read of a target's creature_type (e.g. "animal" / "undead" /
## "giant" / "dragon" / "plant"). Combatants may expose `monster_type` or a
## `category` field; CharacterData has no such field. V1 returns "" if no
## type is available — the Control filter then lets the target through
## (forward-compat).
static func _get_target_creature_type(target_entity) -> String:
	if target_entity == null:
		return ""
	# Try common property names in order of likelihood.
	for prop in ["creature_type", "monster_type", "category", "type"]:
		if prop in target_entity:
			var v = target_entity.get(prop)
			if v is String and not (v as String).is_empty():
				return v
	# Combatant may carry a monster catalog entry as `_monster_catalog_entry`
	# (per the agent's exploration earlier in the project). V1 doesn't dig
	# that deep; return "" and let the filter pass.
	return ""


## Best-effort read of a target's save target number. Combatants expose
## get_effective_save(); CharacterData also exposes it. Returns 20 as a
## conservative default (only a natural 20 saves) if no save is available.
static func _get_target_save(target_entity, save_key: String) -> int:
	if target_entity == null:
		return 20
	if target_entity.has_method("get_effective_save"):
		return int(target_entity.get_effective_save(save_key))
	if save_key in target_entity:
		return int(target_entity.get(save_key))
	return 20


## Best-effort read of a target's combat side (PARTY=0, ENEMY=1). Returns
## -1 if the target has no side (out-of-combat CharacterData, etc.).
static func _get_target_side(target_entity) -> int:
	if target_entity == null:
		return -1
	if "side" in target_entity:
		return int(target_entity.get("side"))
	return -1


## Best-effort read of a target's EntityFlags container. Combatants /
## CharacterData expose `flags`; returns null if absent.
static func _get_entity_flags(target_entity):
	if target_entity == null:
		return null
	if "flags" in target_entity:
		return target_entity.get("flags")
	return null


## Pick the coat_spec for an oil item + application mode. Hard-coded for V1
## (Oil of Slipperiness only); generalization candidates (a catalog
## `oil_binding` field analogous to spell_binding) land when the second oil
## arrives, so the shape settles after a real second consumer.
static func _select_oil_coat_spec(item_key: String, mode: String) -> Dictionary:
	match item_key:
		"oil_of_slipperiness":
			match mode:
				"creature":
					return SurfaceCoatResolver.oil_of_slipperiness_creature_spec()
				"cell":
					var spec: Dictionary = SurfaceCoatResolver.oil_of_slipperiness_cell_spec()
					spec["area_size_ft"] = 10  # RAW: one 10' x 10' patch
					return spec
				_:
					return {}
		_:
			return {}


# ---------------------------------------------------------------------------
# Shared pipeline — used by drink_potion, activate_charged_item, and
# activate_worn_item.
# ---------------------------------------------------------------------------

## Validate that target params match the binding's target_mode. Returns
## {ok: bool, message: String}. The shared validation lets both entry points
## use a consistent failure mode for missing target_id / target_cell.
static func _validate_target(
		binding: Dictionary,
		label: String,
		target_id: String,
		target_entity,
		target_cell: Vector3i) -> Dictionary:
	var target_mode: String = str(binding.get("target_mode", "self"))
	match target_mode:
		"self":
			return {"ok": true, "message": ""}
		"single_creature":
			if target_id.is_empty() or target_entity == null:
				return {"ok": false,
					"message": "%s requires a designated creature target (target_mode=single_creature)." % label}
			return {"ok": true, "message": ""}
		"single_target":
			# Wand-style: wielder picks one target which may be a creature
			# (single-target spells like magic_missile, hold_monster) or a
			# cell (area spells like fireball anchored at a point). At least
			# one of target_id / target_cell must be supplied.
			var has_creature: bool = (not target_id.is_empty()) and (target_entity != null)
			var has_cell: bool = target_cell != Vector3i.ZERO
			if not has_creature and not has_cell:
				return {"ok": false,
					"message": "%s requires a designated target (creature id or cell)." % label}
			return {"ok": true, "message": ""}
		_:
			return {"ok": false,
				"message": "%s has unsupported target_mode='%s'." % [label, target_mode]}


## Build CasterContext + SpellChoice + TargetDescriptor + targets_by_id and
## invoke CastingResolver.resolve. The caller is responsible for consumption
## (potion delete / charge decrement) based on result.success.
static func _cast_via_binding(
		binding: Dictionary,
		user: CharacterData,
		casting_resolver: CastingResolver,
		target_id: String,
		target_entity,
		target_cell: Vector3i,
		map_context: String,
		origin_cell: Vector3i) -> ResolutionResult:
	var ctx: CasterContext = _build_caster_context(user, binding, map_context, origin_cell)
	var choice: SpellChoice = _build_spell_choice(binding)
	var descriptor: TargetDescriptor = _build_target_descriptor(
		binding, user, target_id, target_cell, origin_cell)

	var target_mode: String = str(binding.get("target_mode", "self"))
	var targets_by_id: Dictionary = {}
	match target_mode:
		"self":
			targets_by_id[user.id] = user
		"single_creature":
			targets_by_id[target_id] = target_entity
		"single_target":
			if not target_id.is_empty() and target_entity != null:
				targets_by_id[target_id] = target_entity

	return casting_resolver.resolve(ctx, choice, descriptor, user, targets_by_id)


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

## CasterContext for a potion drinker. The DRINKER is the caster — items
## carry the magical knowledge for us. Tradition + caster_level come from the
## binding (the potion was BREWED by an N-level <tradition> caster, and that
## casting expression is what the drinker triggers). Casting-stat-bonus is
## the drinker's own stat bonus per RAW (a Cleric drinking a Potion of
## Fireball still benefits from their WIS adjustment to saves cast by them).
static func _build_caster_context(
		drinker: CharacterData,
		binding: Dictionary,
		map_context: String,
		origin_cell: Vector3i) -> CasterContext:
	var ctx := CasterContext.new()
	ctx.caster_id = drinker.id
	ctx.caster_name = drinker.name
	ctx.caster_level = int(binding.get("caster_level", 1))
	ctx.caster_class = drinker.character_class
	ctx.tradition = str(binding.get("tradition", "arcane"))
	# Casting stat bonus per drinker (their own modifier applies to save DCs
	# the potion creates, per RAW magic-item interpretation). For V1 we
	# default to 0 — feeding the drinker's INT/WIS bonus is a refinement.
	ctx.casting_stat_bonus = 0
	ctx.alignment = drinker.alignment
	ctx.map_context = map_context
	ctx.current_position = origin_cell
	# Drinking is a free action — drinker can be prone, can't speak (gagged),
	# etc., and still drink. So we mark "can_speak"=true to satisfy
	# verbal-component checks (potions BYPASS verbal/somatic per RAW; the
	# magic is in the liquid). Same for can_move_hands (must be able to grasp
	# the bottle, but no spell components needed). This is the project's
	# interpretation of "potions have no component requirements."
	ctx.is_prone = false
	ctx.can_move_hands = true
	ctx.can_speak = true
	ctx.is_in_silence_area = false
	return ctx


## SpellChoice — fixed for a potion (no level scaling, no reversed form, no
## disjunctive branch in V1). All current bindings are non-disjunctive single-
## branch spells, so chosen_disjunctive_index stays -1 (the resolver accepts
## -1 for non-disjunctive entries).
##
## 2026-06-02 (Elemental Commanders cluster) — if the binding carries a
## `resolver_args_override` dict, propagate it to SpellChoice so the
## CastingResolver._dispatch_custom merge picks it up at dispatch time.
## Each entry's key is a resolver_id (e.g. "conjure_elemental"); the
## value is the override args dict.
static func _build_spell_choice(binding: Dictionary) -> SpellChoice:
	var choice := SpellChoice.new(
		str(binding.get("spell_key", "")),
		1,      # spell_choice.level: a potion's effective spell-level is fixed
		        # at the binding's caster_level on CasterContext. The SpellChoice.level
		        # field tracks which slot was used by a real caster — irrelevant
		        # for a potion (no slot is consumed). Default to 1.
		false,  # is_reversed — no reversed-form potions in the V1 binding map.
		-1)     # chosen_disjunctive_index — none of the V1 bound spells are
		        # disjunctive.
	var overrides: Variant = binding.get("resolver_args_override", null)
	if overrides is Dictionary:
		choice.resolver_args_overrides = overrides
	return choice


## TargetDescriptor — derived from the binding's target_mode. The spell's
## actual target_spec.kind (touch_creature / touch_ally / self / etc.) is
## set on the descriptor so the resolver routes mutations to the correct
## entity. For self-targeted potions the user is the only target_id; for
## single_creature the caller supplies it; for single_target (wands) the
## caller supplies a creature id OR a cell (or both for hybrid spells).
static func _build_target_descriptor(
		binding: Dictionary,
		user: CharacterData,
		target_id: String,
		target_cell: Vector3i,
		origin_cell: Vector3i) -> TargetDescriptor:
	var descriptor := TargetDescriptor.new()
	descriptor.origin_cell = origin_cell
	var target_mode: String = str(binding.get("target_mode", "self"))
	match target_mode:
		"self":
			# The resolver looks up target_spec.kind from the catalog; we
			# default the descriptor's kind to "self" but it's also valid for
			# the resolver to overlay touch_creature / touch_ally.
			descriptor.kind = "self"
			descriptor.target_ids = [user.id]
		"single_creature":
			descriptor.kind = "single_creature"
			descriptor.target_ids = [target_id]
		"single_target":
			# Wand-style hybrid: populate whichever side the caller supplied.
			# The resolver picks what to use based on the spell's target_spec.
			if not target_id.is_empty():
				descriptor.target_ids = [target_id]
			if target_cell != Vector3i.ZERO:
				descriptor.target_cells = [target_cell]
			# Generic kind — the registry/resolver overlays the spell's actual
			# target_spec.kind during payload resolution.
			descriptor.kind = "single_target"
	return descriptor




# ---------------------------------------------------------------------------
# Generic consumable activation (Wards scrolls + future scrolls/dusts/etc.)
# ---------------------------------------------------------------------------

## Activate a consumable magic item. V1 routes scroll-category items by
## `direct_consumable_effect` to per-effect apply functions.
##
## Currently dispatches:
##   - Scrolls of Warding (Elementals / Lycanthropes / Magic / Undead) per
##     `direct_consumable_effect.effect_kind` ("ward_against_creature_type"
##     or "ward_against_magic").
##
## Returns:
##   { success: bool, message: String, consumed: bool, effect_kind: String,
##     flag_set: String, source_id: String }
static func activate_consumable(
		item_id: String,
		reader: CharacterData,
		magic_item_catalog: MagicItemCatalog,
		origin_cell: Vector3i = Vector3i.ZERO) -> Dictionary:
	var empty := {
		"success": false,
		"message": "",
		"consumed": false,
		"effect_kind": "",
		"flag_set": "",
		"source_id": "",
	}

	# 1. Inventory + catalog lookup.
	var item_row: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	if item_row.is_empty():
		empty["message"] = "Consumable not found in inventory (id=%s)." % item_id
		return empty
	var item_key: String = str(item_row.get("item_key", ""))
	var catalog_entry: Dictionary = magic_item_catalog.get_item(item_key)
	if catalog_entry.is_empty():
		empty["message"] = "Item '%s' has no catalog entry." % item_key
		return empty
	var category: String = str(catalog_entry.get("category", ""))
	if category != "scroll":
		empty["message"] = "Item '%s' is not a consumable scroll (category=%s)." % [
			item_key, category]
		return empty

	# 2. Direct-consumable-effect dispatch.
	var direct_v: Variant = catalog_entry.get("direct_consumable_effect", null)
	if not (direct_v is Dictionary):
		empty["message"] = (
			"Scroll '%s' has no direct_consumable_effect (effect not yet implemented)."
			% item_key)
		return empty
	var direct: Dictionary = direct_v
	var effect_kind: String = String(direct.get("effect_kind", ""))
	empty["effect_kind"] = effect_kind

	# 3. Reader gate.
	if reader == null:
		empty["message"] = "Consumable requires a reader."
		return empty

	# 4. Per-effect dispatch.
	var apply_result: Dictionary
	match effect_kind:
		"ward_against_creature_type":
			apply_result = _apply_ward_against_creature_type(
				item_id, reader, catalog_entry, direct)
		"ward_against_magic":
			apply_result = _apply_ward_against_magic(
				item_id, reader, catalog_entry, direct)
		_:
			empty["message"] = "Unknown direct_consumable_effect.effect_kind='%s'." % effect_kind
			return empty

	# 5. Consume on success (scrolls are single-use).
	var consumed: bool = false
	if bool(apply_result.get("success", false)):
		consumed = CampaignRepository.remove_inventory_item(item_id)
	return {
		"success": bool(apply_result.get("success", false)),
		"message": String(apply_result.get("message", "")),
		"consumed": consumed,
		"effect_kind": effect_kind,
		"flag_set": String(apply_result.get("flag_set", "")),
		"source_id": String(apply_result.get("source_id", "")),
	}


## Apply a Scroll of Warding against Elementals / Lycanthropes / Undead.
## Sets the `warded_against_creature_type` flag on the reader with
## metadata carrying the creature_types filter, radius_feet, ward_kind,
## and caster_level. RAW-aligned semantics 2026-06-03:
##   - ENTRY BLOCK: MovementResolver refuses moves that would put a
##     creature of the warded type into a cell within radius_feet of bearer
##   - NO ATTACK SAVE: warded creatures can still attack with missiles
##     and spells from outside
##   - BEARER-MELEE-OUT DISMISSAL: when bearer attacks (melee) at a
##     warded creature type, the ward clears (SpellCombatHooks)
##   - DURATION: "until dismissed" (V1: until cleared via bearer-melee-out
##     or inventory removal; no UI dismiss yet)
##
## RAW: `acore_treasure_and_magic_items_rules.xml:268-272`. Any literate
## character can use it. caster_level is stamped for narration but does
## not affect duration (RAW says "until dismissed").
static func _apply_ward_against_creature_type(
		item_id: String,
		reader: CharacterData,
		catalog_entry: Dictionary,
		direct: Dictionary) -> Dictionary:
	var creature_types: Array = direct.get("creature_types", [])
	if creature_types.is_empty():
		return {
			"success": false,
			"message": "Scroll missing creature_types filter.",
		}
	var ward_kind: String = String(direct.get("ward_kind", "ward_against_creature_type"))
	var radius_feet: int = int(direct.get("radius_feet", 10))
	var caster_level: int = int(direct.get("caster_level", max(5, reader.level)))
	var source_id: String = "scroll_ward:%s:%s" % [ward_kind, item_id]
	reader.flags.set_flag("warded_against_creature_type", source_id, {
		"creature_types": creature_types,
		"radius_feet": radius_feet,
		"caster_level": caster_level,
		"ward_kind": ward_kind,
	})
	return {
		"success": true,
		"message": "Read '%s' - bearer warded against %s (10' barrier; ends on melee-out at warded type)." % [
			str(catalog_entry.get("name", "Scroll")),
			", ".join(creature_types),
		],
		"flag_set": "warded_against_creature_type",
		"source_id": source_id,
	}


## Apply a Scroll of Warding against Magic. RAW alignment 2026-06-03:
## Magic-ward is now a creature_type="magic" entry block, same mechanic
## as Elementals / Lycanthropes / Undead — RAW
## `acore_treasure_and_magic_items_rules.xml:268-272` makes no
## distinction between the 4 wards; each plugs a different creature_type
## into the same 10' entry-block barrier. V1 limitation: no monster
## catalog rows currently carry the "magic" creature_type, so Magic-ward
## is effectively inert in combat until consumer tagging lands.
##
## (Consolidates the prior `warded_against_magic` flag into the unified
## `warded_against_creature_type` family.)
static func _apply_ward_against_magic(
		item_id: String,
		reader: CharacterData,
		catalog_entry: Dictionary,
		direct: Dictionary) -> Dictionary:
	var radius_feet: int = int(direct.get("radius_feet", 10))
	var caster_level: int = int(direct.get("caster_level", max(5, reader.level)))
	var source_id: String = "scroll_ward:ward_against_magic:%s" % item_id
	reader.flags.set_flag("warded_against_creature_type", source_id, {
		"creature_types": ["magic"],
		"radius_feet": radius_feet,
		"caster_level": caster_level,
		"ward_kind": "ward_against_magic",
	})
	return {
		"success": true,
		"message": "Read '%s' - bearer warded against magic creatures (10' barrier)." % [
			str(catalog_entry.get("name", "Scroll of Warding against Magic")),
		],
		"flag_set": "warded_against_creature_type",
		"source_id": source_id,
	}
