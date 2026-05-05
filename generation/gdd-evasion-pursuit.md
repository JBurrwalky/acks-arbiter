# GDD: Wilderness Evasion and Pursuit

**Authority:** SACRED. The Wilderness Evasion table, the 5% minimum escape chance, the 50% catch-up roll, and the daily-retry cycle all come from `acore_adventures_and_encounters.xml` §chases_in_the_wilderness. The reaction-router-driven engagement decision is PROJECT-DESIGNED and lives in `gdd-reaction-router.md`.
**Status:** Phase 5 v1 implemented (2026-05-04).
**Depends on ACKS rules:** `acore_adventures_and_encounters.xml` §reactions, §evasion_and_pursuit, §chases_in_the_wilderness.
**Depends on project GDDs:** `gdd-realtime-scheduler.md` (daily catch-up event), `gdd-reaction-router.md` (drives the routing into combat after catch-up).

---

## 1. Purpose

What happens when one side flees and the other chases in the wilderness:

1. The fleeing side tries to evade (1d20 vs the size-banded table, modified by pursuer ratio).
2. On success → escape, no further pursuit for 24 hours minimum.
3. On failure → pursuit_states row opens; daily 50% catch-up rolls follow until the fleeing side either evades on a retry or is caught.
4. On catch-up → forced hostile combat encounter.

---

## 2. ACKS Rules Constraints (Sacred)

### 2.1 Wilderness Evasion (§chases_in_the_wilderness)

> "Otherwise, the fleeing party must succeed on the Wilderness Evasion table."
> "The larger the pursuing group relative to the fleeing group, the easier it is for the fleeing side to escape."
> **minimum_escape_chance:** 5%

| Evading Party Size | Base Throw | Mod ≤25% pursuers | Mod 26-75% | Mod 76%+ |
|---|---|---|---|---|
| Up to 4   | 11+ | 0 | +4 | +8 |
| 5  to 12  | 14+ | 0 | +3 | +5 |
| 13 to 24  | 16+ | 0 | +3 | +5 |
| 25 or more | 19+ | 0 | +3 | +5 |

The modifier is a **bonus to the throw** (helping the evader), not a penalty to the target. RAW intent ("the larger the pursuing group… the easier it is for the fleeing side") confirms the sign.

### 2.2 5% minimum escape chance

> "minimum_escape_chance: 5%."

v1 models this as: a natural 20 always succeeds, even when modifiers would otherwise fail the throw. 1/20 = 5%. The result dict carries `floor_applied: bool` so a Notebook history can mark these as "lucky escape".

### 2.3 If evasion fails (§if_evasion_fails)

> "The pursuers keep the fleeing party within sight."
> "If the pursuers have greater movement, they have a 50% chance (11+ on d20) to catch up close."
> "If that catch-up roll fails, the fleeing side may attempt to escape again."
> "This cycle repeats daily until either the fleeing side escapes or the pursuers catch them."

Phase 5 fires `pursuit_catchup_check` daily on the EventScheduler:
- If pursuer is faster (`pursuer_speed_advantage > 0`), roll 1d20 vs 11.
- 11+ → caught: pursuit closes, hostile combat begins immediately.
- <11 → falls back: the fleeing side may attempt evasion again on its next turn (player-driven via context-menu action).
- Repeat daily.

### 2.4 Reaction-driven pursuit decision (§evasion_and_pursuit)

> "Whether monsters pursue fleeing characters is determined by a Monster Reaction roll; a result of 2-8 means they pursue."

Phase 5 v1 does NOT auto-roll this — pursuit is opened by the caller (combat retreat handler, future surrender flow). The `behavioral_disposition` field on the originating encounter is the input; pursuit opens for hostile/unfriendly/neutral (matching the 2-8 RAW threshold inverted: Hostile=2, Unfriendly=3-5, Neutral=6-8). Indifferent/friendly do not pursue.

---

## 3. Project-Designed Elaborations

### 3.1 No automatic surprise-escape v1

RAW §automatic_escape_on_surprise lets a surprised fleeing side escape automatically. Phase 5 v1 does NOT wire this — the surprise stage of combat entry isn't currently represented as a discrete pre-combat phase, so the auto-escape isn't yet a hookable point. Tracked as Phase 5.5 polish.

### 3.2 Pursuer-speed advantage as a single integer

RAW says "If the pursuers have greater movement…". v1 reduces this to a `pursuer_speed_advantage: int` field on the pursuit_states row. Any positive value triggers the catch-up roll; the magnitude doesn't scale the d20 target (RAW doesn't either). Set on pursuit open by comparing pursuer movement to party.miles_per_day.

### 3.3 One open pursuit per party

Like tracking sessions, v1 enforces one open pursuit per party. Multi-pursuer scenarios (two factions chasing the same party) collapse to the most-dangerous pursuer.

### 3.4 Caught-up forces hostile combat

RAW says the pursuers "catch them" without specifying combat is forced. Phase 5 v1 forces a hostile encounter (`behavioral_disposition: "hostile"`, `forced_pursuit: true`) on catch-up — the pursuer chose not to give up across multiple days, so a friendly outcome would be inconsistent. Reaction roll is set to 2 (Hostile). Future Opus review may revisit if the always-hostile outcome reads as too punishing.

### 3.5 Judge modifier as parameter

RAW §judge_modifiers allows the Judge to apply situational bonuses ("densely wooded terrain may give a bonus to flee"). v1 carries a `judge_modifier: int` parameter on `EvasionResolver.attempt`; callers pass the appropriate value when terrain or weather warrants. Default 0.

---

## 4. Implementation Map

| Concern | File |
|---|---|
| Wilderness Evasion table + ratio bands + 5% floor | [evasion_resolver.gd](engine/subsystems/exploration/evasion_resolver.gd) |
| Daily 11+ catch-up roll | `EvasionResolver.catch_up` |
| `pursuit_catchup_check` event handler | [wilderness_handlers.gd](engine/subsystems/session/handlers/wilderness_handlers.gd) `_handle_pursuit_catchup_check` |
| pursuit_states open / update / close | [campaign_repository.gd](engine/autoloads/campaign_repository.gd) `open_pursuit_state`, `get_open_pursuit_state`, `update_pursuit_state`, `close_pursuit_state` |
| DB schema | [052_tracking_pursuit.sql](db/migrations/052_tracking_pursuit.sql) |

---

## 5. Signals

| Signal | Emitted from | Listeners |
|---|---|---|
| `evasion_attempted(party_id, result)` | caller of `EvasionResolver.attempt` (combat-retreat handler) | NotificationManager toast, history panel |
| `pursuit_caught_up(party_id, pursuit_id, result)` | `_handle_pursuit_catchup_check` on caught | combat-entry router (forces hostile encounter), NotificationManager (danger toast) |

---

## 6. Deferred (Phase 5.5 / later)

* **Surprise auto-escape.** RAW §automatic_escape_before_combat applies in the dungeon ("if combat has not commenced and the fleeing side has higher movement, it can always escape"); the wilderness counterpart §automatic_escape_on_surprise needs a hookable surprise stage in the encounter pipeline.
* **Combat-retreat → evasion entry.** v1 has `EvasionResolver` ready; the combat retreat code in `morale_resolver.gd` / `combat_finalizer.gd` needs to call it when a side flees and the other intends to pursue.
* **Speed-difference catch-up scaling.** RAW §outcomes (sea evasion section) details speed differences in feet/round; the wilderness rule simplifies to a binary "faster?" check. v1 uses the wilderness rule.
* **Multi-pursuer state.** Allow more than one open pursuit_states row per party for "two warbands chasing each other and the PCs" cases.
* **Reaction-driven pursue decision.** The §evasion_and_pursuit "2-8 means they pursue" check needs a hook in the combat-retreat path.
