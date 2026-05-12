Short answer: **ACKS 1e does not have a critical-hit rule.** A natural 20 has no special damage effect by default — it just guarantees the attack lands. Here's what the rules corpus actually says about a natural 20, and what the closest analogues are.

## What a natural 20 does by default

**RAW:** `rules/acore_combat_and_wounds.xml:157-167`

> To attack, roll 1d20 and apply modifiers from Strength or Dexterity, magic, and circumstances.
> Compare the result to the attacker's attack throw target number.
> Add the target's Armor Class to the required attack throw value.
> If the modified roll is greater than or equal to the required number, the attack hits.
> **An unmodified natural 20 always hits.**
> An unmodified natural 1 always misses.
> On a hit, roll damage according to weapon or monster attack and apply bonuses or penalties.

That's it for the base mechanic. A natural 20 is an auto-hit that bypasses AC math entirely, but it deals ordinary damage — no doubling, no crit table, no bonus effect. Searches for "critical hit," "natural twenty," and similar D&D-flavored phrasings return no matches in the rules corpus.

## Conditional exceptions — where a natural 20 *does* do something extra

ACKS handles "the 20 mattered more than just hitting" through narrowly scoped opt-in effects rather than a universal crit rule:

**1. Weapon Focus proficiency** — `rules/acore_proficiencies_rules_and_catalog.xml:1048-1060`

> With a chosen weapon category, an unmodified natural 20 deals double normal damage.

Pick a weapon category (Axes; Maces, flails, and hammers; Swords and daggers; Bows and crossbows; Slings and thrown weapons; Spears and polearms). Within that category, a natural 20 doubles damage. Repeatable for additional categories.

**2. Vorpal sword** — `rules/acore_treasure_and_magic_items_rules.xml:272-282`

> On a natural 20 attack throw, decapitates a struck target unless it saves versus Death. If the save succeeds, or if the target has no head, the attack instead deals double normal damage.

Item-specific, but the same trigger.

## The closest ACKS-native analogue to "crit" feel: cleaving

ACKS gets its "the big hit feels great" energy from **cleaving**, not from natural 20s — see `rules/acore_combat_and_wounds.xml:479-498`:

> Whenever a combatant kills or incapacitates an opponent with a melee or missile attack, the attacker may immediately make another attack throw. The new target must be within 5 feet of the enemy just dropped. The additional attack must use the same weapon... Fighters, monsters, and other characters using fighter attack throws may make up to a number of cleave attacks per round equal to their Hit Dice. Clerics, thieves, and others using cleric/thief attack throws may make up to half their Hit Dice in cleave attacks, rounded down. Mages and others using mage attack throws may not cleave.

So in implementation terms: a natural 20 in our engine should auto-hit, deal normal damage, and check (a) Weapon Focus on the attacker for the weapon category in use, and (b) any vorpal-like item effects. There is no universal crit multiplier or crit table to apply.

## Heads-up — design gap

If you want a "natural 20 = something more dramatic" feel as a house rule for the Arbiter — even for monsters or untrained fighters — that's outside ACKS RAW and would need to live in a `generation/` GDD. Want me to draft one, or do you want to keep crits flat and let Weapon Focus / cleave do the heavy lifting?
