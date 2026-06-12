extends "res://tests/test_suite_base.gd"

## Unit tests for the Timekeeping autoload.
## Run via test_runner.tscn. Uses plain check() — no external framework.
##
## Tests cover:
##   1. Calendar math (year/month/day boundaries)
##   2. Granularity conversions (rounds ↔ minutes ↔ turns ↔ hours ↔ days)
##   3. Boundary signal emission (day_changed, month_changed, dawn, dusk)
##   4. advance_to_hour edge cases
##   5. is_daylight() at boundary hours
##   6. Multi-party time sync
##   7. Persistence round-trip (save / load)


# ---------------------------------------------------------------------------
# Signal capture — connected in _ready(), used across all signal tests.
# ---------------------------------------------------------------------------

var _day_count: int = 0
var _last_day: Array = []   # [day, month, year]

var _month_count: int = 0
var _last_month: Array = [] # [month, year]

var _year_count: int = 0

var _dawn_count: int = 0
var _dusk_count: int = 0

var _season_count: int = 0
var _last_season: String = ""


func _ready() -> void:
	Timekeeping.day_changed.connect(_on_day_changed)
	Timekeeping.month_changed.connect(_on_month_changed)
	Timekeeping.year_changed.connect(_on_year_changed)
	Timekeeping.dawn.connect(_on_dawn)
	Timekeeping.dusk.connect(_on_dusk)
	Timekeeping.season_changed.connect(_on_season_changed)


func _on_day_changed(d: int, m: int, y: int) -> void:
	_day_count += 1
	_last_day = [d, m, y]


func _on_month_changed(m: int, y: int) -> void:
	_month_count += 1
	_last_month = [m, y]


func _on_year_changed(_y: int) -> void:
	_year_count += 1


func _on_dawn() -> void:
	_dawn_count += 1


func _on_dusk() -> void:
	_dusk_count += 1


func _on_season_changed(s: String) -> void:
	_season_count += 1
	_last_season = s


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Reset Timekeeping's internal state to a known baseline for each test.
func _reset() -> void:
	Timekeeping._elapsed_rounds = 0
	Timekeeping._dawn_hour      = 6
	Timekeeping._dusk_hour      = 20
	Timekeeping._campaign_id    = ""
	_day_count   = 0
	_last_day    = []
	_month_count = 0
	_last_month  = []
	_year_count  = 0
	_dawn_count    = 0
	_dusk_count    = 0
	_season_count  = 0
	_last_season   = ""


# ---------------------------------------------------------------------------
# run_all_tests
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	# 1. Calendar math
	test_calendar_364_days_is_one_year()
	test_calendar_28_days_is_one_month()
	test_calendar_13_months_is_one_year()

	# 2. Granularity conversions
	test_granularity_6_rounds_is_one_minute()
	test_granularity_60_rounds_is_one_turn()
	test_granularity_10_minutes_is_one_turn()
	test_granularity_6_turns_is_one_hour()
	test_granularity_24_hours_is_one_day()

	# 3. Boundary signals
	test_signal_day_changed_fires_on_day_boundary()
	test_signal_month_changed_fires_on_month_boundary()
	test_signal_40_days_fires_correct_counts()
	test_signal_year_changed_fires_on_year_boundary()

	# 4. advance_to_hour
	test_advance_to_hour_from_hour_14_to_6()
	test_advance_to_hour_no_advance_when_exact()
	test_advance_to_hour_mid_hour_wraps_to_next_day()

	# 5. Dawn / dusk signals
	test_dawn_fires_crossing_hour_6()
	test_dusk_fires_crossing_hour_20()

	# 6. is_daylight
	test_is_daylight_true_at_hour_6()
	test_is_daylight_true_at_hour_19()
	test_is_daylight_false_at_hour_5()
	test_is_daylight_false_at_hour_20()

	# 7. Single shared timeline (Jedidiah ruling 2026-06-11)
	test_single_timeline_get_total_rounds()

	# 8. Day-cycle configuration
	test_set_day_cycle_changes_is_daylight()
	test_set_day_cycle_changes_dawn_dusk_signals()
	test_set_day_cycle_defaults_are_6_and_20()

	# 9. Persistence round-trip
	test_persistence_round_trip()
	test_clock_persistence_debounced_until_flush()

	# 10. get_day_of_year
	test_get_day_of_year_first_day()
	test_get_day_of_year_last_day_of_year()
	test_get_day_of_year_year_wrap()
	test_get_day_of_year_summer_start()

	# 11. season_changed signal
	test_season_changed_fires_on_summer_start()
	test_season_changed_fires_on_year_wrap_to_spring()
	test_season_changed_does_not_fire_mid_season()
	test_session_started_loads_clock_state()
	test_year_boundary_ages_campaign_characters()

	if not has_failures():
		print("Timekeeping: all tests passed.")


# ---------------------------------------------------------------------------
# 1. Calendar math
# ---------------------------------------------------------------------------

func test_calendar_364_days_is_one_year() -> void:
	_reset()
	Timekeeping._elapsed_rounds = 364 * Timekeeping.ROUNDS_PER_DAY
	var date := Timekeeping.get_date()
	check(date["year"]  == 2, "364 days should be year 2")
	check(date["month"] == 1, "year boundary should land on month 1")
	check(date["day"]   == 1, "year boundary should land on day 1")


func test_calendar_28_days_is_one_month() -> void:
	_reset()
	Timekeeping._elapsed_rounds = 28 * Timekeeping.ROUNDS_PER_DAY
	var date := Timekeeping.get_date()
	check(date["year"]  == 1, "still year 1 at 28 days")
	check(date["month"] == 2, "28 days should be month 2")
	check(date["day"]   == 1, "month boundary should land on day 1")


func test_calendar_13_months_is_one_year() -> void:
	_reset()
	# 13 months × 28 days = 364 days = exactly 1 year
	Timekeeping._elapsed_rounds = 13 * 28 * Timekeeping.ROUNDS_PER_DAY
	var date := Timekeeping.get_date()
	check(date["year"]  == 2, "13 × 28 days should be year 2")
	check(date["month"] == 1, "should land on month 1 of year 2")
	check(date["day"]   == 1, "should land on day 1")


# ---------------------------------------------------------------------------
# 2. Granularity conversions
# ---------------------------------------------------------------------------

func test_granularity_6_rounds_is_one_minute() -> void:
	_reset()
	Timekeeping._elapsed_rounds = 6
	check(Timekeeping.get_total_minutes() == 1, "6 rounds = 1 minute")


func test_granularity_60_rounds_is_one_turn() -> void:
	_reset()
	Timekeeping._elapsed_rounds = 60
	check(Timekeeping.get_total_turns() == 1, "60 rounds = 1 turn")


func test_granularity_10_minutes_is_one_turn() -> void:
	_reset()
	# 10 minutes × 6 rounds/minute = 60 rounds
	Timekeeping._elapsed_rounds = 10 * Timekeeping.ROUNDS_PER_MINUTE
	check(Timekeeping.get_total_turns() == 1, "10 minutes = 1 turn")


func test_granularity_6_turns_is_one_hour() -> void:
	_reset()
	# 6 turns × 60 rounds/turn = 360 rounds = 1 hour
	Timekeeping._elapsed_rounds = 6 * Timekeeping.ROUNDS_PER_TURN
	var date := Timekeeping.get_date()
	check(date["hour"] == 1, "6 turns = 1 hour")
	check(Timekeeping.get_time_of_day() == 1, "get_time_of_day() should be 1")


func test_granularity_24_hours_is_one_day() -> void:
	_reset()
	# 24 hours × 360 rounds/hour = 8640 rounds = 1 day
	Timekeeping._elapsed_rounds = 24 * Timekeeping.ROUNDS_PER_HOUR
	check(Timekeeping.get_total_days() == 1, "24 hours = 1 day")


# ---------------------------------------------------------------------------
# 3. Boundary signals
# ---------------------------------------------------------------------------

func test_signal_day_changed_fires_on_day_boundary() -> void:
	_reset()
	Timekeeping.advance_days(1)
	check(_day_count == 1, "day_changed should fire once for advance_days(1)")
	check(_last_day == [1, 1, 2] or _last_day == [2, 1, 1],
		"day_changed payload should be day=1, month=1 or the correct next-day date")
	# Advance 1 day from start lands on Day 2, Month 1, Year 1
	check(_last_day[0] == 2, "new day should be 2")
	check(_last_day[1] == 1, "still month 1")
	check(_last_day[2] == 1, "still year 1")


func test_signal_month_changed_fires_on_month_boundary() -> void:
	_reset()
	# Advance exactly 28 days to cross month 1 → month 2 boundary
	Timekeeping.advance_days(28)
	check(_month_count == 1, "month_changed should fire once for advance_days(28)")
	check(_last_month[0] == 2, "new month should be 2")
	check(_last_month[1] == 1, "still year 1")


func test_signal_40_days_fires_correct_counts() -> void:
	_reset()
	# 40 days from start: crosses days 2–41, month boundary at day 29 (month 2).
	Timekeeping.advance_days(40)
	check(_day_count == 40, "day_changed should fire 40 times for advance_days(40)")
	check(_month_count == 1, "one month boundary crossed (month 1→2) in 40 days from start")


func test_signal_year_changed_fires_on_year_boundary() -> void:
	_reset()
	Timekeeping.advance_days(364)
	check(_year_count == 1, "year_changed should fire once for advance_days(364)")


# ---------------------------------------------------------------------------
# 4. advance_to_hour
# ---------------------------------------------------------------------------

func test_advance_to_hour_from_hour_14_to_6() -> void:
	_reset()
	# Set to hour 14 of day 1
	Timekeeping._elapsed_rounds = 14 * Timekeeping.ROUNDS_PER_HOUR
	var before := Timekeeping._elapsed_rounds
	Timekeeping.advance_to_hour(6)
	var added := Timekeeping._elapsed_rounds - before
	# From hour 14 to next hour 6 = 16 hours
	check(added == 16 * Timekeeping.ROUNDS_PER_HOUR,
		"advance_to_hour(6) from hour 14 should advance 16 hours (got %d)" % added)
	check(Timekeeping.get_time_of_day() == 6, "should land on hour 6")


func test_advance_to_hour_no_advance_when_exact() -> void:
	_reset()
	# Start exactly at hour 6, minute 0, round 0
	Timekeeping._elapsed_rounds = 6 * Timekeeping.ROUNDS_PER_HOUR
	var before := Timekeeping._elapsed_rounds
	Timekeeping.advance_to_hour(6)
	check(Timekeeping._elapsed_rounds == before,
		"advance_to_hour(6) when already at hour 6 exactly should not advance")


func test_advance_to_hour_mid_hour_wraps_to_next_day() -> void:
	_reset()
	# Start at hour 6 minute 5 (30 rounds into hour 6) — past the exact hour
	Timekeeping._elapsed_rounds = 6 * Timekeeping.ROUNDS_PER_HOUR + 5 * Timekeeping.ROUNDS_PER_MINUTE
	var before := Timekeeping._elapsed_rounds
	Timekeeping.advance_to_hour(6)
	var added := Timekeeping._elapsed_rounds - before
	# Should advance 23h55m = 23*360 + 5*6 rounds ... no:
	# = ROUNDS_PER_DAY - (6*360 + 5*6) + 6*360
	# = 8640 - (2160+30) + 2160 = 8640 - 30 = 8610
	var expected := Timekeeping.ROUNDS_PER_DAY - 5 * Timekeeping.ROUNDS_PER_MINUTE
	check(added == expected,
		"advance_to_hour(6) mid-hour should wrap to next day (expected %d, got %d)" % [expected, added])
	check(Timekeeping.get_time_of_day() == 6, "should land on hour 6 of next day")


# ---------------------------------------------------------------------------
# 5. Dawn / dusk signals
# ---------------------------------------------------------------------------

func test_dawn_fires_crossing_hour_6() -> void:
	_reset()
	# Start at hour 5, advance 2 hours — crosses hour 6
	Timekeeping._elapsed_rounds = 5 * Timekeeping.ROUNDS_PER_HOUR
	Timekeeping.advance_hours(2)
	check(_dawn_count == 1, "dawn should fire once when crossing hour 6")
	check(_dusk_count == 0, "dusk should not fire")


func test_dusk_fires_crossing_hour_20() -> void:
	_reset()
	# Start at hour 19, advance 2 hours — crosses hour 20
	Timekeeping._elapsed_rounds = 19 * Timekeeping.ROUNDS_PER_HOUR
	Timekeeping.advance_hours(2)
	check(_dusk_count == 1, "dusk should fire once when crossing hour 20")
	check(_dawn_count == 0, "dawn should not fire")


# ---------------------------------------------------------------------------
# 6. is_daylight
# ---------------------------------------------------------------------------

func test_is_daylight_true_at_hour_6() -> void:
	_reset()
	Timekeeping._elapsed_rounds = 6 * Timekeeping.ROUNDS_PER_HOUR
	check(Timekeeping.is_daylight() == true, "hour 6 should be daylight")


func test_is_daylight_true_at_hour_19() -> void:
	_reset()
	Timekeeping._elapsed_rounds = 19 * Timekeeping.ROUNDS_PER_HOUR
	check(Timekeeping.is_daylight() == true, "hour 19 should be daylight")


func test_is_daylight_false_at_hour_5() -> void:
	_reset()
	Timekeeping._elapsed_rounds = 5 * Timekeeping.ROUNDS_PER_HOUR
	check(Timekeeping.is_daylight() == false, "hour 5 should not be daylight")


func test_is_daylight_false_at_hour_20() -> void:
	_reset()
	Timekeeping._elapsed_rounds = 20 * Timekeeping.ROUNDS_PER_HOUR
	check(Timekeeping.is_daylight() == false, "hour 20 should not be daylight")


# ---------------------------------------------------------------------------
# 7. Single shared timeline (Jedidiah ruling 2026-06-11)
# ---------------------------------------------------------------------------

func test_single_timeline_get_total_rounds() -> void:
	_reset()
	check(Timekeeping.get_total_rounds() == 0,
		"get_total_rounds should be 0 after reset")

	# get_total_rounds is the canonical "now" — every advance moves it.
	Timekeeping.advance_rounds(5)
	check(Timekeeping.get_total_rounds() == 5,
		"get_total_rounds should reflect advance_rounds")

	Timekeeping.advance_hours(3)
	check(Timekeeping.get_total_rounds() == 5 + 3 * Timekeeping.ROUNDS_PER_HOUR,
		"get_total_rounds should reflect advance_hours")

	check(Timekeeping.get_total_rounds() == Timekeeping._elapsed_rounds,
		"get_total_rounds should equal the internal clock")


# ---------------------------------------------------------------------------
# 8. Day-cycle configuration (set_day_cycle for seasons/weather system)
# ---------------------------------------------------------------------------

func test_set_day_cycle_changes_is_daylight() -> void:
	_reset()
	# Shorten the day: dawn=8, dusk=16 (8-hour winter day)
	Timekeeping.set_day_cycle(8, 16)
	check(Timekeeping.get_dawn_hour() == 8, "dawn_hour should be 8")
	check(Timekeeping.get_dusk_hour() == 16, "dusk_hour should be 16")

	# Hour 6 should now be night (was daylight with defaults)
	Timekeeping._elapsed_rounds = 6 * Timekeeping.ROUNDS_PER_HOUR
	check(Timekeeping.is_daylight() == false, "hour 6 should be night with dawn=8")

	# Hour 8 should now be dawn
	Timekeeping._elapsed_rounds = 8 * Timekeeping.ROUNDS_PER_HOUR
	check(Timekeeping.is_daylight() == true, "hour 8 should be daylight with dawn=8")

	# Hour 15 should be day
	Timekeeping._elapsed_rounds = 15 * Timekeeping.ROUNDS_PER_HOUR
	check(Timekeeping.is_daylight() == true, "hour 15 should be daylight with dusk=16")

	# Hour 16 should now be dusk (night starts)
	Timekeeping._elapsed_rounds = 16 * Timekeeping.ROUNDS_PER_HOUR
	check(Timekeeping.is_daylight() == false, "hour 16 should be night with dusk=16")


func test_set_day_cycle_changes_dawn_dusk_signals() -> void:
	_reset()
	# Set dawn=8, dusk=16; advance from hour 7 to hour 9 → dawn should fire at hour 8
	Timekeeping.set_day_cycle(8, 16)
	Timekeeping._elapsed_rounds = 7 * Timekeeping.ROUNDS_PER_HOUR
	Timekeeping.advance_hours(2)
	check(_dawn_count == 1, "dawn should fire when crossing new dawn_hour (8)")
	check(_dusk_count == 0, "dusk should not fire")


func test_set_day_cycle_defaults_are_6_and_20() -> void:
	_reset()
	# Defaults must be 6 and 20 so testing works before seasons system is built
	check(Timekeeping.get_dawn_hour() == 6, "default dawn_hour should be 6")
	check(Timekeeping.get_dusk_hour() == 20, "default dusk_hour should be 20")


# ---------------------------------------------------------------------------
# 9. Persistence round-trip
# ---------------------------------------------------------------------------

func test_persistence_round_trip() -> void:
	_reset()
	const TEST_CAMPAIGN := "test_timekeeping_suite"

	# Set a distinctive time and save
	var test_rounds := 7 * Timekeeping.ROUNDS_PER_DAY + 14 * Timekeeping.ROUNDS_PER_HOUR + 3 * Timekeeping.ROUNDS_PER_TURN
	Timekeeping._elapsed_rounds = test_rounds
	Timekeeping._dawn_hour = 7
	Timekeeping._dusk_hour = 19

	Timekeeping.save_state(TEST_CAMPAIGN)

	# Reset to zero, then restore
	Timekeeping._elapsed_rounds = 0
	Timekeeping._dawn_hour      = 6
	Timekeeping._dusk_hour      = 20
	Timekeeping.load_state(TEST_CAMPAIGN)

	check(Timekeeping._elapsed_rounds == test_rounds,
		"loaded elapsed_rounds should match saved value (%d vs %d)" % [Timekeeping._elapsed_rounds, test_rounds])
	check(Timekeeping._dawn_hour == 7, "loaded dawn_hour should be 7")
	check(Timekeeping._dusk_hour == 19, "loaded dusk_hour should be 19")

	# Verify get_date() produces correct date from restored time
	var date := Timekeeping.get_date()
	# 7 days = Day 8, Month 1, Year 1. Hour 14. Turn 3 into the hour (30 min in).
	check(date["year"]   == 1, "year should be 1")
	check(date["month"]  == 1, "month should be 1")
	check(date["day"]    == 8, "day should be 8 (7 full days elapsed)")
	check(date["hour"]   == 14, "hour should be 14")

	# Clean up — reset campaign_id so future tests don't auto-save
	Timekeeping._campaign_id = ""


func test_clock_persistence_debounced_until_flush() -> void:
	_reset()
	const TEST_CAMPAIGN := "test_timekeeping_debounce"
	# Batch C persistence policy: the DB runs in WAL mode...
	CampaignRepository.db.query("PRAGMA journal_mode")
	var mode: String = ""
	if not CampaignRepository.db.query_result.is_empty():
		mode = String(CampaignRepository.db.query_result[0].values()[0]).to_lower()
	check(mode == "wal", "DB should be in WAL journal mode, got '%s'" % mode)

	# ...and advances mark the clock dirty instead of writing per-advance.
	Timekeeping.save_state(TEST_CAMPAIGN)        # seed the row at 0
	Timekeeping._campaign_id = TEST_CAMPAIGN     # simulate a loaded session
	Timekeeping.advance_rounds(500)
	CampaignRepository.db.query_with_bindings(
		"SELECT elapsed_rounds FROM campaign_clock WHERE campaign_id = ?", [TEST_CAMPAIGN])
	var persisted := int(CampaignRepository.db.query_result[0].get("elapsed_rounds", -1))
	check(persisted == 0,
		"advance must NOT write campaign_clock before flush (got %d)" % persisted)

	check(Timekeeping.flush(), "flush should report a write when the clock is dirty")
	CampaignRepository.db.query_with_bindings(
		"SELECT elapsed_rounds FROM campaign_clock WHERE campaign_id = ?", [TEST_CAMPAIGN])
	persisted = int(CampaignRepository.db.query_result[0].get("elapsed_rounds", -1))
	check(persisted == 500, "flush should persist the advanced clock (got %d)" % persisted)
	check(not Timekeeping.flush(), "second flush with no new advances should no-op")

	# Clean up — reset campaign_id + dirty so future tests don't flush
	Timekeeping._campaign_id = ""
	Timekeeping._dirty = false


# ---------------------------------------------------------------------------
# 10. get_day_of_year
# ---------------------------------------------------------------------------

func test_get_day_of_year_first_day() -> void:
	_reset()
	# Elapsed = 0 rounds → Day 1, Month 1, Year 1 → day_of_year = 1
	check(Timekeeping.get_day_of_year() == 1,
		"day_of_year at start should be 1")


func test_get_day_of_year_last_day_of_year() -> void:
	_reset()
	# Advance 363 days → Day 364 of Year 1 (0-indexed total_days = 363)
	Timekeeping._elapsed_rounds = 363 * Timekeeping.ROUNDS_PER_DAY
	check(Timekeeping.get_day_of_year() == 364,
		"363 days elapsed should be day_of_year 364 (got %d)" % Timekeeping.get_day_of_year())


func test_get_day_of_year_year_wrap() -> void:
	_reset()
	# Advance 364 days → Year 2, Month 1, Day 1 → day_of_year wraps back to 1
	Timekeeping._elapsed_rounds = 364 * Timekeeping.ROUNDS_PER_DAY
	check(Timekeeping.get_day_of_year() == 1,
		"364 days elapsed should wrap day_of_year back to 1")


func test_get_day_of_year_summer_start() -> void:
	_reset()
	# Summer starts on day_of_year 92 (0-indexed total_days = 91)
	Timekeeping._elapsed_rounds = 91 * Timekeeping.ROUNDS_PER_DAY
	check(Timekeeping.get_day_of_year() == 92,
		"91 days elapsed should be day_of_year 92 (first day of summer)")


# ---------------------------------------------------------------------------
# 11. season_changed signal
# ---------------------------------------------------------------------------

func test_season_changed_fires_on_summer_start() -> void:
	_reset()
	# Start at day_of_year 91 (last day of spring), advance 1 day → crosses into summer
	Timekeeping._elapsed_rounds = 90 * Timekeeping.ROUNDS_PER_DAY
	Timekeeping.advance_days(1)
	check(_season_count == 1,
		"season_changed should fire once when advancing into summer (got %d)" % _season_count)
	check(_last_season == "summer",
		"new season should be 'summer' (got '%s')" % _last_season)


func test_season_changed_fires_on_year_wrap_to_spring() -> void:
	_reset()
	# Start on day_of_year 364 (last day of winter), advance 1 day → new year, spring
	Timekeeping._elapsed_rounds = 363 * Timekeeping.ROUNDS_PER_DAY
	Timekeeping.advance_days(1)
	check(_season_count == 1,
		"season_changed should fire when year wraps back to spring (got %d)" % _season_count)
	check(_last_season == "spring",
		"new season after year wrap should be 'spring' (got '%s')" % _last_season)


func test_season_changed_does_not_fire_mid_season() -> void:
	_reset()
	# Advance 10 days starting from day_of_year 10 — stays within spring, no season change
	Timekeeping._elapsed_rounds = 9 * Timekeeping.ROUNDS_PER_DAY
	Timekeeping.advance_days(10)
	check(_season_count == 0,
		"season_changed should not fire when advancing within the same season")


# ---------------------------------------------------------------------------
# 12. Session integration
# ---------------------------------------------------------------------------

func test_session_started_loads_clock_state() -> void:
	_reset()
	const TEST_CAMPAIGN := "test_timekeeping_session_start"
	const TEST_PARTY := "test_timekeeping_party"

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[TEST_CAMPAIGN, "Timekeeping Session Test", "Test World"]
	)

	Timekeeping._elapsed_rounds = 5 * Timekeeping.ROUNDS_PER_DAY + 3 * Timekeeping.ROUNDS_PER_HOUR
	Timekeeping._dawn_hour = 7
	Timekeeping._dusk_hour = 19
	Timekeeping.save_state(TEST_CAMPAIGN)

	Timekeeping._elapsed_rounds = 0
	Timekeeping._dawn_hour = 6
	Timekeeping._dusk_hour = 20
	Timekeeping._campaign_id = ""

	GameState.start_session(TEST_CAMPAIGN, TEST_PARTY)

	check(Timekeeping._campaign_id == TEST_CAMPAIGN,
		"session_started should load Timekeeping for the active campaign")
	check(Timekeeping._elapsed_rounds == 5 * Timekeeping.ROUNDS_PER_DAY + 3 * Timekeeping.ROUNDS_PER_HOUR,
		"session_started should restore persisted elapsed_rounds")
	check(Timekeeping._dawn_hour == 7, "session_started should restore dawn_hour")
	check(Timekeeping._dusk_hour == 19, "session_started should restore dusk_hour")

	GameState.end_session()
	_reset()


func test_year_boundary_ages_campaign_characters() -> void:
	_reset()
	const TEST_CAMPAIGN := "test_timekeeping_aging_campaign"
	const TEST_CHARACTER := "test_timekeeping_aging_character"

	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHARACTER]
	)
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[TEST_CAMPAIGN, "Timekeeping Aging Test", "Test World"]
	)

	var c := CharacterData.new()
	c.id = TEST_CHARACTER
	c.campaign_id = TEST_CAMPAIGN
	c.name = "Aging Test"
	c.race = "human"
	c.character_class = "fighter"
	c.current_age = 35
	c.age_category = "adult"
	c.strength = 12
	c.dexterity = 12
	c.constitution = 12
	c.intelligence = 10
	c.wisdom = 10
	c.charisma = 10
	check(CampaignRepository.save_character(c.to_dict()),
		"test setup: save_character should succeed for aging integration test")

	Timekeeping.load_state(TEST_CAMPAIGN)
	Timekeeping.advance_days(Timekeeping.DAYS_PER_YEAR)

	var row := CampaignRepository.get_character(TEST_CHARACTER)
	check(not row.is_empty(), "aged character should still exist after year advance")
	check(int(row.get("current_age", 0)) == 36,
		"year boundary should increase current_age from 35 to 36")
	check(row.get("age_category", "") == "middle_aged",
		"year boundary should advance age_category to middle_aged")
	check(int(row.get("strength", 0)) == 10,
		"adult -> middle_aged should persist STR -2")
	check(int(row.get("dexterity", 0)) == 10,
		"adult -> middle_aged should persist DEX -2")
	check(int(row.get("constitution", 0)) == 10,
		"adult -> middle_aged should persist CON -2")

	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [TEST_CHARACTER]
	)
	Timekeeping._campaign_id = ""
