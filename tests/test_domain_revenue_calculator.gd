extends "res://tests/test_suite_base.gd"

## Unit tests for DomainRevenueCalculator.
##
## Verifies RAW formulas from `acore_axioms_strongholds_and_domains.xml`:
##   * Service revenue: 4 gp/peasant family flat (§domain_revenue.services L195)
##   * Tax revenue: domain.tax_rate_gp_per_family per family (§taxes L197-201)
##   * Land revenue: per-hex (land_value + land_improvement_gp) × families
##   * Tribute pass-through
##   * Income gate when stronghold_value < classification minimum
##     (§peasants_and_followers L108-109)


func run_all_tests() -> void:
	test_service_revenue_is_4_per_peasant()
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

func test_service_revenue_is_4_per_peasant() -> void:
	var domain := {"peasant_families": 100, "tax_rate_gp_per_family": 0}
	var hexes: Array = []
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 999, 0)
	check(r["service"] == 400, "service should be 100 fam × 4gp = 400, got %d" % r["service"])


# ----- Tax revenue -----

func test_tax_revenue_uses_configured_rate() -> void:
	var domain := {"peasant_families": 100, "tax_rate_gp_per_family": 3}
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, [], 999, 0)
	check(r["tax"] == 300, "tax should be 100 × 3 = 300, got %d" % r["tax"])

	var d2 := {"peasant_families": 50, "tax_rate_gp_per_family": 2}
	var r2 := DomainRevenueCalculator.calculate_monthly_revenue(d2, [], 999, 0)
	check(r2["tax"] == 100, "tax should be 50 × 2 = 100, got %d" % r2["tax"])


# ----- Land revenue (per-hex) -----

func test_land_revenue_per_hex() -> void:
	# Two hexes at land_value 5; 100 peasant families distributed evenly = 50/hex.
	# Each hex contributes 50 fam × 5 gp = 250 gp; total = 500.
	var domain := {"peasant_families": 100, "tax_rate_gp_per_family": 0}
	var hexes: Array = [
		{"land_value": 5, "land_improvement_gp": 0},
		{"land_value": 5, "land_improvement_gp": 0},
	]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 999, 0)
	check(r["land"] == 500, "land should be 500, got %d" % r["land"])


func test_land_improvement_adds_to_per_hex_value() -> void:
	# One hex at land_value 6 + improvement 2 = 8 effective gp/fam.
	# 100 peasant families × 8 = 800.
	var domain := {"peasant_families": 100, "tax_rate_gp_per_family": 0}
	var hexes: Array = [{"land_value": 6, "land_improvement_gp": 2}]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 999, 0)
	check(r["land"] == 800, "land should be 100 × (6+2) = 800, got %d" % r["land"])


# ----- Tribute pass-through -----

func test_tribute_in_passes_through() -> void:
	var domain := {"peasant_families": 0, "tax_rate_gp_per_family": 0}
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, [], 999, 0, 350)
	check(r["tribute_in"] == 350, "tribute_in echoes 350, got %d" % r["tribute_in"])
	check(r["total"] == 350, "total includes tribute_in only when no other revenue, got %d" % r["total"])


func test_total_is_sum_of_subcategories() -> void:
	# 100 peasant families, 1 hex at land_value 5, tax rate 2, tribute_in 50.
	# service: 100×4 = 400
	# tax: 100×2 = 200
	# land: 100×5 = 500
	# tribute: 50
	# total: 1150
	var domain := {"peasant_families": 100, "tax_rate_gp_per_family": 2}
	var hexes: Array = [{"land_value": 5, "land_improvement_gp": 0}]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 999, 0, 50)
	check(r["total"] == 1150, "total should sum to 1150, got %d" % r["total"])
	check(r["income_gate_active"] == false, "income gate should be inactive")


# ----- Income gate -----

func test_income_gate_zeroes_revenue() -> void:
	# Wilderness minimum is 32,000 gp per hex (here 1 hex). stronghold_value 0
	# < 32,000 → gate active → all revenue zero.
	var domain := {"peasant_families": 100, "tax_rate_gp_per_family": 2,
		"territory_type": "wilderness"}
	var hexes: Array = [{"land_value": 5, "land_improvement_gp": 0}]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 0, 32000, 999)
	check(r["income_gate_active"] == true, "income gate should be active when stronghold below min")
	check(r["total"] == 0, "total should be 0 below sufficiency, got %d" % r["total"])
	check(r["service"] == 0, "service should be 0 below sufficiency, got %d" % r["service"])
	check(r["land"] == 0, "land should be 0 below sufficiency, got %d" % r["land"])
	check(r["tribute_in"] == 0, "tribute_in should be 0 below sufficiency (gate is total)")


func test_at_minimum_sufficiency_revenue_active() -> void:
	# At exactly the minimum, gate releases.
	var domain := {"peasant_families": 100, "tax_rate_gp_per_family": 2}
	var hexes: Array = [{"land_value": 5, "land_improvement_gp": 0}]
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 32000, 32000)
	check(r["income_gate_active"] == false, "gate releases at exactly minimum")
	check(r["total"] > 0, "revenue active at sufficiency")
