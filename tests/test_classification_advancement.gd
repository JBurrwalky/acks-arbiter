extends "res://tests/test_suite_base.gd"

## Unit tests for ClassificationAdvancement.
##
## Verifies RAW formulas from `acore_axioms_strongholds_and_domains.xml`:
##   * §limits_of_growth.maximum_population L156-161 — family caps 125/250/780.
##   * §classification_advancement L165-175 — promotion criteria.
##   * §optional_rules.regression L178 — regression on lapsed conditions.


func run_all_tests() -> void:
	test_family_caps()
	test_wilderness_advances_to_borderlands_path_a()
	test_wilderness_advances_via_urban_blocked_path_b()
	test_wilderness_blocked_by_distance()
	test_borderlands_advances_to_civilized_path_a()
	test_civilized_regresses_when_distance_exceeds_48()
	test_borderlands_regresses_when_distance_exceeds_72()
	test_no_change_when_unsaturated()
	if not has_failures():
		print("ClassificationAdvancement: all tests passed.")


# ----- Caps -----

func test_family_caps() -> void:
	check(ClassificationAdvancement.family_cap_per_hex(ClassificationAdvancement.TT_WILDERNESS) == 125,
		"wilderness cap = 125")
	check(ClassificationAdvancement.family_cap_per_hex(ClassificationAdvancement.TT_BORDERLANDS) == 250,
		"borderlands cap = 250")
	check(ClassificationAdvancement.family_cap_per_hex(ClassificationAdvancement.TT_CIVILIZED) == 780,
		"civilized cap = 780")


# ----- Advancement to Borderlands -----

func test_wilderness_advances_to_borderlands_path_a() -> void:
	# Path A: every hex at 125 fam (16 hexes × 125 = 2,000) + within 72 mi.
	var domain := {"territory_type": "wilderness", "peasant_families": 2000}
	var r := ClassificationAdvancement.check_classification_change(
		domain, 16, false, 0, 50, false)
	check(r["advanced"] == true, "should advance to Borderlands at 16-hex saturation")
	check(r["new_classification"] == "borderlands", "new = borderlands")


func test_wilderness_advances_via_urban_blocked_path_b() -> void:
	# Path B: hexes saturated, expansion blocked, urban with 20%+ ratio.
	# 4 hexes × 125 fam = 500 peasants; urban 100 = 20%. Within 72 mi.
	var domain := {"territory_type": "wilderness", "peasant_families": 500,
		"urban_families": 100}
	var r := ClassificationAdvancement.check_classification_change(
		domain, 4, true, 20, 50, true)
	check(r["advanced"] == true, "should advance via Path B")


func test_wilderness_blocked_by_distance() -> void:
	# Saturated 16-hex domain but more than 72 mi from friendly settlement.
	var domain := {"territory_type": "wilderness", "peasant_families": 2000}
	var r := ClassificationAdvancement.check_classification_change(
		domain, 16, false, 0, 100, false)
	check(r["advanced"] == false, "blocked by distance > 72mi")
	check(r["new_classification"] == "wilderness", "stays wilderness")


# ----- Advancement to Civilized -----

func test_borderlands_advances_to_civilized_path_a() -> void:
	# Path A: every hex at 250 fam (16 × 250 = 4,000) + within 48 mi.
	var domain := {"territory_type": "borderlands", "peasant_families": 4000}
	var r := ClassificationAdvancement.check_classification_change(
		domain, 16, false, 0, 30, false)
	check(r["advanced"] == true, "should advance to Civilized")
	check(r["new_classification"] == "civilized", "new = civilized")


# ----- Regression -----

func test_civilized_regresses_when_distance_exceeds_48() -> void:
	var domain := {"territory_type": "civilized", "peasant_families": 0}
	var r := ClassificationAdvancement.check_classification_change(
		domain, 4, false, 0, 60, false)  # 60 mi > 48
	check(r["regressed"] == true, "civilized regresses outside 48mi")
	check(r["new_classification"] == "borderlands", "demote one step to borderlands")


func test_borderlands_regresses_when_distance_exceeds_72() -> void:
	var domain := {"territory_type": "borderlands", "peasant_families": 0}
	var r := ClassificationAdvancement.check_classification_change(
		domain, 4, false, 0, 100, false)  # 100 mi > 72
	check(r["regressed"] == true, "borderlands regresses outside 72mi")
	check(r["new_classification"] == "wilderness", "demote one step to wilderness")


# ----- No-op -----

func test_no_change_when_unsaturated() -> void:
	var domain := {"territory_type": "wilderness", "peasant_families": 50}
	var r := ClassificationAdvancement.check_classification_change(
		domain, 1, false, 0, 50, false)
	check(r["advanced"] == false, "no advance when unsaturated")
	check(r["regressed"] == false, "no regression for fresh wilderness")
	check(r["new_classification"] == "wilderness", "stays wilderness")
