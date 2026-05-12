# Turn Undead in ACKS 1e

Pulled from `rules/acore_core_classes.xml` (the cleric class entry, `<class_subsystems><turning>`). This is the canonical 1e rule.

## What it is

The cleric calls upon divine power to **turn away**, **destroy**, or — in some chaotic sects — **control** undead. It is the cleric's signature class power and is gated by upholding the doctrines of the faith and deity (same prerequisite as casting divine spells). Falling from favor can attract Judge-imposed penalties.

## The roll

The result of a turning attempt is read off the **Turning Undead table**, cross-referencing the undead's type against the cleric's level. The cell can be one of:

- **"-"** — cleric is too low level; the attempt cannot affect this undead type at all.
- **A number (e.g., 10+, 7+, 4+)** — roll 1d20; meeting or exceeding the number turns them.
- **"T"** — automatic turn, no 1d20 roll.
- **"D"** — automatic destruction, no 1d20 roll.

On any successful turn (numeric success or "T"), roll **2d6** — that total is the **Hit Dice of undead turned**. On a "D" result, roll 2d6 for **Hit Dice destroyed**. Even if the 2d6 roll is lower than the HD of a single undead present, **at least one undead is always turned or destroyed** on a success.

## Frequency

- **No daily limit** on attempts.
- **But**: if an attempt **fails during an encounter**, the cleric cannot try again against those undead for the rest of that encounter.

## Effects of being turned

- Turned undead **flee for 10 rounds** by the best and fastest means available.
- If they cannot flee, they **cower**, take no actions, and suffer **-2 AC**.
- If the **cleric** attacks the turned undead **in melee**, the turning effect ends. The cleric may still use **spells or missile weapons** on them without breaking the effect.
- **Other characters** can attack the turned undead in any fashion without breaking the effect.
- Destroyed undead are immediately reduced to ash.

## Control (chaotic sects)

Some chaotic clerics control undead instead of turning them:

- Duration is **1 turn per cleric level** on a result that would have turned them; **1 day per cleric level** on a result that would have destroyed them.
- Controlled undead behave as if **charmed** and obey the cleric as friends.
- If another cleric turns or destroys them before control ends, control ends immediately.
- When control ends naturally, the undead flee as if turned.

## Undead types on the table (in ascending difficulty)

Skeleton, Zombie, Ghoul, Wight, Wraith, Mummy, Spectre, Vampire, **Infernal** (the last column covers very powerful undead and unholy beings such as demons and devils). Each step down the list shifts the column right by roughly one cleric level — e.g., a Skeleton is auto-destroyed ("D") at 6th level, while a Vampire only reaches "D" at 13th.

## A few worked column samples

- **1st-level cleric**: 10+ vs Skeletons, 13+ vs Zombies, 16+ vs Ghouls, 19+ vs Wights. Nothing higher.
- **6th-level cleric**: auto-D Skeletons/Zombies, T Ghouls, 4+ Wights, 7+ Wraiths, 10+ Mummies, 13+ Spectres, 16+ Vampires, 19+ Infernals.
- **14th+ cleric**: D across the entire table.

## Implementation notes for the engine

A few things worth pinning down when we build this:

1. **The table is small and stable** — load it as a resource (or hardcode a 2D lookup keyed by `undead_type` and `cleric_level`, clamped at 14+).
2. **Encounter-scoped failure flag.** The "cannot try again this encounter" rule needs an encounter-level state bit on the cleric, not a per-day cooldown. This ties into the EventScheduler's encounter context.
3. **"Melee break" rule** needs a hook on the cleric's attack resolution: if target has the `turned_by:<this_cleric>` status, clear it on a melee strike (but not on spell or missile).
4. **2d6 HD pool** is allocated across undead present — we'll need a deterministic rule for selection order (probably lowest-HD first to maximize affected count, but the XML doesn't specify; flag for Jedidiah).
5. **"Infernal" column** — note this isn't strictly undead. We'll want monster entries to carry an explicit `turning_category` field rather than inferring from type.
6. **Doctrinal favor** is a prerequisite. Once we have the faith/doctrine subsystem, turning needs to check it the same way divine spellcasting does.

Source: `rules/acore_core_classes.xml`, lines ~810-1020 (cleric `<class_subsystems><turning>` block and the `turning_undead` table).
