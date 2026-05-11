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
	test_efficiency_factor_band_boundaries()
	test_efficiency_factor_open_top_tier()
	test_efficiency_factor_resolved_2026_05_06_17_63_band()
	test_compute_tribute_received_applies_efficiency()
	test_describe_returns_complete_payload()
	if not has_failures():
		print("TributeCalculator: all tests passed.")


func test_tribute_base_zero_at_zero_families() -> void:
	check(TributeCalculator.compute_tribute_base_gp(0) == 0,
		"0 families → 0 gp")
	check(TributeCalculator.compute_tribute_base_gp(-50) == 0,
		"negative families → 0 gp")


func test_tribute_base_formula_against_table_at_known_points() -> void:
	# RAW table (acore_axioms §tribute_by_realm_families L300-350) rounded
	# values at known boundaries. The formula 18 × families^0.6 should match
	# within banker's rounding tolerance.
	# 100 families → ~285 (RAW: 285).
	var t100: int = TributeCalculator.compute_tribute_base_gp(100)
	check(absi(t100 - 285) <= 5,
		"100 families ≈ 285 gp, got %d" % t100)
	# 1000 families → ~1135 (RAW: 1135).
	var t1000: int = TributeCalculator.compute_tribute_base_gp(1000)
	check(absi(t1000 - 1135) <= 10,
		"1000 families ≈ 1135 gp, got %d" % t1000)
	# 10000 families → ~4520 (RAW: 4520).
	var t10000: int = TributeCalculator.compute_tribute_base_gp(10000)
	check(absi(t10000 - 4520) <= 30,
		"10000 families ≈ 4520 gp, got %d" % t10000)
	# 100000 families → ~18000 (RAW: 18000).
	var t100k: int = TributeCalculator.compute_tribute_base_gp(100000)
	check(absi(t100k - 18000) <= 100,
		"100k families ≈ 18000 gp, got %d" % t100k)


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
	var families: int = 1000  # base ≈ 1135
	var base: int = TributeCalculator.compute_tribute_base_gp(families)
	# 1 vassal → 100%
	check(TributeCalculator.compute_tribute_received_gp(families, 1) == base,
		"100% efficiency at 1 vassal")
	# 17 vassals → 50% — should be ~half of base.
	var rec_17: int = TributeCalculator.compute_tribute_received_gp(families, 17)
	check(absi(rec_17 - int(round(base * 0.5))) <= 1,
		"50% at 17 vassals; got %d expected ~%d" % [rec_17, int(round(base * 0.5))])
	# 64 vassals → 33%.
	var rec_64: int = TributeCalculator.compute_tribute_received_gp(families, 64)
	check(absi(rec_64 - int(round(base * 0.33))) <= 1,
		"33% at 64 vassals; got %d expected ~%d" % [rec_64, int(round(base * 0.33))])


func test_describe_returns_complete_payload() -> void:
	var d: Dictionary = TributeCalculator.describe(10000, 16)
	check(d.has("base_gp"), "describe has base_gp")
	check(d.has("efficiency_factor"), "describe has efficiency_factor")
	check(d.has("efficiency_pct"), "describe has efficiency_pct")
	check(d.has("efficiency_band_label"), "describe has efficiency_band_label")
	check(d.has("received_gp"), "describe has received_gp")
	check(int(d["efficiency_pct"]) == 66, "16 vassals → 66 pct, got %d" % int(d["efficiency_pct"]))
	check(String(d["efficiency_band_label"]).contains("9"),
		"label mentions 9 (band 2 = '9–16 vassals'), got %s" % String(d["efficiency_band_label"]))
