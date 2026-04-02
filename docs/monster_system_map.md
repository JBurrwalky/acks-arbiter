# Monster-to-System Map

Maps monster stat block fields and special abilities to the game systems they mechanically affect so the build agent can implement monster-ability hooks at system-build time rather than retrofitting them later.

**Authority:** Project-designed document (GDD-tier). Monster details derive from sacred XML rule summaries (`le_monster_characteristics_stats`, `le_monster_creation`, `acore_combat_and_wounds`, all `acore_monster_catalog_*` files, all `le_monster_catalog_*` files). System names match `rule_system_map.md`.

**Scope:** All monsters from ACore and L&E catalogs, plus the monster creation rules from L&E that define the canonical special ability taxonomy. Dragon variant rules from `acore_monster_catalog_dragons` and `le_monster_catalog_dragons`.

**How to use:** When building system X, load the relevant section to see which monster abilities that system must support. Each entry describes the *hook* the system needs — not the full monster stat block (those live in the XML catalogs and the eventual JSON catalog in F-0). Build the hook interface; individual monster bindings happen during monster catalog construction.

**Companion documents:** `spell_system_map.md` (same structure, for spells), `proficiency_system_map.md` (same structure, for proficiencies), `gdd_combat_behavior_tags.md` (behavioral AI tags, not mechanical abilities).

---

## Legend

- **Hook** = the interface or capability the system must expose for monster abilities to interact with it
- **Representative monsters** = not exhaustive; shows the range of creatures that use each hook
- **Source** = XML file where the general rule for this ability is defined
- **XP marker** = `*` (major ability) or `#` (minor ability) per `le_monster_creation` XP counting rules; `**` = counts as two major abilities

---

## 1. Monster Stat Block Schema

The canonical fields every monster entry requires in the data catalog. These fields map directly to the stat block format defined in `le_monster_characteristics_stats`.

### 1.1 Identity & Classification

| Field | Type | Notes |
|---|---|---|
| `id` | string | Unique monster identifier (snake_case, e.g. `giant_spider_black_widow`) |
| `name` | string | Display name |
| `variant` | string or null | Variant label if this is a sub-type (e.g. "Ordinary", "Giant", "Black") |
| `source` | string | Source book reference label |
| `monster_types` | array of string | One or more from the canonical type list (§5). A creature may belong to multiple types. |
| `alignment` | enum | `lawful`, `neutral`, `chaotic` |
| `intelligence` | enum | `mindless`, `animal`, `semi`, `low`, `average`, `high`, `very_high`, `genius`, `supra_genius` |
| `size_category` | enum | `tiny`, `small`, `man_sized`, `large`, `huge`, `gigantic`, `colossal` |

### 1.2 Combat Statistics

| Field | Type | Notes |
|---|---|---|
| `hit_dice` | object | `{ base: int, modifier: int, special_ability_stars: int }`. E.g. HD 6+3* → `{ base: 6, modifier: 3, special_ability_stars: 1 }`. HD "1hp" → `{ base: 0, modifier: 1, special_ability_stars: 0 }`. |
| `armor_class` | int | Numeric AC value. Lycanthropes with dual AC store animal-form AC separately. |
| `attack_routines` | array of AttackRoutine | See §1.3 below. |
| `save_as` | object | `{ class: string, level: int }`. Class abbreviations: F=Fighter, C=Cleric, M=Mage, T=Thief, D=Dwarven Vaultguard, E=Elven Spellsword. |
| `morale` | int or null | Integer from -6 to +4. Null = never rolls morale (mindless vermin, constructs, controlled undead). |
| `xp` | int | Pre-calculated XP value at base HD. |

### 1.3 Attack Routine Schema

A monster may have multiple named attack routines (e.g. "melee_routine" and "breath_weapon_routine" for dragons). Each routine contains:

| Field | Type | Notes |
|---|---|---|
| `routine_name` | string | Identifier (e.g. `melee`, `breath_weapon`, `ranged`) |
| `usage` | string | When this routine applies: `default`, `conditional`, `alternate` with usage probability if applicable (e.g. "50% of rounds") |
| `attacks` | array of Attack | Ordered sequence of individual attacks in this routine |

Each Attack entry:

| Field | Type | Notes |
|---|---|---|
| `attack_type` | string | `claw`, `bite`, `sting`, `tail`, `horn`, `hoof`, `talon`, `touch`, `gaze`, `breath_weapon`, `weapon`, `trample`, `special` |
| `count` | int | Number of this attack per routine (e.g. 2 claws) |
| `damage` | string | Dice expression (e.g. `1d6`, `2d8+2`) or `special` for non-damage attacks |
| `to_hit_modifier` | int | Modifier beyond the HD-derived attack throw, if any (default 0) |
| `special_effect` | string or null | Reference to a special ability that triggers on hit (e.g. `poison`, `paralysis`, `energy_drain`, `petrification`) |

**System requirement:** The combat system must iterate through the active attack routine's attack array, resolving each attack in sequence. Some monsters choose between routines (dragons: melee OR breath weapon); the routine selection logic is behavioral, not mechanical — governed by `gdd_combat_behavior_tags.md` and the tactical AI.

### 1.4 Movement

| Field | Type | Notes |
|---|---|---|
| `movement` | object | Keyed by mode. `{ land: { exploration: int, combat: int }, fly: { exploration: int, combat: int }, swim: {...}, burrow: {...} }`. Values in feet. |

Movement modes are detailed in §3.

### 1.5 Encounter & Ecology

| Field | Type | Notes |
|---|---|---|
| `percent_in_lair` | int or null | 0–100. Null if the monster never lairs. |
| `dungeon_encounter` | object | `{ outside_lair: { collective_noun: string, number: string }, in_lair: { collective_noun: string, number: string } }`. Number is a dice expression (e.g. `1d6`) or reference to a group structure (e.g. `1 warband`). |
| `wilderness_encounter` | object | Same structure as dungeon_encounter. |
| `treasure_type` | string | Letter code A–R, or `None`, or compound (e.g. `P x2`, `O per gang`). |
| `terrain_affinity` | array of string | Primary terrain types where this monster is encountered (used by encounter table builder). |

### 1.6 Special Abilities

| Field | Type | Notes |
|---|---|---|
| `special_abilities` | array of SpecialAbility | Each entry references a canonical ability from the taxonomy in §2. |
| `immunities` | array of string | Blanket immunities from monster type or individual description (e.g. `sleep`, `charm`, `hold`, `poison`, `gas`, `fire`, `normal_weapons`). |
| `resistances` | array of object | `{ type: string, effect: string }` (e.g. `{ type: "silver_weapons", effect: "half_damage" }`). |
| `vulnerabilities` | array of string | Damage types or conditions that impose extra harm (e.g. `fire`, `acid` for trolls). |

### 1.7 Combat Behavior Tags

| Field | Type | Notes |
|---|---|---|
| `combat_behavior` | object | The eight behavior tag families from `gdd_combat_behavior_tags.md`: `formation_discipline`, `aggression_posture`, `engagement_profile`, `spellcasting_timing`, `consumable_timing`, `primary_target_rule`, `target_tie_breaker`, `morale_style`. |

---

## 2. Special Ability Taxonomy

Organized by hook type, not by monster. This is the meat of the document — the equivalent of §1–§13 in `spell_system_map.md`.

### 2.1 Breath Weapons

**Source:** `le_monster_characteristics_stats` (no general breath weapon special attack defined — rules are per-monster), `le_monster_creation` (ability roll 08-09), `acore_monster_catalog_dragons`.

**Hook:** Area-of-effect typed damage with saving throw for half, usage-limited.

| Sub-type | Representative Monsters |
|---|---|
| Fire cone/cloud | Red dragon, gold dragon, hellhound, chimera (dragon head) |
| Lightning line | Blue dragon, behir |
| Acid line | Black dragon |
| Cold cone | White dragon, frost salamander |
| Poison gas cloud | Green dragon |
| Petrification cone | Gorgon (save vs. Petrification, not half-damage) |
| Fetid gas (disease) | Swamp dragon variants |
| Obscuring vapors | Several dragon variants (steam, freezing vapor, scouring wind) |

**System requirements:**
- Breath weapon as an alternate attack routine (replaces melee attacks for the round)
- Area-of-effect shapes: cloud (20'h × 40'l × 40'w), cone (2' wide at origin → 90'l × 30'w), line (100'l × 5'w) — per dragon general rules, but specific monsters may vary
- Damage expression: typically 1d6 per HD, but per-monster override
- Save type: Blast & Breath (save for half damage) as default; Petrification for gorgon (save-or-condition, not half)
- Usage tracking: uses per day (dragons: 3/day; hellhounds: 3/day per `le_monster_creation` default)
- Damage type registry integration (fire, cold, lightning, acid, poison — already required by spell system)
- Breath weapon immunity: dragons immune to own breath type and similar energy
- Breath weapon resistance: half damage from magical attacks of same type as breath
- Secondary effects: obscuring vapors (-2 attack throws in area for 1 round), disease rider (fetid gas: save vs. Breath or contract rotting disease), armor/material destruction (acid)

### 2.2 Gaze Attacks

**Source:** `le_monster_characteristics_stats` → `petrifying_gaze` special attack, `le_monster_creation` (ability roll 52-53 for petrification, 14-15 for charm).

**Hook:** Passive or active line-of-sight effect with saving throw, requiring gaze-aversion and mirror mechanics.

| Effect | Representative Monsters |
|---|---|
| Petrification (gaze) | Basilisk, medusa |
| Petrification (touch/bite) | Cockatrice (beak), basilisk (bite) |
| Charm (gaze) | Vampire |
| Fear/dread (gaze) | Certain unique monsters |

**System requirements:**
- Gaze resolution procedure:
  1. Surprised opponents automatically meet the gaze (no choice)
  2. Non-surprised opponents choose: fight normally (meet gaze), avert eyes (-4 attack, -2 AC), use mirror (-2 attack, no AC penalty)
  3. If gaze is met: save vs. Petrification or suffer effect
- Mirror reflection rules: monster not immune to own gaze; if surprised by mirror, 1-2 on 1d6 chance of seeing own reflection → must save or be affected
- Petrification as a condition (from `ax_conditions_catalog`): target becomes a stone structure, helpless, immune to most effects, can only be reversed by stone to flesh
- Gaze range: line-of-sight within encounter distance (no hard range limit in ACKS rules; visibility and LoS serve as practical limits)
- Per-monster gaze type flag: `petrification`, `charm`, `fear`
- Contact petrification variant (cockatrice): triggered on successful melee hit, not by gaze — save vs. Petrification on being struck; touching with bare hands also triggers save

### 2.3 Energy Drain

**Source:** `le_monster_characteristics_stats` → `energy_drain` special attack, `le_monster_creation` (ability roll 18-19).

**Hook:** On-hit level removal with no saving throw. Reversal only by ritual magic.

| Drain Amount | Representative Monsters |
|---|---|
| 1 level per hit | Wight, wraith |
| 2 levels per hit | Spectre, vampire |

**System requirements:**
- Level drain on successful touch/hit: no saving throw allowed
- CharacterData reverse-level-up procedure: set XP to minimum for new lower level, recalculate HP (re-roll or reduce by average per lost die), reduce spell slots, reduce proficiency slots, recalculate saves and attack throws
- Monster HD drain: reduce HD and recalculate derived stats
- Death trigger: character reduced to level 0 dies
- Undead creation rider: many energy-draining undead create spawn from victims (wight → new wight in 1d4 days; wraith → new wraith in 24 hours; spectre → new spectre; vampire → new vampire). This is a separate `infectious` ability (§2.10) that often co-occurs with energy drain.
- Reversal: only `wish` or equivalent ritual magic. No standard spell reverses energy drain.
- XP marker: `**` (counts as two special abilities for XP)

### 2.4 Poison

**Source:** `le_monster_characteristics_stats` → `poison` special attack, `le_monster_creation` (ability roll 54-61).

**Hook:** On-hit save-or-die (or save-or-damage for non-lethal variants).

| Lethality | Representative Monsters |
|---|---|
| Save vs. Poison or die (immediate) | Giant spiders (most), giant scorpion, wyvern (sting), purple worm (sting), pit viper, cobra |
| Save vs. Poison or die (delayed) | Medusa (snakebite: death after 1 turn) |
| Save vs. Poison or damage/condition | Carcass scavenger (paralysis, technically filed under §2.5), giant centipede (save at +2 or illness) |

**System requirements:**
- Poison application on successful attack hit (specified per-monster which attack carries the poison)
- Default: save vs. Poison or die immediately
- Save modifier: creatures with ≤3 HD apply +2 to victim's save; creatures with ≥9 HD apply -2 (per `le_monster_creation`)
- Non-lethal poison variant: some poisons cause conditions instead of death (coded per-monster)
- Onset delay: most instant, but some have onset (medusa snakebite: 1 turn)
- Neutralize Poison interaction: can restore a poison-killed character if cast within 10 rounds of death
- Delay Poison interaction (from spell system): postpones poison effects for duration
- Poison as attack rider: the poison flag lives on the specific attack entry in the attack routine, not on the monster globally

### 2.5 Paralysis

**Source:** `le_monster_characteristics_stats` → `paralysis` special attack, `le_monster_creation` (ability roll 49-51).

**Hook:** On-hit save-or-paralyze with duration tracking.

| Duration | Representative Monsters |
|---|---|
| 2d4 turns (default) | Ghoul (claw/bite), ghast |
| 1d10 rounds | Some custom monsters per `le_monster_creation` |
| 3d4 turns | Dragon variants with paralyzing blows |
| Special (until removed) | Carrion crawler (8 tentacle attacks), gelatinous cube |

**System requirements:**
- Save vs. Paralysis on hit; failure applies paralyzed condition from `ax_conditions_catalog`
- Paralyzed condition effects: cannot move, speak, or cast spells; conscious and aware; no attack throw needed to hit; any unengaged character can slay in one round
- Duration tracking in turns (most monster paralysis) or rounds (variant)
- Cure Light Wounds interaction: can negate monster paralysis but heals no HP when used this way
- Elf immunity: elves are immune to ghoul paralysis specifically (not all paralysis)
- Multiple-attack paralysis: carrion crawler makes 8 tentacle attacks per round, each requiring a separate save
- Paralysis as attack rider on specific attacks in the routine

### 2.6 Petrification

**Source:** `le_monster_characteristics_stats` → `petrifying_gaze` special attack, `le_monster_creation` (ability roll 52-53).

**Hook:** Save-or-petrify via gaze or touch/hit. Overlaps with §2.2 (gaze delivery) but the petrification *condition* is the hook here.

| Delivery | Representative Monsters |
|---|---|
| Gaze | Basilisk, medusa |
| Beak/bite hit | Cockatrice, basilisk |
| Touch | Cockatrice (bare-hand contact) |
| Breath weapon | Gorgon (cone breath, save vs. Petrification) |

**System requirements:**
- Petrified condition from `ax_conditions_catalog`: helpless, cannot sense or act, does not age, immune to all enchantments/transmogrifications except stone to flesh, immune to death spells except disintegrate, treated as stone structure (1 structural HP per 2,000 lbs)
- Stone to Flesh spell reversal: restores the creature; if the stone form was damaged, restored creature takes proportional damage
- Petrification as a permanent condition (no natural duration — persists until magically reversed or statue destroyed)
- Treasure-on-victims interaction: basilisk/cockatrice/medusa treasure is often on petrified victims and accessible only if restored to flesh

### 2.7 Charm / Domination

**Source:** `le_monster_characteristics_stats` → `charm` special attack, `le_monster_creation` (ability roll 14-15).

**Hook:** Save-or-charm with monster-specific break conditions. Monster charm differs from the charm person spell.

| Delivery | Representative Monsters |
|---|---|
| Gaze | Vampire (charm gaze) |
| Song/voice | Harpy (singing), nixie |
| Touch | Some unique creatures |
| Proximity | Some unique creatures |

**System requirements:**
- Save vs. Spells on exposure; failure applies charmed condition (monster variant)
- Monster charm effects (distinct from spell charm): target becomes confused and passive, cannot use spells or magic items, cannot make decisions, does not defend against charming monster's attacks, acts in monster's interest and protects it (even against allies)
- Save modifier: creatures with ≤3 HD grant +2 to victim's save; creatures with ≥9 HD impose -2
- Break conditions: charm ends immediately if charming monster is killed; other break conditions are per-monster (attacked by the monster, passage of time, remove curse)
- Duration tracking: per-monster (some indefinite until broken, some have fixed duration)
- Charm usage limit: typically 3/day or by gaze (continuous)
- Communication modifier: if monster and victim can communicate, monster can issue commands; if not, victim still acts in monster's interest

### 2.8 Fear / Terror

**Source:** `le_monster_creation` (ability roll 87-88 for "terrifying"), `acore_monster_catalog_dragons` → `fear_aura`.

**Hook:** Area-of-effect or sight-triggered save-or-condition with HD-tiered effects.

| Trigger | Representative Monsters |
|---|---|
| Charge/flyover (HD-tiered) | Dragons (all, by age category) |
| Sight (paralysis) | Mummy (save vs. Paralysis or paralyzed with dread) |
| Proximity/stench aura | Some dragon variants (horrific stench: -3 attack/damage on failed save vs. Poison) |

**System requirements:**
- Dragon fear aura: HD-tiered response on failed save vs. Paralysis:
  - < 1 HD: flee in panic for 4d6 turns (no save)
  - 1–3 HD: paralyzed with fear on failed save
  - 4+ HD: -1 attack throws on failed save
  - Duration: until dragon is slain or passes out of sight and sound
- Mummy fear: save vs. Paralysis or paralyzed with dread (functions as paralysis condition; breaks when mummy leaves line of sight or attacks)
- Fear as condition: interacts with `ax_conditions_catalog` frightened/panicked states
- Morale interaction: fear effects on NPCs/henchmen may trigger morale checks or automatic flight (per Judge discretion)
- Fear immunity: creatures with the `berserk` special ability, undead, constructs, and creatures under the effect of remove fear or similar spells

### 2.9 Regeneration

**Source:** `le_monster_creation` (ability roll 62-63), troll entries in `acore_monster_catalog_tri-wol` and `le_monster_catalog_1`.

**Hook:** Per-round HP recovery with damage-type exceptions.

| Rate | Representative Monsters |
|---|---|
| 3 hp/round (fire and acid bypass) | Troll |
| HD/2 hp/round (generic formula) | Custom monsters per `le_monster_creation` |
| Variable | Vampire (per-monster specific rate if applicable) |

**System requirements:**
- Per-round healing applied during condition tick phase of combat
- Damage-type exception list: two specific damage types (usually fire and acid) prevent regeneration for the round in which that damage was dealt
- Return from zero HP: regenerating creatures reduced to 0 hp continue regenerating and stand to fight again when reaching 1+ hp; only the exception damage types can permanently destroy them
- Limb reattachment: severed parts crawl back to body and reattach instantly if held to stump (narrative flavor; mechanical effect is regeneration continues)
- Morale interaction: trolls' morale drops to 0 when confronted by fire or acid (per source entry)
- Regeneration vs. healing spells: regeneration is a monster ability, not magical healing — it is not blocked by anti-magic effects

### 2.10 Infectious / Spawn Creation

**Source:** `le_monster_creation` (ability roll 39), various undead and lycanthrope entries.

**Hook:** Victims of the monster may transform into monsters of the same type, either on death or on damage threshold.

| Trigger | Representative Monsters |
|---|---|
| Slain by monster → rises as same type | Wight (1d4 days), wraith (24 hours), spectre, vampire |
| 50%+ HP lost to natural attacks → transforms | All lycanthropes (werewolf, wererat, wereboar, weretiger, werebear) — 2d6 day incubation |
| Bite + death → rise as lesser spawn | Vampire (victim becomes vampire under creator's control) |

**System requirements:**
- Death-spawn timer: when a creature is slain by an infectious monster, start a countdown timer; at expiration, the corpse rises as a new creature of the monster's type unless preventive measures are taken (usually bless, remove curse, or destroying the body)
- Damage-threshold lycanthropy: track cumulative damage from a lycanthrope's natural attacks against a victim; if total exceeds 50% of victim's max HP, victim contracts lycanthropy
- Lycanthropy disease: 2d6 day incubation; only humans transform (demi-humans and other humanoids die instead after 2d6 days); cure disease reverses if cast before full transformation; inherited lycanthropy cannot be cured
- Spawn control: spawned undead are under the control of the creating monster (wraith commands its spawn, etc.)
- Spawn prevention: body destruction, bless, holy water, remove curse — per-monster specifics

### 2.11 Swallow Whole

**Source:** `le_monster_characteristics_stats` → `swallow_attack`, `le_monster_creation` (ability roll 81-83).

**Hook:** Engulf mechanic with per-round internal damage, escape mechanics, and digestion timer.

| Trigger Threshold | Representative Monsters |
|---|---|
| Attack throw ≥ target + 4 or natural 20 | Purple worm (up to horse size; 3d6/round) |
| Natural 19-20 | Custom monsters per `le_monster_creation` |
| Automatic on grab | Remorhaz |

**System requirements:**
- Swallow trigger check: compare unmodified attack throw to the monster-specific threshold (typically natural 20, or attack throw exceeding target by 4+)
- Size gate: swallowed creature must be smaller than the monster (specific size limit per monster, e.g. purple worm: up to horse size)
- Engulfed state: swallowed creature is removed from the combat map; takes listed damage each round (per-monster, e.g. 3d6 for purple worm)
- Internal attack: swallowed creature with a sharp weapon may attack from inside at -4 to attack throws; the monster's internal AC is typically lower than external AC (per-monster specification, default = unarmored)
- Escape: only by killing the monster from inside or from outside; no save-based escape in standard rules
- Digestion timer: if swallowed creature dies and remains in belly for 6 turns, body is irrecoverably digested and cannot benefit from restore life and limb
- Treasure interaction: purple worm treasure is found inside the creature's belly

### 2.12 Ongoing / Continuing Damage

**Source:** `le_monster_characteristics_stats` → `continuing_damage`, `le_monster_creation` (ability roll 45-48).

**Hook:** After initial successful hit, damage continues each round without new attack throws.

| Type | Representative Monsters |
|---|---|
| Constriction | Giant snake (python), giant squid/octopus tentacles |
| Blood drain | Stirge, giant leech, vampire |
| Acid (persistent) | Black pudding, gray ooze (but note: black dragon acid does NOT persist) |
| Grab + auto-damage | Roper (tentacle grab → reel in), carrion crawler (tentacle grab) |

**System requirements:**
- Ongoing damage state: once the creature hits, track a "locked on" or "grappling" flag on the target; apply listed damage each round automatically
- End conditions: per-monster (usually: monster death, target death, target breaks free, monster voluntarily releases)
- Stacking: multiple ongoing damage sources stack (e.g., stirge blood drain while also poisoned)
- Acid special case: acid continues to deal damage and can be removed with water; destroys non-magical armor (adjust victim AC to unarmored)

### 2.13 Acid

**Source:** `le_monster_characteristics_stats` → `acid` special attack, `le_monster_creation` (ability roll 01-02).

**Hook:** Acid damage with equipment destruction and persistent damage.

| Effect | Representative Monsters |
|---|---|
| Contact acid (dissolves armor/weapons on hit) | Black pudding, gray ooze, ochre jelly |
| Acid breath (non-persistent, standard damage) | Black dragon |
| Acid splash (ongoing damage until washed) | Ankheg |

**System requirements:**
- Equipment destruction on hit: non-magical armor and clothing destroyed; non-magical weapons striking the monster dissolve after dealing damage
- Magical equipment saving throw: magical weapons and armor receive a save vs. Death using the wielder's save, adding the magical bonus
- Persistent acid damage: continues each round until washed off (requires water or non-flammable liquid)
- Exception: black dragon acid breath does NOT persist round to round
- AC adjustment: if acid destroys armor, victim's AC immediately adjusts to unarmored

### 2.14 Trample

**Source:** `le_monster_characteristics_stats` → `trample` special attack, `le_monster_creation` (ability roll 95-99).

**Hook:** Area attack using bulk, with to-hit bonus against smaller targets.

| Size | Representative Monsters |
|---|---|
| Large+ (individual) | Elephant, triceratops, iron golem |
| Mass trample (20+ animals) | Stampeding herd (horse, cattle) |

**System requirements:**
- Trample as alternate attack routine: monster uses trample instead of normal attack sequence; +4 to attack throw against man-sized or smaller targets
- Usage probability: 3/4 of the time (roll 1d4; 1–3 = trample, 4 = normal attacks) — per general rule, but individual monsters may override
- Mass trample: groups of 20+ normal-sized animals deal 1d20 damage as a trample attack
- Trample damage: should average 2 hp per HD (per `le_monster_creation`)
- Size gate: only Large or bigger creatures can trample (per `le_monster_creation`)

### 2.15 Charge

**Source:** `le_monster_characteristics_stats` → `charge` special attack, `le_monster_creation` (ability roll 10-13).

**Hook:** Double damage on a successful charge attack with natural weapons.

| Weapon Type | Representative Monsters |
|---|---|
| Horn/tusk | Boar, triceratops, rhinoceros |
| Hooves | Warhorse |
| Body slam | Various large creatures |

**System requirements:**
- Charge rules from combat system: move at least 20' in a straight line toward target, attack at +2, then deal double damage if the monster has natural weapons suited for charging
- Charge attack designator on the specific attack type in the monster's routine (e.g., horn attack charges but bite does not)
- Standard charge penalties still apply: +2 to be hit until next action

### 2.16 Dive Attack

**Source:** `le_monster_characteristics_stats` → `dive` special attack, `le_monster_creation` (ability roll 20-23, second result).

**Hook:** Flying creature swoops down for double damage and potential grab.

| Effect | Representative Monsters |
|---|---|
| Dive + grab (talon) | Giant eagle, roc, large dragons |
| Dive + grab (claw) | Dragons (clutching claws special ability) |
| Dive only | Stirge, giant hawk |

**System requirements:**
- Only flying monsters with talons or claws can dive
- Target must be in open terrain (no low ceiling, dense forest canopy, etc.)
- Dive deals double damage
- If both talon/claw attacks hit: monster may grab target if target is smaller than the monster
- Grab save: save vs. Paralysis to avoid being grabbed; modifier based on size difference (-4 for dragon-sized, -6/-8 or greater for much larger; some monsters allow no save)
- Grabbed state: target is helpless and takes automatic damage each round; can attempt save vs. Paralysis each round to escape
- Carried off: grabbed creature may be carried aloft; falls if it escapes, monster releases, or monster is killed

### 2.17 Magic Resistance

**Source:** `le_monster_characteristics_stats` → `magic_resistance`, `le_monster_creation` (ability roll 44).

**Hook:** Percentage-based chance to negate spells and spell-like effects, modified by caster level.

| MR Calculation | Representative Monsters |
|---|---|
| Explicit listed value | Rakshasa, certain demons |
| Formula: 20 - HD | Custom monsters per `le_monster_creation` |

**System requirements:**
- Pre-spell-resolution check: when a spell or qualifying spell-like effect targets the creature, roll 1d20; if the roll ≥ the listed MR value, the spell is negated
- Caster level adjustment: the listed MR assumes a 7th-level caster; -1 to the target for each caster level above 7, +1 for each level below 7
- Qualifying effects: effects that duplicate spells, or are resisted with saves vs. Spells or Staffs & Wands
- Non-qualifying effects: effects resisted with Poison & Death, Blast & Breath, or Paralysis & Petrification do NOT trigger MR unless they also duplicate a spell
- MR check happens before the saving throw (if MR succeeds, no save is needed)

### 2.18 Normal Weapon Immunity

**Source:** `le_monster_creation` (immunity roll 11: all nonmagical weapons), various monster entries.

**Hook:** Monster cannot be damaged by non-magical weapons. Silver weapons may deal half or full damage for some creatures.

| Tier | Representative Monsters |
|---|---|
| Immune to non-magical weapons (magical weapons deal full damage) | Gargoyle, spectre, djinni/efreeti, lycanthropes in animal form |
| Immune to non-magical weapons; silver deals half damage | Wraith, wight |
| Immune to non-magical weapons; silver deals full damage | Werewolf and other lycanthropes (silver bypasses immunity) |
| Immune to weapons below +N | Some unique/powerful monsters |

**System requirements:**
- Weapon material/enchantment check on damage application: if the monster has `immunity_normal_weapons`, check the attacking weapon's properties
- Silver weapon flag on weapon data
- Magical weapon bonus on weapon data
- Damage routing: non-magical → 0 damage; silver → half or full per monster; magical → full damage
- Interaction with Protection from Normal Weapons spell (same hook, different source)
- Enchanted creature flag: all creatures immune to normal weapons are classified as enchanted creatures for Protection from Evil and Dispel Evil purposes

### 2.19 Incorporeal

**Source:** `le_monster_creation` (ability roll 38).

**Hook:** Monster is formless and weightless; weapon immunity tier depends on HD.

| HD Threshold | Weapon Requirement | Representative Monsters |
|---|---|---|
| ≤ 4 HD | Silver weapons or magical | Shadow |
| ≥ 5 HD | Magical weapons only | Spectre, wraith |

**System requirements:**
- Incorporeal flag: monster cannot interact with physical objects except through its own attacks/abilities
- Movement through solid objects (may move through walls, floors — no physical collision)
- Weapon immunity as per §2.18 with HD-based threshold

### 2.20 Berserk

**Source:** `le_monster_creation` (ability roll 05), berserker entry.

**Hook:** Permanent or triggered combat fury state with attack bonus, morale override, and fear immunity.

| Trigger | Representative Monsters |
|---|---|
| Always active | Berserker human fighters |
| Rage trigger (combat start) | Wereboar |

**System requirements:**
- Berserk state: +2 to attack throws, morale becomes +4 (never retreats), immune to fear effects
- No voluntary withdrawal while berserk
- State persistence: until all enemies are down or the creature is killed/incapacitated
- Cross-reference: the Berserkergang proficiency (§1.6 in `proficiency_system_map.md`) grants a similar state to PCs, with the addition of -2 AC penalty

### 2.21 Spellcasting

**Source:** `le_monster_creation` (ability roll 69-71), dragon entries, lich entries, NPC monster entries.

**Hook:** Monster casts spells as a classed caster at a specified level.

| Caster Type | Representative Monsters |
|---|---|
| Mage (arcane) | Lich, some dragon variants, NPC mage monsters |
| Cleric (divine) | Beastman shamans/witch doctors, NPC cleric monsters |
| Variable | Dragon variants (specific spells per age category) |

**System requirements:**
- Spell slot assignment: monster has spell slots as a caster of the specified class and level (max 14th)
- Spell selection: pre-assigned spell list per monster entry (for named/cataloged monsters) or generated by tactical AI (for procedurally generated NPC casters)
- Casting in combat: follows normal spellcasting rules (declaration, interruption, concentration)
- This is the primary divergence point between F-1 (basic combat) and O-2 (tactical AI): F-1 implements the spell-slot and casting pipeline; O-2 implements intelligent spell selection and timing
- `spellcasting_timing` behavior tag from `gdd_combat_behavior_tags.md` governs when the AI chooses to cast vs. attack

### 2.22 Spell-Like Abilities

**Source:** `le_monster_creation` (ability roll 72-75), various monster entries.

**Hook:** Innate abilities that replicate spell effects without using spell slots.

| Usage Pattern | Representative Monsters |
|---|---|
| At will | Djinni (create illusion, become invisible), efreeti (wall of fire at will) |
| N/day | Blink dog (teleport 1/round), medusa (no spell-like abilities in standard entry) |
| On death/trigger | Certain unique creatures |

**System requirements:**
- Spell-like ability as a separate list from spell slots: each entry specifies the spell effect replicated and the usage frequency (at will, N/day, N/turn, etc.)
- No spell slot consumption: spell-like abilities do not use or require spell slots
- Usage tracking: per-day and per-encounter limits
- Spell-like abilities ARE subject to magic resistance (they duplicate spells or use Spells/Staffs & Wands saves)
- Spell-like abilities are NOT subject to interruption as spellcasting (they are innate, not cast with a formula)

### 2.23 Stealth / Surprise Modifiers

**Source:** `le_monster_creation` (ability roll 76-80), various monster entries.

**Hook:** Monsters that impose penalties on opponents' surprise rolls.

| Penalty | Representative Monsters |
|---|---|
| -1 surprise (any terrain) | Bugbear |
| -1 surprise (natural habitat) | Various ambush predators |
| -2 surprise (natural habitat) | Weretiger, panther |

**System requirements:**
- Surprise roll modifier on the opponent (not the monster) when encountering this monster
- Terrain-conditional modifier: some monsters impose surprise penalty only in their natural habitat
- Integration with the surprise system in combat initialization

### 2.24 Grab / Constriction / Hug

**Source:** `le_monster_creation` (ability roll 24-25 for grab, 26-31 for hug).

**Hook:** On-hit grapple with automatic subsequent damage.

| Type | Representative Monsters |
|---|---|
| Grab (save or held) | Roper (tentacle), giant squid/octopus |
| Hug (bonus damage on multi-hit) | Werebear (crushing hug: 2d8 if both claws hit), owl bear |
| Constriction (ongoing) | Giant snake (python), giant squid |

**System requirements:**
- Grab: victim saves vs. Paralysis or is grabbed; grabbed victims are helpless until escape (save vs. Paralysis on their turn)
- Hug: if monster hits with more than half its attacks in a round, bonus damage is dealt (size-scaled: man-sized 2d6, large 2d8, huge 2d10, gigantic 2d12, colossal 2d20)
- Constriction: ongoing damage variant where grab transitions to per-round auto-damage
- Other combatants gain +4 to attack throws against grabbed targets; thieves may backstab

### 2.25 Splitting

**Source:** `le_monster_characteristics_stats` (asterisk-qualifying ability: splitting).

**Hook:** Monster divides into two or more smaller entities when hit by specific damage types.

| Trigger | Representative Monsters |
|---|---|
| Edged/lightning damage | Black pudding (splits into two; each retains full HD) |
| Piercing damage | Ochre jelly |

**System requirements:**
- Entity splitting: on hit by the specified damage type, the monster entity splits into N new entities
- Split entity stats: per-monster (black pudding: each half retains original HD and damage output)
- Combat map placement: new entities placed adjacent to original position
- Maximum split count: per-monster specification
- Entity tracking: each split entity is a separate combat entity with independent HP and actions

### 2.26 Summoning

**Source:** `le_monster_characteristics_stats` (asterisk-qualifying ability: summoning other creatures), various monster entries.

**Hook:** Monster calls additional creatures to the battlefield.

| Method | Representative Monsters |
|---|---|
| Summon kindred animals | All lycanthropes (summon 1d2 of their animal type; arrive in 1d4 rounds) |
| Summon bat/rat/wolf | Vampire (3d6 bats, 3d6 rats, or 2d4 wolves) |
| Summoning horn/cry | Some beastman leaders |

**System requirements:**
- Summoning action: monster uses its action (or a special ability) to call reinforcements
- Arrival delay: summoned creatures arrive after a specified number of rounds
- Summoned creature entity placement: new entities added to the combat map at map edge or appropriate entry point
- Summoned creature stat blocks: use standard stat blocks for the summoned creature type
- Summoned creatures are separate combat entities, not under the summoner's direct control (they act as independent allies with their own behavior tags)
- Daily or encounter limit: per-monster specification

### 2.27 Invisibility

**Source:** `le_monster_creation` (ability roll 42-43).

**Hook:** Monster is naturally invisible and may act without becoming visible.

| Type | Representative Monsters |
|---|---|
| Permanent (attacks without revealing) | Invisible stalker |
| At-will toggle | Some spell-like ability users (djinni) |

**System requirements:**
- Invisible flag on entity: -4 to attack throws against the monster (standard invisibility penalty)
- Does NOT break on attack (unlike the invisibility spell, natural invisibility persists through combat)
- Detection: Detect Invisible spell, true seeing, blindsense/echolocation, Blind Fighting proficiency (reduces penalty from -4 to -2)
- LoS blocking: invisible creatures do not block line of sight for others

### 2.28 Initiative Override

**Source:** `le_monster_creation` (ability roll 40-41).

**Hook:** Monster always acts first in the initiative order.

| Scope | Representative Monsters |
|---|---|
| Always has initiative | Custom monsters per `le_monster_creation` |

**System requirements:**
- Initiative override flag: monster acts at the top of the initiative order regardless of initiative roll results
- Multiple initiative-override creatures: resolve ties between them normally (d6 roll)
- This does NOT override surprise (a surprised creature still loses its first round)

---

## 3. Movement Modes

Each mode requires a movement resolver that works on both the combat grid (diamond isometric) and the exploration/wilderness map (hex-based).

### 3.1 Land

Default movement mode. All monsters have land movement unless specified otherwise.

**System requirements:**
- Exploration rate (feet per turn) and combat rate (feet per round) stored as separate values
- Encumbrance: monster movement is generally not affected by encumbrance (monsters carry their own weight inherently), but weapon/treasure-carrying humanoid monsters may be
- Terrain multipliers apply during wilderness exploration (per `gdd-terrain-system`)

### 3.2 Flight

**Source:** `le_monster_characteristics_stats` (movement modes), `le_monster_creation` (ability roll 20-23), dragon and bird entries.

**Hook:** Aerial movement with ACKS-specific rules for dive attacks, altitude, and landing.

| Speed Tier | Representative Monsters |
|---|---|
| Slow (≤ 120'/round) | Gargoyle, stirge |
| Medium (120'–180'/round) | Wyvern, hippogriff, griffon |
| Fast (≥ 240'/round) | Dragon (240'), roc |

**System requirements:**
- Flight movement rate stored alongside land rate
- Altitude tracking on combat map (abstract tiers: ground, low, high — or specific feet if needed for spell ranges)
- Dive attack eligibility: only from altitude, only with talons/claws, only against targets in open terrain (§2.16)
- Landing requirement: flying creatures must land after extended flight (per-monster endurance if applicable) or when reduced below certain HP
- Charge in flight: flying creatures can charge in flight for double damage (same as ground charge rules)
- Engagement: flying creatures at altitude cannot be engaged in melee by ground creatures without reach weapons or spells
- Dispel-while-airborne: if flight is magical (spell or magic item) and dispelled, creature falls and takes falling damage

### 3.3 Swimming

**Hook:** Aquatic or semi-aquatic movement with underwater combat implications.

| Context | Representative Monsters |
|---|---|
| Aquatic only | Giant fish, sea serpent, mermen |
| Amphibious | Giant crab, giant crocodile, nixie |

**System requirements:**
- Swim movement rate stored separately
- Underwater combat: non-aquatic creatures fighting underwater suffer penalties (limited weapon options, no fire, restricted movement)
- Water Breathing spell interaction: allows underwater action without penalty for land creatures

### 3.4 Burrowing

**Hook:** Underground movement, potentially creating tunnels.

| Type | Representative Monsters |
|---|---|
| Tunnel-creating | Purple worm, ankheg |
| Earth-passing (no tunnel) | Earth elemental, xorn |

**System requirements:**
- Burrow movement rate
- Tunnel creation: some burrowers leave passable tunnels behind them; combat map may need to add new passable cells
- Surprise interaction: burrowing creatures may attack from below with surprise bonus
- Tracking: burrowing creatures below ground are not targetable by most attacks until they surface

### 3.5 Climbing / Web-Walking

**Hook:** Movement on vertical or inverted surfaces.

| Type | Representative Monsters |
|---|---|
| Wall climbing | Giant spider, giant gecko |
| Ceiling movement | Giant spider (web-walking) |

**System requirements:**
- Climb flag: creature can move on vertical surfaces and ceilings at its normal movement rate (or a specified climb rate)
- Combat implications: climbing creatures can attack from unexpected angles; may impose surprise penalties
- Web-walking: spiders can move freely on their own webs (not affected by web movement penalties)

---

## 4. Morale & Behavior Baseline

### 4.1 Morale Mechanics

**Source:** `acore_combat_and_wounds` → morale section.

**Hook:** 2d6 morale check system with triggers, modifiers, and outcome table.

**Morale scores:** Range from -6 (never fights) to +4 (fights to the death). Stored as an integer on the monster stat block. Null = never rolls morale.

**Morale check triggers (ACKS rules):**
1. First member of the monster's side killed in combat
2. Half of the monster's side killed or incapacitated
3. Both triggers in the same round: single morale roll at -2
4. Solo monster: rolls morale when reduced to half HP

**Morale check procedure:**
1. Roll 2d6
2. Add the monster's morale score
3. Add Judge-assigned circumstance modifiers (-2 to +2; not applied to morale -6 or +4)
4. Consult the Monster Morale Table

**Monster Morale Table:**

| Adjusted Roll | Result |
|---|---|
| 2 or less | **Retreat** — full retreat on next action |
| 3–5 | **Fighting Withdrawal** — withdraw until not pursued or 1d10 rounds pass; surrender if escape impossible |
| 6–8 | **Fight On** — continue fighting but do not pursue fleeing opponents |
| 9–11 | **Advance and Pursue** — fight offensively, pursue retreating characters |
| 12+ | **Victory or Death** — fight for the rest of the battle without further morale rolls, pursue fleeing opponents |

**System requirements:**
- Morale check trigger detection: combat system must track casualty count per side and detect threshold crossings (first death, half casualties, solo at half HP)
- Morale roll resolution: 2d6 + morale score + modifiers → table lookup
- Outcome application: set the monster group's behavior state (retreat, fighting withdrawal, fight on, advance, victory-or-death)
- Victory-or-death flag: once triggered, no further morale rolls for that group for the remainder of the battle
- Morale modifier from proficiencies: Command (+2 morale for led troops from `proficiency_system_map.md`), Leadership (+1 max henchman — affects henchman morale separately)
- Chieftain/leader alive modifier: many monster entries grant +1 or +2 to morale rolls while a leader is alive

### 4.2 Morale Exemptions

**Hook:** Some creatures never roll morale.

| Exemption Reason | Representative Monsters |
|---|---|
| Morale N/A (mindless) | Skeletons, zombies, all constructs, mindless vermin |
| Morale +4 (fights to the death) | Remorhaz, some undead (vampires in certain contexts), berserkers |
| Controlled (obey controller) | Summoned creatures, animated dead under caster command |
| Special condition | Trolls: morale drops to 0 when confronted by fire/acid |

**System requirements:**
- Null morale check: if `morale` is null, skip all morale checks
- Morale +4 bypass: if `morale` is +4, skip all morale checks (creature always fights to the death)
- Controlled creature flag: morale determined by controller, not by the creature's own score
- Conditional morale override: some monsters have morale modifiers triggered by specific conditions (trolls + fire/acid)

### 4.3 Behavior Tag Integration

The `morale_style` tag from `gdd_combat_behavior_tags.md` supplements but does NOT replace the morale score and morale check rules. The relationship:

- **Morale score** determines the numeric modifier to the 2d6 roll (ACKS rule, sacred)
- **Morale_style tag** influences how the AI interprets and acts on morale outcomes beyond the strict table result (project-designed, improvable):
  - `steadfast`: holds position longer, less likely to surrender even in Fighting Withdrawal result
  - `normal`: follows morale table outcomes as written
  - `fragile`: more aggressive retreat behavior, more likely to surrender, less likely to re-engage

---

## 5. Creature Type Tags

A classification system for monster-spell, monster-proficiency, and monster-system interactions. These are the canonical ACKS monster types from `le_monster_characteristics_stats` and `le_monster_creation`.

### 5.1 Type Definitions

| Type | Spell Interactions | Immunities | Other Flags |
|---|---|---|---|
| **animal** | Affected by Charm Animal, Speak with Animals. Also vulnerable to Charm Monster, Hold Monster. | (none inherent) | Beast Friendship proficiency applies. Animal Training proficiency applies. |
| **beastman** | (no special spell interactions beyond those granted by other types) | (none inherent) | Goblin-Slaying proficiency targets this type (if goblinoid sub-type). |
| **construct** | Counts as enchanted creature for Protection from Evil and Dispel Evil. | sleep, charm, hold, gas, poison | Morale N/A for mindless constructs. |
| **enchanted_creature** | Kept at bay by Protection from Evil. Destroyed or driven off by Dispel Evil. | (none inherent from this type) | All constructs, summoned creatures, undead, and creatures immune to normal weapons are enchanted creatures. |
| **fantastic_creature** | NOT affected by Charm Person or Hold Person. Vulnerable to Charm Monster and Hold Monster. | (none inherent) | |
| **giant_humanoid** | NOT affected by Charm Person or Hold Person. Vulnerable to Charm Monster and Hold Monster. | (none inherent) | 5+ HD and larger than humanoid. |
| **humanoid** | Vulnerable to Charm Person, Hold Person, Sleep (if ≤4+1 HD). | (none inherent) | ≤ 4 HD and no larger than ogre. Humans and demi-humans remain humanoid even above level 4. |
| **ooze** | (varies per ooze) | sleep, charm, hold | Different oozes have additional individual immunities. |
| **summoned_creature** | Kept at bay by Protection from Evil. Destroyed or driven off by Dispel Evil. Chaotic summoned creatures are inherently evil for Detect Evil and Protection from Evil. | (none inherent from this type) | |
| **undead** | All undead are inherently evil for Detect Evil and Protection from Evil. Subject to Turn Undead. | sleep, charm, hold, gas, poison | Most undead are silent when moving (stealth interaction). |
| **vermin** | NOT affected by Charm Animal or other animal-targeting spells. Vulnerable to Charm Monster and Hold Monster. | (none inherent) | Vermin-Slaying proficiency applies (+1 save vs. special attacks). |

### 5.2 Multi-Type Rules

A creature may belong to multiple types. Combined immunities stack. Type-specific spell interactions all apply. Examples:
- Skeletons and zombies: **undead** + **construct** (all immunities from both)
- Ghoul: **undead** only (not construct — ghouls retain some will)
- Living statue: **construct** + **enchanted_creature**

### 5.3 Tag-to-System Bridge

These type tags are the mechanical bridge between the monster catalog and the proficiency/spell hook systems:

| System Hook | Type Tag Required |
|---|---|
| Turn Undead | `undead` — HD-based turning difficulty |
| Goblin-Slaying proficiency (+1/+2/+3 attack) | `beastman` with sub-tag `goblinoid` (kobold, goblin, orc, gnoll, hobgoblin, bugbear, ogre, troll, giant) |
| Kin-Slaying proficiency (+1/+2/+3 attack) | `humanoid` with sub-tag `kin` (human, elf, dwarf, halfling, gnome, Nobiran) |
| Protection from Evil (keep at bay) | `enchanted_creature` |
| Dispel Evil (destroy/drive off) | `enchanted_creature` |
| Detect Evil (glow) | `undead` (inherent evil), `summoned_creature` with chaotic alignment (inherent evil) |
| Charm Person / Hold Person | `humanoid` only |
| Charm Monster / Hold Monster | All types EXCEPT those immune to charm/hold by type (constructs, oozes, undead) |
| Charm Animal / Speak with Animals | `animal` only |
| Beast Friendship proficiency | `animal` |
| Vermin-Slaying proficiency | `vermin` |

### 5.4 Sub-Tags

Some proficiency and spell hooks require finer-grained classification than the base ACKS types. These sub-tags are project-designed additions for hook routing:

| Sub-Tag | Parent Type(s) | Purpose | Members |
|---|---|---|---|
| `goblinoid` | beastman, giant_humanoid | Goblin-Slaying targeting | Kobold, goblin, orc, gnoll, hobgoblin, bugbear, ogre, troll, giant (and hill giant, stone giant, etc.) |
| `kin` | humanoid | Kin-Slaying targeting | Human, elf, dwarf, halfling, gnome, Nobiran |
| `dragon` | fantastic_creature | Dragon-specific interactions (fear aura by age, breath weapon) | All dragon variants |
| `lycanthrope` | fantastic_creature, enchanted_creature | Lycanthropy disease, wolfsbane vulnerability, silver weapon interaction | Werewolf, wererat, wereboar, weretiger, werebear |
| `elemental` | summoned_creature | Conjure Elemental interactions, elemental immunity | Fire/water/earth/air elementals |
| `demon` | summoned_creature, enchanted_creature | Holy Water damage, Dispel Evil interaction | Cacodemon, balor, etc. |
| `insect_swarm` | vermin | Swarm rules, area-effect-only vulnerability | Insect plague swarms, ant swarms |
| `prehistoric` | animal | No special mechanical effect; classification/narration tag | Dinosaurs, pteranodons |

---

## 6. Cross-Reference Table

When building system X, these monster abilities require hooks. Organized by consuming system.

### 6.1 Combat & Conditions (F-1)

The heaviest consumer. Nearly every special ability in §2 touches combat.

| Ability Category | §Ref | Hook Summary |
|---|---|---|
| Attack routines | §1.3 | Iterate attack array, resolve each attack in sequence |
| Breath weapons | §2.1 | AoE typed damage, save for half, usage tracking |
| Gaze attacks | §2.2 | Gaze resolution procedure (avert/mirror/meet), save-or-condition |
| Energy drain | §2.3 | On-hit level removal, no save, reverse level-up on CharacterData |
| Poison | §2.4 | Save-or-die rider on attack, save modifiers, onset delay |
| Paralysis | §2.5 | Save-or-paralyze rider, condition application, duration tracking |
| Petrification | §2.6 | Save-or-petrify, condition application, stone-to-flesh reversal |
| Charm | §2.7 | Save-or-charm, monster charm vs. spell charm distinction |
| Fear | §2.8 | AoE save-or-condition, HD-tiered effects |
| Regeneration | §2.9 | Per-round healing, damage-type exceptions |
| Swallow whole | §2.11 | Engulf state, per-round internal damage, escape mechanics |
| Ongoing damage | §2.12 | Locked-on auto-damage, end conditions |
| Acid | §2.13 | Equipment destruction, persistent damage |
| Trample | §2.14 | Alternate attack routine, size-based bonus |
| Charge | §2.15 | Double damage on charge with natural weapons |
| Dive attack | §2.16 | Double damage from flight, grab mechanic |
| Magic resistance | §2.17 | Pre-spell check with caster-level modifier |
| Weapon immunity | §2.18 | Damage routing by weapon material/enchantment |
| Incorporeal | §2.19 | Physical interaction limits, weapon immunity |
| Berserk | §2.20 | Attack bonus, morale override, fear immunity |
| Spellcasting | §2.21 | Spell slot pipeline, casting in combat |
| Spell-like abilities | §2.22 | Innate spell effects without slots |
| Stealth | §2.23 | Surprise roll modifier on opponents |
| Grab/hug | §2.24 | Grapple state, auto-damage, escape saves |
| Splitting | §2.25 | Entity division on specific damage types |
| Summoning | §2.26 | Mid-combat reinforcement spawning |
| Invisibility | §2.27 | Persistent invisible state, detection interactions |
| Initiative override | §2.28 | Always-first initiative flag |
| Morale | §4.1 | 2d6 morale check, trigger detection, outcome table |
| Movement modes | §3 | Flight altitude, burrowing, swimming, climbing |

### 6.2 Session Runner (E-2)

| Monster Data | §Ref | Hook Summary |
|---|---|---|
| Number appearing | §1.5 | Dungeon/wilderness encounter number generation |
| Percent in lair | §1.5 | Lair probability check on encounter |
| Terrain affinity | §1.5 | Encounter table filtering by terrain type |

### 6.3 Treasure System

| Monster Data | §Ref | Hook Summary |
|---|---|---|
| Treasure type | §1.5 | Letter code → treasure table roll |
| Treasure-on-victims | §2.6 | Petrified victim treasure accessibility |
| Treasure-in-belly | §2.11 | Swallowed creature inventory retrieval |

### 6.4 Character Data & State (C-1)

| Ability | §Ref | Hook Summary |
|---|---|---|
| Energy drain | §2.3 | Reverse level-up procedure on CharacterData |
| Lycanthropy | §2.10 | Disease contraction, transformation timer, species restriction |
| Spawn creation | §2.10 | Corpse-to-undead timer, NPC entity creation |

### 6.5 Domain Play (H-1)

| Monster Data | §Ref | Hook Summary |
|---|---|---|
| Wilderness lair density | §1.5 | Per `le_wilderness_lair_rules`, lair counts per hex |
| Domain encounter tables | §1.5 | Terrain-filtered monster lists for domain-level random encounters |
| Beastman populations | §5.4 | Goblinoid/beastman cultures for clanhold encounters |

### 6.6 Dungeon Stocking

| Monster Data | §Ref | Hook Summary |
|---|---|---|
| HD-to-dungeon-level mapping | §1.2 | 1 HD → level 1, 2–3 → level 2, 4–5 → level 3, etc. |
| Number appearing (dungeon) | §1.5 | Outside-lair and in-lair quantities |
| Lair composition | §1.5 | Leaders, females, young, bodyguards per monster entry |

### 6.7 Encounter Table Builder (L-4)

| Monster Data | §Ref | Hook Summary |
|---|---|---|
| Terrain affinity | §1.5 | Which monsters appear in which terrain types |
| Frequency weight | §1.5 | Encounter probability (from stocking rules tables) |
| HD range | §1.2 | Level-appropriate encounter filtering |

### 6.8 NPC Systems

| Monster Interaction | §Ref | Hook Summary |
|---|---|---|
| Intelligent monster reactions | §1.1 | Intelligence category determines reaction roll eligibility |
| Monster charm | §2.7 | Charmed NPCs act under monster control |

### 6.9 Monster Training System

| Monster Data | Source | Hook Summary |
|---|---|---|
| Trainability | `le_monster_training_rules` | Species trainability, training time, handler requirements |
| Monster parts | `le_monster_parts` | Harvestable components, proficiency requirements for harvesting |

---

## 7. F-1 Minimum Viable Set

The practical scoping call: which ability hooks are needed for a basic combat test vs. which can be deferred.

### 7.1 Required for F-1 (Basic Combat)

These abilities must be fully functional before combat can be tested end-to-end:

| Ability | Reason |
|---|---|
| **Multi-attack routines** (§1.3) | Every monster uses these. Cannot resolve a combat round without iterating the attack array. |
| **Morale system** (§4.1) | Combat cannot end naturally without morale checks. Core to every encounter. |
| **Basic damage types** (DamageTypes registry) | Already required by spell system. Monsters need typed damage for resistance/immunity routing. |
| **Creature type immunities** (§5.1) | Undead immune to sleep/charm/hold/poison; construct same. Without these, spells resolve incorrectly against half the monster catalog. |
| **Weapon immunity check** (§2.18) | Gargoyles, lycanthropes, wraiths, and many mid-level monsters are immune to normal weapons. Without this check, these encounters are trivially easy and incorrect. |
| **Poison** (§2.4) | The simplest save-or-consequence effect. Giant spiders are a level-1 dungeon encounter. Save-or-die must work. |
| **Paralysis** (§2.5) | Ghouls are a level-2 encounter staple. Save-or-paralyze must work, including the paralyzed condition and the Cure Light Wounds interaction. |
| **Movement modes — land** (§3.1) | All monsters need basic movement on the combat grid. |

### 7.2 Implement If Time Permits During F-1

These are high-value but can be stubbed initially:

| Ability | Stub Strategy |
|---|---|
| **Breath weapons** (§2.1) | Stub: resolve as single-target typed damage (skip area-of-effect targeting). Dragons are not a level-1 encounter. |
| **Fear aura** (§2.8) | Stub: skip HD-tiered resolution; apply a flat -1 attack penalty on failed save. Mummies and dragons are higher-level encounters. |
| **Regeneration** (§2.9) | Stub: apply per-round healing without damage-type exception check. Trolls are level 3-4 encounters. |
| **Charge / dive** (§2.15, §2.16) | Stub: resolve as normal melee attack without double damage. |
| **Flight** (§3.2) | Stub: treat as ground movement without altitude. Flying creatures can still participate in combat on the ground plane. |

### 7.3 Defer to Post-F-1

These abilities are complex, affect few low-level encounters, and can be added without structural changes:

| Ability | Deferral Reason |
|---|---|
| **Energy drain** (§2.3) | Wights are the earliest energy-drain encounter (level 3 dungeon). Requires the full reverse-level-up pipeline on CharacterData. Complex and testable independently. |
| **Gaze attacks** (§2.2) | Basilisks are level 5. Full gaze resolution (avert/mirror/meet) is a distinct subsystem. |
| **Petrification** (§2.6) | Cockatrice is level 4, basilisk level 5. Petrified condition is complex (stone structure rules). |
| **Swallow whole** (§2.11) | Purple worm is level 6. Requires engulfed state, internal combat, digestion timer. |
| **Charm (monster)** (§2.7) | Vampire is level 5+. Monster charm has distinct rules from spell charm. |
| **Infectious / spawn** (§2.10) | Only matters if the victim actually dies to the specific monster. Post-combat resolution. |
| **Splitting** (§2.25) | Black pudding is level 5+. Entity splitting is an unusual mechanic with no other use. |
| **Spellcasting** (§2.21) | Monster spellcasting depends on the spell system being fully built (Phase E). Stub with "no spells" for F-1 testing. |
| **Spell-like abilities** (§2.22) | Same dependency as spellcasting. |
| **Magic resistance** (§2.17) | Rare ability. Only matters when spells are being cast at the monster. Post-Phase E. |
| **Incorporeal** (§2.19) | Spectre/wraith are level 4+. Incorporeal movement through walls is a distinct subsystem. |
| **Summoning** (§2.26) | Mid-combat entity creation. Complex map placement and initiative insertion. |
| **Invisibility** (§2.27) | Invisible stalker is a special encounter. Detection subsystem interactions needed. |
| **Initiative override** (§2.28) | Rare ability. Can be added as a simple flag check later. |
| **Burrowing** (§3.4) | Purple worm / ankheg. Tunnel creation on combat map is complex. |
| **Swimming combat** (§3.3) | Underwater combat has its own penalty rules. Edge case. |

---

## Build Agent Implementation Notes

### Hook Pattern

Each monster ability resolves to one of these patterns (same taxonomy as `spell_system_map.md` and `proficiency_system_map.md`):

- **Modifier**: Numeric adjustment to attack throws, damage, AC, saves, initiative, surprise rolls
- **Flag**: Boolean state on a creature (invisible, incorporeal, berserk, regenerating, immune_normal_weapons, immune_sleep, etc.)
- **Condition**: Applied via ConditionCatalog (paralyzed, petrified, charmed, frightened, nauseated)
- **Alternate routine**: Monster chooses between attack routines (melee vs. breath weapon)
- **Entity spawn**: New combat entity created mid-battle (splitting, summoning, undead spawn creation)
- **State change**: Target creature state altered (energy drain → level reduction, lycanthropy → disease timer)
- **Ongoing effect**: Per-round damage or healing tracked by ActiveEffectTracker (regeneration, ongoing acid, blood drain, swallowed-creature damage)

### Monster Catalog Construction Order

1. **Define the stat block schema** (§1) — the data model for every monster entry
2. **Implement creature type tags** (§5) — required for spell and proficiency interaction routing
3. **Build F-1 minimum viable ability hooks** (§7.1) — multi-attack, morale, poison, paralysis, weapon immunity, creature type immunities
4. **Populate the JSON catalog** (F-0) — extract monster data from XML into the schema, one catalog file at a time
5. **Add deferred ability hooks** (§7.3) — as the systems they depend on become available

### What This Document Does NOT Contain

- **Individual monster stat blocks**: Those are in the XML catalogs now and will be in the JSON catalog (F-0) after extraction.
- **Tactical AI decision trees**: Those are in `gdd_combat_behavior_tags.md` (F-1 baseline) and the O-2 build item (Tier 2 tactical AI).
- **Encounter table weights and terrain-specific encounter lists**: Those are in `acore-monster-stocking-rules` and will be in the L-4 encounter table builder.
- **Monster creation/customization procedures**: Those are in `le_monster_creation` (the rules for Judges creating new monsters).
- **Monster training and harvesting**: Those are in `le_monster_training_rules` and `le_monster_parts`.

---

## Revision History

- **2026-04-02:** Initial draft. Full stat block schema, 28-entry special ability taxonomy, movement modes, morale baseline, creature type tags with sub-tags, cross-reference table by consuming system, F-1 minimum viable scoping.
