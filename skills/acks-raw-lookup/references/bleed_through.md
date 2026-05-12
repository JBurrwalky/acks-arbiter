# D&D / Pathfinder → ACKS Terminology Reference

This file lists the D&D and Pathfinder terms that the model is most likely to import into ACKS Arbiter from training data, along with the ACKS 1e equivalent (or a flag that ACKS doesn't have it). When you catch yourself using one of the left-column terms, stop and look up the ACKS spelling with `scripts/lookup.py`.

The list is non-exhaustive. If you suspect bleed-through but don't see the term here, the safer move is always to run `lookup.py` for the ACKS spelling you think is right — if nothing comes back, ask Jedidiah.

## Active substitutions — use the ACKS term

| D&D / PF term | ACKS 1e equivalent | Where to look |
|---|---|---|
| Rebuke undead | **Turn undead** | cleric class power, `acore_core_classes.xml` |
| Spell slot | Spell repertoire / spells per day | `acore_spellcaster_rules.xml` |
| Difficulty class (DC) | Proficiency throw value (target number) | `acore_proficiencies_rules_and_catalog.xml` |
| Skill check | Proficiency throw | `acore_proficiencies_rules_and_catalog.xml` |
| Concentration check | `concentrating` condition (broken by damage, failed save, attack, casting, fast movement) | `ax_conditions_catalog.xml` |
| Saving throw vs. fortitude / reflex / will | Five named saves: **Petrification & Paralysis**, **Poison & Death**, **Blast & Breath**, **Staffs & Wands**, **Spells** | `acore_basics_and_characters.xml` |
| Spell save DC | Target's named save (Spells, etc.) at the target's class-table value | `acore_basics_and_characters.xml` |
| Initiative (1d20 + Dex) | Initiative (**1d6** + Dex) | `acore_combat_and_wounds.xml` |
| Armor Class (10 base) | Armor Class (ascending scale starting near 0 for unarmored) | `acore_combat_and_wounds.xml`, `acore_basics_and_characters.xml` |
| Long rest, short rest | No equivalent — ACKS uses **turn / hour / day** timekeeping, with HP recovery rates and natural healing tables | `acore_combat_and_wounds.xml`, `acore_adventures_and_encounters.xml` |
| Cleric domain / divine domain | Not the same — ACKS clerics have a uniform spell list; class powers and proficiencies differentiate | `acore_core_classes.xml` |
| Hit Dice (as a healing resource) | HD is a creature stat in ACKS; there is no D&D-5e-style hit-dice-spending recovery | `acore_combat_and_wounds.xml` |
| Pounds (encumbrance unit) | **Stones** | `acore_equipment.xml`, `acore_basics_and_characters.xml` |
| Charisma-based persuasion | Charisma modifier + Reaction roll + influencing rules | `ax_reactions_and_influencing.xml`, `acore_basics_and_characters.xml` |

## Things ACKS 1e does NOT have — do not invent

These have no rules-corpus equivalent. If a task seems to require them, surface the gap rather than synthesizing from D&D.

- **Crusader** class progression. ACKS 1e has four combat progressions: fighter, cleric, thief, mage. ("Crusader" is an ACKS II change, not present here.)
- **Outlands / Unsettled** territory classification. ACKS 1e has three: Civilized, Borderlands, Wilderness.
- **Feats** (per D&D 3e/PF). ACKS uses **proficiencies**, with general / class / venturer trees and the catalogs in `acore_proficiencies_rules_and_catalog.xml` and `pc_proficiencies_catalog.xml`.
- **Bonus actions** (per D&D 5e). ACKS rounds have a movement and an attack/action; no bonus-action economy.
- **Advantage / disadvantage** (per D&D 5e). ACKS uses numeric modifiers and reroll-the-higher mechanics where relevant.
- **Inspiration / hero points / luck points / fate dice**. None in ACKS 1e core. APC class powers may grant similar narrow effects; look those up.
- **Spell components V/S/M** as a tracked resource gating each cast. ACKS has reagents for some spells and material requirements for codex/scroll magic, but not the 5e V/S/M slot system.
- **Critical hits / natural 20 / natural 1 fumble** (as a generic rule). ACKS has **cleaving** on a kill but no generic crit. Some monsters or proficiencies grant specific effects on 20 — look those up.
- **Cantrips** (at-will 0-level spells). ACKS spells start at level 1 with daily uses governed by spells-per-day. (Note: Magical Music and a few class powers function similarly to cantrips for their specific effects — look up the class power, don't generalize.)
- **Death saves** (per D&D 5e). ACKS uses **Mortal Wounds** on reaching 0 HP — `ax_mortal_wounds_and_tampering.xml`.
- **Exhaustion levels** (per D&D 5e). ACKS uses condition entries and the fatigue rules in adventure/exploration sections.
- **Inspiration die / bardic inspiration** (as the 5e mechanic). The ACKS bard, if used, has its own class powers — look them up.

## Adjacent terms ACKS uses differently — always look up

These exist in ACKS but the semantics differ enough from D&D that the model is likely to mis-state them. Always run `lookup.py` before describing.

- **Initiative**: 1d6 + Dex, simultaneous on ties.
- **Attack throws**: target_value + AC = 1d20 to hit, not "DC = 10 + AC + …". The class table specifies the target value.
- **AC**: ascending scale starting at ~0 for unarmored humans. Armor adds to AC. Higher AC = harder to hit.
- **HP healing**: natural recovery is 1 HP/day baseline, modified by Constitution adjustment, infection rules, and rest quality.
- **Encumbrance**: stones (a stone is roughly 10 lb but ACKS treats it as a discrete unit, with item weights and per-class limits).
- **Currency / treasure**: gp/sp/cp at ACKS ratios (10 sp = 1 gp, 10 cp = 1 sp), with the XP-for-gp economy and treasure types per monster.
- **Domain rules**: families, peasant productivity, market classes, land revenue — entirely ACKS-specific.
- **Mass combat (Domains at War)**: troop tables, BR (battle rating), commands per round, morale at unit and army scale. Not D&D-compatible.
- **Hijinks (Campaign hijinks)**: crime/spying/etc. resolved on dedicated tables. Not "skill checks."
- **Mortal Wounds** and **Tampering with Mortality**: ACKS replaces 5e-style death saves with full subsystems. Have a clear lookup before referencing.

## How to use this reference

This file is a checklist, not a rulebook. The rules are in `rules/*.xml`. When a D&D term shows up:

1. Find the row in the substitution table above.
2. Note the suggested file to search.
3. Run `python3 scripts/lookup.py "<ACKS-term>"` to retrieve the citation and excerpt.
4. Use the citation in your output. If the lookup fails, the fallback is escalation to Jedidiah — never substitute the D&D rule.
