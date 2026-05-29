extends "res://tests/scenarios/scenario_runner_base.gd"

## Scenario: Full Loop Fighter Borderlands — multi-month integration.
##
## A 9th-level Fighter establishes a borderlands domain and ticks 6 months.
## Verify the resolver stack composes without errors, domain stays in healthy
## state, and population accumulates positively.


func run_all_tests() -> void:
	cleanup_scenario()
	test_six_months_steady_state()
	cleanup_scenario()
	if not has_failures():
		print("Scenario.FullLoopBorderlands: all tests passed.")


func test_six_months_steady_state() -> void:
	seed_campaign("scenario_fl_camp")
	var ruler: String = seed_character("scenario_fl_ruler", {
		"alignment": "lawful",
		"character_class": "fighter",
		"level": 9,
		"charisma": 13,
	})
	var domain: String = seed_domain("scenario_fl_domain", ruler, {
		"territory_type": "borderlands",
		"peasant_families": 500,
		"alignment": "lawful",
	})
	seed_hexes(domain, 4, 5, 0)

	# Tick 6 months. Deterministic roller in the base class ensures the same
	# growth math every time.
	var results: Array = tick_monthly(6)
	check(results.size() == 6,
		"6 monthly results collected; got %d" % results.size())

	# After 6 months: domain is still active, peasant_families ≥ starting
	# (the deterministic roller's count×5 yields positive net growth at apathy).
	var d: Dictionary = CampaignRepository.get_domain(domain)
	check(str(d.get("lifecycle_state", "")) == "active",
		"lifecycle_state still active after 6 months")
	check(int(d.get("peasant_families", 0)) >= 500,
		"peasant_families ≥ starting 500 after 6 months of growth; got %d"
		% int(d.get("peasant_families", 0)))
	# Each monthly result has the expected keys (composition assertion).
	var last: Dictionary = results[5]
	check(last.has("revenue") and last.has("expenses") and last.has("base_morale"),
		"monthly result composes revenue+expenses+morale subdicts")
