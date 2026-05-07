extends "res://tests/test_suite_base.gd"

## Unit tests for DomainMoraleResolver.
##
## Verifies RAW formulas from `acore_axioms_strongholds_and_domains.xml` §morale
## L412-609:
##   * Base morale = CHA + Leadership + personal_authority + classification penalty
##     + insufficient_stronghold tier + alignment match + additional_troops bonus
##     (insufficient_stronghold and repression tested separately)
##   * Current morale = 2d6 monthly with drift toward base, clamped [-4, +4]
##   * Natural 2 / natural 12 always force ±2
##   * Morale tier mapping per §effects_of_morale L538-549


func run_all_tests() -> void:
	test_base_starts_at_zero_when_neutral_inputs()
	test_cha_modifier_adds_to_base()
	test_leadership_proficiency_adds_one()
	test_personal_authority_level9_in_low_band()
	test_personal_authority_level1_in_high_band()
	test_borderlands_classification_penalty()
	test_wilderness_classification_penalty()
	test_alignment_neutral_to_chaotic_is_minus_one()
	test_alignment_lawful_to_chaotic_is_minus_two()
	test_additional_troops_borderlands_plus_one()
	test_additional_troops_wilderness_plus_two_at_two_gp()
	test_morale_drift_below_base()
	test_morale_drift_above_base()
	test_natural_2_always_minus_two()
	test_natural_12_always_plus_two()
	test_clamp_to_minus_four_floor()
	test_clamp_to_plus_four_ceiling()
	test_morale_tier_mapping()
	if not has_failures():
		print("DomainMoraleResolver: all tests passed.")


# ----- Base morale -----

func test_base_starts_at_zero_when_neutral_inputs() -> void:
	# Civilized (no classification penalty), neutral ruler in neutral domain,
	# CHA mod 0, no Leadership, level 1 with 0 income (cell [1][0] = +1) →
	# base = 0 + 0 + 0 + 1 + 0 + 0 = +1.
	var domain := {"territory_type": "civilized", "alignment": "neutral"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 0)
	check(base == 1, "base = +1 (level 1 personal authority cell), got %d" % base)


func test_cha_modifier_adds_to_base() -> void:
	var domain := {"territory_type": "civilized", "alignment": "neutral"}
	var ruler := {"cha_modifier": 2, "level": 1,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 0)
	check(base == 3, "base += CHA mod 2 → +3, got %d" % base)


func test_leadership_proficiency_adds_one() -> void:
	var domain := {"territory_type": "civilized", "alignment": "neutral"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": true, "alignment": "neutral"}
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 0)
	check(base == 2, "base += Leadership +1 → +2, got %d" % base)


func test_personal_authority_level9_in_low_band() -> void:
	# Level 9, income 0 (band 0): table cell = 4 (per §personal_authority L443).
	# Civilized + neutral/neutral + sufficient stronghold = 0 contributions.
	var domain := {"territory_type": "civilized", "alignment": "neutral"}
	var ruler := {"cha_modifier": 0, "level": 9,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 0)
	check(base == 4, "level 9 / 0 income personal authority = +4, got %d" % base)


func test_personal_authority_level1_in_high_band() -> void:
	# Level 1, income > 12,000 (band 8+): cell = -4.
	var domain := {"territory_type": "civilized", "alignment": "neutral"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 15000, 999, 0, 0)
	check(base == -4, "level 1 / 15000 income personal authority = -4, got %d" % base)


# ----- Classification penalty -----

func test_borderlands_classification_penalty() -> void:
	var domain := {"territory_type": "borderlands", "alignment": "neutral"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 0)
	# Level 1 / band 0 = +1; borderlands = -1; total = 0.
	check(base == 0, "borderlands = +1 - 1 = 0, got %d" % base)


func test_wilderness_classification_penalty() -> void:
	var domain := {"territory_type": "wilderness", "alignment": "neutral"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 0)
	# +1 - 2 = -1.
	check(base == -1, "wilderness = +1 - 2 = -1, got %d" % base)


# ----- Alignment match -----

func test_alignment_neutral_to_chaotic_is_minus_one() -> void:
	# Neutral ruler in chaotic domain → -1 per L468.
	var domain := {"territory_type": "civilized", "alignment": "chaotic"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 0)
	check(base == 0, "neutral-in-chaotic = +1 - 1 = 0, got %d" % base)


func test_alignment_lawful_to_chaotic_is_minus_two() -> void:
	# Lawful ruler in chaotic domain → -2 per L469.
	var domain := {"territory_type": "civilized", "alignment": "chaotic"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": false, "alignment": "lawful"}
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 0)
	check(base == -1, "lawful-in-chaotic = +1 - 2 = -1, got %d" % base)


# ----- Additional troops -----

func test_additional_troops_borderlands_plus_one() -> void:
	var domain := {"territory_type": "borderlands", "alignment": "neutral"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	# +1 personal authority − 1 borderlands + 1 additional = +1.
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 1)
	check(base == 1, "borderlands + 1 gp/fam additional = +1, got %d" % base)


func test_additional_troops_wilderness_plus_two_at_two_gp() -> void:
	var domain := {"territory_type": "wilderness", "alignment": "neutral"}
	var ruler := {"cha_modifier": 0, "level": 1,
		"has_leadership_proficiency": false, "alignment": "neutral"}
	# +1 - 2 wilderness + 2 additional = +1.
	var base := DomainMoraleResolver.resolve_base_morale(domain, ruler, 0, 999, 0, 2)
	check(base == 1, "wilderness + 2 gp/fam additional = +1, got %d" % base)


# ----- Current morale drift -----

func test_morale_drift_below_base() -> void:
	# prior current = -2; base = +2; roll 7 (drift one toward base) → -1.
	var domain := {"morale": -2, "territory_type": "civilized", "alignment": "neutral"}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 2, 0, 0, false, 7)
	check(m["current_morale"] == -1, "drift toward base from -2: -1, got %d" % m["current_morale"])


func test_morale_drift_above_base() -> void:
	var domain := {"morale": 3, "territory_type": "civilized", "alignment": "neutral"}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 0, 0, 0, false, 7)
	check(m["current_morale"] == 2, "drift toward base from +3: +2, got %d" % m["current_morale"])


# ----- Natural 2 / natural 12 -----

func test_natural_2_always_minus_two() -> void:
	# Even with +5 modifiers, natural 2 always reduces by 2 per L476.
	var domain := {"morale": 0}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 0, 5, 0, false, 2)
	check(m["current_morale"] == -2, "natural 2 → -2 regardless of modifiers, got %d" % m["current_morale"])


func test_natural_12_always_plus_two() -> void:
	# Even with -5 modifiers, natural 12 always increases by 2 per L477.
	var domain := {"morale": 0}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 0, -5, 0, false, 12)
	check(m["current_morale"] == 2, "natural 12 → +2 regardless of modifiers, got %d" % m["current_morale"])


# ----- Clamp -----

func test_clamp_to_minus_four_floor() -> void:
	var domain := {"morale": -4}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 0, 0, 0, false, 2)  # natural 2 would shift -2 → would go to -6
	check(m["current_morale"] == -4, "clamped at -4 floor, got %d" % m["current_morale"])


func test_clamp_to_plus_four_ceiling() -> void:
	var domain := {"morale": 4}
	var m := DomainMoraleResolver.resolve_current_morale(
		domain, 0, 0, 0, false, 12)  # natural 12 would shift +2 → would go to +6
	check(m["current_morale"] == 4, "clamped at +4 ceiling, got %d" % m["current_morale"])


# ----- Tier mapping -----

func test_morale_tier_mapping() -> void:
	check(DomainMoraleResolver.morale_tier(-4) == DomainMoraleResolver.TIER_REBELLIOUS,
		"-4 = Rebellious")
	check(DomainMoraleResolver.morale_tier(-3) == DomainMoraleResolver.TIER_DEFIANT,
		"-3 = Defiant")
	check(DomainMoraleResolver.morale_tier(-2) == DomainMoraleResolver.TIER_TURBULENT,
		"-2 = Turbulent")
	check(DomainMoraleResolver.morale_tier(-1) == DomainMoraleResolver.TIER_DEMORALIZED,
		"-1 = Demoralized")
	check(DomainMoraleResolver.morale_tier(0) == DomainMoraleResolver.TIER_APATHETIC,
		"0 = Apathetic")
	check(DomainMoraleResolver.morale_tier(1) == DomainMoraleResolver.TIER_LOYAL,
		"+1 = Loyal")
	check(DomainMoraleResolver.morale_tier(2) == DomainMoraleResolver.TIER_DEDICATED,
		"+2 = Dedicated")
	check(DomainMoraleResolver.morale_tier(3) == DomainMoraleResolver.TIER_STEADFAST,
		"+3 = Steadfast")
	check(DomainMoraleResolver.morale_tier(4) == DomainMoraleResolver.TIER_STALWART,
		"+4 = Stalwart")
