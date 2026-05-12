The cleric's turning power is defined in the Core class entry. Here's the RAW with citations.

**RAW:** `rules/acore_core_classes.xml:810-1021` (turning subsystem: definition, rules, procedure, and turning table)

> Call upon divine power to turn away, destroy, or in some chaotic sects control undead.
>
> - Turning potency depends on cleric level and undead type.
> - On the turning table, "-" means the cleric is too low level to affect that undead type.
> - "T" means the undead are automatically turned.
> - "D" means the undead are automatically destroyed.
> - A numbered entry means the player must roll that number or higher on 1d20 to turn the undead.
> - On a successful numeric turning attempt, or on a "T" result, roll 2d6; the total equals the total Hit Dice of undead turned.
> - On a "D" result, roll 2d6; the total equals the total Hit Dice of undead destroyed.
> - At least one undead monster is always turned or destroyed on a successful use of turning, regardless of the 2d6 total.
> - There is no daily limit on attempts to turn undead.
> - If an attempt to turn undead fails during an encounter, the cleric cannot attempt to turn undead again for the rest of that encounter.
> - Turned undead flee for 10 rounds by the best and fastest means available.
> - If turned undead cannot flee, they cower, take no actions, and suffer a -2 penalty to AC.
> - If the cleric attacks turned undead in melee, the turning effect ends.
> - The cleric may use spells or missile weapons against turned undead without breaking the effect.
> - Other characters may attack turned undead in any fashion without breaking the effect.
> - Destroyed undead are immediately reduced to ash.
> - Certain chaotic sects control undead instead of turning them.
> - Controlled undead last for 1 turn per cleric level, or 1 day per cleric level if the result would have destroyed them.
> - Controlled undead behave as if charmed and obey the cleric as friends.
> - If controlled undead are turned or destroyed by a cleric before control ends, the control ends immediately.
> - If control ends naturally, the undead flee as if turned.
> - Infernal includes very powerful undead or unholy beings such as demons and devils.

The turning table itself (same XML span) is organized by undead type along the row axis (Skeleton, Zombie, Ghoul, Wight, Wraith, Mummy, Spectre, Vampire, Infernal) and cleric level 1 through 14+ across the columns. Each cell holds either a 1d20 target number (e.g., Skeleton vs. level 1 cleric is `10+`), a `T` (auto-turn), a `D` (auto-destroy), or `-` (too low-level to affect).

**RAW:** `rules/acore_combat_and_wounds.xml:357-369` (action economy)

> Instead of attacking, a combatant may take another action accomplishable in a few seconds. [...] Turn undead. [...]

That confirms turning consumes the combatant's action for the round (it's listed among the "other actions" that substitute for an attack).

**Synthesis -- how the power works in 1e**

1. **Trigger.** On the cleric's initiative, they spend their round-action to call on divine power. No daily resource is consumed.
2. **Look up the target.** Cross-reference the cleric's class level against the undead type on the turning table.
   - `-` -> attempt is impossible; the cleric can't affect that undead at their current level.
   - A number (e.g., `7+`) -> roll 1d20; success on that number or higher.
   - `T` -> automatic turn, skip the d20.
   - `D` -> automatic destruction, skip the d20.
3. **Resolve magnitude.** On any success (numeric, T, or D), roll 2d6 for total Hit Dice of undead affected. At least one undead is always affected on a success, even if the 2d6 result would otherwise be lower than the target's HD.
4. **Effect on turned undead.** They flee by the best and fastest available means for 10 rounds. If they can't flee, they cower (no actions, -2 AC). The turning ends if the cleric melees them; spells and missile fire from the cleric -- and any attacks from other party members -- do not break the effect.
5. **Effect on destroyed undead.** Immediately reduced to ash.
6. **Failure lockout.** A failed attempt locks the cleric out of further turning attempts for the rest of that encounter (but not the day -- there is no per-day cap, only the per-encounter "one shot per encounter once you whiff" rule).
7. **Chaotic variant.** Chaotic sects substitute "control" for "turn." Controlled undead behave as charmed allies; duration is 1 turn / cleric level normally, or 1 day / cleric level when the result would have destroyed them. Control collapses if another cleric turns or destroys them, and on natural expiry the undead flee as if turned.
8. **"Infernal" row.** That row applies to extremely powerful undead and to unholy beings such as demons and devils -- useful to know when you're modeling target categories.

**Terminology note.** ACKS 1e uses **turn undead**, not "rebuke undead" (per `CLAUDE.md`). Even chaotic clerics who *control* undead use the same mechanic and are still described as turning attempts on the table -- "control" is a result substitution, not a separate ability name.

**Related references in the corpus (lower precedence, but worth flagging when you implement):**

- `rules/pc_classes_4.xml:474-504` -- the APC priestess inherits "turn undead as a cleric of equal level" with the same per-encounter failure lockout.
- `rules/acore_campaign_classes.xml:932-942` and `rules/acore_demihuman_classes.xml:429-439` -- other classes that piggyback on "turns undead as a cleric."
- `rules/acore_aging_poisons_high-level-start_optional_rules.xml:654-679` -- blighted/forsaken sinkholes modify or disable turning (e.g., lawful clerics turn at -4 effective levels in a blighted sinkhole; cannot turn at all in a forsaken sinkhole).
- `rules/le_monster_catalog_2_summary.xml` -- individual monster entries carry `<spell_interactions>` with `turn undead` results (e.g., skeletons `affected`; certain ghoulish hybrids `unaffected` because they aren't truly undead). When you wire this into the engine, the per-monster interaction tag is the authoritative answer for whether a given creature is turnable, not just whether it has the `undead` keyword.

If/when this gets implemented in GDScript, the natural shape is: a `TurningTable` resource keyed by undead type and cleric level returning `{ kind: NUMERIC|T|D|IMPOSSIBLE, target: int? }`; a `turn_undead()` combat action that consumes the round-action, evaluates against the target's interaction tag, rolls 1d20 if numeric, rolls 2d6 on success, and applies a `turned` or `destroyed` effect with the per-encounter lockout tracked on the cleric.
