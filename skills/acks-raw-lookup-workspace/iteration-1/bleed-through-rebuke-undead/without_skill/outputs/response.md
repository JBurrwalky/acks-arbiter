# GDD: Cleric Turning Undead

**Terminology note (important):** ACKS 1e calls this ability **"turn undead,"** not "rebuke undead." Per `CLAUDE.md`, the project uses "turn undead" everywhere — class methods, signals, action vocabulary, UI strings, database columns. I've written this section accordingly. "Rebuke" is a D&D 3.x/Pathfinder term and the closest in-system concept is the chaotic-sect option to *control* undead, which is described below.

---

## 1. Summary

A cleric may call upon divine power to turn away, destroy, or (for chaotic sects) control undead. Turning is resolved by cross-referencing the cleric's level against the undead's type on the **Turning Undead** table. The result is one of:

- `"-"` — too low level; cannot affect this undead type.
- A **number** (e.g. `10+`) — roll **1d20**; success on that number or higher.
- `"T"` — undead are **automatically turned** (no 1d20 roll).
- `"D"` — undead are **automatically destroyed** (no 1d20 roll).

On any successful turn or destroy result, roll **2d6**. The total is the **Hit Dice of undead affected**. At least one undead is always affected on success, even if the 2d6 total would otherwise be insufficient to cover its HD.

## 2. Undead Types (Table Rows)

In ascending order of difficulty:

`Skeleton -> Zombie -> Ghoul -> Wight -> Wraith -> Mummy -> Spectre -> Vampire -> Infernal`

"Infernal" covers very powerful undead and unholy beings (e.g. demons, devils).

## 3. Level Scaling

The table is indexed by cleric level **1 through 14+**. As cleric level rises, the required 1d20 number drops, then becomes `T`, then `D`. Example progression for **Skeleton**:

| Cleric Level | 1 | 2 | 3 | 4 | 5 | 6+ |
|---|---|---|---|---|---|---|
| Result | 10+ | 7+ | 4+ | T | T | D |

Each undead type is offset roughly two cleric levels harder than the previous type. (Full table values live in `rules/acore_core_classes.xml` under `<table name="turning_undead">` and should be loaded as a `Resource` rather than hardcoded.)

## 4. Resolution Procedure (Engine)

```
1. Look up (undead_type, cleric_level) -> result code.
2. If result is "-": action fails silently (cleric is not exhausted).
3. If result is a number N: roll 1d20; if roll >= N, success = TURN.
   Else: failure -> cleric cannot attempt to turn again this encounter.
4. If result is "T": success = TURN (no 1d20).
5. If result is "D": success = DESTROY (no 1d20).
6. On TURN or DESTROY: roll 2d6 -> hd_affected.
7. Sort target undead group (lowest HD first, ties broken by initiative).
   Apply effect to undead while running_hd_total <= hd_affected.
8. Guarantee: at least one undead is affected on success,
   regardless of 2d6 total.
```

## 5. Effects

- **Turned**: undead flee for **10 rounds** by the best and fastest means available. If they cannot flee, they cower, take no actions, and suffer **-2 AC**.
- **Destroyed**: undead are immediately reduced to ash.
- **Cleric attacks on turned undead in melee end the turning effect.** Spells and missile weapons by the cleric do **not** break it. Allied characters may attack freely in any fashion without breaking it.

## 6. Limits and Restrictions

- **No daily limit** on attempts.
- **One failure per encounter** — on a failed 1d20 turning roll, the cleric cannot attempt turning again in that encounter (a *successful* attempt allows further attempts on other groups).
- The cleric must **uphold the doctrines of the faith and deity** to use turning. A fallen cleric may suffer Judge-imposed penalties or loss of access.
- Turning is invoked as an **other action** in combat (occupies the cleric's action for the round).

## 7. Chaotic-Sect Variant: Control Undead

Some chaotic sects **control** undead in place of turning them:

- On a result that would normally **turn**, undead are instead controlled for **1 turn per cleric level**.
- On a result that would normally **destroy**, undead are instead controlled for **1 day per cleric level**.
- Controlled undead behave as if **charmed** and obey the cleric as friends.
- If a controlling cleric's undead are turned or destroyed by another cleric before control ends, control ends immediately.
- When control ends naturally, the formerly-controlled undead flee as if turned.

## 8. Engine Integration Notes

- **Action vocabulary:** add `turn_undead` (not `rebuke_undead`) to the cleric action set. Chaotic-sect clerics use the same action ID; the control-vs-turn branch is a property of the cleric's sect alignment, resolved inside the action handler.
- **Data:** store the turning table as a `Resource` (`turning_undead_table.tres`) keyed by `undead_type` x `cleric_level`, with values typed as enum `{ IMPOSSIBLE, NUMBER, AUTO_TURN, AUTO_DESTROY }` plus a target number when applicable. Don't hardcode the table in GDScript.
- **Determinism:** all dice (1d20 and 2d6) go through the seeded RNG service. Apply **banker's rounding** if any future modifier introduces fractional levels (none in core rules).
- **Signal:** `undead_turned(cleric_id, target_ids, outcome)` where `outcome` is one of `turned`, `destroyed`, `controlled`, `failed`. The combat narrator subscribes to this signal for retroactive narration.
- **Encounter state:** track a `has_failed_turn_this_encounter` flag on each cleric, cleared at encounter end.
- **Undead type mapping:** monster definitions for undead must carry an `undead_type` tag matching one of the nine table rows. Undead in the monster catalog that don't fit a row exactly (e.g. variant ghasts) should map to the nearest equivalent row, documented in the monster resource.

## 9. Open Questions / Flags

- **Multiple undead groups in one encounter:** rules state "if an attempt fails, cannot attempt again *this encounter*." Need a design call on whether *targeting a different undead type* counts as the same attempt for the per-encounter lockout. Recommend: lockout applies to **any** further turning in the encounter, matching strict text.
- **Mixed-type undead groups:** rules don't explicitly address turning attempts against a mixed group (e.g. zombies + ghouls). Recommend: cleric declares a target type; only undead of that type are eligible; the 2d6 HD pool spends against that type only.
- **Multiple clerics in the party:** each cleric tracks their own per-encounter failure flag.

---

*Source: `rules/acore_core_classes.xml`, `<turning>` subsystem under the Cleric class entry. Table values per `<table name="turning_undead">`. Per Layer 1 document authority these rules are sacred and must be implemented faithfully — flag any apparent errors with code comments, do not modify the XML.*
