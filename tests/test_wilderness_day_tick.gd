extends "res://tests/test_suite_base.gd"

## Unit tests for the wilderness_day_tick event (Wilderness closure Phase 1).
##
## Covers:
##   * schedule_day_tick: idempotency and "next midnight" math against per-party
##     time (Timekeeping). Verifies the helper does not double-schedule.
##   * _handle_wilderness_day_tick: signal emission, last_day_tick_round stamp
##     and persistence, idempotency on re-fire of the same fire_time, and
##     self-rescheduling via the next_events return contract.
##
## Phase 1 only stamps the tick and reschedules — Phase 2 (weather rollover)
## and Phase 3 (sustenance penalty math, gdd-hunting-foraging.md per
## acore_adventures_and_encounters.xml) attach work in later sessions.
##
## Tests use the real CampaignRepository / Timekeeping / EventBus autoloads
## with isolated fixture parties (PARTY_PREFIX) and clean up after each run.


const PARTY_PREFIX := "test_phase1_dt_"
const CAMPAIGN_ID := "test_phase1_dt_campaign"


# ---------------------------------------------------------------------------
# Fake runner: minimal stand-in for SessionRunner so the handler's
# _party_data_for_event(event) hits the "primary" branch and returns the
# PartyData we constructed. The handler never accesses any other field.
# ---------------------------------------------------------------------------

class _FakeRunner:
	var _party_id: String = ""
	var _party_data: PartyData = null

	func get_party_id() -> String:
		return _party_id

	func get_party_data() -> PartyData:
		return _party_data


# ---------------------------------------------------------------------------
# Test entry
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_schedule_at_start_of_day()
	test_schedule_mid_day()
	test_schedule_at_exact_midnight_skips_to_next()
	test_schedule_idempotent()
	test_handler_emits_and_reschedules()
	test_handler_idempotent_on_same_fire_time()
	test_handler_persists_last_tick_round()
	test_handler_returns_empty_when_party_unknown()
	test_all_wilderness_handlers_register_globally()
	if not has_failures():
		print("WildernessDayTick: all tests passed.")


## Option 2 — background-party resolution (2026-06-12): EVERY wilderness event
## type must be globally registered. If any of these goes unregistered, an
## event of that type coming due in another context (dungeon/settlement/camp)
## is popped unhandled and silently destroyed — a background party's travel or
## activity chain dies. This pins the full coverage.
func test_all_wilderness_handlers_register_globally() -> void:
	var handlers := _make_handlers(_FakeRunner.new())
	var registry := EventHandlerRegistry.new()
	handlers.register_global(registry)
	for event_type: String in [
		"travel_leg",
		"wilderness_encounter_check",
		"getting_lost_check",
		"forced_march_check",
		WildernessHandlers.ACTIVITY_EVENT,
		WildernessHandlers.ACTIVITY_COMPLETE_EVENT,
		WildernessHandlers.DAY_TICK_EVENT,
		WildernessHandlers.NOON_TICK_EVENT,
		WildernessHandlers.TRACKING_CHECK_EVENT,
		WildernessHandlers.PURSUIT_CATCHUP_EVENT,
		WildernessHandlers.WILDERNESS_ENCOUNTER_EVENT,
	]:
		check(registry.has_handler(event_type),
			"register_global must cover '%s'" % event_type)
	handlers.unregister_global(registry)
	check(not registry.has_handler("travel_leg"),
		"unregister_global must remove travel_leg")
	print("  all_wilderness_handlers_register_globally: OK")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party_id(suffix: String) -> String:
	return PARTY_PREFIX + suffix


func _ensure_party_row(party_id: String) -> void:
	# Create a parties row referenced by party_state (FK). Idempotent — drop
	# any prior fixture so each test starts clean.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "test phase1 dt"])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[party_id, CAMPAIGN_ID, "Test Phase 1 Party"])


func _cleanup_party(party_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])


func _make_party_data(party_id: String) -> PartyData:
	var pd := PartyData.new()
	pd.id = party_id
	pd.campaign_id = CAMPAIGN_ID
	pd.name = "Test Phase 1 Party"
	pd.character_data = []
	return pd


func _make_handlers(runner: _FakeRunner) -> WildernessHandlers:
	return WildernessHandlers.new(runner)


# ---------------------------------------------------------------------------
# schedule_day_tick tests
# ---------------------------------------------------------------------------

func test_schedule_at_start_of_day() -> void:
	var pid := _make_party_id("start")
	_ensure_party_row(pid)

	var party_time: int = Timekeeping.get_total_rounds()
	var rounds_into_day: int = party_time % Timekeeping.ROUNDS_PER_DAY
	var expected_fire: int = party_time + (Timekeeping.ROUNDS_PER_DAY - rounds_into_day)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	var handlers := _make_handlers(runner)
	var scheduler := EventScheduler.new()

	var event_id: String = handlers.schedule_day_tick(scheduler, pid)
	check(not event_id.is_empty(), "schedule_day_tick returns a non-empty id")

	var owner_events: Array[ScheduledEvent] = scheduler.get_events_for_owner(pid)
	check(owner_events.size() == 1,
		"exactly one day-tick event scheduled, got %d" % owner_events.size())
	var ev := owner_events[0]
	check(ev.event_type == WildernessHandlers.DAY_TICK_EVENT,
		"event_type is wilderness_day_tick, got '%s'" % ev.event_type)
	check(ev.fire_time == expected_fire,
		"fire_time = next midnight (%d), got %d" % [expected_fire, ev.fire_time])
	check(ev.priority == ScheduledEvent.PRIORITY_ENVIRONMENTAL,
		"priority is PRIORITY_ENVIRONMENTAL (0), got %d" % ev.priority)
	check(ev.owner_id == pid, "event owner_id matches party_id")

	_cleanup_party(pid)


func test_schedule_mid_day() -> void:
	var pid := _make_party_id("midday")
	_ensure_party_row(pid)

	# Advance the party 6 hours into the day so we're decidedly mid-day.
	var advance_rounds: int = 6 * Timekeeping.ROUNDS_PER_HOUR
	Timekeeping.advance_rounds(advance_rounds)
	var party_time: int = Timekeeping.get_total_rounds()
	var rounds_into_day: int = party_time % Timekeeping.ROUNDS_PER_DAY
	var expected_fire: int = party_time + (Timekeeping.ROUNDS_PER_DAY - rounds_into_day)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	var handlers := _make_handlers(runner)
	var scheduler := EventScheduler.new()

	handlers.schedule_day_tick(scheduler, pid)
	var owner_events: Array[ScheduledEvent] = scheduler.get_events_for_owner(pid)
	check(owner_events.size() == 1, "one event scheduled")
	check(owner_events[0].fire_time == expected_fire,
		"mid-day schedule lands at next midnight (%d), got %d" %
		[expected_fire, owner_events[0].fire_time])
	# Sanity: the gap is strictly less than 24h since we advanced into the day.
	check(owner_events[0].fire_time - party_time < Timekeeping.ROUNDS_PER_DAY,
		"gap to next midnight < 24h (we advanced 6 hours in)")

	_cleanup_party(pid)


func test_schedule_at_exact_midnight_skips_to_next() -> void:
	var pid := _make_party_id("midnight")
	_ensure_party_row(pid)

	# Earlier tests may have advanced the world clock by an arbitrary offset.
	# Advance just enough to land on the next midnight boundary. The tick must
	# then fire 24h from there, not 0 rounds (the day-tick represents the
	# rollover INTO the upcoming day).
	var initial_time: int = Timekeeping.get_total_rounds()
	var rounds_to_midnight: int = (Timekeeping.ROUNDS_PER_DAY -
		(initial_time % Timekeeping.ROUNDS_PER_DAY)) % Timekeeping.ROUNDS_PER_DAY
	if rounds_to_midnight > 0:
		Timekeeping.advance_rounds(rounds_to_midnight)
	var party_time: int = Timekeeping.get_total_rounds()
	check(party_time % Timekeeping.ROUNDS_PER_DAY == 0,
		"sanity: party sits at exact midnight, got %d" %
		(party_time % Timekeeping.ROUNDS_PER_DAY))

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	var handlers := _make_handlers(runner)
	var scheduler := EventScheduler.new()

	handlers.schedule_day_tick(scheduler, pid)
	var owner_events: Array[ScheduledEvent] = scheduler.get_events_for_owner(pid)
	check(owner_events.size() == 1, "one event scheduled")
	check(owner_events[0].fire_time == party_time + Timekeeping.ROUNDS_PER_DAY,
		"midnight-aligned schedule fires 24h out, got fire_time=%d, party_time=%d" %
		[owner_events[0].fire_time, party_time])

	_cleanup_party(pid)


func test_schedule_idempotent() -> void:
	var pid := _make_party_id("idempotent")
	_ensure_party_row(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	var handlers := _make_handlers(runner)
	var scheduler := EventScheduler.new()

	var first_id: String = handlers.schedule_day_tick(scheduler, pid)
	var second_id: String = handlers.schedule_day_tick(scheduler, pid)
	check(not first_id.is_empty(), "first call returns id")
	check(second_id.is_empty(), "second call no-ops (returns empty)")
	check(scheduler.get_events_for_owner(pid).size() == 1,
		"still exactly one tick in queue, got %d" %
		scheduler.get_events_for_owner(pid).size())

	_cleanup_party(pid)


# ---------------------------------------------------------------------------
# _handle_wilderness_day_tick tests
# ---------------------------------------------------------------------------

func test_handler_emits_and_reschedules() -> void:
	var pid := _make_party_id("handler_emit")
	_ensure_party_row(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	var handlers := _make_handlers(runner)

	var emitted: Array = []
	var capture := func(party_id: String, summary: Dictionary) -> void:
		emitted.append({"party_id": party_id, "summary": summary})
	EventBus.wilderness_day_ticked.connect(capture)

	var fire_time := 100  # arbitrary absolute round
	var event := ScheduledEvent.create(
		fire_time, WildernessHandlers.DAY_TICK_EVENT, pid, {},
		ScheduledEvent.PRIORITY_ENVIRONMENTAL)
	var result: Dictionary = handlers._handle_wilderness_day_tick(event)

	EventBus.wilderness_day_ticked.disconnect(capture)

	check(emitted.size() == 1,
		"wilderness_day_ticked fired exactly once, got %d" % emitted.size())
	if emitted.size() == 1:
		check(emitted[0]["party_id"] == pid, "summary carries party_id")
		var summary: Dictionary = emitted[0]["summary"]
		check(summary.get("tick_round", -1) == fire_time,
			"summary.tick_round = event.fire_time")
		check(summary.has("day_index"), "summary includes day_index")
		check(summary.get("exhaustion_days", -1) == 0,
			"Phase 1 baseline: exhaustion_days = 0")

	# Self-reschedules +24hr.
	var next_events: Array = result.get("next_events", [])
	check(next_events.size() == 1,
		"result.next_events has exactly one entry, got %d" % next_events.size())
	if next_events.size() == 1:
		var ne: Dictionary = next_events[0]
		check(int(ne.get("fire_time", 0)) == fire_time + Timekeeping.ROUNDS_PER_DAY,
			"next tick fires +24h later (%d), got %d" %
			[fire_time + Timekeeping.ROUNDS_PER_DAY, int(ne.get("fire_time", 0))])
		check(ne.get("event_type", "") == WildernessHandlers.DAY_TICK_EVENT,
			"next event_type is wilderness_day_tick")
		check(ne.get("owner_id", "") == pid, "next owner_id is same party")
		check(int(ne.get("priority", -1)) == ScheduledEvent.PRIORITY_ENVIRONMENTAL,
			"next priority is PRIORITY_ENVIRONMENTAL")

	# Day-tick is housekeeping — must not auto-pause.
	check(not result.has("auto_pause") or not result.get("auto_pause", false),
		"day-tick must not auto_pause (housekeeping tier)")

	_cleanup_party(pid)


func test_handler_idempotent_on_same_fire_time() -> void:
	var pid := _make_party_id("handler_idem")
	_ensure_party_row(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	var handlers := _make_handlers(runner)

	var fire_time := 200
	var event := ScheduledEvent.create(
		fire_time, WildernessHandlers.DAY_TICK_EVENT, pid, {},
		ScheduledEvent.PRIORITY_ENVIRONMENTAL)

	var first := handlers._handle_wilderness_day_tick(event)
	check(first.has("next_events"), "first fire returns next_events")

	# Same event, same fire_time — must be a no-op the second time.
	var emit_count := 0
	var capture := func(_pid: String, _s: Dictionary) -> void:
		emit_count += 1
	EventBus.wilderness_day_ticked.connect(capture)
	var second := handlers._handle_wilderness_day_tick(event)
	EventBus.wilderness_day_ticked.disconnect(capture)

	check(second.is_empty(),
		"second fire on same fire_time is a no-op, got %s" % str(second))
	check(emit_count == 0,
		"second fire emits no signal, got %d emissions" % emit_count)

	_cleanup_party(pid)


func test_handler_persists_last_tick_round() -> void:
	var pid := _make_party_id("handler_persist")
	_ensure_party_row(pid)

	var runner := _FakeRunner.new()
	runner._party_id = pid
	runner._party_data = _make_party_data(pid)
	var handlers := _make_handlers(runner)

	var fire_time := 4242
	var event := ScheduledEvent.create(
		fire_time, WildernessHandlers.DAY_TICK_EVENT, pid, {},
		ScheduledEvent.PRIORITY_ENVIRONMENTAL)
	handlers._handle_wilderness_day_tick(event)

	# Reload the party_state row from the DB and verify the column was stamped.
	var ok: bool = CampaignRepository.db.query_with_bindings(
		"SELECT last_day_tick_round FROM party_state WHERE party_id = ?", [pid])
	check(ok and not CampaignRepository.db.query_result.is_empty(),
		"party_state row exists after tick")
	if ok and not CampaignRepository.db.query_result.is_empty():
		var stored: int = int(CampaignRepository.db.query_result[0]["last_day_tick_round"])
		check(stored == fire_time,
			"last_day_tick_round persisted (%d), got %d" % [fire_time, stored])

	# The handler's in-memory PartyData was also stamped.
	check(runner._party_data.last_day_tick_round == fire_time,
		"runner-cached PartyData.last_day_tick_round = %d, got %d" %
		[fire_time, runner._party_data.last_day_tick_round])

	_cleanup_party(pid)


func test_handler_returns_empty_when_party_unknown() -> void:
	# Null PartyData on the primary path → handler is a no-op. (We use the
	# primary path rather than the non-primary DB-load path so this test does
	# not depend on or pollute database state, and so it avoids a noisy
	# load_party_data push_error on a missing row.)
	var pid := _make_party_id("unknown")

	var runner := _FakeRunner.new()
	runner._party_id = pid       # primary-path match
	runner._party_data = null    # but the cache is empty
	var handlers := _make_handlers(runner)

	var event := ScheduledEvent.create(
		300, WildernessHandlers.DAY_TICK_EVENT, pid, {},
		ScheduledEvent.PRIORITY_ENVIRONMENTAL)
	var result: Dictionary = handlers._handle_wilderness_day_tick(event)
	check(result.is_empty(),
		"handler returns empty when PartyData is null, got %s" % str(result))
