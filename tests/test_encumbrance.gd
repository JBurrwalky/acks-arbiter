extends "res://tests/test_suite_base.gd"

## Unit tests for EncumbranceCalculator.
## Run via test_runner.tscn. Uses plain check() — no external framework.
##
## ACKS movement table (encumbrance_units: 1 unit = 1/1000 stone):
##   <= 5 stone (<=5000 units): 120'/turn
##   <= 7 stone (<=7000 units): 90'/turn
##   <= 10 stone (<=10000 units): 60'/turn
##   <= 20 stone (<=20000 units): 30'/turn
##   > 20 stone (>20000 units): overloaded


func run_all_tests() -> void:
	test_empty_inventory()
	test_light_load()
	test_medium_load()
	test_heavy_load()
	test_max_load()
	test_overloaded()
	test_magical_armor_reduction()
	test_movement_tier_boundaries()
	test_coin_encumbrance()
	# Clothing-vs-armor coexistence (gdd-character-tab.md §3.4.6).
	test_worn_clothing_is_weightless()
	test_carried_clothing_keeps_weight()
	test_worn_armor_keeps_full_weight()
	test_clothing_and_armor_coexist()
	test_worn_ornament_and_ring_weightless()
	# Container-as-sub-carrier (Jedidiah refactor 2026-05-31).
	test_mundane_container_aggregates_own_weight_plus_contents()
	test_empty_container_just_own_weight()
	test_extradimensional_container_contents_weightless()
	test_extradimensional_with_overweight_contents()
	test_nested_mundane_containers_recurse_correctly()
	test_nested_extradimensional_in_mundane()
	test_flat_inventory_no_containers_unchanged_behavior()
	if not has_failures():
		print("EncumbranceCalculator: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_item(item_name: String, units: int, category: String = "gear",
		magical: bool = false, mag_bonus: int = 0) -> InventoryItem:
	var item := InventoryItem.new()
	item.name = item_name
	item.encumbrance_units = units
	item.item_category = category
	item.is_magical = magical
	item.magical_bonus = mag_bonus
	return item


# ---------------------------------------------------------------------------
# Empty inventory
# ---------------------------------------------------------------------------

func test_empty_inventory() -> void:
	var result := EncumbranceCalculator.calculate_encumbrance([])
	check(int(result.total_units) == 0,
		"empty inventory should have 0 units")
	check(int(result.exploration_speed) == 120,
		"empty inventory exploration should be 120'/turn")
	check(result.is_overloaded == false,
		"empty inventory should not be overloaded")
	print("  empty_inventory: OK")


# ---------------------------------------------------------------------------
# Light load (<=5 stone = <=5000 units) -> 120'/turn
# ---------------------------------------------------------------------------

func test_light_load() -> void:
	# Sword (1000 units) + dagger (167 units) = 1167 units -> light load
	var items := [
		_make_item("Sword", 1000, "weapon"),
		_make_item("Dagger", 167, "weapon"),
	]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	check(int(result.total_units) == 1167,
		"sword + dagger should be 1167 units, got %d" % int(result.total_units))
	check(int(result.exploration_speed) == 120,
		"1167 units should give 120'/turn exploration")
	print("  light_load: OK")


# ---------------------------------------------------------------------------
# Medium load (>5 stone, <=7 stone = 5001-7000 units) -> 90'/turn
# ---------------------------------------------------------------------------

func test_medium_load() -> void:
	# 5833 units (~5.83 stone) -> 90'/turn
	var items := [_make_item("Heavy gear", 5833)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	check(int(result.total_units) == 5833,
		"should be 5833 units")
	check(int(result.exploration_speed) == 90,
		"5833 units should give 90'/turn exploration, got %d" % int(result.exploration_speed))
	print("  medium_load: OK")


# ---------------------------------------------------------------------------
# Heavy load (>7 stone, <=10 stone = 7001-10000 units) -> 60'/turn
# ---------------------------------------------------------------------------

func test_heavy_load() -> void:
	# 8333 units (~8.33 stone) -> 60'/turn
	var items := [_make_item("Heavy pack", 8333)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	check(int(result.total_units) == 8333,
		"should be 8333 units")
	check(int(result.exploration_speed) == 60,
		"8333 units should give 60'/turn exploration, got %d" % int(result.exploration_speed))
	print("  heavy_load: OK")


# ---------------------------------------------------------------------------
# Max load (>10 stone, <=20 stone = 10001-20000 units) -> 30'/turn
# ---------------------------------------------------------------------------

func test_max_load() -> void:
	# 16667 units (~16.67 stone) -> 30'/turn, not overloaded
	var items := [_make_item("Very heavy pack", 16667)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	check(int(result.total_units) == 16667,
		"should be 16667 units")
	check(int(result.exploration_speed) == 30,
		"16667 units should give 30'/turn exploration, got %d" % int(result.exploration_speed))
	check(result.is_overloaded == false,
		"16667 units (16.7 stone) should NOT be overloaded")
	print("  max_load: OK")


# ---------------------------------------------------------------------------
# Overloaded (>20 stone = >20000 units)
# ---------------------------------------------------------------------------

func test_overloaded() -> void:
	# 21667 units (~21.67 stone) -> overloaded
	var items := [_make_item("Absurd load", 21667)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	check(int(result.total_units) == 21667,
		"should be 21667 units")
	check(result.is_overloaded == true,
		"21667 units (21.7 stone) should be overloaded")
	print("  overloaded: OK")


# ---------------------------------------------------------------------------
# Magical armor weight reduction
# ---------------------------------------------------------------------------

func test_magical_armor_reduction() -> void:
	# Chain mail normally 4000 units. Magical +2 reduces by 2 stones (2000 units).
	# Result: 4000 - 2000 = 2000 units
	var chain := _make_item("Chain Mail +2", 4000, "armor", true, 2)
	var result := EncumbranceCalculator.calculate_encumbrance([chain])
	check(int(result.total_units) == 2000,
		"chain +2 should be 4000-2000=2000 units, got %d" % int(result.total_units))

	# Shield +1 normally 1000 units. Magical +1 reduces by 1 stone (1000 units).
	# Result: 1000 - 1000 = 0 units (clamped to 0)
	var shield := _make_item("Shield +1", 1000, "shield", true, 1)
	var shield_result := EncumbranceCalculator.calculate_encumbrance([shield])
	check(int(shield_result.total_units) == 0,
		"shield +1 should be 1000-1000=0 units, got %d" % int(shield_result.total_units))

	# Non-magical armor gets no reduction
	var normal_chain := _make_item("Chain Mail", 4000, "armor", false, 0)
	var normal_result := EncumbranceCalculator.calculate_encumbrance([normal_chain])
	check(int(normal_result.total_units) == 4000,
		"non-magical chain should be 4000 units, got %d" % int(normal_result.total_units))
	print("  magical_armor_reduction: OK")


# ---------------------------------------------------------------------------
# Movement tier boundaries
# ---------------------------------------------------------------------------

func test_movement_tier_boundaries() -> void:
	# Test exact boundary values:
	# 5000 units = 120'/turn (at 5-stone boundary)
	var tier := EncumbranceCalculator.get_movement_tier(5000)
	check(int(tier.exploration) == 120,
		"5000 units should give 120'/turn, got %d" % int(tier.exploration))

	# 5001 units = 90'/turn (crosses into next tier)
	tier = EncumbranceCalculator.get_movement_tier(5001)
	check(int(tier.exploration) == 90,
		"5001 units should give 90'/turn, got %d" % int(tier.exploration))

	# 7000 units = 90'/turn (at 7-stone boundary)
	tier = EncumbranceCalculator.get_movement_tier(7000)
	check(int(tier.exploration) == 90,
		"7000 units should give 90'/turn, got %d" % int(tier.exploration))

	# 7001 units = 60'/turn (crosses into next tier)
	tier = EncumbranceCalculator.get_movement_tier(7001)
	check(int(tier.exploration) == 60,
		"7001 units should give 60'/turn, got %d" % int(tier.exploration))

	# 10000 units = 60'/turn (at 10-stone boundary)
	tier = EncumbranceCalculator.get_movement_tier(10000)
	check(int(tier.exploration) == 60,
		"10000 units should give 60'/turn, got %d" % int(tier.exploration))

	# 10001 units = 30'/turn (crosses into max-load tier)
	tier = EncumbranceCalculator.get_movement_tier(10001)
	check(int(tier.exploration) == 30,
		"10001 units should give 30'/turn, got %d" % int(tier.exploration))
	print("  movement_tier_boundaries: OK")


# ---------------------------------------------------------------------------
# Coin encumbrance (1 unit per coin, quantity multiplied)
# ---------------------------------------------------------------------------

func test_coin_encumbrance() -> void:
	# 1000 gold coins = 1000 units = 1.0 stone
	var gold := InventoryItem.new()
	gold.name = "Gold Pieces"
	gold.item_key = "coins_gp"
	gold.item_category = "treasure"
	gold.encumbrance_units = 1
	gold.quantity = 1000

	var result := EncumbranceCalculator.calculate_encumbrance([gold])
	check(int(result.total_units) == 1000,
		"1000 coins should be 1000 units, got %d" % int(result.total_units))
	check(abs(result.total_stone - 1.0) < 0.001,
		"1000 coins should be 1.0 stone, got %.3f" % result.total_stone)

	# 100 gold coins = 100 units = 0.1 stone
	var small_purse := InventoryItem.new()
	small_purse.name = "Gold Pieces"
	small_purse.item_key = "coins_gp"
	small_purse.item_category = "treasure"
	small_purse.encumbrance_units = 1
	small_purse.quantity = 100

	var small_result := EncumbranceCalculator.calculate_encumbrance([small_purse])
	check(int(small_result.total_units) == 100,
		"100 coins should be 100 units, got %d" % int(small_result.total_units))
	print("  coin_encumbrance: OK")


# ---------------------------------------------------------------------------
# Clothing-vs-armor coexistence (gdd-character-tab.md §3.4.6).
# Worn clothing/ornamentation/rings are weightless; armor is full-weight even
# when worn; clothing and armor coexist (separate paper-doll slots, migration 151).
# ---------------------------------------------------------------------------

func _worn(units: int, category: String, slot: String) -> InventoryItem:
	var i := InventoryItem.new()
	i.encumbrance_units = units
	i.item_category = category
	i.slot = slot
	i.is_equipped = true
	return i


func test_worn_clothing_is_weightless() -> void:
	# An equipped tunic (167 units) contributes 0 stone while worn.
	var tunic := _worn(167, "clothing", "torso_clothing")
	var result := EncumbranceCalculator.calculate_encumbrance([tunic])
	check(int(result.total_units) == 0,
		"worn torso clothing should weigh 0, got %d" % int(result.total_units))
	# Legs clothing too.
	var hose := _worn(167, "clothing", "legs_clothing")
	check(EncumbranceCalculator.calculate_item_encumbrance(hose) == 0,
		"worn legs clothing should weigh 0")
	print("  worn_clothing_is_weightless: OK")


func test_carried_clothing_keeps_weight() -> void:
	# The SAME tunic carried in the pack (not equipped) weighs its full 167.
	var tunic := _make_item("Tunic", 167, "clothing")  # is_equipped defaults false
	tunic.slot = "pack"
	var result := EncumbranceCalculator.calculate_encumbrance([tunic])
	check(int(result.total_units) == 167,
		"carried (unequipped) clothing keeps full weight, got %d" % int(result.total_units))
	print("  carried_clothing_keeps_weight: OK")


func test_worn_armor_keeps_full_weight() -> void:
	# Equipped chain mail (4000 units) in the dedicated 'armor' slot stays full.
	var chain := _worn(4000, "armor", "armor")
	var result := EncumbranceCalculator.calculate_encumbrance([chain])
	check(int(result.total_units) == 4000,
		"worn armor keeps full weight, got %d" % int(result.total_units))
	print("  worn_armor_keeps_full_weight: OK")


func test_clothing_and_armor_coexist() -> void:
	# A character wears clothing AND armor at once (§3.4.6). The clothing is
	# weightless; only the armor's 4000 units count.
	var tunic := _worn(167, "clothing", "torso_clothing")
	var hose := _worn(167, "clothing", "legs_clothing")
	var chain := _worn(4000, "armor", "armor")
	var result := EncumbranceCalculator.calculate_encumbrance([tunic, hose, chain])
	check(int(result.total_units) == 4000,
		"clothing weightless + armor full = 4000, got %d" % int(result.total_units))
	print("  clothing_and_armor_coexist: OK")


func test_worn_ornament_and_ring_weightless() -> void:
	# Non-clothing-category ornamentation in the neck/cloak/ring slots is also
	# weightless when worn (holy symbol = gear, ring = gear), per §3.4.6.
	var holy := _worn(100, "gear", "neck")
	var ring := _worn(50, "gear", "ring_l")
	var cloak := _worn(167, "gear", "cloak")
	var result := EncumbranceCalculator.calculate_encumbrance([holy, ring, cloak])
	check(int(result.total_units) == 0,
		"worn neck/ring/cloak ornamentation should weigh 0, got %d" % int(result.total_units))
	print("  worn_ornament_and_ring_weightless: OK")


# ---------------------------------------------------------------------------
# Container-as-sub-carrier (Jedidiah refactor 2026-05-31).
# Containers (items with `container_id` pointing to them) act as sub-carriers:
# loose items + per-container aggregate weights, instead of flat sum of all
# items. Extradimensional containers (Bag of Holding, etc.) report their own
# weight only — contents are weightless to the bearer.
# ---------------------------------------------------------------------------

func _make_container(id: String, item_name: String, units: int,
		is_extradimensional: bool = false) -> InventoryItem:
	var c := InventoryItem.new()
	c.id = id
	c.name = item_name
	c.encumbrance_units = units
	c.item_category = "container"
	c.is_extradimensional = is_extradimensional
	return c


func _make_contained(item_name: String, units: int, parent_id: String,
		category: String = "gear") -> InventoryItem:
	var i := InventoryItem.new()
	i.name = item_name
	i.encumbrance_units = units
	i.item_category = category
	i.container_id = parent_id  # this item is INSIDE parent_id
	return i


func test_mundane_container_aggregates_own_weight_plus_contents() -> void:
	# Mundane backpack (167 units = 0.167 stone) with 3 daggers
	# (1000 units = 1 stone each) inside. Total = 167 + 3000 = 3167 units.
	var backpack := _make_container("bp1", "Backpack", 167)
	var d1 := _make_contained("Dagger", 1000, "bp1", "weapon")
	var d2 := _make_contained("Dagger", 1000, "bp1", "weapon")
	var d3 := _make_contained("Dagger", 1000, "bp1", "weapon")
	var inv: Array = [backpack, d1, d2, d3]
	var result := EncumbranceCalculator.calculate_encumbrance(inv)
	check(int(result.total_units) == 3167,
		"backpack (167) + 3 daggers (1000 each) = 3167 total units, got %d" %
			int(result.total_units))


func test_empty_container_just_own_weight() -> void:
	# A container with no contents weighs only its own listed weight.
	var pouch := _make_container("p1", "Pouch", 167)
	var inv: Array = [pouch]
	var result := EncumbranceCalculator.calculate_encumbrance(inv)
	check(int(result.total_units) == 167,
		"empty pouch alone = 167 units, got %d" % int(result.total_units))


func test_extradimensional_container_contents_weightless() -> void:
	# Bag of Holding (6000 units = 6 stone fixed) with 50 stones (50000 units)
	# of contents. RAW: "regardless of what is put into the bag, it weighs a
	# maximum of 6 stone." Bearer sees ONLY the 6000 own weight.
	var bag := _make_container("boh1", "Bag of Holding", 6000, true)
	var heavy1 := _make_contained("Stone Block", 25000, "boh1")
	var heavy2 := _make_contained("Stone Block", 25000, "boh1")
	var inv: Array = [bag, heavy1, heavy2]
	var result := EncumbranceCalculator.calculate_encumbrance(inv)
	check(int(result.total_units) == 6000,
		"Bag of Holding (6000) + 50000 units of contents = bearer sees 6000 only, got %d" %
			int(result.total_units))


func test_extradimensional_with_overweight_contents() -> void:
	# Even if contents exceed the bag's RAW capacity (100 stone), the bearer
	# still sees only the bag's own weight. Capacity enforcement is a
	# separate concern from encumbrance — UI/transfer layer's job.
	var bag := _make_container("boh1", "Bag of Holding", 6000, true)
	var ridiculous := _make_contained("Way Too Heavy", 999999, "boh1")
	var inv: Array = [bag, ridiculous]
	var result := EncumbranceCalculator.calculate_encumbrance(inv)
	check(int(result.total_units) == 6000,
		"extradimensional contributes own weight regardless of insane contents, got %d" %
			int(result.total_units))


func test_nested_mundane_containers_recurse_correctly() -> void:
	# Backpack (167) containing Pouch (167) containing 5 coins (1 each).
	# Total: 167 + 167 + 5 = 339.
	var backpack := _make_container("bp1", "Backpack", 167)
	var pouch := _make_container("p1", "Pouch", 167)
	pouch.container_id = "bp1"  # pouch is INSIDE backpack
	var coins := _make_contained("Coins", 1, "p1", "treasure")
	coins.quantity = 5
	var inv: Array = [backpack, pouch, coins]
	var result := EncumbranceCalculator.calculate_encumbrance(inv)
	check(int(result.total_units) == 339,
		"backpack (167) + pouch (167) + 5 coins (1 each) = 339, got %d" %
			int(result.total_units))


func test_nested_extradimensional_in_mundane() -> void:
	# Backpack (167) containing Bag of Holding (6000) containing 50 stones
	# of contents. Bag of Holding contributes ONLY its 6000; backpack
	# aggregate = 167 + 6000 = 6167. Bearer total = 6167.
	# (RAW interaction: putting extradimensional inside extradimensional
	# explodes — out of V1 scope; this tests extradimensional INSIDE mundane.)
	var backpack := _make_container("bp1", "Backpack", 167)
	var bag := _make_container("boh1", "Bag of Holding", 6000, true)
	bag.container_id = "bp1"  # bag is INSIDE backpack
	var heavy := _make_contained("Stone Block", 50000, "boh1")
	var inv: Array = [backpack, bag, heavy]
	var result := EncumbranceCalculator.calculate_encumbrance(inv)
	check(int(result.total_units) == 6167,
		"backpack (167) + Bag of Holding (6000, contents weightless) = 6167, got %d" %
			int(result.total_units))


func test_flat_inventory_no_containers_unchanged_behavior() -> void:
	# Backward-compat regression: with no container_id set on any item,
	# encumbrance sums flat (same as the pre-refactor behavior). This
	# matches every existing test in this suite (which all use flat
	# inventories) — they keep passing.
	var sword := _make_item("Sword", 1000, "weapon")
	var shield := _make_item("Shield", 1000, "shield")
	var rations := _make_item("Rations", 167)
	rations.quantity = 7
	var inv: Array = [sword, shield, rations]
	var result := EncumbranceCalculator.calculate_encumbrance(inv)
	# Sword 1000 + Shield 1000 + 7 rations (167 each = 1169) = 3169.
	check(int(result.total_units) == 3169,
		"flat inventory: 1000 + 1000 + 7*167 = 3169, got %d" %
			int(result.total_units))
