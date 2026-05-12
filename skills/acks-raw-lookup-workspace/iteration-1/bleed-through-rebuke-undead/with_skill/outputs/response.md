Quick terminology note before the draft: ACKS 1e uses **"turn undead"**, not "rebuke undead." "Rebuke" is the D&D 3.x term for the evil-cleric inverse. ACKS folds both behaviors into a single mechanic: lawful clerics turn (and at higher levels destroy) undead; certain chaotic sects use the same mechanic to *control* undead instead. I've written the GDD section using ACKS terminology throughout.

---

# GDD Section: Cleric Turn Undead

**RAW source:** `rules/acore_core_classes.xml:811-1020`

> <turning>
>   <definition>Call upon divine power to turn away, destroy, or in some chaotic sects control undead.</definition>
>   <rules>
>     <rule>Turning potency depends on cleric level and undead type.</rule>
>     <rule>On the turning table, "-" means the cleric is too low level to affect that undead type.</rule>
>     <rule>"T" means the undead are automatically turned.</rule>
>     <rule>"D" means the undead are automatically destroyed.</rule>
>     <rule>A numbered entry means the player must roll that number or higher on 1d20 to turn the undead.</rule>
>     <rule>On a successful numeric turning attempt, or on a "T" result, roll 2d6; the total equals the total Hit Dice of undead turned.</rule>
>     <rule>On a "D" result, roll 2d6; the total equals the total Hit Dice of undead destroyed.</rule>
>     <rule>At least one undead monster is always turned or destroyed on a successful use of turning, regardless of the 2d6 total.</rule>
>     <rule>There is no daily limit on attempts to turn undead.</rule>
>     <rule>If an attempt to turn undead fails during an encounter, the cleric cannot attempt to turn undead again for the rest of that encounter.</rule>
>     <rule>Turned undead flee for 10 rounds by the best and fastest means available.</rule>
>     <rule>If turned undead cannot flee, they cower, take no actions, and suffer a -2 penalty to AC.</rule>
>     ...
>   </rules>

## 1. Overview

A cleric channels divine power to **turn undead** — driving them to flee, or at sufficient level destroying them outright. Certain chaotic sects invert the same mechanic to *control* undead. The system is a single deterministic resolver keyed on two inputs: **cleric class level** and **undead type**.

Turning is initiated as a combat action (`rules/acore_combat_and_wounds.xml:360` lists "Turn undead" among the in-round actions a combatant may take in place of attacking).

## 2. Inputs

- **Cleric level** (1-14+). Levels 14+ all share the highest column.
- **Undead type** — looked up by row on the turning table (Skeleton, Zombie, Ghoul, Wight, Wraith, Mummy, Spectre, ... up through Infernal at the top of the chart). Monster entries in the catalog flag whether they are "turnable" and at what type (see e.g. `rules/le_monster_catalog_2_summary.xml:430-440` for the skeleton entry).
- **Cleric alignment / sect** — Lawful and Neutral clerics turn or destroy; certain chaotic sects substitute "control" for the same result band.

## 3. Resolution Procedure

The engine resolves a turning attempt in this fixed order. Each step is deterministic; no LLM input.

1. Look up the cell at (undead_type row, cleric_level column) in the turning table.
2. Resolve the cell:
   - **`-`** -> cleric is too low level; the attempt cannot affect this undead type. *(No die roll. No failure flag for the encounter — the attempt simply cannot be made against this type.)*
   - **Numeric (e.g. `10+`)** -> roll **1d20**; success on `result >= cell value`.
   - **`T`** -> automatic turn, no roll.
   - **`D`** -> automatic destruction, no roll.
3. On any success (numeric, T, or D): roll **2d6**. The total is the **Hit Dice of undead affected** in this attempt.
4. **Minimum-one rule:** at least one undead in the affected group is turned (or destroyed) on a success, even if the 2d6 total would not cover its HD. The engine applies the effect to the lowest-HD eligible target first, then continues spending the 2d6 budget on additional targets in HD order until the budget is exhausted.
5. On a numeric failure: the cleric is **locked out of further turning attempts for the remainder of that encounter**. Set a per-encounter flag on the cleric; clear it when the encounter resolver tears down.

There is **no daily limit** on turning attempts — only the per-encounter lockout on failure. The engine should not deduct a "use" from any pool.

## 4. Dice Mechanics Summary

| Cell type | Roll | Effect on success |
|---|---|---|
| `-` | none | Cannot attempt |
| Number `N+` | 1d20 vs. N | Roll 2d6 HD of undead turned |
| `T` | none | Roll 2d6 HD of undead turned |
| `D` | none | Roll 2d6 HD of undead destroyed |

Both d20 and 2d6 use the campaign RNG service; banker's rounding does not apply (integer rolls).

## 5. Level Scaling

Scaling is encoded entirely in the turning table, not as a formula. Each cleric level shifts every undead row leftward by one band, in a regular pattern:

- **`-` -> numeric**: at the level the cleric first becomes able to affect that undead type.
- **Numeric values descend by 3** per cleric level (e.g. Skeleton: 10+ at L1 -> 7+ at L2 -> 4+ at L3).
- **Numeric -> `T`**: when the cell would drop below 4+, it becomes automatic turning.
- **`T` -> `D`**: two levels after first reaching `T`, the result band shifts to automatic destruction.

Concretely from the canonical table (`rules/acore_core_classes.xml:866-961` covers Skeleton through Mummy; the block continues to Spectre, Vampire, Infernal, etc. through line 1020):

- **Skeleton**: 10+/7+/4+/T/T/D/D/D/... (D from L6 onward)
- **Zombie**: 13+/10+/7+/4+/T/T/D/D/... (D from L7)
- **Ghoul**: 16+/13+/10+/7+/4+/T/T/D/... (D from L8)
- **Wight**: 19+/16+/13+/10+/7+/4+/T/T/D/... (D from L9)
- **Wraith**: `-`/19+/16+/13+/10+/7+/4+/T/T/D/... (D from L10)
- **Mummy**: `-`/`-`/19+/16+/13+/10+/7+/4+/T/T/D/... (D from L11)

The engine **loads the table verbatim from a data resource** (e.g. `data/cleric_turning_table.tres`). Do **not** synthesize the values from a formula — the RAW table is the source of truth, and any future Axioms update or sect-specific override should patch the data, not the code.

## 6. Effects on Turned Undead

- Turned undead **flee for 10 rounds** by the best and fastest means available.
- If they cannot flee, they **cower**: no actions, **-2 AC penalty**.
- The turning effect **ends if the turning cleric attacks them in melee**.
- The cleric may attack turned undead with **spells or missile weapons** without breaking the effect; **other characters may attack them in any fashion**.
- **Destroyed** undead are immediately reduced to ash. No body, no loot from the body.

## 7. Chaotic Control Variant

Certain chaotic sects (declared on the cleric's sect descriptor) substitute *control* for *turn* on the same table outcomes:

- A "turn" result -> controlled for **1 turn per cleric level**.
- A "destroy" result -> controlled for **1 day per cleric level**.
- Controlled undead behave as if charmed and obey the cleric as friends.
- If another cleric later turns or destroys them, control ends immediately.
- If control ends naturally (timer elapses), the undead flee as if turned.

The engine implements this as a sect flag (`turning_mode = "turn" | "control"`) on the cleric resource. Resolution shares the same table and 2d6 HD-budget logic; only the post-success effect differs.

## 8. Adjacent Modifiers (out of scope for this section, but flag for cross-system)

- **Blighted / forsaken sinkholes** (`rules/acore_aging_poisons_high-level-start_optional_rules.xml:654-679`) modify turning: in a blighted sinkhole, lawful clerics turn as if **4 class levels lower**; in a forsaken sinkhole they may **not turn undead at all**. The turning resolver must accept a level-modifier input from the encounter environment.
- **Custom-spell wall destructibility** uses "affected as undead by turn undead" as a `x0.75` modifier in spell-creation math (`rules/pc_custom_spell_creation_rules.xml:913`) — relevant to spell research, not to this resolver.
- **Priestess** (`rules/pc_classes_4.xml:474-504`), **Bladedancer** and similar APC classes, and several demihuman classes (`rules/acore_demihuman_classes.xml:429`) all "turn undead as a cleric of equal level" or some fractional level — the resolver should accept an `effective_turning_level` parameter rather than reading the cleric class level directly, so these classes can plug in.

## 9. Open Questions / Flags

- The turning table extends past Mummy to Spectre, Vampire, Infernal, etc. through `rules/acore_core_classes.xml:1020`. Confirm whether L&E or APC adds any further undead types (e.g. liches) that need explicit rows, or whether they map onto Infernal.
- "Infernal includes very powerful undead or unholy beings such as demons and devils" — demons/devils being turnable by clerics is a notable ACKS-vs-D&D divergence worth surfacing in player-facing docs.

---

*Bleed-through check passed: this section uses "turn undead" throughout (ACKS 1e RAW). The user-facing prompt used "rebuke," which is the D&D 3.x term and is not present in the ACKS corpus.*
