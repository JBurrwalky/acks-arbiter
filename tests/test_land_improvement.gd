extends "res://tests/test_suite_base.gd"

## Unit tests for LandImprovement.
##
## Verifies RAW from `acore_axioms_strongholds_and_domains.xml` §land_improvement
## L207-215: 25,000 gp (= 2,500,000 cp) per +1 land value, capped +3 cumulative,
## final value ≤ 9.


func run_all_tests() -> void:
	test_accept_first_improvement_at_min_cp()
	test_reject_when_committed_below_min_cp()
	test_reject_when_already_at_plus_3()
	test_reject_when_land_value_at_9()
	test_accept_full_chain_to_plus_3()
	test_constants_match_raw()
	if not has_failures():
		print("LandImprovement: all tests passed.")


# ----- Accept -----

func test_accept_first_improvement_at_min_cp() -> void:
	var hex := {"land_value": 5, "land_improvement_level": 0}
	var r := LandImprovement.attempt_improvement(hex, 2_500_000)
	check(r["accepted"] == true, "first improvement at 2,500,000 cp accepted")
	check(r["new_improvement"] == 1, "improvement 0 → 1, got %d" % r["new_improvement"])
	check(r["new_land_value"] == 6, "land_value 5 → 6, got %d" % r["new_land_value"])
	check(r["cp_spent"] == 2_500_000, "cp_spent = 2,500,000")
	check(r["reason"] == "ok", "reason = ok, got %s" % r["reason"])


# ----- Reject: insufficient cp -----

func test_reject_when_committed_below_min_cp() -> void:
	var hex := {"land_value": 5, "land_improvement_level": 0}
	var r := LandImprovement.attempt_improvement(hex, 2_499_999)
	check(r["accepted"] == false, "2,499,999 cp rejected")
	check(r["reason"] == "insufficient_cp", "reason = insufficient_cp, got %s" % r["reason"])
	check(r["cp_spent"] == 0, "no cp spent on reject")
	check(r["new_improvement"] == 0, "improvement unchanged on reject")


# ----- Reject: improvement cap -----

func test_reject_when_already_at_plus_3() -> void:
	var hex := {"land_value": 8, "land_improvement_level": 3}  # already at the +3 max
	var r := LandImprovement.attempt_improvement(hex, 2_500_000)
	check(r["accepted"] == false, "rejected at +3 cap")
	check(r["reason"] == "improvement_capped", "reason = improvement_capped, got %s" % r["reason"])
	check(r["cp_spent"] == 0, "no cp spent at cap")


# ----- Reject: land_value cap -----

func test_reject_when_land_value_at_9() -> void:
	# Hex at land_value 9 even though only +1 improvement so far — base 8 + 1.
	var hex := {"land_value": 9, "land_improvement_level": 1}
	var r := LandImprovement.attempt_improvement(hex, 2_500_000)
	check(r["accepted"] == false, "rejected at land_value 9")
	check(r["reason"] == "land_value_capped", "reason = land_value_capped")


# ----- Accept full chain -----

func test_accept_full_chain_to_plus_3() -> void:
	# Three sequential improvements take a base-5 hex from 5 → 6 → 7 → 8.
	var hex := {"land_value": 5, "land_improvement_level": 0}
	for i in range(3):
		var r := LandImprovement.attempt_improvement(hex, 2_500_000)
		check(r["accepted"] == true, "step %d accepted" % i)
		hex["land_value"] = r["new_land_value"]
		hex["land_improvement_level"] = r["new_improvement"]
	check(hex["land_improvement_level"] == 3, "ended at +3 improvement")
	check(hex["land_value"] == 8, "ended at land_value 8 (base 5 + 3)")
	# Fourth attempt rejected.
	var r4 := LandImprovement.attempt_improvement(hex, 2_500_000)
	check(r4["accepted"] == false, "fourth attempt rejected")
	check(r4["reason"] == "improvement_capped", "reason = improvement_capped on 4th")


# ----- Constants -----

func test_constants_match_raw() -> void:
	check(LandImprovement.COST_PER_PLUS_ONE_CP == 2_500_000, "RAW: 25,000 gp (= 2,500,000 cp) per +1")
	check(LandImprovement.MAX_IMPROVEMENT_PER_HEX == 3, "RAW: max +3")
	check(LandImprovement.MAX_TOTAL_LAND_VALUE == 9, "RAW: never exceed 9")
