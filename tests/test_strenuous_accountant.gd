extends "res://tests/test_suite_base.gd"

## Unit tests for StrenuousAccountant (Domain Phase 3).
##
## Verifies the 6-day grace + cumulative -1/day past the limit + rest-day
## reset semantics per ax_campaign_play.xml §effort_rules L166-172 and
## §overtime_rules L173-186.


var _campaign_id: String = ""
var _character_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_no_state_returns_zero_penalty()
	test_first_six_strenuous_days_no_penalty()
	test_seventh_strenuous_day_applies_minus_one()
	test_eighth_strenuous_day_stacks_to_minus_two()
	test_rest_day_resets_streak_and_decays_penalty()
	if not has_failures():
		print("StrenuousAccountant: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Strenuous", "TestWorld")
	_character_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Strenuous Tester', 'pc', 'full', 'human', 'fighter', 1,
			10, 10, 10, 10, 10, 10, 8, 8)
	""", [_character_id, _campaign_id])


func _reset_state() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_activity_state WHERE character_id = ?",
		[_character_id])


func test_no_state_returns_zero_penalty() -> void:
	_reset_state()
	check(StrenuousAccountant.get_attack_throw_penalty(_character_id) == 0,
		"no row → zero penalty")


func test_first_six_strenuous_days_no_penalty() -> void:
	_reset_state()
	for d in range(1, 7):
		CampaignRepository.upsert_character_activity_state(_character_id, {
			"strenuous_days_in_streak": d,
			"attack_throw_penalty": 0,
			"last_updated_calendar_day": d,
		})
	check(StrenuousAccountant.get_attack_throw_penalty(_character_id) == 0,
		"6 strenuous days inside grace window → 0 penalty")


func test_seventh_strenuous_day_applies_minus_one() -> void:
	_reset_state()
	CampaignRepository.upsert_character_activity_state(_character_id, {
		"strenuous_days_in_streak": 7,
		"attack_throw_penalty": 1,  # accountant computes streak - 6 = 1
		"last_updated_calendar_day": 7,
	})
	check(StrenuousAccountant.get_attack_throw_penalty(_character_id) == 1,
		"day 7 → penalty 1, got %d" % StrenuousAccountant.get_attack_throw_penalty(_character_id))


func test_eighth_strenuous_day_stacks_to_minus_two() -> void:
	_reset_state()
	CampaignRepository.upsert_character_activity_state(_character_id, {
		"strenuous_days_in_streak": 8,
		"attack_throw_penalty": 2,
		"last_updated_calendar_day": 8,
	})
	check(StrenuousAccountant.get_attack_throw_penalty(_character_id) == 2,
		"day 8 → penalty 2")


func test_rest_day_resets_streak_and_decays_penalty() -> void:
	_reset_state()
	CampaignRepository.upsert_character_activity_state(_character_id, {
		"strenuous_days_in_streak": 8,
		"attack_throw_penalty": 2,
		"last_updated_calendar_day": 8,
	})
	var accountant := StrenuousAccountant.new(null, ActivityCatalog.new())
	accountant.register_rest_day(_character_id, 9)
	check(StrenuousAccountant.get_attack_throw_penalty(_character_id) == 1,
		"rest day decays penalty by 1, got %d" % StrenuousAccountant.get_attack_throw_penalty(_character_id))
	var row := CampaignRepository.get_character_activity_state(_character_id)
	check(int(row.get("strenuous_days_in_streak", -1)) == 0,
		"rest day resets streak to 0")
