extends "res://tests/test_suite_base.gd"

## Integration tests for the dungeon loot placement pipeline.
##
## Exercises the DB-level flow that _place_dungeon_loot() depends on:
## cache creation → coin item insertion → cache lookup by location_key →
## item listing → cache cleanup. Uses GameState.dice_overrides for deterministic
## rolls and seeds test data directly into the DB.

const Currency := preload("res://engine/subsystems/commerce/currency.gd")

const TEST_CAMPAIGN := "test_dlp_campaign"
const TEST_PARTY := "test_dlp_party"
const PC_A := "test_dlp_pc_a"
const DUNGEON_ID := "test_dungeon_loot_001"


func run_all_tests() -> void:
	test_cache_created_with_coins_at_cell()
	test_cache_lookup_by_location_key()
	test_empty_cache_cleanup()
	test_coin_items_have_correct_category()
	test_multiple_denominations_in_cache()

	if not has_failures():
		print("DungeonLootPlacement: all tests passed.")


# ---------------------------------------------------------------------------
# Test data setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "DLP Test"])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Test Party"])

	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [PC_A, TEST_CAMPAIGN, "TestPC", "pc", "full", "human",
		  "fighter", 1, 0, "fighter", 10, 10, 10, 10, 10, 10])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO party_members (party_id, character_id, formation_slot) VALUES (?, ?, ?)",
		[TEST_PARTY, PC_A, "middle"])

	GameState.campaign_id = TEST_CAMPAIGN
	GameState.party_id = TEST_PARTY


func _cleanup() -> void:
	GameState.dice_overrides.clear()

	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [PC_A])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE location_cache_id IN (SELECT id FROM location_caches WHERE campaign_id = ?)",
		[TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM location_caches WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_members WHERE party_id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [PC_A])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])

	GameState.campaign_id = ""
	GameState.party_id = ""


## Inserts a coin item into the given cache, mirroring _place_dungeon_loot logic.
func _add_coin_to_cache(cache_id: String, coin_key: String, display_name: String,
		quantity: int) -> String:
	var item_id := CampaignRepository.generate_id()
	CampaignRepository.add_inventory_item({
		"id": item_id,
		"character_id": PC_A,
		"item_key": coin_key,
		"name": display_name,
		"quantity": quantity,
		"encumbrance_units": quantity * Currency.ENC_PER_COIN,
		"slot": "pack",
		"is_equipped": false,
		"item_category": Currency.COIN_ITEM_CATEGORY,
	})
	CampaignRepository.transfer_item_to_cache(item_id, cache_id)
	return item_id


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_cache_created_with_coins_at_cell() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 3

	var cell := Vector3i(5, 7, 1)
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, cell)
	check(not cache_id.is_empty(), "cache_id should be non-empty")

	_add_coin_to_cache(cache_id, "coins_gp", "Gold Pieces", 50)

	var items := CampaignRepository.list_items_in_cache(cache_id)
	check(items.size() == 1, "cache should have 1 item, got %d" % items.size())
	check(items[0].get("item_key") == "coins_gp", "item should be coins_gp")
	check(int(items[0].get("quantity", 0)) == 50, "quantity should be 50")

	_cleanup()


func test_cache_lookup_by_location_key() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 3

	var cell := Vector3i(2, 4, 0)
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, cell)
	check(not cache_id.is_empty(), "cache should be created")

	_add_coin_to_cache(cache_id, "coins_sp", "Silver Pieces", 200)

	var location_key := "dungeon:%s:cell:%d,%d,%d" % [DUNGEON_ID, cell.x, cell.y, cell.z]
	var found := CampaignRepository.get_cache_at_location_key(TEST_CAMPAIGN, location_key)
	check(not found.is_empty(), "cache should be found by location_key")
	check(found.get("id") == cache_id, "found cache id should match created id")

	_cleanup()


func test_empty_cache_cleanup() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 3

	var cell := Vector3i(1, 1, 0)
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, cell)
	var item_id := _add_coin_to_cache(cache_id, "coins_cp", "Copper Pieces", 100)

	# Remove the item
	CampaignRepository.remove_inventory_item(item_id)

	# Cache should now be empty
	var items := CampaignRepository.list_items_in_cache(cache_id)
	check(items.is_empty(), "cache should be empty after item removal")

	# Delete the empty cache
	var deleted := CampaignRepository.delete_location_cache(cache_id)
	check(deleted, "delete_location_cache should return true")

	# Verify cache is gone
	var cache := CampaignRepository.get_location_cache(cache_id)
	check(cache.is_empty(), "cache should no longer exist after deletion")

	_cleanup()


func test_coin_items_have_correct_category() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 3

	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(0, 0, 0))
	_add_coin_to_cache(cache_id, "coins_ep", "Electrum Pieces", 10)

	var items := CampaignRepository.list_items_in_cache(cache_id)
	check(items.size() == 1, "should have 1 item")
	check(items[0].get("item_category") == Currency.COIN_ITEM_CATEGORY,
		"coin item_category should be '%s', got '%s'" % [
			Currency.COIN_ITEM_CATEGORY, items[0].get("item_category", "")])

	_cleanup()


func test_multiple_denominations_in_cache() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 3

	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(3, 3, 0))
	_add_coin_to_cache(cache_id, "coins_gp", "Gold Pieces", 25)
	_add_coin_to_cache(cache_id, "coins_sp", "Silver Pieces", 100)
	_add_coin_to_cache(cache_id, "coins_cp", "Copper Pieces", 500)

	var items := CampaignRepository.list_items_in_cache(cache_id)
	check(items.size() == 3, "cache should have 3 items, got %d" % items.size())

	# Verify all are coins
	for item in items:
		check(Currency.is_coin(item.get("item_key", "")),
			"item '%s' should be a coin" % item.get("item_key", ""))

	_cleanup()
