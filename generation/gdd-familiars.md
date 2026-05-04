# GDD: Familiars

**Status:** Stage 1 — data + persistence layer landed. Stage 2 (runtime mechanics) and Stage 3 (UI integration) pending.

## 1. Purpose

Implements the `Familiar` proficiency from ACKS Core ([rules/acore_proficiencies_rules_and_catalog.xml:688-700](../rules/acore_proficiencies_rules_and_catalog.xml)). A character with this proficiency gains a magical animal companion bonded to them. The companion takes the **form** of a real animal (and thereby its body — AC, movement, attacks, special abilities) but its core stats — HD, max HP, Intelligence, proficiency count — are **derived from the master**.

ACKS provides only two stat blocks for ≤1 HD animals suitable as familiar forms (Bat, Hawk). The book's rule is "appropriate to alignment and powers" — i.e. expects the Judge to author the rest. This GDD authors the missing forms as project content.

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **HD = ½ master's HD** (banker's rounding).
- **Max HP = ½ master's max HP** (banker's rounding).
- **INT = master's INT.**
- **Proficiency count** equal to master's general + class proficiency count, chosen from master's class proficiency list.
- Familiar **always understands languages master speaks**; master understands familiar's "speech."
- Familiar is **utterly loyal** — never rolls morale.
- **+1 to all saving throws** for the master while the familiar is within 30 feet.
- If the familiar is **slain**, master must save vs Death or take damage equal to familiar's max HP.
- **No replacement** until master gains a level.

## 3. Project Decisions

### 3.1 Form catalog scope

The form catalog at `data/familiars/familiar_form_catalog.json` covers seven forms, two from canon and five project-authored:

| form_key       | Source            | AC | Cosmetic variants                | Form notable abilities                       |
|----------------|-------------------|----|----------------------------------|----------------------------------------------|
| `bat`          | Canon (rules)     | 3  | Bat                              | Echolocation, fly                            |
| `hawk`         | Canon (catalog)   | 1  | Hawk, Raven, Eagle, Falcon, Owl  | Dive (×2 dmg), fly                           |
| `cat`          | Project-authored  | 3  | Cat                              | Silent move (+4 surprise), low-light vision  |
| `rat`          | Project-authored  | 3  | Rat                              | Squeeze through 1" gaps, climb               |
| `snake_small`  | Project-authored  | 3  | Garter, Adder, Viperling         | +4 surprise hidden in undergrowth            |
| `toad`         | Project-authored  | 3  | Toad, Frog                       | Burrow soft ground, swim                     |
| `weasel`       | Project-authored  | 3  | Weasel, Ferret, Stoat            | Cling on hit (auto-hit until wrestled off)   |

A form's "printed HD" is **not** used by a familiar — its HD is master-derived per §3.3. The form contributes only AC, movement, attack routines (count + dice), and special abilities.

**Authoring rules for project-authored forms:**
- AC may not exceed 3 (the bat's AC, which is the toughest canonical ≤1HD familiar form).
- All movement values must be divisible by 5.
- Saves default to NM (Normal Man) save category at level 0, matching canon's bat and hawk.
- Morale is irrelevant for familiars (utterly loyal — never rolls morale) but is recorded on the form for completeness.

Canon forms (`bat`, `hawk`) reference `data/monsters/monster_catalog.json` by `monster_id` rather than duplicating their stat blocks. Project-authored forms inline their stat blocks under a `stat_block` key.

### 3.2 Reflavoring

The Hawk form supports cosmetic species variants (Hawk/Raven/Eagle/Falcon/Owl) that share the same stat block. The player picks a variant for narrative flavor only; mechanics are identical. Same applies to the Snake (Garter/Adder/Viperling), Toad/Frog, and Weasel/Ferret/Stoat groupings.

### 3.3 Stat overlay rule + HD progression

| Field                            | Source / Formula                                                       |
|----------------------------------|------------------------------------------------------------------------|
| HD (display)                     | Per HD progression table below                                         |
| Max HP                           | ½ master's max HP (banker's rounding)                                  |
| INT                              | Master                                                                 |
| Proficiency count (budget)       | Master (general + class slots, summed across `selections_count`)       |
| Proficiency picks (selections)   | Independently picked by player from union of (a) general proficiency list and (b) master's class proficiency list — **not** required to mirror master's actual picks |
| Attack throw                     | Master L1: as Normal Man (NM/0). Master ≥ L2: as Fighter at HD-integer |
| Save category                    | Master L1: NM. Master ≥ L2: Fighter at HD-integer                      |
| Damage bonus                     | Master L1: 0. Master ≥ L2: +HD-integer (matches fighter level)         |
| AC                               | Form                                                                   |
| Movement (all modes)             | Form                                                                   |
| Attack routines (count + dice)   | Form                                                                   |
| Special abilities                | Form                                                                   |
| Morale                           | N/A — utterly loyal, never rolls morale                                |

#### HD progression table

The familiar's HD scales with the master's level on a half-step pattern. Saves and attack throws track the *integer HD* as a fighter level (Normal Man at master L1).

| Master level | Familiar HD | Attacks/saves as | Damage bonus |
|--------------|-------------|------------------|--------------|
| 1            | 0.5         | Normal Man       | 0            |
| 2            | 1           | Fighter L1       | +1           |
| 3            | 1 + 2 hp    | Fighter L1       | +1           |
| 4            | 2           | Fighter L2       | +2           |
| 5            | 2 + 2 hp    | Fighter L2       | +2           |
| 6            | 3           | Fighter L3       | +3           |
| 7            | 3 + 2 hp    | Fighter L3       | +3           |
| 8            | 4           | Fighter L4       | +4           |
| ...          | ...         | ...              | ...          |

Formulas (master level `M` ≥ 2):
- `hd_dice = M / 2` (integer floor — 2→1, 3→1, 4→2, 5→2, 6→3, 7→3, 8→4, ...)
- `hd_modifier_hp = 2` if `M` is odd, else `0` (no modifier at L2; +2 at L3; +0 at L4; +2 at L5; ...)
- `attack_save_class = "fighter"`, `attack_save_level = hd_dice`, `damage_bonus = hd_dice`

At master level 1 (the special case):
- `hd_dice = 0`, `hd_modifier_hp = 0`, `is_half_hd = true`
- `attack_save_class = "NM"`, `attack_save_level = 0`, `damage_bonus = 0`

This progression is implemented as a pure static helper on `FamiliarData`: `compute_progression_for_master_level(master_level: int) -> Dictionary` returns the keys above. Stage 2's level-up cache refresh re-runs the derivation and persists the new values; the runtime save-throw and attack-throw resolvers then look up "fighter L`attack_save_level`" via the existing `ClassRegistry` (or "NM/0" for master L1 familiars).

Note that *max HP* is still derived as ½ master's max HP rather than rolled from the displayed HD. This is by design: the half-HD progression and the half-HP rule track each other closely (a level-5 master with ~22 HP yields a 2+2 HD familiar with ~11 HP, matching what 2d8+2 would roll on average), and using the master's actual HP keeps the wound state consistent across level-ups without re-rolling.

### 3.4 Acquisition

No ritual, no cost. The familiar materializes the moment the proficiency is taken (character creation) or the moment the master gains a level after their previous familiar died (level-up). Two UI entry points:

1. **Character creation, proficiency-selection page** — when the player picks Familiar, an inline picker collects (in order): form, cosmetic variant, name, and the familiar's own proficiency selections (see §3.4.1 below).
2. **Level-up UI, "Familiar" sub-tab** — visible when `has Familiar proficiency AND (no living familiar with current_level > bonded_at_master_level of the most recent dead) OR (living familiar AND proficiency_count_cached > proficiencies_chosen.size())`. The sub-tab routes to either the full acquisition picker (no living familiar) or just the additional-proficiency-picker step (living familiar whose budget grew on this level-up).

Acquisition stamps `bonded_at_master_level` on the new row equal to the master's level at bonding. Replacement is gated on master's level being **strictly greater than** that value.

#### 3.4.1 Familiar-specific proficiency picker

The familiar selects its **own** proficiencies — same total count as the master (`proficiency_count_cached` = sum of master's general + class `selections_count`), drawn from the union of:

- **(a)** the general proficiency list, and
- **(b)** the master's class proficiency list (e.g., the mage class proficiency list for a mage's familiar).

The familiar's picks are **independent of the master's** — the player isn't required to mirror master's actual choices, but is constrained to the same lists and the same per-proficiency stacking rules (`max_rank`, `max_selections`, `selection_rule` from `data/proficiencies/proficiency_catalog.json`). Stored on the row as `proficiencies_chosen` (already a JSON Array column on the `familiars` table — schema-ready).

The picker reuses the existing proficiency-picker subsystem (`ProficiencySelectionPanel` and `LevelUpProficiencyPicker` patterns established for character creation and master level-up). Stage 3 builds a thin wrapper that:
- Computes the eligible-list union from master's class list + the universal general list.
- Sets the budget = `proficiency_count_cached`.
- Validates against the same stacking rules used elsewhere.
- Persists picks to `proficiencies_chosen` via `update_familiar`.

**Level-up budget growth:** A familiar's `proficiency_count_cached` grows in lockstep with its master's at every level-up tier where master gains new general or class slots. Stage 2's level-up cache-refresh hook recomputes `proficiency_count_cached` from master's current `selections_count` totals; if the new budget exceeds `proficiencies_chosen.size()`, the level-up UI's "Familiar" sub-tab opens an additional-picks step letting the player pick the new proficiencies for the existing familiar (independent of, and in addition to, the new picks the master is making for themselves on their own proficiency tab).

### 3.5 Storage

Dedicated `familiars` table (migration 044). One living familiar per master enforced by partial unique index. Dead familiars are kept (post-mortem and replacement-gating).

### 3.6 Bat's canon land speed (9'/3')

The only canon edge case for the divisible-by-5 movement rule. Stage 1 keeps canon as-printed in the bat entry; the runtime movement system can decide whether to grid-snap. Flagged for confirmation before Stage 2 lands.

## 4. Data Layer Artifacts (Stage 1)

- `data/monsters/monster_catalog.json` — Bat (Ordinary) ported from rules.
- `data/familiars/familiar_form_catalog.json` — seven forms.
- `db/migrations/044_familiars.sql` — new `familiars` table.
- `engine/shared_types/familiar_data.gd` — `FamiliarData` resource type with stat-derivation helper.
- `engine/autoloads/campaign_repository.gd` — familiar CRUD methods.
- `engine/autoloads/event_bus.gd` — `familiar_bonded`, `familiar_died`, `familiar_spoke` signals.

## 5. Items Flagged For Review

- **Project-authored stat blocks** (cat, rat, snake_small, toad, weasel) — Jedidiah sign-off needed on AC/attacks/special abilities. (HD scales with master per §3.3 — not per-form.)
- **Bat's 9'/3' canon land speed** — pass-through canon, grid-snap to 10/5, or other? Confirm before Stage 2.
- **Alignment→form mapping** — v1 allows any form. Confirm.

## 6. Future (Stage 2 / Stage 3)

- **Stage 2** — `familiar_controller.gd`: proximity check (`familiar_within_30ft` flag), death-link save vs Death, cache refresh on level-up. Save-throw modifier resolver wiring for the existing condition flag in [data/proficiencies/proficiency_catalog.json:1377](../data/proficiencies/proficiency_catalog.json).
- **Stage 3** — Familiar-picker UI component (form, cosmetic variant, name fields), familiar-specific proficiency-picker wrapper around the existing `ProficiencySelectionPanel` / `LevelUpProficiencyPicker` (per §3.4.1 — eligible-list union of general + master's class list, budget = `proficiency_count_cached`, picks persist to `proficiencies_chosen`), embed both in the character-creation proficiency-selection page, level-up "Familiar" sub-tab handling both replacement bonding and additional-picks-on-budget-growth, manual end-to-end test (level-1 mage → familiar with form picks + N proficiency picks → level-up → budget grows → additional picks UI surfaces).
