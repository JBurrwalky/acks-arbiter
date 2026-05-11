extends "res://tests/test_suite_base.gd"

## Tests for TradeRangeResolver per acore-setting-construction-rules.xml
## §range_of_trade L264-278.


func run_all_tests() -> void:
	test_range_of_trade_class_vi()
	test_range_of_trade_class_iii()
	test_range_of_trade_class_i()
	test_range_of_trade_water_exceeds_road()
	test_range_of_trade_invalid_returns_zero()
	test_compute_non_henchman_no_data_default()
	if not has_failures():
		print("TradeRangeResolver: all tests passed.")


func test_range_of_trade_class_vi() -> void:
	# Class VI: 24 miles (4 hexes) road / 48 miles (8 hexes) water.
	check(TradeRangeResolver.range_of_trade_hexes(6, false) == 4, "Class VI road = 4 hexes")
	check(TradeRangeResolver.range_of_trade_hexes(6, true) == 8, "Class VI water = 8 hexes")


func test_range_of_trade_class_iii() -> void:
	# Class III: 96 miles (18 hexes) / 240 miles (40 hexes).
	check(TradeRangeResolver.range_of_trade_hexes(3, false) == 18, "Class III road = 18 hexes")
	check(TradeRangeResolver.range_of_trade_hexes(3, true) == 40, "Class III water = 40 hexes")


func test_range_of_trade_class_i() -> void:
	# Class I: 168 miles (28 hexes) / 480 miles (80 hexes).
	check(TradeRangeResolver.range_of_trade_hexes(1, false) == 28, "Class I road = 28 hexes")
	check(TradeRangeResolver.range_of_trade_hexes(1, true) == 80, "Class I water = 80 hexes")


func test_range_of_trade_water_exceeds_road() -> void:
	# Water range exceeds road range for every class (RAW values vary;
	# Class IV is the smallest gap at 12→20). Sanity-check water > road.
	for mc in range(1, 7):
		var road := TradeRangeResolver.range_of_trade_hexes(mc, false)
		var water := TradeRangeResolver.range_of_trade_hexes(mc, true)
		check(water > road, "Class %d water (%d) > road (%d)" % [mc, water, road])


func test_range_of_trade_invalid_returns_zero() -> void:
	check(TradeRangeResolver.range_of_trade_hexes(0, false) == 0, "0 → 0")
	check(TradeRangeResolver.range_of_trade_hexes(7, false) == 0, "7 → 0 (no Class VII)")


func test_compute_non_henchman_no_data_default() -> void:
	# Empty inputs → lenient default in-range -2.
	check(TradeRangeResolver.compute_non_henchman_base_loyalty("", "") == -2,
		"empty inputs → -2 (in-range default)")
