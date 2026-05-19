extends "res://tests/test_suite_base.gd"

## Unit tests for DomainExpenseCalculator.
##
## Verifies RAW formulas from `acore_axioms_strongholds_and_domains.xml`
## §domain_expenses (L216-254), with all amounts in cp per the 2026-05-15
## currency-precision pass (1 gp = 100 cp):
##   * Garrison: max(actual_paid_cp, 200 cp/family universal minimum) per L218, L226
##   * Liturgies: domains.liturgy_rate_cp_per_family × peasants
##   * Maintenance: 100 cp/family (RAW 1 gp; constant MAINTENANCE_CP_PER_FAMILY)
##   * Tithes: 100 cp/family default (paid even by cleric/bladedancer rulers per L248)
##   * Tribute_out: domains.tribute_out_owed (cp)
##   * Repression: domains.repression_cp_per_family_this_month × peasants


func run_all_tests() -> void:
	test_garrison_universal_minimum_200cp_per_family()
	test_garrison_uses_actual_when_above_minimum()
	test_liturgy_uses_configured_rate()
	test_maintenance_is_100cp_per_family()
	test_tithe_uses_configured_rate()
	test_tribute_out_passes_through()
	test_repression_per_family_when_active()
	test_total_sums_subcategories()
	test_income_gate_keeps_garrison_zeros_others()
	if not has_failures():
		print("DomainExpenseCalculator: all tests passed.")


# ----- Garrison -----

func test_garrison_universal_minimum_200cp_per_family() -> void:
	# Ruler tries to pay 0 cp; the calculator clamps to 200 cp/family minimum.
	var domain := {"peasant_families": 100}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 0, false)
	check(e["garrison"] == 20_000,
		"garrison clamped to 200 cp × 100 fam = 20,000 cp, got %d" % e["garrison"])


func test_garrison_uses_actual_when_above_minimum() -> void:
	var domain := {"peasant_families": 100}
	# Ruler pays 35,000 cp (well above the 20,000 cp minimum).
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 35_000, false)
	check(e["garrison"] == 35_000,
		"garrison uses actual when above minimum, got %d" % e["garrison"])


# ----- Liturgies -----

func test_liturgy_uses_configured_rate() -> void:
	# 1 gp/family default = 100 cp/family. 100 families × 100 = 10,000 cp.
	var d1 := {"peasant_families": 100, "liturgy_rate_cp_per_family": 100}
	var e1 := DomainExpenseCalculator.calculate_monthly_expenses(d1, 20_000, false)
	check(e1["liturgy"] == 10_000,
		"liturgy at default 100 cp × 100 fam = 10,000 cp, got %d" % e1["liturgy"])

	# Ruler raises liturgy rate to 3 gp/family = 300 cp/family. 100 × 300 = 30,000 cp.
	var d2 := {"peasant_families": 100, "liturgy_rate_cp_per_family": 300}
	var e2 := DomainExpenseCalculator.calculate_monthly_expenses(d2, 20_000, false)
	check(e2["liturgy"] == 30_000,
		"liturgy at 300 cp × 100 fam = 30,000 cp, got %d" % e2["liturgy"])


# ----- Maintenance -----

func test_maintenance_is_100cp_per_family() -> void:
	var domain := {"peasant_families": 100}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 20_000, false)
	check(e["maintenance"] == 10_000,
		"maintenance is 100 cp × 100 fam = 10,000 cp, got %d" % e["maintenance"])


# ----- Tithes -----

func test_tithe_uses_configured_rate() -> void:
	var domain := {"peasant_families": 100, "tithe_rate_cp_per_family": 100}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 20_000, false)
	check(e["tithe"] == 10_000,
		"tithe at 100 cp × 100 fam = 10,000 cp, got %d" % e["tithe"])


# ----- Tribute -----

func test_tribute_out_passes_through() -> void:
	# tribute_out_owed is already cp (per the 2026-05-15 cp pass migration 111).
	var domain := {"peasant_families": 100, "tribute_out_owed": 25_000}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 20_000, false)
	check(e["tribute_out"] == 25_000, "tribute_out echoes 25,000 cp, got %d" % e["tribute_out"])


# ----- Repression -----

func test_repression_per_family_when_active() -> void:
	# Ruler sets repression at 2 gp/family = 200 cp/family. 100 × 200 = 20,000 cp.
	var domain := {"peasant_families": 100,
		"is_repressed_this_month": 1,
		"repression_cp_per_family_this_month": 200}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 20_000, false)
	check(e["repression"] == 20_000,
		"repression at 200 cp × 100 fam = 20,000 cp, got %d" % e["repression"])


# ----- Total -----

func test_total_sums_subcategories() -> void:
	# peasants 100; garrison_paid 25,000 cp; liturgy 100, tithe 100; tribute 5,000 cp.
	# garrison: max(25,000, 20,000) = 25,000
	# liturgy: 10,000
	# maintenance: 10,000
	# tithe: 10,000
	# tribute_out: 5,000
	# total: 60,000
	var domain := {"peasant_families": 100, "liturgy_rate_cp_per_family": 100,
		"tithe_rate_cp_per_family": 100, "tribute_out_owed": 5_000}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 25_000, false)
	check(e["total"] == 60_000, "total sums to 60,000 cp, got %d" % e["total"])


# ----- Income gate -----

func test_income_gate_keeps_garrison_zeros_others() -> void:
	var domain := {"peasant_families": 100, "liturgy_rate_cp_per_family": 100,
		"tithe_rate_cp_per_family": 100, "tribute_out_owed": 5_000}
	# income_gate_active=true: only garrison stays.
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 0, true)
	check(e["garrison"] == 20_000,
		"garrison still owed under income gate (20,000 cp), got %d" % e["garrison"])
	check(e["liturgy"] == 0, "liturgy zeroed under income gate, got %d" % e["liturgy"])
	check(e["maintenance"] == 0, "maintenance zeroed under income gate")
	check(e["tithe"] == 0, "tithe zeroed under income gate")
	check(e["tribute_out"] == 0, "tribute_out zeroed under income gate")
	check(e["repression"] == 0, "repression zeroed under income gate")
	check(e["total"] == 20_000,
		"total = garrison only when gate active, got %d" % e["total"])
