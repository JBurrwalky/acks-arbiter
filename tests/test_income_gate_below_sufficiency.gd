extends "res://tests/test_suite_base.gd"

## Unit tests for the income gate below stronghold sufficiency.
##
## RAW: `acore_axioms_strongholds_and_domains.xml` §peasants_and_followers L108-109:
##   "Peasants begin generating income and incurring costs only once the
##    stronghold is sufficient to secure the domain. Before the stronghold is
##    sufficient, the domain does not generate money and does not grow."
##
## Phase 0 implementation:
##   * DomainRevenueCalculator zeros all revenue subcategories when
##     stronghold_value < classification_minimum.
##   * DomainExpenseCalculator keeps the 2 gp/family garrison minimum but
##     zeros liturgy / maintenance / tithe / tribute_out / repression.
##   * DomainGrowthResolver zeros random change AND morale-tier modifier;
##     active-adventuring and investment are unaffected (RAW reads them as
##     independent of sufficiency — the ruler's exploits / pre-9 investments
##     attract families regardless per L121).


func run_all_tests() -> void:
	test_revenue_zeroed_below_sufficiency()
	test_expense_keeps_garrison_zeros_others()
	test_growth_random_zeroed_below_sufficiency()
	test_growth_morale_tier_zeroed_below_sufficiency()
	test_growth_active_adventuring_unaffected()
	test_gate_releases_at_sufficiency()
	if not has_failures():
		print("IncomeGateBelowSufficiency: all tests passed.")


# Deterministic dice stub via lambda: returns count × 5 for every call.
func _stub() -> Callable:
	return func(_faces: int, count: int, _exploding: bool) -> int:
		return count * 5


# ----- Revenue -----

func test_revenue_zeroed_below_sufficiency() -> void:
	var domain := {"peasant_families": 100, "tax_rate_gp_per_family": 2,
		"territory_type": "wilderness"}
	var hexes: Array = [{"land_value": 5, "land_improvement_gp": 0}]
	# Wilderness minimum: 32,000 gp/hex × 1 hex = 32,000. Value 0 ⇒ gate active.
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 0, 32000, 999)
	check(r["income_gate_active"] == true, "gate active below sufficiency")
	check(r["total"] == 0, "total = 0 below sufficiency, got %d" % r["total"])


# ----- Expense -----

func test_expense_keeps_garrison_zeros_others() -> void:
	var domain := {"peasant_families": 100, "liturgy_rate_gp_per_family": 1,
		"tithe_rate_gp_per_family": 1, "tribute_out_owed": 50}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 0, true)
	check(e["garrison"] == 200, "garrison still owed at 2 gp/fam × 100 fam = 200, got %d" % e["garrison"])
	check(e["liturgy"] == 0, "liturgy zeroed under gate")
	check(e["maintenance"] == 0, "maintenance zeroed under gate")
	check(e["tithe"] == 0, "tithe zeroed under gate")
	check(e["tribute_out"] == 0, "tribute_out zeroed under gate")
	check(e["repression"] == 0, "repression zeroed under gate")
	check(e["total"] == 200, "total = garrison only, got %d" % e["total"])


# ----- Growth -----

func test_growth_random_zeroed_below_sufficiency() -> void:
	var domain := {"peasant_families": 1000, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Apathetic", false, true, _stub())
	check(g["random_increase"] == 0, "random_increase zeroed")
	check(g["random_decrease"] == 0, "random_decrease zeroed")


func test_growth_morale_tier_zeroed_below_sufficiency() -> void:
	# Even at Loyal (+1d10/1000 normally), gate zeros the tier modifier.
	var domain := {"peasant_families": 1000, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Loyal", false, true, _stub())
	check(g["morale_tier_modifier"] == 0, "morale tier modifier zeroed under gate, got %d" % g["morale_tier_modifier"])


func test_growth_active_adventuring_unaffected() -> void:
	var domain := {"peasant_families": 50, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Apathetic", true, true, _stub())
	# Active adventuring at 1-100 pop = 5d20. Stub = count × 5 = 25.
	check(g["active_adventuring_bonus"] == 25, "active adventuring still applies, got %d" % g["active_adventuring_bonus"])


# ----- Gate release -----

func test_gate_releases_at_sufficiency() -> void:
	var domain := {"peasant_families": 100, "tax_rate_gp_per_family": 2}
	var hexes: Array = [{"land_value": 5, "land_improvement_gp": 0}]
	# At exactly the minimum, gate is inactive.
	var r := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 32000, 32000)
	check(r["income_gate_active"] == false, "gate releases at minimum")
	check(r["total"] > 0, "revenue active at minimum")
