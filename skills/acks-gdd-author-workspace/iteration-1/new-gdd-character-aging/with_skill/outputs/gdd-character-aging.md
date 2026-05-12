# GDD: Character Aging

**Document type:** Game Design Document (RAW-implementation with thin project layer)
**Authority:** PROJECT-DESIGNED — scheduling, persistence, and UI surfaces are engineering decisions. §2 ACKS Constraints come from the books and may NOT be changed.
**Status:** Draft
**Depends on ACKS rules:** [`rules/acore_aging_poisons_high-level-start_optional_rules.xml:2-143`](../rules/acore_aging_poisons_high-level-start_optional_rules.xml) (starting age table for ACore classes, race age categories, ability-score adjustments by age, aging rules, death-from-old-age procedure); [`rules/pc_aging_tables.xml:1-84`](../rules/pc_aging_tables.xml) (starting age table for APC classes)
**Depends on project GDDs:** [`gdd-realtime-scheduler.md`](gdd-realtime-scheduler.md) (`EventScheduler` is the substrate for queued age-bracket transitions and death-from-old-age checks); [`gdd-calendar-seasons.md`](gdd-calendar-seasons.md) (calendar gives the "1d12 months" timing window a deterministic in-game date); [`gdd-character-tab.md`](gdd-character-tab.md) (Identity sub-section already lists `Age`; this GDD defines what gets written there and what side effects firing an age transition produces)
**Modifiable by Claude Code:** Yes within constraints. §2 ACKS Constraints are RAW and may not be changed. §3 Project Decisions (event scheduling, persistence schema, notification surfaces) are engineering decisions.
**Last updated:** 2026-05-12

---

## 1. Purpose

Define how the game tracks a character's age, applies ACKS 1e age-bracket ability-score adjustments at the correct in-game moment, and resolves the death-from-old-age saving-throw procedure. The system is owned by the unified character model (per design brief §10.1, which already lists `aging` as a character-record section) and integrated with the EventScheduler so transitions fire on the right in-game date rather than on a polled tick or a "next downtime" boundary.

This GDD covers PCs, henchmen, and NPCs uniformly — there is one aging rule set in ACKS 1e and one implementation. It deliberately does *not* cover NPC age generation at world-init (handled by the NPC generation pipeline) beyond providing the starting-age dice tables for classed NPCs.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed.

### 2.1 Starting age by class

Roll on the appropriate starting-age table at character creation. The result is the character's age at level 1.

**ACore classes** (`rules/acore_aging_poisons_high-level-start_optional_rules.xml:3-52`):

| Class | Starting age |
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

**APC classes** (`rules/pc_aging_tables.xml:7-82`):

| Class | Starting age |
|---|---|
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

### 2.2 Age categories by race

The bracket a character occupies at any given age, by race (`rules/acore_aging_poisons_high-level-start_optional_rules.xml:54-98`):

| Race | Youth | Adult | Middle Aged | Old | Ancient |
|---|---|---|---|---|---|
| Beastman | 12–15 | 16–30 | 31–45 | 46–60 | 61–75 |
| Dwarf | 15–25 | 26–50 | 51–75 | 76–115 | 116–150 |
| Elf | 15–50 | 51–200 | — | — | — |
| Gnome | 15–25 | 26–62 | 63–95 | 96–135 | 136–175 |
| Halfling | 14–21 | 22–42 | 43–65 | 66–95 | 96–125 |
| Human | 13–17 | 18–35 | 36–55 | 56–75 | 76–95 |

**Special rule (`:75`):** *Elves do not progress past Adult.* They never enter Middle Aged, Old, or Ancient brackets and the ability-score adjustments for those brackets never apply to them. They also never trigger death-from-old-age checks (see §2.4 below — those triggers reference racial Old/Ancient ages which Elves do not have).

### 2.3 Ability-score adjustments by age

When a character enters a new age category, apply the **progressive** column. The **cumulative** column is the total adjustment from the character's natural starting (Adult) baseline and is used when generating a character directly at an advanced age (`rules/acore_aging_poisons_high-level-start_optional_rules.xml:100-128`).

| Age category | Progressive (applied on entry) | Cumulative (used at advanced-age generation) |
|---|---|---|
| Youth | -2 STR, -2 INT, -2 WIS | -2 STR, -2 INT, -2 WIS |
| Adult | +2 STR, +2 INT, +2 WIS | No adjustments |
| Middle Aged | -2 STR, -2 DEX, -2 CON | -2 STR, -2 DEX, -2 CON |
| Old | -2 STR, -2 DEX, -2 CON, -2 CHA | -4 STR, -4 DEX, -4 CON, -2 CHA |
| Ancient | -2 STR, -2 DEX, -2 CON, -2 CHA | -6 STR, -6 DEX, -6 CON, -4 CHA |

Additional rules from `rules/acore_aging_poisons_high-level-start_optional_rules.xml:123-128`:

- Apply the progressive adjustment **at each new age category** (i.e., on transition).
- For a character generated *at* an advanced age, the **cumulative** adjustment for the current age category may be used instead of summing successive progressive transitions.
- Ability-score adjustments from aging cannot reduce a score **below a class minimum** (i.e., a Fighter cannot drop below the Fighter STR minimum from aging — the score floors at the minimum).
- Ability-score adjustments from aging can never reduce a score **below 3**.

### 2.4 Death from old age

Procedure from `rules/acore_aging_poisons_high-level-start_optional_rules.xml:130-142`:

- **Save type:** Save vs. Death (the "Poison & Death" save row).
- **Timing of each check:** Each required save is made within **1d12 months** of reaching the triggering age. (Each trigger rolls its own 1d12-month offset.)
- **Triggering ages:**
  1. Racial minimum **Old** age + current Constitution score.
  2. Racial minimum **Ancient** age + current Constitution score.
  3. Racial maximum listed age (the upper end of the Ancient bracket), and **each year thereafter**.
- **Constitution lookup rule:** Use the character's **current** Constitution *after* age-based adjustments when computing the trigger age. (This means the trigger age is computed live each time the character ages, not frozen at character creation.)
- **Permanent on failure:** *Restore Life and Limb does not raise characters who die from old age.* This is one of the few "real" deaths in ACKS — no mortal-wounds-table reprieve, no resurrection.

---

## 3. Project Decisions

### 3.1 Lifecycle pipeline

```
1. CHARACTER CREATION
   → roll starting age from class table (§2.1)
   → store birth_round (in elapsed game-time rounds, computed backward
     from current campaign time and the rolled age in years)
   → classify into starting age bracket (§2.2) and apply any starting
     bracket adjustments (typically none — most starting ages are
     within the Adult bracket; advanced-age generation uses cumulative
     adjustments per §2.3)
   → schedule next bracket transition event (§3.4)
   → if already in Old or Ancient bracket at creation, schedule first
     death-from-old-age check (§3.5)

2. EVENT-SCHEDULED BRACKET TRANSITION FIRES (party clock reaches
   character's next-bracket-entry timestamp)
   → apply progressive adjustment for new bracket (§2.3) with the
     floor rules (class minimum, hard floor of 3)
   → recompute derived combat stats that depend on ability modifiers
     (attack throws, saves, AC, HP cap, encumbrance, etc.)
   → recompute death-from-old-age trigger ages using CURRENT Con
   → schedule next bracket transition (if any remain — Adult→Middle
     Aged, Middle Aged→Old, Old→Ancient; Elves stop after Adult)
   → schedule death-from-old-age trigger(s) newly applicable from
     the new Con value
   → emit `character_aged` signal with from/to bracket and stat delta
   → auto-pause: NO. Aging transitions are notification-only; the
     player sees a unified-log entry but is not interrupted.

3. EVENT-SCHEDULED DEATH-FROM-OLD-AGE TRIGGER FIRES
   → roll the save vs. Death
   → on success: schedule no follow-up unless this is the
     "each year thereafter" trigger (§2.4 trigger 3), in which case
     schedule the next annual check 1d12 months out
   → on failure: kill the character. Set a death flag that prevents
     Restore Life and Limb from succeeding. Emit `character_died`
     with cause = "old_age".
   → auto-pause: YES if the character is a PC or henchman. NPCs
     dying off-screen log silently.
```

### 3.2 Time substrate

Per [`gdd-realtime-scheduler.md`](gdd-realtime-scheduler.md), all in-game time is expressed in elapsed rounds on a per-party clock. One ACKS year is fixed by [`gdd-calendar-seasons.md`](gdd-calendar-seasons.md) at 364 days = 13 months × 28 days. Conversions:

- **1 day** = 1440 minutes = 14400 rounds (10-second rounds; check the constant used by `Timekeeping` if this is wrong — the actual round length is set there, not here).
- **1 month** = 28 days = 403,200 rounds (with the assumption above).
- **1 year** = 364 days = 5,241,600 rounds.

The aging system stores `birth_round` and computes `current_age_years` as `(now - birth_round) / rounds_per_year` with banker's rounding for any fractional comparison. All scheduled aging events store their `fire_time` as absolute round counts, computed from the calendar.

> **Architectural note:** `birth_round` is stored as a signed integer because campaign start at game time 0 is normal, and most characters were born before then (negative `birth_round`). If `Timekeeping` only stores unsigned timestamps, this needs revisiting.

### 3.3 Per-party clock vs. shared character

A henchman might join Party A, leave, and join Party B. Each party has its own clock. The character's age advances with **whichever party they are currently traveling with**. When a character is detached from a party (e.g., guarding a stronghold, hired as a specialist not on adventure), they advance with the **domain/site clock** they are bound to, falling back to the campaign reference clock for characters with no current owner.

> **Architectural concern:** This is the same "which clock does this character age on" question that domain ticks face. The answer should match whatever `gdd-realtime-scheduler.md` says about per-character timekeeping when characters are not in a party. Flagged for Jedidiah's review — the realtime scheduler GDD describes per-*party* clocks but does not explicitly say how an unparty'd character's clock advances.

### 3.4 Bracket-transition event scheduling

A character's *next* bracket entry is always known deterministically from race + current age. The scheduler holds one `ScheduledEvent` per character of type `character_aging_transition`:

- **`event_type`:** `"character_aging_transition"`
- **`owner_id`:** `character_id`
- **`data`:** `{ "from_bracket": "Adult", "to_bracket": "Middle Aged" }`
- **`priority`:** `PRIORITY_ENVIRONMENTAL = 0` — aging is a background world-tick, not an action arrival.
- **`fire_time`:** `birth_round + (start_age_of_to_bracket × rounds_per_year)`.

On firing, the handler applies the progressive adjustment, then schedules the *next* transition (if any) and any newly-applicable death-from-old-age checks. Elves get no follow-up scheduled after entry to Adult.

### 3.5 Death-from-old-age event scheduling

Three potential `character_old_age_death_check` events per character, scheduled lazily as they become applicable. Each rolls its own 1d12-month offset at scheduling time:

| Trigger | Computed trigger age | When scheduled |
|---|---|---|
| First check | `racial_old_minimum + current_CON` | Scheduled when the character enters Middle Aged or later (whichever bracket entry first crosses or matches the trigger age). Re-scheduled if CON changes the trigger before it fires. |
| Second check | `racial_ancient_minimum + current_CON` | Scheduled when first check resolves (success) and the trigger age is reached or exceeded; otherwise scheduled at the bracket transition that crosses it. |
| Recurring annual | each year after racial maximum | Scheduled annually after the second check, with a fresh 1d12-month offset per scheduling. |

**Event payload:**

```
event_type: "character_old_age_death_check"
owner_id:   character_id
data: {
  "trigger_index": 0 | 1 | 2,    // which trigger row from §2.4
  "trigger_age_years": int,      // for log readability
}
priority:   PRIORITY_CONSEQUENCE = 30  // higher than ordinary aging
```

The fire_time is rolled at schedule time as `birth_round + (trigger_age × rounds_per_year) + (1d12 × rounds_per_month)` — the 1d12-month offset is randomized once and locked into the event, not re-rolled on resolution.

#### 3.5.1 CON-change reschedule

The death-from-old-age trigger ages are a function of *current* CON (per §2.4 special rule). When CON changes for any reason — aging adjustment, magic, permanent loss — the open `character_old_age_death_check` events for that character must be **cancelled and rescheduled** with the new trigger age. The handler for `character_aged` does this for the aging case; the character-stat-change pathway (yet to be designed) needs to do the same for non-aging CON changes.

> **Open question — flagged below:** is there a single "character stat changed" signal we can subscribe to? If not, this reschedule needs to live in every code path that mutates CON.

### 3.6 Advanced-age character generation

Per `:125`, characters generated at an advanced age may use the **cumulative** column (§2.3) rather than walking through each bracket's progressive adjustment. This affects high-level-start characters (per the same XML's `playing_with_advanced_characters` block at lines 724+) and any NPC generation that pre-ages an NPC. The character creator therefore needs both code paths:

- **Roll-up path:** Start at level 1 with the rolled starting age, walk forward through bracket transitions as game time elapses (the normal path).
- **Drop-in path:** Generated at age N. Look up the bracket, apply the cumulative adjustment for that bracket only. Schedule the next bracket transition from N forward. Schedule any death-from-old-age check already applicable.

Both paths converge on the same character state for any given current age. They differ only in computational shortcut.

### 3.7 Ability-score floor logic

Per `:126-127`:

```
func apply_aging_adjustment(score: int, delta: int, class_min: int) -> int:
    # banker's rounding not relevant here (integer arithmetic),
    # but the floors are:
    var adjusted := score + delta
    var floor_value := max(3, class_min)
    return max(adjusted, floor_value)
```

`class_min` defaults to 3 for races/classes without an explicit minimum. The floor is per-score — STR floors at the Fighter STR minimum for a Fighter, but DEX floors at 3 because no class has a DEX minimum above 3. The character-creation rules carry the per-class minimums; this GDD assumes they are accessible to the aging handler.

### 3.8 Notification surface

- **`character_aged`** (signal): emitted on bracket transition. Listened to by the unified log panel ([`gdd-unified-log-panel.md`](gdd-unified-log-panel.md)) for a "Garrick has entered Old Age" entry, and by the character tab ([`gdd-character-tab.md`](gdd-character-tab.md)) for live UI refresh.
- **`character_died`** with `cause: "old_age"` (signal): emitted on failed death-from-old-age save. Same listeners; also triggers any party-leadership / domain-succession workflows that key off of `character_died`.
- **Auto-pause behavior:** bracket transitions do *not* auto-pause. Death-from-old-age failures *do* auto-pause for PCs and henchmen, per the SchedulerLoop's pause-on-attention pattern.

---

## 4. Data Model

Two additions to the character record (per design brief §10.1's `aging` section), and one new event row in the scheduled-event payload vocabulary.

### 4.1 Character record (additions to `characters` table)

| Column | Type | Notes |
|---|---|---|
| `birth_round` | INTEGER (signed) | Absolute round count. Negative for characters born before campaign start. |
| `starting_age_years` | INTEGER | The rolled value from §2.1 — stored for audit/log, not used at runtime. |
| `current_age_bracket` | TEXT | `"Youth"`, `"Adult"`, `"Middle Aged"`, `"Old"`, `"Ancient"`. Denormalized from race + (now - birth_round); kept in sync by the aging handler so UI doesn't recompute. |
| `aged_stat_adjustments` | JSON | Cumulative aging-derived delta on each ability score. Subtracted from `score_natural` to show the unmodified score in the character sheet. Format: `{"STR": -2, "DEX": 0, ...}`. |
| `next_aging_event_id` | TEXT NULLABLE | The currently-scheduled `character_aging_transition` event_id for this character, for fast cancel/reschedule on CON change or character deletion. |
| `pending_death_check_event_ids` | JSON | Array of event_ids for the up-to-N pending `character_old_age_death_check` events. |
| `died_of_old_age` | BOOLEAN | Set true on failed death-from-old-age save. Blocks Restore Life and Limb success. |

### 4.2 Scheduled event types (additions to action vocabulary)

```
character_aging_transition
  data: { from_bracket: String, to_bracket: String }
  priority: PRIORITY_ENVIRONMENTAL (0)

character_old_age_death_check
  data: { trigger_index: int, trigger_age_years: int }
  priority: PRIORITY_CONSEQUENCE (30)
```

Both register with `EventHandlerRegistry` at session-runner startup, are persisted/restored normally with the rest of the queue, and serialize/deserialize via the standard `ScheduledEvent.to_dict()` / `from_dict()` round-trip.

### 4.3 Migration

New columns on `characters` require a sequential, non-destructive migration. Existing characters (test fixtures, in-progress saves) need:

- `birth_round` populated from existing `age_at_creation` field (if it exists) + current round.
- `starting_age_years` populated from `age_at_creation`.
- `current_age_bracket` populated by classifying the current computed age against §2.2.
- `aged_stat_adjustments` populated as the zero vector unless the character was generated at advanced age (in which case the cumulative adjustment is reconstructable but probably not auditable post-hoc — flag for review).
- `next_aging_event_id` and `pending_death_check_event_ids` populated by running the bracket-transition + death-check scheduling logic once for each existing character at migration time.

---

## 5. UI Touchpoints

- **Character tab Identity section** ([`gdd-character-tab.md`](gdd-character-tab.md) §93-94 already lists `Age`): show `age_years` and `bracket` (e.g., "47 (Middle Aged)"). On hover, show the in-game date of the next bracket transition (and, if applicable, the next scheduled death-from-old-age check window).
- **Unified log panel** ([`gdd-unified-log-panel.md`](gdd-unified-log-panel.md)): receive `character_aged` and `character_died` signals; format as world-tick log lines.
- **Auto-pause prompt** (combat/dungeon UI): when a PC or henchman fails a death-from-old-age save, auto-pause and surface the death confirmation. This shares the existing PC-death modal path; no new UI surface required.

---

## 6. Implementation Notes

- **Banker's rounding** applies to any fractional-year arithmetic (e.g., computing current age from `(now - birth_round)`). The age in years is normally an integer because `birth_round` is set to a whole-year boundary at character creation, but day-of-year edge cases at bracket transitions need banker's rounding. Use the project's standard `MathUtil.round_half_to_even()`.
- **Determinism:** the 1d12-month offset for each death-from-old-age check must be rolled via `DiceSystem` with a seeded RNG tied to the character_id and trigger_index so save/load determinism holds. The same goes for the starting-age roll at character creation.
- **Elf special case:** the bracket-transition scheduling code must check the race-specific "stops at Adult" rule explicitly. A naive walk through age brackets will try to schedule Elf transitions to Middle Aged at age 201, which is wrong.
- **No autoload needed.** Aging logic lives in a subsystem module (e.g., `engine/subsystems/character/aging_system.gd`) that the event handlers call. It does not need a global singleton — the EventScheduler is the only persistent state, and character records hold the per-entity state.

---

## 7. Open Questions / Architectural Concerns

- **Per-character clock when detached from a party.** §3.3 above. The realtime-scheduler GDD describes per-party clocks but is silent on how an unparty'd character (e.g., a specialist guarding a stronghold) advances time for purposes of aging. Recommend a clarification pass on `gdd-realtime-scheduler.md` before implementing.
- **CON-change reschedule signal.** §3.5.1 above. The death-from-old-age trigger age depends on current CON, which means any CON change must cancel and reschedule the open check. We need either (a) a unified `character_stat_changed` signal that aging can subscribe to, or (b) explicit reschedule calls in every code path that mutates CON. Recommend (a); flag for the character-data-flow design pass.
- **Advanced-age generation and cumulative reconstruction.** §4.3 above. For existing save data at migration time, we cannot perfectly reconstruct whether an advanced-age character used the cumulative or progressive path. The conservative default is to treat the character's *current* ability scores as ground truth and back-fill `aged_stat_adjustments` as the delta from the racial/class natural baseline. Confirm this is acceptable.
- **Death-from-old-age save target.** ACKS 1e save vs. Death is the "Poison & Death" save row; the actual target number is per-class-per-level from the class progression tables (not in either aging XML). Confirm that the character record exposes a `save_vs_death_target` value that the aging handler can read at trigger time, or specify the lookup interface here.
- **NPC aging at world-init.** The setting generator pre-ages many NPCs (e.g., a 60-year-old domain ruler). This GDD assumes the drop-in path (§3.6) is used. Confirm with the NPC-generation pipeline that this is the contract.
- **Elven bracket terminology.** ACKS 1e gives Elves only Youth and Adult; there is no "elven equivalent" to Old or Ancient. The XML's special_rule (`:75`) is clear that they do not progress past Adult, but it is silent on whether elves die naturally at any age. Confirmed RAW: ACKS 1e does not specify a maximum elven age. Elves in this implementation therefore do not trigger death-from-old-age checks. Flag if Jedidiah wants a project-designed elven mortality model — that would be a new GDD, not an extension of this one.
- **Beastman classes.** No class is explicitly Beastman in the starting-age tables, but Beastmen appear in the race age-categories table (`:55-61`). If/when Beastman-classed characters are added (presumably via L&E monster characteristics for player-monster races), the starting-age table needs an entry. RAW does not currently provide one — design gap, not bleed-through.
- **Banker's rounding on the "10% chance per year" / 1d12-month timing.** §2.4 specifies the 1d12-month window for *each* save. We are rolling this once at schedule time; the alternative is to roll fresh at trigger time. Reading the RAW (`:132`) — *"Each required save must be made within 1d12 months of reaching the triggering age"* — supports either reading, but a once-rolled offset is more deterministic for save/load and matches the project's general "schedule then resolve" pattern. Flag for review.
