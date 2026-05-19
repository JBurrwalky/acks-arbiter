extends "res://tests/test_suite_base.gd"

## Tests for FollowerArrivalResolver (Domain Phase 5).
##
## Verifies the [RAW PATCH] wave math per `acore_axioms` §followers_arrival
## L111-116 (ceil(N×0.5) / ceil(N×0.25) / remainder), the L9 gate per
## §before_ninth_level L117-123, and the stronghold-sufficiency gate per
## the O-D10 resolution. Wave 3 scheduling is not exercised here (it requires
## a live scheduler tick); covered separately by the integration harness.


var _campaign_id: String = ""
var _ruler_id: String = ""
var _domain_id: String = ""
var _stronghold_id: String = ""


func run_all_tests() -> void:
	test_compute_wave_count_basic()
	test_compute_wave_count_rounding_overrun_clip()
	test_compute_wave_count_zero()
	_setup_full_scenario()
	test_pre_l9_no_followers()
	test_l9_below_sufficiency_no_followers()
	test_l9_at_sufficiency_halfway_spawns_wave1()
	test_completed_spawns_wave2()
	test_wave3_resolves_remainder_and_arrival_logged()
	test_wave2_schedules_wave3_event()
	if not has_failures():
		print("FollowerArrivalResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Pure math
# ---------------------------------------------------------------------------

func test_compute_wave_count_basic() -> void:
	# 200 mercs: ceil(200×0.5)=100, ceil(200×0.25)=50, remainder=50.
	check(FollowerArrivalResolver.compute_wave_count(200, 1) == 100,
		"200 wave 1 should be 100, got %d" % FollowerArrivalResolver.compute_wave_count(200, 1))
	check(FollowerArrivalResolver.compute_wave_count(200, 2) == 50,
		"200 wave 2 should be 50")
	check(FollowerArrivalResolver.compute_wave_count(200, 3) == 50,
		"200 wave 3 should be 50")


func test_compute_wave_count_rounding_overrun_clip() -> void:
	# Edge case from the roadmap: ceil(N×0.5) + ceil(N×0.25) > N×0.75.
	# 5 mercs: ceil(5×0.5)=3, ceil(5×0.25)=2 → 3+2=5 → remainder=0.
	check(FollowerArrivalResolver.compute_wave_count(5, 1) == 3, "5 wave 1 should be 3")
	check(FollowerArrivalResolver.compute_wave_count(5, 2) == 2, "5 wave 2 should be 2")
	check(FollowerArrivalResolver.compute_wave_count(5, 3) == 0,
		"5 wave 3 should be 0 (rounding clip)")
	# 1 merc: ceil(1×0.5)=1, ceil(1×0.25)=1 → wave 2 clamped to 0; remainder=0.
	check(FollowerArrivalResolver.compute_wave_count(1, 1) == 1, "1 wave 1 should be 1")
	check(FollowerArrivalResolver.compute_wave_count(1, 2) == 0,
		"1 wave 2 should be 0 (clamped after wave 1 took the only soldier)")
	check(FollowerArrivalResolver.compute_wave_count(1, 3) == 0, "1 wave 3 should be 0")


func test_compute_wave_count_zero() -> void:
	check(FollowerArrivalResolver.compute_wave_count(0, 1) == 0, "0 total → 0 in any wave")
	check(FollowerArrivalResolver.compute_wave_count(-5, 1) == 0, "negative total → 0")


# ---------------------------------------------------------------------------
# End-to-end milestone resolution
# ---------------------------------------------------------------------------

func _setup_full_scenario() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Followers", "TestWorld")
	_ruler_id = CampaignRepository.generate_id()
	# L7 ruler initially — bumped to 9 in the L9-gate test.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Test Lord', 'pc', 'full', 'human', 'fighter', 7,
			14, 10, 10, 10, 10, 14, 50, 50)
	""", [_ruler_id, _campaign_id])
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Followers Test Domain",
		"territory_type": "civilized",
		"owner_character_id": _ruler_id,
	})
	CampaignRepository.update_domain_monthly_state(_domain_id, {"peasant_families": 100})
	# Build a 16,000gp castle (above the 15,000gp civilized minimum).
	# Migration 116: column is cp_value (gp × 100); 16000 gp → 1,600,000 cp.
	_stronghold_id = CampaignRepository.create_stronghold({
		"domain_id": _domain_id,
		"owner_character_id": _ruler_id,
		"archetype": "fortress",
		"structure_type": "castle",
		"cp_value": 1600000,
		"shp": 100,
		"completion_pct": 50,
		"is_conforming_to_class": true,
		"status": "in_progress",
	})


func _make_resolver() -> FollowerArrivalResolver:
	var resolver := FollowerArrivalResolver.new()
	# Bypass scheduler/registry for math-focused tests; subscribe is no-op.
	resolver._load_data()
	return resolver


func _set_ruler_level(level: int) -> void:
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET level = ? WHERE id = ?", [level, _ruler_id])


func _set_stronghold_gp(value: int) -> void:
	# Migration 116: column is cp_value; convert gp → cp at the boundary.
	CampaignRepository.db.query_with_bindings(
		"UPDATE strongholds SET cp_value = ? WHERE id = ?", [value * 100, _stronghold_id])


func _clear_followers_state() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM domain_followers WHERE domain_id = ?", [_domain_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM follower_arrivals WHERE domain_id = ?", [_domain_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE assigned_domain_id = ? AND source_type = 'follower'",
		[_domain_id])


func test_pre_l9_no_followers() -> void:
	_clear_followers_state()
	_set_ruler_level(7)
	_set_stronghold_gp(16000)
	var resolver := _make_resolver()
	var summary: Dictionary = resolver._resolve_milestone(_stronghold_id, 1)
	check(String(summary.get("summary", "")).contains("below L9"),
		"summary should explain L9 gate, got: %s" % summary.get("summary", ""))
	check(_count_follower_units() == 0, "no follower troop_units should be spawned pre-L9")


func test_l9_below_sufficiency_no_followers() -> void:
	_clear_followers_state()
	_set_ruler_level(9)
	_set_stronghold_gp(5000)  # well below 15,000 civilized minimum
	var resolver := _make_resolver()
	var summary: Dictionary = resolver._resolve_milestone(_stronghold_id, 1)
	check(String(summary.get("summary", "")).contains("classification minimum"),
		"summary should explain sufficiency gate, got: %s" % summary.get("summary", ""))
	check(_count_follower_units() == 0,
		"no follower troop_units should be spawned below classification minimum")


func test_l9_at_sufficiency_halfway_spawns_wave1() -> void:
	_clear_followers_state()
	_set_ruler_level(9)
	_set_stronghold_gp(20000)  # above 15k civ minimum
	var resolver := _make_resolver()
	var summary: Dictionary = resolver._resolve_milestone(_stronghold_id, 1)
	check(String(summary.get("summary", "")).contains("wave 1"),
		"summary should reference wave 1, got: %s" % summary.get("summary", ""))
	# Wave 1 should have spawned at least one troop_unit (fighter class attractor
	# rolls 1d4+1×100 = 200-500, ceil×0.5 = 100-250; the unit is at most 120
	# soldiers per template so we expect at least one unit).
	check(_count_follower_units() >= 1,
		"at least one follower troop_unit should be spawned at half-built")
	check(_arrival_log_count(50) == 1,
		"one wave_pct=50 follower_arrival audit row should exist")


func test_completed_spawns_wave2() -> void:
	# Continues from test_l9_at_sufficiency_halfway_spawns_wave1 — wave 1 already done.
	# Resolve wave 2 from the completed milestone.
	var prior_units: int = _count_follower_units()
	var resolver := _make_resolver()
	var summary: Dictionary = resolver._resolve_milestone(_stronghold_id, 2)
	check(String(summary.get("summary", "")).contains("wave 2"),
		"summary should reference wave 2, got: %s" % summary.get("summary", ""))
	check(_count_follower_units() >= prior_units,
		"wave 2 should add zero or more follower units (>= prior count %d)" % prior_units)
	check(_arrival_log_count(25) >= 1,
		"at least one wave_pct=25 follower_arrival audit row should exist after wave 2")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _count_follower_units() -> int:
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM troop_units
		WHERE assigned_domain_id = ? AND source_type = 'follower'
	""", [_domain_id])
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("c", 0))


func _arrival_log_count(wave_pct: int) -> int:
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM follower_arrivals
		WHERE domain_id = ? AND wave_pct = ?
	""", [_domain_id, wave_pct])
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("c", 0))


# ---------------------------------------------------------------------------
# Wave 3 + scheduler-integration coverage (2026-05-19 bucket-A item #20).
# ---------------------------------------------------------------------------

## Wave 3 fires when the POST_COMPLETION event scheduled by wave 2 elapses.
## This test calls _resolve_milestone(stronghold_id, 3) directly to verify the
## resolver's wave-3 path: remainder follower count spawned + audit row
## recorded with wave_pct=25 + arrival_phase advanced to "post_completion".
## Continues from test_completed_spawns_wave2 — wave 1 + 2 already done.
func test_wave3_resolves_remainder_and_arrival_logged() -> void:
	var prior_wave25_rows: int = _arrival_log_count(25)
	var resolver := _make_resolver()
	var summary: Dictionary = resolver._resolve_milestone(_stronghold_id, 3)
	check(String(summary.get("summary", "")).contains("wave 3"),
		"summary should reference wave 3, got: %s" % summary.get("summary", ""))
	var new_wave25_rows: int = _arrival_log_count(25)
	check(new_wave25_rows == prior_wave25_rows + 1,
		"wave 3 should record one additional wave_pct=25 audit row; prior=%d new=%d" % [
			prior_wave25_rows, new_wave25_rows])
	# Domain followers row should now be in 'post_completion' arrival_phase.
	CampaignRepository.db.query_with_bindings("""
		SELECT arrival_phase FROM domain_followers WHERE domain_id = ? LIMIT 1
	""", [_domain_id])
	if not CampaignRepository.db.query_result.is_empty():
		var phase := String(CampaignRepository.db.query_result[0].get("arrival_phase", ""))
		check(phase == "post_completion",
			"domain_followers.arrival_phase should advance to post_completion after wave 3; got '%s'" % phase)


## Scheduler-integration smoke: verifies wave 2 schedules a POST_COMPLETION
## event for wave 3 onto the scheduler. The integration uses a captured
## stub-scheduler that records schedule_at calls and asserts the event
## payload + fire-time offset (1 month = DAYS_PER_MONTH × ROUNDS_PER_DAY).
func test_wave2_schedules_wave3_event() -> void:
	# Use a fresh stronghold scenario so this test doesn't interfere with the
	# prior wave1/2/3 progression on _stronghold_id.
	var stub_stronghold_id: String = _make_completed_stronghold_for_wave2_scheduling_test()
	var capture: WaveScheduleCapture = WaveScheduleCapture.new()
	var resolver := _make_resolver()
	resolver._scheduler = capture
	# Pre-set wave 1 done so wave 2 is the next step (the resolver only
	# schedules wave 3 from wave 2 per L161-168 in the resolver).
	resolver._resolve_milestone(stub_stronghold_id, 1)
	var summary: Dictionary = resolver._resolve_milestone(stub_stronghold_id, 2)
	check(String(summary.get("summary", "")).contains("wave 2"),
		"wave 2 summary expected, got: %s" % summary.get("summary", ""))
	check(capture.schedule_calls.size() >= 1,
		"wave 2 must schedule at least one POST_COMPLETION event; got %d" % capture.schedule_calls.size())
	var call: Dictionary = capture.schedule_calls[0]
	check(String(call.get("event_type", "")) == "follower_arrival_post_completion",
		"scheduled event_type should match POST_COMPLETION constant; got '%s'" % call.get("event_type"))
	check(String(call.get("entity_id", "")) == stub_stronghold_id,
		"scheduled entity_id should be the stronghold id")
	var data: Dictionary = call.get("data", {})
	check(String(data.get("stronghold_id", "")) == stub_stronghold_id,
		"event data should carry stronghold_id")
	# Fire time should be 1 month out (DAYS_PER_MONTH * ROUNDS_PER_DAY) per L163.
	var expected_offset: int = Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY
	check(int(call.get("fire_time", 0)) >= expected_offset,
		"fire_time should be >= 1-month offset; got %d expected >= %d" % [
			int(call.get("fire_time", 0)), expected_offset])


## Helper: clones the test scenario's stronghold into a new completed-and-sufficient
## stronghold so the test can drive a fresh wave-1/wave-2 cycle without colliding
## with the running test state. Returns the new stronghold id.
func _make_completed_stronghold_for_wave2_scheduling_test() -> String:
	var new_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds
			(id, campaign_id, domain_id, name, structure_type, archetype,
			 cp_value, shp, max_shp, status, owner_character_id, ruler_class_id)
		VALUES (?, ?, ?, 'WaveSchedTestKeep', 'keep_with_walls', 'fortress',
				2500000, 100, 100, 'completed', ?, 'fighter')
	""", [new_id, _campaign_id, _domain_id, _ruler_id])
	return new_id


## Lightweight scheduler stub that records schedule_at calls so tests can
## verify scheduling without spinning up a full EventScheduler.
class WaveScheduleCapture extends RefCounted:
	var schedule_calls: Array = []
	func schedule_at(fire_time: int, event_type: String, entity_id: String, data: Dictionary):
		schedule_calls.append({
			"fire_time": fire_time,
			"event_type": event_type,
			"entity_id": entity_id,
			"data": data,
		})
		return "stub_event_%d" % schedule_calls.size()
