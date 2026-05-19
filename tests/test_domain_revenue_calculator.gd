extends "res://tests/test_suite_base.gd"

## Unit tests for DomainRevenueCalculator.
##
## Verifies RAW formulas from `acore_axioms_strongholds_and_domains.xml`,
## with all amounts expressed in cp per the 2026-05-15 currency-precision pass
## (1 gp = 100 cp):
##   * Service revenue: 400 cp/peasant family flat (RAW 4 gp; §domain_revenue.services L195)
##   * Tax revenue: domain.tax_rate_cp_per_family per family (§taxes L197-201)
##   * Land revenue: per-hex (land_value + land_improvement_level) × 100 × families (cp)
##   * Tribute pass-through
##   * Income gate when stronghold_value_cp < classification_minimum_cp
##     (§peasants_and_followers L108-109)


func run_all_tests() -> void:
	test_service_revenue_is_400cp_per_peasant()
	test_tax_revenue_uses_configured_rate()
	test_land_revenue_per_hex()
	test_land_improvement_adds_to_per_hex_value()
	test_tribute_in_passes_through()
	test_total_is_sum_of_subcategories()
	test_income_gate_zeroes_revenue()
	test_at_minimum_sufficiency_revenue_active()
	if not has_failures():
		print("DomainRevenueCalculator: all tests passed.")


# ----- Service revenue -----

func test_service_revenue_is_400cp_per_peasant() -> void:
	var domain := {"peasant_families": 100, "tax_rate_cp_per_family": 0}
	var hexes: Array = []
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 999_999_999, 0)
	check(r["service"] == 40_000, "service should be 100 fam × 400 cp = 40,000 cp, got %d" % r["service"])


# ----- Tax revenue -----

func test_tax_revenue_uses_configured_rate() -> void:
	# 3 gp/family = 300 cp/family. 100 families × 300 = 30,000 cp.
	var domain := {"peasant_families": 100, "tax_rate_cp_per_family": 300}
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, [], 999_999_999, 0)
	check(r["tax"] == 30_000, "tax should be 100 × 300 cp = 30,000 cp, got %d" % r["tax"])

	# 2 gp/family = 200 cp/family. 50 families × 200 = 10,000 cp.
	var d2 := {"peasant_families": 50, "tax_rate_cp_per_family": 200}
	var r2 := DomainRevenueCalculator.calculate_monthly_revenue(d2, [], 999_999_999, 0)
	check(r2["tax"] == 10_000, "tax should be 50 × 200 cp = 10,000 cp, got %d" % r2["tax"])


# ----- Land revenue (per-hex) -----

func test_land_revenue_per_hex() -> void:
	# Two hexes at land_value 5 gp/fam; 100 peasants split 50/hex.
	# Each hex contributes 50 fam × 5 gp = 250 gp = 25,000 cp; total = 50,000 cp.
	var domain := {"peasant_families": 100, "tax_rate_cp_per_family": 0}
	var hexes: Array = [
		{"land_value": 5, "land_improvement_level": 0},
		{"land_value": 5, "land_improvement_level": 0},
	]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 999_999_999, 0)
	check(r["land"] == 50_000, "land should be 50,000 cp, got %d" % r["land"])


func test_land_improvement_adds_to_per_hex_value() -> void:
	# One hex at land_value 6 + improvement 2 = 8 effective gp/fam = 800 cp/fam.
	# 100 peasants × 800 = 80,000 cp.
	var domain := {"peasant_families": 100, "tax_rate_cp_per_family": 0}
	var hexes: Array = [{"land_value": 6, "land_improvement_level": 2}]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 999_999_999, 0)
	check(r["land"] == 80_000, "land should be 100 × (6+2) gp × 100 cp/gp = 80,000 cp, got %d" % r["land"])


# ----- Tribute pass-through -----

func test_tribute_in_passes_through() -> void:
	# Tribute is already cp; pass-through unchanged.
	var domain := {"peasant_families": 0, "tax_rate_cp_per_family": 0}
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, [], 999_999_999, 0, 35_000)
	check(r["tribute_in"] == 35_000, "tribute_in echoes 35,000 cp, got %d" % r["tribute_in"])
	check(r["total"] == 35_000, "total includes tribute_in only when no other revenue, got %d" % r["total"])


func test_total_is_sum_of_subcategories() -> void:
	# 100 peasants, 1 hex at land_value 5, tax_rate 200 cp/fam (= 2 gp/fam),
	# tribute_in 5000 cp.
	# service: 100 × 400 cp = 40,000 cp
	# tax: 100 × 200 cp = 20,000 cp
	# land: 100 × 5 gp × 100 cp/gp = 50,000 cp
	# tribute: 5,000 cp
	# total: 115,000 cp
	var domain := {"peasant_families": 100, "tax_rate_cp_per_family": 200}
	var hexes: Array = [{"land_value": 5, "land_improvement_level": 0}]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 999_999_999, 0, 5_000)
	check(r["total"] == 115_000, "total should sum to 115,000 cp, got %d" % r["total"])
	check(r["income_gate_active"] == false, "income gate should be inactive")


# ----- Income gate -----

func test_income_gate_zeroes_revenue() -> void:
	# Wilderness minimum is 32,000 gp per hex = 3,200,000 cp per hex.
	# stronghold_value 0 < 3,200,000 → gate active → all revenue zero.
	var domain := {"peasant_families": 100, "tax_rate_cp_per_family": 200,
		"territory_type": "wilderness"}
	var hexes: Array = [{"land_value": 5, "land_improvement_level": 0}]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 0, 3_200_000, 99_900)
	check(r["income_gate_active"] == true, "income gate should be active when stronghold below min")
	check(r["total"] == 0, "total should be 0 below sufficiency, got %d" % r["total"])
	check(r["service"] == 0, "service should be 0 below sufficiency, got %d" % r["service"])
	check(r["land"] == 0, "land should be 0 below sufficiency, got %d" % r["land"])
	check(r["tribute_in"] == 0, "tribute_in should be 0 below sufficiency (gate is total)")


func test_at_minimum_sufficiency_revenue_active() -> void:
	# At exactly the minimum, gate releases.
	var domain := {"peasant_families": 100, "tax_rate_cp_per_family": 200}
	var hexes: Array = [{"land_value": 5, "land_improvement_level": 0}]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 3_200_000, 3_200_000)
	check(r["income_gate_active"] == false, "gate releases at exactly minimum")
	check(r["total"] > 0, "revenue active at sufficiency")
