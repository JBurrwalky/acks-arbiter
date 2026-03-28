class_name CalendarConstants

## Canonical day-of-year constants for the ACKS Arbiter 13×28 calendar.
##
## All day-of-year values are 1-indexed (1 = Month 1, Day 1).
## Season definitions per gdd-calendar-seasons.md.
## 13 months × 28 days = 364 days/year; no leap year.


# ---------------------------------------------------------------------------
# Season boundary days (first day of each season, 1-indexed day-of-year)
# ---------------------------------------------------------------------------

## First day of Spring — also the first day of the calendar year.
const SPRING_START_DAY := 1

## First day of Summer.
const SUMMER_START_DAY := 92

## First day of Autumn.
const AUTUMN_START_DAY := 183

## First day of Winter.
const WINTER_START_DAY := 274


# ---------------------------------------------------------------------------
# Season end days (last day of each season, 1-indexed day-of-year)
# ---------------------------------------------------------------------------

## Last day of Spring.
const SPRING_END_DAY := 91

## Last day of Summer.
const SUMMER_END_DAY := 182

## Last day of Autumn.
const AUTUMN_END_DAY := 273

## Last day of Winter — also the last day of the calendar year.
const WINTER_END_DAY := 364


# ---------------------------------------------------------------------------
# Astronomical events (day-of-year, 1-indexed)
# Solstices and equinoxes fall at season midpoints, not at season boundaries.
# Reference: gdd-calendar-seasons.md §3.
# ---------------------------------------------------------------------------

## Vernal Equinox: equal day and night, spring midpoint. Calendar: Month 2, Day 18.
const VERNAL_EQUINOX_DAY := 46

## Summer Solstice: longest day of year, summer midpoint. Calendar: Month 5, Day 11.
const SUMMER_SOLSTICE_DAY := 137

## Autumnal Equinox: equal day and night, autumn midpoint. Calendar: Month 8, Day 4.
const AUTUMNAL_EQUINOX_DAY := 228

## Winter Solstice: shortest day of year, winter midpoint. Calendar: Month 11, Day 25.
const WINTER_SOLSTICE_DAY := 319


# ---------------------------------------------------------------------------
# Seasonal transition window
# ---------------------------------------------------------------------------

## Number of days in the blend window straddling each season boundary.
## The window is centered on the first day of the incoming season:
##   [boundary_day - 3, boundary_day + 3] = 7 days.
## Weight formula: (day_into_window) / TRANSITION_WINDOW_DAYS
##   → 0.0 at window start (fully outgoing), approaches 1.0 by window end.
const TRANSITION_WINDOW_DAYS := 7
