extends "res://tests/test_suite_base.gd"

## Tests for OverrideManager.
##
## Covers: dice queue lifecycle, character stat mutations, inventory gold adjustment,
## snapshot save/restore round-trip.
##
## These tests require the DB to be initialised (CampaignRepository._ready() must
## have run). They create temporary campaign/character records with known IDs and
## clean up after themselves.

const TEST_CAMPAIGN_ID := "test_override_campaign"
const TEST_CHARACTER_ID := "test_override_char_01"

var _mgr: OverrideManager


func run_all_tests() -> void:
	_setup()
	test_dice_queue_and_consume()
	test_dice_clear_single()
	test_dice_clear_all()
	test_character_stat_override()
	test_character_stat_disallowed_field()
	test_character_xp_add()
	test_character_xp_subtract_floors_at_zero()
	test_character_condition_apply_remove()
	test_character_status_toggle()
	test_adjust_gold_add()
	test_adjust_gold_subtract()
	test_adjust_gold_floors_at_zero()
	test_snapshot_save_restore()
	test_override_create_wilderness_loose_cache()
	test_override_create_wilderness_hidden_cache()
	test_override_create_dungeon_loose_cache()
	test_override_create_settlement_cache()
	test_override_create_cache_logs_audit_entry()
	test_override_create_cache_returns_nonempty_id()
	_teardown()
	if not has_failures():
		print("OverrideManager: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_mgr = OverrideManager.new()
	add_child(_mgr)

	# Seed test campaign so logging doesn't no-op
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[TEST_CAMPAIGN_ID, "Override Test Campaign", "Test World"]
	)
	# Seed test character
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [TEST_CHARACTER_ID, TEST_CAMPAIGN_ID, "Test Hero", "fighter", 1, 0, 8, 8])

	# Point GameState at the test campaign so _log_override works
	GameState.campaign_id = TEST_CAMPAIGN_ID


func _teardown() -> void:
	# Remove test data (leaf tables first)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [TEST_CHARACTER_ID]
	)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_conditions WHERE character_id = ?", [TEST_CHARACTER_ID]
	)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM override_log WHERE campaign_id = ?", [TEST_CAMPAIGN_ID]
	)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM game_snapshots WHERE campaign_id = ?", [TEST_CAMPAIGN_ID]
	)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHARACTER_ID]
	)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN_ID]
	)
	GameState.campaign_id = ""
	GameState.dice_overrides.clear()
	_mgr.queue_free()


# ---------------------------------------------------------------------------
# Dice queue
# ---------------------------------------------------------------------------

func test_dice_queue_and_consume() -> void:
	_mgr.queue_dice_override("attack_throw", 20)
	check(GameState.dice_overrides.has("attack_throw"), "queued override not in GameState")
	check(GameState.dice_overrides["attack_throw"] == 20, "wrong forced value")
	var consumed := _mgr.consume_dice_override("attack_throw")
	check(consumed == 20, "consume returned wrong value: %d" % consumed)
	check(not GameState.dice_overrides.has("attack_throw"), "override not removed after consume")


func test_dice_clear_single() -> void:
	_mgr.queue_dice_override("morale_check", 2)
	_mgr.queue_dice_override("initiative", 6)
	_mgr.clear_dice_override("morale_check")
	check(not GameState.dice_overrides.has("morale_check"), "cleared override still present")
	check(GameState.dice_overrides.has("initiative"), "uncleared override was removed")
	_mgr.clear_dice_override("initiative")


func test_dice_clear_all() -> void:
	_mgr.queue_dice_override("encounter_check", 1)
	_mgr.queue_dice_override("reaction_roll", 12)
	_mgr.clear_all_dice_overrides()
	check(GameState.dice_overrides.is_empty(), "dice_overrides not empty after clear_all")


func test_dice_no_override_returns_minus_one() -> void:
	var result := _mgr.consume_dice_override("saving_throw_poison")
	check(result == -1, "expected -1 for missing override, got %d" % result)


# ---------------------------------------------------------------------------
# Character stat
# ---------------------------------------------------------------------------

func test_character_stat_override() -> void:
	var ok := _mgr.override_character_stat(TEST_CHARACTER_ID, "strength", 18)
	check(ok, "override_character_stat returned false")
	var char_data := CampaignRepository.get_character(TEST_CHARACTER_ID)
	check(char_data.get("strength", 0) == 18, "strength not updated in DB: %d" % char_data.get("strength", 0))


func test_character_stat_disallowed_field() -> void:
	var ok := _mgr.override_character_stat(TEST_CHARACTER_ID, "campaign_id", "evil_injection")
	check(not ok, "disallowed field should return false")
	var char_data := CampaignRepository.get_character(TEST_CHARACTER_ID)
	check(char_data.get("campaign_id", "") == TEST_CHARACTER_ID or \
		   char_data.get("campaign_id", "") == TEST_CAMPAIGN_ID,
		"campaign_id should not have changed")


func test_character_xp_add() -> void:
	# Reset XP to known state
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET xp = 0 WHERE id = ?", [TEST_CHARACTER_ID]
	)
	_mgr.override_character_xp(TEST_CHARACTER_ID, 500)
	var char_data := CampaignRepository.get_character(TEST_CHARACTER_ID)
	check(char_data.get("xp", -1) == 500, "XP should be 500, got %d" % char_data.get("xp", -1))


func test_character_xp_subtract_floors_at_zero() -> void:
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET xp = 100 WHERE id = ?", [TEST_CHARACTER_ID]
	)
	_mgr.override_character_xp(TEST_CHARACTER_ID, -500)
	var char_data := CampaignRepository.get_character(TEST_CHARACTER_ID)
	check(char_data.get("xp", -1) == 0, "XP should floor at 0, got %d" % char_data.get("xp", -1))


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func test_character_condition_apply_remove() -> void:
	var ok_apply := _mgr.override_character_condition(TEST_CHARACTER_ID, "paralysed", true)
	check(ok_apply, "apply condition returned false")
	var conditions := CampaignRepository.get_conditions(TEST_CHARACTER_ID)
	var found := false
	for c in conditions:
		if c.get("condition_name", "") == "paralysed":
			found = true
	check(found, "condition 'paralysed' not found in DB after apply")

	var ok_remove := _mgr.override_character_condition(TEST_CHARACTER_ID, "paralysed", false)
	check(ok_remove, "remove condition returned false")
	conditions = CampaignRepository.get_conditions(TEST_CHARACTER_ID)
	var still_found := false
	for c in conditions:
		if c.get("condition_name", "") == "paralysed":
			still_found = true
	check(not still_found, "condition 'paralysed' still in DB after remove")


# ---------------------------------------------------------------------------
# Character status
# ---------------------------------------------------------------------------

func test_character_status_toggle() -> void:
	var ok := _mgr.override_character_status(TEST_CHARACTER_ID, true)
	check(ok, "override_character_status returned false")
	var char_data := CampaignRepository.get_character(TEST_CHARACTER_ID)
	check(char_data.get("is_dead", 0) == 1, "is_dead should be 1")
	check(char_data.get("is_active", 1) == 0, "is_active should be 0 when dead")

	_mgr.override_character_status(TEST_CHARACTER_ID, false)
	char_data = CampaignRepository.get_character(TEST_CHARACTER_ID)
	check(char_data.get("is_dead", 1) == 0, "is_dead should be 0 after revive")
	check(char_data.get("is_active", 0) == 1, "is_active should be 1 after revive")


# ---------------------------------------------------------------------------
# Inventory / gold
# ---------------------------------------------------------------------------

func test_adjust_gold_add() -> void:
	# Ensure no coins_gp item exists (plural prefix matches Currency.DENOMINATIONS)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ? AND item_key = 'coins_gp'",
		[TEST_CHARACTER_ID]
	)
	_mgr.override_adjust_gold(TEST_CHARACTER_ID, 150)
	var items := CampaignRepository.get_inventory_items(TEST_CHARACTER_ID)
	var found_gold := false
	for item in items:
		if item.get("item_key", "") == "coins_gp":
			found_gold = true
			check(item.get("quantity", 0) == 150, "gold qty should be 150, got %d" % item.get("quantity", 0))
	check(found_gold, "coins_gp item not created")


func test_adjust_gold_subtract() -> void:
	# Ensure 200 GP exists
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ? AND item_key = 'coins_gp'",
		[TEST_CHARACTER_ID]
	)
	_mgr.override_adjust_gold(TEST_CHARACTER_ID, 200)
	_mgr.override_adjust_gold(TEST_CHARACTER_ID, -50)
	var items := CampaignRepository.get_inventory_items(TEST_CHARACTER_ID)
	for item in items:
		if item.get("item_key", "") == "coins_gp":
			check(item.get("quantity", 0) == 150, "gold after subtract should be 150, got %d" % item.get("quantity", 0))


func test_adjust_gold_floors_at_zero() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ? AND item_key = 'coins_gp'",
		[TEST_CHARACTER_ID]
	)
	_mgr.override_adjust_gold(TEST_CHARACTER_ID, 10)
	_mgr.override_adjust_gold(TEST_CHARACTER_ID, -9999)
	var items := CampaignRepository.get_inventory_items(TEST_CHARACTER_ID)
	for item in items:
		if item.get("item_key", "") == "coins_gp":
			check(item.get("quantity", 0) == 0, "gold should floor at 0, got %d" % item.get("quantity", 0))


# ---------------------------------------------------------------------------
# Snapshot round-trip
# ---------------------------------------------------------------------------

func test_snapshot_save_restore() -> void:
	# Set a known state
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET strength = 15, xp = 999 WHERE id = ?",
		[TEST_CHARACTER_ID]
	)
	var snap_id := _mgr.save_session_snapshot("pre-fight checkpoint")
	check(not snap_id.is_empty(), "snapshot id should not be empty")

	# Mutate state
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET strength = 3, xp = 0 WHERE id = ?",
		[TEST_CHARACTER_ID]
	)
	var mutated := CampaignRepository.get_character(TEST_CHARACTER_ID)
	check(mutated.get("strength", -1) == 3, "pre-restore: strength should be 3")

	# Restore
	var ok := _mgr.restore_session_snapshot(snap_id)
	check(ok, "restore_session_snapshot returned false")

	var restored := CampaignRepository.get_character(TEST_CHARACTER_ID)
	check(restored.get("strength", -1) == 15, "restored strength should be 15, got %d" % restored.get("strength", -1))
	check(restored.get("xp", -1) == 999, "restored xp should be 999, got %d" % restored.get("xp", -1))


# ---------------------------------------------------------------------------
# Cache overrides
# ---------------------------------------------------------------------------

func test_override_create_wilderness_loose_cache() -> void:
	var cache_id := _mgr.override_create_wilderness_loose_cache(5, 7)
	check(not cache_id.is_empty(), "wilderness loose cache_id should not be empty")
	var cache := CampaignRepository.get_location_cache(cache_id)
	check(not cache.is_empty(), "cache should exist in DB")
	check(cache.get("location_key", "") == "hex:5,7", "location_key should be hex:5,7, got %s" % cache.get("location_key", ""))
	check(cache.get("cache_variant", "") == "loose", "variant should be loose, got %s" % cache.get("cache_variant", ""))
	check(cache.get("is_persistent", -1) == 0, "should not be persistent")
	CampaignRepository.delete_location_cache(cache_id)


func test_override_create_wilderness_hidden_cache() -> void:
	var cache_id := _mgr.override_create_wilderness_hidden_cache(3, 4)
	check(not cache_id.is_empty(), "wilderness hidden cache_id should not be empty")
	var cache := CampaignRepository.get_location_cache(cache_id)
	check(not cache.is_empty(), "cache should exist in DB")
	check(cache.get("location_key", "") == "hex:3,4", "location_key should be hex:3,4, got %s" % cache.get("location_key", ""))
	check(cache.get("cache_variant", "") == "hidden_wilderness", "variant should be hidden_wilderness, got %s" % cache.get("cache_variant", ""))
	check(cache.get("is_persistent", -1) == 1, "should be persistent")
	check(cache.get("raid_monthly_modifier", -1) == 0, "raid modifier should start at 0")
	CampaignRepository.delete_location_cache(cache_id)


func test_override_create_dungeon_loose_cache() -> void:
	var cache_id := _mgr.override_create_dungeon_loose_cache("test_dungeon", 2, 3)
	check(not cache_id.is_empty(), "dungeon loose cache_id should not be empty")
	var cache := CampaignRepository.get_location_cache(cache_id)
	check(not cache.is_empty(), "cache should exist in DB")
	check(cache.get("location_type", "") == "dungeon_cell", "location_type should be dungeon_cell")
	check(cache.get("location_key", "") == "dungeon:test_dungeon:cell:2,3",
		"location_key mismatch: %s" % cache.get("location_key", ""))
	check(cache.get("cache_variant", "") == "loose", "variant should be loose")
	check(cache.get("decay_check_day", 0) > 0, "decay_check_day should be set")
	CampaignRepository.delete_location_cache(cache_id)


func test_override_create_settlement_cache() -> void:
	var cache_id := _mgr.override_create_settlement_cache("test_settlement", "tavern_01")
	check(not cache_id.is_empty(), "settlement cache_id should not be empty")
	var cache := CampaignRepository.get_location_cache(cache_id)
	check(not cache.is_empty(), "cache should exist in DB")
	check(cache.get("location_type", "") == "settlement_node", "location_type should be settlement_node")
	check(cache.get("location_key", "") == "settlement:test_settlement:poi:tavern_01",
		"location_key mismatch: %s" % cache.get("location_key", ""))
	check(cache.get("decay_check_day", 0) > 0, "decay_check_day should be set")
	CampaignRepository.delete_location_cache(cache_id)


func test_override_create_cache_logs_audit_entry() -> void:
	# Clear existing override_log entries for this campaign
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM override_log WHERE campaign_id = ? AND override_type LIKE 'cache_create_%'",
		[TEST_CAMPAIGN_ID]
	)
	var cache_id := _mgr.override_create_wilderness_loose_cache(10, 20)
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM override_log WHERE campaign_id = ? AND override_type = 'cache_create_wilderness_loose'",
		[TEST_CAMPAIGN_ID]
	)
	check(not CampaignRepository.db.query_result.is_empty(),
		"override_log should have an entry for cache creation")
	var log_row: Dictionary = CampaignRepository.db.query_result[0]
	check(log_row.get("target_id", "") == cache_id,
		"log target_id should match cache_id")
	CampaignRepository.delete_location_cache(cache_id)


func test_override_create_cache_returns_nonempty_id() -> void:
	var ids: Array[String] = []
	ids.append(_mgr.override_create_wilderness_loose_cache(0, 0))
	ids.append(_mgr.override_create_wilderness_hidden_cache(1, 1))
	ids.append(_mgr.override_create_dungeon_loose_cache("d1", 0, 0))
	ids.append(_mgr.override_create_settlement_cache("s1", "p1"))
	for id in ids:
		check(not id.is_empty(), "all cache creation methods should return non-empty IDs")
	# Cleanup
	for id in ids:
		CampaignRepository.delete_location_cache(id)
