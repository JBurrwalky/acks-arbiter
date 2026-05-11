extends "res://tests/test_suite_base.gd"

## Tests for GarrisonExpenditureCalculator (Domain Phase 5).
##
## Covers the [RAW PATCH] 2gp/family universal minimum per `acore_axioms`
## §garrison L218 / L226-227, the morale-incentive band per §additional_troops
## L461-464, the wilderness <4gp/family warning per §garrison L233, and the
## chaotic +2gp/family adjustment per `ax_domains_of_chaos` §exceptions L86.


var _campaign_id: String = ""
var _ruler_id: String = ""
var _domain_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_empty_domain_meets_minimum_with_zero()
	test_below_minimum_flag()
	test_minimum_met_no_incentive()
	test_borderlands_incentive_plus1_at_3gp()
	test_wilderness_incentive_plus1_at_3gp()
	test_wilderness_incentive_plus2_at_4gp()
	test_chaotic_offset_increases_minimum()
	test_unpaid_followers_count_by_gp_value()
	if not has_failures():
		print("GarrisonExpenditureCalculator: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Garrison", "TestWorld")
	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Lord Garrison', 'pc', 'full', 'human', 'fighter', 9,
			14, 10, 10, 10, 10, 14, 60, 60)
	""", [_ruler_id, _campaign_id])
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Garrison Test",
		"territory_type": "borderlands",
		"owner_character_id": _ruler_id,
	})
	# peasant_families lives in the monthly-state whitelist; set it after creation.
	CampaignRepository.update_domain_monthly_state(_domain_id, {"peasant_families": 100})


func _set_classification(value: String) -> void:
	# Schema column is `territory_type` (per §domains in schema.sql) — sometimes
	# called "classification" in roadmap text following RAW.
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET territory_type = ? WHERE id = ?", [value, _domain_id])


func _set_chaotic(value: bool) -> void:
	CampaignRepository.update_domain_settings(_domain_id, {"is_chaotic_domain": 1 if value else 0})


func _wipe_units() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE assigned_domain_id = ?", [_domain_id])


func _add_unit(count: int, monthly_cost_gp: int, source: String = "mercenary",
		assignment: String = "garrison", monthly_wage_gp: int = -1) -> void:
	var wage: int = monthly_wage_gp if monthly_wage_gp >= 0 else monthly_cost_gp
	TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id,
		"owner_character_id": _ruler_id,
		"assigned_domain_id": _domain_id,
		"source_type": source,
		"troop_type": "Test Troop",
		"count": count,
		"starting_count": count,
		"monthly_wage_gp": wage,
		"monthly_supply_gp": 0,
		"monthly_cost_gp": monthly_cost_gp,
		"battle_rating": 0.01 * count,
		"morale": 0,
		"assignment_kind": assignment,
	})


func test_empty_domain_meets_minimum_with_zero() -> void:
	_set_classification("borderlands")
	_set_chaotic(false)
	_wipe_units()
	# 100 peasants; minimum_total = 200gp. With no troops, total_value=0 < 200, fails.
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["minimum_total_gp"]) == 200,
		"100 peasants × 2gp/fam = 200, got %s" % str(summary["minimum_total_gp"]))
	check(not bool(summary["meets_minimum"]),
		"empty domain should NOT meet 200gp minimum")
	check(int(summary["gp_below_minimum_per_family"]) == 2,
		"should be 2gp/fam below minimum, got %s" % str(summary["gp_below_minimum_per_family"]))


func test_below_minimum_flag() -> void:
	_set_classification("borderlands")
	_set_chaotic(false)
	_wipe_units()
	_add_unit(50, 100)  # 100gp/month for 100 peasants = 1gp/fam
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["gp_per_family_value"]) == 1,
		"100gp / 100 peasants = 1gp/fam, got %s" % str(summary["gp_per_family_value"]))
	check(not bool(summary["meets_minimum"]), "1gp/fam < 2gp/fam minimum")
	check(int(summary["gp_below_minimum_per_family"]) == 1,
		"1gp below minimum")
	check(int(summary["morale_incentive_bonus"]) == 0, "below minimum → no incentive")


func test_minimum_met_no_incentive() -> void:
	_set_classification("borderlands")
	_set_chaotic(false)
	_wipe_units()
	_add_unit(50, 200)  # 2gp/fam exact
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(bool(summary["meets_minimum"]), "exactly 2gp/fam meets minimum")
	check(int(summary["gp_below_minimum_per_family"]) == 0, "no shortfall")
	check(int(summary["morale_incentive_bonus"]) == 0,
		"2gp/fam = minimum, no incentive bonus per §additional_troops L462")


func test_borderlands_incentive_plus1_at_3gp() -> void:
	_set_classification("borderlands")
	_set_chaotic(false)
	_wipe_units()
	_add_unit(60, 300)  # 3gp/fam → +1 in Borderlands
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["gp_per_family_value"]) == 3, "3gp/fam expected")
	check(int(summary["morale_incentive_bonus"]) == 1,
		"Borderlands +1 at 3gp/fam, got %s" % str(summary["morale_incentive_bonus"]))


func test_wilderness_incentive_plus1_at_3gp() -> void:
	_set_classification("wilderness")
	_set_chaotic(false)
	_wipe_units()
	_add_unit(60, 300)
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["morale_incentive_bonus"]) == 1,
		"Wilderness +1 at 3gp/fam (1gp above minimum)")
	check(bool(summary["wilderness_under_4gp"]), "3gp < 4gp wilderness threshold")


func test_wilderness_incentive_plus2_at_4gp() -> void:
	_set_classification("wilderness")
	_set_chaotic(false)
	_wipe_units()
	_add_unit(80, 400)  # 4gp/fam
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["morale_incentive_bonus"]) == 2,
		"Wilderness +2 at 4gp/fam (2gp above 2gp baseline), got %s" % str(summary["morale_incentive_bonus"]))
	check(not bool(summary["wilderness_under_4gp"]),
		"4gp/fam meets the wilderness 4gp reference; warning should clear")


func test_chaotic_offset_increases_minimum() -> void:
	_set_classification("borderlands")
	_set_chaotic(true)
	_wipe_units()
	# 100 peasants × (2 + 2) chaotic = 400 minimum.
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["minimum_total_gp"]) == 400,
		"chaotic borderlands: 100 × 4gp/fam = 400, got %s" % str(summary["minimum_total_gp"]))
	check(int(summary["chaotic_offset_per_family"]) == 2,
		"chaotic offset surfaced in result")


func test_unpaid_followers_count_by_gp_value() -> void:
	_set_classification("borderlands")
	_set_chaotic(false)
	_wipe_units()
	# Faithful follower-source unit with monthly_cost_gp=0 (wages_required=false in
	# template) but monthly_wage_gp=300 of by-gp-value; should count.
	_add_unit(50, 0, "follower", "garrison", 300)
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["unpaid_value_gp"]) == 300,
		"unpaid faithful counts 300gp by gp value, got %s" % str(summary["unpaid_value_gp"]))
	check(int(summary["total_value_gp"]) == 300, "unpaid faithful contributes to total")
	check(bool(summary["meets_minimum"]),
		"300 ≥ 200 minimum even though paid=0 (faithful counts by gp value)")
