extends Node

## Unit tests for EncumbranceCalculator.
## Run via test_runner.tscn. Uses plain assert() — no external framework.
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
	assert(int(result.total_units) == 0,
		"empty inventory should have 0 units")
	assert(int(result.exploration_speed) == 120,
		"empty inventory exploration should be 120'/turn")
	assert(result.is_overloaded == false,
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
	assert(int(result.total_units) == 1167,
		"sword + dagger should be 1167 units, got %d" % int(result.total_units))
	assert(int(result.exploration_speed) == 120,
		"1167 units should give 120'/turn exploration")
	print("  light_load: OK")


# ---------------------------------------------------------------------------
# Medium load (>5 stone, <=7 stone = 5001-7000 units) -> 90'/turn
# ---------------------------------------------------------------------------

func test_medium_load() -> void:
	# 5833 units (~5.83 stone) -> 90'/turn
	var items := [_make_item("Heavy gear", 5833)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	assert(int(result.total_units) == 5833,
		"should be 5833 units")
	assert(int(result.exploration_speed) == 90,
		"5833 units should give 90'/turn exploration, got %d" % int(result.exploration_speed))
	print("  medium_load: OK")


# ---------------------------------------------------------------------------
# Heavy load (>7 stone, <=10 stone = 7001-10000 units) -> 60'/turn
# ---------------------------------------------------------------------------

func test_heavy_load() -> void:
	# 8333 units (~8.33 stone) -> 60'/turn
	var items := [_make_item("Heavy pack", 8333)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	assert(int(result.total_units) == 8333,
		"should be 8333 units")
	assert(int(result.exploration_speed) == 60,
		"8333 units should give 60'/turn exploration, got %d" % int(result.exploration_speed))
	print("  heavy_load: OK")


# ---------------------------------------------------------------------------
# Max load (>10 stone, <=20 stone = 10001-20000 units) -> 30'/turn
# ---------------------------------------------------------------------------

func test_max_load() -> void:
	# 16667 units (~16.67 stone) -> 30'/turn, not overloaded
	var items := [_make_item("Very heavy pack", 16667)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	assert(int(result.total_units) == 16667,
		"should be 16667 units")
	assert(int(result.exploration_speed) == 30,
		"16667 units should give 30'/turn exploration, got %d" % int(result.exploration_speed))
	assert(result.is_overloaded == false,
		"16667 units (16.7 stone) should NOT be overloaded")
	print("  max_load: OK")


# ---------------------------------------------------------------------------
# Overloaded (>20 stone = >20000 units)
# ---------------------------------------------------------------------------

func test_overloaded() -> void:
	# 21667 units (~21.67 stone) -> overloaded
	var items := [_make_item("Absurd load", 21667)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	assert(int(result.total_units) == 21667,
		"should be 21667 units")
	assert(result.is_overloaded == true,
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
	assert(int(result.total_units) == 2000,
		"chain +2 should be 4000-2000=2000 units, got %d" % int(result.total_units))

	# Shield +1 normally 1000 units. Magical +1 reduces by 1 stone (1000 units).
	# Result: 1000 - 1000 = 0 units (clamped to 0)
	var shield := _make_item("Shield +1", 1000, "shield", true, 1)
	var shield_result := EncumbranceCalculator.calculate_encumbrance([shield])
	assert(int(shield_result.total_units) == 0,
		"shield +1 should be 1000-1000=0 units, got %d" % int(shield_result.total_units))

	# Non-magical armor gets no reduction
	var normal_chain := _make_item("Chain Mail", 4000, "armor", false, 0)
	var normal_result := EncumbranceCalculator.calculate_encumbrance([normal_chain])
	assert(int(normal_result.total_units) == 4000,
		"non-magical chain should be 4000 units, got %d" % int(normal_result.total_units))
	print("  magical_armor_reduction: OK")


# ---------------------------------------------------------------------------
# Movement tier boundaries
# ---------------------------------------------------------------------------

func test_movement_tier_boundaries() -> void:
	# Test exact boundary values:
	# 5000 units = 120'/turn (at 5-stone boundary)
	var tier := EncumbranceCalculator.get_movement_tier(5000)
	assert(int(tier.exploration) == 120,
		"5000 units should give 120'/turn, got %d" % int(tier.exploration))

	# 5001 units = 90'/turn (crosses into next tier)
	tier = EncumbranceCalculator.get_movement_tier(5001)
	assert(int(tier.exploration) == 90,
		"5001 units should give 90'/turn, got %d" % int(tier.exploration))

	# 7000 units = 90'/turn (at 7-stone boundary)
	tier = EncumbranceCalculator.get_movement_tier(7000)
	assert(int(tier.exploration) == 90,
		"7000 units should give 90'/turn, got %d" % int(tier.exploration))

	# 7001 units = 60'/turn (crosses into next tier)
	tier = EncumbranceCalculator.get_movement_tier(7001)
	assert(int(tier.exploration) == 60,
		"7001 units should give 60'/turn, got %d" % int(tier.exploration))

	# 10000 units = 60'/turn (at 10-stone boundary)
	tier = EncumbranceCalculator.get_movement_tier(10000)
	assert(int(tier.exploration) == 60,
		"10000 units should give 60'/turn, got %d" % int(tier.exploration))

	# 10001 units = 30'/turn (crosses into max-load tier)
	tier = EncumbranceCalculator.get_movement_tier(10001)
	assert(int(tier.exploration) == 30,
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
	assert(int(result.total_units) == 1000,
		"1000 coins should be 1000 units, got %d" % int(result.total_units))
	assert(abs(result.total_stone - 1.0) < 0.001,
		"1000 coins should be 1.0 stone, got %.3f" % result.total_stone)

	# 100 gold coins = 100 units = 0.1 stone
	var small_purse := InventoryItem.new()
	small_purse.name = "Gold Pieces"
	small_purse.item_key = "coins_gp"
	small_purse.item_category = "treasure"
	small_purse.encumbrance_units = 1
	small_purse.quantity = 100

	var small_result := EncumbranceCalculator.calculate_encumbrance([small_purse])
	assert(int(small_result.total_units) == 100,
		"100 coins should be 100 units, got %d" % int(small_result.total_units))
	print("  coin_encumbrance: OK")
