extends "res://tests/test_suite_base.gd"

## Phase 0 acceptance test for the domain monthly resolver chain.
##
## Verifies that the revenue / expense / morale / growth resolvers, when
## driven in handler-equivalent orchestration with deterministic fixtures,
## produce numbers matching the RAW benchmarks at
## `acore_axioms_strongholds_and_domains.xml` §domain_income L259-263.
##
## 2026-05-15 currency-precision pass: all amounts are cp (1 gp = 100 cp).
## RAW benchmarks (gp) × 100 = the cp expectations below.
##
##   * Wilderness  : revenue (Land 3-9 + Service 4 + Tax 2) - costs (Garrison 4
##                   + Liturgies 1 + Tithes 1 + Maint 1) ≈ +5 gp/family
##   * Borderlands : same revenue band; garrison 3 → income ≈ +6 gp/family
##   * Civilized   : same revenue band; garrison 2 → income ≈ +7 gp/family
##
## The per-classification garrison values come from the §additional_troops
## morale-incentive tiers; the universal RAW minimum is 2 gp/family per
## §garrison L218, L226.


const HEXES_PER_DOMAIN := 8
const FAMILIES_PER_DOMAIN := 1000  # 125 fam/hex × 8 hexes — wilderness saturation
const LAND_VALUE_FIXTURE := 6  # near-median of 3d3
const TAX_RATE_CP := 200      # RAW 2 gp/family
const LITURGY_RATE_CP := 100  # RAW 1 gp/family
const TITHE_RATE_CP := 100    # RAW 1 gp/family


func run_all_tests() -> void:
	test_wilderness_benchmark()
	test_borderlands_benchmark()
	test_civilized_benchmark()
	test_income_gate_blocks_revenue_below_sufficiency()
	test_income_gate_garrison_still_owed()
	test_twelve_month_stability()
	if not has_failures():
		print("DomainMonthlyTickRaw: all tests passed.")


# ----- Per-classification benchmarks per §domain_income L259-263 -----

func test_wilderness_benchmark() -> void:
	# Garrison spend per L260 wilderness column = 4 gp/fam = 400 cp/fam.
	var bundle := _resolve_one_month("wilderness", FAMILIES_PER_DOMAIN * 400, true)
	# Revenue: 1000 × (6 + 4 + 2) gp = 12,000 gp = 1,200,000 cp
	# Expense: 1000 × (4 + 1 + 1 + 1) gp = 7,000 gp = 700,000 cp
	# Net:     500,000 cp = 5 gp/fam
	check(bundle.revenue == 1_200_000, "wilderness revenue 1,200,000 cp, got %d" % bundle.revenue)
	check(bundle.expenses == 700_000, "wilderness expenses 700,000 cp, got %d" % bundle.expenses)
	check(bundle.net == 500_000, "wilderness net 500,000 cp, got %d" % bundle.net)
	check(bundle.net_per_family == 500, "wilderness ≈500 cp/fam (= 5 gp/fam), got %d" % bundle.net_per_family)


func test_borderlands_benchmark() -> void:
	# Garrison spend per L261 borderlands column = 3 gp/fam = 300 cp/fam.
	var bundle := _resolve_one_month("borderlands", FAMILIES_PER_DOMAIN * 300, true)
	# Revenue: 1,200,000 cp; Expense: 1000 × (3 + 1 + 1 + 1) gp = 6,000 gp = 600,000 cp.
	check(bundle.revenue == 1_200_000, "borderlands revenue 1,200,000 cp, got %d" % bundle.revenue)
	check(bundle.expenses == 600_000, "borderlands expenses 600,000 cp, got %d" % bundle.expenses)
	check(bundle.net == 600_000, "borderlands net 600,000 cp, got %d" % bundle.net)
	check(bundle.net_per_family == 600, "borderlands ≈600 cp/fam (= 6 gp/fam), got %d" % bundle.net_per_family)


func test_civilized_benchmark() -> void:
	# Garrison spend per L262 civilized column = 2 gp/fam = 200 cp/fam (universal minimum).
	var bundle := _resolve_one_month("civilized", FAMILIES_PER_DOMAIN * 200, true)
	# Revenue: 1,200,000 cp; Expense: 1000 × (2 + 1 + 1 + 1) gp = 5,000 gp = 500,000 cp.
	check(bundle.revenue == 1_200_000, "civilized revenue 1,200,000 cp, got %d" % bundle.revenue)
	check(bundle.expenses == 500_000, "civilized expenses 500,000 cp, got %d" % bundle.expenses)
	check(bundle.net == 700_000, "civilized net 700,000 cp, got %d" % bundle.net)
	check(bundle.net_per_family == 700, "civilized ≈700 cp/fam (= 7 gp/fam), got %d" % bundle.net_per_family)


# ----- Income gate -----

func test_income_gate_blocks_revenue_below_sufficiency() -> void:
	# Wilderness with stronghold value 0 (vs. 32,000 gp/hex × 8 hex = 25,600,000 cp minimum).
	var bundle := _resolve_one_month("wilderness", FAMILIES_PER_DOMAIN * 400, false)
	check(bundle.revenue == 0, "revenue zeroed below sufficiency, got %d" % bundle.revenue)
	check(bundle.income_gate_active == true, "income gate active")


func test_income_gate_garrison_still_owed() -> void:
	# Even with revenue zeroed, the universal 2 gp/family garrison minimum
	# applies — the ruler can still pay above it (we pass 4 gp/fam wilderness = 400 cp/fam),
	# and the calculator records what they paid (max(actual, minimum)).
	var bundle := _resolve_one_month("wilderness", FAMILIES_PER_DOMAIN * 400, false)
	check(bundle.expenses == FAMILIES_PER_DOMAIN * 400,
		"garrison still 400 cp/fam × 1000 = 400,000 cp, got %d" % bundle.expenses)


# ----- Stability across months -----

func test_twelve_month_stability() -> void:
	# Resolve the same fixture 12 times and verify the deterministic numbers
	# (revenue, expenses, net) are identical each month.
	var first := _resolve_one_month("borderlands", FAMILIES_PER_DOMAIN * 300, true)
	for i in range(11):
		var nth := _resolve_one_month("borderlands", FAMILIES_PER_DOMAIN * 300, true)
		check(nth.revenue == first.revenue,
			"month %d revenue drifted: %d vs %d" % [i + 2, nth.revenue, first.revenue])
		check(nth.expenses == first.expenses,
			"month %d expenses drifted: %d vs %d" % [i + 2, nth.expenses, first.expenses])
		check(nth.net == first.net,
			"month %d net drifted: %d vs %d" % [i + 2, nth.net, first.net])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Drive the deterministic resolver chain (revenue + expenses) for one month
## with a fixture domain at the given classification + garrison spend (cp).
## sufficiency_met=true means the stronghold value is at the per-classification
## minimum (income gate inactive); false means below sufficiency (gate closes).
func _resolve_one_month(territory_type: String, garrison_paid_cp: int,
		sufficiency_met: bool) -> Dictionary:
	var domain := _make_domain_fixture(territory_type)
	var hexes := _make_hex_fixture()

	# Per-classification minimum (cp) per §minimum_stronghold_value L88-94 × 8 hexes.
	var per_hex_min_cp := _per_hex_minimum_cp_for(territory_type)
	var sh_minimum_cp: int = per_hex_min_cp * HEXES_PER_DOMAIN
	var sh_value_cp: int = sh_minimum_cp if sufficiency_met else 0

	var revenue := DomainRevenueCalculator.calculate_monthly_revenue(
		domain, hexes, sh_value_cp, sh_minimum_cp, 0)
	var expenses := DomainExpenseCalculator.calculate_monthly_expenses(
		domain, garrison_paid_cp, revenue["income_gate_active"])

	var peasants: int = int(domain.get("peasant_families", 1))
	var net: int = int(revenue["total"]) - int(expenses["total"])
	return {
		"revenue": revenue["total"],
		"revenue_breakdown": revenue,
		"expenses": expenses["total"],
		"expense_breakdown": expenses,
		"net": net,
		"net_per_family": net / peasants if peasants > 0 else 0,
		"income_gate_active": revenue["income_gate_active"],
	}


func _make_domain_fixture(territory_type: String) -> Dictionary:
	return {
		"id": "fixture_domain",
		"territory_type": territory_type,
		"alignment": "neutral",
		"peasant_families": FAMILIES_PER_DOMAIN,
		"urban_families": 0,
		"morale": 0,
		"tax_rate_cp_per_family": TAX_RATE_CP,
		"liturgy_rate_cp_per_family": LITURGY_RATE_CP,
		"tithe_rate_cp_per_family": TITHE_RATE_CP,
		"tribute_out_owed": 0,
		"is_repressed_this_month": 0,
		"repression_cp_per_family_this_month": 0,
	}


func _make_hex_fixture() -> Array:
	var hexes: Array = []
	for q in range(HEXES_PER_DOMAIN):
		hexes.append({
			"hex_q": q,
			"hex_r": 0,
			"land_value": LAND_VALUE_FIXTURE,
			"land_improvement_level": 0,
		})
	return hexes


## Per-hex stronghold minimum in cp (RAW × 100).
func _per_hex_minimum_cp_for(territory_type: String) -> int:
	match territory_type:
		"civilized":   return 1_500_000   # RAW 15,000 gp
		"borderlands": return 2_250_000   # RAW 22,500 gp
		_:             return 3_200_000   # RAW 32,000 gp (wilderness default)
