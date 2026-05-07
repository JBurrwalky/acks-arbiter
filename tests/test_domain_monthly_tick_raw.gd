extends "res://tests/test_suite_base.gd"

## Phase 0 acceptance test for the domain monthly resolver chain.
##
## Verifies that the revenue / expense / morale / growth resolvers, when
## driven in handler-equivalent orchestration with deterministic fixtures,
## produce numbers matching the RAW benchmarks at
## `acore_axioms_strongholds_and_domains.xml` §domain_income L259-263:
##
##   * Wilderness  : revenue (Land 3-9 + Service 4 + Tax 2) - costs (Garrison 4
##                   + Liturgies 1 + Tithes 1 + Maint 1) ≈ +5 gp/family
##   * Borderlands : same revenue band; garrison 3 → income ≈ +6 gp/family
##   * Civilized   : same revenue band; garrison 2 → income ≈ +7 gp/family
##
## The per-classification garrison values come from the §additional_troops
## morale-incentive tiers; the universal RAW minimum is 2 gp/family per
## §garrison L218, L226. We pay each tier's recommended garrison so net income
## matches the benchmark table verbatim. With land_value fixed at 6 (the median
## 3d3 result, ≈5.6) all three benchmarks land within 1 gp of the §domain_income
## targets — the tolerance below allows for the 3-9 land-value spread.
##
## Stochastic components (morale roll, random growth, random event) are tested
## in their dedicated unit-test files; this integration suite exercises only
## the deterministic pipeline so the benchmark numbers are reproducible across
## runs without dice stubbing the handler.


const HEXES_PER_DOMAIN := 8
const FAMILIES_PER_DOMAIN := 1000  # 125 fam/hex × 8 hexes — wilderness saturation
const LAND_VALUE_FIXTURE := 6  # near-median of 3d3
const TAX_RATE := 2
const LITURGY_RATE := 1
const TITHE_RATE := 1


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
	# Garrison spend per L260 wilderness column = 4 gp/fam (morale-incentive tier).
	var bundle := _resolve_one_month("wilderness", FAMILIES_PER_DOMAIN * 4, true)
	# Revenue: 1000 × (6 + 4 + 2) = 12,000
	# Expense: 1000 × (4 + 1 + 1 + 1) = 7,000
	# Net:     5,000  → 5 gp/fam
	check(bundle.revenue == 12000, "wilderness revenue 12000, got %d" % bundle.revenue)
	check(bundle.expenses == 7000, "wilderness expenses 7000, got %d" % bundle.expenses)
	check(bundle.net == 5000, "wilderness net 5000, got %d" % bundle.net)
	check(bundle.net_per_family == 5, "wilderness ≈5 gp/fam, got %d" % bundle.net_per_family)


func test_borderlands_benchmark() -> void:
	# Garrison spend per L261 borderlands column = 3 gp/fam.
	var bundle := _resolve_one_month("borderlands", FAMILIES_PER_DOMAIN * 3, true)
	# Revenue: 12,000; Expense: 1000 × (3 + 1 + 1 + 1) = 6,000; Net: 6,000.
	check(bundle.revenue == 12000, "borderlands revenue 12000, got %d" % bundle.revenue)
	check(bundle.expenses == 6000, "borderlands expenses 6000, got %d" % bundle.expenses)
	check(bundle.net == 6000, "borderlands net 6000, got %d" % bundle.net)
	check(bundle.net_per_family == 6, "borderlands ≈6 gp/fam, got %d" % bundle.net_per_family)


func test_civilized_benchmark() -> void:
	# Garrison spend per L262 civilized column = 2 gp/fam (universal minimum).
	var bundle := _resolve_one_month("civilized", FAMILIES_PER_DOMAIN * 2, true)
	# Revenue: 12,000; Expense: 1000 × (2 + 1 + 1 + 1) = 5,000; Net: 7,000.
	check(bundle.revenue == 12000, "civilized revenue 12000, got %d" % bundle.revenue)
	check(bundle.expenses == 5000, "civilized expenses 5000, got %d" % bundle.expenses)
	check(bundle.net == 7000, "civilized net 7000, got %d" % bundle.net)
	check(bundle.net_per_family == 7, "civilized ≈7 gp/fam, got %d" % bundle.net_per_family)


# ----- Income gate -----

func test_income_gate_blocks_revenue_below_sufficiency() -> void:
	# Wilderness with stronghold value 0 (vs. 32k/hex × 8 hex = 256k minimum).
	var bundle := _resolve_one_month("wilderness", FAMILIES_PER_DOMAIN * 4, false)
	check(bundle.revenue == 0, "revenue zeroed below sufficiency, got %d" % bundle.revenue)
	check(bundle.income_gate_active == true, "income gate active")


func test_income_gate_garrison_still_owed() -> void:
	# Even with revenue zeroed, the universal 2 gp/family garrison minimum
	# applies — the ruler can still pay above it (we pass 4gp/fam wilderness),
	# and the calculator records what they paid (max(actual, minimum)).
	var bundle := _resolve_one_month("wilderness", FAMILIES_PER_DOMAIN * 4, false)
	check(bundle.expenses == FAMILIES_PER_DOMAIN * 4,
		"garrison still 4 gp/fam × 1000 = 4000, got %d" % bundle.expenses)


# ----- Stability across months -----

func test_twelve_month_stability() -> void:
	# Resolve the same fixture 12 times and verify the deterministic numbers
	# (revenue, expenses, net) are identical each month — no drift, no
	# accumulation bug. Morale roll and random growth are stochastic and
	# verified in dedicated unit tests; here we confirm the deterministic
	# pipeline is steady.
	var first := _resolve_one_month("borderlands", FAMILIES_PER_DOMAIN * 3, true)
	for i in range(11):
		var nth := _resolve_one_month("borderlands", FAMILIES_PER_DOMAIN * 3, true)
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
## with a fixture domain at the given classification + garrison spend.
## sufficiency_met=true means the stronghold value is at the per-classification
## minimum (income gate inactive); false means below sufficiency (gate closes).
func _resolve_one_month(territory_type: String, garrison_paid_gp: int,
		sufficiency_met: bool) -> Dictionary:
	var domain := _make_domain_fixture(territory_type)
	var hexes := _make_hex_fixture()

	# Per-classification minimum per §minimum_stronghold_value L88-94 × 8 hexes.
	var per_hex_min := _per_hex_minimum_for(territory_type)
	var sh_minimum: int = per_hex_min * HEXES_PER_DOMAIN
	var sh_value: int = sh_minimum if sufficiency_met else 0

	var revenue := DomainRevenueCalculator.calculate_monthly_revenue(
		domain, hexes, sh_value, sh_minimum, 0)
	var expenses := DomainExpenseCalculator.calculate_monthly_expenses(
		domain, garrison_paid_gp, revenue["income_gate_active"])

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
		"tax_rate_gp_per_family": TAX_RATE,
		"liturgy_rate_gp_per_family": LITURGY_RATE,
		"tithe_rate_gp_per_family": TITHE_RATE,
		"tribute_out_owed": 0,
		"is_repressed_this_month": 0,
		"repression_gp_per_family_this_month": 0,
	}


func _make_hex_fixture() -> Array:
	var hexes: Array = []
	for q in range(HEXES_PER_DOMAIN):
		hexes.append({
			"hex_q": q,
			"hex_r": 0,
			"land_value": LAND_VALUE_FIXTURE,
			"land_improvement_gp": 0,
		})
	return hexes


func _per_hex_minimum_for(territory_type: String) -> int:
	match territory_type:
		"civilized":   return 15000
		"borderlands": return 22500
		_:             return 32000  # wilderness default
