extends "res://tests/test_suite_base.gd"

## Unit tests for AbstractTributeResolver.
##
## Coverage:
##   * Per-title rates match expected RAW averages (within 1 cp of bankers
##     rounding).
##   * No tribute when liege_domain_id is null/empty.
##   * No tribute when peasant_families is 0.
##   * Owned domains fall through to the TributeCalculator path.
##   * Unrecognized realm_title returns 0 (defensive default).


func run_all_tests() -> void:
	test_per_family_rates_by_title()
	test_abstract_baron_tribute()
	test_abstract_marquis_tribute()
	test_no_liege_returns_zero()
	test_zero_families_returns_zero()
	test_unknown_title_returns_zero()
	test_owned_domain_uses_tribute_calculator()
	if not has_failures():
		print("AbstractTributeResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Per-family rates
# ---------------------------------------------------------------------------

func test_per_family_rates_by_title() -> void:
	# Expected cp/family computed from RAW average gp / average families,
	# then × 100 cp/gp, banker's-rounded (round half to even).
	#   Baron:   2.125    × 100 = 212.5    → 212 (half-to-even)
	#   Marquis: 1.0667   × 100 = 106.67   → 107
	#   Count:   0.5615   × 100 =  56.15   →  56
	#   Duke:    0.2708   × 100 =  27.08   →  27
	#   Prince:  0.1317   × 100 =  13.17   →  13
	#   King:    0.0727   × 100 =   7.27   →   7
	check(AbstractTributeResolver.per_family_rate_cp("Baron") == 212,
		"Baron rate cp/family: expected 212, got %d" % AbstractTributeResolver.per_family_rate_cp("Baron"))
	check(AbstractTributeResolver.per_family_rate_cp("Marquis") == 107,
		"Marquis rate cp/family: expected 107, got %d" % AbstractTributeResolver.per_family_rate_cp("Marquis"))
	check(AbstractTributeResolver.per_family_rate_cp("Count") == 56,
		"Count rate cp/family: expected 56, got %d" % AbstractTributeResolver.per_family_rate_cp("Count"))
	check(AbstractTributeResolver.per_family_rate_cp("Duke") == 27,
		"Duke rate cp/family: expected 27, got %d" % AbstractTributeResolver.per_family_rate_cp("Duke"))
	check(AbstractTributeResolver.per_family_rate_cp("Prince") == 13,
		"Prince rate cp/family: expected 13, got %d" % AbstractTributeResolver.per_family_rate_cp("Prince"))
	check(AbstractTributeResolver.per_family_rate_cp("King") == 7,
		"King rate cp/family: expected 7, got %d" % AbstractTributeResolver.per_family_rate_cp("King"))
	print("  per_family_rates_by_title: OK")


# ---------------------------------------------------------------------------
# Sample inputs
# ---------------------------------------------------------------------------

func test_abstract_baron_tribute() -> void:
	# 160 families × 2.125 gp/family × 100 cp/gp = 34,000 cp exactly.
	var domain := {
		"realm_title": "Baron",
		"peasant_families": 160,
		"liege_domain_id": "domain_marquis_001",
		"owner_character_id": null,
	}
	var got: int = AbstractTributeResolver.compute_tribute_owed(domain)
	check(got == 34000,
		"abstract Baron 160 families: expected 34000 cp, got %d" % got)
	print("  abstract_baron_tribute: OK")


func test_abstract_marquis_tribute() -> void:
	# 320 families × 1.0667 gp/family × 100 cp/gp = 34,134.4 → bankers-round 34134.
	var domain := {
		"realm_title": "Marquis",
		"peasant_families": 320,
		"liege_domain_id": "domain_count_001",
		"owner_character_id": null,
	}
	var got: int = AbstractTributeResolver.compute_tribute_owed(domain)
	check(got == 34134,
		"abstract Marquis 320 families: expected 34134 cp, got %d" % got)
	print("  abstract_marquis_tribute: OK")


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

func test_no_liege_returns_zero() -> void:
	var domain := {
		"realm_title": "Prince",
		"peasant_families": 7500,
		"liege_domain_id": null,
		"owner_character_id": null,
	}
	check(AbstractTributeResolver.compute_tribute_owed(domain) == 0,
		"no liege should yield 0 tribute")
	var domain2 := {
		"realm_title": "Prince",
		"peasant_families": 7500,
		"liege_domain_id": "",
		"owner_character_id": null,
	}
	check(AbstractTributeResolver.compute_tribute_owed(domain2) == 0,
		"empty liege should yield 0 tribute")
	print("  no_liege_returns_zero: OK")


func test_zero_families_returns_zero() -> void:
	var domain := {
		"realm_title": "Baron",
		"peasant_families": 0,
		"liege_domain_id": "domain_marquis_001",
		"owner_character_id": null,
	}
	check(AbstractTributeResolver.compute_tribute_owed(domain) == 0,
		"zero families should yield 0 tribute")
	print("  zero_families_returns_zero: OK")


func test_unknown_title_returns_zero() -> void:
	var domain := {
		"realm_title": "Bogus",
		"peasant_families": 100,
		"liege_domain_id": "domain_marquis_001",
		"owner_character_id": null,
	}
	check(AbstractTributeResolver.compute_tribute_owed(domain) == 0,
		"unknown title should yield 0 tribute")
	print("  unknown_title_returns_zero: OK")


func test_owned_domain_uses_tribute_calculator() -> void:
	# Owned 780-family Count: tribute_base_gp = 18 × 780^0.6.
	# 780^0.6 ≈ 53.83, × 18 ≈ 968.94, banker-rounded ≈ 969 gp → 96900 cp.
	var domain := {
		"realm_title": "Count",
		"peasant_families": 780,
		"liege_domain_id": "domain_duke_001",
		"owner_character_id": "character_count_lord",
	}
	var got: int = AbstractTributeResolver.compute_tribute_owed(domain)
	var expected_gp: int = TributeCalculator.compute_tribute_base_gp(780)
	check(got == expected_gp * 100,
		"owned Count tribute: expected %d cp (TributeCalculator base × 100), got %d" % [
			expected_gp * 100, got])
	print("  owned_domain_uses_tribute_calculator: OK")
