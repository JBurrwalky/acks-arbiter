# GDD — Character Aging

**Status:** Draft v1
**Authority Layer:** Generation Design Document (Layer 2). The "ACKS Constraints" sections below are extracted from `rules/acore_aging_poisons_high-level-start_optional_rules.xml` and `rules/pc_aging_tables.xml` and may not be altered.
**Related Rules:**
- `rules/acore_aging_poisons_high-level-start_optional_rules.xml` (aging_and_death section)
- `rules/pc_aging_tables.xml` (starting age extensions for Player's Companion classes)

**Related Systems:**
- Character generation (consumes starting age table)
- EventScheduler (`gdd-realtime-scheduler.md`) — schedules birthday ticks, age category transitions, death-from-old-age saves
- Ability score subsystem (applies aging modifiers, enforces class minimums and floor of 3)
- Saving throw subsystem (Save vs. Death)
- Resurrection / Restore Life and Limb (death-from-old-age cannot be reversed)

---

## 1. Purpose

The aging system models the passage of in-game time for player characters and NPCs. Aging produces three observable effects in play:

1. **Starting age** at character generation, used downstream by histories, social standing, family generation, and (eventually) heirs.
2. **Ability score adjustments** as a character crosses age category thresholds (or as advanced starting ages are computed via cumulative modifiers).
3. **Death from old age**, a Save vs. Death event triggered at race-specific thresholds tied to current Constitution and racial maximum age.

Because ACKS Arbiter is an EventScheduler-first game, aging is implemented as a set of scheduled events. There is no "tick the calendar" loop. When a character is created, the engine schedules the events the character will eventually face; when game time crosses those events, the engine applies effects deterministically.

## 2. ACKS Constraints (from rules — NOT modifiable)

### 2.1 Starting Age by Class

From `acore_aging_poisons_high-level-start_optional_rules.xml` (core classes) and `pc_aging_tables.xml` (Player's Companion classes). Starting age is rolled at character generation.

| Class | Starting Age |
|---|---|
| Assassin | 17+1d6 |
| Bard | 14+1d8 |
| Bladedancer | 17+1d6 |
| Cleric | 17+1d6 |
| Dwarven Craftpriest | 25+2d8 |
| Dwarven Vaultguard | 23+3d4 |
| Elven Nightblade | 75+5d4 |
| Elven Spellsword | 75+5d4 |
| Explorer | 17+1d6 |
| Fighter | 15+1d8 |
| Mage | 17+3d6 |
| Thief | 15+1d8 |
| Anti-Paladin | 17+1d6 |
| Barbarian | 14+1d8 |
| Dwarven Fury | 23+3d4 |
| Dwarven Machinist | 28+2d8 |
| Dwarven Delver | 21+3d4 |
| Elven Courtier | 75+5d4 |
| Elven Enchanter | 80+5d4 |
| Elven Ranger | 70+5d4 |
| Gnomish Trickster | 50+4d4 |
| Mystic | 17+3d6 |
| Nobiran Wonderworker | 17+3d6 |
| Paladin | 17+1d6 |
| Priestess | 17+1d6 |
| Shaman | 17+1d6 |
| Thrassian Gladiator | 14+1d6 |
| Venturer | 17+2d4 |
| Warlock | 17+3d6 |
| Witch | 17+1d6 |
| Zaharan Ruinguard | 17+1d6 |

### 2.2 Age Categories by Race

| Race | Youth | Adult | Middle Aged | Old | Ancient |
|---|---|---|---|---|---|
| Beastman | 12-15 | 16-30 | 31-45 | 46-60 | 61-75 |
| Dwarf | 15-25 | 26-50 | 51-75 | 76-115 | 116-150 |
| Elf | 15-50 | 51-200 | - | - | - |
| Gnome | 15-25 | 26-62 | 63-95 | 96-135 | 136-175 |
| Human | 13-17 | 18-35 | 36-55 | 56-75 | 76-95 |
| Halfling | 14-21 | 22-42 | 43-65 | 66-95 | 96-125 |

**Special rule:** Elves do not progress past Adult. They never receive aging penalties from Middle Aged / Old / Ancient categories.

### 2.3 Ability Score Adjustments by Age

| Age Category | Progressive (applied on entry) | Cumulative (used for advanced starting age) |
|---|---|---|
| Youth | -2 STR, -2 INT, -2 WIS | -2 STR, -2 INT, -2 WIS |
| Adult | +2 STR, +2 INT, +2 WIS | none |
| Middle Aged | -2 STR, -2 DEX, -2 CON | -2 STR, -2 DEX, -2 CON |
| Old | -2 STR, -2 DEX, -2 CON, -2 CHA | -4 STR, -4 DEX, -4 CON, -2 CHA |
| Ancient | -2 STR, -2 DEX, -2 CON, -2 CHA | -6 STR, -6 DEX, -6 CON, -4 CHA |

**Rules:**
- Apply the progressive adjustment when a character crosses into a new age category during play.
- For a character created at an advanced age, the cumulative adjustment for that age category may be used instead (one-time replacement, not in addition to progressive).
- Aging adjustments cannot reduce an ability score below the class minimum.
- Aging adjustments can never reduce an ability score below 3.

### 2.4 Death from Old Age

- **Save type:** Save vs. Death.
- **Timing:** Each required save is made within 1d12 months of reaching the triggering age.
- **Triggers (each save is independent):**
  1. Racial minimum Old age + current Constitution score.
  2. Racial minimum Ancient age + current Constitution score.
  3. Racial maximum age, and each year thereafter.
- **Use current Constitution** after age-based adjustments when computing trigger ages.
- **Restore Life and Limb does not raise** characters who die from old age. Other resurrection effects must check this flag.

---

## 3. Engine Design

### 3.1 Data Model

Characters carry the following aging fields (persisted in the `characters` table; new columns required):

| Column | Type | Notes |
|---|---|---|
| `date_of_birth` | INTEGER (in-game days since campaign epoch) | Set at character creation: `current_date - (starting_age_years * days_per_year) - random_day_offset`. |
| `age_category` | TEXT | One of `youth`, `adult`, `middle_aged`, `old`, `ancient`. Denormalized for fast lookup; recomputed authoritatively from race + DOB. |
| `aging_applied_categories` | TEXT (JSON array) | Categories whose progressive adjustment has already been applied. Prevents double-applying if a character is loaded mid-event. |
| `advanced_start_used_cumulative` | INTEGER (0/1) | If 1, the cumulative adjustment was applied at creation; no progressive adjustments are applied for any prior category. |
| `died_of_old_age` | INTEGER (0/1) | If 1, the character is permanently dead; revival magic short of Wish must reject. |
| `oldage_saves_taken` | TEXT (JSON array) | Each entry: `{trigger, scheduled_day, resolved_day, result}`. |

Race and class minimums are referenced from existing race / class tables (no schema change there beyond reading existing minimum-ability-score columns).

### 3.2 Calendar Assumptions

- Define `DAYS_PER_YEAR = 365` as a constant in the calendar module. (If the campaign calendar diverges later, this becomes a `CalendarService` lookup.) [PROVISIONAL]
- Age in years is computed as `floor((current_date - date_of_birth) / DAYS_PER_YEAR)`.
- "Within 1d12 months" is implemented as `roll(1, 12) * 30` days from the trigger date. (Months treated as 30 days for scheduling. Refine if the calendar GDD specifies otherwise.) [PROVISIONAL]

### 3.3 EventScheduler Events

All aging activity is expressed as scheduled events. The aging subsystem registers the following event types:

| Event | When Scheduled | When Fired | Effect |
|---|---|---|---|
| `aging.category_transition` | At character creation, one event per future category boundary for the character's race. | When game time reaches the start of the new category's age range, on the character's birthday (DOB + N years). | Update `age_category`. Apply the progressive ability adjustment if the new category has one, respecting class minimums and the floor of 3. Append the category to `aging_applied_categories`. Emit `character_aged(character_id, new_category, applied_adjustments)`. If the new category is Old or Ancient, schedule the corresponding death save event. |
| `aging.death_save` | When a character enters Old or Ancient, and when a character first reaches the racial maximum age. The scheduled day is `trigger_day + roll(1d12 months in days)`. | When game time reaches the scheduled day. | Roll Save vs. Death with the character's current bonuses. On failure, set `died_of_old_age = 1`, emit `character_died_of_old_age(character_id, trigger)`. On success, record the result. For the "max age" trigger, schedule the next yearly save at `trigger_day + 365 + roll(1d12 months)`. |
| `aging.birthday` (optional) | At character creation, recurring annually. | On each DOB anniversary. | Used to fire narrative beats, family events, downtime hooks. **Not required** for the mechanical aging system but reserved here so it isn't reinvented elsewhere. |

**Determinism:** All dice rolls (the 1d12 months offset, the saving throw) go through the central RNG service with seeded streams per character. This keeps aging reproducible on replay.

### 3.4 Trigger Age Computation

When entering Old:
1. Compute `old_save_age = race.old_min_age + character.constitution`.
2. Convert to a day: `dob + old_save_age * DAYS_PER_YEAR`.
3. Add a random offset: `offset = roll(1, 12) * 30`.
4. Schedule `aging.death_save{trigger="old"}` at that day.

When entering Ancient: same procedure with `race.ancient_min_age + constitution`.

When reaching racial maximum age (race.ancient_max_age + 1, i.e., the first year past the listed Ancient maximum):
1. Compute trigger day for year T.
2. Add `roll(1, 12) * 30` days offset.
3. Schedule `aging.death_save{trigger="max+N"}`.
4. On passing, immediately schedule the next year's save.

**Constitution change handling:** If Constitution changes after entering Old or Ancient (e.g., from magic items, wishes, or further aging), the *already-scheduled* save is not rescheduled. The trigger fires at the originally computed date. This is consistent with the rule that the save is made within 1d12 months of *reaching* the triggering age. Later Constitution changes affect the *roll bonus* (via Con-modified save tables) but not the trigger timing.

### 3.5 Elves

Elves skip Middle Aged / Old / Ancient entirely. At character creation:
- Schedule only the Youth->Adult `category_transition` event (if starting age is Youth).
- Schedule the racial-maximum death save event for `dob + (race.ancient_max_age + 1) * DAYS_PER_YEAR + roll(1d12 months)`. (Elves still die of natural causes at racial maximum, per the rule's third trigger which references racial maximum and is not category-dependent.)
- Do NOT schedule Old or Ancient death saves; the elven row has no Old or Ancient minimum age.

### 3.6 Advanced Starting Age

When a character is created at an age that places them past Adult, the player (or NPC generator) may opt to apply the cumulative adjustment for the current category instead of running progressive adjustments retroactively. Implementation:

1. At creation, compute the character's starting age category from race and rolled (or specified) age.
2. If the category is Middle Aged, Old, or Ancient AND cumulative mode is selected:
   - Apply the cumulative adjustment row for that category.
   - Set `advanced_start_used_cumulative = 1`.
   - Populate `aging_applied_categories` with every category up to and including the current one (so the system never re-applies progressive deltas for those).
3. If progressive mode is selected (the default for player-built characters working up through play), apply each progressive row in sequence for every category already passed, respecting the class-minimum and floor-of-3 rules at each step. This produces a different end state than cumulative mode because ordering matters for clamping.

The ACKS rule reads "may be used instead," so the choice is exposed to the player at character creation when applicable.

### 3.7 Ability Score Clamping

When applying an aging adjustment delta to an ability score:
1. Compute `new_value = current_value + delta`.
2. Look up the class minimum for that ability (from the class definition).
3. Set `new_value = max(new_value, class_minimum, 3)`.
4. If clamping occurred, log it (so it's auditable in the character's history).

A character cannot lose class membership through aging — clamping at class minimum guarantees the character still qualifies for their class. If a future rule (e.g., disease, drain) brings a score below class minimum, that's handled by the relevant system, not aging.

### 3.8 Death from Old Age — Resurrection Interaction

The `died_of_old_age` flag must be consulted by any revival code path. The resurrection / Restore Life and Limb spell handler MUST check this flag and refuse if set. The flag is permanent; no in-game effect clears it. (A future Wish-like effect, if added, would need an explicit override path documented there.)

### 3.9 NPC Handling

NPCs (henchmen, hirelings, domain personalities) use the same scheduling system. Because they are persisted in the same characters table, the same event types fire for them. This produces emergent effects: a long-serving henchman can die of old age between sessions, a famous mage can age out of relevance, etc. For NPCs not currently loaded into a scene, the event still resolves at the scheduled time; the engine simply does not produce UI for the transition unless the NPC is relevant to the player's view.

## 4. Interfaces

### 4.1 Public Signals

```gdscript
signal character_aged(character_id: int, new_category: String, applied_adjustments: Dictionary)
# applied_adjustments example: { "STR": -2, "DEX": -2, "CON": -2 }
# Adjustments shown are the actual deltas applied AFTER clamping.

signal character_died_of_old_age(character_id: int, trigger: String)
# trigger is one of "old", "ancient", "max+0", "max+1", ...
```

### 4.2 Service API (sketch)

```gdscript
# AgingService (NOT an autoload — owned by CharacterRepository or similar)
func compute_starting_age(class_id: String, rng: RNGStream) -> int
func compute_age_category(race_id: String, age_years: int) -> String
func schedule_aging_events(character_id: int) -> void   # called once at creation
func apply_progressive_adjustment(character_id: int, category: String) -> Dictionary
func apply_cumulative_adjustment(character_id: int, category: String) -> Dictionary
func handle_category_transition_event(event: ScheduledEvent) -> void
func handle_death_save_event(event: ScheduledEvent) -> void
```

### 4.3 Database Migration

A new migration adds the columns listed in 3.1 to the `characters` table. No data destructive operations. Existing characters get:
- `date_of_birth` backfilled from their stored age field if present, else flagged as missing and resolved at next load.
- `age_category` recomputed.
- `aging_applied_categories` defaulted to all categories at-or-below the current category (assumed already applied for legacy characters).
- `died_of_old_age` defaulted to 0.
- `oldage_saves_taken` defaulted to `[]`.

## 5. Testing Strategy

Unit tests against the mock RNG (deterministic streams):

1. **Starting age generator** — for each class, produce 1000 rolls; verify the range matches the formula bounds.
2. **Category boundaries** — for each race, verify a character at the exact youth->adult, adult->middle_aged, etc. boundary day produces a `category_transition` event and applies the correct progressive deltas.
3. **Elf exception** — verify elves never schedule middle_aged/old/ancient transitions but do schedule a max-age death save.
4. **Cumulative vs. progressive** — verify a character created at Old via cumulative receives `-4 STR, -4 DEX, -4 CON, -2 CHA` and that one created via progressive receives the same totals when no clamping occurs; verify they diverge when clamping is involved (e.g., a 10 STR character clamping at class minimum 9 in Middle Aged).
5. **Class minimum clamping** — verify aging never drops an ability score below the class minimum or below 3.
6. **Death save scheduling** — for a Human Fighter with Con 12 entering Old: verify `aging.death_save` is scheduled at (DOB + (56 + 12) * 365) + offset_days, with offset in [30, 360].
7. **Death save resolution** — with seeded RNG forcing failure, verify `died_of_old_age = 1` and `character_died_of_old_age` signal emitted.
8. **Resurrection refusal** — verify Restore Life and Limb refuses a character flagged died_of_old_age.
9. **Yearly post-max saves** — verify that passing a max-age save schedules the next year's save with a fresh 1d12 offset.
10. **Constitution change after Old** — verify a Con buff applied after the Old save was scheduled does not reschedule it.

Integration test with the EventScheduler:
- Create a 50-year-old human fighter, advance simulated time 50 years, verify the character passes Middle Aged at age 36, Old at 56, Ancient at 76, faces a death save at 56+Con, and dies or survives deterministically based on seeded rolls.

## 6. Open Questions

- **Calendar granularity:** Does the campaign calendar use 12 months of 30 days, or something else? The 30-day-month approximation in 3.2 may need to be replaced with a `CalendarService.months_to_days` call. Flag for design review.
- **Birthday narrative beats:** Should `aging.birthday` events fire LLM-narrated vignettes by default, or only at category transitions? Recommend: category transitions only, with birthday hooks reserved for henchmen and domain personalities.
- **Beastmen as PCs:** The age category table includes Beastmen, but no Beastman starting-age class is defined in the loaded rules. Confirm whether Beastman is a PC race for ACKS Arbiter scope or NPC-only.
- **Mid-life Constitution changes interacting with the "racial minimum + Con" trigger:** The current design uses the Con at the time the character enters Old. If a player drinks a potion of longevity after that point, the rule does not say the trigger reschedules. Confirm interpretation.
- **Anti-aging magic** (e.g., potion of longevity, alter time): Not in the loaded rule extracts. Out of scope for this GDD; add to a follow-up when those items are scheduled for implementation.

## 7. Implementation Order

1. Migration: add aging columns to `characters` table.
2. AgingService skeleton with `compute_starting_age` and `compute_age_category`.
3. Wire starting-age computation into character creation.
4. Implement progressive and cumulative adjustment application with clamping.
5. Define and register `aging.category_transition` and `aging.death_save` event handlers with EventScheduler.
6. Schedule events at character creation for all currently-loaded characters (and via migration for legacy ones).
7. Hook `died_of_old_age` flag into resurrection paths.
8. Tests (Section 5).
9. UI surface: character sheet displays current age and category; transition events surface a notification.
