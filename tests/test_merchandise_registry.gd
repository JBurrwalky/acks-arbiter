extends "res://tests/test_suite_base.gd"

## Unit tests for MerchandiseRegistry (Prereq.1 of the mercantile build).
## Per generation/gdd-settlement-economy.md §2.9.
##
## MerchandiseRegistry is autoloaded — tests reference the singleton directly.


func run_all_tests() -> void:
	test_common_count_20()
	test_precious_count_11()
	test_total_count_31()
	test_spot_check_base_prices()
	test_spot_check_load_weights()
	test_dispatcher_rows_return_zero()
	test_roll_range_coverage_100()
	test_monster_parts_count()
	if not has_failures():
		print("MerchandiseRegistry: all tests passed.")


# ---------------------------------------------------------------------------
# §2.9 test 1: common count == 20
# ---------------------------------------------------------------------------

func test_common_count_20() -> void:
	var commons: Array = MerchandiseRegistry.all_common()
	check(commons.size() == 20,
		"MerchandiseRegistry: all_common() should return 20 entries, got %d" % commons.size())


# ---------------------------------------------------------------------------
# §2.9 test 2: precious count == 11
# ---------------------------------------------------------------------------

func test_precious_count_11() -> void:
	var preciouses: Array = MerchandiseRegistry.all_precious()
	check(preciouses.size() == 11,
		"MerchandiseRegistry: all_precious() should return 11 entries, got %d" % preciouses.size())


# ---------------------------------------------------------------------------
# §2.9 test 3: total count == 31 + key uniqueness
# ---------------------------------------------------------------------------

func test_total_count_31() -> void:
	var all: Array = MerchandiseRegistry.all_merchandise()
	check(all.size() == 31,
		"MerchandiseRegistry: all_merchandise() should return 31 entries, got %d" % all.size())

	# Key uniqueness — every entry has a distinct merchandise_type.
	var seen: Dictionary = {}
	for entry in all:
		var key: String = entry.get("merchandise_type", "")
		check(not key.is_empty(),
			"MerchandiseRegistry: entry has empty merchandise_type: %s" % str(entry))
		check(not seen.has(key),
			"MerchandiseRegistry: duplicate merchandise_type %s" % key)
		seen[key] = true


# ---------------------------------------------------------------------------
# §2.9 test 4: spot-check base prices against RAW
# ---------------------------------------------------------------------------

func test_spot_check_base_prices() -> void:
	check(MerchandiseRegistry.base_price_gp("grain_vegetables") == 10,
		"grain_vegetables base price should be 10 gp (RAW common merchandise table)")
	check(MerchandiseRegistry.base_price_gp("silk") == 2000,
		"silk base price should be 2000 gp")
	check(MerchandiseRegistry.base_price_gp("gems") == 3000,
		"gems base price should be 3000 gp")
	check(MerchandiseRegistry.base_price_gp("salt") == 100,
		"salt base price should be 100 gp")
	check(MerchandiseRegistry.base_price_gp("monster_parts") == 300,
		"monster_parts base price should be 300 gp")


# ---------------------------------------------------------------------------
# §2.9 test 5: spot-check load weights
# ---------------------------------------------------------------------------

func test_spot_check_load_weights() -> void:
	check(MerchandiseRegistry.load_weight_stone("grain_vegetables") == 80,
		"grain_vegetables load weight should be 80 stone")
	check(MerchandiseRegistry.load_weight_stone("spices") == 1,
		"spices load weight should be 1 stone")
	check(MerchandiseRegistry.load_weight_stone("metals_common") == 100,
		"metals_common load weight should be 100 stone")
	check(MerchandiseRegistry.load_weight_stone("silk") == 20,
		"silk load weight should be 20 stone")


# ---------------------------------------------------------------------------
# §2.9 test 6: dispatcher rows (animals/mounts) return 0 base_price/weight
# ---------------------------------------------------------------------------

func test_dispatcher_rows_return_zero() -> void:
	check(MerchandiseRegistry.base_price_gp("animals") == 0,
		"animals dispatcher should return base_price_gp == 0 (sentinel)")
	check(MerchandiseRegistry.load_weight_stone("animals") == 0,
		"animals dispatcher should return load_weight_stone == 0 (sentinel)")
	check(MerchandiseRegistry.base_price_gp("mounts") == 0,
		"mounts dispatcher should return base_price_gp == 0 (sentinel)")
	check(MerchandiseRegistry.load_weight_stone("mounts") == 0,
		"mounts dispatcher should return load_weight_stone == 0 (sentinel)")

	# Verify dispatcher metadata exists on the row itself
	var animals_entry: Dictionary = MerchandiseRegistry.get_by_type("animals")
	check(animals_entry.get("dispatcher", "") == "animals_subtable",
		"animals entry should have dispatcher='animals_subtable'")
	check(animals_entry.get("subroll", "") == "1d6",
		"animals dispatcher subroll should be '1d6'")

	var mounts_entry: Dictionary = MerchandiseRegistry.get_by_type("mounts")
	check(mounts_entry.get("dispatcher", "") == "animals_subtable",
		"mounts entry should have dispatcher='animals_subtable'")
	check(mounts_entry.get("subroll", "") == "1d4+4",
		"mounts dispatcher subroll should be '1d4+4'")


# ---------------------------------------------------------------------------
# §2.9 test 7: d100 roll-range coverage == 100 on each table
# ---------------------------------------------------------------------------

func test_roll_range_coverage_100() -> void:
	# Common: 20 entries cover [1..85] continuous; [86..100] dispatches to precious.
	var common: Array = MerchandiseRegistry.all_common()
	var sum_common: int = 0
	var prev_max: int = 0
	for entry in common:
		var rr: Array = entry.get("roll_range", [0, 0])
		var lo: int = int(rr[0])
		var hi: int = int(rr[1])
		check(lo == prev_max + 1,
			"Common roll ranges must be continuous: expected %d, got %d for %s" % [
				prev_max + 1, lo, entry.get("merchandise_type", "?")
			])
		check(hi >= lo,
			"Common roll range invalid for %s: %d-%d" % [entry.get("merchandise_type", "?"), lo, hi])
		sum_common += (hi - lo + 1)
		prev_max = hi
	check(sum_common == 85,
		"Common roll ranges should cover 85 d100 slots (1-85; 86-100 dispatches to precious); got %d" % sum_common)
	check(prev_max == 85,
		"Common table should end at 85 (before precious dispatch); ends at %d" % prev_max)

	# Precious: 11 entries cover [1..100] continuous.
	var precious: Array = MerchandiseRegistry.all_precious()
	var sum_precious: int = 0
	prev_max = 0
	for entry in precious:
		var rr: Array = entry.get("roll_range", [0, 0])
		var lo: int = int(rr[0])
		var hi: int = int(rr[1])
		check(lo == prev_max + 1,
			"Precious roll ranges must be continuous: expected %d, got %d for %s" % [
				prev_max + 1, lo, entry.get("merchandise_type", "?")
			])
		check(hi >= lo,
			"Precious roll range invalid for %s: %d-%d" % [entry.get("merchandise_type", "?"), lo, hi])
		sum_precious += (hi - lo + 1)
		prev_max = hi
	check(sum_precious == 100,
		"Precious roll ranges should cover 100 d100 slots; got %d" % sum_precious)


# ---------------------------------------------------------------------------
# §2.9 test 8: monster_parts_count derivation
# ---------------------------------------------------------------------------

func test_monster_parts_count() -> void:
	check(MerchandiseRegistry.monster_parts_count(10) == 30,
		"monster_parts_count(10) should be 30 (floor(300/10))")
	check(MerchandiseRegistry.monster_parts_count(25) == 12,
		"monster_parts_count(25) should be 12 (floor(300/25))")
	check(MerchandiseRegistry.monster_parts_count(300) == 1,
		"monster_parts_count(300) should be 1")
	check(MerchandiseRegistry.monster_parts_count(0) == 0,
		"monster_parts_count(0) should return 0 (safety)")
	check(MerchandiseRegistry.monster_parts_count(-5) == 0,
		"monster_parts_count(-5) should return 0 (safety)")
	# Spot-check a fractional case: 7 XP → floor(300/7) = 42
	check(MerchandiseRegistry.monster_parts_count(7) == 42,
		"monster_parts_count(7) should be 42 (floor(300/7))")
