class_name TreasureInstantiator
extends RefCounted

## Converts a generation-time TreasureHoardData (gdd-dungeon-generator-v1.md §13)
## into player-facing inventory: an aggregate coin value plus inventory-item
## templates for gems, jewelry, and magic items.
##
## Pure and deterministic — NO DB writes, NO signals. Returns a plan the caller
## applies (coins via PartyWallet.deposit_* / CampaignRepository.add_coins_cp;
## items via CampaignRepository.add_inventory_item after stamping an owner). This
## mirrors LootAutoDistributor's "return a plan, caller applies it" contract.
##
## The runtime-consumer contract: gdd-treasure-item-backing.md §5.
##
## ACKS RAW:
##   Encumbrance (rules/acore_equipment.xml:582-588): treasure is 1 stone per
##   1,000 coins or gems -> coin = 1 unit, gem = 1 unit. Jewelry weight is a RAW
##   gap; project decision (Jedidiah 2026-05-28): jewelry = 1 unit, same as a gem
##   (gdd-treasure-item-backing.md §7). One "item" = 1/6 stone = 167 units
##   (item_counting_rule) governs magic-item placeholders.
##   Value: value_cp = value_gp * 100 — exact, since gem/jewelry gp values are
##   whole integers (no rounding needed).
##   Magic items grant 0 recovery XP by RAW
##   (rules/acore_treasure_and_magic_items_rules.xml:6, :184-216) but DO carry a
##   sale value (value_gp -> value_cp) from the catalog; with an rng + a loaded
##   MagicItemCatalog they resolve to real, priced named items, else to carriable
##   placeholder stubs (gdd §5 step 4, §9).

const GEM_ENC_UNITS := 1                  ## 1/1,000 stone (RAW: acore_equipment.xml:586)
const JEWELRY_ENC_UNITS := 1              ## project decision §7 — gem-equivalent
const MAGIC_PLACEHOLDER_ENC_UNITS := 167  ## 1 item = 1/6 stone (acore_equipment.xml:592)
const GP_TO_CP := 100


## Converts a hoard into a loot plan.
## Returns {
##   coins_cp:int,                      # aggregate coin value (Currency rates)
##   items:Array[Dictionary],           # gem + jewelry inventory-item templates
##   magic_placeholders:Array[Dictionary],  # carriable unidentified-magic stubs
## }
## items / magic_placeholders are inventory_items-shaped dicts WITHOUT an owner —
## the caller stamps character_id (or party_id / creature_id) before insert.
static func hoard_to_loot(
		hoard: TreasureHoardData,
		rng: RandomNumberGenerator = null,
		magic_catalog = null) -> Dictionary:
	if hoard == null:
		return {"coins_cp": 0, "items": [], "magic_placeholders": []}
	var items: Array = []
	items.append_array(_gem_items(hoard))
	items.append_array(_jewelry_items(hoard))
	# Magic items become real named catalog items when an rng + a loaded
	# MagicItemCatalog are supplied; otherwise they stay carriable placeholders.
	var magic: Dictionary = _resolve_magic(hoard, rng, magic_catalog)
	items.append_array(magic["items"])
	return {
		"coins_cp": coins_cp(hoard),
		"items": items,
		"magic_placeholders": magic["placeholders"],
	}


## Aggregate coin value in copper pieces (Currency 1e exchange rates).
static func coins_cp(hoard: TreasureHoardData) -> int:
	return (
		hoard.platinum * 500
		+ hoard.gold * 100
		+ hoard.electrum * 50
		+ hoard.silver * 10
		+ hoard.copper
	)


static func _gem_items(hoard: TreasureHoardData) -> Array:
	var out: Array = []
	for gem: Dictionary in hoard.gems:
		var gem_class: String = str(gem.get("gem_class", "gem"))
		var value_gp: int = int(gem.get("value_gp", 0))
		var nm: String = "Gem" if gem_class == "gem" else "%s gem" % gem_class.capitalize()
		out.append({
			"item_key": "gem_%s" % gem_class,
			"name": nm,
			"quantity": 1,
			"item_category": "gem",
			"encumbrance_units": GEM_ENC_UNITS,
			"is_heavy": false,
			"is_magical": false,
			"value_cp": value_gp * GP_TO_CP,
			"slot": "pack",
		})
	return out


static func _jewelry_items(hoard: TreasureHoardData) -> Array:
	var out: Array = []
	for jwl: Dictionary in hoard.jewelry:
		var jwl_class: String = str(jwl.get("jewelry_class", "jewelry"))
		var value_gp: int = int(jwl.get("value_gp", 0))
		out.append({
			"item_key": "jewelry_%s" % jwl_class,
			"name": jwl_class.capitalize(),
			"quantity": 1,
			"item_category": "jewelry",
			"encumbrance_units": JEWELRY_ENC_UNITS,
			"is_heavy": false,
			"is_magical": false,
			"value_cp": value_gp * GP_TO_CP,
			"slot": "pack",
		})
	return out


## Resolve a hoard's magic items. With a loaded MagicItemCatalog + rng, each
## indicated item becomes a real named item (Phase 2 catalog). Without them — or
## when the catalog cannot resolve the indicated category — it stays a carriable,
## identifiable placeholder stub (non-sellable, 0 value, 1-item weight) so nothing
## is lost. Returns {items:Array (real magic items), placeholders:Array}.
static func _resolve_magic(hoard: TreasureHoardData, rng, magic_catalog) -> Dictionary:
	var real_items: Array = []
	var placeholders: Array = []
	var can_resolve: bool = rng != null and magic_catalog != null and magic_catalog.is_loaded()
	for mi: Dictionary in hoard.magic_items:
		var category: String = str(mi.get("category", "any"))
		var resolved: Dictionary = magic_catalog.pick_for_token(category, rng) if can_resolve else {}
		if not resolved.is_empty():
			# Sale value: value_gp from the catalog (priced found item) -> cp.
			# value_gp 0 (cursed/worthless) -> value_cp 0 (carriable, non-sellable);
			# value_gp -1 (unpriced) -> value_cp -1. Magic items still grant 0
			# recovery XP by RAW regardless of sale value.
			var rv_gp: int = int(resolved.get("value_gp", -1))
			var rv_cp: int = (rv_gp * GP_TO_CP) if rv_gp >= 0 else -1
			# Initial charges for charged items (wands, staves) — pulled from
			# the catalog's spell_binding.default_charges per RAW: a freshly-
			# materialized wand starts at full charge. -1 = not a charged item
			# (potions, persistent rings, etc.). When the activator decrements
			# uses_remaining to 0 the item becomes useless and non-magical
			# (acore_treasure_and_magic_items_rules.xml identification_and_use).
			#
			# Tier 4 Cluster A (2026-06-01): charged items that DON'T bind to a
			# spell (e.g. Rod of Cancellation — see SPECIAL_CHARGED_EFFECTS in
			# tools/extract_magic_item_catalog.py) stamp `default_charges` at
			# the TOP LEVEL of the catalog entry. Check the binding first, then
			# fall back to the top-level field.
			#
			# Tier 4 magic swords (2026-06-01): some items roll their charge
			# count at materialization time (Life Drinker 1d4+4, Luck Blade
			# 1d4+1) rather than starting at a fixed value. The catalog
			# stamps the dice expression as a STRING (e.g. "1d4+4"); _roll_charges
			# detects the string vs. int and rolls if needed using the supplied
			# rng for determinism in tests.
			var binding: Variant = resolved.get("spell_binding", null)
			var initial_uses: int = -1
			if binding is Dictionary:
				initial_uses = _roll_charges(
					(binding as Dictionary).get("default_charges", -1), rng)
			if initial_uses < 0 and resolved.has("default_charges"):
				initial_uses = _roll_charges(resolved.get("default_charges", -1), rng)
			# Magic containers (Bag of Holding, Bag of Devouring, future Portable
			# Hole etc.) carry a `container_behavior` block on their catalog
			# entry. When present, override item_category to "container",
			# propagate is_extradimensional, and stamp capacity_units so the
			# transfer-time capacity enforcement (update_inventory_item_equip_state)
			# has a per-row cap. Sub-carrier refactor 2026-05-31 + bags 2026-05-31.
			var container_behavior_v: Variant = resolved.get("container_behavior", null)
			var item_category: String = "magic"
			var is_extradimensional: bool = false
			var capacity_units: int = 0
			if container_behavior_v is Dictionary:
				var cb: Dictionary = container_behavior_v
				item_category = str(cb.get("item_category", item_category))
				is_extradimensional = bool(cb.get("is_extradimensional", false))
				capacity_units = int(cb.get("capacity_units", 0))
			real_items.append({
				"item_key": str(resolved.get("item_key", "magic_item")),
				"name": str(resolved.get("name", "Magic item")),
				"quantity": 1,
				"item_category": item_category,
				"encumbrance_units": int(resolved.get("encumbrance_units", MAGIC_PLACEHOLDER_ENC_UNITS)),
				"is_heavy": false,
				"is_magical": true,
				"magical_bonus": int(resolved.get("magical_bonus", 0)),
				"value_cp": rv_cp,
				"uses_remaining": initial_uses,
				"slot": "pack",
				"notes": _magic_item_notes(resolved),
				# RAW: acore_treasure_and_magic_items_rules.xml:233-237 — cursed
				# items propagate the catalog flag through to the inventory row;
				# the equip-state path enforces the sticky-unequip rule.
				"is_cursed": bool(resolved.get("is_cursed", false)),
				# Container metadata (zero/false for non-containers, real values
				# from container_behavior for Bag of Holding / Devouring / etc.).
				"is_extradimensional": is_extradimensional,
				"capacity_units": capacity_units,
			})
		else:
			placeholders.append({
				"item_key": "magic_placeholder",
				"name": "Unidentified magic item (%s)" % category,
				"quantity": 1,
				"item_category": "magic",
				"encumbrance_units": MAGIC_PLACEHOLDER_ENC_UNITS,
				"is_heavy": false,
				"is_magical": true,
				"magical_bonus": 0,
				"value_cp": -1,
				"uses_remaining": -1,
				"slot": "pack",
				"notes": str(mi.get("notes", "")),
			})
	return {"items": real_items, "placeholders": placeholders}


## Human-readable notes for a resolved magic item. For generated Scrolls of
## Spells, records the rolled class + spell levels (specific named spells are
## bound later by the usage session).
static func _magic_item_notes(resolved: Dictionary) -> String:
	var note: String = "Found magic item; effects pending the identification/usage system."
	if resolved.has("spell_levels"):
		note += " %s scroll, spell levels %s." % [
			str(resolved.get("scroll_class", "")).capitalize(),
			str(resolved.get("spell_levels", [])),
		]
	return note


## Resolve a default_charges field that may be either an int (fixed
## charges, e.g. Rod of Cancellation = 1, Wand of Fireballs = 20) or a
## dice expression string (e.g. Life Drinker = "1d4+4", Luck Blade =
## "1d4+1"). Returns the rolled / fixed int. Returns -1 when the input
## is null or an unparseable type (sentinel: "no charges set").
##
## Uses the supplied rng (the same rng caller-passed for hoard
## randomization) so tests can seed the materializer for deterministic
## charge counts.
static func _roll_charges(value, rng: RandomNumberGenerator) -> int:
	if value == null:
		return -1
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is String:
		var s: String = value
		if s.is_empty():
			return -1
		# Plain integer string.
		if s.is_valid_int():
			return s.to_int()
		# Parse a simple dice expression: NdM+K / NdM-K / NdM (no modifier).
		var lower: String = s.to_lower().strip_edges()
		var modifier: int = 0
		var dice_part: String = lower
		# Strip the modifier suffix.
		var plus_idx: int = lower.rfind("+")
		var minus_idx: int = lower.rfind("-")
		var sep_idx: int = maxi(plus_idx, minus_idx)
		if sep_idx > 0:
			var mod_str: String = lower.substr(sep_idx)
			modifier = mod_str.to_int()
			dice_part = lower.substr(0, sep_idx)
		var d_idx: int = dice_part.find("d")
		if d_idx <= 0:
			return -1
		var count: int = dice_part.substr(0, d_idx).to_int()
		var sides: int = dice_part.substr(d_idx + 1).to_int()
		if count <= 0 or sides <= 0:
			return -1
		var total: int = modifier
		if rng != null:
			for i in range(count):
				total += rng.randi_range(1, sides)
		else:
			# No rng — return the average (rounded) so the catalog tests
			# without an rng get a stable, reproducible value.
			total += count * ((sides + 1) / 2)
		return total
	return -1
