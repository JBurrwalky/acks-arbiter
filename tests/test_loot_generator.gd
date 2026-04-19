extends "res://tests/test_suite_base.gd"

## Unit tests for LootGenerator — treasure type parsing and coin generation.
## Uses GameState.dice_overrides to force deterministic rolls where needed.


func run_all_tests() -> void:
	test_parse_none_returns_empty()
	test_parse_letter_only()
	test_parse_letter_with_suffix()
	test_parse_invalid_returns_empty()
	test_generate_no_valid_types_returns_empty()
	test_generate_with_override_produces_coins()
	test_generate_failed_chance_produces_zero()
	test_multiple_types_aggregate()
	test_gp_value_mixed_coins()
	test_gp_value_empty_dict()
	test_gp_value_copper_only_rounds_down()
	test_gp_value_gold_only()

	if not has_failures():
		print("LootGenerator: all tests passed.")


# ---------------------------------------------------------------------------
# _parse_treasure_letter tests (via generate, observing behaviour)
# ---------------------------------------------------------------------------

func test_parse_none_returns_empty() -> void:
	var gen := LootGenerator.new()
	var result := gen.generate_from_treasure_types(["None"])
	check(result.is_empty(),
		"parse 'None' should produce empty result, got %s" % str(result))


func test_parse_letter_only() -> void:
	# "E" is a valid type — with overrides we can force a known result.
	# Override treasure_chance to pass (roll 1 ≤ 80%), treasure_coins to roll 5.
	GameState.dice_overrides["treasure_chance"] = 1
	GameState.dice_overrides["treasure_coins"] = 5
	var gen := LootGenerator.new()
	var result := gen.generate_from_treasure_types(["E"])
	check(not result.is_empty(),
		"valid type 'E' should produce a non-empty result")
	# Type E has copper (80%, 2d20) — with chance=1 (pass) and coins=5, expect 5000 cp.
	check(result.get("coins_cp", 0) == 5000,
		"E copper: expected 5000, got %d" % result.get("coins_cp", 0))


func test_parse_letter_with_suffix() -> void:
	# "E (per warband)" should parse to "E" and work the same.
	GameState.dice_overrides["treasure_chance"] = 1
	GameState.dice_overrides["treasure_coins"] = 3
	var gen := LootGenerator.new()
	var result := gen.generate_from_treasure_types(["E (per warband)"])
	check(not result.is_empty(),
		"'E (per warband)' should parse to valid type E")
	check(result.get("coins_cp", 0) == 3000,
		"E copper with roll=3: expected 3000, got %d" % result.get("coins_cp", 0))


func test_parse_invalid_returns_empty() -> void:
	var gen := LootGenerator.new()
	var result := gen.generate_from_treasure_types(["Z"])
	check(result.is_empty(),
		"invalid type 'Z' should produce empty result")


# ---------------------------------------------------------------------------
# generate_from_treasure_types tests
# ---------------------------------------------------------------------------

func test_generate_no_valid_types_returns_empty() -> void:
	var gen := LootGenerator.new()
	var result := gen.generate_from_treasure_types(["None", "", "Z"])
	check(result.is_empty(),
		"all invalid types should produce empty result")


func test_generate_with_override_produces_coins() -> void:
	# Type R has electrum (50%, 1d6), gold (60%, 1d6), platinum (80%, 1d8).
	# Force the first column (electrum) chance to pass, coins to 4.
	# The other columns will use real dice (or no override → random),
	# but we check that the electrum column is deterministic.
	GameState.dice_overrides["treasure_chance"] = 1  # pass first check
	GameState.dice_overrides["treasure_coins"] = 4   # first coin roll = 4
	var gen := LootGenerator.new()
	var result := gen.generate_from_treasure_types(["R"])
	check(not result.is_empty(), "type R should produce non-empty result")
	# Electrum is first non-null column for R → should be 4 * 1000 = 4000 ep.
	check(result.get("coins_ep", 0) == 4000,
		"R electrum: expected 4000, got %d" % result.get("coins_ep", 0))


func test_generate_failed_chance_produces_zero() -> void:
	# Type A has only silver (30% chance).
	# Force the chance roll to 100 (fail, since 100 > 30).
	GameState.dice_overrides["treasure_chance"] = 100
	var gen := LootGenerator.new()
	var result := gen.generate_from_treasure_types(["A"])
	check(not result.is_empty(), "type A should still return a result dict")
	check(result.get("coins_sp", 0) == 0,
		"A silver with failed check: expected 0, got %d" % result.get("coins_sp", 0))


func test_multiple_types_aggregate() -> void:
	# Two type A entries, both with forced success.
	# Type A: silver only (30%, 1d4).
	# First call: chance=1 (pass), coins=2 → 2000 sp.
	# Second call: overrides already consumed, so second will use real dice.
	# We just verify the first contributes correctly.
	GameState.dice_overrides["treasure_chance"] = 1
	GameState.dice_overrides["treasure_coins"] = 2
	var gen := LootGenerator.new()
	var result := gen.generate_from_treasure_types(["A", "A"])
	check(not result.is_empty(), "two A types should produce non-empty result")
	# At minimum, the first A contributed 2000 sp (second is random).
	check(result.get("coins_sp", 0) >= 2000,
		"two A types: expected at least 2000 sp, got %d" % result.get("coins_sp", 0))


# ---------------------------------------------------------------------------
# compute_treasure_gp_value tests
# ---------------------------------------------------------------------------

func test_gp_value_mixed_coins() -> void:
	# 2 pp (1000 cp) + 5 gp (500 cp) + 3 ep (150 cp) + 10 sp (100 cp) + 40 cp = 1790 cp
	# 1790 / 100 = 17 gp (integer division)
	var coins := {"coins_pp": 2, "coins_gp": 5, "coins_ep": 3, "coins_sp": 10, "coins_cp": 40}
	var gp := LootGenerator.compute_treasure_gp_value(coins)
	check(gp == 17,
		"mixed coins: expected 17 gp, got %d" % gp)


func test_gp_value_empty_dict() -> void:
	var gp := LootGenerator.compute_treasure_gp_value({})
	check(gp == 0, "empty dict: expected 0 gp, got %d" % gp)


func test_gp_value_copper_only_rounds_down() -> void:
	# 99 cp = 0 gp (truncated, not rounded)
	var coins := {"coins_cp": 99}
	var gp := LootGenerator.compute_treasure_gp_value(coins)
	check(gp == 0, "99 cp: expected 0 gp, got %d" % gp)


func test_gp_value_gold_only() -> void:
	var coins := {"coins_gp": 100}
	var gp := LootGenerator.compute_treasure_gp_value(coins)
	check(gp == 100, "100 gp: expected 100, got %d" % gp)
