extends "res://tests/test_suite_base.gd"

## SettlementGrowthResolver unit tests — Stage B per
## `generation/gdd-urban-growth-stocking.md` §13.2.
##
## All math is exercised through deterministic dice rollers (mock RNG) so
## scenarios are reproducible. The resolver is a pure-function static
## class: no I/O, no signal emission — those land in the orchestrator
## (domain_handlers.gd) and are exercised indirectly via the full-month
## integration (Stage B covers the resolver math; integration assertions
## are part of Stage C+).
##
## Scenarios (per GDD §13.2):
##   1. Class VI → V advancement when urban_families crosses 250.
##   2. Population growth dice formula: 2 × (1d10 per 1000 urban_families).
##   3. Random growth ±1d10.
##   4. Dissolution at urban_families < 75.
##   5. Clanhold exception: investment-driven attraction skipped; cap at 250.


func run_all_tests() -> void:
	test_class_vi_to_v_advancement()
	test_population_growth_dice()
	test_random_growth_applies()
	test_dissolution_below_75()
	test_clanhold_investment_growth_halved_rate()
	test_clanhold_cap_at_250_lifted()
	test_clanhold_still_subject_to_standard_investment_cap()
	test_no_class_change_when_below_next_threshold()
	test_cumulative_investment_increments()
	test_market_class_regressed_when_pop_drops()
	if not has_failures():
		print("SettlementGrowthResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a Callable that returns predetermined results, in order.
## sequence is an Array of ints — each call pops the next value.
## Calls beyond the sequence length return 0 (use this for tests that don't
## care about excess rolls; for strict-mode use _strict_roller below).
func _scripted_roller(sequence: Array) -> Callable:
	var idx_ref := [0]
	return func(faces: int, count: int, exploding: bool) -> int:
		var i: int = idx_ref[0]
		if i >= sequence.size():
			return 0
		idx_ref[0] = i + 1
		return int(sequence[i])


## Build a dice roller that always returns `value` for every call.
## Useful for "no random change" / "always max" baseline tests.
func _constant_roller(value: int) -> Callable:
	return func(faces: int, count: int, exploding: bool) -> int:
		return value


func _settlement(urban_families: int, market_class: int,
		cumulative_investment_gp: int = 25000) -> Dictionary:
	return {
		"id": "test_settle",
		"urban_families": urban_families,
		"market_class": market_class,
		"cumulative_investment_gp": cumulative_investment_gp,
	}


## Migration 127 (Phase 11D.1): `is_chaotic_domain` dropped in favor of
## `domain_style` per gdd-domain-style-and-alignment.md. is_clanhold=true
## maps to domain_style='clanhold'.
func _domain(is_clanhold: bool = false, peasant_families: int = 1000) -> Dictionary:
	return {
		"id": "test_domain",
		"domain_style": "clanhold" if is_clanhold else "civilized",
		"peasant_families": peasant_families,
	}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## Class VI -> V advancement. Start: 200 urban_families (Class VI), 5000gp
## (= 500000 cp) investment. With scripted rolls that add ≥50 families:
##   * investment dice: 5 × 1d10 — scripted to sum 30 (six 5s)
##   * pop growth increase: 1 × 1d10 (exploding) — scripted to 5
##   * pop growth decrease: 1 × 1d10 (exploding) — scripted to 5
##   * random increase: 1 × 1d10 — scripted to 25
##   * random decrease: 1 × 1d10 — scripted to 0
## Net: 200 + 30 + 0 (pop net) + 25 - 0 = 255 → Class V threshold 250 crossed.
func test_class_vi_to_v_advancement() -> void:
	var roller := _scripted_roller([
		30,  # investment dice (1d10 × 5 = up to 50; scripted to 30)
		5,   # pop growth increase
		5,   # pop growth decrease
		25,  # random increase
		0,   # random decrease
	])
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(200, 6, 25000),
		_domain(0, 1000),
		500000,  # 5000gp = 500000cp
		roller)
	check(int(result.get("urban_families_new", 0)) == 255,
		"urban_families should reach 255; got %d" % int(result.get("urban_families_new", 0)))
	check(int(result.get("market_class_new", 6)) == 5,
		"market_class should advance to 5 (Class V); got %d" % int(result.get("market_class_new", 6)))
	check(bool(result.get("class_advanced", false)) == true,
		"class_advanced flag should be true")
	check(bool(result.get("class_regressed", false)) == false,
		"class_regressed flag should be false")
	check(bool(result.get("dissolved", false)) == false,
		"settlement should not be dissolved")


## Population growth dice — 2×1d10 per full 1000 urban_families, rounded up.
## At 2500 urban_families that's 3 groups => 3d10 increase + 3d10 decrease.
## We script: investment=0, increase=18, decrease=12, random_up=0, random_down=0
## Net delta = 18 - 12 = +6. No investment input.
func test_population_growth_dice() -> void:
	var roller := _scripted_roller([
		18,  # pop growth increase (3 groups, scripted to 18)
		12,  # pop growth decrease
		0,   # random up
		0,   # random down
	])
	# cumulative_investment_gp=200000 raises the population cap to 4999
	# (per the maximum-population-by-total-investment table at
	# `acore_axioms_strongholds_and_domains.xml:641-648`); without that
	# headroom the 75000gp tier caps at 2499 and would clip the result.
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(2500, 4, 200000),
		_domain(0, 5000),
		0,  # no investment
		roller)
	check(int(result.get("urban_families_new", 0)) == 2506,
		"urban_families should reach 2506; got %d" % int(result.get("urban_families_new", 0)))
	check(int(result.get("population_growth_increase", 0)) == 18,
		"population_growth_increase should be 18")
	check(int(result.get("population_growth_decrease", 0)) == 12,
		"population_growth_decrease should be 12")


## Random growth: ±1d10 each. With investment=0 and population_growth
## scripted to zero net, random growth should be the only delta.
func test_random_growth_applies() -> void:
	var roller := _scripted_roller([
		0,   # pop growth increase
		0,   # pop growth decrease
		7,   # random up
		3,   # random down
	])
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(500, 5, 25000),
		_domain(0, 2000),
		0,
		roller)
	check(int(result.get("random_growth", 0)) == 4,
		"random_growth should be +7 - 3 = 4; got %d" % int(result.get("random_growth", 0)))
	check(int(result.get("urban_families_new", 0)) == 504,
		"urban_families should reach 504; got %d" % int(result.get("urban_families_new", 0)))


## Dissolution at urban_families < 75. Start: 100 urban_families with
## scripted heavy population loss to drop below 75.
func test_dissolution_below_75() -> void:
	var roller := _scripted_roller([
		2,   # pop growth increase
		30,  # pop growth decrease (heavy loss)
		0,   # random up
		0,   # random down
	])
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(100, 6, 10000),
		_domain(0, 500),
		0,
		roller)
	check(bool(result.get("dissolved", false)) == true,
		"settlement should dissolve (urban_families dropped to %d)"
		% int(result.get("urban_families_new", -1)))
	check(int(result.get("urban_families_new", -1)) == 0,
		"post-dissolution urban_families should be 0")
	check(int(result.get("market_class_new", 6)) == 6,
		"dissolved settlement market_class falls back to 6")


## Phase 11D.2 (per GDD §2 + RAW L80-83): clanhold settlements DO grow via
## investment, but at halved rate (1d10 per 2,000 gp invested, not 1,000 gp).
## The previous "no investment growth for clanholds" behavior was the v1
## reading of xml:28-33 base clanhold rules; Arbiter applies the
## exceptions_from_clanholds L76-86 package, which LIFTS the cap and ENABLES
## investment growth at halved value.
func test_clanhold_investment_growth_halved_rate() -> void:
	var roller := _scripted_roller([
		3,   # investment dice (5,000 gp / 2,000 = 2 thousand-groups for clanhold,
		     # but actually 10,000 gp / 2,000 = 5 groups; first scripted value
		     # is the SUM of those 5 d10s).
		5,   # pop growth increase
		3,   # pop growth decrease
		2,   # random up
		1,   # random down
	])
	var clanhold_domain := _domain(true, 1000)  # domain_style = 'clanhold'
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(100, 6, 10000),
		clanhold_domain,
		1000000,  # 10,000gp investment → 5 d10 rolls at 2,000gp/roll for clanhold
		roller)
	check(int(result.get("investment_families_added", -1)) == 3,
		"clanhold investment growth at halved rate (10,000gp / 2,000 = 5 rolls; scripted sum 3); got %d"
		% int(result.get("investment_families_added", -1)))
	# 100 + 3 (investment) + (5-3) (pop growth) + (2-1) (random) = 106
	check(int(result.get("urban_families_new", 0)) == 106,
		"clanhold urban_families: 100 + 3 + (5-3) + (2-1) = 106; got %d"
		% int(result.get("urban_families_new", 0)))


## Phase 11D.2 (per RAW L80 + GDD §2): the previous 250-urban-families cap
## for clanholds is LIFTED. Settlements grow until they hit the cumulative-
## investment cap, same as civilized settlements. With low cumulative
## investment, the natural cap stays low; with high cumulative investment,
## clanholds can grow beyond 250.
func test_clanhold_cap_at_250_lifted() -> void:
	var roller := _scripted_roller([
		100, # pop growth increase — heavy (would push past old 250 cap)
		0,   # pop growth decrease
		0,   # random up
		0,   # random down
	])
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(240, 6, 75000),  # high cumulative_investment_gp → higher cap
		_domain(true, 5000),  # clanhold; old 12.5% cap would have been 625
		0,
		roller)
	# 240 + 100 = 340; new cap at 75,000gp cumulative investment is 2,499; no truncation.
	check(int(result.get("urban_families_new", 0)) == 340,
		"clanhold cap is lifted in 11D.2: no 250 / 12.5%% cap; got %d"
		% int(result.get("urban_families_new", 0)))
	check(int(result.get("cap_truncation", 0)) == 0,
		"no cap truncation when within the standard investment-based cap")


## Phase 11D.2: a low-cumulative-investment clanhold still caps at the
## standard investment-based table. The cap is the SAME function as civilized
## (i.e., 25,000 gp → 624 urban_families). The clanhold-specific cap is the
## one that was lifted, not the standard one.
func test_clanhold_still_subject_to_standard_investment_cap() -> void:
	# At cumulative_investment_gp=25,000, the standard cap is 624. A clanhold
	# settlement with the dice scripted to push past 624 should still cap.
	var roller := _scripted_roller([
		500, # pop growth increase — heavy
		0,   # pop growth decrease
		0,   # random up
		0,   # random down
	])
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(200, 6, 25000),
		_domain(true, 5000),  # clanhold, plenty of peasants
		0,
		roller)
	check(int(result.get("urban_families_new", 0)) == 624,
		"clanhold still capped by standard investment-cap (624 at 25,000gp); got %d"
		% int(result.get("urban_families_new", 0)))
	check(int(result.get("cap_truncation", 0)) == 76,
		"cap_truncation = 200+500-624 = 76; got %d"
		% int(result.get("cap_truncation", 0)))


## Market class should NOT change when urban_families stays in band.
func test_no_class_change_when_below_next_threshold() -> void:
	var roller := _scripted_roller([
		0,   # investment dice (5 × 1d10 — but scripted total 0)
		1,   # pop growth increase
		1,   # pop growth decrease
		2,   # random up
		1,   # random down
	])
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(200, 6, 25000),  # well below 250 (Class V threshold)
		_domain(0, 1000),
		500000,  # 5000gp -> 5 thousand-groups, but roller scripted to 0
		roller)
	check(bool(result.get("class_advanced", false)) == false,
		"class should NOT advance from 200 urban_families")
	check(int(result.get("market_class_new", 6)) == 6,
		"market_class should remain Class VI")


## cumulative_investment_gp increments by consumed investment_gp.
func test_cumulative_investment_increments() -> void:
	var roller := _constant_roller(0)  # no growth this month
	var start_cumulative := 25000
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(300, 5, start_cumulative),
		_domain(0, 1500),
		700000,  # 7000gp
		roller)
	check(int(result.get("investment_gp_consumed", -1)) == 7000,
		"investment_gp_consumed should be 7000")
	check(int(result.get("new_cumulative_investment_gp", -1)) == start_cumulative + 7000,
		"new_cumulative_investment_gp should be %d; got %d" % [
			start_cumulative + 7000,
			int(result.get("new_cumulative_investment_gp", -1)),
		])


## market_class_regressed when urban_families drops through a class
## threshold without dissolving (e.g. Class IV town shrinks back to V).
func test_market_class_regressed_when_pop_drops() -> void:
	# Start: 700 families (Class IV: 625+). Big loss to drop to Class V.
	var roller := _scripted_roller([
		0,   # pop growth increase
		200, # pop growth decrease
		0,   # random up
		100, # random down
	])
	var result := SettlementGrowthResolver.process_monthly_tick(
		_settlement(700, 4, 75000),
		_domain(0, 3000),
		0,
		roller)
	check(int(result.get("urban_families_new", 0)) == 400,
		"urban_families should drop to 400; got %d"
		% int(result.get("urban_families_new", 0)))
	check(int(result.get("market_class_new", 6)) == 5,
		"market_class should regress to Class V; got %d"
		% int(result.get("market_class_new", 6)))
	check(bool(result.get("class_regressed", false)) == true,
		"class_regressed flag should be true")
	check(bool(result.get("dissolved", false)) == false,
		"settlement should NOT be dissolved (still ≥ 75)")
