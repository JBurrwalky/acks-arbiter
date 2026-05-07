extends "res://tests/test_suite_base.gd"

## Unit tests for StrongholdCostCalculator.
##
## Verifies RAW formulas from `acore_stronghold_construction_costs.pdf`:
##   * Base build rate: 1 day per 500 gp (500 gp/day base).
##   * Speed tier 100/150/200 → daily rate 500/666/1000 gp.
##   * Engineer requirement: ceil(gp_committed / 100,000) at 250 gp/month.
##   * Class cost reduction: 50% for cleric / bladedancer.
##   * Accessory upgrade discount: 25% of base cost during construction.
##   * Class location restrictions (dwarven underground, elf spellsword
##     non-human/dwarven, explorer borderlands/wilderness).


func run_all_tests() -> void:
	test_base_structure_cost_summation()
	test_accessory_25pct_upgrade_discount()
	test_cleric_50pct_cost_reduction()
	test_bladedancer_50pct_cost_reduction()
	test_speed_tier_100_base_rate()
	test_speed_tier_150_premium_rate()
	test_speed_tier_200_capped_rate()
	test_engineer_requirement_per_100k()
	test_engineer_minimum_one()
	test_estimated_duration_days()
	test_validate_explorer_in_civilized_fails()
	test_validate_explorer_in_borderlands_passes()
	test_validate_dwarven_must_be_underground()
	test_validate_dwarven_no_human_civilized()
	test_validate_elf_spellsword_no_human_civilized()
	test_validate_engineer_requirement()
	if not has_failures():
		print("StrongholdCostCalculator: all tests passed.")


# ----- Base cost summation -----

func test_base_structure_cost_summation() -> void:
	# 1 keep (75k) + 2 medium towers (22.5k each) = 120,000
	var preset := {"class_cost_reduction_pct": 0}
	var structures: Array = [
		{"gp_cost": 75000},
		{"gp_cost": 22500},
		{"gp_cost": 22500},
	]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 100, 100)
	check(r["base_structure_cost"] == 120000,
		"base = 75k + 22.5k + 22.5k = 120,000, got %d" % r["base_structure_cost"])


# ----- Accessory upgrade discount -----

func test_accessory_25pct_upgrade_discount() -> void:
	# Total accessory base cost 100; at construction → 25 gp.
	var preset := {"class_cost_reduction_pct": 0}
	var accessories: Array = [
		{"gp_cost": 50},
		{"gp_cost": 50},
	]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, [], accessories, 100, 100)
	check(r["accessory_cost"] == 25,
		"accessories at 25%% of 100 = 25, got %d" % r["accessory_cost"])


# ----- Class cost reduction -----

func test_cleric_50pct_cost_reduction() -> void:
	# Cleric Fortified Church: 50% off the structure cost.
	# 30,000 gp keep → 15,000 gp discounted_base_cost.
	var preset := {"class_cost_reduction_pct": 50}
	var structures: Array = [{"gp_cost": 30000}]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 100, 100)
	check(r["discounted_base_cost"] == 15000,
		"cleric 50%% off 30,000 = 15,000, got %d" % r["discounted_base_cost"])
	check(r["class_cost_reduction_pct"] == 50,
		"class_cost_reduction_pct = 50, got %d" % r["class_cost_reduction_pct"])


func test_bladedancer_50pct_cost_reduction() -> void:
	var preset := {"class_cost_reduction_pct": 50}
	var structures: Array = [{"gp_cost": 50000}]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 100, 100)
	check(r["discounted_base_cost"] == 25000,
		"bladedancer 50%% off 50,000 = 25,000, got %d" % r["discounted_base_cost"])


# ----- Speed tiers -----

func test_speed_tier_100_base_rate() -> void:
	var preset := {"class_cost_reduction_pct": 0}
	var structures: Array = [{"gp_cost": 5000}]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 100, 100)
	check(r["speed_tier_pct"] == 100, "tier 100")
	check(r["daily_construction_rate_gp"] == 500,
		"tier 100 → 500 gp/day, got %d" % r["daily_construction_rate_gp"])
	check(r["speed_premium_gp"] == 0,
		"tier 100 → no premium, got %d" % r["speed_premium_gp"])
	check(r["gp_committed"] == 5000,
		"tier 100 → gp_committed = 5000, got %d" % r["gp_committed"])


func test_speed_tier_150_premium_rate() -> void:
	# +50% cost → 25% time savings → 666 gp/day equivalent.
	# Base 5000 → premium 2500 → committed 7500. duration = ceil(7500/666) = 12.
	var preset := {"class_cost_reduction_pct": 0}
	var structures: Array = [{"gp_cost": 5000}]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 150, 100)
	check(r["speed_tier_pct"] == 150, "tier 150")
	check(r["daily_construction_rate_gp"] == 666 or r["daily_construction_rate_gp"] == 667,
		"tier 150 → ~666 gp/day, got %d" % r["daily_construction_rate_gp"])
	check(r["speed_premium_gp"] == 2500,
		"tier 150 → 50%% premium 2500, got %d" % r["speed_premium_gp"])
	check(r["gp_committed"] == 7500,
		"tier 150 → gp_committed = 7500, got %d" % r["gp_committed"])


func test_speed_tier_200_capped_rate() -> void:
	# +100% cost → 50% time savings → 1000 gp/day cap.
	var preset := {"class_cost_reduction_pct": 0}
	var structures: Array = [{"gp_cost": 5000}]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 200, 100)
	check(r["speed_tier_pct"] == 200, "tier 200")
	check(r["daily_construction_rate_gp"] == 1000,
		"tier 200 → 1000 gp/day, got %d" % r["daily_construction_rate_gp"])
	check(r["speed_premium_gp"] == 5000,
		"tier 200 → 100%% premium 5000, got %d" % r["speed_premium_gp"])
	check(r["gp_committed"] == 10000,
		"tier 200 → gp_committed = 10000, got %d" % r["gp_committed"])


# ----- Engineer requirement -----

func test_engineer_requirement_per_100k() -> void:
	# 250,000 gp commit → ceil(250000/100000) = 3 engineers.
	# But our formula uses gp_committed which depends on speed tier; with tier
	# 100, gp_committed = base. So we need a 250,000 gp base.
	var preset := {"class_cost_reduction_pct": 0}
	var structures: Array = [{"gp_cost": 250000}]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 100, 100)
	check(r["engineers_required"] == 3,
		"250k gp → 3 engineers, got %d" % r["engineers_required"])
	check(r["engineer_monthly_wage_gp"] == 750,
		"3 engineers × 250 gp = 750 gp/month, got %d" % r["engineer_monthly_wage_gp"])


func test_engineer_minimum_one() -> void:
	# Even tiny strongholds (1,000 gp) need at least 1 engineer.
	var preset := {"class_cost_reduction_pct": 0}
	var structures: Array = [{"gp_cost": 1000}]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 100, 100)
	check(r["engineers_required"] == 1,
		"min 1 engineer always, got %d" % r["engineers_required"])


# ----- Estimated duration -----

func test_estimated_duration_days() -> void:
	# 5,000 gp at 500 gp/day = 10 days exactly.
	var preset := {"class_cost_reduction_pct": 0}
	var structures: Array = [{"gp_cost": 5000}]
	var r := StrongholdCostCalculator.calculate_total_cost(preset, structures, [], 100, 100)
	check(r["estimated_duration_days"] == 10,
		"5000 gp at 500/day = 10 days, got %d" % r["estimated_duration_days"])


# ----- Class location validation -----

func test_validate_explorer_in_civilized_fails() -> void:
	var errors := StrongholdCostCalculator.validate_class_location(
		"stronghold_border_fort", "civilized", "human", false)
	check(errors.has("explorer_borderlands_or_wilderness_only"),
		"explorer in civilized → error, got %s" % str(errors))


func test_validate_explorer_in_borderlands_passes() -> void:
	var errors := StrongholdCostCalculator.validate_class_location(
		"stronghold_border_fort", "borderlands", "human", false)
	check(errors.is_empty(),
		"explorer in borderlands → no errors, got %s" % str(errors))


func test_validate_dwarven_must_be_underground() -> void:
	var errors := StrongholdCostCalculator.validate_class_location(
		"stronghold_vault", "wilderness", "dwarven", false)
	check(errors.has("dwarven_must_be_underground"),
		"dwarven not underground → error, got %s" % str(errors))


func test_validate_dwarven_no_human_civilized() -> void:
	var errors := StrongholdCostCalculator.validate_class_location(
		"stronghold_vault", "civilized", "human", true)
	check(errors.has("dwarven_no_human_or_elven_civilized_or_borderlands"),
		"dwarven in human civilized → error, got %s" % str(errors))


func test_validate_elf_spellsword_no_human_civilized() -> void:
	var errors := StrongholdCostCalculator.validate_class_location(
		"stronghold_fastness", "civilized", "human", false)
	check(errors.has("elf_spellsword_no_human_or_dwarven_civilized_or_borderlands"),
		"elf spellsword in human civilized → error, got %s" % str(errors))


# ----- Engineer requirement validation -----

func test_validate_engineer_requirement() -> void:
	# 100,000 gp needs 1 engineer
	check(StrongholdCostCalculator.validate_engineer_requirement(100000, 1) == true,
		"100k / 1 engineer is valid")
	# 200,000 gp needs 2 engineers; 1 assigned → invalid
	check(StrongholdCostCalculator.validate_engineer_requirement(200000, 1) == false,
		"200k / 1 engineer is INSUFFICIENT (needs 2)")
	check(StrongholdCostCalculator.validate_engineer_requirement(200000, 2) == true,
		"200k / 2 engineers is valid")
	# Edge: 0 gp still requires 1 engineer (minimum)
	check(StrongholdCostCalculator.validate_engineer_requirement(0, 0) == false,
		"0 gp / 0 engineers fails (min 1 always)")
	check(StrongholdCostCalculator.validate_engineer_requirement(0, 1) == true,
		"0 gp / 1 engineer passes")
