extends Node

## Unit tests for EquipmentCatalog (loading, querying, cost formatting).
## Run via test_runner.tscn. Uses plain assert() — no external framework.


func run_all_tests() -> void:
	test_load_count()
	test_get_known_items()
	test_has_item()
	test_category_filtering()
	test_all_categories()
	test_foodstuffs_loaded()
	test_transport_loaded()
	test_format_cost_gp_only()
	test_format_cost_sp_only()
	test_format_cost_cp_only()
	test_format_cost_mixed()
	test_format_cost_zero()
	test_search_items()
	test_load_errors_empty()
	print("EquipmentCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Load count
# ---------------------------------------------------------------------------

func test_load_count() -> void:
	var cat := EquipmentCatalog.new()
	# base (130) + transport (32) + foodstuffs (14) = 176
	var count := cat.get_item_count()
	assert(count == 176,
		"expected 176 items total, got %d" % count)
	print("  load_count: OK (%d items)" % count)


# ---------------------------------------------------------------------------
# Known items from base_equipment.json
# ---------------------------------------------------------------------------

func test_get_known_items() -> void:
	var cat := EquipmentCatalog.new()

	var sword := cat.get_item("sword")
	assert(not sword.is_empty(), "sword should be present")
	assert(sword.get("name", "") != "", "sword should have a name field")
	assert(sword.has("cost_cp"), "sword should have cost_cp field")

	var leather := cat.get_item("leather_armor")
	assert(not leather.is_empty(), "leather_armor should be present")
	assert(leather.get("item_category", "") == "armor",
		"leather_armor category should be 'armor'")

	var backpack := cat.get_item("backpack")
	assert(not backpack.is_empty(), "backpack should be present")
	assert(backpack.get("item_category", "") == "gear",
		"backpack category should be 'gear'")

	print("  get_known_items: OK")


# ---------------------------------------------------------------------------
# has_item
# ---------------------------------------------------------------------------

func test_has_item() -> void:
	var cat := EquipmentCatalog.new()
	assert(cat.has_item("sword"), "has_item('sword') should be true")
	assert(cat.has_item("backpack"), "has_item('backpack') should be true")
	assert(not cat.has_item("nonexistent_item_xyz"),
		"has_item for unknown key should be false")
	print("  has_item: OK")


# ---------------------------------------------------------------------------
# Category filtering
# ---------------------------------------------------------------------------

func test_category_filtering() -> void:
	var cat := EquipmentCatalog.new()

	var weapons := cat.get_items_by_category("weapon")
	assert(weapons.size() > 0, "weapon category should have items")
	for item in weapons:
		assert(item.get("item_category", "") == "weapon",
			"all items in 'weapon' category should have item_category=='weapon'")

	var armor_items := cat.get_items_by_category("armor")
	assert(armor_items.size() > 0, "armor category should have items")
	for item in armor_items:
		assert(item.get("item_category", "") == "armor",
			"all items in 'armor' category should have item_category=='armor'")

	var empty := cat.get_items_by_category("not_a_real_category")
	assert(empty.size() == 0, "unknown category should return empty array")

	print("  category_filtering: OK")


# ---------------------------------------------------------------------------
# All categories
# ---------------------------------------------------------------------------

func test_all_categories() -> void:
	var cat := EquipmentCatalog.new()
	var cats := cat.get_all_categories()
	assert(cats.size() > 0, "get_all_categories should return non-empty array")

	# Expected categories from base + transport + foodstuff
	for expected in ["weapon", "armor", "shield", "gear", "clothing",
			"mount", "pack_animal", "draft_animal", "vehicle",
			"tack", "barding", "livestock", "foodstuff"]:
		assert(expected in cats,
			"expected category '%s' not found in all_categories" % expected)

	# Verify sorted
	var sorted_copy := cats.duplicate()
	sorted_copy.sort()
	assert(cats == sorted_copy, "get_all_categories should return sorted array")

	print("  all_categories: OK (%d categories)" % cats.size())


# ---------------------------------------------------------------------------
# Foodstuffs loaded from provisions_services.json
# ---------------------------------------------------------------------------

func test_foodstuffs_loaded() -> void:
	var cat := EquipmentCatalog.new()

	var food := cat.get_items_by_category("foodstuff")
	assert(food.size() == 14,
		"expected 14 foodstuff items, got %d" % food.size())

	# Verify defaults were applied
	for item in food:
		assert(item.has("encumbrance_sixths"),
			"foodstuff '%s' should have encumbrance_sixths" % item.get("item_key", "?"))
		assert(item.has("is_heavy"),
			"foodstuff '%s' should have is_heavy" % item.get("item_key", "?"))
		assert(item.get("is_heavy") == false,
			"foodstuff '%s' is_heavy should be false" % item.get("item_key", "?"))

	# Check a specific known item
	var ale := cat.get_item("ale_cheap")
	assert(not ale.is_empty(), "ale_cheap should be present")
	assert(ale.get("item_category", "") == "foodstuff",
		"ale_cheap should have item_category 'foodstuff'")

	print("  foodstuffs_loaded: OK (%d items)" % food.size())


# ---------------------------------------------------------------------------
# Transport items loaded from transport.json
# ---------------------------------------------------------------------------

func test_transport_loaded() -> void:
	var cat := EquipmentCatalog.new()

	# Transport categories collectively
	var mounts := cat.get_items_by_category("mount")
	assert(mounts.size() > 0, "mount category should have items")

	var pack_animals := cat.get_items_by_category("pack_animal")
	assert(pack_animals.size() > 0, "pack_animal category should have items")

	# Check a known item
	var mule := cat.get_item("mule")
	assert(not mule.is_empty(), "mule should be present")
	assert(mule.get("item_category", "") == "pack_animal",
		"mule should be in pack_animal category")

	var camel := cat.get_item("camel")
	assert(not camel.is_empty(), "camel should be present")

	print("  transport_loaded: OK")


# ---------------------------------------------------------------------------
# format_cost — gp only
# ---------------------------------------------------------------------------

func test_format_cost_gp_only() -> void:
	assert(EquipmentCatalog.format_cost(1000) == "10gp",
		"1000cp should format as '10gp'")
	assert(EquipmentCatalog.format_cost(100) == "1gp",
		"100cp should format as '1gp'")
	assert(EquipmentCatalog.format_cost(500) == "5gp",
		"500cp should format as '5gp'")
	print("  format_cost_gp_only: OK")


# ---------------------------------------------------------------------------
# format_cost — sp only
# ---------------------------------------------------------------------------

func test_format_cost_sp_only() -> void:
	assert(EquipmentCatalog.format_cost(50) == "5sp",
		"50cp should format as '5sp'")
	assert(EquipmentCatalog.format_cost(10) == "1sp",
		"10cp should format as '1sp'")
	assert(EquipmentCatalog.format_cost(90) == "9sp",
		"90cp should format as '9sp'")
	print("  format_cost_sp_only: OK")


# ---------------------------------------------------------------------------
# format_cost — cp only
# ---------------------------------------------------------------------------

func test_format_cost_cp_only() -> void:
	assert(EquipmentCatalog.format_cost(1) == "1cp",
		"1cp should format as '1cp'")
	assert(EquipmentCatalog.format_cost(3) == "3cp",
		"3cp should format as '3cp'")
	assert(EquipmentCatalog.format_cost(9) == "9cp",
		"9cp should format as '9cp'")
	print("  format_cost_cp_only: OK")


# ---------------------------------------------------------------------------
# format_cost — mixed denominations
# ---------------------------------------------------------------------------

func test_format_cost_mixed() -> void:
	# 1550cp = 15gp 5sp 0cp
	assert(EquipmentCatalog.format_cost(1550) == "15gp 5sp",
		"1550cp should format as '15gp 5sp', got '%s'" % EquipmentCatalog.format_cost(1550))
	# 103cp = 1gp 0sp 3cp
	assert(EquipmentCatalog.format_cost(103) == "1gp 3cp",
		"103cp should format as '1gp 3cp', got '%s'" % EquipmentCatalog.format_cost(103))
	# 113cp = 1gp 1sp 3cp
	assert(EquipmentCatalog.format_cost(113) == "1gp 1sp 3cp",
		"113cp should format as '1gp 1sp 3cp', got '%s'" % EquipmentCatalog.format_cost(113))
	# 1003cp = 10gp 0sp 3cp
	assert(EquipmentCatalog.format_cost(1003) == "10gp 3cp",
		"1003cp should format as '10gp 3cp', got '%s'" % EquipmentCatalog.format_cost(1003))
	print("  format_cost_mixed: OK")


# ---------------------------------------------------------------------------
# format_cost — zero and negative
# ---------------------------------------------------------------------------

func test_format_cost_zero() -> void:
	assert(EquipmentCatalog.format_cost(0) == "0cp",
		"0cp should format as '0cp'")
	assert(EquipmentCatalog.format_cost(-5) == "0cp",
		"negative values should format as '0cp'")
	print("  format_cost_zero: OK")


# ---------------------------------------------------------------------------
# search_items — case-insensitive substring match
# ---------------------------------------------------------------------------

func test_search_items() -> void:
	var cat := EquipmentCatalog.new()

	var sword_results := cat.search_items("sword")
	assert(sword_results.size() >= 3,
		"search 'sword' should find at least 3 results (sword, two_handed_sword, short_sword)")
	for item in sword_results:
		assert((item.get("name", "") as String).to_lower().contains("sword"),
			"search result should contain 'sword' in name")

	# Case-insensitive
	var upper_results := cat.search_items("SWORD")
	assert(upper_results.size() == sword_results.size(),
		"search should be case-insensitive")

	# No results
	var no_results := cat.search_items("xyzzy_not_an_item")
	assert(no_results.size() == 0, "search for unknown string should return empty array")

	print("  search_items: OK")


# ---------------------------------------------------------------------------
# Load errors should be empty on clean load
# ---------------------------------------------------------------------------

func test_load_errors_empty() -> void:
	var cat := EquipmentCatalog.new()
	var errors := cat.get_load_errors()
	assert(errors.is_empty(),
		"load_errors should be empty after clean load, got: %s" % str(errors))
	print("  load_errors_empty: OK")
