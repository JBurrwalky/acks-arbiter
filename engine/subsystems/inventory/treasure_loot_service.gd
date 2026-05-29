class_name TreasureLootService
extends RefCounted

## Bridges generated dungeon treasure hoards into a lootable location cache.
##
## Called by the DG-V1 runtime-consumer when a party claims a room's treasure:
## loads the room's UNLOOTED hoards, materialises them into a dungeon loose cache
## (coins as per-denomination coin rows; gems/jewelry/magic as inventory items
## carrying value_cp), marks the hoards looted, and returns the cache_id for the
## existing loot-modal / pick-up-all flow to consume via LocationCacheManager.
##
## Decoupled by design: this does NOT open UI and does NOT deposit coins or award
## treasure XP — the caller's existing loot-modal / pick-up flow handles coin
## deposit + XP exactly as it does for any other cache. The hoard's gems/jewelry
## land in the cache as real, weighed, valued items (value_cp), so they can be
## carried and sold. Magic items land as carriable placeholders (Phase 2 catalog
## will upgrade them). See gdd-treasure-item-backing.md §5, §11; the contract is
## consumed by the dungeon runtime (gdd-dungeon-generator-v1.md).


## Materialise a room's unlooted treasure hoards into a dungeon loose cache.
##
## [param dungeon_id] scopes the cache location_key; [param floor_id] + [param
## room_id] identify the hoards; [param cell] is the voxel cell the cache sits in.
##
## Returns {cache_id:String, hoard_count:int, coins_cp:int, item_count:int}.
## cache_id == "" with hoard_count 0 means the room had no unlooted treasure.
## Idempotent: claimed hoards are flagged is_looted, so a second call is a no-op.
static func claim_room_hoards(
		dungeon_id: String, floor_id: String, room_id: int, cell: Vector3i) -> Dictionary:
	var empty := {"cache_id": "", "hoard_count": 0, "coins_cp": 0, "item_count": 0}

	var hoards: Array = DungeonGeneratorRepository.get_unlooted_treasure_hoards_for_room(
		floor_id, room_id)
	if hoards.is_empty():
		return empty

	var cache_id: String = LocationCacheManager.create_dungeon_loose_cache(dungeon_id, cell)
	if cache_id.is_empty():
		push_error("TreasureLootService.claim_room_hoards: cache creation failed (dungeon=%s cell=%s)" % [
			dungeon_id, str(cell)])
		return empty

	var total_coins_cp: int = 0
	var item_count: int = 0
	for h in hoards:
		var hoard: TreasureHoardData = h
		total_coins_cp += _cache_coins(hoard, cache_id)
		# Per-hoard seeded RNG → deterministic specific magic-item selection.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("treasure_loot|%s" % hoard.id)
		var loot: Dictionary = TreasureInstantiator.hoard_to_loot(hoard, rng, _magic_catalog())
		item_count += _cache_items(loot["items"], cache_id)
		item_count += _cache_items(loot["magic_placeholders"], cache_id)
		DungeonGeneratorRepository.mark_hoard_looted(hoard.id)

	return {
		"cache_id": cache_id,
		"hoard_count": hoards.size(),
		"coins_cp": total_coins_cp,
		"item_count": item_count,
	}


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Insert per-denomination coin rows for one hoard into the cache (so the loot
## modal / pick-up flow deposits them as it does any cached coins). Returns cp total.
static func _cache_coins(hoard: TreasureHoardData, cache_id: String) -> int:
	var pairs := [
		["coins_pp", hoard.platinum], ["coins_gp", hoard.gold],
		["coins_ep", hoard.electrum], ["coins_sp", hoard.silver],
		["coins_cp", hoard.copper],
	]
	var total_cp: int = 0
	for p in pairs:
		var key: String = p[0]
		var count: int = int(p[1])
		if count <= 0:
			continue
		var item_id: String = CampaignRepository.add_inventory_item({
			"character_id": "",
			"item_key": key,
			"name": Currency.coin_key_to_name(key),
			"quantity": count,
			"encumbrance_units": Currency.ENC_PER_COIN,
			"item_category": Currency.COIN_ITEM_CATEGORY,
		})
		if item_id.is_empty():
			continue
		CampaignRepository.transfer_item_to_cache(item_id, cache_id)
		total_cp += count * Currency.coin_key_to_cp_value(key)
	return total_cp


## Insert inventory-item templates (gems/jewelry/magic placeholders) into the
## cache. Each dict is created (carrying value_cp via add_inventory_item) then
## transferred to the cache. Returns the number placed.
static func _cache_items(items: Array, cache_id: String) -> int:
	var placed: int = 0
	for it in items:
		var data: Dictionary = (it as Dictionary).duplicate()
		data["character_id"] = ""
		var item_id: String = CampaignRepository.add_inventory_item(data)
		if item_id.is_empty():
			continue
		CampaignRepository.transfer_item_to_cache(item_id, cache_id)
		placed += 1
	return placed


## Lazily-cached found-magic-item catalog, shared across claims this session.
static var _magic_catalog_cache = null

static func _magic_catalog() -> MagicItemCatalog:
	if _magic_catalog_cache == null:
		_magic_catalog_cache = MagicItemCatalog.new()
	return _magic_catalog_cache
