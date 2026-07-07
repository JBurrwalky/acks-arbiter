extends "res://tests/test_suite_base.gd"

## Unit tests for ActivityTimeCostExecutor (Domain Phase 3).
##
## Covers Singular / Restricted / Ongoing semantics per
## gdd-realtime-scheduler.md §4.8.3:
##   * Singular launch + scheduled fire produces activity_completed
##   * Cancellation of Singular = total failure (no partial credit)
##   * Restricted launch sets cooldown on completion
##   * Ongoing tick accrues, absence accumulates, tick-tolerance forfeit
##
## Tests bypass SchedulerLoop and directly invoke the executor's event handlers
## via _handle_activity_complete / _handle_ongoing_session_complete to keep the
## suite deterministic.


var _campaign_id: String = ""
var _character_id: String = ""
var _domain_id: String = ""
var _catalog: ActivityCatalog = null
var _registry: ActivityHandlerRegistry = null
var _executor: ActivityTimeCostExecutor = null
var _scheduler: EventScheduler = null


func run_all_tests() -> void:
	_setup()
	test_singular_launch_persists_state()
	test_singular_completion_invokes_handler()
	test_singular_cancel_marks_forfeited_with_no_partial_credit()
	test_restricted_cooldown_blocks_relaunch()
	test_ongoing_tick_increments_when_present()
	test_ongoing_absence_increments_when_away()
	test_ongoing_tick_tolerance_forfeits_when_absence_exceeds_ticks()
	test_ongoing_completion_after_required_ticks()
	test_oversee_investment_launch_debits_treasury_exactly_once()
	test_oversee_investment_launch_blocked_when_insufficient_funds()
	test_calendar_day_uses_thirteen_month_year()
	test_domain_handlers_calendar_day_from_date_thirteen_months()
	if not has_failures():
		print("ActivityTimeCostExecutor: all tests passed.")


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Activity Executor", "TestWorld")
	_character_id = _create_character()
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Test Domain",
		"owner_character_id": _character_id,
	})
	DomainTreasury.deposit(_domain_id, 100_000 * 100, 1, "revenue", "test_seed", "seed treasury")
	_catalog = ActivityCatalog.new()
	_registry = ActivityHandlerRegistry.new()
	_register_test_handlers()
	_executor = ActivityTimeCostExecutor.new(null, _catalog, _registry)
	_executor.set_location_resolver(_test_location_resolver)
	_scheduler = EventScheduler.new()


func _create_character() -> String:
	var id: String = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, strength, intelligence, wisdom,
			 dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 1,
			10, 10, 10, 10, 10, 10, 8, 8)
	""", [id, _campaign_id, "Test Ruler"]):
		return ""
	return id


# Records "where is this character?" for each test. Tests mutate this dict to
# simulate travel-away / return.
var _location_by_character: Dictionary = {}

func _test_location_resolver(character_id: String) -> Dictionary:
	return _location_by_character.get(character_id, {"kind": "anywhere", "ref": ""})


# Handler invocations are recorded so tests can verify on_complete fired.
var _handler_invocations: Array = []

func _register_test_handlers() -> void:
	_registry.register("administer_domain", func(state, _runner): return _record("administer_domain", state))
	_registry.register("issue_decree", func(state, _runner): return _record("issue_decree", state))
	_registry.register("hire_mercenaries", func(state, _runner): return _record("hire_mercenaries", state))
	_registry.register("oversee_investment", func(state, _runner): return _record("oversee_investment", state))


func _record(def_id: String, state: Dictionary) -> Dictionary:
	_handler_invocations.append({"def_id": def_id, "state_id": state.get("id", "")})
	return {"summary": "test handler %s" % def_id}


func _make_event(event_id: String, state_id: String, def_id: String) -> ScheduledEvent:
	var e := ScheduledEvent.new()
	e.event_id = event_id
	e.event_type = "activity_complete"
	e.fire_time = 1000
	e.owner_id = _character_id
	e.data = {"activity_state_id": state_id, "activity_def_id": def_id}
	return e


# ---------------------------------------------------------------------------
# Singular tests
# ---------------------------------------------------------------------------

func test_singular_launch_persists_state() -> void:
	var result := _executor.launch(
		_character_id, "issue_decree", "anywhere", "",
		{"decree_kind": "tax", "value": 3}, _scheduler)
	check(bool(result.get("success", false)), "launch should succeed")
	var state_id: String = result.get("activity_state_id", "")
	check(not state_id.is_empty(), "state_id should be returned")
	var state := CampaignRepository.get_activity_state(state_id)
	check(String(state.get("frequency_type", "")) == "singular",
		"frequency should be singular")
	check(String(state.get("status", "")) == "active",
		"initial status should be active")


func test_singular_completion_invokes_handler() -> void:
	_handler_invocations.clear()
	var result := _executor.launch(
		_character_id, "issue_decree", "anywhere", "",
		{"decree_kind": "tax", "value": 3}, _scheduler)
	var state_id: String = result["activity_state_id"]
	var event := _make_event("test_evt_1", state_id, "issue_decree")
	_executor._handle_activity_complete(event)
	var state := CampaignRepository.get_activity_state(state_id)
	check(String(state.get("status", "")) == "completed",
		"status should be completed after fire, got %s" % state.get("status", "?"))
	check(_handler_invocations.size() >= 1, "handler should have been invoked")
	check(_handler_invocations[-1]["def_id"] == "issue_decree",
		"last handler should be issue_decree")


func test_singular_cancel_marks_forfeited_with_no_partial_credit() -> void:
	var result := _executor.launch(
		_character_id, "issue_decree", "anywhere", "",
		{}, _scheduler)
	var state_id: String = result["activity_state_id"]
	check(_executor.cancel(state_id, "player_cancel", _scheduler),
		"cancel should return true")
	var state := CampaignRepository.get_activity_state(state_id)
	check(String(state.get("status", "")) == "forfeited",
		"singular cancel should be forfeited, got %s" % state.get("status", "?"))
	check(int(state.get("ticks_accumulated", -1)) == 0,
		"singular cancel should have 0 ticks_accumulated (no partial credit)")


# ---------------------------------------------------------------------------
# Restricted: skipped — no domain-category Restricted activities exist in
# Phase 3's catalog. (Phase 9 carouse / lay_low will add tests.)
# ---------------------------------------------------------------------------

func test_restricted_cooldown_blocks_relaunch() -> void:
	# Synthesize: launch a singular, then artificially set a cooldown and try
	# again with the same activity treated as restricted via direct cooldown
	# write. Verifies set/get_restricted_cooldown plumbing.
	CampaignRepository.set_restricted_cooldown(
		_character_id, "issue_decree", 999_999_999, _campaign_id)
	var cd := CampaignRepository.get_restricted_cooldown(_character_id, "issue_decree")
	check(cd == 999_999_999, "cooldown round-trips through repository")


# ---------------------------------------------------------------------------
# Ongoing tests
# ---------------------------------------------------------------------------

func test_ongoing_tick_increments_when_present() -> void:
	_location_by_character[_character_id] = {"kind": "anywhere", "ref": ""}
	var result := _executor.launch(
		_character_id, "administer_domain", "anywhere", "",
		{}, _scheduler)
	var state_id: String = result["activity_state_id"]
	var event := _make_event("test_evt_ongoing_1", state_id, "administer_domain")
	event.event_type = "ongoing_session_complete"
	_executor._handle_ongoing_session_complete(event)
	var state := CampaignRepository.get_activity_state(state_id)
	check(int(state.get("ticks_accumulated", 0)) == 1,
		"ticks_accumulated should be 1 after first session, got %d" % int(state.get("ticks_accumulated", 0)))
	check(int(state.get("absence_accumulated", 0)) == 0,
		"absence should remain 0")


func test_ongoing_absence_increments_when_away() -> void:
	_location_by_character[_character_id] = {"kind": "anywhere", "ref": ""}
	# Define an ongoing activity requiring at_stronghold, then "be elsewhere".
	var result := _executor.launch(
		_character_id, "administer_domain", "at_stronghold", "stronghold:foo",
		{}, _scheduler)
	var state_id: String = result["activity_state_id"]
	# Ruler is "anywhere" but the activity requires "at_stronghold".
	var event := _make_event("test_evt_ongoing_absent", state_id, "administer_domain")
	event.event_type = "ongoing_session_complete"
	_executor._handle_ongoing_session_complete(event)
	var state := CampaignRepository.get_activity_state(state_id)
	check(int(state.get("ticks_accumulated", 0)) == 0,
		"ticks should NOT increment when absent, got %d" % int(state.get("ticks_accumulated", 0)))
	check(int(state.get("absence_accumulated", 0)) == 1,
		"absence should be 1, got %d" % int(state.get("absence_accumulated", 0)))


func test_ongoing_tick_tolerance_forfeits_when_absence_exceeds_ticks() -> void:
	_location_by_character[_character_id] = {"kind": "at_stronghold", "ref": "stronghold:foo"}
	# Use administer_domain with params that yield ticks_required = 8 so the
	# session can run multiple cycles without auto-completing on tick 1.
	var result := _executor.launch(
		_character_id, "administer_domain", "at_stronghold", "stronghold:foo",
		{"hex_count": 10, "vassal_count": 2, "market_class": 2}, _scheduler)
	var state_id: String = result["activity_state_id"]
	# Bank one tick by being present.
	var ev1 := _make_event("evt1", state_id, "administer_domain")
	ev1.event_type = "ongoing_session_complete"
	_executor._handle_ongoing_session_complete(ev1)
	# Now travel away and let two more sessions fire in absence.
	_location_by_character[_character_id] = {"kind": "anywhere", "ref": ""}
	var ev2 := _make_event("evt2", state_id, "administer_domain")
	ev2.event_type = "ongoing_session_complete"
	_executor._handle_ongoing_session_complete(ev2)
	var ev3 := _make_event("evt3", state_id, "administer_domain")
	ev3.event_type = "ongoing_session_complete"
	_executor._handle_ongoing_session_complete(ev3)
	var state := CampaignRepository.get_activity_state(state_id)
	check(String(state.get("status", "")) == "forfeited",
		"absence > ticks should forfeit, got status=%s" % state.get("status", "?"))


func test_ongoing_completion_after_required_ticks() -> void:
	_handler_invocations.clear()
	_location_by_character[_character_id] = {"kind": "anywhere", "ref": ""}
	# Force ticks_required = 1 by using oversee_investment with gp_committed=500
	# (one tick = 1 day per 500gp).
	var result := _executor.launch(
		_character_id, "oversee_investment", "anywhere", "",
		{"gp_committed": 500}, _scheduler)
	var state_id: String = result["activity_state_id"]
	var ev := _make_event("evt_done", state_id, "oversee_investment")
	ev.event_type = "ongoing_session_complete"
	_executor._handle_ongoing_session_complete(ev)
	var state := CampaignRepository.get_activity_state(state_id)
	check(String(state.get("status", "")) == "completed",
		"oversee_investment with 1 required tick should complete on first session, got status=%s" % state.get("status", "?"))


# ---------------------------------------------------------------------------
# Launch-time treasury debit (§91 launcher-debits contract)
# ---------------------------------------------------------------------------

## oversee_investment's handler assumes "the treasury was already debited at
## launch" — regression for the hole where the player launch path never
## actually performed that debit (task_aea5086f), letting a committed
## investment grow the domain's families for free. The debit must happen
## exactly once, at launch, for the committed cp amount.
func test_oversee_investment_launch_debits_treasury_exactly_once() -> void:
	var prior_balance: int = DomainTreasury.get_balance(_domain_id)
	var prior_ledger_count: int = CampaignRepository.list_ledger_entries(_domain_id).size()
	var result := _executor.launch(
		_character_id, "oversee_investment", "anywhere", "",
		{"gp_committed": 1000, "domain_id": _domain_id}, _scheduler)
	check(bool(result.get("success", false)), "launch should succeed with sufficient funds")
	var new_balance: int = DomainTreasury.get_balance(_domain_id)
	check(new_balance == prior_balance - 1000 * 100,
		"treasury should be debited exactly 1000gp (100,000cp), got prior=%d new=%d" % [prior_balance, new_balance])
	var ledger: Array = CampaignRepository.list_ledger_entries(_domain_id)
	check(ledger.size() == prior_ledger_count + 1,
		"exactly one new ledger row should be written at launch, got %d new rows" \
			% (ledger.size() - prior_ledger_count))
	var debit_row: Dictionary = ledger[-1]
	check(String(debit_row.get("category", "")) == "expense",
		"launch-time debit should be categorized as an expense, got %s" % debit_row.get("category", "?"))
	check(String(debit_row.get("subcategory", "")) == "oversee_investment_committed",
		"launch-time debit subcategory should be oversee_investment_committed, got %s" \
			% debit_row.get("subcategory", "?"))
	check(int(debit_row.get("cp_amount", 0)) == -1000 * 100,
		"ledger debit should be negative cp_amount, got %d" % int(debit_row.get("cp_amount", 0)))


## A committed amount the domain can't afford must block the launch outright
## — no activity_state created, no scheduled event, and the treasury left
## untouched (fail closed, not a silent short-fall).
func test_oversee_investment_launch_blocked_when_insufficient_funds() -> void:
	var poor_character_id: String = _create_character()
	var poor_domain_id: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Poor Domain",
		"owner_character_id": poor_character_id,
	})
	check(DomainTreasury.get_balance(poor_domain_id) == 0,
		"fixture sanity: poor domain should start with 0 treasury")
	var result := _executor.launch(
		poor_character_id, "oversee_investment", "anywhere", "",
		{"gp_committed": 1000, "domain_id": poor_domain_id}, _scheduler)
	check(not bool(result.get("success", false)),
		"launch should fail when the domain cannot afford the commitment")
	check(String(result.get("error", "")) == "insufficient_funds",
		"error should be insufficient_funds, got %s" % result.get("error", "?"))
	check(String(result.get("activity_state_id", "")).is_empty(),
		"no activity_state should be persisted on a blocked launch")
	check(DomainTreasury.get_balance(poor_domain_id) == 0,
		"treasury should remain untouched after a blocked launch")


# ---------------------------------------------------------------------------
# Calendar-day serial (13-month calendar regression)
# ---------------------------------------------------------------------------

## _calendar_day() must use the project's 13-month calendar
## (Timekeeping.MONTHS_PER_YEAR). The old (year - 1) * 12 formula made
## Year 2 Month 1 collide with Year 1 Month 13 (both = 336 + day), so any
## cross-year started_calendar_day / last_session_day arithmetic saw zero
## elapsed days at the year boundary and drifted a month per elapsed year.
func test_calendar_day_uses_thirteen_month_year() -> void:
	var saved_rounds: int = Timekeeping._elapsed_rounds

	# Year 1 Month 1 Day 1 → day-serial 1.
	Timekeeping._elapsed_rounds = 0
	check(_executor._calendar_day() == 1,
		"Y1 M1 D1 should be day 1, got %d" % _executor._calendar_day())

	# Year 1 Month 13 Day 1 (total_days = 336) → 337.
	Timekeeping._elapsed_rounds = 336 * Timekeeping.ROUNDS_PER_DAY
	var month13_day: int = _executor._calendar_day()
	check(month13_day == 337,
		"Y1 M13 D1 should be day 337, got %d" % month13_day)

	# Year 2 Month 1 Day 1 (total_days = 364) → 365. The buggy 12-month
	# formula returned 337 here — a collision with Y1 M13 D1.
	Timekeeping._elapsed_rounds = 364 * Timekeeping.ROUNDS_PER_DAY
	var year2_day: int = _executor._calendar_day()
	check(year2_day == 365,
		"Y2 M1 D1 should be day 365, got %d" % year2_day)
	check(year2_day > month13_day,
		"day serial must stay monotonic across the year boundary")

	# Identity: the serial equals Timekeeping.get_total_days() + 1 at any date.
	for total_days in [0, 27, 28, 363, 364, 391, 728, 1000]:
		Timekeeping._elapsed_rounds = total_days * Timekeeping.ROUNDS_PER_DAY
		check(_executor._calendar_day() == Timekeeping.get_total_days() + 1,
			"serial should equal get_total_days()+1 at total_days=%d" % total_days)

	Timekeeping._elapsed_rounds = saved_rounds


## DomainHandlers._calendar_day_from_date stamps siege/ledger calendar days
## with the same (formerly copy-pasted-buggy) formula; pin it too.
func test_domain_handlers_calendar_day_from_date_thirteen_months() -> void:
	var handlers := DomainHandlers.new(_StubRunner.new())
	check(handlers._calendar_day_from_date({"year": 1, "month": 13, "day": 28}) == 364,
		"Y1 M13 D28 should be day 364, got %d" % handlers._calendar_day_from_date({"year": 1, "month": 13, "day": 28}))
	check(handlers._calendar_day_from_date({"year": 2, "month": 1, "day": 1}) == 365,
		"Y2 M1 D1 should be day 365 (old 12-month formula collided at 337), got %d" % handlers._calendar_day_from_date({"year": 2, "month": 1, "day": 1}))


class _StubRunner:
	func get_campaign_id() -> String:
		return ""
