class_name TreasureLootService
extends RefCounted

## Bridges placed dungeon treasure hoards into lootable location caches at
## individual cells (gdd-treasure-item-backing.md §15).
##
## Called by the dungeon runtime when a party interacts with a cell that may
## contain a placed treasure container: looks up the single UNLOOTED hoard at
## the cell, materialises it into a `loose` cache (pile types) or a
## `locked_container` cache backed by a real inventory_items row (chest /
## barrel / sack), marks the hoard looted, and returns the cache_id (plus
## container_item_id and lock/trap state) for the loot UI to consume via
## LocationCacheManager.
##
## Decoupled by design: this does NOT open UI and does NOT deposit coins or
## award treasure XP — the caller's existing loot-modal / pick-up flow handles
## coin deposit + XP exactly as it does for any other cache. The hoard's
## gems/jewelry land in the cache as real, weighed, valued items (value_cp),
## so they can be carried and sold. Magic items resolve through the
## MagicItemCatalog into real named items (or carriable placeholders for
## catalog misses).
##
## History: an earlier room-level entry point (`claim_room_hoards`) was
## retired in Commit 5 of the cell-based-treasure-containers arc once the
## cell-based flow was wired end-to-end through DungeonHandlers._resolve_loot.


## Materialise a single PLACED hoard into runtime state at its cell. Lazy —
## called on first interaction with the cell (Commit 3 of the cell-based
## treasure containers arc — gdd-treasure-item-backing.md §15).
##
## [param dungeon_id] scopes the cache location_key; [param floor_id] is the
## floor the hoard is on; [param cell] is the voxel cell where the placement
## service stamped the hoard.
##
## Behavior:
##   - Idempotent: if a cache already exists at this location_key, returns its
##     id + container_item_id verbatim (no re-materialization). Safe to call
##     on every cell-interaction tick.
##   - No-op when no unlooted hoard sits at the cell. Returns the empty result
##     with cache_id "".
##   - For pile container types (coin_pile / gear_pile): creates a `loose`
##     cache and drops coins + items into it (no backing container item).
##   - For backing-container types (chest / barrel / sack): creates a real
##     `inventory_items` row that IS the container — carrying the hoard's
##     is_locked + is_trapped flags forward (migration 138) — and a
##     `locked_container` cache linked to it via `container_item_id`. The
##     cache_variant `locked_container` is used for both locked AND unlocked
##     containers in V1; the variant means "has a backing container item",
##     not "is locked". Lock state is read from the container item's
##     is_locked field at interaction time (Commit 4).
##   - Marks the hoard `is_looted=1` after the cache is built (idempotent
##     guard against re-materialization).
##
## Returns {cache_id:String, container_item_id:String, hoard_id:String,
##   coins_cp:int, item_count:int, container_type:String, is_locked:bool,
##   is_trapped:bool, is_hidden:bool}. cache_id == "" means no hoard or
##   cache failure. is_hidden is true ONLY when a hidden hoard was found and
##   NOT materialized (the function short-circuits before creating a cache);
##   the caller (e.g. dungeon_handlers._resolve_loot) gates rendering /
##   interaction on it.
static func materialize_hoard_cell(
		dungeon_id: String, floor_id: String, cell: Vector3i) -> Dictionary:
	var empty := {
		"cache_id": "",
		"container_item_id": "",
		"hoard_id": "",
		"coins_cp": 0,
		"item_count": 0,
		"container_type": "",
		"is_locked": false,
		"is_trapped": false,
		"is_hidden": false,
	}

	# Idempotency: short-circuit if a cache already exists at this cell. The
	# only way the cache can pre-exist is a prior materialize_hoard_cell call
	# (or a save-game restore of one) — the placement service stamps a hoard,
	# never a cache. Returning the existing cache lets the cell-interaction
	# layer call us on every tick without duplicating rows.
	var location_key: String = LocationCacheManager.build_dungeon_cell_key(dungeon_id, cell)
	var existing: Dictionary = LocationCacheManager.get_cache_at_location(location_key)
	if not existing.is_empty():
		var ex_container_id: String = str(existing.get("container_item_id", "") if existing.get("container_item_id", null) != null else "")
		var ex_result: Dictionary = empty.duplicate()
		ex_result["cache_id"] = str(existing.get("id", ""))
		ex_result["container_item_id"] = ex_container_id
		# Re-derive lock / trap from the backing container item when present.
		if not ex_container_id.is_empty():
			var item_row: Dictionary = CampaignRepository.get_inventory_item_by_id(ex_container_id)
			if not item_row.is_empty():
				ex_result["is_locked"] = int(item_row.get("is_locked", 0)) == 1
				ex_result["is_trapped"] = int(item_row.get("is_trapped", 0)) == 1
				ex_result["container_type"] = str(item_row.get("item_key", "")).trim_prefix("treasure_container_")
		return ex_result

	# No cache yet — look for an unlooted hoard at this cell.
	var hoard: TreasureHoardData = (
		DungeonGeneratorRepository.get_unlooted_treasure_hoard_at_cell(floor_id, cell))
	if hoard == null:
		return empty

	# Hidden gate: a hidden hoard short-circuits materialization. The caller
	# decides what "hidden" means at the interaction layer (typically: the
	# player can't see it, and a Search check is required to reveal it before
	# it can be looted). Returning is_hidden=true lets the caller surface
	# "nothing here" or initiate a search prompt without re-querying the hoard.
	# The hoard stays is_looted=0 so a later un-hide + materialize call works.
	if hoard.is_hidden:
		var hidden_result: Dictionary = empty.duplicate()
		hidden_result["hoard_id"] = hoard.id
		hidden_result["container_type"] = hoard.container_type
		hidden_result["is_hidden"] = true
		hidden_result["is_locked"] = hoard.is_locked
		hidden_result["is_trapped"] = hoard.is_trapped
		return hidden_result

	# Branch on container kind.
	var pile_types: Array[String] = [TreasureContainerTypes.COIN_PILE, TreasureContainerTypes.GEAR_PILE]
	var is_pile: bool = hoard.container_type in pile_types
	var cache_id: String = ""
	var container_item_id: String = ""

	if is_pile:
		# Loose loot — no backing container item, plain `loose` cache.
		cache_id = LocationCacheManager.create_dungeon_loose_cache(dungeon_id, cell)
	else:
		# Container types: create the backing inventory_items row first so the
		# cache can reference it via container_item_id.
		container_item_id = _create_container_item(hoard)
		if container_item_id.is_empty():
			push_error("TreasureLootService.materialize_hoard_cell: container-item creation failed (hoard %s)" % hoard.id)
			return empty
		cache_id = LocationCacheManager.create_dungeon_container_cache(
			dungeon_id, cell, container_item_id)

	if cache_id.is_empty():
		push_error("TreasureLootService.materialize_hoard_cell: cache creation failed (dungeon=%s cell=%s)" % [
			dungeon_id, str(cell)])
		return empty

	# Coin + item materialization for this hoard.
	var coins_cp: int = _cache_coins(hoard, cache_id)
	var item_rng := RandomNumberGenerator.new()
	item_rng.seed = hash("treasure_loot|%s" % hoard.id)
	var loot: Dictionary = TreasureInstantiator.hoard_to_loot(hoard, item_rng, _magic_catalog())
	var item_count: int = 0
	item_count += _cache_items(loot["items"], cache_id)
	item_count += _cache_items(loot["magic_placeholders"], cache_id)

	# Flag the hoard so a future first-visit hit short-circuits at the
	# get_unlooted_treasure_hoard_at_cell step (defense-in-depth on top of the
	# cache-exists idempotency check above).
	DungeonGeneratorRepository.mark_hoard_looted(hoard.id)

	return {
		"cache_id": cache_id,
		"container_item_id": container_item_id,
		"hoard_id": hoard.id,
		"coins_cp": coins_cp,
		"item_count": item_count,
		"container_type": hoard.container_type,
		"is_locked": hoard.is_locked,
		"is_trapped": hoard.is_trapped,
	}


## Create the backing inventory_items row for a chest / barrel / sack hoard.
## Encumbrance comes from TreasureContainerTypes.PROPERTIES; the container is
## item_category "container" with a synthetic item_key so it isn't confused
## with a mundane catalog item. is_locked + is_trapped flow through from the
## hoard (migration 138).
static func _create_container_item(hoard: TreasureHoardData) -> String:
	var ct: String = hoard.container_type
	var props: Dictionary = TreasureContainerTypes.PROPERTIES.get(ct, {})
	var display_name: String = str(props.get("display_name", ct.capitalize()))
	var weight: int = int(props.get("weight_units", 0))
	return CampaignRepository.add_inventory_item({
		"character_id": "",
		"item_key": "treasure_container_%s" % ct,
		"name": display_name,
		"quantity": 1,
		"encumbrance_units": weight,
		"item_category": "container",
		"is_locked": hoard.is_locked,
		"is_trapped": hoard.is_trapped,
		"is_heavy": weight >= 1000,  # 1 stone or more
		# Containers carry no intrinsic gp value (the loot inside does). A future
		# pass may price them as mundane catalog items if players can move them.
		"value_cp": 0,
	})


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
