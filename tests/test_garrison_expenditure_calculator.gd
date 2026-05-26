extends "res://tests/test_suite_base.gd"

## Tests for GarrisonExpenditureCalculator (Domain Phase 5).
##
## Covers the [RAW PATCH] 2gp/family universal minimum per `acore_axioms`
## §garrison L218 / L226-227, the morale-incentive band per §additional_troops
## L461-464, the wilderness <4gp/family warning per §garrison L233, and the
## chaotic +2gp/family adjustment per `ax_domains_of_chaos` §exceptions L86.
##
## 2026-05-16 cp pass: all returned amounts are cp (1 gp = 100 cp).
## RAW gp values × 100 = cp expectations below.


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


func _set_clanhold(value: bool) -> void:
	# Migration 127 (Phase 11D.1): the +2gp garrison offset is now style-driven,
	# not alignment-driven. Tests that exercise the offset toggle domain_style.
	CampaignRepository.update_domain_settings(_domain_id,
		{"domain_style": "clanhold" if value else "civilized"})


func _wipe_units() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE assigned_domain_id = ?", [_domain_id])


## All amounts (monthly_cost_cp, monthly_wage_cp) are cp.
func _add_unit(count: int, monthly_cost_cp: int, source: String = "mercenary",
		assignment: String = "garrison", monthly_wage_cp: int = -1) -> void:
	var wage_cp: int = monthly_wage_cp if monthly_wage_cp >= 0 else monthly_cost_cp
	TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id,
		"owner_character_id": _ruler_id,
		"assigned_domain_id": _domain_id,
		"source_type": source,
		"troop_type": "Test Troop",
		"count": count,
		"starting_count": count,
		"monthly_wage_cp": wage_cp,
		"monthly_supply_cp": 0,
		"monthly_cost_cp": monthly_cost_cp,
		"battle_rating": 0.01 * count,
		"morale": 0,
		"assignment_kind": assignment,
	})


func test_empty_domain_meets_minimum_with_zero() -> void:
	_set_classification("borderlands")
	_set_clanhold(false)
	_wipe_units()
	# 100 peasants; minimum_total = 200 gp × 100 = 20,000 cp.
	# No troops → total_value=0 < 20,000, fails.
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["minimum_total_cp"]) == 20_000,
		"100 peasants × 200 cp/fam = 20,000 cp, got %s" % str(summary["minimum_total_cp"]))
	check(not bool(summary["meets_minimum"]),
		"empty domain should NOT meet 20,000 cp minimum")
	check(int(summary["gp_below_minimum_per_family"]) == 2,
		"should be 2 gp/fam below minimum, got %s" % str(summary["gp_below_minimum_per_family"]))


func test_below_minimum_flag() -> void:
	_set_classification("borderlands")
	_set_clanhold(false)
	_wipe_units()
	# 100 cp/month for 100 peasants = 1 cp/fam (way below minimum).
	_add_unit(50, 10_000)  # 100 gp = 10,000 cp; 100 cp/fam = 1 gp/fam
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["cp_per_family_value"]) == 100,
		"10,000 cp / 100 peasants = 100 cp/fam (= 1 gp/fam), got %s" % str(summary["cp_per_family_value"]))
	check(not bool(summary["meets_minimum"]), "1 gp/fam < 2 gp/fam minimum")
	check(int(summary["gp_below_minimum_per_family"]) == 1,
		"1 gp below minimum")
	check(int(summary["morale_incentive_bonus"]) == 0, "below minimum → no incentive")


func test_minimum_met_no_incentive() -> void:
	_set_classification("borderlands")
	_set_clanhold(false)
	_wipe_units()
	_add_unit(50, 20_000)  # 200 cp/fam = 2 gp/fam exact
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(bool(summary["meets_minimum"]), "exactly 2 gp/fam meets minimum")
	check(int(summary["gp_below_minimum_per_family"]) == 0, "no shortfall")
	check(int(summary["morale_incentive_bonus"]) == 0,
		"2 gp/fam = minimum, no incentive bonus per §additional_troops L462")


func test_borderlands_incentive_plus1_at_3gp() -> void:
	_set_classification("borderlands")
	_set_clanhold(false)
	_wipe_units()
	_add_unit(60, 30_000)  # 300 cp/fam = 3 gp/fam → +1 in Borderlands
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["cp_per_family_value"]) == 300, "300 cp/fam expected")
	check(int(summary["morale_incentive_bonus"]) == 1,
		"Borderlands +1 at 3 gp/fam, got %s" % str(summary["morale_incentive_bonus"]))


func test_wilderness_incentive_plus1_at_3gp() -> void:
	_set_classification("wilderness")
	_set_clanhold(false)
	_wipe_units()
	_add_unit(60, 30_000)  # 300 cp/fam = 3 gp/fam
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["morale_incentive_bonus"]) == 1,
		"Wilderness +1 at 3 gp/fam (1 gp above minimum)")
	check(bool(summary["wilderness_under_4gp"]), "3 gp < 4 gp wilderness threshold")


func test_wilderness_incentive_plus2_at_4gp() -> void:
	_set_classification("wilderness")
	_set_clanhold(false)
	_wipe_units()
	_add_unit(80, 40_000)  # 400 cp/fam = 4 gp/fam
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["morale_incentive_bonus"]) == 2,
		"Wilderness +2 at 4 gp/fam (2 gp above 2 gp baseline), got %s" % str(summary["morale_incentive_bonus"]))
	check(not bool(summary["wilderness_under_4gp"]),
		"4 gp/fam meets the wilderness 4 gp reference; warning should clear")


func test_chaotic_offset_increases_minimum() -> void:
	_set_classification("borderlands")
	_set_clanhold(true)
	_wipe_units()
	# 100 peasants × (200 + 200 clanhold) cp = 40,000 minimum.
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["minimum_total_cp"]) == 40_000,
		"clanhold borderlands: 100 × 400 cp/fam = 40,000, got %s" % str(summary["minimum_total_cp"]))
	check(int(summary["clanhold_offset_per_family_cp"]) == 200,
		"clanhold offset of 200 cp/fam surfaced in result")


func test_unpaid_followers_count_by_gp_value() -> void:
	_set_classification("borderlands")
	_set_clanhold(false)
	_wipe_units()
	# Faithful follower-source unit with monthly_cost_cp=0 (wages_required=false in
	# template) but monthly_wage_cp=30,000 of by-cp-value; should count toward total.
	_add_unit(50, 0, "follower", "garrison", 30_000)
	var summary := GarrisonExpenditureCalculator.compute(_domain_id)
	check(int(summary["unpaid_value_cp"]) == 30_000,
		"unpaid faithful counts 30,000 cp by cp value, got %s" % str(summary["unpaid_value_cp"]))
	check(int(summary["total_value_cp"]) == 30_000, "unpaid faithful contributes to total")
	check(bool(summary["meets_minimum"]),
		"30,000 ≥ 20,000 minimum even though paid=0 (faithful counts by cp value)")
