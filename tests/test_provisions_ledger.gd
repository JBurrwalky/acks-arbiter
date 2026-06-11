extends "res://tests/test_suite_base.gd"

## Unit tests for ProvisionsLedger — the pure provisions-accounting layer of the
## rations / water / fodder consumption system (gdd-rations-foodstuffs.md).
## Exercises person-day math, the migration-149 "uninitialized = full" rule, the
## perishable-first food ordering, and water-container capacity — all without DB.

var _catalog: EquipmentCatalog = null


func run_all_tests() -> void:
	_catalog = EquipmentCatalog.new()
	test_uninitialized_food_row_is_full()
	test_explicit_remaining_overrides_capacity()
	test_capacity_days_scales_with_quantity()
	test_sum_food_days_mixed_rows()
	test_water_rows_only_count_holds_water()
	test_water_capacity_vs_current_fill()
	test_food_priority_iron_last()
	test_food_rows_sorted_perishable_then_standard_then_iron()
	test_humanoid_count_excludes_mercenaries()
	if not has_failures():
		print("ProvisionsLedger: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _row(item_key: String, quantity: int = 1, remaining: int = -1) -> Dictionary:
	return {
		"id": "row_%s_%d" % [item_key, quantity],
		"item_key": item_key,
		"quantity": quantity,
		"consumable_units_remaining": remaining,
	}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_uninitialized_food_row_is_full() -> void:
	# rations_standard_week = 7 person-days/unit; -1 remaining = full.
	var r := _row("rations_standard_week", 1, -1)
	check(ProvisionsLedger.row_effective_days(r, _catalog) == 7,
		"uninitialized 1-week ration row = 7 person-days")


func test_explicit_remaining_overrides_capacity() -> void:
	var r := _row("rations_standard_week", 1, 4)
	check(ProvisionsLedger.row_effective_days(r, _catalog) == 4,
		"explicit remaining=4 wins over the 7-day capacity")


func test_capacity_days_scales_with_quantity() -> void:
	var r := _row("rations_iron_week", 3, -1)
	check(ProvisionsLedger.row_capacity_days(r, _catalog) == 21,
		"3 iron-week rations = 21 person-days capacity")
	check(ProvisionsLedger.row_effective_days(r, _catalog) == 21,
		"uninitialized stack of 3 = full 21 days")


func test_sum_food_days_mixed_rows() -> void:
	var rows := [
		_row("rations_standard_week", 1, -1),  # 7
		_row("rations_iron_week", 1, 5),        # 5 explicit
		_row("bread_white", 2, -1),             # 1 pd/unit (2-lb ration) x 2 = 2
		_row("waterskin", 2, -1),               # water, excluded from food
	]
	check(ProvisionsLedger.sum_food_days(rows, _catalog) == 14,
		"food sum = 7 + 5 + 2 = 14 (water excluded); got %d"
		% ProvisionsLedger.sum_food_days(rows, _catalog))


func test_water_rows_only_count_holds_water() -> void:
	var rows := [
		_row("waterskin", 1, -1),   # holds_water, 1 pd
		_row("barrel", 1, -1),      # holds_water, 20 pd
		_row("wine_cheap", 4, -1),  # consumable_kind water but NOT holds_water
		_row("rations_standard_week", 1, -1),  # food
	]
	check(ProvisionsLedger.sum_water_days(rows, _catalog) == 21,
		"water = waterskin(1) + barrel(20) = 21; tavern wine excluded; got %d"
		% ProvisionsLedger.sum_water_days(rows, _catalog))


func test_water_capacity_vs_current_fill() -> void:
	var rows := [
		_row("waterskin", 2, 0),   # 2 skins, currently empty
		_row("barrel", 1, 8),      # 1 barrel, 8 of 20 gallons left
	]
	check(ProvisionsLedger.sum_water_days(rows, _catalog) == 8,
		"current fill = 0 + 8 = 8")
	check(ProvisionsLedger.sum_water_capacity_days(rows, _catalog) == 22,
		"capacity = 2x1 + 1x20 = 22")


func test_food_priority_iron_last() -> void:
	check(ProvisionsLedger.food_priority("rations_iron_week")
			> ProvisionsLedger.food_priority("rations_standard_week"),
		"iron rations consumed after standard")
	check(ProvisionsLedger.food_priority("rations_standard_week")
			> ProvisionsLedger.food_priority("bread_white"),
		"standard rations consumed after fresh perishables")


func test_food_rows_sorted_perishable_then_standard_then_iron() -> void:
	var rows := [
		_row("rations_iron_week", 1, -1),
		_row("rations_standard_week", 1, -1),
		_row("bread_white", 1, -1),
	]
	var ordered := ProvisionsLedger.food_rows_in_priority(rows, _catalog)
	check(ordered.size() == 3, "all 3 food rows retained")
	check(ProvisionsLedger.row_item_key(ordered[0]) == "bread_white",
		"perishable foodstuff first")
	check(ProvisionsLedger.row_item_key(ordered[1]) == "rations_standard_week",
		"standard rations second")
	check(ProvisionsLedger.row_item_key(ordered[2]) == "rations_iron_week",
		"iron rations last")


func test_humanoid_count_excludes_mercenaries() -> void:
	var pd := PartyData.new()
	pd.character_data = []
	var pc := CharacterData.new()
	pc.character_type = "pc"
	var hench := CharacterData.new()
	hench.character_type = "henchman"
	var merc := CharacterData.new()
	merc.character_type = "mercenary"
	pd.character_data = [pc, hench, merc]
	check(ProvisionsLedger.humanoid_count(pd) == 2,
		"PC + henchman counted, mercenary excluded; got %d"
		% ProvisionsLedger.humanoid_count(pd))
