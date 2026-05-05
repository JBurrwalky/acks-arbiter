# GDD: Tracking

**Authority:** SACRED. The throw target, modifiers, and half-speed penalty all come from `acore_proficiencies_rules_and_catalog.xml` Tracking entry. Daily tracking-check cadence and weather-decay accumulation across save/load are PROJECT-DESIGNED elaborations.
**Status:** Phase 5 v1 implemented (2026-05-04).
**Depends on ACKS rules:** `acore_proficiencies_rules_and_catalog.xml` (Tracking proficiency entry).
**Depends on project GDDs:** `gdd-realtime-scheduler.md` (event-driven daily checks), `gdd-weather-generation.md` (atmosphere channel drives the rain/snow decay).

---

## 1. Purpose

Per-trail tracking — a party with the Tracking proficiency follows a creature group, character, or caravan across the wilderness over multiple days. Distinct from the Phase 4 lair-search +4 Tracking bonus, which uses the proficiency to detect lairs at hex granularity.

---

## 2. ACKS Rules Constraints (Sacred)

`acore_proficiencies_rules_and_catalog.xml` Tracking entry:

> **Base throw:** 11+ on 1d20.
> **Group-size modifiers:** +2 (2-4 creatures), +4 (4-8), +6 (8-16), +8 (17 or more).
> **Ground modifiers:** +4 soft or muddy ground; -8 hard or rocky ground.
> **Lighting:** -4 in bad lighting.
> **Weather decay:** -1 per 12 hours of good weather since the trail was made; -4 per hour of rain or snow.
> **Movement:** Characters move at half speed while tracking.

Phase 5 implements every modifier above. Group-size band overlaps in RAW (4-8 spans the +4 and +6 boundary) are split as 2-4 → +2, 5-7 → +4, 8-15 → +6, 17+ → +8. The +6 and +8 rows have a 1-creature gap at exactly 16, which v1 maps to +6 (lower band). Test fixtures pin the exact values.

---

## 3. Project-Designed Elaborations

### 3.1 Daily check cadence

RAW does not specify *when* a tracking throw happens. Phase 5 v1 fires one throw per game day per active session, scheduled as a `tracking_check` event in the EventScheduler. The first throw fires when the session opens; subsequent throws self-reschedule on success at +24hr. Failure closes the session "lost_trail" — no retry without re-opening.

Rationale: a daily throw matches the wilderness day-tick cadence we're already running for sustenance and weather. A per-hour throw would fire 24× more often and turn tracking into a clicker. A single one-shot throw doesn't represent a multi-day pursuit.

### 3.2 Accumulating weather decay

RAW says "-1 per 12 hours of good weather *since the trail was made*" and "-4 per hour of rain or snow *since the trail was made*". Phase 5 maintains the running total in the `tracking_sessions.weather_decay_total` column (REAL) and adds the elapsed-period decay each daily check. The period-average weather is the current hex's weather (a v1 simplification — future polish can integrate weather over the trail length).

### 3.3 One open session per party

v1 enforces a single open session per party. Opening a new session while one is open is undefined behavior (caller responsibility). Future polish: allow multiple parallel trails when a sub-party splits off (already supported by `splitting_up` in the lair-search rules).

### 3.4 Half-speed during tracking

Per RAW: "Characters move at half speed while tracking." Phase 5 wires `is_tracking: bool` parameter into `TravelSpeedCalculator.calculate_party_speed`, applied as a 0.5× multiplier after terrain × encumbrance × forced-march × weather. The wilderness handler queries `CampaignRepository.get_open_tracking_session(...)` when scheduling travel and sets the flag.

---

## 4. Implementation Map

| Concern | File |
|---|---|
| Throw target / modifiers / weather decay computation | [tracking_resolver.gd](engine/subsystems/exploration/tracking_resolver.gd) |
| Daily `tracking_check` event handler | [wilderness_handlers.gd](engine/subsystems/session/handlers/wilderness_handlers.gd) `_handle_tracking_check` |
| Half-speed multiplier | [travel_speed_calculator.gd](engine/subsystems/exploration/travel_speed_calculator.gd) |
| DB schema | [052_tracking_pursuit.sql](db/migrations/052_tracking_pursuit.sql) |

---

## 5. Signals

| Signal | Emitted from | Listeners |
|---|---|---|
| `tracking_session_started(party_id, session)` | caller (game-launch / quest hooks) | NotificationManager toast, future Notebook history panel |
| `tracking_session_ended(party_id, result)` | `_handle_tracking_check` (lost_trail / abandoned) or external callers | NotificationManager toast, history panel |

---

## 6. Deferred (Phase 5.5 / later)

* **Sub-party tracking.** RAW §splitting_up (lair-search adjacent) allows sub-parties to track independently; v1 enforces one session per party.
* **Trail-length weather integration.** Compute the weather decay over each historical hex of the trail rather than the current hex. Requires tracking the trail's hex history, which the data model doesn't carry yet.
* **Hour-cadence option.** A speed-up multiplier on the daily throw or a Judge override that fires hourly could surface in a "fast pursuit" mode for short-range tracking (within-hex hunts).
* **Tracker-skill UI.** v1 picks the first member with Tracking; a picker UI surfaces best-tracker selection when multiple members are proficient.
* **Bonuses for trained creatures** (war-dogs, hunting hawks). RAW catalog references but v1 doesn't query trained_creature stats.
