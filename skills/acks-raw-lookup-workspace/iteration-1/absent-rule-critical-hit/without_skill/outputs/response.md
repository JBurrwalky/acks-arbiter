# Critical Hits in ACKS 1e

Short answer: **ACKS 1e does not have a "critical hit" rule.** A natural 20 on an attack throw is special only in one narrow way — it is an automatic hit regardless of modifiers — but it does no extra damage and triggers no special table by default.

## What the rules actually say

From `rules/acore_combat_and_wounds.xml` (the general attack procedure):

- "An unmodified natural 20 always hits."
- "An unmodified natural 1 always misses."
- "On a hit, roll damage according to weapon or monster attack and apply bonuses or penalties."

That's it. There is no doubled damage, no critical confirmation roll, no "fumble" effect on a natural 1 beyond the automatic miss. Damage on a natural 20 is rolled the same as any other hit.

## Why D&D players expect more

If you're coming from later D&D editions (3e onward) or from house-ruled OSR games, you may be used to crits doubling damage dice or rolling on a critical table. ACKS 1e deliberately omits that mechanic — extra lethality in ACKS comes from the **Mortal Wounds** system (`rules/ax_mortal_wounds_and_tampering.xml`), which triggers when a creature is reduced to 0 hp or below, not from the attack roll itself.

## Adjacent rules people sometimes confuse with crits

A few ACKS rules can cause damage to be multiplied, but none of them are "critical hits":

- **Charging with a spear, lance, polearm, or certain natural attacks** deals double damage on a successful charge (acore_combat_and_wounds.xml).
- **Setting a spear/polearm against a charge** deals double damage to the charger if the defender has equal or better initiative.
- **Backstab** (thief class ability) multiplies damage based on the thief's level.
- **Coup de grace / slaying a helpless foe** is an automatic kill, not a crit roll.

These are situational multipliers tied to tactics or class features, not to the attack roll showing a 20.

## Implications for the engine

For the Arbiter implementation, the attack resolver should:

1. Roll 1d20, add attack throw modifiers, compare to (target number + AC).
2. Treat an **unmodified** 20 as auto-hit (bypass the comparison).
3. Treat an **unmodified** 1 as auto-miss.
4. On any hit, roll damage normally — no multiplier hook needed for the natural 20.
5. Damage multipliers (x2 on charges, backstab multipliers, set-against-charge) are separate code paths driven by combat state and class features, not by the d20 result.

If you eventually want a house-ruled crit system, that's a Layer 2 (`generation/`) design decision — but it's not in the books and shouldn't be implemented as if it were.
