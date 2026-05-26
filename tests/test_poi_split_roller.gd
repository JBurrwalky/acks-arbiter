extends "res://tests/test_suite_base.gd"

## PoiSplitRoller unit tests — Stage C pure-function implementation of
## `gdd-urban-growth-stocking.md` §5.4.1 split table.
##
## All tests use a seeded RandomNumberGenerator so the d6 outcome is
## deterministic. We pre-compute the seed → d6 sequence for the assertions.


func run_all_tests() -> void:
	test_k_zero_returns_empty()
	test_k_one_returns_single()
	test_k_two_d6_1_3_one_poi()
	test_k_two_d6_4_6_two_pois()
	test_k_three_d6_1_2_one_poi()
	test_k_three_d6_3_4_two_pois()
	test_k_three_d6_5_6_three_pois()
	test_k_four_d6_1_one_massive()
	test_k_seven_d6_3_three_pois_even()
	test_k_seven_d6_6_all_small()
	test_k_fourteen_d6_2_3_quarter_split()
	test_k_fourteen_d6_6_all_small()
	test_even_split_remainder_to_highest()
	test_sum_invariant_across_K_range()
	if not has_failures():
		print("PoiSplitRoller: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns an RNG seeded so the FIRST call to randi_range(1, 6) returns
## the given d6 value. Used to assert deterministic split table outcomes.
func _rng_with_d6(target: int) -> RandomNumberGenerator:
	for seed in range(1, 2000):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var preview := RandomNumberGenerator.new()
		preview.seed = seed
		if preview.randi_range(1, 6) == target:
			return rng
	push_error("could not find RNG seed for d6=%d" % target)
	return RandomNumberGenerator.new()


## Compare an Array[int] to an expected sequence of ints. Avoids the
## GDScript precedence ambiguity in `result == [...] as Array[int]` where
## the cast binds to the comparison result.
func _array_equals(actual: Array[int], expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i in range(actual.size()):
		if int(actual[i]) != int(expected[i]):
			return false
	return true


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_k_zero_returns_empty() -> void:
	var rng := RandomNumberGenerator.new()
	var result: Array[int] = PoiSplitRoller.roll_split(0, rng)
	check(result.size() == 0, "K=0 should produce no POIs")


func test_k_one_returns_single() -> void:
	var rng := RandomNumberGenerator.new()
	var result: Array[int] = PoiSplitRoller.roll_split(1, rng)
	check(_array_equals(result, [1]),
		"K=1 should produce [1]; got %s" % str(result))


func test_k_two_d6_1_3_one_poi() -> void:
	for d in [1, 2, 3]:
		var rng := _rng_with_d6(d)
		var result: Array[int] = PoiSplitRoller.roll_split(2, rng)
		check(_array_equals(result, [2]),
			"K=2 d6=%d should produce [2]; got %s" % [d, str(result)])


func test_k_two_d6_4_6_two_pois() -> void:
	for d in [4, 5, 6]:
		var rng := _rng_with_d6(d)
		var result: Array[int] = PoiSplitRoller.roll_split(2, rng)
		check(_array_equals(result, [1, 1]),
			"K=2 d6=%d should produce [1,1]; got %s" % [d, str(result)])


func test_k_three_d6_1_2_one_poi() -> void:
	for d in [1, 2]:
		var rng := _rng_with_d6(d)
		var result: Array[int] = PoiSplitRoller.roll_split(3, rng)
		check(_array_equals(result, [3]),
			"K=3 d6=%d should produce [3]; got %s" % [d, str(result)])


func test_k_three_d6_3_4_two_pois() -> void:
	for d in [3, 4]:
		var rng := _rng_with_d6(d)
		var result: Array[int] = PoiSplitRoller.roll_split(3, rng)
		check(_array_equals(result, [2, 1]),
			"K=3 d6=%d should produce [2,1]; got %s" % [d, str(result)])


func test_k_three_d6_5_6_three_pois() -> void:
	for d in [5, 6]:
		var rng := _rng_with_d6(d)
		var result: Array[int] = PoiSplitRoller.roll_split(3, rng)
		check(_array_equals(result, [1, 1, 1]),
			"K=3 d6=%d should produce [1,1,1]; got %s" % [d, str(result)])


func test_k_four_d6_1_one_massive() -> void:
	var rng := _rng_with_d6(1)
	var result: Array[int] = PoiSplitRoller.roll_split(4, rng)
	check(_array_equals(result, [4]),
		"K=4 d6=1 should produce [4]; got %s" % str(result))


## K=7 d6=3: N=3, even split with banker's rounding → 7/3 = 2 remainder 1
## → first POI gets +1 → [3, 2, 2].
func test_k_seven_d6_3_three_pois_even() -> void:
	var rng := _rng_with_d6(3)
	var result: Array[int] = PoiSplitRoller.roll_split(7, rng)
	check(_array_equals(result, [3, 2, 2]),
		"K=7 d6=3 should produce [3,2,2]; got %s" % str(result))


## K=7 d6=6: N=K, all [1].
func test_k_seven_d6_6_all_small() -> void:
	var rng := _rng_with_d6(6)
	var result: Array[int] = PoiSplitRoller.roll_split(7, rng)
	check(_array_equals(result, [1, 1, 1, 1, 1, 1, 1]),
		"K=7 d6=6 should produce 7×[1]; got %s" % str(result))


## K=14 d6=2 or 3: N=banker(14/4)=banker(3.5)=4 (round to even) → 14/4=3
## remainder 2 → [4, 4, 3, 3].
func test_k_fourteen_d6_2_3_quarter_split() -> void:
	for d in [2, 3]:
		var rng := _rng_with_d6(d)
		var result: Array[int] = PoiSplitRoller.roll_split(14, rng)
		check(_array_equals(result, [4, 4, 3, 3]),
			"K=14 d6=%d should produce [4,4,3,3]; got %s" % [d, str(result)])


## K=14 d6=6: all [1] × 14.
func test_k_fourteen_d6_6_all_small() -> void:
	var rng := _rng_with_d6(6)
	var result: Array[int] = PoiSplitRoller.roll_split(14, rng)
	check(result.size() == 14, "K=14 d6=6 should produce 14 entries; got %d" % result.size())
	var all_one := true
	for v in result:
		if v != 1:
			all_one = false
			break
	check(all_one, "K=14 d6=6 entries should all be 1")


## K=8, d6=3, N=3: even split → 8/3=2 remainder 2 → [3, 3, 2].
func test_even_split_remainder_to_highest() -> void:
	var rng := _rng_with_d6(3)
	var result: Array[int] = PoiSplitRoller.roll_split(8, rng)
	check(_array_equals(result, [3, 3, 2]),
		"K=8 d6=3 should produce [3,3,2]; got %s" % str(result))


## Across K = 1..30, for every d6 outcome, the returned split must sum to K.
func test_sum_invariant_across_K_range() -> void:
	for K in range(1, 31):
		for d in range(1, 7):
			var rng := _rng_with_d6(d)
			var result: Array[int] = PoiSplitRoller.roll_split(K, rng)
			var s: int = 0
			for v in result:
				s += int(v)
			check(s == K, "K=%d d6=%d sum mismatch (got %d, expected %d): %s" % [
				K, d, s, K, str(result)])
