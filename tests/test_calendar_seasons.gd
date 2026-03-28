extends Node

## Unit tests for CalendarSeasons and CalendarConstants.
## Run via test_runner.tscn. Uses plain assert() — no external framework.
##
## Tests cover:
##   1. get_season() — all four seasons, exact boundary days
##   2. get_season_index() — 0-indexed mapping
##   3. get_climate_season() — northern and southern hemisphere
##   4. get_transition_blend() — in-window and out-of-window cases, wrap-around
##   5. get_season_progress() — early / mid / late labels
##   6. CalendarConstants — spot-check key values


# ---------------------------------------------------------------------------
# run_all_tests
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	# 1. get_season boundaries
	test_get_season_spring_boundaries()
	test_get_season_summer_boundaries()
	test_get_season_autumn_boundaries()
	test_get_season_winter_boundaries()

	# 2. get_season_index
	test_get_season_index_all_four()

	# 3. get_climate_season hemisphere model
	test_get_climate_season_north_unchanged()
	test_get_climate_season_south_inverts_all()

	# 4. get_transition_blend
	test_transition_blend_stable_mid_spring()
	test_transition_blend_spring_summer_window_start()
	test_transition_blend_spring_summer_center()
	test_transition_blend_spring_summer_window_end()
	test_transition_blend_summer_autumn_center()
	test_transition_blend_autumn_winter_center()
	test_transition_blend_winter_spring_wrap_day_362()
	test_transition_blend_winter_spring_wrap_day_1()
	test_transition_blend_winter_spring_wrap_day_4()
	test_transition_blend_just_outside_window()

	# 5. get_season_progress
	test_season_progress_early()
	test_season_progress_mid()
	test_season_progress_late()
	test_season_progress_winter_late()

	# 6. CalendarConstants spot-checks
	test_constants_solstice_equinox_days()
	test_constants_season_boundaries_consistent()

	print("CalendarSeasons: all tests passed.")


# ---------------------------------------------------------------------------
# 1. get_season — boundary days
# ---------------------------------------------------------------------------

func test_get_season_spring_boundaries() -> void:
	assert(CalendarSeasons.get_season(1)  == "spring", "day 1 should be spring")
	assert(CalendarSeasons.get_season(46) == "spring", "vernal equinox (day 46) should be spring")
	assert(CalendarSeasons.get_season(91) == "spring", "day 91 (last of spring) should be spring")


func test_get_season_summer_boundaries() -> void:
	assert(CalendarSeasons.get_season(92)  == "summer", "day 92 (first of summer) should be summer")
	assert(CalendarSeasons.get_season(137) == "summer", "summer solstice (day 137) should be summer")
	assert(CalendarSeasons.get_season(182) == "summer", "day 182 (last of summer) should be summer")


func test_get_season_autumn_boundaries() -> void:
	assert(CalendarSeasons.get_season(183) == "autumn", "day 183 (first of autumn) should be autumn")
	assert(CalendarSeasons.get_season(228) == "autumn", "autumnal equinox (day 228) should be autumn")
	assert(CalendarSeasons.get_season(273) == "autumn", "day 273 (last of autumn) should be autumn")


func test_get_season_winter_boundaries() -> void:
	assert(CalendarSeasons.get_season(274) == "winter", "day 274 (first of winter) should be winter")
	assert(CalendarSeasons.get_season(319) == "winter", "winter solstice (day 319) should be winter")
	assert(CalendarSeasons.get_season(364) == "winter", "day 364 (last of winter) should be winter")


# ---------------------------------------------------------------------------
# 2. get_season_index
# ---------------------------------------------------------------------------

func test_get_season_index_all_four() -> void:
	assert(CalendarSeasons.get_season_index(1)   == 0, "spring index should be 0")
	assert(CalendarSeasons.get_season_index(91)  == 0, "last spring day index should be 0")
	assert(CalendarSeasons.get_season_index(92)  == 1, "first summer day index should be 1")
	assert(CalendarSeasons.get_season_index(182) == 1, "last summer day index should be 1")
	assert(CalendarSeasons.get_season_index(183) == 2, "first autumn day index should be 2")
	assert(CalendarSeasons.get_season_index(273) == 2, "last autumn day index should be 2")
	assert(CalendarSeasons.get_season_index(274) == 3, "first winter day index should be 3")
	assert(CalendarSeasons.get_season_index(364) == 3, "last winter day index should be 3")


# ---------------------------------------------------------------------------
# 3. get_climate_season — hemisphere model
# ---------------------------------------------------------------------------

func test_get_climate_season_north_unchanged() -> void:
	assert(CalendarSeasons.get_climate_season(1,   "north") == "spring", "north spring unchanged")
	assert(CalendarSeasons.get_climate_season(92,  "north") == "summer", "north summer unchanged")
	assert(CalendarSeasons.get_climate_season(183, "north") == "autumn", "north autumn unchanged")
	assert(CalendarSeasons.get_climate_season(274, "north") == "winter", "north winter unchanged")


func test_get_climate_season_south_inverts_all() -> void:
	assert(CalendarSeasons.get_climate_season(1,   "south") == "autumn",
		"south: calendar spring → climate autumn")
	assert(CalendarSeasons.get_climate_season(92,  "south") == "winter",
		"south: calendar summer → climate winter")
	assert(CalendarSeasons.get_climate_season(183, "south") == "spring",
		"south: calendar autumn → climate spring")
	assert(CalendarSeasons.get_climate_season(274, "south") == "summer",
		"south: calendar winter → climate summer")


# ---------------------------------------------------------------------------
# 4. get_transition_blend
# ---------------------------------------------------------------------------

func test_transition_blend_stable_mid_spring() -> void:
	# Day 46 is the vernal equinox — mid-spring, well outside any transition window
	var b := CalendarSeasons.get_transition_blend(46)
	assert(b["in_transition"] == false,
		"day 46 (vernal equinox) should not be in a transition window")
	assert(b["weight"] == 0.0, "stable period weight should be 0.0")


func test_transition_blend_spring_summer_window_start() -> void:
	# Day 89 is the first day of the Spring→Summer window
	var b := CalendarSeasons.get_transition_blend(89)
	assert(b["in_transition"] == true, "day 89 should be in Spring→Summer window")
	assert(b["outgoing_season"] == "spring", "outgoing should be spring")
	assert(b["incoming_season"] == "summer", "incoming should be summer")
	assert(b["weight"] == 0.0, "weight at window start should be 0.0")


func test_transition_blend_spring_summer_center() -> void:
	# Day 92 is the boundary (center of the 7-day window). Weight = 3/7.
	var b := CalendarSeasons.get_transition_blend(92)
	assert(b["in_transition"] == true, "day 92 should be in transition window")
	var expected_weight := 3.0 / 7.0
	assert(abs(b["weight"] - expected_weight) < 0.001,
		"weight at center (day 92) should be 3/7 (got %f)" % b["weight"])


func test_transition_blend_spring_summer_window_end() -> void:
	# Day 95 is the last day of the Spring→Summer window. Weight = 6/7.
	var b := CalendarSeasons.get_transition_blend(95)
	assert(b["in_transition"] == true, "day 95 should still be in transition window")
	var expected_weight := 6.0 / 7.0
	assert(abs(b["weight"] - expected_weight) < 0.001,
		"weight at window end (day 95) should be 6/7 (got %f)" % b["weight"])


func test_transition_blend_summer_autumn_center() -> void:
	# Day 183 is the Summer→Autumn boundary. Weight = 3/7.
	var b := CalendarSeasons.get_transition_blend(183)
	assert(b["in_transition"] == true, "day 183 should be in Summer→Autumn window")
	assert(b["outgoing_season"] == "summer", "outgoing should be summer")
	assert(b["incoming_season"] == "autumn", "incoming should be autumn")
	var expected_weight := 3.0 / 7.0
	assert(abs(b["weight"] - expected_weight) < 0.001,
		"weight at center (day 183) should be 3/7 (got %f)" % b["weight"])


func test_transition_blend_autumn_winter_center() -> void:
	# Day 274 is the Autumn→Winter boundary. Weight = 3/7.
	var b := CalendarSeasons.get_transition_blend(274)
	assert(b["in_transition"] == true, "day 274 should be in Autumn→Winter window")
	assert(b["outgoing_season"] == "autumn", "outgoing should be autumn")
	assert(b["incoming_season"] == "winter", "incoming should be winter")
	var expected_weight := 3.0 / 7.0
	assert(abs(b["weight"] - expected_weight) < 0.001,
		"weight at center (day 274) should be 3/7 (got %f)" % b["weight"])


func test_transition_blend_winter_spring_wrap_day_362() -> void:
	# Day 362 is the start of the Winter→Spring wrap window. Weight = 0.0.
	var b := CalendarSeasons.get_transition_blend(362)
	assert(b["in_transition"] == true, "day 362 should be in Winter→Spring window")
	assert(b["outgoing_season"] == "winter", "outgoing should be winter")
	assert(b["incoming_season"] == "spring", "incoming should be spring")
	assert(b["weight"] == 0.0, "weight at day 362 (window start) should be 0.0")


func test_transition_blend_winter_spring_wrap_day_1() -> void:
	# Day 1 is the center of the Winter→Spring window. Weight = 3/7.
	var b := CalendarSeasons.get_transition_blend(1)
	assert(b["in_transition"] == true, "day 1 should be in Winter→Spring window")
	assert(b["outgoing_season"] == "winter", "outgoing should be winter")
	assert(b["incoming_season"] == "spring", "incoming should be spring")
	var expected_weight := 3.0 / 7.0
	assert(abs(b["weight"] - expected_weight) < 0.001,
		"weight at day 1 (window center) should be 3/7 (got %f)" % b["weight"])


func test_transition_blend_winter_spring_wrap_day_4() -> void:
	# Day 4 is the last day of the Winter→Spring window. Weight = 6/7.
	var b := CalendarSeasons.get_transition_blend(4)
	assert(b["in_transition"] == true, "day 4 should be in Winter→Spring window")
	var expected_weight := 6.0 / 7.0
	assert(abs(b["weight"] - expected_weight) < 0.001,
		"weight at day 4 (window end) should be 6/7 (got %f)" % b["weight"])


func test_transition_blend_just_outside_window() -> void:
	# Day 5 is one day after the Winter→Spring window — should be stable spring
	var b5 := CalendarSeasons.get_transition_blend(5)
	assert(b5["in_transition"] == false, "day 5 should be outside Winter→Spring window")

	# Day 88 is one day before the Spring→Summer window
	var b88 := CalendarSeasons.get_transition_blend(88)
	assert(b88["in_transition"] == false, "day 88 should be outside Spring→Summer window")

	# Day 96 is one day after the Spring→Summer window
	var b96 := CalendarSeasons.get_transition_blend(96)
	assert(b96["in_transition"] == false, "day 96 should be outside Spring→Summer window")

	# Day 361 is one day before the Winter→Spring window
	var b361 := CalendarSeasons.get_transition_blend(361)
	assert(b361["in_transition"] == false, "day 361 should be outside Winter→Spring window")


# ---------------------------------------------------------------------------
# 5. get_season_progress
# ---------------------------------------------------------------------------

func test_season_progress_early() -> void:
	# Spring day 1–30: day_in_season 0–29 → "early"
	assert(CalendarSeasons.get_season_progress(1)  == "early", "day 1 should be early spring")
	assert(CalendarSeasons.get_season_progress(30) == "early", "day 30 should be early spring")


func test_season_progress_mid() -> void:
	# Spring days 31–60 of season = day_of_year 31–60 → "mid"
	assert(CalendarSeasons.get_season_progress(31) == "mid", "day 31 should be mid spring")
	assert(CalendarSeasons.get_season_progress(60) == "mid", "day 60 should be mid spring")


func test_season_progress_late() -> void:
	# Spring days 61–91 of season = day_of_year 61–91 → "late"
	assert(CalendarSeasons.get_season_progress(61) == "late", "day 61 should be late spring")
	assert(CalendarSeasons.get_season_progress(91) == "late", "day 91 (last spring) should be late")


func test_season_progress_winter_late() -> void:
	# Winter starts day 274. "late" = days 335–364 (day_in_season 61–90).
	assert(CalendarSeasons.get_season_progress(335) == "late",
		"day 335 (winter day 62) should be late winter")
	assert(CalendarSeasons.get_season_progress(364) == "late",
		"day 364 (last day of year) should be late winter")


# ---------------------------------------------------------------------------
# 6. CalendarConstants spot-checks
# ---------------------------------------------------------------------------

func test_constants_solstice_equinox_days() -> void:
	assert(CalendarConstants.VERNAL_EQUINOX_DAY   == 46,  "vernal equinox should be day 46")
	assert(CalendarConstants.SUMMER_SOLSTICE_DAY  == 137, "summer solstice should be day 137")
	assert(CalendarConstants.AUTUMNAL_EQUINOX_DAY == 228, "autumnal equinox should be day 228")
	assert(CalendarConstants.WINTER_SOLSTICE_DAY  == 319, "winter solstice should be day 319")
	# Solstices and equinoxes must fall within their respective seasons
	assert(CalendarSeasons.get_season(CalendarConstants.VERNAL_EQUINOX_DAY)   == "spring")
	assert(CalendarSeasons.get_season(CalendarConstants.SUMMER_SOLSTICE_DAY)  == "summer")
	assert(CalendarSeasons.get_season(CalendarConstants.AUTUMNAL_EQUINOX_DAY) == "autumn")
	assert(CalendarSeasons.get_season(CalendarConstants.WINTER_SOLSTICE_DAY)  == "winter")


func test_constants_season_boundaries_consistent() -> void:
	# Season boundaries must cover all 364 days with no gaps and no overlap
	assert(CalendarConstants.SPRING_START_DAY == 1,   "spring starts on day 1")
	assert(CalendarConstants.SUMMER_START_DAY == CalendarConstants.SPRING_END_DAY + 1,
		"summer follows immediately after spring")
	assert(CalendarConstants.AUTUMN_START_DAY == CalendarConstants.SUMMER_END_DAY + 1,
		"autumn follows immediately after summer")
	assert(CalendarConstants.WINTER_START_DAY == CalendarConstants.AUTUMN_END_DAY + 1,
		"winter follows immediately after autumn")
	assert(CalendarConstants.WINTER_END_DAY == 364, "winter ends on day 364")
	# Each season is exactly 91 days
	var spring_len := CalendarConstants.SPRING_END_DAY - CalendarConstants.SPRING_START_DAY + 1
	var summer_len := CalendarConstants.SUMMER_END_DAY - CalendarConstants.SUMMER_START_DAY + 1
	var autumn_len := CalendarConstants.AUTUMN_END_DAY - CalendarConstants.AUTUMN_START_DAY + 1
	var winter_len := CalendarConstants.WINTER_END_DAY - CalendarConstants.WINTER_START_DAY + 1
	assert(spring_len == 91, "spring should be 91 days (got %d)" % spring_len)
	assert(summer_len == 91, "summer should be 91 days (got %d)" % summer_len)
	assert(autumn_len == 91, "autumn should be 91 days (got %d)" % autumn_len)
	assert(winter_len == 91, "winter should be 91 days (got %d)" % winter_len)
