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
##     unassigned: Array of item dicts that couldn't be placed,
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

		# Step 4: No valid target — unassigned.
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

	for c in pcs:
		if not _would_worsen_band(c, item, carrier_enc):
			return c["carrier_id"]
	return ""


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

## Returns true if adding the item to this carrier would push them into a worse
## encumbrance band. For creatures/vehicles, checks pure capacity overflow only.
func _would_worsen_band(carrier: Dictionary, item: Dictionary, carrier_enc: Dictionary) -> bool:
	var carrier_id: String = carrier["carrier_id"]
	var carrier_type: String = carrier.get("carrier_type", "")
	var current_units: int = carrier_enc.get(carrier_id, 0)
	var max_units: int = carrier.get("max_enc_units", 20000)
	var item_enc: int = _item_total_enc(item)
	var proposed_units: int = current_units + item_enc

	# Creatures/vehicles: simple capacity check (no bands).
	if carrier_type in ["creature", "vehicle"]:
		return proposed_units > max_units

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
