extends "res://tests/test_suite_base.gd"

## Unit tests for EquipmentCatalog (loading, querying, cost formatting).
## Run via test_runner.tscn. Uses plain check() — no external framework.


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
	test_container_identification()
	test_container_capacity()
	if not has_failures():
		print("EquipmentCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Load count
# ---------------------------------------------------------------------------

func test_load_count() -> void:
	var cat := EquipmentCatalog.new()
	# base (130) + transport (32) + foodstuffs (14) = 176
	var count := cat.get_item_count()
	check(count == 176,
		"expected 176 items total, got %d" % count)
	print("  load_count: OK (%d items)" % count)


# ---------------------------------------------------------------------------
# Known items from base_equipment.json
# ---------------------------------------------------------------------------

func test_get_known_items() -> void:
	var cat := EquipmentCatalog.new()

	var sword := cat.get_item("sword")
	check(not sword.is_empty(), "sword should be present")
	check(sword.get("name", "") != "", "sword should have a name field")
	check(sword.has("cost_cp"), "sword should have cost_cp field")

	var leather := cat.get_item("leather_armor")
	check(not leather.is_empty(), "leather_armor should be present")
	check(leather.get("item_category", "") == "armor",
		"leather_armor category should be 'armor'")

	var backpack := cat.get_item("backpack")
	check(not backpack.is_empty(), "backpack should be present")
	check(backpack.get("item_category", "") == "gear",
		"backpack category should be 'gear'")

	print("  get_known_items: OK")


# ---------------------------------------------------------------------------
# has_item
# ---------------------------------------------------------------------------

func test_has_item() -> void:
	var cat := EquipmentCatalog.new()
	check(cat.has_item("sword"), "has_item('sword') should be true")
	check(cat.has_item("backpack"), "has_item('backpack') should be true")
	check(not cat.has_item("nonexistent_item_xyz"),
		"has_item for unknown key should be false")
	print("  has_item: OK")


# ---------------------------------------------------------------------------
# Category filtering
# ---------------------------------------------------------------------------

func test_category_filtering() -> void:
	var cat := EquipmentCatalog.new()

	var weapons := cat.get_items_by_category("weapon")
	check(weapons.size() > 0, "weapon category should have items")
	for item in weapons:
		check(item.get("item_category", "") == "weapon",
			"all items in 'weapon' category should have item_category=='weapon'")

	var armor_items := cat.get_items_by_category("armor")
	check(armor_items.size() > 0, "armor category should have items")
	for item in armor_items:
		check(item.get("item_category", "") == "armor",
			"all items in 'armor' category should have item_category=='armor'")

	var empty := cat.get_items_by_category("not_a_real_category")
	check(empty.size() == 0, "unknown category should return empty array")

	print("  category_filtering: OK")


# ---------------------------------------------------------------------------
# All categories
# ---------------------------------------------------------------------------

func test_all_categories() -> void:
	var cat := EquipmentCatalog.new()
	var cats := cat.get_all_categories()
	check(cats.size() > 0, "get_all_categories should return non-empty array")

	# Expected categories from base + transport + foodstuff
	for expected in ["weapon", "armor", "shield", "gear", "clothing",
			"mount", "pack_animal", "draft_animal", "vehicle",
			"tack", "barding", "livestock", "foodstuff"]:
		check(expected in cats,
			"expected category '%s' not found in all_categories" % expected)

	# Verify sorted
	var sorted_copy := cats.duplicate()
	sorted_copy.sort()
	check(cats == sorted_copy, "get_all_categories should return sorted array")

	print("  all_categories: OK (%d categories)" % cats.size())


# ---------------------------------------------------------------------------
# Foodstuffs loaded from provisions_services.json
# ---------------------------------------------------------------------------

func test_foodstuffs_loaded() -> void:
	var cat := EquipmentCatalog.new()

	var food := cat.get_items_by_category("foodstuff")
	check(food.size() == 14,
		"expected 14 foodstuff items, got %d" % food.size())

	# Verify defaults were applied
	for item in food:
		check(item.has("encumbrance_units"),
			"foodstuff '%s' should have encumbrance_units" % item.get("item_key", "?"))
		check(item.has("is_heavy"),
			"foodstuff '%s' should have is_heavy" % item.get("item_key", "?"))
		check(item.get("is_heavy") == false,
			"foodstuff '%s' is_heavy should be false" % item.get("item_key", "?"))

	# Check a specific known item
	var ale := cat.get_item("ale_cheap")
	check(not ale.is_empty(), "ale_cheap should be present")
	check(ale.get("item_category", "") == "foodstuff",
		"ale_cheap should have item_category 'foodstuff'")

	print("  foodstuffs_loaded: OK (%d items)" % food.size())


# ---------------------------------------------------------------------------
# Transport items loaded from transport.json
# ---------------------------------------------------------------------------

func test_transport_loaded() -> void:
	var cat := EquipmentCatalog.new()

	# Transport categories collectively
	var mounts := cat.get_items_by_category("mount")
	check(mounts.size() > 0, "mount category should have items")

	var pack_animals := cat.get_items_by_category("pack_animal")
	check(pack_animals.size() > 0, "pack_animal category should have items")

	# Check a known item
	var mule := cat.get_item("mule")
	check(not mule.is_empty(), "mule should be present")
	check(mule.get("item_category", "") == "pack_animal",
		"mule should be in pack_animal category")

	var camel := cat.get_item("camel")
	check(not camel.is_empty(), "camel should be present")

	print("  transport_loaded: OK")


# ---------------------------------------------------------------------------
# format_cost — gp only
# ---------------------------------------------------------------------------

func test_format_cost_gp_only() -> void:
	check(EquipmentCatalog.format_cost(1000) == "10gp",
		"1000cp should format as '10gp'")
	check(EquipmentCatalog.format_cost(100) == "1gp",
		"100cp should format as '1gp'")
	check(EquipmentCatalog.format_cost(500) == "5gp",
		"500cp should format as '5gp'")
	print("  format_cost_gp_only: OK")


# ---------------------------------------------------------------------------
# format_cost — sp only
# ---------------------------------------------------------------------------

func test_format_cost_sp_only() -> void:
	check(EquipmentCatalog.format_cost(50) == "5sp",
		"50cp should format as '5sp'")
	check(EquipmentCatalog.format_cost(10) == "1sp",
		"10cp should format as '1sp'")
	check(EquipmentCatalog.format_cost(90) == "9sp",
		"90cp should format as '9sp'")
	print("  format_cost_sp_only: OK")


# ---------------------------------------------------------------------------
# format_cost — cp only
# ---------------------------------------------------------------------------

func test_format_cost_cp_only() -> void:
	check(EquipmentCatalog.format_cost(1) == "1cp",
		"1cp should format as '1cp'")
	check(EquipmentCatalog.format_cost(3) == "3cp",
		"3cp should format as '3cp'")
	check(EquipmentCatalog.format_cost(9) == "9cp",
		"9cp should format as '9cp'")
	print("  format_cost_cp_only: OK")


# ---------------------------------------------------------------------------
# format_cost — mixed denominations
# ---------------------------------------------------------------------------

func test_format_cost_mixed() -> void:
	# 1550cp = 15gp 5sp 0cp
	check(EquipmentCatalog.format_cost(1550) == "15gp 5sp",
		"1550cp should format as '15gp 5sp', got '%s'" % EquipmentCatalog.format_cost(1550))
	# 103cp = 1gp 0sp 3cp
	check(EquipmentCatalog.format_cost(103) == "1gp 3cp",
		"103cp should format as '1gp 3cp', got '%s'" % EquipmentCatalog.format_cost(103))
	# 113cp = 1gp 1sp 3cp
	check(EquipmentCatalog.format_cost(113) == "1gp 1sp 3cp",
		"113cp should format as '1gp 1sp 3cp', got '%s'" % EquipmentCatalog.format_cost(113))
	# 1003cp = 10gp 0sp 3cp
	check(EquipmentCatalog.format_cost(1003) == "10gp 3cp",
		"1003cp should format as '10gp 3cp', got '%s'" % EquipmentCatalog.format_cost(1003))
	print("  format_cost_mixed: OK")


# ---------------------------------------------------------------------------
# format_cost — zero and negative
# ---------------------------------------------------------------------------

func test_format_cost_zero() -> void:
	check(EquipmentCatalog.format_cost(0) == "0cp",
		"0cp should format as '0cp'")
	check(EquipmentCatalog.format_cost(-5) == "0cp",
		"negative values should format as '0cp'")
	print("  format_cost_zero: OK")


# ---------------------------------------------------------------------------
# search_items — case-insensitive substring match
# ---------------------------------------------------------------------------

func test_search_items() -> void:
	var cat := EquipmentCatalog.new()

	var sword_results := cat.search_items("sword")
	check(sword_results.size() >= 3,
		"search 'sword' should find at least 3 results (sword, two_handed_sword, short_sword)")
	for item in sword_results:
		check((item.get("name", "") as String).to_lower().contains("sword"),
			"search result should contain 'sword' in name")

	# Case-insensitive
	var upper_results := cat.search_items("SWORD")
	check(upper_results.size() == sword_results.size(),
		"search should be case-insensitive")

	# No results
	var no_results := cat.search_items("xyzzy_not_an_item")
	check(no_results.size() == 0, "search for unknown string should return empty array")

	print("  search_items: OK")


# ---------------------------------------------------------------------------
# Load errors should be empty on clean load
# ---------------------------------------------------------------------------

func test_load_errors_empty() -> void:
	var cat := EquipmentCatalog.new()
	var errors := cat.get_load_errors()
	check(errors.is_empty(),
		"load_errors should be empty after clean load, got: %s" % str(errors))
	print("  load_errors_empty: OK")


# ---------------------------------------------------------------------------
# Container identification
# ---------------------------------------------------------------------------

func test_container_identification() -> void:
	var cat := EquipmentCatalog.new()

	check(cat.is_container("backpack"),
		"backpack should be a container")
	check(cat.is_container("sack_large"),
		"sack_large should be a container")
	check(cat.is_container("sack_small"),
		"sack_small should be a container")
	check(cat.is_container("pouch"),
		"pouch should be a container")
	check(cat.is_container("chest_ironbound"),
		"chest_ironbound should be a container")
	check(cat.is_container("saddlebags"),
		"saddlebags should be a container")

	# Must NOT be containers
	check(not cat.is_container("spell_component_pouch"),
		"spell_component_pouch should NOT be a container")
	check(not cat.is_container("sword"),
		"sword should NOT be a container")
	check(not cat.is_container("leather_armor"),
		"leather_armor should NOT be a container")

	print("  container_identification: OK")


# ---------------------------------------------------------------------------
# Container capacity
# ---------------------------------------------------------------------------

func test_container_capacity() -> void:
	var cat := EquipmentCatalog.new()

	check(cat.get_container_capacity_units("backpack") == 4000,
		"backpack capacity should be 4000 units (4 stone), got %d" % cat.get_container_capacity_units("backpack"))
	check(cat.get_container_capacity_units("sack_large") == 6000,
		"sack_large capacity should be 6000 units, got %d" % cat.get_container_capacity_units("sack_large"))
	check(cat.get_container_capacity_units("sack_small") == 2000,
		"sack_small capacity should be 2000 units, got %d" % cat.get_container_capacity_units("sack_small"))
	check(cat.get_container_capacity_units("pouch") == 500,
		"pouch capacity should be 500 units (0.5 stone), got %d" % cat.get_container_capacity_units("pouch"))
	check(cat.get_container_capacity_units("chest_ironbound") == 20000,
		"chest_ironbound capacity should be 20000 units (20 stone), got %d" % cat.get_container_capacity_units("chest_ironbound"))
	check(cat.get_container_capacity_units("saddlebags") == 3000,
		"saddlebags capacity should be 3000 units (3 stone), got %d" % cat.get_container_capacity_units("saddlebags"))

	# Non-containers should return 0
	check(cat.get_container_capacity_units("sword") == 0,
		"sword container capacity should be 0")
	check(cat.get_container_capacity_units("spell_component_pouch") == 0,
		"spell_component_pouch container capacity should be 0")

	print("  container_capacity: OK")
