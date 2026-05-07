extends "res://tests/test_suite_base.gd"

## Unit tests for DomainExpenseCalculator.
##
## Verifies RAW formulas from `acore_axioms_strongholds_and_domains.xml`
## §domain_expenses (L216-254):
##   * Garrison: max(actual_paid, 2 gp/family universal minimum) per L218, L226
##   * Liturgies: domains.liturgy_rate_gp_per_family × peasants
##   * Maintenance: 1 gp/family
##   * Tithes: 1 gp/family (paid even by cleric/bladedancer rulers per L248)
##   * Tribute_out: domains.tribute_out_owed
##   * Repression: domains.repression_gp_per_family_this_month × peasants


func run_all_tests() -> void:
	test_garrison_universal_minimum_2gp_per_family()
	test_garrison_uses_actual_when_above_minimum()
	test_liturgy_uses_configured_rate()
	test_maintenance_is_1gp_per_family()
	test_tithe_uses_configured_rate()
	test_tribute_out_passes_through()
	test_repression_per_family_when_active()
	test_total_sums_subcategories()
	test_income_gate_keeps_garrison_zeros_others()
	if not has_failures():
		print("DomainExpenseCalculator: all tests passed.")


# ----- Garrison -----

func test_garrison_universal_minimum_2gp_per_family() -> void:
	# Ruler tries to pay 0 gp; the calculator clamps to 2 gp/family minimum.
	var domain := {"peasant_families": 100}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 0, false)
	check(e["garrison"] == 200, "garrison clamped to 2 gp × 100 fam = 200, got %d" % e["garrison"])


func test_garrison_uses_actual_when_above_minimum() -> void:
	var domain := {"peasant_families": 100}
	# Ruler pays 350 gp (well above the 200 gp minimum).
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 350, false)
	check(e["garrison"] == 350, "garrison uses actual when above minimum, got %d" % e["garrison"])


# ----- Liturgies -----

func test_liturgy_uses_configured_rate() -> void:
	var d1 := {"peasant_families": 100, "liturgy_rate_gp_per_family": 1}
	var e1 := DomainExpenseCalculator.calculate_monthly_expenses(d1, 200, false)
	check(e1["liturgy"] == 100, "liturgy at default 1 gp × 100 fam = 100, got %d" % e1["liturgy"])

	var d2 := {"peasant_families": 100, "liturgy_rate_gp_per_family": 3}
	var e2 := DomainExpenseCalculator.calculate_monthly_expenses(d2, 200, false)
	check(e2["liturgy"] == 300, "liturgy at 3 gp × 100 fam = 300, got %d" % e2["liturgy"])


# ----- Maintenance -----

func test_maintenance_is_1gp_per_family() -> void:
	var domain := {"peasant_families": 100}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 200, false)
	check(e["maintenance"] == 100, "maintenance is 1 gp × 100 fam = 100, got %d" % e["maintenance"])


# ----- Tithes -----

func test_tithe_uses_configured_rate() -> void:
	var domain := {"peasant_families": 100, "tithe_rate_gp_per_family": 1}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 200, false)
	check(e["tithe"] == 100, "tithe at 1 gp × 100 fam = 100, got %d" % e["tithe"])


# ----- Tribute -----

func test_tribute_out_passes_through() -> void:
	var domain := {"peasant_families": 100, "tribute_out_owed": 250}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 200, false)
	check(e["tribute_out"] == 250, "tribute_out echoes 250, got %d" % e["tribute_out"])


# ----- Repression -----

func test_repression_per_family_when_active() -> void:
	var domain := {"peasant_families": 100,
		"is_repressed_this_month": 1,
		"repression_gp_per_family_this_month": 2}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 200, false)
	check(e["repression"] == 200, "repression at 2 gp × 100 fam = 200, got %d" % e["repression"])


# ----- Total -----

func test_total_sums_subcategories() -> void:
	# peasants 100; garrison_paid 250; liturgy 1, tithe 1; tribute 50; repression 0
	# garrison: max(250, 200) = 250; liturgy: 100; maintenance: 100; tithe: 100;
	# tribute_out: 50 → total 600
	var domain := {"peasant_families": 100, "liturgy_rate_gp_per_family": 1,
		"tithe_rate_gp_per_family": 1, "tribute_out_owed": 50}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 250, false)
	check(e["total"] == 600, "total sums to 600, got %d" % e["total"])


# ----- Income gate -----

func test_income_gate_keeps_garrison_zeros_others() -> void:
	var domain := {"peasant_families": 100, "liturgy_rate_gp_per_family": 1,
		"tithe_rate_gp_per_family": 1, "tribute_out_owed": 50}
	# income_gate_active=true: only garrison stays.
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 0, true)
	check(e["garrison"] == 200, "garrison still owed under income gate (200), got %d" % e["garrison"])
	check(e["liturgy"] == 0, "liturgy zeroed under income gate, got %d" % e["liturgy"])
	check(e["maintenance"] == 0, "maintenance zeroed under income gate")
	check(e["tithe"] == 0, "tithe zeroed under income gate")
	check(e["tribute_out"] == 0, "tribute_out zeroed under income gate")
	check(e["repression"] == 0, "repression zeroed under income gate")
	check(e["total"] == 200, "total = garrison only when gate active, got %d" % e["total"])
