extends "res://tests/test_suite_base.gd"

## Tests for the camp encounter throw + hybrid encounter-gate rule introduced
## in gdd-realtime-scheduler.md §4.3 (revised 2026-05-27).
##
## Covers:
##   * `CampHandlers.schedule_watches` — stamps camp state on PartyData, runs
##     the gated camp encounter throw, and schedules a `wilderness_encounter`
##     event at a uniform hour-within-camp on a positive throw. Verifies the
##     three watch markers + rest_complete are still scheduled.
##   * Gate behavior — camp throw is gated on `last_encounter_trigger_day`.
##     A party that has already had a wilderness encounter today does NOT
##     get a camp throw. A party with a stale (or -1) gate flag does.
##   * `CampHandlers._handle_camp_watch` returns a state/UX-only result with
##     no enter_combat / no auto_pause / no encounter_data.
##   * `CampHandlers.clear_camp_state` cancels any pending wilderness_encounter
##     event for the party and clears the camp_* fields on PartyData.
##   * `WildernessHandlers._compute_camp_surprise_context` returns the correct
##     observer state for fire_times in each watch, applies the Hear Noises
##     18+ throw to sleepers, and falls back to passively_watching when the
##     fire_time is outside the camp window.
##
## Dice control is via GameState.dice_overrides (DiceTestHarness pattern,
## conventions §56). Roll types overridden here: "camp_encounter_check",
## "camp_encounter_hour", "hear_noises".


const PARTY_PREFIX := "test_camp_gate_"
const CAMPAIGN_ID := "test_camp_gate_campaign"


# ---------------------------------------------------------------------------
# Fake runner: minimal stand-in for SessionRunner. The camp throw reads only
# get_hex_map_controller (we return null → terrain check is skipped, so the
# throw proceeds) and get_party_data / get_party_id (resolves to our fixture
# PartyData). get_scheduler is used by clear_camp_state to cancel events.
# ---------------------------------------------------------------------------

class _FakeRunner:
	var _party_id: String = ""
	var _party_data: PartyData = null
	var _scheduler: EventScheduler = null

	func get_party_id() -> String:
		return _party_id

	func get_party_data() -> PartyData:
		return _party_data

	func get_hex_map_controller():
		return null  # no terrain check → camp throw proceeds

	func get_scheduler() -> EventScheduler:
		return _scheduler


# ---------------------------------------------------------------------------
# Test entry
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_schedule_watches_stamps_camp_state_on_party_data()
	test_schedule_watches_runs_camp_throw_on_positive_roll()
	test_schedule_watches_skips_throw_on_negative_roll()
	test_camp_throw_gated_when_encounter_already_triggered_today()
	test_camp_throw_stamps_gate_on_positive_trigger()
	test_handle_camp_watch_is_state_ux_only()
	test_clear_camp_state_cancels_pending_wilderness_encounter()
	test_compute_camp_surprise_observer_states()
	test_compute_camp_surprise_hear_noises_18plus_rouses()
	test_compute_camp_surprise_outside_camp_window()
	if not has_failures():
		print("CampEncounterGate: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party_id(suffix: String) -> String:
	return PARTY_PREFIX + suffix


func _ensure_party_row(party_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "test camp gate"])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[party_id, CAMPAIGN_ID, "Test Camp Gate Party"])


func _cleanup_party(party_id: String) -> void:
	Timekeeping.unregister_party(party_id)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])
	DiceTestHarness.clear_all()


func _make_party_data(party_id: String) -> PartyData:
	var pd := PartyData.new()
	pd.id = party_id
	pd.campaign_id = CAMPAIGN_ID
	pd.name = "Test Camp Gate Party"
	pd.character_data = []
	# Three party members for full watch coverage (one per watch).
	for member_name in ["alice", "bob", "carol"]:
		var cd := CharacterData.new()
		cd.id = member_name
		cd.name = member_name.capitalize()
		cd.hp_max = 10
		cd.hp_current = 10
		pd.character_data.append(cd)
	return pd


func _three_watch_assignments() -> Array:
	return [["alice"], ["bob"], ["carol"]]


# ---------------------------------------------------------------------------
# schedule_watches tests
# ---------------------------------------------------------------------------

func test_schedule_watches_stamps_camp_state_on_party_data() -> void:
	var pid := _make_party_id("stamp")
	_ensure_party_row(pid)
	Timekeeping.unregister_party(pid)
	Timekeeping.register_party(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	runner._scheduler = EventScheduler.new()

	# Force a negative camp throw so we isolate the stamping behavior from
	# the encounter-scheduling behavior (tested separately below).
	DiceTestHarness.force_roll("camp_encounter_check", 6)

	var handlers := CampHandlers.new(runner)
	var camp_start: int = Timekeeping.get_party_time(pid)
	handlers.schedule_watches(_three_watch_assignments(), [], runner._scheduler, pid)

	var pd := runner._party_data
	check(pd.is_camping, "is_camping=true after schedule_watches")
	check(pd.camp_start_round == camp_start,
		"camp_start_round = party time at schedule, got %d (expected %d)" %
		[pd.camp_start_round, camp_start])
	var expected_end: int = camp_start + (CampManager.TOTAL_REST_HOURS * Timekeeping.ROUNDS_PER_HOUR)
	check(pd.camp_end_round == expected_end,
		"camp_end_round = start + 12h, got %d (expected %d)" %
		[pd.camp_end_round, expected_end])

	var parsed_assignments: Variant = JSON.parse_string(pd.camp_watch_assignments_json)
	check(parsed_assignments is Array and parsed_assignments.size() == 3,
		"camp_watch_assignments_json parses to a 3-element Array")

	# The three watch markers + the rest_complete event are still scheduled.
	var events: Array[ScheduledEvent] = runner._scheduler.get_events_for_owner(pid)
	var watch_count := 0
	var rest_count := 0
	for e: ScheduledEvent in events:
		if e.event_type == "camp_watch":
			watch_count += 1
		elif e.event_type == "camp_rest_complete":
			rest_count += 1
	check(watch_count == CampManager.WATCH_COUNT,
		"3 camp_watch markers scheduled, got %d" % watch_count)
	check(rest_count == 1, "1 camp_rest_complete scheduled, got %d" % rest_count)

	_cleanup_party(pid)


func test_schedule_watches_runs_camp_throw_on_positive_roll() -> void:
	var pid := _make_party_id("throw_pos")
	_ensure_party_row(pid)
	Timekeeping.unregister_party(pid)
	Timekeeping.register_party(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	runner._scheduler = EventScheduler.new()

	# Positive 1-in-6 throw + force the hour-within-camp roll to 3 (offset 2).
	DiceTestHarness.force_roll("camp_encounter_check", 1)
	DiceTestHarness.force_roll("camp_encounter_hour", 3)

	var handlers := CampHandlers.new(runner)
	var camp_start: int = Timekeeping.get_party_time(pid)
	handlers.schedule_watches(_three_watch_assignments(), [], runner._scheduler, pid)

	var events: Array[ScheduledEvent] = runner._scheduler.get_events_for_owner(pid)
	var encounter_events: Array[ScheduledEvent] = []
	for e: ScheduledEvent in events:
		if e.event_type == WildernessHandlers.WILDERNESS_ENCOUNTER_EVENT:
			encounter_events.append(e)
	check(encounter_events.size() == 1,
		"one wilderness_encounter scheduled, got %d" % encounter_events.size())
	if encounter_events.size() == 1:
		var expected_fire: int = camp_start + 2 * Timekeeping.ROUNDS_PER_HOUR
		check(encounter_events[0].fire_time == expected_fire,
			"wilderness_encounter fires at camp_start + 2h (%d), got %d" %
			[expected_fire, encounter_events[0].fire_time])
		check(encounter_events[0].data.get("trigger_source", "") == "camp",
			"event data tags trigger_source='camp'")

	_cleanup_party(pid)


func test_schedule_watches_skips_throw_on_negative_roll() -> void:
	var pid := _make_party_id("throw_neg")
	_ensure_party_row(pid)
	Timekeeping.unregister_party(pid)
	Timekeeping.register_party(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	runner._scheduler = EventScheduler.new()

	DiceTestHarness.force_roll("camp_encounter_check", 6)  # miss

	var handlers := CampHandlers.new(runner)
	handlers.schedule_watches(_three_watch_assignments(), [], runner._scheduler, pid)

	var events: Array[ScheduledEvent] = runner._scheduler.get_events_for_owner(pid)
	for e: ScheduledEvent in events:
		check(e.event_type != WildernessHandlers.WILDERNESS_ENCOUNTER_EVENT,
			"no wilderness_encounter scheduled on negative throw")

	# Gate flag is NOT stamped on a negative throw — the day still has its
	# quota open for a later travel-leg trigger.
	check(runner._party_data.last_encounter_trigger_day == -1,
		"last_encounter_trigger_day unchanged on negative throw, got %d" %
		runner._party_data.last_encounter_trigger_day)

	_cleanup_party(pid)


# ---------------------------------------------------------------------------
# Gate behavior
# ---------------------------------------------------------------------------

func test_camp_throw_gated_when_encounter_already_triggered_today() -> void:
	var pid := _make_party_id("gated")
	_ensure_party_row(pid)
	Timekeeping.unregister_party(pid)
	Timekeeping.register_party(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	runner._scheduler = EventScheduler.new()

	# Pre-stamp the gate to today.
	@warning_ignore("integer_division")
	var today_index: int = Timekeeping.get_party_time(pid) / Timekeeping.ROUNDS_PER_DAY
	runner._party_data.last_encounter_trigger_day = today_index

	# Even with a forced positive throw, the gate must suppress it. Setting
	# the override anyway proves the gate runs before the roll.
	DiceTestHarness.force_roll("camp_encounter_check", 1)
	DiceTestHarness.force_roll("camp_encounter_hour", 1)

	var handlers := CampHandlers.new(runner)
	handlers.schedule_watches(_three_watch_assignments(), [], runner._scheduler, pid)

	var events: Array[ScheduledEvent] = runner._scheduler.get_events_for_owner(pid)
	for e: ScheduledEvent in events:
		check(e.event_type != WildernessHandlers.WILDERNESS_ENCOUNTER_EVENT,
			"gated camp produces no wilderness_encounter")

	# The forced overrides remain unconsumed (gate stopped before the roll).
	# Don't assert this directly — DiceTestHarness.clear_all in cleanup
	# tolerates leftover entries.
	_cleanup_party(pid)


func test_camp_throw_stamps_gate_on_positive_trigger() -> void:
	var pid := _make_party_id("stamp_gate")
	_ensure_party_row(pid)
	Timekeeping.unregister_party(pid)
	Timekeeping.register_party(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	runner._scheduler = EventScheduler.new()

	DiceTestHarness.force_roll("camp_encounter_check", 1)
	DiceTestHarness.force_roll("camp_encounter_hour", 5)

	var handlers := CampHandlers.new(runner)
	@warning_ignore("integer_division")
	var expected_day: int = Timekeeping.get_party_time(pid) / Timekeeping.ROUNDS_PER_DAY
	handlers.schedule_watches(_three_watch_assignments(), [], runner._scheduler, pid)

	check(runner._party_data.last_encounter_trigger_day == expected_day,
		"last_encounter_trigger_day stamped to today (%d), got %d" %
		[expected_day, runner._party_data.last_encounter_trigger_day])

	_cleanup_party(pid)


# ---------------------------------------------------------------------------
# camp_watch handler
# ---------------------------------------------------------------------------

func test_handle_camp_watch_is_state_ux_only() -> void:
	var runner := _FakeRunner.new()
	var handlers := CampHandlers.new(runner)
	var event := ScheduledEvent.new()
	event.event_type = "camp_watch"
	event.owner_id = "test_party"
	event.fire_time = 0
	event.data = {"watch_index": 1}

	var result: Dictionary = handlers._handle_camp_watch(event)
	check(not result.get("enter_combat", false),
		"camp_watch result has no enter_combat")
	check(not result.get("auto_pause", false),
		"camp_watch result has no auto_pause")
	check(not result.has("encounter_data"),
		"camp_watch result has no encounter_data")
	var presentation: Dictionary = result.get("presentation", {})
	check(presentation.get("type", "") == "camp_watch_boundary",
		"presentation.type == 'camp_watch_boundary'")
	check(presentation.get("watch_index", -1) == 1,
		"presentation.watch_index passed through")


# ---------------------------------------------------------------------------
# clear_camp_state
# ---------------------------------------------------------------------------

func test_clear_camp_state_cancels_pending_wilderness_encounter() -> void:
	var pid := _make_party_id("clear")
	_ensure_party_row(pid)
	Timekeeping.unregister_party(pid)
	Timekeeping.register_party(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	runner._scheduler = EventScheduler.new()

	# Manually schedule a wilderness_encounter to simulate a pending camp
	# encounter from an earlier camp_setup.
	runner._scheduler.schedule_at(
		Timekeeping.get_party_time(pid) + 4 * Timekeeping.ROUNDS_PER_HOUR,
		WildernessHandlers.WILDERNESS_ENCOUNTER_EVENT,
		pid,
		{"trigger_source": "camp"},
		ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
	)
	runner._party_data.is_camping = true
	runner._party_data.camp_start_round = Timekeeping.get_party_time(pid)
	runner._party_data.camp_end_round = runner._party_data.camp_start_round + 12 * Timekeeping.ROUNDS_PER_HOUR
	runner._party_data.camp_watch_assignments_json = JSON.stringify(_three_watch_assignments())

	var handlers := CampHandlers.new(runner)
	handlers.clear_camp_state(pid, runner._party_data)

	var events: Array[ScheduledEvent] = runner._scheduler.get_events_for_owner(pid)
	for e: ScheduledEvent in events:
		check(e.event_type != WildernessHandlers.WILDERNESS_ENCOUNTER_EVENT,
			"clear_camp_state cancelled pending wilderness_encounter")

	check(not runner._party_data.is_camping, "is_camping cleared")
	check(runner._party_data.camp_start_round == -1, "camp_start_round reset to -1")
	check(runner._party_data.camp_end_round == -1, "camp_end_round reset to -1")
	check(runner._party_data.camp_watch_assignments_json == "[]",
		"camp_watch_assignments_json reset to '[]'")

	_cleanup_party(pid)


# ---------------------------------------------------------------------------
# _compute_camp_surprise_context
# ---------------------------------------------------------------------------

func _make_camping_party(party_id: String, camp_start: int) -> PartyData:
	var pd := _make_party_data(party_id)
	pd.is_camping = true
	pd.camp_start_round = camp_start
	pd.camp_end_round = camp_start + CampManager.TOTAL_REST_HOURS * Timekeeping.ROUNDS_PER_HOUR
	pd.camp_watch_assignments_json = JSON.stringify(_three_watch_assignments())
	pd.camp_armed_sleepers_json = "[]"
	return pd


func test_compute_camp_surprise_observer_states() -> void:
	var pd := _make_camping_party("ctx_observers", 0)
	# Hour 2 (mid-watch-0): alice on duty; bob & carol asleep.
	# Force hear_noises = 1 so sleepers stay distracted_or_not_looking (unroused).
	DiceTestHarness.force_roll("hear_noises", 1)
	var handlers := WildernessHandlers.new(null)
	var fire_time: int = 2 * Timekeeping.ROUNDS_PER_HOUR
	var ctx: Dictionary = handlers._compute_camp_surprise_context(pd, fire_time)

	check(ctx.get("watch_index", -99) == 0,
		"hour 2 → watch_index 0, got %d" % ctx.get("watch_index", -99))
	var states: Dictionary = ctx.get("observer_states", {})
	check(states.get("alice", "") == "actively_watching",
		"alice on watch 0 → actively_watching, got '%s'" % states.get("alice", ""))
	check(states.get("bob", "") == "distracted_or_not_looking",
		"bob asleep → distracted_or_not_looking, got '%s'" % states.get("bob", ""))
	check(states.get("carol", "") == "distracted_or_not_looking",
		"carol asleep → distracted_or_not_looking, got '%s'" % states.get("carol", ""))

	# Hour 6 (mid-watch-1): bob on duty.
	DiceTestHarness.force_roll("hear_noises", 1)
	fire_time = 6 * Timekeeping.ROUNDS_PER_HOUR
	ctx = handlers._compute_camp_surprise_context(pd, fire_time)
	check(ctx.get("watch_index", -99) == 1,
		"hour 6 → watch_index 1, got %d" % ctx.get("watch_index", -99))
	states = ctx.get("observer_states", {})
	check(states.get("bob", "") == "actively_watching",
		"bob on watch 1 → actively_watching")

	# Hour 10 (mid-watch-2): carol on duty.
	DiceTestHarness.force_roll("hear_noises", 1)
	fire_time = 10 * Timekeeping.ROUNDS_PER_HOUR
	ctx = handlers._compute_camp_surprise_context(pd, fire_time)
	check(ctx.get("watch_index", -99) == 2,
		"hour 10 → watch_index 2, got %d" % ctx.get("watch_index", -99))
	states = ctx.get("observer_states", {})
	check(states.get("carol", "") == "actively_watching",
		"carol on watch 2 → actively_watching")

	DiceTestHarness.clear_all()


func test_compute_camp_surprise_hear_noises_18plus_rouses() -> void:
	var pd := _make_camping_party("ctx_rouse", 0)
	var handlers := WildernessHandlers.new(null)

	# Hour 2 (watch 0): alice on duty; bob + carol asleep.
	# Force the first Hear Noises to 20 (bob rouses), the second to 1
	# (carol stays asleep). DiceTestHarness consumes one override per roll;
	# we re-queue after each consumption.
	#
	# Implementation note: GameState.dice_overrides is a single value per
	# roll_type, consumed once. To control two consecutive d20 rolls in the
	# same handler call we exploit the deterministic iteration order of
	# party_data.character_data + the override system: we set both rolls
	# inline via a setter that swaps values between consumptions. Simpler
	# here: call _compute_camp_surprise_context once per sleeper, with
	# distinct overrides.
	#
	# Two-sleeper case in one call: split into two single-sleeper parties.

	var pd_rouse := _make_camping_party("ctx_rouse_one", 0)
	pd_rouse.character_data = []
	var bob := CharacterData.new()
	bob.id = "bob"; bob.name = "Bob"
	pd_rouse.character_data.append(bob)
	# Two-member watch rotation so bob is genuinely off-watch at hour 2.
	pd_rouse.camp_watch_assignments_json = JSON.stringify([["alice"], ["bob"], ["alice"]])

	DiceTestHarness.force_roll("hear_noises", 20)
	var ctx_pass: Dictionary = handlers._compute_camp_surprise_context(
		pd_rouse, 2 * Timekeeping.ROUNDS_PER_HOUR)
	check(ctx_pass.get("roused_sleepers", []).has("bob"),
		"hear_noises=20 → bob roused, got roused=%s" % str(ctx_pass.get("roused_sleepers", [])))
	check(not ctx_pass.get("unroused_sleepers", []).has("bob"),
		"bob not in unroused list when rouse succeeded")

	DiceTestHarness.force_roll("hear_noises", 1)
	var ctx_fail: Dictionary = handlers._compute_camp_surprise_context(
		pd_rouse, 2 * Timekeeping.ROUNDS_PER_HOUR)
	check(ctx_fail.get("unroused_sleepers", []).has("bob"),
		"hear_noises=1 → bob unroused, got unroused=%s" %
		str(ctx_fail.get("unroused_sleepers", [])))
	check(not ctx_fail.get("roused_sleepers", []).has("bob"),
		"bob not in roused list when rouse failed")

	# Boundary: 17 fails, 18 passes.
	DiceTestHarness.force_roll("hear_noises", 17)
	var ctx_17: Dictionary = handlers._compute_camp_surprise_context(
		pd_rouse, 2 * Timekeeping.ROUNDS_PER_HOUR)
	check(ctx_17.get("unroused_sleepers", []).has("bob"),
		"hear_noises=17 → bob unroused (boundary just below 18)")

	DiceTestHarness.force_roll("hear_noises", 18)
	var ctx_18: Dictionary = handlers._compute_camp_surprise_context(
		pd_rouse, 2 * Timekeeping.ROUNDS_PER_HOUR)
	check(ctx_18.get("roused_sleepers", []).has("bob"),
		"hear_noises=18 → bob roused (boundary just at 18)")

	DiceTestHarness.clear_all()


func test_compute_camp_surprise_outside_camp_window() -> void:
	var pd := _make_camping_party("ctx_outside", 0)
	var handlers := WildernessHandlers.new(null)

	# fire_time before camp_start: everyone is passively_watching (no watch
	# index resolvable), no Hear Noises rolls.
	var ctx_before: Dictionary = handlers._compute_camp_surprise_context(pd, -100)
	check(ctx_before.get("watch_index", -99) == -1,
		"fire_time before camp_start → watch_index=-1")
	var states: Dictionary = ctx_before.get("observer_states", {})
	for cid in ["alice", "bob", "carol"]:
		check(states.get(cid, "") == "passively_watching",
			"%s passively_watching outside camp window, got '%s'" %
			[cid, states.get(cid, "")])

	# fire_time at/after camp_end: same behavior.
	var ctx_after: Dictionary = handlers._compute_camp_surprise_context(
		pd, pd.camp_end_round + 1)
	check(ctx_after.get("watch_index", -99) == -1,
		"fire_time at camp_end → watch_index=-1")
