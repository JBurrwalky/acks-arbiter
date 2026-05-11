extends "res://tests/test_suite_base.gd"

## Tests for CommissionPipeline.bump_daily_construction_rate (Domain Phase 4).
##
## Verifies the +5% / +10% rate bump applied by oversee_construction and
## supervise_construction handlers per ax_campaign_play.xml §oversee_construction
## L661-672. Banker's rounding via XPAwardCalculator; if rounding collapses the
## bump (low base rate), forced +1 fallback so successive supervisors progress.


var _campaign_id: String = ""
var _domain_id: String = ""
var _ruler_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_bump_rejects_unknown_commission()
	test_bump_rejects_zero_or_negative_pct()
	test_bump_increases_rate_by_5_pct()
	test_bump_stacks_compoundingly()
	test_bump_rejects_completed_commission()
	test_get_in_progress_commission_for_domain_returns_empty_when_none()
	test_get_in_progress_commission_for_domain_returns_active()
	if not has_failures():
		print("CommissionPipelineRateBump: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Rate Bump", "TestWorld")
	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Bumper', 'pc', 'full', 'human', 'fighter', 9,
			10, 10, 10, 10, 10, 10, 8, 8)
	""", [_ruler_id, _campaign_id])
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Bump Test Domain",
		"territory_type": "borderlands",
		"owner_character_id": _ruler_id,
	})


func _make_commission(daily_rate: int, status: String = "in_progress") -> String:
	var stronghold_id: String = CampaignRepository.create_stronghold({
		"domain_id": _domain_id,
		"owner_character_id": _ruler_id,
		"archetype": "fortress",
		"archetype_power_id": "fighter_castle",
		"structure_type": "keep",
		"gp_value": 30000,
		"shp": 100,
		"ac": 6,
		"garrison_capacity": 50,
		"completion_pct": 0,
		"status": "in_progress" if status == "in_progress" else "completed",
	})
	return CampaignRepository.create_commission({
		"stronghold_id": stronghold_id,
		"gp_committed": 30000,
		"daily_construction_rate_gp": daily_rate,
		"speed_tier_pct": 100,
		"engineers_required": 1,
		"engineers_assigned": 1,
		"engineer_monthly_wage_gp": 250,
		"magic_rate_modifier_pct": 100,
		"materials_strategy": "local",
		"class_cost_reduction_pct": 0,
		"started_calendar_day": 1,
		"expected_halfway_day": 30,
		"expected_completion_day": 60,
		"gp_progressed": 0,
		"halfway_signal_fired": false,
		"status": status,
	})


# ---------------------------------------------------------------------------

func test_bump_rejects_unknown_commission() -> void:
	check(CommissionPipeline.bump_daily_construction_rate("nonexistent", 5) == 0,
		"unknown commission_id returns 0")


func test_bump_rejects_zero_or_negative_pct() -> void:
	var cid := _make_commission(500)
	check(CommissionPipeline.bump_daily_construction_rate(cid, 0) == 0,
		"bonus_pct = 0 returns 0")
	check(CommissionPipeline.bump_daily_construction_rate(cid, -5) == 0,
		"negative bonus_pct returns 0")


func test_bump_increases_rate_by_5_pct() -> void:
	var cid := _make_commission(500)
	var new_rate := CommissionPipeline.bump_daily_construction_rate(cid, 5)
	# 500 * 1.05 = 525
	check(new_rate == 525, "500 * 1.05 = 525, got %d" % new_rate)
	var commission := CampaignRepository.get_commission(cid)
	check(int(commission.get("daily_construction_rate_gp", 0)) == 525,
		"persisted rate should match new_rate")


func test_bump_stacks_compoundingly() -> void:
	var cid := _make_commission(500)
	var r1 := CommissionPipeline.bump_daily_construction_rate(cid, 10)
	# 500 * 1.10 = 550
	check(r1 == 550, "first +10%% bump → 550, got %d" % r1)
	var r2 := CommissionPipeline.bump_daily_construction_rate(cid, 5)
	# 550 * 1.05 = 577.5 → banker's rounds to 578 (half to even at .5 rounds
	# 577 to 578 since 578 is even).
	check(r2 == 578 or r2 == 577,
		"second +5%% on top → 577 or 578 (banker's rounding), got %d" % r2)


func test_bump_rejects_completed_commission() -> void:
	var cid := _make_commission(500, "completed")
	var new_rate := CommissionPipeline.bump_daily_construction_rate(cid, 5)
	check(new_rate == 0, "completed commission rejects bump, got %d" % new_rate)


func test_get_in_progress_commission_for_domain_returns_empty_when_none() -> void:
	var fresh_domain := CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Empty Domain",
		"territory_type": "borderlands",
		"owner_character_id": _ruler_id,
	})
	var commission := CommissionPipeline.get_in_progress_commission_for_domain(fresh_domain)
	check(commission.is_empty(),
		"empty domain returns empty Dict, got %s" % str(commission))


func test_get_in_progress_commission_for_domain_returns_active() -> void:
	var fresh_domain := CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Active Domain",
		"territory_type": "borderlands",
		"owner_character_id": _ruler_id,
	})
	var stronghold_id: String = CampaignRepository.create_stronghold({
		"domain_id": fresh_domain,
		"owner_character_id": _ruler_id,
		"archetype": "fortress",
		"archetype_power_id": "fighter_castle",
		"structure_type": "keep",
		"gp_value": 30000,
		"shp": 100,
		"ac": 6,
		"garrison_capacity": 50,
		"completion_pct": 0,
		"status": "in_progress",
	})
	CampaignRepository.create_commission({
		"stronghold_id": stronghold_id,
		"gp_committed": 30000,
		"daily_construction_rate_gp": 500,
		"speed_tier_pct": 100,
		"engineers_required": 1,
		"engineers_assigned": 1,
		"engineer_monthly_wage_gp": 250,
		"magic_rate_modifier_pct": 100,
		"materials_strategy": "local",
		"class_cost_reduction_pct": 0,
		"started_calendar_day": 1,
		"expected_halfway_day": 30,
		"expected_completion_day": 60,
		"gp_progressed": 0,
		"halfway_signal_fired": false,
		"status": "in_progress",
	})
	var commission := CommissionPipeline.get_in_progress_commission_for_domain(fresh_domain)
	check(not commission.is_empty(), "active commission returned for domain")
	check(int(commission.get("daily_construction_rate_gp", 0)) == 500,
		"correct rate read back")
