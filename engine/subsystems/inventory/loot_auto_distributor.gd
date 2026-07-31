class_name LootAutoDistributor
extends RefCounted

# LootAutoDistributor — pure-logic auto-distribute algorithm for loot and existing inventory.
#
# Dependencies:
#   - EquipmentCatalog (local instance): item metadata lookup
#
# Design note:
#   Pure distribution — no side effects, no actual transfers. Returns a plan the
#   caller executes via CampaignRepository transfer methods or PartyWallet.deposit_*.
#   The overlay calls this to redistribute existing carrier loads; the loot modal
#   calls it to distribute queued items from combat/container/commission.
#
#   Coins (item_category == "treasure") are always excluded — they are handled
#   separately by the gold-share mechanism via PartyWallet.


# ---------------------------------------------------------------------------
# Preference tag → item matching rules
# ---------------------------------------------------------------------------
# Most equipment items share the broad "gear" category, so matching is done by
# item_key substrings and item properties rather than item_category alone.

## Each tag maps to a matcher dict: {categories: Array, key_patterns: Array, check_magical: bool}
const TAG_MATCHERS := {
	"torch_bearer": {
		"categories": [],
		"key_patterns": ["torch", "lantern", "oil_flask", "tinderbox"],
		"check_magical": false,
	},
	"rations_keeper": {
		"categories": ["foodstuff"],
		"key_patterns": ["rations"],
		"check_magical": false,
	},
	"scroll_keeper": {
		"categories": [],
		"key_patterns": ["scroll"],
		"check_magical": false,
	},
	"gold_purse": {
		"categories": ["treasure"],
		"key_patterns": [],
		"check_magical": false,
	},
	"rope_bearer": {
		"categories": [],
		"key_patterns": ["rope"],
		"check_magical": false,
	},
	"magic_item_keeper": {
		"categories": [],
		"key_patterns": [],
		"check_magical": true,
	},
	"ammunition_porter": {
		"categories": ["ammunition"],
		"key_patterns": [],
		"check_magical": false,
	},
	"healing_kit_keeper": {
		"categories": [],
		"key_patterns": ["potion", "birthwort", "woundwart", "healing", "comfrey", "goldenrod"],
		"check_magical": false,
	},
}

# Encumbrance band thresholds (replicating PartyInventoryTransferValidator._encumbrance_band).
# Band index: 0=unencumbered, 1=light, 2=heavy, 3=severe, 4=over_max
const _BAND_THRESHOLDS := [5000, 7000, 10000]  # Values above 10000 → band 3 (severe)


# ---------------------------------------------------------------------------
# Instance state
# ---------------------------------------------------------------------------

var _catalog: RefCounted  # EquipmentCatalog
var _round_robin_index: Dictionary = {}  # tag_or_rule -> int


func _init(catalog: RefCounted) -> void:
	_catalog = catalog


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Distributes items to carriers. Returns a plan the caller can preview and apply.
##
## items: Array of Dictionaries. Each must have:
##   - item_key: String
##   - quantity: int
##   - item_id: String (optional — present for existing inventory)
##   - item_category: String (optional — looked up from catalog if missing)
##   - encumbrance_units: int (optional — looked up from catalog if missing)
##   - source_carrier: Dictionary {carrier_type, carrier_id} (optional — for overlay mode)
##
## carriers: Array of Dictionaries. Each must have:
##   - carrier_id: String
##   - carrier_type: String ("pc", "henchman", "creature", "vehicle")
##   - current_enc_units: int
##   - max_enc_units: int
##   - preferences: Array of tag strings
##   - equipped_weapons: Array of item_key strings (for ammunition matching)
##   - strength: int (for heavy-item tiebreak)
##
## Returns:
##   {
##     moves: Array of {item: Dictionary, to_carrier: String, reason: String},
##       reason ∈ "preference_tag" | "heuristic" | "capacity_fallback"
##       ("capacity_fallback" = placed across an encumbrance band because every
##        carrier was already band-full but at least one had raw hard-cap room —
##        the loot policy places rather than drops).
##     unassigned: Array of item dicts that couldn't be placed. Each carries an
##       "unassigned_reason": "over_capacity" (no carrier has raw hard-cap room —
##       the loot modal surfaces these for a drop-to-make-room pass) or
##       "coin_excluded" (coins, handled separately by the gold-share mechanism).
##     summary: {total_items: int, moved: int, unassigned_count: int}
##   }
func distribute(items: Array, carriers: Array, _context: Dictionary = {}) -> Dictionary:
	_round_robin_index.clear()

	var moves: Array = []
	var unassigned: Array = []

	# Enrich items with catalog data where missing.
	var enriched_items: Array = []
	for item in items:
		enriched_items.append(_enrich_item(item.duplicate()))

	# Track running encumbrance per carrier so sequential assignments accumulate.
	var carrier_enc: Dictionary = {}  # carrier_id -> current_enc_units (running total)
	for c in carriers:
		carrier_enc[c["carrier_id"]] = c.get("current_enc_units", 0)

	for item in enriched_items:
		var category: String = item.get("item_category", "")

		# Step 1: Skip coins — handled separately by gold-share mechanism.
		if category == "treasure":
			item["unassigned_reason"] = "coin_excluded"
			unassigned.append(item)
			continue

		# Step 2: Preference-tag matching.
		var target_id := _find_preferred_carrier(item, carriers, carrier_enc)
		if not target_id.is_empty():
			var item_enc: int = _item_total_enc(item)
			carrier_enc[target_id] += item_enc
			moves.append({"item": item, "to_carrier": target_id, "reason": "preference_tag"})
			continue

		# Step 3: Generic heuristic fallback.
		target_id = _find_fallback_carrier(item, carriers, carrier_enc)
		if not target_id.is_empty():
			var item_enc: int = _item_total_enc(item)
			carrier_enc[target_id] += item_enc
			moves.append({"item": item, "to_carrier": target_id, "reason": "heuristic"})
			continue

		# Step 4: Capacity fallback — the loot policy forbids silently dropping
		# loot to the ground when a carrier could physically hold it. Steps 2-3
		# decline to WORSEN a carrier's encumbrance band, but a band is only the
		# soft cap (a movement penalty), not a hard limit (GDD gdd-inventory-tab
		# O-I6: auto-distribute must respect the HARD cap only). So before giving
		# up, place the item on the best carrier that still fits it under raw
		# hard-cap capacity, accepting the heavier band.
		target_id = _find_capacity_fallback_carrier(item, carriers, carrier_enc)
		if not target_id.is_empty():
			var item_enc: int = _item_total_enc(item)
			carrier_enc[target_id] += item_enc
			moves.append({"item": item, "to_carrier": target_id, "reason": "capacity_fallback"})
			continue

		# Step 5: Over hard-cap for every carrier — the item TRULY does not fit
		# anyone. Surface it unassigned with a reason the loot modal shows the
		# player, who can drop other gear to make room (never a silent discard).
		item["unassigned_reason"] = "over_capacity"
		unassigned.append(item)

	return {
		"moves": moves,
		"unassigned": unassigned,
		"summary": {
			"total_items": enriched_items.size(),
			"moved": moves.size(),
			"unassigned_count": unassigned.size(),
		},
	}


## Rebalances already-owned items across an adjacent-carrier cluster to equalize
## encumbrance. Differs from distribute():
##   - Input is existing inventory across `carriers` (no new loot queue).
##   - Target is even encumbrance_units spread, not preference matching.
##   - Equipped items never move.
##   - Coins are skipped (PartyWallet owns them).
##   - Everything gets a home (no "unassigned").
##
## Greedy first-fit-decreasing: items ranked heaviest first, each placed with
## the carrier that has the lowest projected total. Stable and good enough for
## party sizes 2–8; swap to a two-pass if the result feels lopsided.
##
## items: union of items across `carriers`. Each must carry item_id, source
##   carrier_id, encumbrance_units, quantity, is_equipped (optional). Coin items
##   and equipped items are ignored.
## carriers: same shape as distribute().
## _anchor_id: active character's carrier_id — preserved for future preference
##   (e.g. "keep torch on the leader"), not used by the base algorithm today.
## Returns {moves, summary}. moves only includes items whose destination differs
## from their current owner.
func redistribute_among_adjacent(items: Array, carriers: Array, _anchor_id: String = "") -> Dictionary:
	var moves: Array = []

	if carriers.is_empty():
		return {"moves": [], "summary": {"total_items": 0, "moved": 0, "unassigned_count": 0}}

	# Filter moveable items: skip coins, skip equipped.
	var movable: Array = []
	for raw_item in items:
		var item: Dictionary = _enrich_item(raw_item.duplicate())
		if item.get("item_category", "") == "treasure":
			continue
		var is_eq = item.get("is_equipped", false)
		if (is_eq is bool and is_eq) or (not (is_eq is bool) and int(is_eq) == 1):
			continue
		movable.append(item)

	# Sort heaviest-first so the greedy decision about the large items is made
	# before small ones fill the gaps.
	movable.sort_custom(func(a, b):
		return _item_total_enc(a) > _item_total_enc(b)
	)

	# Running totals per carrier start from their current_enc_units minus the
	# moveable contribution (so we compute the target delta against a clean base).
	var carrier_enc: Dictionary = {}
	for c in carriers:
		carrier_enc[c["carrier_id"]] = c.get("current_enc_units", 0)
	for item in movable:
		var src_id: String = str(item.get("source_carrier_id", item.get("character_id", "")))
		if not src_id.is_empty() and carrier_enc.has(src_id):
			carrier_enc[src_id] = max(0, carrier_enc[src_id] - _item_total_enc(item))

	# Assign each item to the carrier that would end up with the lowest total
	# after the item lands there, breaking ties by highest max capacity.
	for item in movable:
		var best_id: String = ""
		var best_total: int = 0
		var best_max: int = 0
		for c in carriers:
			var cid: String = c["carrier_id"]
			var item_enc: int = _item_total_enc(item)
			var projected: int = carrier_enc.get(cid, 0) + item_enc
			var max_units: int = c.get("max_enc_units", 20000)
			if projected > max_units:
				continue  # can't overflow capacity
			if best_id.is_empty() or projected < best_total \
					or (projected == best_total and max_units > best_max):
				best_id = cid
				best_total = projected
				best_max = max_units

		if best_id.is_empty():
			# Every carrier would overflow — leave this item where it is.
			continue

		carrier_enc[best_id] = best_total
		var src_id: String = str(item.get("source_carrier_id", item.get("character_id", "")))
		if best_id != src_id:
			moves.append({
				"item": item,
				"to_carrier": best_id,
				"from_carrier": src_id,
				"reason": "rebalance",
			})

	return {
		"moves": moves,
		"summary": {
			"total_items": movable.size(),
			"moved": moves.size(),
			"unassigned_count": 0,
		},
	}


# ---------------------------------------------------------------------------
# Preference-tag matching
# ---------------------------------------------------------------------------

func _find_preferred_carrier(item: Dictionary, carriers: Array, carrier_enc: Dictionary) -> String:
	for tag in TAG_MATCHERS:
		if tag == "gold_purse":
			continue  # Coins excluded
		if not _item_matches_tag(item, tag):
			continue
		# Find all carriers with this tag and capacity.
		var matching_carriers: Array = []
		for c in carriers:
			var prefs: Array = c.get("preferences", [])
			if tag in prefs:
				matching_carriers.append(c)

		if matching_carriers.is_empty():
			continue

		# Round-robin among matching carriers, skipping those that would worsen band.
		var target := _pick_round_robin(tag, matching_carriers, item, carrier_enc)
		if not target.is_empty():
			return target

	return ""


func _item_matches_tag(item: Dictionary, tag: String) -> bool:
	if not TAG_MATCHERS.has(tag):
		return false
	var matcher: Dictionary = TAG_MATCHERS[tag]
	var category: String = item.get("item_category", "")
	var key: String = item.get("item_key", "")

	# Check category match.
	for cat in matcher.get("categories", []):
		if category == cat:
			return true

	# Check item_key pattern match.
	for pattern in matcher.get("key_patterns", []):
		if key.contains(pattern):
			return true

	# Check magical property.
	if matcher.get("check_magical", false) and item.get("is_magical", false):
		return true

	return false


# ---------------------------------------------------------------------------
# Generic heuristic fallback (GDD §6.5)
# ---------------------------------------------------------------------------

func _find_fallback_carrier(item: Dictionary, carriers: Array, carrier_enc: Dictionary) -> String:
	var category: String = item.get("item_category", "")
	var key: String = item.get("item_key", "")
	var is_heavy: bool = item.get("is_heavy", false)
	var item_enc: int = _item_total_enc(item)

	# Heavy items (≥ 1 stone = 1000 units) → PC with highest STR and remaining capacity.
	if is_heavy or item_enc >= 1000:
		return _pick_highest_str(carriers, item, carrier_enc)

	# Ammunition → PC with matching ranged weapon equipped.
	if category == "ammunition":
		var target := _pick_ammo_match(key, carriers, item, carrier_enc)
		if not target.is_empty():
			return target
		# Fallback: round-robin among PCs.
		return _pick_round_robin("ammo_fallback", _filter_pcs(carriers), item, carrier_enc)

	# Magic items → PCs, round-robin.
	if item.get("is_magical", false):
		return _pick_round_robin("magic_rr", _filter_pcs(carriers), item, carrier_enc)

	# Rations/foodstuff → creatures first (abundant capacity), then PCs.
	if category == "foodstuff" or key.contains("rations"):
		var creatures := _filter_by_type(carriers, ["creature"])
		if not creatures.is_empty():
			var target := _pick_round_robin("rations_creatures", creatures, item, carrier_enc)
			if not target.is_empty():
				return target
		return _pick_round_robin("rations_pcs", _filter_pcs(carriers), item, carrier_enc)

	# Light sources → PCs, round-robin.
	if key.contains("torch") or key.contains("lantern") or key.contains("oil"):
		return _pick_round_robin("light_rr", _filter_pcs(carriers), item, carrier_enc)

	# Everything else → round-robin across PCs with remaining capacity.
	return _pick_round_robin("default_rr", _filter_pcs(carriers), item, carrier_enc)


# ---------------------------------------------------------------------------
# Ammunition-to-weapon matching (v1 approximation)
# ---------------------------------------------------------------------------
# Known Issue: substring matching — "arrow" pairs with "bow", "bolt" with "crossbow",
# "sling_stone" with "sling". Needs explicit catalog field for weapon/ammo relationships.

const _AMMO_WEAPON_MAP := {
	"arrow": ["bow"],          # shortbow, longbow, composite_bow (NOT crossbow)
	"bolt": ["crossbow", "arbalest"],
	"sling_stone": ["sling"],
	"dart": [],                # darts are self-contained, no launcher match needed
}

func _pick_ammo_match(ammo_key: String, carriers: Array, item: Dictionary, carrier_enc: Dictionary) -> String:
	# Determine which weapon patterns this ammo type matches.
	var weapon_patterns: Array = []
	for ammo_pattern in _AMMO_WEAPON_MAP:
		if ammo_key.contains(ammo_pattern):
			weapon_patterns = _AMMO_WEAPON_MAP[ammo_pattern]
			break

	if weapon_patterns.is_empty():
		return ""

	# Find carriers with a matching ranged weapon equipped.
	for c in carriers:
		var weapons: Array = c.get("equipped_weapons", [])
		for weapon_key in weapons:
			for pattern in weapon_patterns:
				# "bow" matches shortbow, longbow, composite_bow but NOT crossbow.
				# "crossbow" matches crossbow, arbalest.
				if pattern == "bow":
					if weapon_key.contains("bow") and not weapon_key.contains("crossbow"):
						if not _would_worsen_band(c, item, carrier_enc):
							return c["carrier_id"]
				else:
					if weapon_key.contains(pattern):
						if not _would_worsen_band(c, item, carrier_enc):
							return c["carrier_id"]
	return ""


# ---------------------------------------------------------------------------
# Carrier selection helpers
# ---------------------------------------------------------------------------

func _pick_round_robin(rule_key: String, candidates: Array, item: Dictionary, carrier_enc: Dictionary) -> String:
	if candidates.is_empty():
		return ""

	var start_idx: int = _round_robin_index.get(rule_key, 0)
	var count: int = candidates.size()

	for i in count:
		var idx: int = (start_idx + i) % count
		var c: Dictionary = candidates[idx]
		if not _would_worsen_band(c, item, carrier_enc):
			_round_robin_index[rule_key] = (idx + 1) % count
			return c["carrier_id"]

	return ""  # All candidates would worsen their band.


func _pick_highest_str(carriers: Array, item: Dictionary, carrier_enc: Dictionary) -> String:
	var pcs := _filter_pcs(carriers)
	if pcs.is_empty():
		return ""

	# Sort by STR descending, then remaining capacity descending.
	pcs.sort_custom(func(a, b):
		var str_a: int = a.get("strength", 10)
		var str_b: int = b.get("strength", 10)
		if str_a != str_b:
			return str_a > str_b
		var rem_a: int = a.get("max_enc_units", 20000) - carrier_enc.get(a["carrier_id"], 0)
		var rem_b: int = b.get("max_enc_units", 20000) - carrier_enc.get(b["carrier_id"], 0)
		return rem_a > rem_b
	)

	# Strongest carrier that can take it WITHOUT worsening a band. When none can
	# (a heavy item that would push every carrier into a worse encumbrance band),
	# return "" — but this is NOT the end of the line for the item: distribute()
	# then runs the capacity fallback (_find_capacity_fallback_carrier), which
	# places band-crossing heavy loot on the strongest carrier that still fits it
	# under raw hard-cap capacity. Only when NO carrier has hard-cap room does the
	# item stay unassigned, and even then the loot modal surfaces it for a
	# drop-to-make-room pass. Loot is never silently discarded.
	for c in pcs:
		if not _would_worsen_band(c, item, carrier_enc):
			return c["carrier_id"]
	return ""


# ---------------------------------------------------------------------------
# Capacity fallback (loot policy: place rather than drop)
# ---------------------------------------------------------------------------

## Last-resort placement used by distribute() when preference/heuristic passes
## all decline because the item would WORSEN every carrier's encumbrance band.
## Crossing a band is only a movement penalty, not a hard limit, so this pass
## places the item on the best carrier that can still hold it within raw hard-cap
## capacity. Heavy items prefer the strongest carrier (matching GDD §6.5 heavy
## routing); other items prefer the carrier with the most remaining capacity.
## Characters/henchmen are tried before creatures/vehicles. Returns "" only when
## NO carrier has raw room — i.e. the item is genuinely over capacity for all.
func _find_capacity_fallback_carrier(item: Dictionary, carriers: Array, carrier_enc: Dictionary) -> String:
	var item_enc: int = _item_total_enc(item)
	var is_heavy: bool = item.get("is_heavy", false) or item_enc >= 1000

	# Prefer PCs/henchmen; fall back to pack animals/vehicles as a final resort.
	var ordered: Array = _filter_pcs(carriers) + _filter_by_type(carriers, ["creature", "vehicle"])

	var best_id: String = ""
	var best_score: int = -1
	for c in ordered:
		var cid: String = c["carrier_id"]
		var current: int = carrier_enc.get(cid, 0)
		var max_units: int = c.get("max_enc_units", 20000)
		if current + item_enc > max_units:
			continue  # over hard cap for this carrier — cannot physically hold it
		# Score: strongest wins for heavy items, most-remaining wins otherwise.
		var score: int = c.get("strength", 10) if is_heavy else (max_units - current)
		if best_id.is_empty() or score > best_score:
			best_id = cid
			best_score = score
	return best_id


## Maps an `unassigned_reason` tag to a short player-facing phrase the loot modal
## interpolates into its alert. Pure/static so it is headless-testable.
static func describe_unassigned_reason(reason: String) -> String:
	match reason:
		"over_capacity":
			return "no one has enough carrying capacity"
		"coin_excluded":
			return "coins are shared separately"
		_:
			return "it couldn't be placed"


func _filter_pcs(carriers: Array) -> Array:
	var result: Array = []
	for c in carriers:
		var ct: String = c.get("carrier_type", "")
		if ct == "pc" or ct == "henchman":
			result.append(c)
	return result


func _filter_by_type(carriers: Array, types: Array) -> Array:
	var result: Array = []
	for c in carriers:
		if c.get("carrier_type", "") in types:
			result.append(c)
	return result


# ---------------------------------------------------------------------------
# Encumbrance band checking (GDD §6.5 rule 4)
# ---------------------------------------------------------------------------

## Returns true when the item should NOT be placed on this carrier in the
## band-respecting pass — either because it would exceed the carrier's raw
## hard-cap capacity (never allowed for anyone) or push a character into a worse
## encumbrance band. Bands top out at 10000 units while the hard cap is higher,
## so the explicit hard-cap guard is required: without it the heuristic could
## place an item that overflows raw capacity. The capacity fallback in
## distribute() may still cross a band, but it too honors the hard cap.
func _would_worsen_band(carrier: Dictionary, item: Dictionary, carrier_enc: Dictionary) -> bool:
	var carrier_id: String = carrier["carrier_id"]
	var carrier_type: String = carrier.get("carrier_type", "")
	var current_units: int = carrier_enc.get(carrier_id, 0)
	var max_units: int = carrier.get("max_enc_units", 20000)
	var item_enc: int = _item_total_enc(item)
	var proposed_units: int = current_units + item_enc

	# Hard cap: no carrier may exceed raw capacity, regardless of band.
	if proposed_units > max_units:
		return true

	# Creatures/vehicles: capacity only (no bands) — covered by the guard above.
	if carrier_type in ["creature", "vehicle"]:
		return false

	# Characters (PC/henchman): band comparison.
	var current_band: int = _encumbrance_band(current_units)
	var proposed_band: int = _encumbrance_band(proposed_units)
	return proposed_band > current_band


## Returns encumbrance band index: 0=unencumbered, 1=light, 2=heavy, 3=severe.
## Mirrors PartyInventoryTransferValidator._encumbrance_band() logic.
static func _encumbrance_band(units: int) -> int:
	if units <= _BAND_THRESHOLDS[0]:
		return 0
	if units <= _BAND_THRESHOLDS[1]:
		return 1
	if units <= _BAND_THRESHOLDS[2]:
		return 2
	return 3


# ---------------------------------------------------------------------------
# Item helpers
# ---------------------------------------------------------------------------

func _enrich_item(item: Dictionary) -> Dictionary:
	if _catalog == null:
		return item
	var key: String = item.get("item_key", "")
	if key.is_empty():
		return item
	var catalog_entry: Dictionary = _catalog.get_item(key)
	if catalog_entry.is_empty():
		return item
	if not item.has("item_category"):
		item["item_category"] = catalog_entry.get("item_category", "")
	if not item.has("encumbrance_units"):
		item["encumbrance_units"] = catalog_entry.get("encumbrance_units", 0)
	if not item.has("is_heavy"):
		item["is_heavy"] = catalog_entry.get("is_heavy", false)
	if not item.has("is_magical"):
		item["is_magical"] = catalog_entry.get("is_magical", false)
	return item


func _item_total_enc(item: Dictionary) -> int:
	return item.get("encumbrance_units", 0) * item.get("quantity", 1)
