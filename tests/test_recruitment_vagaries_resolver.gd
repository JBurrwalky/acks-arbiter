extends "res://tests/test_suite_base.gd"

## Tests for RecruitmentVagariesResolver (Phase 6A).
##
## Covers:
##   - 19-row dispatch table coverage (every row resolves to a result_key)
##   - lookup() boundary correctness (low, mid, and high of each band)
##   - resolve() emits the recruitment_vagary_resolved signal
##   - Per-result payload shape (e.g., bidding_war months/multiplier ranges)
##   - list_recruiting_characters returns characters who launched recruitment activities


var _campaign_id: String = ""
var _signal_received: bool = false
var _signal_payload: Dictionary = {}
var _signal_result_key: String = ""


func run_all_tests() -> void:
	_setup()
	test_lookup_covers_all_bands()
	test_lookup_war_declared_low_boundary()
	test_lookup_alliance_offered_high_boundary()
	test_lookup_all_quiet_mid_band()
	test_resolve_emits_signal()
	test_bidding_war_payload_shape()
	test_war_profiteers_payload_shape()
	test_list_recruiting_characters_excludes_old_activities()
	if not has_failures():
		print("RecruitmentVagariesResolver: all tests passed.")


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Vagary Test", "World")


func test_lookup_covers_all_bands() -> void:
	# Every roll 1..100 should map to some defined result_key.
	for roll in range(1, 101):
		var result := RecruitmentVagariesResolver.lookup(roll)
		check(not String(result.get("result_key", "")).is_empty(),
			"roll %d returns a result_key" % roll)


func test_lookup_war_declared_low_boundary() -> void:
	check(String(RecruitmentVagariesResolver.lookup(1).get("result_key", "")) == "war_declared",
		"roll 1 → war_declared")
	check(String(RecruitmentVagariesResolver.lookup(2).get("result_key", "")) == "war_declared",
		"roll 2 → war_declared")
	check(String(RecruitmentVagariesResolver.lookup(3).get("result_key", "")) == "resignation",
		"roll 3 → resignation (next band)")


func test_lookup_alliance_offered_high_boundary() -> void:
	check(String(RecruitmentVagariesResolver.lookup(99).get("result_key", "")) == "alliance_offered",
		"roll 99 → alliance_offered")
	check(String(RecruitmentVagariesResolver.lookup(100).get("result_key", "")) == "alliance_offered",
		"roll 100 → alliance_offered")
	check(String(RecruitmentVagariesResolver.lookup(98).get("result_key", "")) == "bold_captain",
		"roll 98 → bold_captain (preceding band)")


func test_lookup_all_quiet_mid_band() -> void:
	for roll in [43, 50, 58]:
		check(String(RecruitmentVagariesResolver.lookup(roll).get("result_key", "")) == "all_quiet",
			"roll %d → all_quiet" % roll)


func test_resolve_emits_signal() -> void:
	_signal_received = false
	_signal_payload = {}
	_signal_result_key = ""
	EventBus.recruitment_vagary_resolved.connect(_on_signal)
	# Force a known roll via a fixed-result dice roller (returns 50 → all_quiet).
	var rolled := RecruitmentVagariesResolver.resolve(
		"act_001", "char_001", 1000,
		func(_count, _sides): return 50
	)
	EventBus.recruitment_vagary_resolved.disconnect(_on_signal)
	check(int(rolled.get("roll", 0)) == 50, "roll value 50 returned")
	check(String(rolled.get("result_key", "")) == "all_quiet", "all_quiet result")
	check(_signal_received, "signal received")
	check(_signal_result_key == "all_quiet", "signal result_key matches")


func _on_signal(activity_id: String, result_key: String, payload: Dictionary) -> void:
	_signal_received = true
	_signal_result_key = result_key
	_signal_payload = payload
	var _unused := activity_id
	check(true, "signal received with activity_id %s" % _unused)


func test_bidding_war_payload_shape() -> void:
	# Roll = 13..17 → bidding_war. Use a roller that returns 15 first then
	# the inner rolls (1d6, 2d4) deterministically.
	var roll_values := [15, 4, 5]  # outer d100 = 15, then 1d6 = 4, then 2d4 returns 5 (treated as one roll here)
	var idx := [0]
	var roller := func(_count: int, sides: int):
		var v: int = roll_values[idx[0]] if idx[0] < roll_values.size() else 1
		idx[0] += 1
		return v if v <= sides else sides
	var result := RecruitmentVagariesResolver.resolve("act_002", "char_002", 1000, roller)
	check(String(result.get("result_key", "")) == "bidding_war", "bidding_war result")
	var payload: Dictionary = result.get("payload", {})
	check(payload.has("months_active"), "payload has months_active")
	check(payload.has("mercenary_find_cost_multiplier"), "payload has multiplier")
	check(float(payload.get("mercenary_find_cost_multiplier", 0.0)) >= 1.0,
		"multiplier >= 1.0")


func test_war_profiteers_payload_shape() -> void:
	# Roll 38..42 → war_profiteers.
	var result := RecruitmentVagariesResolver.resolve(
		"act_003", "char_003", 1000,
		func(_count, _sides): return 40
	)
	check(String(result.get("result_key", "")) == "war_profiteers", "war_profiteers result")
	var payload: Dictionary = result.get("payload", {})
	check(float(payload.get("price_multiplier", 0.0)) == 1.10, "+10% multiplier")
	var cats: Array = payload.get("categories", [])
	check(cats.has("artillery") and cats.has("supplies"), "categories include artillery+supplies")


func test_list_recruiting_characters_excludes_old_activities() -> void:
	# Insert an activity_state row for a character at calendar_day 100.
	var character_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Recruiter', 'pc', 'full', 'human', 'fighter', 5,
			12, 12, 12, 12, 12, 12, 30, 30)
	""", [character_id, _campaign_id])
	var activity_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO activity_state (id, campaign_id, character_id, activity_def_id,
			frequency_type, status, started_calendar_day)
		VALUES (?, ?, ?, 'hire_mercenaries', 'singular', 'completed', 100)
	""", [activity_id, _campaign_id, character_id])
	# Window covers day 100.
	var recruiting := RecruitmentVagariesResolver.list_recruiting_characters(_campaign_id, 110, 30)
	check(recruiting.has(character_id), "character listed within window")
	# Window does not cover day 100 (looking back from day 200, window 30 → start 170).
	var recruiting2 := RecruitmentVagariesResolver.list_recruiting_characters(_campaign_id, 200, 30)
	check(not recruiting2.has(character_id), "character excluded outside window")
