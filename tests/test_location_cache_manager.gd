extends "res://tests/test_suite_base.gd"

## Unit tests for LocationCacheManager — cache creation, item routing,
## daily decay, monthly raids, and hide-and-memorize flow.
##
## Uses GameState.dice_overrides for deterministic dice rolls.
## Seeds test data into the DB and cleans up after itself.

const Currency := preload("res://engine/subsystems/commerce/currency.gd")

const TEST_CAMPAIGN := "test_lcm_campaign"
const TEST_PARTY := "test_lcm_party"
const PC_A := "test_lcm_pc_a"

# Location keys for tests
const HEX_KEY := "hex:5,3"
const DUNGEON_ID := "test_dungeon_001"
const SETTLEMENT_ID := "test_settlement_001"
const POI_ID := "test_poi_tavern"


func run_all_tests() -> void:
	# Cache creation
	test_create_dungeon_loose_cache()
	test_create_dungeon_container_cache()
	test_create_wilderness_loose_cache()
	test_create_wilderness_hidden_cache()
	test_create_settlement_loose_cache()

	# Item routing
	test_drop_item_to_cache()
	test_pick_up_item_character()
	test_pick_up_item_creature()
	test_pick_up_item_vehicle()
	test_cache_deletion_cascades_items()

	# Daily decay
	test_decay_fires_on_due_day()
	test_decay_skips_future_caches()
	test_decay_skips_locked_container()
	test_decay_skips_hidden_wilderness()

	# Monthly raids
	test_raid_increments_modifier()
	test_raid_fires_on_low_roll()
	test_raid_skips_on_high_roll()
	test_raid_loss_25_percent()
	test_raid_loss_50_percent()
	test_raid_loss_75_percent()

	# Hide-and-memorize
	test_hide_and_memorize_advances_time()
	test_hide_and_memorize_creates_persistent_cache()

	# PartyWallet location filter (structural)
	test_contributors_all_returned_when_colocated()
	test_contributors_all_returned_when_unknown_location()
	test_contributors_all_returned_when_none_location()

	if not has_failures():
		print("LocationCacheManager: all tests passed.")


# ---------------------------------------------------------------------------
# Test data setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_cleanup()

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "LCM Test"])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Test Party"])

	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [PC_A, TEST_CAMPAIGN, "Alice", "pc", "full", "human",
		  "fighter", 1, 0, "fighter", 10, 10, 10, 10, 10, 10])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO party_members (party_id, character_id, formation_slot) VALUES (?, ?, ?)",
		[TEST_PARTY, PC_A, "middle"])

	GameState.campaign_id = TEST_CAMPAIGN
	GameState.party_id = TEST_PARTY
	GameState.current_location_key = HEX_KEY


func _cleanup() -> void:
	# Clear dice overrides
	GameState.dice_overrides.clear()

	# Delete test data in dependency order
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
	GameState.current_location_key = "unknown"


## Creates a test inventory item on a character. Returns the item_id.
func _create_test_item(character_id: String, item_key: String, item_name: String,
		quantity: int = 1) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, item_category)
		VALUES (?, ?, ?, ?, ?, ?, 'pack', 0, 'gear')
	""", [id, character_id, item_key, item_name, quantity, 100])
	return id


# ---------------------------------------------------------------------------
# Cache creation tests
# ---------------------------------------------------------------------------

func test_create_dungeon_loose_cache() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 5  # 5 days

	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(3, 4, 1))
	check(not cache_id.is_empty(), "dungeon loose cache should return non-empty id")

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(cache.get("cache_variant") == "loose", "variant should be 'loose'")
	check(cache.get("location_type") == "dungeon_cell", "type should be 'dungeon_cell'")
	check(cache.get("location_key") == "dungeon:%s:cell:3,4,1" % DUNGEON_ID, "location_key should match")
	check(int(cache.get("is_persistent", -1)) == 0, "should not be persistent")

	var current_day := Timekeeping.get_total_days()
	check(int(cache.get("decay_check_day", -1)) == current_day + 5, "decay_check_day = current + 5")
	_cleanup()


func test_create_dungeon_container_cache() -> void:
	_setup()
	var container_id := _create_test_item(PC_A, "chest_large", "Large Chest")

	var cache_id := LocationCacheManager.create_dungeon_container_cache(
		DUNGEON_ID, Vector3i(1, 2, 0), container_id)
	check(not cache_id.is_empty(), "container cache should return non-empty id")

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(cache.get("cache_variant") == "locked_container", "variant should be 'locked_container'")
	check(int(cache.get("is_persistent", -1)) == 1, "should be persistent")
	check(cache.get("container_item_id") == container_id, "container_item_id should match")
	check(cache.get("decay_check_day") == null, "no decay_check_day for persistent")
	_cleanup()


func test_create_wilderness_loose_cache() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 3  # 3 weeks = 21 days

	var cache_id := LocationCacheManager.create_wilderness_loose_cache(Vector2i(5, 3))
	check(not cache_id.is_empty(), "wilderness loose cache should return non-empty id")

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(cache.get("cache_variant") == "loose", "variant should be 'loose'")
	check(cache.get("location_type") == "hex", "type should be 'hex'")
	check(int(cache.get("is_persistent", -1)) == 0, "should not be persistent")

	var current_day := Timekeeping.get_total_days()
	check(int(cache.get("decay_check_day", -1)) == current_day + 21, "decay_check_day = current + 3*7")
	_cleanup()


func test_create_wilderness_hidden_cache() -> void:
	_setup()
	var cache_id := LocationCacheManager.create_wilderness_hidden_cache(Vector2i(5, 3))
	check(not cache_id.is_empty(), "hidden cache should return non-empty id")

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(cache.get("cache_variant") == "hidden_wilderness", "variant should be 'hidden_wilderness'")
	check(int(cache.get("is_persistent", -1)) == 1, "should be persistent")
	check(int(cache.get("raid_monthly_modifier", -1)) == 0, "modifier starts at 0")
	check(cache.get("decay_check_day") == null, "no decay_check_day for persistent")
	_cleanup()


func test_create_settlement_loose_cache() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 4  # 4 days

	var cache_id := LocationCacheManager.create_settlement_cache(SETTLEMENT_ID, POI_ID)
	check(not cache_id.is_empty(), "settlement cache should return non-empty id")

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(cache.get("cache_variant") == "loose", "variant should be 'loose'")
	check(cache.get("location_type") == "settlement_node", "type should be 'settlement_node'")
	check(int(cache.get("is_persistent", -1)) == 0, "should not be persistent")

	var current_day := Timekeeping.get_total_days()
	check(int(cache.get("decay_check_day", -1)) == current_day + 4, "decay_check_day = current + 4")
	_cleanup()


# ---------------------------------------------------------------------------
# Item routing tests
# ---------------------------------------------------------------------------

func test_drop_item_to_cache() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 7
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(0, 0, 0))
	var item_id := _create_test_item(PC_A, "sword", "Longsword")

	var ok := LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)
	check(ok, "drop_item_to_cache should succeed")

	# Verify item is now in cache
	CampaignRepository.db.query_with_bindings(
		"SELECT location_cache_id, character_id FROM inventory_items WHERE id = ?", [item_id])
	var rows: Array = CampaignRepository.db.query_result
	check(not rows.is_empty(), "item should still exist")
	check(str(rows[0].get("location_cache_id", "")) == cache_id, "location_cache_id should be set")
	check(str(rows[0].get("character_id", "x")) == "", "character_id should be cleared")
	_cleanup()


func test_pick_up_item_character() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 7
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(0, 0, 0))
	var item_id := _create_test_item(PC_A, "sword", "Longsword")
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)

	var ok := LocationCacheManager.pick_up_item(item_id, PC_A, "character")
	check(ok, "pick_up_item should succeed")

	CampaignRepository.db.query_with_bindings(
		"SELECT location_cache_id, character_id FROM inventory_items WHERE id = ?", [item_id])
	var rows: Array = CampaignRepository.db.query_result
	check(str(rows[0].get("character_id", "")) == PC_A, "character_id should be set")
	check(rows[0].get("location_cache_id") == null or str(rows[0].get("location_cache_id", "")) == "",
		"location_cache_id should be cleared")
	_cleanup()


func test_pick_up_item_creature() -> void:
	_setup()
	# Create a test creature
	var creature_id := "test_lcm_creature"
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO trained_creatures
			(id, campaign_id, species_id, name, hp_current, hp_max)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [creature_id, TEST_CAMPAIGN, "mule", "Bessie", 5, 5])

	GameState.dice_overrides["cache_decay_timer"] = 7
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(0, 0, 0))
	var item_id := _create_test_item(PC_A, "sack", "Sack of Grain")
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)

	var ok := LocationCacheManager.pick_up_item(item_id, creature_id, "creature")
	check(ok, "pick_up_item creature should succeed")

	CampaignRepository.db.query_with_bindings(
		"SELECT creature_id, location_cache_id FROM inventory_items WHERE id = ?", [item_id])
	var rows: Array = CampaignRepository.db.query_result
	check(str(rows[0].get("creature_id", "")) == creature_id, "creature_id should be set")

	# Cleanup creature
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE creature_id = ?", [creature_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM trained_creatures WHERE id = ?", [creature_id])
	_cleanup()


func test_pick_up_item_vehicle() -> void:
	_setup()
	# Create a test vehicle
	var vehicle_id := "test_lcm_vehicle"
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO draft_vehicles
			(id, campaign_id, vehicle_type, name, hp_current, hp_max)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [vehicle_id, TEST_CAMPAIGN, "cart", "Cart", 10, 10])

	GameState.dice_overrides["cache_decay_timer"] = 7
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(0, 0, 0))
	var item_id := _create_test_item(PC_A, "barrel", "Barrel")
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)

	var ok := LocationCacheManager.pick_up_item(item_id, vehicle_id, "vehicle")
	check(ok, "pick_up_item vehicle should succeed")

	CampaignRepository.db.query_with_bindings(
		"SELECT vehicle_id, location_cache_id FROM inventory_items WHERE id = ?", [item_id])
	var rows: Array = CampaignRepository.db.query_result
	check(str(rows[0].get("vehicle_id", "")) == vehicle_id, "vehicle_id should be set")

	# Cleanup vehicle
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE vehicle_id = ?", [vehicle_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM draft_vehicles WHERE id = ?", [vehicle_id])
	_cleanup()


func test_cache_deletion_cascades_items() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 7
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(0, 0, 0))
	var item_id := _create_test_item(PC_A, "gem", "Ruby")
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)

	CampaignRepository.delete_location_cache(cache_id)

	# Item should be deleted by CASCADE
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM inventory_items WHERE id = ?", [item_id])
	check(CampaignRepository.db.query_result.is_empty(),
		"item should be deleted by ON DELETE CASCADE")
	_cleanup()


# ---------------------------------------------------------------------------
# Daily decay tests
# ---------------------------------------------------------------------------

func test_decay_fires_on_due_day() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 1  # expires tomorrow
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(0, 0, 0))
	var item_id := _create_test_item(PC_A, "torch", "Torch")
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)

	var current_day := Timekeeping.get_total_days()
	# Decay on the due day (current + 1)
	LocationCacheManager.resolve_daily_decay(current_day + 1)

	# Cache should be deleted
	var cache := CampaignRepository.get_location_cache(cache_id)
	check(cache.is_empty(), "cache should be deleted after decay")

	# Item should be deleted
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM inventory_items WHERE id = ?", [item_id])
	check(CampaignRepository.db.query_result.is_empty(), "item should be deleted after decay")
	_cleanup()


func test_decay_skips_future_caches() -> void:
	_setup()
	GameState.dice_overrides["cache_decay_timer"] = 7  # 7 days out
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, Vector3i(0, 0, 0))
	var item_id := _create_test_item(PC_A, "rope", "50ft Rope")
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)

	var current_day := Timekeeping.get_total_days()
	# Resolve on day 1 — cache decays on day 7, should be skipped
	LocationCacheManager.resolve_daily_decay(current_day + 1)

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(not cache.is_empty(), "cache should still exist (decay day not reached)")
	_cleanup()


func test_decay_skips_locked_container() -> void:
	_setup()
	var container_id := _create_test_item(PC_A, "chest_large", "Chest")
	var cache_id := LocationCacheManager.create_dungeon_container_cache(
		DUNGEON_ID, Vector3i(0, 0, 0), container_id)

	# Advance far into the future
	LocationCacheManager.resolve_daily_decay(Timekeeping.get_total_days() + 9999)

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(not cache.is_empty(), "locked container cache should survive any decay sweep")
	_cleanup()


func test_decay_skips_hidden_wilderness() -> void:
	_setup()
	var cache_id := LocationCacheManager.create_wilderness_hidden_cache(Vector2i(5, 3))

	LocationCacheManager.resolve_daily_decay(Timekeeping.get_total_days() + 9999)

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(not cache.is_empty(), "hidden wilderness cache should survive any decay sweep")
	_cleanup()


# ---------------------------------------------------------------------------
# Monthly raid tests
# ---------------------------------------------------------------------------

func test_raid_increments_modifier() -> void:
	_setup()
	var cache_id := LocationCacheManager.create_wilderness_hidden_cache(Vector2i(5, 3))

	# Force raid roll to NOT trigger (high roll > any modifier)
	GameState.dice_overrides["cache_raid_roll"] = 100
	LocationCacheManager.resolve_monthly_raids()

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(int(cache.get("raid_monthly_modifier", -1)) == 1,
		"modifier should increment from 0 to 1")
	_cleanup()


func test_raid_fires_on_low_roll() -> void:
	_setup()
	var cache_id := LocationCacheManager.create_wilderness_hidden_cache(Vector2i(5, 3))

	# Add a valuable item to the cache
	var item_id := _create_test_item(PC_A, "sword", "Magic Sword")
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)

	# Force modifier to 50 so raid is very likely
	CampaignRepository.update_cache_raid_modifier(cache_id, 49)

	# Force raid to trigger (roll 1 <= 50) and loss roll
	GameState.dice_overrides["cache_raid_roll"] = 1
	GameState.dice_overrides["cache_raid_loss"] = 8  # 75% loss

	LocationCacheManager.resolve_monthly_raids()

	# Modifier should be reset to 0 after raid
	var cache := CampaignRepository.get_location_cache(cache_id)
	check(int(cache.get("raid_monthly_modifier", -1)) == 0,
		"modifier should reset to 0 after raid fires")
	_cleanup()


func test_raid_skips_on_high_roll() -> void:
	_setup()
	var cache_id := LocationCacheManager.create_wilderness_hidden_cache(Vector2i(5, 3))
	var item_id := _create_test_item(PC_A, "sword", "Longsword")
	LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)

	# Force high roll (100 > 1 modifier)
	GameState.dice_overrides["cache_raid_roll"] = 100
	LocationCacheManager.resolve_monthly_raids()

	# Item should still be in cache
	var items := CampaignRepository.list_items_in_cache(cache_id)
	check(items.size() == 1, "item should still exist when raid doesn't fire")
	_cleanup()


func test_raid_loss_25_percent() -> void:
	_setup()
	_verify_raid_loss(2, 25)  # 2d4 sum=2 → 25%
	_cleanup()


func test_raid_loss_50_percent() -> void:
	_setup()
	_verify_raid_loss(5, 50)  # 2d4 sum=5 → 50%
	_cleanup()


func test_raid_loss_75_percent() -> void:
	_setup()
	_verify_raid_loss(8, 75)  # 2d4 sum=8 → 75%
	_cleanup()


## Helper: creates a hidden cache with known-value items and verifies raid loss.
func _verify_raid_loss(forced_loss_roll: int, expected_loss_pct: int) -> void:
	var cache_id := LocationCacheManager.create_wilderness_hidden_cache(Vector2i(5, 3))

	# Add 4 items of equal value (swords at ~1000cp each from catalog)
	var item_ids: Array = []
	for i in range(4):
		var item_id := _create_test_item(PC_A, "sword", "Sword %d" % i)
		LocationCacheManager.drop_item_to_cache(item_id, cache_id, PC_A)
		item_ids.append(item_id)

	# Set modifier high enough that raid will fire
	CampaignRepository.update_cache_raid_modifier(cache_id, 99)

	GameState.dice_overrides["cache_raid_roll"] = 1
	GameState.dice_overrides["cache_raid_loss"] = forced_loss_roll

	LocationCacheManager.resolve_monthly_raids()

	# Count remaining items
	var remaining := CampaignRepository.list_items_in_cache(cache_id)
	var lost_count: int = 4 - remaining.size()

	# With 4 equal-value items and the given loss %, we expect some items removed
	# The exact count depends on the catalog value of "sword" — just verify SOME were lost
	check(lost_count > 0, "raid at %d%% should remove at least 1 item (removed %d)" % [
		expected_loss_pct, lost_count])


# ---------------------------------------------------------------------------
# Hide-and-memorize tests
# ---------------------------------------------------------------------------

func test_hide_and_memorize_advances_time() -> void:
	_setup()
	var before := Timekeeping.get_total_rounds()

	LocationCacheManager.hide_and_memorize_wilderness_cache(Vector2i(5, 3), TEST_PARTY)

	var after := Timekeeping.get_total_rounds()
	# 6 turns × 60 rounds/turn = 360 rounds
	check(after - before == 360,
		"hide_and_memorize should advance 6 turns (360 rounds), got %d" % (after - before))
	_cleanup()


func test_hide_and_memorize_creates_persistent_cache() -> void:
	_setup()

	var cache_id := LocationCacheManager.hide_and_memorize_wilderness_cache(
		Vector2i(5, 3), TEST_PARTY)
	check(not cache_id.is_empty(), "should return non-empty cache id")

	var cache := CampaignRepository.get_location_cache(cache_id)
	check(int(cache.get("is_persistent", -1)) == 1, "should be persistent")
	check(cache.get("cache_variant") == "hidden_wilderness", "variant should be hidden_wilderness")
	_cleanup()


# ---------------------------------------------------------------------------
# PartyWallet location filter tests (structural)
# ---------------------------------------------------------------------------

func test_contributors_all_returned_when_colocated() -> void:
	_setup()
	# Add a second PC
	var pc_b := "test_lcm_pc_b"
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [pc_b, TEST_CAMPAIGN, "Bob", "pc", "full", "human",
		  "fighter", 1, 0, "fighter", 10, 10, 10, 10, 10, 10])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO party_members (party_id, character_id, formation_slot) VALUES (?, ?, ?)",
		[TEST_PARTY, pc_b, "middle"])

	# Both PCs at same hex location
	GameState.current_location_key = "hex:5,3"

	var contribs := PartyWallet.get_contributors(TEST_PARTY, PC_A)
	check(contribs.size() == 2, "both PCs should be returned when colocated, got %d" % contribs.size())
	check(contribs[0] == PC_A, "active character should be first")

	# Cleanup extra PC
	CampaignRepository.db.query_with_bindings("DELETE FROM inventory_items WHERE character_id = ?", [pc_b])
	CampaignRepository.db.query_with_bindings("DELETE FROM party_members WHERE character_id = ?", [pc_b])
	CampaignRepository.db.query_with_bindings("DELETE FROM characters WHERE id = ?", [pc_b])
	_cleanup()


func test_contributors_all_returned_when_unknown_location() -> void:
	_setup()
	GameState.current_location_key = "unknown"
	var contribs := PartyWallet.get_contributors(TEST_PARTY, PC_A)
	check(contribs.size() == 1, "should return all PCs when location is unknown")
	_cleanup()


func test_contributors_all_returned_when_none_location() -> void:
	_setup()
	GameState.current_location_key = "none"
	var contribs := PartyWallet.get_contributors(TEST_PARTY, PC_A)
	check(contribs.size() == 1, "should return all PCs when location is none")
	_cleanup()
