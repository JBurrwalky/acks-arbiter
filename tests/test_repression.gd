extends "res://tests/test_suite_base.gd"

## Unit tests for repression mechanics.
##
## Cuts across DomainExpenseCalculator (repression line) and
## DomainMoraleResolver (repression cap on current_morale ≤ 0).
##
## RAW: `acore_axioms_strongholds_and_domains.xml` §repression L510-516 and
## §monthly_event_modifiers L488-491:
##   * 1 gp/family of additional repressing troops → +1 morale roll bonus
##   * 2 gp/family → +2; each additional gp/family → +1 more
##   * Current morale cannot exceed 0 while repressed
##   * (Militia ineligibility flag is enforced by Phase 3's activity handler,
##      not by these resolvers; not exercised here.)


func run_all_tests() -> void:
	test_repression_expense_line_when_active()
	test_repression_zero_when_not_active()
	test_current_morale_capped_at_0_when_repressed()
	test_current_morale_not_capped_when_not_repressed()
	test_repression_cap_overrides_high_natural_roll()
	test_capped_by_repression_flag_set()
	if not has_failures():
		print("Repression: all tests passed.")


# ----- Expense -----

func test_repression_expense_line_when_active() -> void:
	# 100 peasant families, 3 gp/family of repression → 300 gp/month.
	var domain := {"peasant_families": 100,
		"is_repressed_this_month": 1,
		"repression_gp_per_family_this_month": 3}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 200, false)
	check(e["repression"] == 300, "repression = 100 × 3 = 300, got %d" % e["repression"])


func test_repression_zero_when_not_active() -> void:
	var domain := {"peasant_families": 100,
		"is_repressed_this_month": 0,
		"repression_gp_per_family_this_month": 0}
	var e := DomainExpenseCalculator.calculate_monthly_expenses(domain, 200, false)
	check(e["repression"] == 0, "no repression line when inactive, got %d" % e["repression"])


# ----- Morale cap -----

func test_current_morale_capped_at_0_when_repressed() -> void:
	# Prior current = 0; base = 0; +5 modifiers + roll 12 would push to +2,
	# but repression caps at 0.
	var domain := {"morale": 0}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 0, 5, 0, true, 12)
	check(m["current_morale"] == 0, "capped at 0 while repressed, got %d" % m["current_morale"])
	check(m["capped_by_repression"] == true, "capped_by_repression flag set")


func test_current_morale_not_capped_when_not_repressed() -> void:
	var domain := {"morale": 0}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 0, 5, 0, false, 12)
	check(m["current_morale"] == 2, "natural 12 → +2 when not repressed, got %d" % m["current_morale"])
	check(m["capped_by_repression"] == false, "capped_by_repression flag false")


func test_repression_cap_overrides_high_natural_roll() -> void:
	# Even with +3 repression bonus and roll 11 (which would shift +1), the cap
	# clamps at 0 since repression is active.
	var domain := {"morale": -1}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 0, 0, 3, true, 11)
	check(m["current_morale"] <= 0, "current_morale capped ≤ 0 while repressed, got %d" % m["current_morale"])
	check(m["adjusted_roll"] == 14, "adjusted_roll includes repression_bonus 3, got %d" % m["adjusted_roll"])


func test_capped_by_repression_flag_set() -> void:
	# When the cap actually fires, the flag is set; when it doesn't (because
	# the morale was already ≤ 0), the flag is not set.
	var domain := {"morale": -2}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 0, 0, 0, true, 7)
	# Drift toward base 0 from -2: +1 → -1. Not capped (already ≤ 0).
	check(m["current_morale"] == -1, "drift to -1 (still under cap)")
	check(m["capped_by_repression"] == false, "flag false: cap didn't have to fire")
