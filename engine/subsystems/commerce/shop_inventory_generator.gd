class_name ShopInventoryGenerator
extends RefCounted

## Generates and refreshes per-POI shop inventory based on ACKS market class
## availability rules and the GDD §7.1 shop-size fractions.
##
## Not an autoload — instantiate as needed: var gen := ShopInventoryGenerator.new()

const MARKET_AVAILABILITY_PATH := "res://data/equipment/market_availability.json"

## Monthly refresh: 30 game-days.
const REFRESH_INTERVAL_ROUNDS := 30 * Timekeeping.ROUNDS_PER_DAY

## Shop size → fraction of settlement-level availability (GDD §7.1).
const SHOP_SIZE_FRACTIONS := {
	"small": 0.10,
	"medium": 0.25,
	"large": 0.50,
}

## POI subtype → equipment categories sold.
const SUBTYPE_CATEGORIES := {
	"armorer":      ["armor", "shield"],
	"weaponsmith":  ["weapon"],
	"bowyer":       ["weapon", "ammunition"],  # bows, crossbows, arrows
	"general":      ["gear", "clothing", "ammunition"],
	"provisioner":  ["foodstuff"],
	"stables":      ["mount", "pack_animal", "draft_animal", "tack", "barding", "livestock"],
	"chandler":     ["gear", "clothing", "ammunition", "foodstuff"],
	"emporium":     [],  # empty = all categories
	"market":       [],
}

var _price_tiers: Array = []
var _catalog: EquipmentCatalog = null
var _load_error: String = ""


func _init() -> void:
	_catalog = EquipmentCatalog.new()
	_load_market_availability()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns true if the shop inventory for a POI needs to be regenerated.
static func needs_refresh(generated_at_round: int, current_round: int) -> bool:
	return (current_round - generated_at_round) >= REFRESH_INTERVAL_ROUNDS


## Generates shop inventory for a POI and persists it to the DB.
## Returns an array of { item_key, name, cost_cp, quantity_available, ... } dicts.
func generate(
	poi: Dictionary,
	market_class: int,
	settlement_id: String,
	campaign_id: String,
	current_round: int,
) -> Array[Dictionary]:
	if not _load_error.is_empty():
		push_error("ShopInventoryGenerator: cannot generate — %s" % _load_error)
		return []

	var market_idx := clampi(market_class, 1, 6) - 1  # 0-based index

	# Determine which equipment categories this shop sells.
	var poi_subtype: String = poi.get("subtype", "general")
	var allowed_categories: Array = SUBTYPE_CATEGORIES.get(poi_subtype, [])

	# Determine shop size fraction.
	var shop_size: String = poi.get("size", "medium")
	var fraction: float = SHOP_SIZE_FRACTIONS.get(shop_size, 0.25)

	# Get all items from the catalog.
	var all_items: Array[Dictionary]
	if allowed_categories.is_empty():
		# Emporium/market: sell all categories.
		all_items = _catalog.get_all_items()
	else:
		all_items = []
		for cat in allowed_categories:
			all_items.append_array(_catalog.get_items_by_category(cat))

	# Clear existing inventory for this POI before regenerating.
	CampaignRepository.clear_shop_inventory(campaign_id, poi.get("id", ""))

	var result: Array[Dictionary] = []
	var poi_id: String = poi.get("id", "")

	for item in all_items:
		var item_key: String = item.get("item_key", "")
		var cost_cp: int = int(item.get("cost_cp", 0))
		if cost_cp <= 0 or item_key.is_empty():
			continue

		# Skip coins and non-purchasable items.
		if Currency.is_coin(item_key):
			continue

		# Find the price tier for this item's cost.
		var settlement_qty := _get_settlement_availability(cost_cp, market_idx)
		if settlement_qty == 0:
			continue

		# Apply shop size fraction with banker's rounding.
		var raw_qty: float = settlement_qty * fraction
		var shop_qty: int = _bankers_round(raw_qty)
		if shop_qty <= 0:
			continue

		# Persist to DB.
		CampaignRepository.upsert_shop_inventory(
			campaign_id, settlement_id, poi_id,
			item_key, shop_qty, current_round)

		result.append({
			"item_key": item_key,
			"name": item.get("name", ""),
			"cost_cp": cost_cp,
			"quantity_available": shop_qty,
			"item_category": item.get("item_category", ""),
			"encumbrance_units": int(item.get("encumbrance_units", 0)),
		})

	return result


# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

## Returns the settlement-level availability quantity for a given item cost
## and market class index. Returns 0 if item is unavailable ("NA") or
## if the percentage check fails.
func _get_settlement_availability(cost_cp: int, market_idx: int) -> int:
	for tier in _price_tiers:
		if cost_cp <= int(tier["max_cp"]):
			var avail_array: Array = tier["availability"]
			if market_idx >= avail_array.size():
				return 0
			var val = avail_array[market_idx]
			if val is int or val is float:
				return int(val)
			# String: either a percentage or "NA".
			var s: String = str(val)
			if s == "NA":
				return 0
			# Parse percentage: "25%" → 25
			if s.ends_with("%"):
				var pct: float = float(s.trim_suffix("%"))
				if randf() * 100.0 < pct:
					return 1
				return 0
			return 0
	return 0


## Banker's rounding (round half to even).
static func _bankers_round(value: float) -> int:
	var floor_val := floori(value)
	var frac := value - float(floor_val)
	if absf(frac - 0.5) < 0.0001:
		# Exactly half: round to even.
		if floor_val % 2 == 0:
			return floor_val
		return floor_val + 1
	return roundi(value)


func _load_market_availability() -> void:
	var file := FileAccess.open(MARKET_AVAILABILITY_PATH, FileAccess.READ)
	if file == null:
		_load_error = "Cannot open %s" % MARKET_AVAILABILITY_PATH
		push_error("ShopInventoryGenerator: %s" % _load_error)
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_load_error = "JSON parse error in %s: %s" % [MARKET_AVAILABILITY_PATH, json.get_error_message()]
		push_error("ShopInventoryGenerator: %s" % _load_error)
		return

	var data: Dictionary = json.data
	_price_tiers = data.get("price_tiers", [])
	if _price_tiers.is_empty():
		_load_error = "No price_tiers in %s" % MARKET_AVAILABILITY_PATH
		push_error("ShopInventoryGenerator: %s" % _load_error)
