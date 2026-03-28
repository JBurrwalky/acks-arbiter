# GDD: Weather Generation

**Authority:** HYBRID — DaW Vagaries weather effects and ACKS movement/visibility rules are SACRED (sourced from XML). All generation algorithms, climate modeling, and dawn/dusk calculations are PROJECT-DESIGNED.
**Status:** Draft
**Depends on ACKS rules:** `daw_vagaries.xml` (severe weather conditions table, weather effect rules), `acore_adventures_and_encounters.xml` (wilderness encounter distance by terrain, visibility rules, terrain movement multipliers, wind conditions for sea travel, foraging/hunting modifiers), `acks_core_spell_catalog_a-i_summary.xml` (Control Weather spell effects)
**Depends on project GDDs:** `gdd-calendar-seasons.md` (season definitions, solstice/equinox dates, hemisphere model, transition blending), `gdd-setting-generation.md` (Layer 2 climate pipeline — Köppen codes, temperature, precipitation, effective latitude per hex), `gdd-terrain-system.md` (terrain tags, biome definitions, encounter table selection), `gdd-combat-map-generation.md` (weather effects on battle maps §13.2–13.3)
**Modifiable by Claude Code:** Yes — all generation algorithms, parameter tables, and scheduling logic are engineering decisions. ACKS-sourced weather effects and movement rules are not modifiable.
**Last updated:** 2026-03-28

---

## 1. Purpose

Provide a deterministic weather simulation that produces realistic, regionally varied weather across the campaign map, driven by the Köppen climate codes already assigned to each hex by the setting generation pipeline. The system models precipitation, cloud cover, temperature, wind, visibility, and daylight hours on a per-hex, per-day basis. Weather changes gradually over time, varies across regions (not uniform), and responds to seasonal shifts.

The weather system feeds three consumers:

1. **Timekeeping** — dawn and dusk times per hex, per day, which the session runner's day-cycle scheduling depends on.
2. **Mechanical effects** — travel speed modifiers, encounter distance/visibility modifiers, and foraging modifiers derived from current weather state.
3. **Narration and UI** — weather description for LLM context, hex hover popup display, and potential future animation overlays.

Weather generation is fully deterministic given a campaign seed + calendar date + hex coordinates. No LLM involvement.

---

## 2. ACKS Rules Constraints (Sacred)

These come directly from the sourcebooks and must be respected exactly.

### 2.1 DaW Severe Weather (daw_vagaries.xml)

The DaW severe weather table cross-indexes terrain type × season to produce a temperature condition (Cold / Mild / Hot) and an atmospheric condition (Calm / Rainy / Snowy / Windy), with percentage chances for some combinations. Weather effects from DaW:

- **Cold:** Strategic movement halved; 10% disease chance per week from exposure.
- **Hot:** Strategic movement halved; supply cost +25%; out-of-supply penalties doubled; mud cannot form.
- **Calm:** No effect.
- **Rainy:** Strategic movement halved; reconnaissance -2; in clear/grass/scrub terrain mud halves movement again; 10% disease chance per week.
- **Snowy:** Strategic movement halved; reconnaissance -4; 10% disease chance per week.
- **Windy:** Strategic movement halved; in barren/desert terrain reconnaissance -4 (sandstorms).
- All effects stack cumulatively.

The weather system's output must be expressible in DaW terms so the domain-level and mass combat systems can consume it directly. The adventuring-scale weather model (§4) is a superset of DaW's categories — it produces finer-grained states that map cleanly back to DaW categories when needed.

### 2.2 Wilderness Encounter Distance (acore_adventures_and_encounters.xml)

Encounter distance varies by terrain. Weather modifies these distances:

- "Harsh weather or dense fog may reduce normal visibility distances by 90%."
- Man-sized targets visible up to 1,000 yards over flat plains under normal conditions.
- Ship-to-ship visibility: up to 6 miles normally; land visible up to 24 miles.

### 2.3 Terrain Movement Multipliers (acore_adventures_and_encounters.xml)

Base terrain multipliers are sacred. Weather applies additional modifiers on top of terrain (§7.1).

### 2.4 Wind Conditions for Sea Travel (acore_adventures_and_encounters.xml)

The wind conditions table (d20: Becalmed through Gale) with sailing modifiers is sacred. The weather system generates a wind state that maps to this table for sea hexes.

### 2.5 Control Weather Spell (acks_core_spell_catalog_a-i_summary.xml)

The arcane 6th-level spell creates a chosen weather condition in a 240-yard radius. The spell's weather categories (Calm, Hot, Cold, Severe Winds, Tornado, Foggy, Rainy, Snowy) and their effects are sacred. The weather system must support spell-imposed overrides at the local level.

---

## 3. Calendar and Seasons

Season definitions, solstice/equinox dates, hemisphere inversion, and seasonal transition blending are defined in `gdd-calendar-seasons.md`. That GDD is the single authoritative source for all seasonal data.

The weather system calls `get_climate_season(day_of_year, hemisphere)` from the calendar/seasons subsystem to determine which seasonal climate profile to use. Transition blending (7-day lerp window at season boundaries) is applied to climate profile weights before weather channel rolls (§5.3 step 1). Solstice and equinox dates feed the dawn/dusk declination calculation (§6.2).

---

## 4. Weather State Model

Each hex carries a weather state record updated daily. The state consists of six channels:

### 4.1 Temperature Band

An ordinal category rather than a precise degree value, since ACKS mechanics operate on categorical weather, not numeric temperature.

| Band | Label | Rough °C Equivalent | Notes |
|---|---|---|---|
| 0 | Frigid | < -10°C | Extreme cold; exposure risk per hour |
| 1 | Cold | -10°C to 5°C | DaW "Cold" equivalent |
| 2 | Cool | 5°C to 15°C | Comfortable with layers; no mechanical effect |
| 3 | Mild | 15°C to 25°C | DaW "Mild" equivalent; no mechanical effect |
| 4 | Warm | 25°C to 35°C | Comfortable but noticeable; no mechanical effect |
| 5 | Hot | > 35°C | DaW "Hot" equivalent |

The base temperature band for a hex is determined by its Köppen code + current season + elevation, then modified by the daily weather roll.

### 4.2 Precipitation

| Level | Label | Description |
|---|---|---|
| 0 | None | Dry skies |
| 1 | Drizzle / Flurries | Light intermittent precipitation; no mechanical effect |
| 2 | Rain / Snow | Steady precipitation; DaW "Rainy" or "Snowy" equivalent |
| 3 | Heavy Rain / Blizzard | Intense precipitation; visibility severely reduced |
| 4 | Storm | Thunderstorm, ice storm, or whiteout; dangerous conditions |

Whether precipitation falls as rain or snow is determined by the temperature band: bands 0–1 produce snow/ice forms; bands 2+ produce rain. Band 2 at precipitation level 2+ may produce sleet (mixed).

### 4.3 Cloud Cover

| Level | Label | Effect |
|---|---|---|
| 0 | Clear | Full sun; sharp shadows; maximum visibility |
| 1 | Partly Cloudy | Intermittent sun; no mechanical effect |
| 2 | Overcast | Full cloud cover; diffuse light; no mechanical effect |
| 3 | Heavy Overcast / Fog | Reduced visibility (§7.2); fog is a special case that can occur at any cloud level but is tracked here |

Fog is a distinct flag that can be set independently of cloud level. Fog occurs most commonly at cloud levels 2–3 in humid climates, near water, or in valleys at dawn.

### 4.4 Wind

| Level | Label | Beaufort Approx. | DaW/ACKS Mapping |
|---|---|---|---|
| 0 | Calm | 0–1 | Becalmed (sea); no land effect |
| 1 | Light | 2–3 | Light Breeze (×1/3 sailing) |
| 2 | Moderate | 4–5 | Moderate Breeze (×2/3 sailing) |
| 3 | Average | 6 | Average Winds (×1 sailing) |
| 4 | Strong | 7 | Strong Winds (×1⅓ sailing) |
| 5 | Very Strong | 8–9 | Very Strong Winds (×1⅔ sailing); DaW "Windy" equivalent |
| 6 | Gale | 10+ | Gale (×2 sailing); severe danger on land |

Wind also carries a **direction** (one of 8 compass points: N, NE, E, SE, S, SW, W, NW). Wind direction is used for sailing mechanics and influences weather propagation across the map (§5.5).

### 4.5 Visibility Modifier

A multiplier applied to base encounter distances and spotting ranges. Derived from the combination of precipitation, cloud cover, fog, wind, and time of day:

| Condition | Visibility Multiplier |
|---|---|
| Clear day, no precipitation | 1.0 (full) |
| Partly cloudy | 1.0 |
| Overcast | 0.9 |
| Light rain/drizzle | 0.75 |
| Steady rain or snow | 0.5 |
| Heavy rain, blizzard, sandstorm | 0.25 |
| Dense fog | 0.1 (matches ACKS "90% reduction") |
| Storm | 0.15 |
| Night, clear sky, moonlit | 0.3 |
| Night, overcast / no moon | 0.1 |

Multiple conditions stack multiplicatively. Example: steady rain (0.5) at night with overcast (0.1) = 0.05 total multiplier.

### 4.6 Complete Weather State Record

```
WeatherState:
  hex_id: int
  day_of_year: int
  temperature_band: int (0-5)
  precipitation_level: int (0-4)
  precipitation_type: enum (none, rain, snow, sleet, hail)
  cloud_cover: int (0-3)
  fog: bool
  wind_level: int (0-6)
  wind_direction: enum (N, NE, E, SE, S, SW, W, NW)
  visibility_multiplier: float (0.0-1.0)
  dawn_hour: float (fractional hours, e.g. 6.5 = 6:30 AM)
  dusk_hour: float
  daw_temperature: enum (Cold, Mild, Hot)  # derived for DaW compatibility
  daw_atmosphere: enum (Calm, Rainy, Snowy, Windy)  # derived for DaW compatibility
```

---

## 5. Weather Generation Algorithm

### 5.1 Climate Profile Tables

Each Köppen code maps to a **climate profile** — a set of seasonal probability distributions for each weather channel. These profiles are the core data tables driving the generator.

A climate profile contains, per season:

```
ClimateSeasonProfile:
  temperature_weights: array[6]     # probability weights for bands 0-5
  precipitation_weights: array[5]   # probability weights for levels 0-4
  cloud_weights: array[4]           # probability weights for levels 0-3
  wind_weights: array[7]            # probability weights for levels 0-6
  fog_chance: float                 # daily probability of fog (0.0-1.0)
  prevailing_wind: enum             # dominant wind direction this season
```

The full profile table is defined in §5.2. Each Köppen code has 4 seasonal profiles (spring, summer, autumn, winter).

### 5.2 Köppen Climate Profile Table

The following table defines representative profiles for each Köppen group used in the game. Profiles are expressed as the **most likely** temperature band and precipitation level per season, plus qualitative descriptors. The actual implementation stores full probability weight arrays derived from these reference points.

**Group A — Tropical:**

| Code | Spring | Summer | Autumn | Winter | Wind Pattern |
|---|---|---|---|---|---|
| Af | Warm, Rain frequent (70%) | Hot, Rain frequent (75%) | Warm, Rain frequent (70%) | Warm, Rain moderate (60%) | Light, variable |
| Am | Hot, Heavy rain (80%) | Hot, Storm possible (20%) | Warm, Rain tapering | Warm, Dry (80% none) | Moderate, monsoon shift |
| Aw | Hot, Dry transitioning to wet | Hot, Rain frequent (65%) | Warm, Rain tapering | Warm to Hot, Dry (85% none) | Light to moderate |

**Group B — Arid:**

| Code | Spring | Summer | Autumn | Winter | Wind Pattern |
|---|---|---|---|---|---|
| BWh | Hot, Dry (95% none) | Hot, Dry (98% none) | Warm, Dry (95% none) | Mild, Dry (90% none) | Moderate, steady |
| BWk | Cool, Dry (95% none) | Warm, Dry (95% none) | Cool, Dry (95% none) | Cold, Dry (90% none) | Moderate to strong |
| BSh | Warm, Drizzle possible (20%) | Hot, Dry (90% none) | Warm, Drizzle possible (15%) | Mild, Light rain possible (25%) | Light to moderate |
| BSk | Cool, Light rain possible (25%) | Warm, Dry (85% none) | Cool, Light rain possible (20%) | Cold, Snow flurries possible (20%) | Moderate |

**Group C — Temperate:**

| Code | Spring | Summer | Autumn | Winter | Wind Pattern |
|---|---|---|---|---|---|
| Cfa | Mild, Rain moderate (50%) | Hot, Rain + storms (60%) | Mild, Rain moderate (45%) | Cool, Rain/snow mix (40%) | Light to moderate |
| Cfb | Cool, Rain frequent (55%) | Mild, Rain moderate (50%) | Cool, Rain frequent (55%) | Cool, Rain frequent (50%) | Moderate, westerly |
| Cfc | Cool, Rain frequent (60%) | Cool, Rain moderate (50%) | Cool, Rain frequent (60%) | Cold, Rain/snow (55%) | Moderate to strong |
| Csa | Mild, Rain moderate (45%) | Hot, Dry (85% none) | Mild, Rain returning (40%) | Cool, Rain frequent (60%) | Light, variable |
| Csb | Cool, Rain moderate (45%) | Mild, Dry (80% none) | Cool, Rain returning (40%) | Cool, Rain frequent (55%) | Moderate, westerly |
| Cwa | Warm, Rain increasing (50%) | Hot, Rain heavy (70%) | Warm, Rain tapering (40%) | Mild, Dry (80% none) | Monsoon shift |
| Cwb | Mild, Rain increasing (45%) | Mild, Rain moderate (55%) | Mild, Rain tapering (35%) | Cool, Dry (75% none) | Light |

**Group D — Continental:**

| Code | Spring | Summer | Autumn | Winter | Wind Pattern |
|---|---|---|---|---|---|
| Dfa | Cool, Rain moderate (45%) | Hot, Rain + storms (55%) | Cool, Rain moderate (40%) | Cold, Snow frequent (50%) | Moderate |
| Dfb | Cool, Rain/snow mix (45%) | Mild, Rain moderate (50%) | Cool, Rain moderate (45%) | Cold, Snow frequent (55%) | Moderate |
| Dfc | Cold, Snow/rain mix (50%) | Cool, Rain moderate (45%) | Cold, Snow/rain mix (50%) | Frigid, Snow frequent (60%) | Moderate to strong |
| Dfd | Cold, Snow (55%) | Cool, Rain moderate (40%) | Cold, Snow (55%) | Frigid, Snow heavy (70%) | Strong |
| Dwa | Cool, Dry (70% none) | Hot, Rain heavy (65%) | Cool, Dry tapering (60% none) | Cold, Dry (80% none) | Monsoon shift |
| Dwb | Cool, Dry (65% none) | Mild, Rain moderate (55%) | Cool, Dry (60% none) | Cold, Dry (75% none) | Monsoon shift |
| Dwc | Cold, Dry (70% none) | Cool, Rain moderate (50%) | Cold, Dry (65% none) | Frigid, Dry (80% none) | Strong |
| Dwd | Cold, Dry (75% none) | Cool, Rain light (40%) | Cold, Dry (70% none) | Frigid, Dry (85% none) | Strong, steady |

**Group E — Polar:**

| Code | Spring | Summer | Autumn | Winter | Wind Pattern |
|---|---|---|---|---|---|
| ET | Cold, Snow/rain mix (45%) | Cool, Rain light (35%) | Cold, Snow (50%) | Frigid, Snow (55%) | Strong, variable |
| EF | Frigid, Snow light (40%) | Frigid, Snow flurries (35%) | Frigid, Snow (45%) | Frigid, Snow (50%) | Strong, steady |

### 5.3 Daily Weather Generation Procedure

Weather is generated per hex, per day. The procedure uses a seeded RNG to ensure determinism:

```
seed = hash(campaign_seed, hex_id, day_of_year, year)
rng = RandomNumberGenerator(seed)

1. Look up hex Köppen code → retrieve seasonal climate profile
   (using current season with transition blending per `gdd-calendar-seasons.md` §5)

2. Apply elevation modifier:
   - Per 1000m elevation equivalent above sea level,
     shift temperature_weights one band colder
   - Mountain hexes get +10% to precipitation_weights at levels 2+
   - Valley hexes (lowest local elevation) get +15% fog_chance

3. Apply coastal modifier:
   - Hexes within 2 of ocean: wind_weights shift +1 level
   - Coastal hexes: +10% fog_chance; temperature extremes dampened
     (reduce weight on bands 0 and 5 by 20%, redistribute to 1 and 4)

4. Roll each channel independently using weighted random selection:
   temperature_band = weighted_choice(rng, modified_temperature_weights)
   precipitation_level = weighted_choice(rng, modified_precipitation_weights)
   cloud_cover = weighted_choice(rng, modified_cloud_weights)
   wind_level = weighted_choice(rng, modified_wind_weights)
   fog = rng.randf() < modified_fog_chance

5. Apply coherence constraints (§5.4)

6. Derive precipitation_type from temperature_band:
   if temperature_band <= 1: snow (or blizzard at level 3+)
   elif temperature_band == 2 and precipitation_level >= 2: sleet (50%) or rain
   else: rain (or thunderstorm at level 4)

7. Derive visibility_multiplier from state channels (§4.5 table)

8. Calculate dawn_hour and dusk_hour (§6)

9. Derive DaW compatibility fields:
   daw_temperature: band 0-1 → Cold; band 2-3 → Mild; band 4-5 → Hot
   daw_atmosphere: precipitation 0 + wind < 5 → Calm;
                   precipitation 2+ snow → Snowy;
                   precipitation 2+ rain → Rainy;
                   wind >= 5 → Windy
```

### 5.4 Coherence Constraints

After independent channel rolls, apply physical plausibility corrections:

- **Rain requires clouds:** If precipitation_level >= 1, force cloud_cover >= 2.
- **Storm requires wind:** If precipitation_level >= 4, force wind_level >= 4.
- **Fog suppresses wind:** If fog == true, cap wind_level at 2 (fog disperses in strong wind).
- **Desert fog is rare:** In BWh/BWk hexes, fog only persists if adjacent to water (river, coast).
- **Blizzard requires cold:** If precipitation_level >= 3 and temperature_band >= 3, downgrade to heavy rain instead.
- **Hail:** At precipitation_level 4 with temperature_band 3–4, there is a 30% chance the storm includes hail (narrative detail, no additional mechanical effect beyond storm).

### 5.5 Weather Persistence and Regional Variation

Weather should not change randomly from hex to hex. A "weather region" system ensures spatial coherence:

**Weather fronts:** At the start of each game day, the system generates 1–3 weather fronts across the campaign map. Each front is a line segment with a width (3–8 hexes) and a movement direction (aligned with prevailing wind). Fronts carry a weather modification:

```
WeatherFront:
  position: line segment across hex grid
  width: int (3-8 hexes)
  direction: compass heading
  speed: int (1-3 hexes per day)
  type: enum (warm_front, cold_front, storm_front, dry_front)
  intensity: float (0.5-2.0, multiplier on precipitation weights)
  duration: int (2-7 days remaining)
```

Front effects:
- **Warm front:** Shift temperature +1 band; increase precipitation weights at levels 1–2; increase cloud cover.
- **Cold front:** Shift temperature -1 band; increase precipitation at levels 2–3; increase wind +1 level.
- **Storm front:** Increase precipitation at levels 3–4; increase wind +1–2 levels; increase cloud to 3.
- **Dry front:** Decrease precipitation weights at all levels; decrease cloud cover.

Fronts move across the map daily according to their speed and direction. Hexes under a front's influence zone have their climate profile modified before rolling.

**Temporal persistence:** Each hex's weather state carries forward with inertia. The daily generation is not purely independent — 60% of the new day's state is influenced by the previous day's state, 40% by the fresh climate profile roll. This prevents whiplash day-to-day changes:

```
for each channel:
  raw_roll = weighted_choice(rng, climate_profile_weights)
  if abs(raw_roll - yesterday.channel_value) > 1:
    # Large jumps are dampened
    effective_value = yesterday.channel_value + sign(raw_roll - yesterday.channel_value)
  else:
    effective_value = raw_roll
```

This means weather usually changes by at most 1 step per day per channel. A bright clear day doesn't become a blizzard overnight — it transitions through overcast, then rain, then snow over several days.

### 5.6 Köppen Subset Bounding

The full Köppen system includes ~30 distinct codes. A given campaign setting uses only a subset determined by the setting generation pipeline's latitude range and geographic features.

**At setting generation time (Layer 2):**

1. The climate generator assigns a Köppen code to every hex.
2. After assignment, the weather system scans all hex codes and builds the **active Köppen set** — the unique codes actually present on the map.
3. Only climate profiles for codes in the active set are loaded into memory.

**Typical subsets by setting latitude_range parameter:**

| latitude_range | Typical Active Codes | Climate Character |
|---|---|---|
| Tropical | Af, Am, Aw, BWh, BSh | Hot and wet, with desert margins |
| Subtropical | Aw, BSh, BSk, Cfa, Csa, Cwa | Warm with seasonal variation |
| Temperate | Cfb, Cfc, Csb, Dfb, BSk | Classic four-season; the default |
| Continental | Dfb, Dfc, Dfd, BSk, ET | Cold winters, warm summers |
| Polar | Dfc, Dfd, ET, EF | Short cool summers, long harsh winters |
| Mixed (large maps) | 10–15 codes spanning multiple groups | Full diversity |

The setting map area (~100,000 to ~1,550,000 sq mi depending on map size) corresponds to a segment of an earth-sized planet. The latitude_range parameter determines where on that planet the map falls. Even a "Huge" map at ~1,550,000 sq mi covers roughly 4% of a hemisphere's land area — equivalent to the contiguous United States — which realistically spans about 8–12 Köppen codes. A "Small" map might span 3–5 codes.

The weather system does not simulate global atmospheric circulation. It assumes prevailing wind direction (a user parameter, default west-to-east) and derives regional weather variation from the interaction of that wind with the map's terrain (mountains, coast, latitude gradient). This is the same approach used by Azgaar's Fantasy Map Generator — local simulation within a bounded region, with global-scale patterns represented as configurable parameters rather than simulated from first principles.

---

## 6. Dawn and Dusk Calculation

### 6.1 Purpose

The timekeeping system requires dawn and dusk times for each hex on each game day. These determine:

- When daylight travel begins and ends (affects travel hours per day).
- When night encounters use darkness visibility rules.
- When light sources become necessary.
- Watch scheduling during camp.

### 6.2 Simplified Sunrise Equation

The game uses an earth-like planet with 23.45° axial tilt and a 364-day year. The sunrise equation is simplified from the real-world formula, adapted for the game calendar:

```
# Inputs
latitude = hex_effective_latitude (degrees, from setting generation)
day = day_of_year (1-364)

# Solar declination (simplified sinusoidal model)
declination = 23.45 * sin(2π * (day - 80) / 364)
# day 80 ≈ vernal equinox area; peak at day 171 ≈ summer solstice

# Hour angle at sunrise/sunset
cos_hour_angle = -tan(latitude) * tan(declination)

# Clamp for polar day/night
if cos_hour_angle < -1.0:
  # Polar day (midnight sun): dawn = 0.0, dusk = 24.0
  dawn = 0.0
  dusk = 24.0
elif cos_hour_angle > 1.0:
  # Polar night: dawn = 12.0, dusk = 12.0 (no daylight)
  dawn = 12.0
  dusk = 12.0
else:
  hour_angle = acos(cos_hour_angle)  # in radians
  daylight_hours = 2.0 * hour_angle * (12.0 / π)
  dawn = 12.0 - (daylight_hours / 2.0)
  dusk = 12.0 + (daylight_hours / 2.0)
```

### 6.3 Hex Effective Latitude

Each hex has an effective latitude derived from the setting generation pipeline. The formula and the canonical latitude range presets (degree values for Tropical, Subtropical, Temperate, Continental, Polar) are defined in `gdd-setting-generation.md` §5.1. The weather system reads `hex.effective_latitude` as stored data — it does not compute latitude independently.

Southern hemisphere settings use the same absolute latitude values with negative sign. The hemisphere flag (per `gdd-calendar-seasons.md` §4) handles season inversion; the dawn/dusk equation (§6.2) uses the absolute latitude value with sign for correct polar day/night behavior.

### 6.4 Daylight Hours Examples

At 45°N latitude (mid-temperate):

| Season Point | Day | Declination | Daylight Hours | Dawn | Dusk |
|---|---|---|---|---|---|
| Vernal Equinox | 46 | ~0° | ~12h 0m | 6:00 | 18:00 |
| Summer Solstice | 137 | ~+23.4° | ~15h 30m | 4:15 | 19:45 |
| Autumnal Equinox | 228 | ~0° | ~12h 0m | 6:00 | 18:00 |
| Winter Solstice | 319 | ~-23.4° | ~8h 30m | 7:45 | 16:15 |

These match real-world day lengths at comparable latitudes, providing an intuitive experience.

### 6.5 Civil Twilight

Dawn and dusk are the moments of actual sunrise/sunset. The system also provides civil twilight bounds — the period before dawn / after dusk when there is enough ambient light to see without artificial sources:

```
twilight_duration = 0.5 hours (fixed approximation)
civil_dawn = dawn - twilight_duration
civil_dusk = dusk + twilight_duration
```

During civil twilight, the visibility multiplier is 0.5 (reduced but not darkness). The session runner uses civil dawn/dusk for the "safe travel without light sources" window.

---

## 7. Mechanical Effects

### 7.1 Travel Speed Modifier

Weather applies a multiplier to daily wilderness movement rate, stacking with terrain multipliers from ACKS:

| Weather Condition | Travel Multiplier | Source |
|---|---|---|
| DaW Cold (temp band 0–1) | ×0.5 | Sacred (DaW) |
| DaW Hot (temp band 5) | ×0.5 | Sacred (DaW) |
| DaW Rainy (precip 2+ rain) | ×0.5 | Sacred (DaW) |
| DaW Snowy (precip 2+ snow) | ×0.5 | Sacred (DaW) |
| DaW Windy (wind 5+) | ×0.5 | Sacred (DaW) |
| Mud (rain on clear/grass/scrub) | ×0.5 additional | Sacred (DaW) |
| Light precipitation (precip 1) | ×0.9 | Project-designed |
| Storm (precip 4) | ×0.33 | Project-designed |
| Dense fog | ×0.75 | Project-designed |
| Frigid (temp band 0) | ×0.33 | Project-designed |

DaW multipliers stack cumulatively per the sacred rules. Project-designed modifiers also stack but are capped so total weather penalty never exceeds ×0.1 (weather alone cannot reduce travel to zero — the party can always crawl forward at 10% speed).

### 7.2 Encounter Distance Modifier

The visibility_multiplier (§4.5) is applied directly to the rolled encounter distance:

```
effective_encounter_distance = base_roll * visibility_multiplier
```

Where `base_roll` is the terrain-specific encounter distance roll from ACKS (e.g., 5d20 × 10 yards for plains). This means heavy fog on plains reduces the 500–1000 yard sighting distance to 50–100 yards — consistent with the ACKS "90% reduction" rule.

### 7.3 Foraging and Hunting Modifier

| Condition | Modifier | Source |
|---|---|---|
| Storm or blizzard | Foraging impossible; hunting impossible | Project-designed |
| Heavy rain/snow | Foraging -2; hunting -2 | Project-designed |
| Steady rain/snow | Foraging -1; hunting -1 | Project-designed |
| Dense fog | Hunting -2 (can't see prey) | Project-designed |
| Frigid | Foraging -4 (nothing grows) | Project-designed |

These modify the proficiency throw target, stacking with Survival proficiency bonus (+4) and terrain factors.

### 7.4 Sea Travel Wind Mapping

The weather system's wind_level maps directly to the ACKS wind conditions table:

| wind_level | ACKS Wind Condition | Sailing Modifier |
|---|---|---|
| 0 | Becalmed | ×0 |
| 1 | Light Breeze | ×1/3 |
| 2 | Moderate Breeze | ×2/3 |
| 3 | Average Winds | ×1 |
| 4 | Strong Winds | ×1⅓ |
| 5 | Very Strong Winds | ×1⅔ |
| 6 | Gale | ×2 |

Wind direction relative to the vessel's heading determines whether the tacking penalty applies (sailing against the wind reduces modifier by two rows).

### 7.5 Mud Formation

Per DaW: Rainy weather in clear, grass, or scrub terrain forms mud, which halves movement again. The weather system tracks mud as a hex-level persistent state:

```
if precipitation_level >= 2 and precipitation_type == rain:
  if hex.biome in [clear, scrub]:  # grass is represented as clear
    hex.mud = true
    hex.mud_duration = 2  # days after rain stops before mud dries

# Mud dries:
if hex.mud and precipitation_level < 2:
  hex.mud_duration -= 1
  if hex.mud_duration <= 0:
    hex.mud = false

# Hot weather dries mud faster:
if hex.mud and temperature_band >= 4:
  hex.mud_duration -= 1  # dries in half the time
```

---

## 8. Spell and Override Integration

### 8.1 Control Weather Spell

When a caster uses Control Weather, the spell creates a localized weather override within a 240-yard radius (roughly one-quarter of a 6-mile hex):

```
WeatherOverride:
  center: hex_id (and sub-hex position if at 6-mile scale)
  radius: 240 yards
  imposed_state: WeatherState (partial — only channels the spell specifies)
  duration: indefinite while concentrating
  source: spell
```

The spell's weather categories map to weather state channels:
- Calm → precipitation 0, wind 0, fog false
- Hot → temperature band 5
- Cold → temperature band 0-1
- Severe Winds → wind 5
- Tornado → wind 6, precipitation 4 (storm)
- Foggy → fog true, visibility 0.1
- Rainy → precipitation 2-3 (rain), cloud 3
- Snowy → precipitation 2-3 (snow), cloud 3, temperature band 1

### 8.2 Human Override

The override system (design brief §8.5) allows the player to manually set weather for any hex or region. Overrides are logged and persist until cleared or until the next natural weather generation cycle.

---

## 9. UI Presentation

### 9.1 Hex Hover Popup

When the player hovers over a hex on the wilderness map, the popup includes a weather line. Format:

```
[Weather icon] [Temperature label], [Precipitation label], [Wind label]
Example: ☀️ Mild, Clear, Light Winds
Example: 🌧️ Cool, Steady Rain, Moderate Winds
Example: ❄️ Cold, Heavy Snow, Strong Winds — Visibility Reduced
```

If visibility_multiplier < 0.5, append "— Visibility Reduced". If < 0.25, append "— Visibility Severely Reduced".

If mud is active: append "— Muddy Ground".

### 9.2 Weather Panel

A collapsible panel in the exploration UI shows current weather for the party's hex. **Default state: hidden**, with a persistent weather tab (small icon + one-line summary, e.g. "🌧️ Cool, Rain") always visible at the panel edge. Clicking the tab expands the full panel:

```
┌─────────────────────────┐
│  ☁️  Overcast, Cool      │
│  🌧️  Steady Rain          │
│  💨  Moderate W Wind      │
│  👁️  Visibility: 50%      │
│  🌅  Dawn 5:48 Dusk 19:12 │
└─────────────────────────┘
```

### 9.3 LLM Context

When assembling context for LLM narration, the weather system provides a natural-language weather summary:

```
"The weather in this hex is [temperature_label] with [precipitation_description] and 
[wind_description]. [fog_description]. Visibility is [visibility_description]. 
The sun rises at [dawn] and sets at [dusk]."
```

Example: "The weather is cool with a steady rain falling and moderate westerly winds. A low fog clings to the valley floor. Visibility is poor — about half normal range. The sun rises at 6:15 and sets at 18:45."

### 9.4 Future Animation Layer

Placeholder for v1: weather icons only. Post-v1 enhancement: particle overlays on the hex map for rain, snow, fog. The weather state record contains all information needed to drive such overlays (precipitation type and intensity, fog boolean, wind direction for particle drift).

---

## 10. Data Storage

### 10.1 Schema

Weather states are ephemeral and regenerated on demand from the deterministic seed. Only overrides and mud state need persistence:

```sql
-- Persistent weather overrides (spell effects, human overrides)
CREATE TABLE weather_overrides (
  id INTEGER PRIMARY KEY,
  hex_id INTEGER NOT NULL,
  source TEXT NOT NULL,  -- 'spell', 'override'
  temperature_band INTEGER,  -- NULL = no override for this channel
  precipitation_level INTEGER,
  precipitation_type TEXT,
  cloud_cover INTEGER,
  fog INTEGER,
  wind_level INTEGER,
  wind_direction TEXT,
  start_day INTEGER NOT NULL,
  duration_days INTEGER,  -- NULL = indefinite
  FOREIGN KEY (hex_id) REFERENCES hexes(id)
);

-- Persistent mud tracking
CREATE TABLE hex_mud_state (
  hex_id INTEGER PRIMARY KEY,
  mud_active INTEGER NOT NULL DEFAULT 0,
  days_remaining INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (hex_id) REFERENCES hexes(id)
);
```

Weather state for the current day is computed on demand and cached in memory for the active session. When the player advances time (travel, rest, downtime), weather is regenerated for the new day.

### 10.2 Performance

Weather generation per hex is trivially cheap (~10 weighted random rolls per hex). For a full map recalculation (e.g., advancing a full month during downtime), even a Huge map (2,700 hexes) requires only ~27,000 random rolls — well under a millisecond. Weather fronts add a spatial query (which hexes are under each front) but this is a simple distance check.

The expensive path is batch-computing a full month of weather for all hexes (for domain simulation or NPC army movement). At 2,700 hexes × 28 days = 75,600 weather state calculations — still trivially fast. No optimization needed beyond the deterministic seed approach.

---

## 11. Integration Points

### 11.1 Upstream Producers

- **Calendar/seasons system** (`gdd-calendar-seasons.md`): Provides current season, climate season (hemisphere-adjusted), transition blending weights, and solstice/equinox reference dates.
- **Setting generation pipeline (Layer 2):** Provides each hex's Köppen code, elevation, effective latitude, coastal proximity, and prevailing wind direction.
- **Timekeeping system:** Provides current game day and year.
- **Spell system:** Produces weather overrides from Control Weather and similar effects.
- **Override system:** Produces manual weather overrides.

### 11.2 Downstream Consumers

- **Timekeeping system:** Consumes dawn/dusk times for day-cycle scheduling.
- **Movement/exploration system:** Consumes travel speed multipliers and mud state.
- **Encounter system:** Consumes visibility multiplier for encounter distance rolls.
- **Combat map generation:** Consumes weather state for battle map surface types and LOS caps (per `gdd-combat-map-generation.md` §13.2).
- **Sea travel system:** Consumes wind level and direction for sailing modifier lookup.
- **Foraging/hunting system:** Consumes weather modifiers for proficiency throws.
- **Domain simulation (DaW):** Consumes DaW-compatible temperature + atmosphere categories.
- **LLM context assembly:** Consumes natural-language weather summary.
- **UI renderer:** Consumes weather state for hex popup, weather panel, and future animation layer.

### 11.3 What This System Does NOT Do

- **Climate generation.** The setting generator assigns Köppen codes. This system reads them.
- **Long-term climate change.** Climate is static for the campaign's lifetime. No multi-year warming/cooling.
- **Indoor weather.** Dungeons, settlements, and interiors are unaffected. Weather applies only to wilderness and sea hexes.
- **Magical weather patterns.** Cursed regions, elemental planes, or supernatural weather zones are implemented as persistent overrides (§8), not as special climate codes.

---

## 12. File Organization

```
engine/subsystems/weather/
  weather_generator.gd        # Core daily weather generation algorithm
  weather_state.gd            # WeatherState data class
  climate_profiles.gd         # Köppen → seasonal profile lookup tables
  weather_front.gd            # Weather front propagation logic
  dawn_dusk_calculator.gd     # Sunrise equation implementation
  weather_effects.gd          # Mechanical effect derivation (travel, visibility, etc.)
  weather_override.gd         # Spell and manual override management
  weather_ui.gd               # Weather panel and hex popup data formatting

data/climate/
  koppen_profiles.json        # Full climate profile table (§5.2 in machine-readable form)
```

---

## 13. Design Decisions (Resolved)

- **Categorical temperature bands, not numeric degrees: DECIDED.** ACKS mechanics use categorical weather (Cold/Mild/Hot). A numeric temperature adds complexity with no mechanical payoff. The 6-band system provides enough granularity for narration (the LLM can turn "Cool" into evocative prose) while keeping the engine simple. If a spell or effect needs a specific temperature, it operates on bands.

- **Deterministic seed-based generation, not pre-rolled weather tables: DECIDED.** Weather is regenerated from seed + date + hex ID on demand. This avoids storing 364 × N_hexes weather records per campaign year. The seed guarantees the same weather if the player reloads or the system recalculates. Weather fronts are also seeded deterministically (front positions derived from campaign_seed + day_of_year).

- **Weather fronts for regional coherence, not cellular automata: DECIDED.** A cellular automaton propagation model (where each hex's weather influences neighbors) is more physically realistic but much more expensive and harder to make deterministic across save/load boundaries. The front-based system achieves plausible regional variation with simple geometry and is trivially reproducible from seed.

- **No microclimate simulation: DECIDED for v1.** Individual 6-mile hexes within a 24-mile hex all share the parent's weather. This could be refined later (e.g., rain shadow within a single 24-mile hex containing mountains) but adds complexity with minimal gameplay payoff.

- **Prevailing wind as a user parameter, not simulated: DECIDED.** Following Azgaar's approach — global atmospheric circulation is a parameter, not a simulation. Most fantasy settings assume broadly west-to-east winds (like Earth's mid-latitudes). The user can change this at campaign creation for exotic settings (e.g., a tidally-locked world with permanent easterlies).

- **Dawn/dusk provided by weather system, not timekeeping: DECIDED.** The timekeeping system requested this. Dawn/dusk depends on latitude and day-of-year, which are geographic/seasonal data owned by the weather system. Timekeeping consumes the output.

---

## 14. Open Questions

None at this time. All design questions resolved during drafting.

---

## 15. Revision History

- **2026-03-28:** Initial draft. Full weather state model with six channels. Köppen climate profile table covering all groups A–E. Simplified sunrise equation for dawn/dusk. Weather front system for regional coherence. Temporal persistence for gradual day-to-day changes. Full integration with DaW weather effects (sacred), ACKS movement/visibility rules (sacred), and Control Weather spell. Mud tracking. UI spec for hex hover popup and weather panel. Deterministic seed-based generation.
- **2026-03-28 (rev 2):** Refactored. Extracted §3 (Calendar and Seasons) into standalone `gdd-calendar-seasons.md`. Moved latitude range presets from §6.3 to `gdd-setting-generation.md` §5.1 (canonical owner). Replaced extracted content with cross-references. Title changed from "Weather and Seasons Generation" to "Weather Generation". Weather panel specified as collapsible-default-hidden with persistent tab.
