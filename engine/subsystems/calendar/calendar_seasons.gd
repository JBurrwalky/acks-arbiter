class_name CalendarSeasons

## Seasonal layer for the ACKS Arbiter 13×28 calendar.
##
## All functions are static — instantiate nothing, call directly:
##   CalendarSeasons.get_season(Timekeeping.get_day_of_year())
##   CalendarSeasons.get_climate_season(day, "south")
##
## Authoritative source: gdd-calendar-seasons.md.
## Calendar constants (boundary days, solstices) live in CalendarConstants.


# ---------------------------------------------------------------------------
# Season name constants — use these instead of raw strings to avoid typos.
# ---------------------------------------------------------------------------

const SPRING := "spring"
const SUMMER := "summer"
const AUTUMN := "autumn"
const WINTER := "winter"

## Season names in index order, matching CalendarConstants.XYZ_START_DAY ordering.
## Index 0=spring, 1=summer, 2=autumn, 3=winter.
const SEASON_NAMES: Array = [SPRING, SUMMER, AUTUMN, WINTER]

## Southern-hemisphere climate inversion: each key maps to its opposing season.
const _HEMISPHERE_INVERSE: Dictionary = {
	SPRING: AUTUMN,
	SUMMER: WINTER,
	AUTUMN: SPRING,
	WINTER: SUMMER
}


# ---------------------------------------------------------------------------
# Season lookup
# ---------------------------------------------------------------------------

## Returns the calendar season name for [param day_of_year] (1–364).
##   spring = days   1–91
##   summer = days  92–182
##   autumn = days 183–273
##   winter = days 274–364
static func get_season(day_of_year: int) -> String:
	if day_of_year <= 91:
		return SPRING
	elif day_of_year <= 182:
		return SUMMER
	elif day_of_year <= 273:
		return AUTUMN
	else:
		return WINTER


## Returns the season index (0–3) for [param day_of_year] (1–364).
## Use for array lookups: 0=spring, 1=summer, 2=autumn, 3=winter.
## Formula per gdd-calendar-seasons.md §2.1: (day_of_year - 1) / 91.
static func get_season_index(day_of_year: int) -> int:
	return (day_of_year - 1) / 91


# ---------------------------------------------------------------------------
# Hemisphere model
# ---------------------------------------------------------------------------

## Returns the climate-effective season for [param day_of_year] and [param hemisphere].
##
## Southern-hemisphere campaigns invert the climate-season mapping. Calendar dates
## are unchanged — Month 1 Day 1 is still the calendar year start — but the climate
## profile is swapped so weather, agriculture, and domain systems behave correctly.
##
## [param hemisphere]: "north" (default) or "south".
##
## Weather, domain simulation, and all other climate consumers call this.
## Narrative systems may call get_season() directly when they want the cultural
## (calendar) season name regardless of hemisphere.
static func get_climate_season(day_of_year: int, hemisphere: String) -> String:
	var season := get_season(day_of_year)
	if hemisphere == "south":
		return _HEMISPHERE_INVERSE.get(season, season)
	return season


# ---------------------------------------------------------------------------
# Transition blending
# ---------------------------------------------------------------------------

## Returns a blend descriptor for the 7-day seasonal transition window at
## [param day_of_year].
##
## Return Dictionary keys:
##   "in_transition" (bool)        — true when inside a transition window.
##   "outgoing_season" (String)    — season being exited.
##   "incoming_season" (String)    — season being entered.
##   "weight" (float 0.0–1.0)      — 0.0 = fully outgoing, 1.0 = fully incoming.
##                                   Approaches 1.0 by the last day of the window;
##                                   the day after the window snaps to 1.0 / new season.
##
## Outside all windows: "in_transition" = false, other fields empty/zero.
##
## Consumers apply blending to their own profile values:
##   effective = lerp(outgoing_value, incoming_value, blend["weight"])
##
## Window layout (each centered on the first day of the incoming season):
##   Spring→Summer: days  89– 95  (centered on day  92)
##   Summer→Autumn: days 180–186  (centered on day 183)
##   Autumn→Winter: days 271–277  (centered on day 274)
##   Winter→Spring: days 362–  4  (centered on day   1, wraps year boundary)
##
## Note: the GDD table lists the Winter→Spring window as "Day 361–Day 3" — this
## appears to be a typographical error. The consistent rule (window = [boundary-3,
## boundary+3]) produces days 362–4 for the Day-1 boundary, matching the stated
## "7 days centered on Day 1." This implementation follows the consistent rule.
static func get_transition_blend(day_of_year: int) -> Dictionary:
	var W := CalendarConstants.TRANSITION_WINDOW_DAYS  # 7

	# Winter→Spring wraps the year boundary: window days 362–364, 1–4.
	if day_of_year >= 362:
		return {
			"in_transition": true,
			"outgoing_season": WINTER,
			"incoming_season": SPRING,
			"weight": float(day_of_year - 362) / W
		}
	if day_of_year <= 4:
		return {
			"in_transition": true,
			"outgoing_season": WINTER,
			"incoming_season": SPRING,
			"weight": float(day_of_year + 2) / W
		}

	# Spring→Summer: days 89–95
	if day_of_year >= 89 and day_of_year <= 95:
		return {
			"in_transition": true,
			"outgoing_season": SPRING,
			"incoming_season": SUMMER,
			"weight": float(day_of_year - 89) / W
		}

	# Summer→Autumn: days 180–186
	if day_of_year >= 180 and day_of_year <= 186:
		return {
			"in_transition": true,
			"outgoing_season": SUMMER,
			"incoming_season": AUTUMN,
			"weight": float(day_of_year - 180) / W
		}

	# Autumn→Winter: days 271–277
	if day_of_year >= 271 and day_of_year <= 277:
		return {
			"in_transition": true,
			"outgoing_season": AUTUMN,
			"incoming_season": WINTER,
			"weight": float(day_of_year - 271) / W
		}

	return {"in_transition": false, "outgoing_season": "", "incoming_season": "", "weight": 0.0}


# ---------------------------------------------------------------------------
# Season progress (for LLM narrative context)
# ---------------------------------------------------------------------------

## Returns a season progress label for [param day_of_year].
## Used by LLM context assembly to describe where in the season the current date falls.
##   "early" = days  1–30 of the season
##   "mid"   = days 31–60 of the season
##   "late"  = days 61–91 of the season
static func get_season_progress(day_of_year: int) -> String:
	var boundary_days: Array = [
		CalendarConstants.SPRING_START_DAY,
		CalendarConstants.SUMMER_START_DAY,
		CalendarConstants.AUTUMN_START_DAY,
		CalendarConstants.WINTER_START_DAY
	]
	var start: int = boundary_days[get_season_index(day_of_year)]
	var day_in_season: int = day_of_year - start  # 0–90
	if day_in_season < 30:
		return "early"
	elif day_in_season < 60:
		return "mid"
	else:
		return "late"
