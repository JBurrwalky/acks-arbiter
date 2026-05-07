extends "res://tests/test_suite_base.gd"

## Unit tests for DomainGrowthResolver.
##
## Verifies RAW formulas from:
##   * `acore_axioms` §domain_growth.monthly_change L126-131 — 1d10 increase −
##     1d10 decrease per 1,000 families (rounded up), each exploding on 10s.
##   * §investments L132-135 — 1d10 per 1,000 gp invested, capped at
##     max(monthly_revenue, 1,000 gp).
##   * §active_adventuring_growth L138-149 — population-band table.
##   * §effects_of_morale L538-609 — Loyal +1d10/1000, ..., Stalwart +4d10/1000;
##     Demoralized -1d10, ..., Defiant -3d10; Rebellious halts random growth.
##
## Dice are injected via a deterministic stub so the resolver's math can be
## verified independently of RNG.


func run_all_tests() -> void:
	test_random_change_is_increase_minus_decrease()
	test_active_adventuring_band_for_small_population()
	test_active_adventuring_band_for_large_population()
	test_investment_cap_max_revenue_or_1000()
	test_morale_tier_loyal_adds_growth()
	test_morale_tier_demoralized_subtracts_growth()
	test_rebellious_halts_random_growth()
	test_income_gate_zeroes_random_growth()
	test_income_gate_keeps_active_adventuring()
	if not has_failures():
		print("DomainGrowthResolver: all tests passed.")


# A deterministic dice stub via lambda: returns count × per_die_value.
# (Inner-class Callables don't always round-trip cleanly across the resolver's
# `is_valid()` check, so the lambda form is the reliable injection path.)
func _stub_dice(per_die_value: int) -> Callable:
	return func(_faces: int, count: int, _exploding: bool) -> int:
		return count * per_die_value


# ----- Random change -----

func test_random_change_is_increase_minus_decrease() -> void:
	# Stub returns count × 3 for every roll. With 1,000 families → 1 group →
	# increase 1×3 = 3, decrease 1×3 = 3, net random = 0.
	var domain := {"peasant_families": 1000, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Apathetic", false, false, _stub_dice(3))
	check(g["random_increase"] == 3, "increase = 3, got %d" % g["random_increase"])
	check(g["random_decrease"] == 3, "decrease = 3, got %d" % g["random_decrease"])


# ----- Active adventuring -----

func test_active_adventuring_band_for_small_population() -> void:
	# 1-100 population → 5d20. Stub = count × 7 → 5 × 7 = 35.
	var domain := {"peasant_families": 50, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Apathetic", true, false, _stub_dice(7))
	check(g["active_adventuring_bonus"] == 35, "5d20 stub = 35, got %d" % g["active_adventuring_bonus"])


func test_active_adventuring_band_for_large_population() -> void:
	# 500+ population → 1d10. Stub = count × 7 → 1 × 7 = 7.
	var domain := {"peasant_families": 600, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Apathetic", true, false, _stub_dice(7))
	check(g["active_adventuring_bonus"] == 7, "1d10 stub = 7, got %d" % g["active_adventuring_bonus"])


# ----- Investment -----

func test_investment_cap_max_revenue_or_1000() -> void:
	# Revenue 500 gp, invest 5,000 gp. Cap = max(500, 1000) = 1000.
	# Allowed = min(5000, 1000) = 1000 → 1 group of 1d10. Stub = 1 × 4 = 4.
	var domain := {"peasant_families": 0, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 500, 5000, "Apathetic", false, false, _stub_dice(4))
	check(g["investment_bonus"] == 4, "investment cap to 1000gp → 1d10 = 4, got %d" % g["investment_bonus"])

	# Revenue 3000, invest 5000 → cap 3000 → 3 groups → 3 × 4 = 12.
	var g2 := DomainGrowthResolver.resolve_growth(
		domain, 3000, 5000, "Apathetic", false, false, _stub_dice(4))
	check(g2["investment_bonus"] == 12, "investment cap to 3000gp → 3d10 = 12, got %d" % g2["investment_bonus"])


# ----- Morale tier modifier -----

func test_morale_tier_loyal_adds_growth() -> void:
	# Loyal = +1d10 per 1,000 families. 1,000 fam → 1 die. Stub = 1 × 5 = 5.
	var domain := {"peasant_families": 1000, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Loyal", false, false, _stub_dice(5))
	# Random rolls also fire (Loyal != Rebellious, gate inactive). Stub gives
	# 1×5=5 for both increase and decrease, so net random = 0. The tier modifier
	# is what we're testing.
	check(g["morale_tier_modifier"] == 5, "Loyal +1d10 = 5, got %d" % g["morale_tier_modifier"])


func test_morale_tier_demoralized_subtracts_growth() -> void:
	# Demoralized = -1d10 per 1,000.
	var domain := {"peasant_families": 1000, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Demoralized", false, false, _stub_dice(5))
	check(g["morale_tier_modifier"] == -5, "Demoralized -1d10 = -5, got %d" % g["morale_tier_modifier"])


# ----- Rebellious halts -----

func test_rebellious_halts_random_growth() -> void:
	# Rebellious blocks random change; tier modifier ALSO is -4d10 per 1,000
	# but per the resolver, Rebellious halts random + still applies the tier
	# modifier (the rule "no population growth" is captured via halt + the
	# negative tier dice). For Phase 0 we treat Rebellious = halt + apply
	# tier dice (the population still loses families).
	var domain := {"peasant_families": 1000, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Rebellious", false, false, _stub_dice(5))
	check(g["growth_halted_by_morale"] == true, "Rebellious halts random growth")
	check(g["random_increase"] == 0, "random increase zeroed at Rebellious")
	check(g["random_decrease"] == 0, "random decrease zeroed at Rebellious")


# ----- Income gate -----

func test_income_gate_zeroes_random_growth() -> void:
	var domain := {"peasant_families": 1000, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Apathetic", false, true, _stub_dice(5))
	check(g["income_gate_active"] == true, "income gate echoed")
	check(g["random_increase"] == 0, "income gate zeroes random_increase")
	check(g["random_decrease"] == 0, "income gate zeroes random_decrease")
	check(g["morale_tier_modifier"] == 0, "income gate zeroes morale tier modifier")


func test_income_gate_keeps_active_adventuring() -> void:
	# Income gate active, but ruler is adventuring → adventuring bonus still
	# applies (RAW reads adventuring as independent of stronghold sufficiency).
	var domain := {"peasant_families": 50, "urban_families": 0}
	var g := DomainGrowthResolver.resolve_growth(
		domain, 0, 0, "Apathetic", true, true, _stub_dice(7))
	check(g["active_adventuring_bonus"] == 35, "active adventuring still applies under income gate, got %d" % g["active_adventuring_bonus"])
