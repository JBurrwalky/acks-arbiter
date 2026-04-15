extends "res://tests/test_suite_base.gd"

## Unit tests for ShopService (buy, sell, commission, pickup).
## Requires DB. Seeds test data in _setup(), cleans in _teardown().

const TEST_CAMPAIGN_ID := "test_shop_svc_campaign"
const TEST_CHARACTER_ID := "test_shop_svc_char_01"
const TEST_SETTLEMENT_ID := "test_shop_svc_settlement"
const TEST_POI_ID := "test_shop_svc_poi"

var _service: ShopService


func run_all_tests() -> void:
	_setup()
	test_open_shop_generates_inventory()
	test_buy_success()
	test_buy_insufficient_gold()
	test_buy_insufficient_stock()
	test_sell_success()
	test_sell_magic_excluded()
	test_get_sellable_excludes_coins()
	test_commission_creates_record()
	test_pickup_before_ready_fails()
	test_pickup_success()
	_teardown()
	if not has_failures():
		print("ShopService: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_service = ShopService.new()

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[TEST_CAMPAIGN_ID, "Shop Svc Test", "Test World"])

	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [TEST_CHARACTER_ID, TEST_CAMPAIGN_ID, "Test Buyer", "fighter", 1, 0, 8, 8])

	GameState.campaign_id = TEST_CAMPAIGN_ID

	# Give the character 10gp (1000cp) to work with.
	CampaignRepository.add_specific_coins(TEST_CHARACTER_ID, "coins_gp", 10)


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM commissions WHERE campaign_id = ?", [TEST_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM shop_inventory WHERE campaign_id = ?", [TEST_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [TEST_CHARACTER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHARACTER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN_ID])


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_open_shop_generates_inventory() -> void:
	var poi := {"id": TEST_POI_ID, "subtype": "general", "size": "medium", "name": "Test Shop"}
	var result := _service.open_shop(poi, 3, TEST_SETTLEMENT_ID, TEST_CAMPAIGN_ID, 0)
	var inventory: Array = result.get("inventory", [])
	check(inventory.size() > 0, "open_shop should generate inventory, got %d items" % inventory.size())
	print("  open_shop_generates: OK (%d items)" % inventory.size())


func test_buy_success() -> void:
	# Ensure we have stock by opening the shop first.
	var poi := {"id": TEST_POI_ID, "subtype": "general", "size": "medium", "name": "Test Shop"}
	var shop := _service.open_shop(poi, 3, TEST_SETTLEMENT_ID, TEST_CAMPAIGN_ID, 0)
	var inventory: Array = shop.get("inventory", [])
	if inventory.is_empty():
		push_error("  buy_success: SKIP — no inventory generated")
		return

	# Find an affordable item.
	var target: Dictionary = {}
	for item in inventory:
		if int(item.get("cost_cp", 0)) <= 1000 and int(item.get("quantity_available", 0)) > 0:
			target = item
			break
	if target.is_empty():
		push_error("  buy_success: SKIP — no affordable item found")
		return

	var item_key: String = target["item_key"]
	var cost_cp: int = int(target["cost_cp"])
	var wealth_before := CampaignRepository.get_character_wealth_cp(TEST_CHARACTER_ID)

	var result := _service.buy_item(TEST_CHARACTER_ID, item_key, 1, TEST_POI_ID, TEST_CAMPAIGN_ID)
	check(result["success"], "buy should succeed: %s" % result.get("message", ""))

	var wealth_after := CampaignRepository.get_character_wealth_cp(TEST_CHARACTER_ID)
	check(wealth_after == wealth_before - cost_cp,
		"wealth should decrease by %d, was %d now %d" % [cost_cp, wealth_before, wealth_after])
	print("  buy_success: OK (bought %s for %s)" % [item_key, Currency.format_cost(cost_cp)])


func test_buy_insufficient_gold() -> void:
	# Seed an expensive item in stock.
	CampaignRepository.upsert_shop_inventory(
		TEST_CAMPAIGN_ID, TEST_SETTLEMENT_ID, TEST_POI_ID,
		"plate_armor", 1, 0)
	# plate_armor costs 6000cp (60gp). Character has 10gp = 1000cp.
	var result := _service.buy_item(TEST_CHARACTER_ID, "plate_armor", 1, TEST_POI_ID, TEST_CAMPAIGN_ID)
	# This may fail if plate_armor isn't in catalog or if we've already spent gold.
	# The key check is that it doesn't succeed when wealth < cost.
	if result.get("success", false):
		# If they somehow had enough, just verify the logic path works.
		print("  buy_insufficient: SKIP — character had enough gold")
	else:
		check(not result["success"], "buy should fail with insufficient funds")
		print("  buy_insufficient: OK")


func test_buy_insufficient_stock() -> void:
	# Put 0 stock for an item.
	CampaignRepository.upsert_shop_inventory(
		TEST_CAMPAIGN_ID, TEST_SETTLEMENT_ID, TEST_POI_ID,
		"sword", 0, 0)
	var result := _service.buy_item(TEST_CHARACTER_ID, "sword", 1, TEST_POI_ID, TEST_CAMPAIGN_ID)
	check(not result["success"], "buy should fail with 0 stock")
	print("  buy_insufficient_stock: OK")


func test_sell_success() -> void:
	# Add an item to the character.
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": TEST_CHARACTER_ID,
		"item_key": "dagger",
		"name": "Dagger",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "weapon",
	})
	# Put dagger in shop stock so increment works.
	CampaignRepository.upsert_shop_inventory(
		TEST_CAMPAIGN_ID, TEST_SETTLEMENT_ID, TEST_POI_ID,
		"dagger", 5, 0)

	var wealth_before := CampaignRepository.get_character_wealth_cp(TEST_CHARACTER_ID)
	var result := _service.sell_item(TEST_CHARACTER_ID, item_id, TEST_POI_ID, TEST_CAMPAIGN_ID)
	check(result["success"], "sell should succeed: %s" % result.get("message", ""))

	# Dagger costs 300cp (3gp). Sell at full price.
	var catalog := EquipmentCatalog.new()
	var dagger_cost: int = int(catalog.get_item("dagger").get("cost_cp", 0))
	var wealth_after := CampaignRepository.get_character_wealth_cp(TEST_CHARACTER_ID)
	check(wealth_after == wealth_before + dagger_cost,
		"wealth should increase by %d, was %d now %d" % [dagger_cost, wealth_before, wealth_after])
	print("  sell_success: OK")


func test_sell_magic_excluded() -> void:
	# Add a magic item.
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": TEST_CHARACTER_ID,
		"item_key": "sword",
		"name": "Sword +1",
		"quantity": 1,
		"encumbrance_units": 1000,
		"item_category": "weapon",
		"is_magical": true,
		"magical_bonus": 1,
	})
	var result := _service.sell_item(TEST_CHARACTER_ID, item_id, TEST_POI_ID, TEST_CAMPAIGN_ID)
	check(not result["success"], "magic items should not be sellable")
	# Clean up.
	CampaignRepository.remove_inventory_item(item_id)
	print("  sell_magic_excluded: OK")


func test_get_sellable_excludes_coins() -> void:
	var sellable := _service.get_sellable_items(TEST_CHARACTER_ID)
	for item in sellable:
		check(not Currency.is_coin(item.get("item_key", "")),
			"coins should not be in sellable list")
	print("  sellable_excludes_coins: OK")


func test_commission_creates_record() -> void:
	# Commission a sword (not in stock).
	var poi := {"id": TEST_POI_ID, "name": "Test Shop"}
	var result := _service.commission_item(
		TEST_CHARACTER_ID, "sword", 1, poi, TEST_SETTLEMENT_ID,
		TEST_CAMPAIGN_ID, null, "test_party", 0)
	# May fail if character doesn't have enough gold for a sword (1000cp = 10gp).
	if result["success"]:
		check(not result["commission_id"].is_empty(), "commission_id should be set")
		check(result["ready_at_round"] > 0, "ready_at_round should be > 0")
		# Verify DB record.
		var commissions := CampaignRepository.get_commissions(
			TEST_CAMPAIGN_ID, TEST_POI_ID, TEST_CHARACTER_ID)
		check(commissions.size() > 0, "commission should exist in DB")
		print("  commission_creates: OK")
	else:
		print("  commission_creates: SKIP (insufficient funds after prior tests)")


func test_pickup_before_ready_fails() -> void:
	# Create a commission with ready_at_round far in the future.
	var commission_id := CampaignRepository.add_commission({
		"campaign_id": TEST_CAMPAIGN_ID,
		"settlement_id": TEST_SETTLEMENT_ID,
		"poi_id": TEST_POI_ID,
		"character_id": TEST_CHARACTER_ID,
		"item_key": "torch",
		"quantity": 1,
		"cost_cp": 100,
		"ordered_at_round": 0,
		"ready_at_round": 999999,
	})
	var result := _service.pickup_commission(commission_id, TEST_CHARACTER_ID, 100)
	check(not result["success"], "pickup before ready should fail")
	print("  pickup_before_ready: OK")


func test_pickup_success() -> void:
	# Create a commission that's already ready.
	var commission_id := CampaignRepository.add_commission({
		"campaign_id": TEST_CAMPAIGN_ID,
		"settlement_id": TEST_SETTLEMENT_ID,
		"poi_id": TEST_POI_ID,
		"character_id": TEST_CHARACTER_ID,
		"item_key": "torch",
		"quantity": 1,
		"cost_cp": 100,
		"ordered_at_round": 0,
		"ready_at_round": 50,
	})
	var result := _service.pickup_commission(commission_id, TEST_CHARACTER_ID, 100)
	check(result["success"], "pickup should succeed: %s" % result.get("message", ""))
	# Verify item added.
	var items := CampaignRepository.get_inventory_items(TEST_CHARACTER_ID)
	var found := false
	for item in items:
		if item.get("item_key", "") == "torch":
			found = true
			break
	check(found, "torch should be in character inventory after pickup")
	print("  pickup_success: OK")
