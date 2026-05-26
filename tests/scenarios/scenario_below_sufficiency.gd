extends "res://tests/scenarios/scenario_runner_base.gd"

## Scenario: Below Sufficiency — exercises 11B lifecycle income gate.
##
## Setup: a domain whose stronghold_value < classification minimum. Verify the
## income gate fires (revenue → 0; expenses still owed; growth doesn't happen).


func run_all_tests() -> void:
	cleanup_scenario()
	test_income_gate_active_when_stronghold_insufficient()
	cleanup_scenario()
	if not has_failures():
		print("Scenario.BelowSufficiency: all tests passed.")


func test_income_gate_active_when_stronghold_insufficient() -> void:
	seed_campaign("scenario_bs_camp")
	var ruler: String = seed_character("scenario_bs_ruler",
		{"alignment": "lawful"})
	var domain: String = seed_domain("scenario_bs_domain", ruler, {
		"territory_type": "borderlands",
		"peasant_families": 500,
		"alignment": "lawful",
	})
	seed_hexes(domain, 4, 5, 0)
	# Borderlands minimum = 75,000 gp = 7,500,000 cp.
	# Set stronghold value below that.
	var stronghold_value_cp: int = 3_000_000  # 30,000 gp — below 75,000 gp threshold
	var stronghold_minimum_cp: int = 7_500_000  # 75,000 gp
	var d: Dictionary = CampaignRepository.get_domain(domain)
	var hexes: Array = _list_hexes_for_domain(domain)
	var revenue: Dictionary = DomainRevenueCalculator.calculate_monthly_revenue(
		d, hexes, stronghold_value_cp, stronghold_minimum_cp, 0)
	check(bool(revenue.get("income_gate_active", false)),
		"income gate active when stronghold < classification minimum")
	check(int(revenue.get("total", -1)) == 0,
		"total revenue = 0 when income gate active; got %d" % int(revenue.get("total", -1)))
	# Expenses still include the 2gp/family universal min even when income gated.
	var expenses: Dictionary = DomainExpenseCalculator.calculate_monthly_expenses(
		d, 0, true)
	check(int(expenses.get("garrison", 0)) > 0,
		"garrison expense still owed when income gated; got %d"
		% int(expenses.get("garrison", 0)))
	# Growth doesn't proceed when income gated (per RAW §peasants_and_followers L108-109).
	var growth: Dictionary = DomainGrowthResolver.resolve_growth(
		d, 0, 0, DomainMoraleResolver.TIER_APATHETIC, false, true,
		func(_f: int, count: int, _e: bool) -> int: return count * 5)
	check(bool(growth.get("income_gate_active", false)),
		"growth resolver respects income_gate_active flag")
	check(int(growth.get("random_increase", -1)) == 0,
		"random_increase=0 under income gate; got %d"
		% int(growth.get("random_increase", -1)))
	check(int(growth.get("random_decrease", -1)) == 0,
		"random_decrease=0 under income gate; got %d"
		% int(growth.get("random_decrease", -1)))
