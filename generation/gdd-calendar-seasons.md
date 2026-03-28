# GDD: Calendar and Seasons

**Authority:** PROJECT-DESIGNED — the calendar structure, season definitions, astronomical events, and hemisphere model are all engineering decisions. No ACKS sourcebook defines a calendar or seasonal system.
**Status:** Draft
**Depends on ACKS rules:** None directly. The design brief §8.3 establishes the 13×28 calendar structure; this GDD builds the seasonal and astronomical layer on top of it.
**Depends on project GDDs:** `gdd-setting-generation.md` (provides the `latitude_range` and `hemisphere` user parameters at campaign creation)
**Modifiable by Claude Code:** Yes — all definitions are engineering decisions.
**Last updated:** 2026-03-28

---

## 1. Purpose

Define the campaign calendar's seasonal structure, astronomical events, hemisphere model, and seasonal transition rules. This GDD is the single authoritative source for "what season is it on day X" and "when are the solstices/equinoxes." It is consumed by every system that cares about time of year:

- **Weather generation** (`gdd-weather-generation.md`) — selects seasonal climate profiles, drives dawn/dusk calculation.
- **Domain simulation** — agricultural yields, seasonal trade, campaign army supply costs.
- **Timekeeping / session runner** — day-cycle scheduling, watch length from daylight hours.
- **Narrative context / LLM** — seasonal descriptions, festival dates, NPC dialogue.
- **NPC scheduling** — daily routine shifts with daylight hours.

The calendar skeleton (13 months × 28 days, 7-day weeks) is defined in the design brief §8.3 and is not repeated here — this GDD defines only the seasonal layer built on top of that skeleton.

---

## 2. Season Definitions

Four seasons, each exactly 91 days (13 weeks, or 3.25 months), covering the full 364-day year with no gaps or overlap.

| Season | Start Day | End Day | Months Covered |
|---|---|---|---|
| Spring | Day 1 (Month 1, Day 1) | Day 91 (Month 3, Day 28 + Month 4, Day 7) | Months 1–3 + first week of Month 4 |
| Summer | Day 92 (Month 4, Day 8) | Day 182 (Month 6, Day 28 + Month 7, Day 14) | Months 4–6 + first two weeks of Month 7 |
| Autumn | Day 183 (Month 7, Day 15) | Day 273 (Month 9, Day 28 + Month 10, Day 21) | Months 7–9 + first three weeks of Month 10 |
| Winter | Day 274 (Month 10, Day 22) | Day 364 (Month 13, Day 28) | Months 10–13 (remainder) |

### 2.1 Season Lookup

```
func get_season(day_of_year: int) -> String:
  if day_of_year <= 91: return "spring"
  elif day_of_year <= 182: return "summer"
  elif day_of_year <= 273: return "autumn"
  else: return "winter"
```

Consumers needing the season index (0–3) for array lookups use: `season_index = (day_of_year - 1) / 91`.

---

## 3. Solstice and Equinox Days

These astronomical events mark the peak and trough of daylight hours and are the reference points for the dawn/dusk calculation in `gdd-weather-generation.md` §6.

| Event | Day of Year | Calendar Date | Significance |
|---|---|---|---|
| Vernal Equinox | Day 46 | Month 2, Day 18 | Equal day/night; spring midpoint |
| Summer Solstice | Day 137 | Month 5, Day 11 | Longest day; summer midpoint |
| Autumnal Equinox | Day 228 | Month 8, Day 4 | Equal day/night; autumn midpoint |
| Winter Solstice | Day 319 | Month 11, Day 25 | Shortest day; winter midpoint |

The solstices and equinoxes fall at the midpoints of their respective seasons, not at season boundaries. This matches real-world convention (e.g., the summer solstice is the peak of summer, not the start).

---

## 4. Hemisphere Model

### 4.1 Hemisphere Flag

The setting generator assigns a `hemisphere` flag (north or south) as a user parameter at campaign creation. Default: **north**.

### 4.2 Season Inversion

Southern hemisphere campaigns invert the climate-season mapping. The calendar dates do not change — Month 1 Day 1 is still the start of the calendar year — but the climate profile applied by the weather system is swapped:

| Calendar Season | North Hemisphere Climate | South Hemisphere Climate |
|---|---|---|
| Spring (Days 1–91) | Spring | Autumn |
| Summer (Days 92–182) | Summer | Winter |
| Autumn (Days 183–273) | Autumn | Spring |
| Winter (Days 274–364) | Winter | Summer |

Implementation: a single function wraps the season lookup:

```
func get_climate_season(day_of_year: int, hemisphere: String) -> String:
  var calendar_season = get_season(day_of_year)
  if hemisphere == "south":
    match calendar_season:
      "spring": return "autumn"
      "summer": return "winter"
      "autumn": return "spring"
      "winter": return "summer"
  return calendar_season
```

The weather system, domain simulation, and any other climate-sensitive consumer calls `get_climate_season()` rather than `get_season()` when selecting behavioral profiles. Narrative systems may use either — a culture in the southern hemisphere might still call Month 1 "spring" culturally even though the weather is autumnal.

---

## 5. Seasonal Transition

Seasons do not snap instantly. A **7-day transition window** straddles each season boundary. During this window, any system consuming seasonal profiles blends the outgoing season's values with the incoming season's using linear interpolation:

```
transition_weight = days_into_transition / 7
effective_profile = lerp(outgoing_season_profile, incoming_season_profile, transition_weight)
```

Transition windows:

| Transition | Calendar Days | Window |
|---|---|---|
| Winter → Spring | Day 361 – Day 3 (wraps year boundary) | 7 days centered on Day 1 |
| Spring → Summer | Day 89 – Day 95 | 7 days centered on Day 92 |
| Summer → Autumn | Day 180 – Day 186 | 7 days centered on Day 183 |
| Autumn → Winter | Day 271 – Day 277 | 7 days centered on Day 274 |

The wrap-around at the year boundary (Winter → Spring) ensures the first and last days of the year feel continuous rather than having a hard weather reset.

---

## 6. Integration Points

### 6.1 Downstream Consumers

- **Weather generation** (`gdd-weather-generation.md`) — calls `get_climate_season()` to select seasonal climate profiles; reads solstice/equinox dates for dawn/dusk declination calculation.
- **Domain simulation** — season determines agricultural yield phase (planting, growing, harvest, fallow), trade route accessibility, and army supply modifiers.
- **Timekeeping / session runner** — season is displayed in the UI; day-cycle scheduling uses daylight hours (provided by weather system, which depends on this GDD's season definitions).
- **LLM context assembly** — season name and progress (early/mid/late) included in scene descriptions.
- **NPC scheduling** — daily routines shift with season (e.g., farmers work longer days in summer).

### 6.2 Upstream Producers

- **Design brief §8.3** — defines the 13×28 calendar skeleton.
- **Setting generation pipeline** — provides the `hemisphere` user parameter.

---

## 7. File Organization

```
engine/subsystems/calendar/
  calendar_seasons.gd    # Season lookup, hemisphere inversion, transition blending
  calendar_constants.gd  # Solstice/equinox days, season boundary days
```

---

## 8. Design Decisions (Resolved)

- **Solstices/equinoxes at season midpoints, not boundaries: DECIDED.** Matches real-world convention and produces more intuitive daylight curves. The longest day falls in the middle of summer, not the first day.

- **7-day transition window: DECIDED.** Long enough to prevent abrupt weather shifts at season boundaries; short enough that the seasons feel distinct. The window is symmetric (3.5 days on each side of the boundary).

- **Calendar season names are cultural, climate season is physical: DECIDED.** A southern-hemisphere culture's "Month 1" is still the start of their year, but the weather system knows to apply autumn climate profiles. This separation lets the LLM generate culturally appropriate seasonal references without fighting the climate model.

---

## 9. Revision History

- **2026-03-28:** Initial draft. Extracted from `gdd-weather-generation.md` §3. Season definitions, solstice/equinox table, hemisphere inversion model, transition blending rules. Established as the single authoritative source for seasonal data consumed by weather, domain, timekeeping, and narrative systems.
