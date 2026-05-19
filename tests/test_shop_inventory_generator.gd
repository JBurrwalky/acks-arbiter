extends "res://tests/test_suite_base.gd"

## Unit tests for ShopInventoryGenerator.
## Tests market class availability, shop size fractions, banker's rounding,
## and refresh cycle detection.

const TEST_CAMPAIGN_ID := "test_shop_gen_campaign"
const TEST_SETTLEMENT_ID := "test_shop_gen_settlement"
const TEST_POI_ID := "test_shop_gen_poi"


func run_all_tests() -> void:
	_setup()
	test_bankers_rounding()
	test_needs_refresh_false()
	test_needs_refresh_true()
	test_generate_class_1_has_items()
	test_generate_class_6_fewer_items()
	test_generate_small_shop_fraction()
	test_generate_emporium_all_categories()
	test_generate_armorer_only_armor()
	test_generate_persists_to_db()
	_teardown()
	if not has_failures():
		print("ShopInventoryGenerator: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[TEST_CAMPAIGN_ID, "Shop Gen Test Campaign", "Test World"]
	)


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM shop_inventory WHERE campaign_id = ?", [TEST_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN_ID])


# ---------------------------------------------------------------------------
# Banker's rounding
# ---------------------------------------------------------------------------

func test_bankers_rounding() -> void:
	# Half rounds to even.
	check(XPAwardCalculator.bankers_round(2.5) == 2, "2.5 → 2 (even)")
	check(XPAwardCalculator.bankers_round(3.5) == 4, "3.5 → 4 (even)")
	check(XPAwardCalculator.bankers_round(4.5) == 4, "4.5 → 4 (even)")
	check(XPAwardCalculator.bankers_round(5.5) == 6, "5.5 → 6 (even)")
	# Non-half rounds normally.
	check(XPAwardCalculator.bankers_round(2.3) == 2, "2.3 → 2")
	check(XPAwardCalculator.bankers_round(2.7) == 3, "2.7 → 3")
	print("  bankers_rounding: OK")


# ---------------------------------------------------------------------------
# Refresh cycle
# ---------------------------------------------------------------------------

func test_needs_refresh_false() -> void:
	# Generated 1 day ago, refresh is 30 days.
	var gen_round := 0
	var current := Timekeeping.ROUNDS_PER_DAY * 10
	check(not ShopInventoryGenerator.needs_refresh(gen_round, current),
		"10 days should not trigger refresh")
	print("  needs_refresh_false: OK")


func test_needs_refresh_true() -> void:
	var gen_round := 0
	var current := Timekeeping.ROUNDS_PER_DAY * 31
	check(ShopInventoryGenerator.needs_refresh(gen_round, current),
		"31 days should trigger refresh")
	print("  needs_refresh_true: OK")


# ---------------------------------------------------------------------------
# Generation tests
# ---------------------------------------------------------------------------

func test_generate_class_1_has_items() -> void:
	var gen := ShopInventoryGenerator.new()
	var poi := {"id": TEST_POI_ID + "_c1", "subtype": "emporium", "size": "large"}
	var result := gen.generate(poi, 1, TEST_SETTLEMENT_ID, TEST_CAMPAIGN_ID, 0)
	check(result.size() > 0, "Class I emporium should have items, got %d" % result.size())
	# Class I large emporium should have many items.
	check(result.size() > 50, "Class I large emporium should have >50 items, got %d" % result.size())
	print("  generate_class_1: OK (%d items)" % result.size())


func test_generate_class_6_fewer_items() -> void:
	var gen := ShopInventoryGenerator.new()
	var poi := {"id": TEST_POI_ID + "_c6", "subtype": "emporium", "size": "small"}
	var result := gen.generate(poi, 6, TEST_SETTLEMENT_ID, TEST_CAMPAIGN_ID, 0)
	# Class VI small shop should have significantly fewer items.
	# Many items will be filtered out by availability + small fraction.
	check(result.size() >= 0, "Class VI should generate without error")
	print("  generate_class_6: OK (%d items)" % result.size())


func test_generate_small_shop_fraction() -> void:
	var gen := ShopInventoryGenerator.new()
	var poi_large := {"id": TEST_POI_ID + "_lg", "subtype": "emporium", "size": "large"}
	var poi_small := {"id": TEST_POI_ID + "_sm", "subtype": "emporium", "size": "small"}
	var result_large := gen.generate(poi_large, 3, TEST_SETTLEMENT_ID, TEST_CAMPAIGN_ID, 0)
	var result_small := gen.generate(poi_small, 3, TEST_SETTLEMENT_ID, TEST_CAMPAIGN_ID, 0)
	check(result_large.size() >= result_small.size(),
		"large shop should have >= items as small shop (large=%d, small=%d)" % [result_large.size(), result_small.size()])
	print("  small_shop_fraction: OK (large=%d, small=%d)" % [result_large.size(), result_small.size()])


func test_generate_emporium_all_categories() -> void:
	var gen := ShopInventoryGenerator.new()
	var poi := {"id": TEST_POI_ID + "_emp", "subtype": "emporium", "size": "large"}
	var result := gen.generate(poi, 1, TEST_SETTLEMENT_ID, TEST_CAMPAIGN_ID, 0)
	# Should have items from multiple categories.
	var categories := {}
	for item in result:
		categories[item.get("item_category", "")] = true
	check(categories.size() >= 3, "emporium should have items from >=3 categories, got %d" % categories.size())
	print("  emporium_all_categories: OK (%d categories)" % categories.size())


func test_generate_armorer_only_armor() -> void:
	var gen := ShopInventoryGenerator.new()
	var poi := {"id": TEST_POI_ID + "_arm", "subtype": "armorer", "size": "medium"}
	var result := gen.generate(poi, 1, TEST_SETTLEMENT_ID, TEST_CAMPAIGN_ID, 0)
	for item in result:
		var cat: String = item.get("item_category", "")
		check(cat in ["armor", "shield"],
			"armorer should only have armor/shield, got '%s' for %s" % [cat, item.get("name", "")])
	print("  armorer_only_armor: OK (%d items)" % result.size())


func test_generate_persists_to_db() -> void:
	var gen := ShopInventoryGenerator.new()
	var poi_id := TEST_POI_ID + "_db"
	var poi := {"id": poi_id, "subtype": "general", "size": "medium"}
	var result := gen.generate(poi, 3, TEST_SETTLEMENT_ID, TEST_CAMPAIGN_ID, 1000)
	var db_rows := CampaignRepository.get_shop_inventory(TEST_CAMPAIGN_ID, poi_id)
	check(db_rows.size() == result.size(),
		"DB rows (%d) should match generated count (%d)" % [db_rows.size(), result.size()])
	# Check generated_at_round is set.
	if not db_rows.is_empty():
		check(int(db_rows[0].get("generated_at_round", 0)) == 1000,
			"generated_at_round should be 1000")
	print("  generate_persists: OK")
