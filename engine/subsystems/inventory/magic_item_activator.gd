class_name MagicItemActivator
extends RefCounted

## Bridges magic-item activation ("drink potion", later "use wand", "wear ring",
## etc.) into the existing spell-effect pipeline (`CastingResolver`).
##
## V1 thin slice — POTIONS ONLY: a potion that carries a `spell_binding` field
## in `data/treasure/magic_item_catalog.json` activates by routing through
## CastingResolver.resolve() with the drinker as caster, the binding's
## spell_key + caster_level + tradition stamped onto the CasterContext +
## SpellChoice, and a TargetDescriptor built from the binding's target_mode
## ("self" → drinker is the target; "single_creature" → caller supplies
## target_id + target_entity). On a successful cast the potion is consumed
## (deleted from inventory_items). On failure no consumption (the dose
## survives, per RAW magic-item-use semantics — a spell failure doesn't drain
## the bottle).
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

	# 3. Validate target params match the binding's target_mode.
	var target_mode: String = str(binding.get("target_mode", "self"))
	match target_mode:
		"self":
			# Drinker is both caster and target.
			pass
		"single_creature":
			if target_id.is_empty() or target_entity == null:
				empty["message"] = ("Potion '%s' requires a designated target (target_mode=%s)." %
					[item_key, target_mode])
				return empty
		_:
			empty["message"] = ("Potion '%s' has unsupported target_mode='%s'." %
				[item_key, target_mode])
			return empty

	# 4. Build CasterContext / SpellChoice / TargetDescriptor.
	var ctx: CasterContext = _build_caster_context(
		drinker, binding, map_context, origin_cell)
	var choice: SpellChoice = _build_spell_choice(binding)
	var descriptor: TargetDescriptor = _build_target_descriptor(
		binding, drinker, target_id, origin_cell)
	var targets_by_id: Dictionary = {}
	match target_mode:
		"self":
			# CharacterData.id is the canonical key.
			targets_by_id[drinker.id] = drinker
		"single_creature":
			targets_by_id[target_id] = target_entity

	# 5. Resolve the spell via the existing pipeline.
	var result: ResolutionResult = casting_resolver.resolve(
		ctx, choice, descriptor, drinker, targets_by_id)

	# 6. Consume the potion ONLY on success. The hand-drained-bottle rule: a
	# failed cast doesn't waste the dose. Consumed = inventory row deleted
	# (quantity == 1 always for potions in V1; stacks not modeled).
	var consumed: bool = false
	var message: String = ""
	if result != null and result.success:
		consumed = _consume_potion(item_id, item_row)
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
## entity. For self-targeted potions the drinker is the only target_id; for
## single_creature the caller supplies it.
static func _build_target_descriptor(
		binding: Dictionary,
		drinker: CharacterData,
		target_id: String,
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
			descriptor.target_ids = [drinker.id]
		"single_creature":
			descriptor.kind = "single_creature"
			descriptor.target_ids = [target_id]
	return descriptor


# ---------------------------------------------------------------------------
# Consumption
# ---------------------------------------------------------------------------

## Consume one dose of a potion. V1 assumes quantity == 1 for any potion
## (ACKS RAW doesn't model potion stacks). Returns true if the row was
## successfully removed.
static func _consume_potion(item_id: String, _item_row: Dictionary) -> bool:
	return CampaignRepository.remove_inventory_item(item_id)
