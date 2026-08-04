extends "res://tests/test_suite_base.gd"

## Tests for TributeCalculator per acore_axioms_strongholds_and_domains.xml
## §tribute L286-351 + §tribute_inefficiency L398-409.
##
## Critical RAW patches verified:
## - [RESOLVED 2026-05-06] efficiency factor 17-63 = 50% (digit-transposition
##   correction of source XML's "17-36 = 50%").
## - precise_optional_formula 18 × families^0.6 — matches lookup table within
##   banker's rounding.


func run_all_tests() -> void:
	test_tribute_base_zero_at_zero_families()
	test_tribute_base_formula_against_table_at_known_points()
	test_tribute_base_is_copper_not_gold()
	test_efficiency_factor_band_boundaries()
	test_efficiency_factor_open_top_tier()
	test_efficiency_factor_resolved_2026_05_06_17_63_band()
	test_compute_tribute_received_applies_efficiency()
	test_describe_returns_complete_payload()
	if not has_failures():
		print("TributeCalculator: all tests passed.")


func test_tribute_base_zero_at_zero_families() -> void:
	check(TributeCalculator.compute_tribute_base_cp(0) == 0,
		"0 families → 0 cp")
	check(TributeCalculator.compute_tribute_base_cp(-50) == 0,
		"negative families → 0 cp")


func test_tribute_base_formula_against_table_at_known_points() -> void:
	# RAW table (acore_axioms §tribute_by_realm_families L300-350) rounded
	# values at known boundaries. The formula 18 × families^0.6 should match
	# within banker's rounding tolerance. RAW publishes gp; TributeCalculator
	# is cp-native (conventions §127), so each RAW gp figure is × 100 here and
	# the tolerance scales with it.
	# 100 families → RAW 285 gp.
	var t100_cp: int = TributeCalculator.compute_tribute_base_cp(100)
	check(absi(t100_cp - 285 * 100) <= 5 * 100,
		"100 families ≈ 285 gp (28,500 cp), got %d cp" % t100_cp)
	# 1000 families → RAW 1,135 gp.
	var t1000_cp: int = TributeCalculator.compute_tribute_base_cp(1000)
	check(absi(t1000_cp - 1135 * 100) <= 10 * 100,
		"1000 families ≈ 1135 gp (113,500 cp), got %d cp" % t1000_cp)
	# 10000 families → RAW 4,520 gp.
	var t10000_cp: int = TributeCalculator.compute_tribute_base_cp(10000)
	check(absi(t10000_cp - 4520 * 100) <= 30 * 100,
		"10000 families ≈ 4520 gp (452,000 cp), got %d cp" % t10000_cp)
	# 100000 families → RAW 18,000 gp.
	var t100k_cp: int = TributeCalculator.compute_tribute_base_cp(100000)
	check(absi(t100k_cp - 18000 * 100) <= 100 * 100,
		"100k families ≈ 18000 gp (1,800,000 cp), got %d cp" % t100k_cp)


## Regression lock for the 2026-07-31 cp pass. Before it, the monthly tick wrote
## a gp figure into the cp-denominated `domains.tribute_out_owed`, so a domain's
## tribute silently collapsed 100× on its first month of play. Assert the
## calculator returns copper, not gold, at a scale where the two cannot be
## confused.
func test_tribute_base_is_copper_not_gold() -> void:
	var cp: int = TributeCalculator.compute_tribute_base_cp(1000)
	check(cp > 100_000,
		"1000 families must be ~113,500 cp not ~1,135 gp; got %d" % cp)
	# The removed `compute_tribute_base_gp` entry point is enforced by the
	# parser, not by this test: any caller still using it fails to compile, which
	# is the point of deleting it rather than deprecating it.
	check(TributeCalculator.compute_tribute_received_cp(1000, 1) == cp,
		"received at 1 vassal (100%% efficiency) must equal base, in the same unit")


func test_efficiency_factor_band_boundaries() -> void:
	# Band 1: ≤8 vassals → 100%.
	check(TributeCalculator.efficiency_factor(1) == 1.0, "1 vassal → 100%")
	check(TributeCalculator.efficiency_factor(8) == 1.0, "8 vassals → 100%")
	# Band 2: 9-16 → 66%.
	check(TributeCalculator.efficiency_factor(9) == 0.66, "9 vassals → 66%")
	check(TributeCalculator.efficiency_factor(16) == 0.66, "16 vassals → 66%")
	# Band 4: 64-216 → 33%.
	check(TributeCalculator.efficiency_factor(64) == 0.33, "64 vassals → 33%")
	check(TributeCalculator.efficiency_factor(216) == 0.33, "216 vassals → 33%")
	# Band 5: 217-1024 → 20%.
	check(TributeCalculator.efficiency_factor(217) == 0.20, "217 vassals → 20%")
	check(TributeCalculator.efficiency_factor(1024) == 0.20, "1024 vassals → 20%")
	# Band 6: 1025-4095 → 10%.
	check(TributeCalculator.efficiency_factor(1025) == 0.10, "1025 → 10%")
	# Band 7: 4096-16384 → 5%.
	check(TributeCalculator.efficiency_factor(4096) == 0.05, "4096 → 5%")
	check(TributeCalculator.efficiency_factor(16384) == 0.05, "16384 → 5%")


func test_efficiency_factor_open_top_tier() -> void:
	# Band 8: 16385+ → 1%.
	check(TributeCalculator.efficiency_factor(16385) == 0.01, "16385 → 1%")
	check(TributeCalculator.efficiency_factor(50000) == 0.01, "50k → 1%")
	check(TributeCalculator.efficiency_factor(1_000_000) == 0.01, "1M → 1%")


func test_efficiency_factor_resolved_2026_05_06_17_63_band() -> void:
	# [RESOLVED 2026-05-06] — source XML reads "17-36 = 50%"; project
	# interpretation is "17-63 = 50%" per digit-transposition correction.
	# These three boundary cases are explicit RAW-PATCH lock-ins.
	check(TributeCalculator.efficiency_factor(17) == 0.50, "17 vassals → 50%")
	check(TributeCalculator.efficiency_factor(36) == 0.50, "36 vassals → 50% (boundary in source XML)")
	check(TributeCalculator.efficiency_factor(63) == 0.50, "63 vassals → 50% (boundary per RAW PATCH)")
	check(TributeCalculator.efficiency_factor(64) == 0.33, "64 vassals → 33% (next band)")


func test_compute_tribute_received_applies_efficiency() -> void:
	var families: int = 1000  # base ≈ 1135 gp = 113,500 cp
	var base_cp: int = TributeCalculator.compute_tribute_base_cp(families)
	# 1 vassal → 100%
	check(TributeCalculator.compute_tribute_received_cp(families, 1) == base_cp,
		"100% efficiency at 1 vassal")
	# 17 vassals → 50% — should be ~half of base.
	var rec_17: int = TributeCalculator.compute_tribute_received_cp(families, 17)
	check(absi(rec_17 - int(round(base_cp * 0.5))) <= 1,
		"50% at 17 vassals; got %d expected ~%d" % [rec_17, int(round(base_cp * 0.5))])
	# 64 vassals → 33%.
	var rec_64: int = TributeCalculator.compute_tribute_received_cp(families, 64)
	check(absi(rec_64 - int(round(base_cp * 0.33))) <= 1,
		"33% at 64 vassals; got %d expected ~%d" % [rec_64, int(round(base_cp * 0.33))])


func test_describe_returns_complete_payload() -> void:
	var d: Dictionary = TributeCalculator.describe(10000, 16)
	check(d.has("base_cp"), "describe has base_cp")
	check(d.has("efficiency_factor"), "describe has efficiency_factor")
	check(d.has("efficiency_pct"), "describe has efficiency_pct")
	check(d.has("efficiency_band_label"), "describe has efficiency_band_label")
	check(d.has("received_cp"), "describe has received_cp")
	check(int(d["efficiency_pct"]) == 66, "16 vassals → 66 pct, got %d" % int(d["efficiency_pct"]))
	check(String(d["efficiency_band_label"]).contains("9"),
		"label mentions 9 (band 2 = '9–16 vassals'), got %s" % String(d["efficiency_band_label"]))
