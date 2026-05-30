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
static func _build_spell_choice(binding: Dictionary) -> SpellChoice:
	return SpellChoice.new(
		str(binding.get("spell_key", "")),
		1,      # spell_choice.level: a potion's effective spell-level is fixed
		        # at the binding's caster_level on CasterContext. The SpellChoice.level
		        # field tracks which slot was used by a real caster — irrelevant
		        # for a potion (no slot is consumed). Default to 1.
		false,  # is_reversed — no reversed-form potions in the V1 binding map.
		-1)     # chosen_disjunctive_index — none of the V1 bound spells are
		        # disjunctive.


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


