extends "res://tests/test_suite_base.gd"

## Tests for OverseeConstructionHandler / SuperviseConstructionHandler
## (Domain Phase 4 wire-in to CommissionPipeline.bump_daily_construction_rate).


var _campaign_id: String = ""
var _ruler_id: String = ""
var _domain_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_oversee_construction_bumps_rate_by_5_pct()
	test_supervise_construction_bumps_rate_by_10_pct()
	test_oversee_no_active_commission_logs_ledger_no_op()
	if not has_failures():
		print("OverseeConstructionHandler: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Oversee Construction", "TestWorld")
	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Test Overseer', 'pc', 'full', 'human', 'fighter', 9,
			10, 10, 10, 10, 10, 10, 8, 8)
	""", [_ruler_id, _campaign_id])
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Oversee Test Domain",
		"territory_type": "borderlands",
		"owner_character_id": _ruler_id,
	})


func _make_commission(daily_rate: int) -> String:
	var stronghold_id: String = CampaignRepository.create_stronghold({
		"domain_id": _domain_id,
		"owner_character_id": _ruler_id,
		"archetype": "fortress",
		"archetype_power_id": "fighter_castle",
		"structure_type": "keep",
		"cp_value": 3000000,  # Migration 116: 30000 gp × 100 = 3,000,000 cp.
		"shp": 100,
		"ac": 6,
		"garrison_capacity": 50,
		"completion_pct": 0,
		"status": "in_progress",
	})
	return CampaignRepository.create_commission({
		"stronghold_id": stronghold_id,
		"cp_committed": 3000000,  # 30,000 gp × 100
		"daily_construction_rate_cp": daily_rate,
		"speed_tier_pct": 100,
		"engineers_required": 1,
		"engineers_assigned": 1,
		"engineer_monthly_wage_cp": 250,
		"magic_rate_modifier_pct": 100,
		"materials_strategy": "local",
		"class_cost_reduction_pct": 0,
		"started_calendar_day": 1,
		"expected_halfway_day": 30,
		"expected_completion_day": 60,
		"cp_progressed": 0,
		"halfway_signal_fired": false,
		"status": "in_progress",
	})


func _delete_commissions() -> void:
	# Clear all commissions for the test domain so each test starts clean.
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM stronghold_commissions WHERE stronghold_id IN (
			SELECT id FROM strongholds WHERE domain_id = ?
		)
	""", [_domain_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM strongholds WHERE domain_id = ?", [_domain_id])


# ---------------------------------------------------------------------------

func test_oversee_construction_bumps_rate_by_5_pct() -> void:
	_delete_commissions()
	var cid := _make_commission(50000)  # 500 gp/day × 100 = 50,000 cp/day
	var state: Dictionary = {
		"id": "test_state_oversee",
		"character_id": _ruler_id,
	}
	var result: Dictionary = OverseeConstructionHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("525gp"),
		"summary should reflect new rate 52,500 cp = 525 gp (500 * 1.05), got: %s" % result.get("summary", ""))
	var commission := CampaignRepository.get_commission(cid)
	check(int(commission.get("daily_construction_rate_cp", 0)) == 52500,
		"commission rate should be 52500 cp, got %d" % int(commission.get("daily_construction_rate_cp", 0)))


func test_supervise_construction_bumps_rate_by_10_pct() -> void:
	_delete_commissions()
	var cid := _make_commission(50000)
	var state: Dictionary = {
		"id": "test_state_supervise",
		"character_id": _ruler_id,
	}
	var result: Dictionary = SuperviseConstructionHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("550gp"),
		"summary should reflect new rate 55,000 cp = 550 gp (500 * 1.10), got: %s" % result.get("summary", ""))
	var commission := CampaignRepository.get_commission(cid)
	check(int(commission.get("daily_construction_rate_cp", 0)) == 55000,
		"commission rate should be 55000 cp, got %d" % int(commission.get("daily_construction_rate_cp", 0)))


func test_oversee_no_active_commission_logs_ledger_no_op() -> void:
	_delete_commissions()
	var prior_entries: int = CampaignRepository.list_ledger_entries(_domain_id).size()
	var state: Dictionary = {
		"id": "test_state_oversee_noop",
		"character_id": _ruler_id,
	}
	var result: Dictionary = OverseeConstructionHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("no active commission"),
		"summary should mention no active commission, got: %s" % result.get("summary", ""))
	var entries := CampaignRepository.list_ledger_entries(_domain_id)
	check(entries.size() > prior_entries,
		"a ledger entry should still be written for the no-op case")
	var found: bool = false
	for e in entries:
		if String(e.get("subcategory", "")) == "oversee_construction_no_active_commission":
			found = true
			break
	check(found, "ledger should contain oversee_construction_no_active_commission subcategory")
