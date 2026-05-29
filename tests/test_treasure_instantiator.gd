extends "res://tests/test_suite_base.gd"

## Unit tests for TreasureInstantiator (gdd-treasure-item-backing.md §5).
## Pure logic — no DB. Builds a TreasureHoardData and asserts the loot plan:
## coin aggregation, gem/jewelry item templates (value_cp + 1-unit weight),
## and carriable magic-item placeholder stubs.
##
## Also hosts a DB-backed ShopService integration test (gem sale by value_cp).
## It lives in THIS suite — which is registered to run last — so its
## generate_id() calls do not perturb the global, randomize()'d _id_rng
## sequence that earlier RNG-seeded suites (e.g. shipping-contract offers)
## implicitly depend on.

const _DB_CAMPAIGN := "test_treasure_backing_campaign"
const _DB_CHAR := "test_treasure_backing_char"
const _DB_POI := "test_treasure_backing_poi"
const _DUNGEON_ID := "test_treasure_backing_dungeon"
const _FLOOR_ID := "test_treasure_backing_floor"
const _ROOM_ID := 7


func run_all_tests() -> void:
	test_coins_cp_aggregation()
	test_gems_become_weighted_valued_items()
	test_jewelry_become_weighted_valued_items()
	test_value_cp_is_gp_times_100_exact()
	test_coins_are_not_emitted_as_items()
	test_magic_items_become_carriable_placeholders()
	test_magic_items_resolve_with_catalog()
	test_null_hoard_is_empty_plan()
	test_empty_hoard_is_empty_plan()
	test_shop_sells_gem_by_value_cp()
	test_shop_sells_priced_magic_item()
	test_claim_room_hoards_creates_cache()
	test_claim_room_hoards_idempotent_and_empty()
	# Cell-based materialization (Commit 3 of the cell-based treasure containers arc).
	test_materialize_no_hoard_returns_empty()
	test_materialize_pile_creates_loose_cache_without_container_item()
	test_materialize_chest_creates_container_item_and_cache()
	test_materialize_marks_hoard_looted()
	test_materialize_is_idempotent()
	test_materialize_trap_fallback_locked_chest()
	# Cursed items (RAW: acore_treasure_and_magic_items_rules.xml:233-237)
	test_cursed_catalog_item_propagates_is_cursed()
	test_cursed_item_round_trips_through_inventory_item()
	test_sticky_unequip_blocks_cursed_item_removal()
	test_unequipping_non_cursed_item_still_works()
	if not has_failures():
		print("TreasureInstantiator: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _hoard() -> TreasureHoardData:
	return TreasureHoardData.new()


# ---------------------------------------------------------------------------
# Coins
# ---------------------------------------------------------------------------

func test_coins_cp_aggregation() -> void:
	var h := _hoard()
	h.platinum = 1   # 500
	h.gold = 2       # 200
	h.electrum = 1   # 50
	h.silver = 3     # 30
	h.copper = 4     # 4
	var plan := TreasureInstantiator.hoard_to_loot(h)
	check(int(plan["coins_cp"]) == 784,
		"coins_cp should be 784 (1pp+2gp+1ep+3sp+4cp), got %d" % int(plan["coins_cp"]))


func test_coins_are_not_emitted_as_items() -> void:
	var h := _hoard()
	h.gold = 5
	var plan := TreasureInstantiator.hoard_to_loot(h)
	for item: Dictionary in plan["items"]:
		check(str(item.get("item_category", "")) != "treasure",
			"coins must not appear in the items list (handled via coins_cp)")
	check(plan["items"].is_empty(), "a coins-only hoard yields no item templates")


# ---------------------------------------------------------------------------
# Gems
# ---------------------------------------------------------------------------

func test_gems_become_weighted_valued_items() -> void:
	var h := _hoard()
	h.gems = [
		{"value_gp": 200, "gem_class": "gem"},
		{"value_gp": 30, "gem_class": "ornamental"},
	]
	var plan := TreasureInstantiator.hoard_to_loot(h)
	var items: Array = plan["items"]
	check(items.size() == 2, "two gems should yield two item templates, got %d" % items.size())
	var g0: Dictionary = items[0]
	check(str(g0.get("item_category", "")) == "gem", "gem item_category should be 'gem'")
	check(int(g0.get("encumbrance_units", -1)) == 1, "gem weighs 1 unit (1/1000 stone), got %d" % int(g0.get("encumbrance_units", -1)))
	check(int(g0.get("value_cp", -1)) == 20000, "200gp gem -> value_cp 20000, got %d" % int(g0.get("value_cp", -1)))
	check(bool(g0.get("is_magical", true)) == false, "gem is not magical")
	check(str(g0.get("item_key", "")) == "gem_gem", "gem item_key should be 'gem_gem'")


# ---------------------------------------------------------------------------
# Jewelry
# ---------------------------------------------------------------------------

func test_jewelry_become_weighted_valued_items() -> void:
	var h := _hoard()
	h.jewelry = [{"value_gp": 1000, "jewelry_class": "jewelry"}]
	var plan := TreasureInstantiator.hoard_to_loot(h)
	var items: Array = plan["items"]
	check(items.size() == 1, "one jewelry piece should yield one item template, got %d" % items.size())
	var j0: Dictionary = items[0]
	check(str(j0.get("item_category", "")) == "jewelry", "jewelry item_category should be 'jewelry'")
	check(int(j0.get("encumbrance_units", -1)) == 1,
		"jewelry weighs 1 unit (project decision §7), got %d" % int(j0.get("encumbrance_units", -1)))
	check(int(j0.get("value_cp", -1)) == 100000, "1000gp jewelry -> value_cp 100000, got %d" % int(j0.get("value_cp", -1)))
	check(str(j0.get("item_key", "")) == "jewelry_jewelry", "jewelry item_key should be 'jewelry_jewelry'")


func test_value_cp_is_gp_times_100_exact() -> void:
	var h := _hoard()
	h.gems = [{"value_gp": 4000, "gem_class": "brilliant"}]
	var plan := TreasureInstantiator.hoard_to_loot(h)
	check(int(plan["items"][0].get("value_cp", -1)) == 400000,
		"4000gp brilliant -> value_cp 400000 (exact, no rounding)")


# ---------------------------------------------------------------------------
# Magic items
# ---------------------------------------------------------------------------

func test_magic_items_become_carriable_placeholders() -> void:
	var h := _hoard()
	h.magic_items = [{
		"category": "any", "specific_item_id": "", "is_placeholder": true,
		"notes": "Treasure type A: 'any' x1 indicated",
	}]
	var plan := TreasureInstantiator.hoard_to_loot(h)
	var stubs: Array = plan["magic_placeholders"]
	check(stubs.size() == 1, "one magic item -> one placeholder stub, got %d" % stubs.size())
	var m0: Dictionary = stubs[0]
	check(bool(m0.get("is_magical", false)) == true, "magic placeholder is flagged is_magical")
	check(int(m0.get("value_cp", 0)) == -1, "magic placeholder has no sale value yet (value_cp -1)")
	check(str(m0.get("item_category", "")) == "magic", "magic placeholder item_category 'magic'")
	check(int(m0.get("encumbrance_units", -1)) == 167,
		"magic placeholder weighs 1 item = 167 units, got %d" % int(m0.get("encumbrance_units", -1)))
	# Magic items are never emitted in the regular sellable items list.
	check(plan["items"].is_empty(), "magic items go to magic_placeholders, not items")


func test_magic_items_resolve_with_catalog() -> void:
	# With an rng + a loaded MagicItemCatalog, a magic item resolves to a real
	# named catalog item (in `items`), not a placeholder.
	var h := _hoard()
	h.magic_items = [{"category": "potion", "notes": "x"}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var plan := TreasureInstantiator.hoard_to_loot(h, rng, MagicItemCatalog.new())
	check(plan["magic_placeholders"].is_empty(),
		"with a loaded catalog, the magic item resolves (no placeholder)")
	var magic: Array = []
	for it in plan["items"]:
		if bool(it.get("is_magical", false)):
			magic.append(it)
	check(magic.size() == 1, "one resolved magic item, got %d" % magic.size())
	var key: String = str(magic[0].get("item_key", ""))
	check(key != "magic_placeholder", "resolved item is a real catalog item, not a placeholder")
	check(key.begins_with("potion"), "'potion' token resolves to a potion item_key, got '%s'" % key)
	# A resolved catalog item carries an authoritative value_cp (priced or, for a
	# cursed potion, 0) — never the -1 placeholder sentinel.
	check(int(magic[0].get("value_cp", -1)) >= 0,
		"resolved priced magic item carries value_cp >= 0, got %d" % int(magic[0].get("value_cp", -1)))


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

func test_null_hoard_is_empty_plan() -> void:
	var plan := TreasureInstantiator.hoard_to_loot(null)
	check(int(plan["coins_cp"]) == 0, "null hoard -> 0 coins")
	check(plan["items"].is_empty(), "null hoard -> no items")
	check(plan["magic_placeholders"].is_empty(), "null hoard -> no magic placeholders")


func test_empty_hoard_is_empty_plan() -> void:
	var plan := TreasureInstantiator.hoard_to_loot(_hoard())
	check(int(plan["coins_cp"]) == 0, "empty hoard -> 0 coins")
	check(plan["items"].is_empty(), "empty hoard -> no items")
	check(plan["magic_placeholders"].is_empty(), "empty hoard -> no magic placeholders")


# ---------------------------------------------------------------------------
# DB-backed: a gem instantiated from a hoard is a real, sellable inventory item
# ---------------------------------------------------------------------------

func test_shop_sells_gem_by_value_cp() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "Treasure Backing Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR, _DB_CAMPAIGN, "Gem Seller", "fighter", 1, 0, 8, 8])
	GameState.campaign_id = _DB_CAMPAIGN

	# A gem template, as TreasureInstantiator would emit it.
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "gem_gem", "name": "Gem",
		"quantity": 1, "encumbrance_units": 1, "item_category": "gem", "value_cp": 20000,
	})

	# value_cp must round-trip through the migration-134 column.
	var stored_value := -999
	for r in CampaignRepository.get_inventory_items(_DB_CHAR):
		if r.get("id", "") == item_id:
			stored_value = int(r.get("value_cp", -999))
	check(stored_value == 20000, "value_cp should persist to the DB, got %d" % stored_value)

	# The gem is not in the equipment catalog; it sells at its value_cp.
	var service := ShopService.new()
	var wealth_before := CampaignRepository.get_character_wealth_cp(_DB_CHAR)
	var result := service.sell_item(_DB_CHAR, item_id, _DB_POI, _DB_CAMPAIGN)
	check(result["success"], "gem should be sellable by value_cp: %s" % result.get("message", ""))
	var wealth_after := CampaignRepository.get_character_wealth_cp(_DB_CHAR)
	check(wealth_after == wealth_before + 20000,
		"selling a 200gp gem should add 20000cp, was %d now %d" % [wealth_before, wealth_after])

	# Teardown.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
	print("  shop_sells_gem_by_value_cp: OK")


# ---------------------------------------------------------------------------
# DB-backed: priced found magic items sell; cursed (0) / crafted (-1) do not
# ---------------------------------------------------------------------------

func test_shop_sells_priced_magic_item() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "Magic Sale Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR, _DB_CAMPAIGN, "Magic Seller", "fighter", 1, 0, 8, 8])
	GameState.campaign_id = _DB_CAMPAIGN

	# Priced found magic item (a 30,000gp wand): value_cp = 3,000,000.
	var priced_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "wand_of_fire_balls", "name": "Wand of Fire Balls",
		"quantity": 1, "encumbrance_units": 167, "item_category": "magic",
		"is_magical": true, "value_cp": 3000000,
	})
	# Cursed/worthless magic item: value_cp 0.
	var cursed_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "cursed_sword", "name": "Cursed Sword",
		"quantity": 1, "encumbrance_units": 167, "item_category": "magic",
		"is_magical": true, "value_cp": 0,
	})
	# Crafted/quest magic item with no authoritative value: value_cp -1.
	var unpriced_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "sword", "name": "Crafted Sword +1",
		"quantity": 1, "encumbrance_units": 167, "item_category": "magic",
		"is_magical": true, "value_cp": -1,
	})

	var service := ShopService.new()

	# get_sellable_items: only the priced magic item appears.
	var sellable_ids := {}
	for s in service.get_sellable_items(_DB_CHAR):
		sellable_ids[str(s.get("item_id", ""))] = true
	check(sellable_ids.has(priced_id), "priced magic item is sellable-listed")
	check(not sellable_ids.has(cursed_id), "cursed (value 0) magic item is NOT sellable-listed")
	check(not sellable_ids.has(unpriced_id), "unpriced (value -1) magic item is NOT sellable-listed")

	# sell_item: priced sells at value_cp; the other two are rejected.
	var wealth_before := CampaignRepository.get_character_wealth_cp(_DB_CHAR)
	var ok := service.sell_item(_DB_CHAR, priced_id, _DB_POI, _DB_CAMPAIGN)
	check(ok["success"], "priced magic item sells: %s" % ok.get("message", ""))
	var wealth_after := CampaignRepository.get_character_wealth_cp(_DB_CHAR)
	check(wealth_after == wealth_before + 3000000,
		"selling a 30000gp wand adds 3000000cp, was %d now %d" % [wealth_before, wealth_after])

	check(not service.sell_item(_DB_CHAR, cursed_id, _DB_POI, _DB_CAMPAIGN)["success"],
		"cursed (value 0) magic item is not sellable")
	check(not service.sell_item(_DB_CHAR, unpriced_id, _DB_POI, _DB_CAMPAIGN)["success"],
		"unpriced (value -1) magic item is not sellable")

	# Teardown.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
	print("  shop_sells_priced_magic_item: OK")


# ---------------------------------------------------------------------------
# DB-backed: TreasureLootService materialises a room's hoards into a cache
# ---------------------------------------------------------------------------

func test_claim_room_hoards_creates_cache() -> void:
	_loot_setup()
	# A hoard: 5 gp + a 200gp gem + a 1000gp jewelry + 1 magic item.
	_insert_hoard("test_hoard_1", _ROOM_ID, {
		"gold": 5,
		"gems": [{"value_gp": 200, "gem_class": "gem"}],
		"jewelry": [{"value_gp": 1000, "jewelry_class": "jewelry"}],
		"magic_items": [{"category": "any", "notes": "test"}],
		"total_gp_value": 1700,
	})

	var result := TreasureLootService.claim_room_hoards(
		_DUNGEON_ID, _FLOOR_ID, _ROOM_ID, Vector3i(2, 3, 0))
	check(not str(result["cache_id"]).is_empty(), "claim should create a cache")
	check(int(result["hoard_count"]) == 1, "one hoard claimed, got %d" % int(result["hoard_count"]))
	check(int(result["coins_cp"]) == 500, "5gp = 500cp, got %d" % int(result["coins_cp"]))

	# Cache holds 1 coin row (gp) + gem + jewelry + magic placeholder = 4 items.
	var cache_items := CampaignRepository.list_items_in_cache(str(result["cache_id"]))
	check(cache_items.size() == 4,
		"cache should hold 4 items (coin + gem + jewelry + magic), got %d" % cache_items.size())

	# The gem must carry its value_cp into the cache.
	var found_gem := false
	for ci in cache_items:
		if str(ci.get("item_key", "")) == "gem_gem":
			found_gem = true
			check(int(ci.get("value_cp", -1)) == 20000,
				"cached gem keeps value_cp 20000, got %d" % int(ci.get("value_cp", -1)))
	check(found_gem, "cache should contain the gem")

	# The magic item resolved to a real catalog item (not a placeholder), since
	# TreasureLootService passes a seeded rng + the MagicItemCatalog.
	var found_magic := false
	for ci in cache_items:
		if int(ci.get("is_magical", 0)) == 1:
			found_magic = true
			check(str(ci.get("item_key", "")) != "magic_placeholder",
				"cached magic item should be a real catalog item, not a placeholder")
	check(found_magic, "cache should contain a magic item")

	# Hoard is marked looted: a fresh unlooted query returns nothing.
	var remaining := DungeonGeneratorRepository.get_unlooted_treasure_hoards_for_room(_FLOOR_ID, _ROOM_ID)
	check(remaining.is_empty(), "hoard should be marked looted after claim")

	_loot_teardown()
	print("  claim_room_hoards_creates_cache: OK")


func test_claim_room_hoards_idempotent_and_empty() -> void:
	_loot_setup()

	# Empty room (no hoard) → no cache.
	var empty := TreasureLootService.claim_room_hoards(_DUNGEON_ID, _FLOOR_ID, 99, Vector3i(0, 0, 0))
	check(str(empty["cache_id"]).is_empty() and int(empty["hoard_count"]) == 0,
		"empty room yields no cache")

	# A hoard, claimed twice — second claim is a no-op.
	_insert_hoard("test_hoard_2", _ROOM_ID, {"gold": 1, "total_gp_value": 1})
	var first := TreasureLootService.claim_room_hoards(_DUNGEON_ID, _FLOOR_ID, _ROOM_ID, Vector3i(1, 1, 0))
	check(int(first["hoard_count"]) == 1, "first claim gets the hoard")
	var second := TreasureLootService.claim_room_hoards(_DUNGEON_ID, _FLOOR_ID, _ROOM_ID, Vector3i(1, 1, 0))
	check(int(second["hoard_count"]) == 0, "second claim is a no-op (idempotent)")

	_loot_teardown()
	print("  claim_room_hoards_idempotent_and_empty: OK")


# ---------------------------------------------------------------------------
# Cursed items (RAW: acore_treasure_and_magic_items_rules.xml:233-237)
# - Negative magical_bonus flows through the existing +N attack/AC paths.
# - is_cursed flag drives CampaignRepository.update_inventory_item_equip_state
#   to refuse UNEQUIPPING a currently-equipped cursed item.
# ---------------------------------------------------------------------------

func test_cursed_catalog_item_propagates_is_cursed() -> void:
	# Construct a hoard with a sword-category magic indicator. With the catalog
	# loaded + a seeded rng, TreasureInstantiator resolves it to a real catalog
	# item; if that item happens to be a Cursed Sword (the only sword with
	# is_cursed=true), the instantiated row must carry is_cursed=true. Test
	# directly by injecting the cursed entry via a custom seed scan — we
	# enumerate seeds until the resolver lands on cursed_sword.
	var h := _hoard()
	h.magic_items = [{"category": "sword", "notes": "test"}]
	var catalog := MagicItemCatalog.new()
	var found_cursed := false
	for seed_val in range(1, 200):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		var plan := TreasureInstantiator.hoard_to_loot(h, rng, catalog)
		var items: Array = plan["items"]
		if items.is_empty():
			continue
		var key: String = str(items[0].get("item_key", ""))
		if key == "cursed_sword":
			check(bool(items[0].get("is_cursed", false)) == true,
				"cursed_sword instantiated item carries is_cursed=true (seed %d)" % seed_val)
			check(int(items[0].get("magical_bonus", 99)) == -1,
				"cursed_sword carries -1 magical_bonus, got %d" % int(items[0].get("magical_bonus", 99)))
			found_cursed = true
			break
	check(found_cursed,
		"across 200 seeds at least one sword-category roll should land on cursed_sword")


func test_cursed_item_round_trips_through_inventory_item() -> void:
	# InventoryItem.from_dict / to_dict must preserve is_cursed across the
	# DB-integer / GDScript-bool boundary.
	var item := InventoryItem.from_dict({
		"id": "x", "item_key": "cursed_sword", "name": "Cursed Sword",
		"magical_bonus": -1, "is_cursed": 1, "is_magical": 1,
	})
	check(item.is_cursed == true, "is_cursed=1 -> bool true via from_dict")
	check(item.magical_bonus == -1, "magical_bonus=-1 preserved")
	var d := item.to_dict()
	check(int(d.get("is_cursed", -99)) == 1, "to_dict emits is_cursed=1 for sqlite")
	# Round-trip the dict back through from_dict.
	var item2 := InventoryItem.from_dict(d)
	check(item2.is_cursed == true, "is_cursed round-trips: true -> 1 -> true")


func test_sticky_unequip_blocks_cursed_item_removal() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "Cursed Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR, _DB_CAMPAIGN, "Cursed Wearer", "fighter", 1, 0, 8, 8])
	GameState.campaign_id = _DB_CAMPAIGN

	# A cursed sword, equipped in the main hand from the start.
	var cursed_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "cursed_sword", "name": "Cursed Sword",
		"quantity": 1, "encumbrance_units": 1000, "item_category": "weapon",
		"is_magical": true, "magical_bonus": -1, "is_cursed": true,
		"is_equipped": true, "slot": "hands_main",
	})

	# Try to unequip → must fail per RAW :235; item must remain equipped.
	var ok := CampaignRepository.update_inventory_item_equip_state(cursed_id, false, "pack", "")
	check(ok == false, "unequipping a cursed item must return false")
	CampaignRepository.db.query_with_bindings(
		"SELECT is_equipped, slot FROM inventory_items WHERE id = ?", [cursed_id])
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(int(row.get("is_equipped", 0)) == 1,
		"cursed item must remain equipped after a refused unequip attempt")
	check(str(row.get("slot", "")) == "hands_main",
		"slot must not change on a refused unequip attempt")

	# Manually clear the curse (simulating Remove Curse / Dispel Evil) — the
	# wearer should now be able to discard the item.
	CampaignRepository.db.query_with_bindings(
		"UPDATE inventory_items SET is_cursed = 0 WHERE id = ?", [cursed_id])
	var ok2 := CampaignRepository.update_inventory_item_equip_state(cursed_id, false, "pack", "")
	check(ok2 == true, "after Remove Curse clears is_cursed, unequip succeeds")

	# Teardown.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
	print("  sticky_unequip_blocks_cursed_item_removal: OK")


func test_unequipping_non_cursed_item_still_works() -> void:
	# Regression: the sticky check must not block UNCURSED items.
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "Non-Cursed Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR, _DB_CAMPAIGN, "Normal Wearer", "fighter", 1, 0, 8, 8])
	GameState.campaign_id = _DB_CAMPAIGN

	var sword_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "sword_1", "name": "Magic Sword +1",
		"quantity": 1, "encumbrance_units": 1000, "item_category": "weapon",
		"is_magical": true, "magical_bonus": 1, "is_cursed": false,
		"is_equipped": true, "slot": "hands_main",
	})
	check(CampaignRepository.update_inventory_item_equip_state(sword_id, false, "pack", "") == true,
		"uncursed magic sword unequips freely")

	# Teardown.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
	print("  unequipping_non_cursed_item_still_works: OK")


# ---------------------------------------------------------------------------
# DB-backed: TreasureLootService.materialize_hoard_cell (Commit 3 of the
# cell-based treasure containers arc — gdd-treasure-item-backing.md §15).
# ---------------------------------------------------------------------------

func test_materialize_no_hoard_returns_empty() -> void:
	_loot_setup()
	# No hoard at the cell → empty result, no cache created.
	var result := TreasureLootService.materialize_hoard_cell(
		_DUNGEON_ID, _FLOOR_ID, Vector3i(99, 99, 0))
	check(str(result["cache_id"]).is_empty(),
		"materialize on a hoardless cell yields no cache, got '%s'" % str(result["cache_id"]))
	check(str(result["container_item_id"]).is_empty(),
		"materialize on a hoardless cell yields no container item")
	check(str(result["hoard_id"]).is_empty(), "no hoard_id on no-op")
	_loot_teardown()
	print("  materialize_no_hoard_returns_empty: OK")


func test_materialize_pile_creates_loose_cache_without_container_item() -> void:
	_loot_setup()
	# A coin_pile hoard: loose loot — should create a `loose` cache with no
	# container_item_id, but with the coins + items inside.
	_insert_hoard("test_hoard_pile", _ROOM_ID, {
		"gold": 5,
		"gems": [{"value_gp": 200, "gem_class": "gem"}],
		"total_gp_value": 205,
		"cell_x": 10, "cell_y": 4, "cell_z": 0,
		"container_type": TreasureContainerTypes.COIN_PILE,
		"is_locked": false, "is_trapped": false,
	})

	var result := TreasureLootService.materialize_hoard_cell(
		_DUNGEON_ID, _FLOOR_ID, Vector3i(10, 4, 0))
	check(not str(result["cache_id"]).is_empty(), "pile materialization creates a cache")
	check(str(result["container_item_id"]).is_empty(),
		"pile materialization has NO container_item_id, got '%s'" % str(result["container_item_id"]))
	check(str(result["container_type"]) == TreasureContainerTypes.COIN_PILE,
		"result carries the container_type back to the caller")
	check(bool(result["is_locked"]) == false and bool(result["is_trapped"]) == false,
		"pile lock/trap flags are false")
	check(int(result["coins_cp"]) == 500, "5gp = 500cp, got %d" % int(result["coins_cp"]))

	# Cache must be variant `loose`.
	var cache_row: Dictionary = LocationCacheManager.get_cache_at_location(
		LocationCacheManager.build_dungeon_cell_key(_DUNGEON_ID, Vector3i(10, 4, 0)))
	check(str(cache_row.get("cache_variant", "")) == "loose",
		"pile cache variant should be 'loose', got '%s'" % str(cache_row.get("cache_variant", "")))

	# Cache holds the coins + gem (2 items).
	var cache_items := CampaignRepository.list_items_in_cache(str(result["cache_id"]))
	check(cache_items.size() == 2,
		"pile cache should hold 2 items (coin + gem), got %d" % cache_items.size())

	_loot_teardown()
	print("  materialize_pile_creates_loose_cache_without_container_item: OK")


func test_materialize_chest_creates_container_item_and_cache() -> void:
	_loot_setup()
	# A locked chest hoard: should create a backing inventory_items row that IS
	# the chest, plus a `locked_container` cache referencing it via
	# container_item_id, plus the coins + items INSIDE the cache.
	_insert_hoard("test_hoard_chest", _ROOM_ID, {
		"gold": 50,
		"jewelry": [{"value_gp": 1000, "jewelry_class": "jewelry"}],
		"total_gp_value": 1050,
		"cell_x": 7, "cell_y": 9, "cell_z": 0,
		"container_type": TreasureContainerTypes.CHEST,
		"is_locked": true, "is_trapped": false,
	})

	var result := TreasureLootService.materialize_hoard_cell(
		_DUNGEON_ID, _FLOOR_ID, Vector3i(7, 9, 0))
	check(not str(result["cache_id"]).is_empty(), "chest materialization creates a cache")
	check(not str(result["container_item_id"]).is_empty(),
		"chest materialization creates a backing container item")
	check(str(result["container_type"]) == TreasureContainerTypes.CHEST,
		"result carries container_type back")
	check(bool(result["is_locked"]) == true, "locked chest carries is_locked=true through to result")
	check(bool(result["is_trapped"]) == false, "non-trapped chest carries is_trapped=false")
	check(int(result["coins_cp"]) == 5000, "50gp = 5000cp, got %d" % int(result["coins_cp"]))

	# The backing container item exists, with the correct flags + key + weight.
	var container_row: Dictionary = CampaignRepository.get_inventory_item_by_id(
		str(result["container_item_id"]))
	check(not container_row.is_empty(), "container item exists in inventory_items")
	check(str(container_row.get("item_key", "")) == "treasure_container_chest",
		"container item_key is 'treasure_container_chest', got '%s'" % str(container_row.get("item_key", "")))
	check(int(container_row.get("is_locked", 0)) == 1,
		"backing chest item carries is_locked=1 from the hoard")
	check(int(container_row.get("is_trapped", 0)) == 0,
		"backing chest item carries is_trapped=0 from the hoard (got %d)" % int(container_row.get("is_trapped", 0)))
	check(str(container_row.get("item_category", "")) == "container",
		"container item_category is 'container'")
	check(int(container_row.get("encumbrance_units", 0)) == TreasureContainerTypes.weight_units(TreasureContainerTypes.CHEST),
		"backing chest weight matches the catalog (6000 units)")

	# Cache must be variant `locked_container` with container_item_id set.
	var cache_row: Dictionary = LocationCacheManager.get_cache_at_location(
		LocationCacheManager.build_dungeon_cell_key(_DUNGEON_ID, Vector3i(7, 9, 0)))
	check(str(cache_row.get("cache_variant", "")) == "locked_container",
		"chest cache variant should be 'locked_container', got '%s'" % str(cache_row.get("cache_variant", "")))
	check(str(cache_row.get("container_item_id", "")) == str(result["container_item_id"]),
		"cache.container_item_id should reference the backing chest item")

	# Cache holds the loot (coins + jewelry = 2 items). The chest item itself
	# is NOT inside the cache — it IS the container, referenced via
	# container_item_id.
	var cache_items := CampaignRepository.list_items_in_cache(str(result["cache_id"]))
	check(cache_items.size() == 2,
		"chest cache should hold 2 loot items (coin + jewelry), got %d" % cache_items.size())
	for ci in cache_items:
		check(str(ci.get("id", "")) != str(result["container_item_id"]),
			"the chest item itself must NOT be inside its own cache (it IS the container)")

	_loot_teardown()
	print("  materialize_chest_creates_container_item_and_cache: OK")


func test_materialize_marks_hoard_looted() -> void:
	_loot_setup()
	_insert_hoard("test_hoard_marked", _ROOM_ID, {
		"gold": 10,
		"total_gp_value": 10,
		"cell_x": 3, "cell_y": 3, "cell_z": 0,
		"container_type": TreasureContainerTypes.COIN_PILE,
	})

	# Pre-condition: hoard is unlooted.
	var pre: TreasureHoardData = DungeonGeneratorRepository.get_unlooted_treasure_hoard_at_cell(
		_FLOOR_ID, Vector3i(3, 3, 0))
	check(pre != null, "hoard should be unlooted before materialize")

	TreasureLootService.materialize_hoard_cell(_DUNGEON_ID, _FLOOR_ID, Vector3i(3, 3, 0))

	# Post-condition: hoard.is_looted=1, so the unlooted query returns nothing.
	var post: TreasureHoardData = DungeonGeneratorRepository.get_unlooted_treasure_hoard_at_cell(
		_FLOOR_ID, Vector3i(3, 3, 0))
	check(post == null, "hoard should be marked looted after materialize")

	_loot_teardown()
	print("  materialize_marks_hoard_looted: OK")


func test_materialize_is_idempotent() -> void:
	_loot_setup()
	_insert_hoard("test_hoard_idem", _ROOM_ID, {
		"gold": 25,
		"total_gp_value": 25,
		"cell_x": 5, "cell_y": 5, "cell_z": 0,
		"container_type": TreasureContainerTypes.SACK,
		"is_locked": false, "is_trapped": false,
	})

	var first := TreasureLootService.materialize_hoard_cell(
		_DUNGEON_ID, _FLOOR_ID, Vector3i(5, 5, 0))
	check(not str(first["cache_id"]).is_empty(), "first materialize creates a cache")
	var first_cache_id: String = str(first["cache_id"])
	var first_container_id: String = str(first["container_item_id"])
	var first_items := CampaignRepository.list_items_in_cache(first_cache_id)
	var first_item_count: int = first_items.size()

	# Second call: cache pre-exists, should return the SAME cache id without
	# duplicating items or creating a new container row.
	var second := TreasureLootService.materialize_hoard_cell(
		_DUNGEON_ID, _FLOOR_ID, Vector3i(5, 5, 0))
	check(str(second["cache_id"]) == first_cache_id,
		"second call returns the same cache_id (idempotent)")
	check(str(second["container_item_id"]) == first_container_id,
		"second call returns the same container_item_id")
	var second_items := CampaignRepository.list_items_in_cache(first_cache_id)
	check(second_items.size() == first_item_count,
		"cache item count unchanged after second materialize (was %d, now %d)"
			% [first_item_count, second_items.size()])

	_loot_teardown()
	print("  materialize_is_idempotent: OK")


func test_materialize_trap_fallback_locked_chest() -> void:
	_loot_setup()
	# The V1 trap-fallback guardrail: a hoard that "should" be trapped is emitted
	# by the placement service as is_locked=1, is_trapped=0. The materializer
	# must carry those flags through to the backing chest item — when the traps
	# system lands and a hoard arrives with is_trapped=1, the chest item gets
	# is_trapped=1 too. Here we exercise the V1 (fallback) shape.
	_insert_hoard("test_hoard_fallback", _ROOM_ID, {
		"gold": 100,
		"total_gp_value": 100,
		"cell_x": 1, "cell_y": 8, "cell_z": 0,
		"container_type": TreasureContainerTypes.CHEST,
		"is_locked": true, "is_trapped": false,   # V1 trap-fallback shape
	})

	var result := TreasureLootService.materialize_hoard_cell(
		_DUNGEON_ID, _FLOOR_ID, Vector3i(1, 8, 0))
	check(bool(result["is_locked"]) == true,
		"trap-fallback chest materializes with is_locked=true")
	check(bool(result["is_trapped"]) == false,
		"trap-fallback chest materializes with is_trapped=false (per V1 guardrail)")

	var container_row: Dictionary = CampaignRepository.get_inventory_item_by_id(
		str(result["container_item_id"]))
	check(int(container_row.get("is_locked", 0)) == 1,
		"backing chest item carries the locked flag forward")
	check(int(container_row.get("is_trapped", 0)) == 0,
		"backing chest item is not trapped (matches the hoard)")

	_loot_teardown()
	print("  materialize_trap_fallback_locked_chest: OK")


# ---------------------------------------------------------------------------
# Loot-service DB helpers
# ---------------------------------------------------------------------------

func _loot_setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "Treasure Loot Test", "Test World"])
	GameState.campaign_id = _DB_CAMPAIGN
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM treasure_hoards WHERE dungeon_id = ?", [_DUNGEON_ID])


func _insert_hoard(hoard_pk: String, room_id: int, fields: Dictionary) -> void:
	# container_type "" persists as SQL NULL (matches CHECK enum semantics).
	var container_type: Variant = null
	if not str(fields.get("container_type", "")).is_empty():
		container_type = fields["container_type"]
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO treasure_hoards
			(id, dungeon_id, floor_id, room_id, source, treasure_type_letter,
			 copper, silver, electrum, gold, platinum, gems, jewelry, magic_items,
			 total_gp_value, is_hidden,
			 cell_x, cell_y, cell_z, container_type, is_locked, is_trapped)
		VALUES (?, ?, ?, ?, 'lair', NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0,
			?, ?, ?, ?, ?, ?)
	""", [
		hoard_pk, _DUNGEON_ID, _FLOOR_ID, str(room_id),
		int(fields.get("copper", 0)), int(fields.get("silver", 0)),
		int(fields.get("electrum", 0)), int(fields.get("gold", 0)),
		int(fields.get("platinum", 0)),
		JSON.stringify(fields.get("gems", [])),
		JSON.stringify(fields.get("jewelry", [])),
		JSON.stringify(fields.get("magic_items", [])),
		int(fields.get("total_gp_value", 0)),
		int(fields.get("cell_x", -1)),
		int(fields.get("cell_y", -1)),
		int(fields.get("cell_z", 0)),
		container_type,
		1 if bool(fields.get("is_locked", false)) else 0,
		1 if bool(fields.get("is_trapped", false)) else 0,
	])


func _loot_teardown() -> void:
	# Delete cache items + caches created for the test campaign, then hoards + campaign.
	for c in LocationCacheManager.list_caches_for_campaign():
		var cid: String = str(c.get("id", ""))
		for it in CampaignRepository.list_items_in_cache(cid):
			CampaignRepository.remove_inventory_item(str(it.get("id", "")))
		CampaignRepository.delete_location_cache(cid)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM treasure_hoards WHERE dungeon_id = ?", [_DUNGEON_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
