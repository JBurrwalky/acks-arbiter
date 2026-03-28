extends Node

## Unit tests for EncumbranceCalculator.
## Run via test_runner.tscn. Uses plain assert() — no external framework.
##
## ACKS movement table:
##   <= 5 stone (<=30 sixths): 120'/turn
##   <= 7 stone (<=42 sixths): 90'/turn
##   <= 10 stone (<=60 sixths): 60'/turn
##   <= 20 stone (<=120 sixths): 30'/turn
##   > 20 stone (>120 sixths): overloaded


func run_all_tests() -> void:
	test_empty_inventory()
	test_light_load()
	test_medium_load()
	test_heavy_load()
	test_max_load()
	test_overloaded()
	test_magical_armor_reduction()
	test_movement_tier_boundaries()
	print("EncumbranceCalculator: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_item(item_name: String, sixths: int, category: String = "gear",
		magical: bool = false, mag_bonus: int = 0) -> InventoryItem:
	var item := InventoryItem.new()
	item.name = item_name
	item.encumbrance_sixths = sixths
	item.item_category = category
	item.is_magical = magical
	item.magical_bonus = mag_bonus
	return item


# ---------------------------------------------------------------------------
# Empty inventory
# ---------------------------------------------------------------------------

func test_empty_inventory() -> void:
	var result := EncumbranceCalculator.calculate_encumbrance([])
	assert(int(result.total_sixths) == 0,
		"empty inventory should have 0 sixths")
	assert(int(result.exploration_speed) == 120,
		"empty inventory exploration should be 120'/turn")
	assert(result.is_overloaded == false,
		"empty inventory should not be overloaded")
	print("  empty_inventory: OK")


# ---------------------------------------------------------------------------
# Light load (<=5 stone = <=30 sixths) -> 120'/turn
# ---------------------------------------------------------------------------

func test_light_load() -> void:
	# Sword (6 sixths) + dagger (1 sixth) = 7 sixths -> still light
	var items := [
		_make_item("Sword", 6, "weapon"),
		_make_item("Dagger", 1, "weapon"),
	]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	assert(int(result.total_sixths) == 7,
		"sword + dagger should be 7 sixths, got %d" % int(result.total_sixths))
	assert(int(result.exploration_speed) == 120,
		"7 sixths should give 120'/turn exploration")
	print("  light_load: OK")


# ---------------------------------------------------------------------------
# Medium load (>5 stone, <=7 stone = 31-42 sixths) -> 90'/turn
# ---------------------------------------------------------------------------

func test_medium_load() -> void:
	# 35 sixths (~5.8 stone) -> 90'/turn
	var items := [_make_item("Heavy gear", 35)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	assert(int(result.total_sixths) == 35,
		"should be 35 sixths")
	assert(int(result.exploration_speed) == 90,
		"35 sixths should give 90'/turn exploration, got %d" % int(result.exploration_speed))
	print("  medium_load: OK")


# ---------------------------------------------------------------------------
# Heavy load (>7 stone, <=10 stone = 43-60 sixths) -> 60'/turn
# ---------------------------------------------------------------------------

func test_heavy_load() -> void:
	# 50 sixths -> 60'/turn
	var items := [_make_item("Heavy pack", 50)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	assert(int(result.total_sixths) == 50,
		"should be 50 sixths")
	assert(int(result.exploration_speed) == 60,
		"50 sixths should give 60'/turn exploration, got %d" % int(result.exploration_speed))
	print("  heavy_load: OK")


# ---------------------------------------------------------------------------
# Max load (>10 stone, <=20 stone = 61-120 sixths) -> 30'/turn
# ---------------------------------------------------------------------------

func test_max_load() -> void:
	# 100 sixths -> 30'/turn
	var items := [_make_item("Very heavy pack", 100)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	assert(int(result.total_sixths) == 100,
		"should be 100 sixths")
	assert(int(result.exploration_speed) == 30,
		"100 sixths should give 30'/turn exploration, got %d" % int(result.exploration_speed))
	assert(result.is_overloaded == false,
		"100 sixths (16.7 stone) should NOT be overloaded")
	print("  max_load: OK")


# ---------------------------------------------------------------------------
# Overloaded (>20 stone = >120 sixths)
# ---------------------------------------------------------------------------

func test_overloaded() -> void:
	# 130 sixths -> overloaded
	var items := [_make_item("Absurd load", 130)]
	var result := EncumbranceCalculator.calculate_encumbrance(items)
	assert(int(result.total_sixths) == 130,
		"should be 130 sixths")
	assert(result.is_overloaded == true,
		"130 sixths (21.7 stone) should be overloaded")
	print("  overloaded: OK")


# ---------------------------------------------------------------------------
# Magical armor weight reduction
# ---------------------------------------------------------------------------

func test_magical_armor_reduction() -> void:
	# Chain mail normally 24 sixths. Magical +2 reduces by 2 stones (12 sixths).
	# Result: 24 - 12 = 12 sixths
	var chain := _make_item("Chain Mail +2", 24, "armor", true, 2)
	var result := EncumbranceCalculator.calculate_encumbrance([chain])
	assert(int(result.total_sixths) == 12,
		"chain +2 should be 24-12=12 sixths, got %d" % int(result.total_sixths))

	# Shield +1 normally 6 sixths. Magical +1 reduces by 1 stone (6 sixths).
	# Result: 6 - 6 = 0 sixths (clamped to 0)
	var shield := _make_item("Shield +1", 6, "shield", true, 1)
	var shield_result := EncumbranceCalculator.calculate_encumbrance([shield])
	assert(int(shield_result.total_sixths) == 0,
		"shield +1 should be 6-6=0 sixths, got %d" % int(shield_result.total_sixths))

	# Non-magical armor gets no reduction
	var normal_chain := _make_item("Chain Mail", 24, "armor", false, 0)
	var normal_result := EncumbranceCalculator.calculate_encumbrance([normal_chain])
	assert(int(normal_result.total_sixths) == 24,
		"non-magical chain should be 24 sixths, got %d" % int(normal_result.total_sixths))
	print("  magical_armor_reduction: OK")


# ---------------------------------------------------------------------------
# Movement tier boundaries
# ---------------------------------------------------------------------------

func test_movement_tier_boundaries() -> void:
	# Test exact boundary values:
	# 30 sixths = 120'/turn (at boundary)
	var tier := EncumbranceCalculator.get_movement_tier(30)
	assert(int(tier.exploration) == 120,
		"30 sixths should give 120'/turn, got %d" % int(tier.exploration))

	# 31 sixths = 90'/turn (crosses into next tier)
	tier = EncumbranceCalculator.get_movement_tier(31)
	assert(int(tier.exploration) == 90,
		"31 sixths should give 90'/turn, got %d" % int(tier.exploration))

	# 42 sixths = 90'/turn (at boundary)
	tier = EncumbranceCalculator.get_movement_tier(42)
	assert(int(tier.exploration) == 90,
		"42 sixths should give 90'/turn, got %d" % int(tier.exploration))

	# 43 sixths = 60'/turn (crosses into next tier)
	tier = EncumbranceCalculator.get_movement_tier(43)
	assert(int(tier.exploration) == 60,
		"43 sixths should give 60'/turn, got %d" % int(tier.exploration))

	# 60 sixths = 60'/turn (at boundary)
	tier = EncumbranceCalculator.get_movement_tier(60)
	assert(int(tier.exploration) == 60,
		"60 sixths should give 60'/turn, got %d" % int(tier.exploration))

	# 61 sixths = 30'/turn (crosses into next tier)
	tier = EncumbranceCalculator.get_movement_tier(61)
	assert(int(tier.exploration) == 30,
		"61 sixths should give 30'/turn, got %d" % int(tier.exploration))
	print("  movement_tier_boundaries: OK")
