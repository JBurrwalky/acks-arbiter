extends "res://tests/test_suite_base.gd"

## Unit tests for V2 SettlementHandlers.schedule_travel.
##
## Verifies the simplified travel cost contract:
##   - same-district travel = 1 turn (60 rounds) + 1 encounter check
##   - cross-district travel = 1 hour (360 rounds) + 2 encounter checks
##   - encounter checks are tagged with the right district_id
##   - cancel_travel removes both arrival and encounter check events
##   - SettlementExploreState._is_nighttime() (the is_night source for
##     schedule_travel) follows Timekeeping's dawn/dusk day cycle
##
## See gdd-settlement-exploration-ui.md v2 §5.


const PARTY_ID := "test_party_handlers_v2"
const CAMPAIGN_ID := "test_campaign"
const SETTLEMENT_ID := "test_settlement"


func run_all_tests() -> void:
	test_same_district_one_turn_one_encounter_check()
	test_cross_district_one_hour_two_encounter_checks()
	test_same_district_destination_same_as_origin_returns_empty()
	test_unknown_destination_returns_empty()
	test_cancel_travel_removes_all_pending_events()
	test_district_encounter_modifier_changes_threshold()
	test_is_nighttime_follows_timekeeping_day_cycle()
	if not has_failures():
		print("SettlementHandlersV2: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_settlement() -> SettlementMapData:
	return SettlementMapData.from_dict({
		"id": "handlers_test_city",
		"name": "Handlers Test City",
		"market_class": 4,
		"districts": [
			{
				"id": "d_origin",
				"name": "Origin District",
				"type": "village_center",
				"encounter_modifier": "default",
				"pois": [
					{"id": "origin_poi", "name": "Origin", "type": "tavern",
						"is_entry_exit": false, "importance": "major"},
					{"id": "origin_neighbor", "name": "Origin Neighbor", "type": "shop",
						"is_entry_exit": false, "importance": "minor"},
				],
			},
			{
				"id": "d_dest",
				"name": "Destination District",
				"type": "market",
				"encounter_modifier": "high-crime",
				"pois": [
					{"id": "dest_poi", "name": "Destination", "type": "market",
						"is_entry_exit": false, "importance": "major"},
				],
			},
		],
	})


func _make_handlers() -> SettlementHandlers:
	# Pass null runner — schedule_travel and cancel_travel do not use it.
	return SettlementHandlers.new(null)


func _make_scheduler() -> EventScheduler:
	return EventScheduler.new()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_same_district_one_turn_one_encounter_check() -> void:
	var settlement := _make_settlement()
	var handlers := _make_handlers()
	var scheduler := _make_scheduler()
	var start_time: int = Timekeeping.get_total_rounds()

	var result := handlers.schedule_travel(
		settlement, "origin_poi", "origin_neighbor",
		scheduler, PARTY_ID, CAMPAIGN_ID, SETTLEMENT_ID, false)

	check(not result.is_empty(), "result not empty")
	check(result.get("is_same_district", false),
		"travel within d_origin is same-district")
	check(result.get("total_rounds", 0) == Timekeeping.ROUNDS_PER_TURN,
		"same-district travel = 1 turn (%d rounds), got %d" %
		[Timekeeping.ROUNDS_PER_TURN, result.get("total_rounds", 0)])

	var owner_events: Array[ScheduledEvent] = scheduler.get_events_for_owner(PARTY_ID)
	var arrivals := 0
	var encounter_checks := 0
	for ev in owner_events:
		if ev.event_type == "city_travel_arrival":
			arrivals += 1
			check(ev.fire_time == start_time + Timekeeping.ROUNDS_PER_TURN,
				"arrival fires at start + 1 turn")
		elif ev.event_type == "city_encounter_check":
			encounter_checks += 1
			check(ev.data.get("district_id", "") == "d_origin",
				"intra-district check tagged with origin district, got '%s'" %
				ev.data.get("district_id", ""))
	check(arrivals == 1, "exactly 1 arrival, got %d" % arrivals)
	check(encounter_checks == 1, "exactly 1 encounter check, got %d" % encounter_checks)
	print("  same_district_one_turn_one_encounter_check: OK")


func test_cross_district_one_hour_two_encounter_checks() -> void:
	var settlement := _make_settlement()
	var handlers := _make_handlers()
	var scheduler := _make_scheduler()
	var start_time: int = Timekeeping.get_total_rounds()

	var result := handlers.schedule_travel(
		settlement, "origin_poi", "dest_poi",
		scheduler, PARTY_ID, CAMPAIGN_ID, SETTLEMENT_ID, false)

	check(not result.is_empty(), "result not empty")
	check(not result.get("is_same_district", true),
		"travel d_origin -> d_dest is cross-district")
	check(result.get("total_rounds", 0) == 6 * Timekeeping.ROUNDS_PER_TURN,
		"cross-district travel = 1 hour (%d rounds), got %d" %
		[6 * Timekeeping.ROUNDS_PER_TURN, result.get("total_rounds", 0)])

	var owner_events: Array[ScheduledEvent] = scheduler.get_events_for_owner(PARTY_ID)
	var arrivals := 0
	var origin_checks := 0
	var dest_checks := 0
	for ev in owner_events:
		if ev.event_type == "city_travel_arrival":
			arrivals += 1
			check(ev.fire_time == start_time + 6 * Timekeeping.ROUNDS_PER_TURN,
				"arrival fires at start + 6 turns")
		elif ev.event_type == "city_encounter_check":
			var d_id: String = ev.data.get("district_id", "")
			if d_id == "d_origin":
				origin_checks += 1
			elif d_id == "d_dest":
				dest_checks += 1
	check(arrivals == 1, "exactly 1 arrival, got %d" % arrivals)
	check(origin_checks == 1, "exactly 1 origin-tagged encounter check, got %d" % origin_checks)
	check(dest_checks == 1, "exactly 1 dest-tagged encounter check, got %d" % dest_checks)
	print("  cross_district_one_hour_two_encounter_checks: OK")


func test_same_district_destination_same_as_origin_returns_empty() -> void:
	var settlement := _make_settlement()
	var handlers := _make_handlers()
	var scheduler := _make_scheduler()

	var result := handlers.schedule_travel(
		settlement, "origin_poi", "origin_poi",
		scheduler, PARTY_ID, CAMPAIGN_ID, SETTLEMENT_ID, false)

	check(result.is_empty(), "scheduling travel to current PoI returns empty")
	check(scheduler.size() == 0, "no events scheduled")
	print("  same_district_destination_same_as_origin_returns_empty: OK")


func test_unknown_destination_returns_empty() -> void:
	var settlement := _make_settlement()
	var handlers := _make_handlers()
	var scheduler := _make_scheduler()

	var result := handlers.schedule_travel(
		settlement, "origin_poi", "does_not_exist",
		scheduler, PARTY_ID, CAMPAIGN_ID, SETTLEMENT_ID, false)

	check(result.is_empty(), "unknown destination PoI returns empty")
	check(scheduler.size() == 0, "no events scheduled")
	print("  unknown_destination_returns_empty: OK")


func test_cancel_travel_removes_all_pending_events() -> void:
	var settlement := _make_settlement()
	var handlers := _make_handlers()
	var scheduler := _make_scheduler()

	# Cross-district = 1 arrival + 2 encounter checks = 3 events.
	handlers.schedule_travel(
		settlement, "origin_poi", "dest_poi",
		scheduler, PARTY_ID, CAMPAIGN_ID, SETTLEMENT_ID, false)
	check(scheduler.size() == 3, "3 events scheduled before cancel, got %d" % scheduler.size())
	check(handlers.is_traveling(PARTY_ID), "is_traveling true after schedule")

	var cancelled: int = handlers.cancel_travel(scheduler, PARTY_ID)
	check(cancelled == 3, "3 events cancelled, got %d" % cancelled)
	check(not handlers.is_traveling(PARTY_ID), "is_traveling false after cancel")

	# get_events_for_owner skips cancelled events.
	var remaining: Array[ScheduledEvent] = scheduler.get_events_for_owner(PARTY_ID)
	check(remaining.is_empty(),
		"no live owner events remain after cancel, got %d" % remaining.size())
	print("  cancel_travel_removes_all_pending_events: OK")


func test_district_encounter_modifier_changes_threshold() -> void:
	var settlement := _make_settlement()
	var handlers := _make_handlers()
	var scheduler := _make_scheduler()

	# Cross-district trip into d_dest, which is "high-crime" (threshold 5+).
	handlers.schedule_travel(
		settlement, "origin_poi", "dest_poi",
		scheduler, PARTY_ID, CAMPAIGN_ID, SETTLEMENT_ID, false)

	var owner_events: Array[ScheduledEvent] = scheduler.get_events_for_owner(PARTY_ID)
	for ev in owner_events:
		if ev.event_type != "city_encounter_check":
			continue
		var d_id: String = ev.data.get("district_id", "")
		var threshold: int = int(ev.data.get("threshold", 0))
		if d_id == "d_origin":
			check(threshold == SettlementHandlers.ENCOUNTER_THRESHOLD_DEFAULT,
				"d_origin (default) threshold = %d, got %d" %
				[SettlementHandlers.ENCOUNTER_THRESHOLD_DEFAULT, threshold])
		elif d_id == "d_dest":
			check(threshold == SettlementHandlers.ENCOUNTER_THRESHOLD_HIGH_CRIME,
				"d_dest (high-crime) threshold = %d, got %d" %
				[SettlementHandlers.ENCOUNTER_THRESHOLD_HIGH_CRIME, threshold])
	print("  district_encounter_modifier_changes_threshold: OK")


func test_is_nighttime_follows_timekeeping_day_cycle() -> void:
	# _is_nighttime() must delegate to Timekeeping.is_daylight() — dawn/dusk
	# driven, season-adjustable — not the old hardcoded 18:00–06:00
	# approximation (handoff_multi_party_time.md §3.1, fixed 2026-06-12).
	# Private vars are assigned directly (test_timekeeping.gd pattern) so no
	# transient day cycle is persisted to the loaded campaign.
	var saved_rounds: int = Timekeeping._elapsed_rounds
	var saved_dawn: int = Timekeeping._dawn_hour
	var saved_dusk: int = Timekeeping._dusk_hour

	var state := SettlementExploreState.new()
	state._runner = RefCounted.new()  # non-null; _is_nighttime only null-checks it

	# Default cycle (dawn=6, dusk=20). Hours 18–19 are the regression hours:
	# the old approximation called them night.
	Timekeeping._dawn_hour = 6
	Timekeeping._dusk_hour = 20
	Timekeeping._elapsed_rounds = 19 * Timekeeping.ROUNDS_PER_HOUR
	check(state._is_nighttime() == false, "hour 19 is daytime with default dusk=20")
	Timekeeping._elapsed_rounds = 20 * Timekeeping.ROUNDS_PER_HOUR
	check(state._is_nighttime() == true, "hour 20 is night with default dusk=20")
	Timekeeping._elapsed_rounds = 5 * Timekeeping.ROUNDS_PER_HOUR
	check(state._is_nighttime() == true, "hour 5 is night with default dawn=6")
	Timekeeping._elapsed_rounds = 6 * Timekeeping.ROUNDS_PER_HOUR
	check(state._is_nighttime() == false, "hour 6 is daytime with default dawn=6")

	# Seasonal short day (dawn=8, dusk=16): hour 17 flips to night.
	Timekeeping._dawn_hour = 8
	Timekeeping._dusk_hour = 16
	Timekeeping._elapsed_rounds = 17 * Timekeeping.ROUNDS_PER_HOUR
	check(state._is_nighttime() == true, "hour 17 is night with seasonal dusk=16")

	# Null-runner guard preserved.
	state._runner = null
	check(state._is_nighttime() == false, "null runner returns false (guard)")

	Timekeeping._dawn_hour = saved_dawn
	Timekeeping._dusk_hour = saved_dusk
	Timekeeping._elapsed_rounds = saved_rounds
	print("  is_nighttime_follows_timekeeping_day_cycle: OK")
