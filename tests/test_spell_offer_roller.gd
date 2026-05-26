extends "res://tests/test_suite_base.gd"

## SpellOfferRoller tests — Stage G pure-function dice rolls for the RAW
## Spell Availability by Market table per `acore_equipment.xml:979-991`.
##
## Uses seeded RandomNumberGenerator for deterministic outcomes; tests
## assert the dice expression is parsed correctly by rolling under known
## seeds and checking the result range.


func run_all_tests() -> void:
	test_unit_cost_divine_levels()
	test_unit_cost_arcane_levels()
	test_unit_cost_unknown_returns_zero()
	test_has_offer_row()
	test_max_spell_level_for()
	test_class_vi_excludes_high_divine()
	test_class_vi_excludes_high_arcane()
	test_class_vi_divine_1st_range_1_to_6()
	test_class_v_divine_5th_unavailable()
	test_class_iv_arcane_5th_unavailable()
	test_arcane_6th_class_iii_can_be_zero_or_one()
	test_invalid_tradition_returns_zero()
	test_roll_all_offers_for_market_class_class_vi()
	test_roll_all_offers_for_market_class_class_iii()
	test_class_i_divine_1st_uses_multiplier_x100()
	if not has_failures():
		print("SpellOfferRoller: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# ---------------------------------------------------------------------------
# Unit cost tests
# ---------------------------------------------------------------------------

func test_unit_cost_divine_levels() -> void:
	check(SpellOfferRoller.unit_cost_gp("divine", 1) == 10, "divine 1 = 10gp")
	check(SpellOfferRoller.unit_cost_gp("divine", 2) == 40, "divine 2 = 40gp")
	check(SpellOfferRoller.unit_cost_gp("divine", 3) == 150, "divine 3 = 150gp")
	check(SpellOfferRoller.unit_cost_gp("divine", 4) == 325, "divine 4 = 325gp")
	check(SpellOfferRoller.unit_cost_gp("divine", 5) == 500, "divine 5 = 500gp")


func test_unit_cost_arcane_levels() -> void:
	check(SpellOfferRoller.unit_cost_gp("arcane", 1) == 5, "arcane 1 = 5gp")
	check(SpellOfferRoller.unit_cost_gp("arcane", 2) == 20, "arcane 2 = 20gp")
	check(SpellOfferRoller.unit_cost_gp("arcane", 3) == 75, "arcane 3 = 75gp")
	check(SpellOfferRoller.unit_cost_gp("arcane", 4) == 325, "arcane 4 = 325gp")
	check(SpellOfferRoller.unit_cost_gp("arcane", 5) == 1250, "arcane 5 = 1250gp")
	check(SpellOfferRoller.unit_cost_gp("arcane", 6) == 4500, "arcane 6 = 4500gp")


func test_unit_cost_unknown_returns_zero() -> void:
	check(SpellOfferRoller.unit_cost_gp("divine", 99) == 0,
		"unknown level returns 0")
	check(SpellOfferRoller.unit_cost_gp("psionic", 1) == 0,
		"unknown tradition returns 0")


func test_has_offer_row() -> void:
	check(SpellOfferRoller.has_offer_row("divine", 1), "divine 1 valid")
	check(SpellOfferRoller.has_offer_row("arcane", 6), "arcane 6 valid")
	check(not SpellOfferRoller.has_offer_row("divine", 6),
		"divine 6 invalid (RAW max is 5)")
	check(not SpellOfferRoller.has_offer_row("arcane", 7),
		"arcane 7 invalid (RAW max is 6)")


func test_max_spell_level_for() -> void:
	check(SpellOfferRoller.max_spell_level_for("divine") == 5,
		"divine max is 5")
	check(SpellOfferRoller.max_spell_level_for("arcane") == 6,
		"arcane max is 6")
	check(SpellOfferRoller.max_spell_level_for("unknown") == 0,
		"unknown tradition max is 0")


# ---------------------------------------------------------------------------
# Class VI availability — exclusion of high spell levels
# ---------------------------------------------------------------------------

func test_class_vi_excludes_high_divine() -> void:
	var rng := _seeded_rng(1)
	# Divine 3rd, 4th, 5th are unavailable at Class VI ("—" in the RAW table).
	check(SpellOfferRoller.roll_offer_count("divine", 3, 6, rng) == 0,
		"Class VI Divine 3rd should always be 0 (RAW dash)")
	check(SpellOfferRoller.roll_offer_count("divine", 4, 6, rng) == 0,
		"Class VI Divine 4th should always be 0")
	check(SpellOfferRoller.roll_offer_count("divine", 5, 6, rng) == 0,
		"Class VI Divine 5th should always be 0")


func test_class_vi_excludes_high_arcane() -> void:
	var rng := _seeded_rng(1)
	check(SpellOfferRoller.roll_offer_count("arcane", 3, 6, rng) == 0,
		"Class VI Arcane 3rd should always be 0 (RAW dash)")
	check(SpellOfferRoller.roll_offer_count("arcane", 4, 6, rng) == 0,
		"Class VI Arcane 4th should always be 0")
	check(SpellOfferRoller.roll_offer_count("arcane", 5, 6, rng) == 0,
		"Class VI Arcane 5th should always be 0")
	check(SpellOfferRoller.roll_offer_count("arcane", 6, 6, rng) == 0,
		"Class VI Arcane 6th should always be 0")


func test_class_vi_divine_1st_range_1_to_6() -> void:
	# Class VI Divine 1st = 1d6 → value in [1, 6].
	for seed in [1, 100, 12345, 99999, 7]:
		var rng := _seeded_rng(seed)
		var c := SpellOfferRoller.roll_offer_count("divine", 1, 6, rng)
		check(c >= 1 and c <= 6,
			"Class VI Divine 1st (1d6) should be in [1,6]; seed=%d got=%d"
			% [seed, c])


func test_class_v_divine_5th_unavailable() -> void:
	var rng := _seeded_rng(1)
	check(SpellOfferRoller.roll_offer_count("divine", 5, 5, rng) == 0,
		"Class V Divine 5th unavailable")


func test_class_iv_arcane_5th_unavailable() -> void:
	var rng := _seeded_rng(1)
	check(SpellOfferRoller.roll_offer_count("arcane", 5, 4, rng) == 0,
		"Class IV Arcane 5th unavailable")


## Class III Arcane 6th = 1d2-1 → result in [0, 1].
func test_arcane_6th_class_iii_can_be_zero_or_one() -> void:
	var seen_zero := false
	var seen_one := false
	for seed in range(1, 50):
		var rng := _seeded_rng(seed)
		var c := SpellOfferRoller.roll_offer_count("arcane", 6, 3, rng)
		check(c == 0 or c == 1,
			"Class III Arcane 6th (1d2-1) should be 0 or 1; seed=%d got=%d"
			% [seed, c])
		if c == 0:
			seen_zero = true
		if c == 1:
			seen_one = true
		if seen_zero and seen_one:
			break
	check(seen_zero, "Class III Arcane 6th should produce 0 in at least one seed")
	check(seen_one, "Class III Arcane 6th should produce 1 in at least one seed")


func test_invalid_tradition_returns_zero() -> void:
	var rng := _seeded_rng(1)
	check(SpellOfferRoller.roll_offer_count("psionic", 1, 4, rng) == 0,
		"unknown tradition returns 0")


# ---------------------------------------------------------------------------
# roll_all_offers_for_market_class — aggregate roll across every row
# ---------------------------------------------------------------------------

func test_roll_all_offers_for_market_class_class_vi() -> void:
	var rng := _seeded_rng(1)
	var rolls := SpellOfferRoller.roll_all_offers_for_market_class(6, rng)
	# Class VI has divine 1, 2 and arcane 1, 2 available. 3+ are 0.
	# The result dict drops 0-count entries.
	if rolls.has("divine"):
		var divine: Dictionary = rolls["divine"]
		check(divine.has(1), "Class VI should roll some Divine 1st")
		check(not divine.has(3), "Class VI Divine 3rd should be excluded")
		check(not divine.has(4), "Class VI Divine 4th should be excluded")
		check(not divine.has(5), "Class VI Divine 5th should be excluded")
	if rolls.has("arcane"):
		var arcane: Dictionary = rolls["arcane"]
		check(not arcane.has(3), "Class VI Arcane 3rd should be excluded")
		check(not arcane.has(4), "Class VI Arcane 4th should be excluded")
		check(not arcane.has(6), "Class VI Arcane 6th should be excluded")


func test_roll_all_offers_for_market_class_class_iii() -> void:
	var rng := _seeded_rng(42)
	var rolls := SpellOfferRoller.roll_all_offers_for_market_class(3, rng)
	# Class III should have entries for divine 1-5 (mostly) and arcane 1-6.
	check(rolls.has("divine") or rolls.has("arcane"),
		"Class III should produce non-empty rolls")
	# Divine 1st is 5d10 → guaranteed >= 5 (at least one casting).
	if rolls.has("divine"):
		var divine: Dictionary = rolls["divine"]
		check(divine.has(1),
			"Class III Divine 1st (5d10) should always have at least one casting")
		var d1: int = int(divine[1])
		check(d1 >= 5 and d1 <= 50,
			"Class III Divine 1st (5d10) should be in [5,50]; got %d" % d1)


## Class I Divine 1st = 2d3×100, so the result should be a multiple of 100
## in the range [200, 600]. Verifies the multiplier is applied.
func test_class_i_divine_1st_uses_multiplier_x100() -> void:
	for seed in [1, 7, 13, 42, 999]:
		var rng := _seeded_rng(seed)
		var c := SpellOfferRoller.roll_offer_count("divine", 1, 1, rng)
		check(c >= 200 and c <= 600,
			"Class I Divine 1st (2d3×100) should be in [200,600]; seed=%d got=%d"
			% [seed, c])
		check(c % 100 == 0,
			"Class I Divine 1st result should be a multiple of 100; got %d" % c)
