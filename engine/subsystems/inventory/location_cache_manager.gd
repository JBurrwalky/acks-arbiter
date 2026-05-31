# LocationCacheManager — location-scoped inventory caches for dropped items
#
# Dependencies:
#   - GameState (autoload): campaign_id scoping
#   - CampaignRepository (autoload): DB access for caches and their inventory items
#   - Timekeeping (autoload): day_changed / month_changed boundary signals
#   - DiceSystem (autoload): raid rolls (1d100 check, 2d4 loss percentage) and decay timers
#   - EventBus (autoload): cache lifecycle signals
#   - Currency (engine/subsystems/commerce/currency.gd): coin value lookups
#   - EquipmentCatalog (instantiated locally): item data for value computation
#
# Signals emitted (via EventBus):
#   - cache_created(cache_id, location_key, variant)
#   - cache_decayed(cache_id, items_lost)
#   - cache_raided(cache_id, items_lost, value_lost_gp)
#   - cache_picked_up(cache_id, item_id, carrier_id)
#   - cache_dropped(cache_id, item_id, source_carrier_id)
#
# Design note:
#   LocationCacheManager does NOT store items directly. Items live in inventory_items
#   with location_cache_id set. This class manages cache metadata and item routing only.
#
# No class_name — autoload scripts must not use class_name.

extends Node

const Currency := preload("res://engine/subsystems/commerce/currency.gd")


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _catalog: RefCounted = null  # EquipmentCatalog instance


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	var equip_script = load("res://engine/subsystems/characters/equipment_catalog.gd")
	if equip_script != null:
		_catalog = equip_script.new()
	Timekeeping.day_changed.connect(_on_day_changed)
	Timekeeping.month_changed.connect(_on_month_changed)
	# Bag of Devouring timer tick (2026-05-31). LocationCacheManager already
	# wires Timekeeping subscriptions for cache decay; bag-of-devouring
	# expiration is conceptually adjacent (timer-driven inventory deletion).
	Timekeeping.turn_advanced.connect(_on_turn_advanced)


## Tick handler for Bag of Devouring timers. On each turn advance, scan the
## active campaign's inventory for bags with expired timers (devouring_at_turn
## >= 0 AND devouring_at_turn <= current_turn) and devour their contents.
## See BagOfDevouringService for the mechanic + RAW context.
func _on_turn_advanced(_turns_elapsed: int) -> void:
	var campaign_id := GameState.campaign_id
	if campaign_id.is_empty():
		return
	var current_turn := Timekeeping.get_total_turns()
	var expired_ids: Array = BagOfDevouringService.find_expired_bags(campaign_id, current_turn)
	for bag_id in expired_ids:
		BagOfDevouringService.devour_contents(str(bag_id))


# ---------------------------------------------------------------------------
# Public API — Location key format
# ---------------------------------------------------------------------------

## Builds the canonical location_key for a dungeon cell cache. Format:
##   "dungeon:<dungeon_id>:cell:<col>,<row>,<level>"
## The level axis was added in migration 037 (voxel migration session 9);
## caches from before that point have level 0 backfilled by the migration.
static func build_dungeon_cell_key(dungeon_id: String, cell: Vector3i) -> String:
	return "dungeon:%s:cell:%d,%d,%d" % [dungeon_id, cell.x, cell.y, cell.z]


## Parses a dungeon cell location_key back to its components. Returns
##   {dungeon_id: String, cell: Vector3i}
## on success, or an empty Dictionary if the key doesn't match the dungeon-cell
## shape. Accepts legacy 2D keys (col,row) as level 0 for safety, though migration
## 037 upgrades them in place.
static func parse_dungeon_cell_key(location_key: String) -> Dictionary:
	var parts := location_key.split(":")
	if parts.size() < 4 or parts[0] != "dungeon" or parts[2] != "cell":
		return {}
	var coords: PackedStringArray = parts[3].split(",")
	if coords.size() < 2:
		return {}
	var level := 0 if coords.size() < 3 else int(coords[2])
	return {
		"dungeon_id": parts[1],
		"cell": Vector3i(int(coords[0]), int(coords[1]), level),
	}


# ---------------------------------------------------------------------------
# Public API — Cache creation
# ---------------------------------------------------------------------------

## Creates a loose cache in a dungeon cell. Decays in 1d7 days.
## Cell is a voxel coordinate (col, row, level); the location_key carries all
## three axes so caches on different floors at the same (col,row) are distinct.
func create_dungeon_loose_cache(dungeon_id: String, cell: Vector3i) -> String:
	var current_day := Timekeeping.get_total_days()
	var decay_roll := DiceSystem.roll_digital(7, 1, 0, "cache_decay_timer")
	var decay_day := current_day + decay_roll.modified_total
	var location_key := build_dungeon_cell_key(dungeon_id, cell)
	var cache_id := CampaignRepository.create_location_cache({
		"campaign_id": GameState.campaign_id,
		"location_type": "dungeon_cell",
		"location_key": location_key,
		"cache_variant": "loose",
		"container_item_id": null,
		"is_persistent": 0,
		"decay_check_day": decay_day,
		"created_at_day": current_day,
		"raid_monthly_modifier": 0,
	})
	if not cache_id.is_empty():
		EventBus.cache_created.emit(cache_id, location_key, "loose")
	return cache_id


## Creates a locked container cache in a dungeon cell. Persistent, no decay.
## Cell is a voxel coordinate (col, row, level).
func create_dungeon_container_cache(dungeon_id: String, cell: Vector3i, container_item_id: String) -> String:
	var current_day := Timekeeping.get_total_days()
	var location_key := build_dungeon_cell_key(dungeon_id, cell)
	var cache_id := CampaignRepository.create_location_cache({
		"campaign_id": GameState.campaign_id,
		"location_type": "dungeon_cell",
		"location_key": location_key,
		"cache_variant": "locked_container",
		"container_item_id": container_item_id,
		"is_persistent": 1,
		"decay_check_day": null,
		"created_at_day": current_day,
		"raid_monthly_modifier": 0,
	})
	if not cache_id.is_empty():
		EventBus.cache_created.emit(cache_id, location_key, "locked_container")
	return cache_id


## Creates a loose cache in a wilderness hex. Decays in 1d4 weeks.
func create_wilderness_loose_cache(hex_qr: Vector2i) -> String:
	var current_day := Timekeeping.get_total_days()
	var decay_roll := DiceSystem.roll_digital(4, 1, 0, "cache_decay_timer")
	var decay_day := current_day + (decay_roll.modified_total * 7)
	var location_key := "hex:%d,%d" % [hex_qr.x, hex_qr.y]
	var cache_id := CampaignRepository.create_location_cache({
		"campaign_id": GameState.campaign_id,
		"location_type": "hex",
		"location_key": location_key,
		"cache_variant": "loose",
		"container_item_id": null,
		"is_persistent": 0,
		"decay_check_day": decay_day,
		"created_at_day": current_day,
		"raid_monthly_modifier": 0,
	})
	if not cache_id.is_empty():
		EventBus.cache_created.emit(cache_id, location_key, "loose")
	return cache_id


## Creates a hidden wilderness cache. Persistent, subject to monthly raid checks.
func create_wilderness_hidden_cache(hex_qr: Vector2i) -> String:
	var current_day := Timekeeping.get_total_days()
	var location_key := "hex:%d,%d" % [hex_qr.x, hex_qr.y]
	var cache_id := CampaignRepository.create_location_cache({
		"campaign_id": GameState.campaign_id,
		"location_type": "hex",
		"location_key": location_key,
		"cache_variant": "hidden_wilderness",
		"container_item_id": null,
		"is_persistent": 1,
		"decay_check_day": null,
		"created_at_day": current_day,
		"raid_monthly_modifier": 0,
	})
	if not cache_id.is_empty():
		EventBus.cache_created.emit(cache_id, location_key, "hidden_wilderness")
	return cache_id


## Creates a loose cache in a settlement POI. Decays in 1d7 days.
func create_settlement_cache(settlement_id: String, poi_id: String) -> String:
	var current_day := Timekeeping.get_total_days()
	var decay_roll := DiceSystem.roll_digital(7, 1, 0, "cache_decay_timer")
	var decay_day := current_day + decay_roll.modified_total
	var location_key := "settlement:%s:poi:%s" % [settlement_id, poi_id]
	var cache_id := CampaignRepository.create_location_cache({
		"campaign_id": GameState.campaign_id,
		"location_type": "settlement_node",
		"location_key": location_key,
		"cache_variant": "loose",
		"container_item_id": null,
		"is_persistent": 0,
		"decay_check_day": decay_day,
		"created_at_day": current_day,
		"raid_monthly_modifier": 0,
	})
	if not cache_id.is_empty():
		EventBus.cache_created.emit(cache_id, location_key, "loose")
	return cache_id


# ---------------------------------------------------------------------------
# Public API — Cache queries
# ---------------------------------------------------------------------------

## Returns the cache at a specific location key, or empty dict.
func get_cache_at_location(location_key: String) -> Dictionary:
	var campaign_id := GameState.campaign_id
	if campaign_id.is_empty():
		return {}
	return CampaignRepository.get_cache_at_location_key(campaign_id, location_key)


## Returns all caches for the active campaign.
func list_caches_for_campaign() -> Array:
	var campaign_id := GameState.campaign_id
	if campaign_id.is_empty():
		return []
	return CampaignRepository.list_location_caches(campaign_id)


## Returns all inventory items assigned to a cache.
func get_items_in_cache(cache_id: String) -> Array:
	return CampaignRepository.list_items_in_cache(cache_id)


# ---------------------------------------------------------------------------
# Public API — Item routing
# ---------------------------------------------------------------------------

## Drops an item into a cache. Clears all carrier FKs, sets location_cache_id.
## No capacity validation here — overlay layer does that.
func drop_item_to_cache(item_id: String, cache_id: String, source_carrier_id: String = "") -> bool:
	if not CampaignRepository.transfer_item_to_cache(item_id, cache_id):
		push_error("LocationCacheManager.drop_item_to_cache: transfer failed. item=%s cache=%s" % [
			item_id, cache_id])
		return false
	var cache := CampaignRepository.get_location_cache(cache_id)
	var location_key: String = cache.get("location_key", "")
	EventBus.cache_dropped.emit(cache_id, item_id, source_carrier_id)
	return true


## Picks up an item from a cache and assigns it to a carrier.
## carrier_type: "character" | "creature" | "vehicle"
func pick_up_item(item_id: String, target_carrier_id: String, carrier_type: String) -> bool:
	# Determine the cache_id before transfer (item still has location_cache_id)
	CampaignRepository.db.query_with_bindings(
		"SELECT location_cache_id FROM inventory_items WHERE id = ?", [item_id])
	var rows: Array = CampaignRepository.db.query_result
	var cache_id: String = ""
	if not rows.is_empty():
		cache_id = str(rows[0].get("location_cache_id", ""))

	if not CampaignRepository.transfer_item_from_cache(item_id, target_carrier_id, carrier_type):
		push_error("LocationCacheManager.pick_up_item: transfer failed. item=%s carrier=%s type=%s" % [
			item_id, target_carrier_id, carrier_type])
		return false
	EventBus.cache_picked_up.emit(cache_id, item_id, target_carrier_id)
	return true


# ---------------------------------------------------------------------------
# Public API — Hide-and-memorize
# ---------------------------------------------------------------------------

## Hides items at a wilderness hex. Costs 1 hour (6 turns) of party time.
## No proficiency check required. Returns the cache_id.
func hide_and_memorize_wilderness_cache(hex_qr: Vector2i, party_id: String) -> String:
	# 1 hour = 6 turns of 10 minutes each
	Timekeeping.advance_party_turns(party_id, 6)
	return create_wilderness_hidden_cache(hex_qr)


# ---------------------------------------------------------------------------
# Timekeeping integration — Daily decay
# ---------------------------------------------------------------------------

func _on_day_changed(_new_day: int, _new_month: int, _new_year: int) -> void:
	resolve_daily_decay(Timekeeping.get_total_days())


## Resolves decay for all ephemeral caches whose timer has expired.
## Public for testability; wired to Timekeeping.day_changed via _ready().
func resolve_daily_decay(current_day: int) -> void:
	var campaign_id := GameState.campaign_id
	if campaign_id.is_empty():
		return

	var caches := CampaignRepository.list_ephemeral_caches_due(campaign_id, current_day)

	for cache in caches:
		var variant: String = cache.get("cache_variant", "")
		# Only "loose" variants are ephemeral. locked_container and hidden_wilderness
		# are is_persistent = 1 and filtered out by the query, but double-check.
		if variant != "loose":
			continue

		var items := get_items_in_cache(cache.get("id", ""))
		var items_lost: Array = []

		# v1: all loose variants delete all items on decay.
		# Future: dungeon loose relocates 50% to pre-existing treasure caches (GDD §13.1).
		for item in items:
			items_lost.append({
				"item_id": item.get("id", ""),
				"name": item.get("name", ""),
			})
			CampaignRepository.remove_inventory_item(item.get("id", ""))

		CampaignRepository.delete_location_cache(cache.get("id", ""))
		EventBus.cache_decayed.emit(cache.get("id", ""), items_lost)


# ---------------------------------------------------------------------------
# Timekeeping integration — Monthly raids
# ---------------------------------------------------------------------------

func _on_month_changed(_new_month: int, _new_year: int) -> void:
	resolve_monthly_raids()


## Resolves monthly raid checks for all hidden wilderness caches.
## Public for testability; wired to Timekeeping.month_changed via _ready().
func resolve_monthly_raids() -> void:
	var campaign_id := GameState.campaign_id
	if campaign_id.is_empty():
		return

	var hidden_caches := CampaignRepository.list_hidden_wilderness_caches(campaign_id)

	for cache in hidden_caches:
		var cache_id: String = cache.get("id", "")

		# Accumulate risk: +1% per month
		var new_modifier: int = int(cache.get("raid_monthly_modifier", 0)) + 1
		CampaignRepository.update_cache_raid_modifier(cache_id, new_modifier)

		var raid_roll := DiceSystem.roll_digital(100, 1, 0, "cache_raid_roll")
		if raid_roll.modified_total > new_modifier:
			continue

		# Raid fires. 2d4 loss percentage.
		var loss_roll := DiceSystem.roll_digital(4, 2, 0, "cache_raid_loss")
		var sum_2d4: int = loss_roll.modified_total  # range 2–8
		var loss_pct: int = roundi(25.0 + (sum_2d4 - 2) * (50.0 / 6.0))

		var items := get_items_in_cache(cache_id)
		var total_value_cp: int = 0
		for item in items:
			total_value_cp += _compute_item_value_cp(item)

		var target_loss_cp: int = roundi(total_value_cp * loss_pct / 100.0)

		# Sort by value descending — remove highest-value items first
		items.sort_custom(func(a, b): return _compute_item_value_cp(a) > _compute_item_value_cp(b))

		var items_lost: Array = []
		var removed_value_cp: int = 0
		for item in items:
			if removed_value_cp >= target_loss_cp:
				break
			var item_value := _compute_item_value_cp(item)
			items_lost.append({
				"item_id": item.get("id", ""),
				"name": item.get("name", ""),
				"value_cp": item_value,
			})
			CampaignRepository.remove_inventory_item(item.get("id", ""))
			removed_value_cp += item_value

		# Raid resets obscurity
		CampaignRepository.update_cache_raid_modifier(cache_id, 0)

		var value_lost_gp: float = removed_value_cp / 100.0
		EventBus.cache_raided.emit(cache_id, items_lost, value_lost_gp)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Computes the value of an inventory item in copper pieces.
## Handles both coin items (via Currency.DENOMINATIONS) and equipment (via catalog).
func _compute_item_value_cp(item: Dictionary) -> int:
	var item_key: String = item.get("item_key", "")
	var quantity: int = int(item.get("quantity", 1))

	# Check if this is a coin item
	if Currency.is_coin(item_key):
		return Currency.coin_key_to_cp_value(item_key) * quantity

	# Look up equipment value from catalog
	if _catalog != null:
		var catalog_item: Dictionary = _catalog.get_item(item_key)
		if not catalog_item.is_empty():
			return int(catalog_item.get("cost_cp", 0)) * quantity

	return 0
