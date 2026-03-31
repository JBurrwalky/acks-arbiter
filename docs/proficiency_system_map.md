# Proficiency-to-System Map

Maps proficiencies to the game systems they mechanically affect so the build agent can implement proficiency-effect hooks at system-build time.

**Authority:** Project-designed document (GDD-tier). Proficiency details derive from sacred XML rule summaries (`acore_proficiencies_rules_and_catalog`, `pc_proficiencies_catalog`, `ax_thief_skill_update`). System names match `rule_system_map.md`.

**Scope:** All proficiencies from ACore general and class lists, PC additional proficiencies, and Axioms thief skill updates. Class abilities that function identically to proficiencies (e.g., Bladedancer's Diplomacy-equivalent) are noted but not independently listed — the class data model handles those.

**How to use:** When building system X, load this section to see which proficiency effects that system must support. Each entry describes the *hook* the system needs. Individual proficiency bindings happen during character data model / proficiency system construction.

**Companion document:** `spell_system_map.md` (same structure, for spells).

---

## Legend

- **Hook** = the interface or capability the system must expose
- **(G)** = general proficiency (available to all characters)
- **(C)** = class proficiency only
- **(P)** = progression/ranked proficiency (has ranks 1/2/3 or level-scaling bonuses)
- Multiple selections noted where the proficiency can be taken more than once

---

## 1. Combat & Conditions

The most proficiency-dense system. Most class proficiencies exist to modify combat behavior.

### 1.1 Attack Throw Modifiers

**Hook:** Apply conditional bonuses/penalties to attack throws.

| Proficiency | Effect |
|---|---|
| Fighting Style (C) | +1 attack throw for missile, single weapon, or two-weapon style (one style active per round) |
| Weapon Finesse (C) | Use DEX modifier instead of STR for one-handed melee attack throws |
| Precise Shooting (C)(P) | Enables missile fire into melee at -4; each additional selection reduces penalty by 2 |
| Goblin-Slaying (C)(P) | +1/+2/+3 attack vs kobolds, goblins, orcs, gnolls, hobgoblins, bugbears, ogres, trolls, giants (at levels 1/7/13) |
| Kin-Slaying (C)(P) | +1/+2/+3 attack vs humans, elves, dwarves, halflings, gnomes, Nobiran (at levels 1/7/13) |
| Ambushing (C) | +4 attack throw when attacking with surprise |
| Sniping (C) | May backstab/ambush with ranged weapons at short range |

**System requirements:**
- Conditional attack throw modifier system (by weapon style, target type, situation)
- "Into melee" missile fire gating (blocked without Precise Shooting)
- Creature-type tag matching for Goblin-Slaying / Kin-Slaying
- Surprise-state check for Ambushing bonus
- DEX-for-STR substitution flag on attack throws

### 1.2 Damage Modifiers

**Hook:** Apply conditional bonuses to damage rolls.

| Proficiency | Effect |
|---|---|
| Fighting Style — Two-handed (C) | +1 damage with two-handed weapons |
| Weapon Focus (C) | Natural 20 deals double damage with chosen weapon category |
| Ambushing (C) | Double damage when attacking with surprise |

**System requirements:**
- Weapon category registry (axes; maces/flails/hammers; swords/daggers; bows/crossbows; slings/thrown; spears/polearms)
- Natural-20 detection for Weapon Focus double damage
- Surprise-state double damage for Ambushing

### 1.3 Armor Class Modifiers

**Hook:** Apply conditional AC bonuses.

| Proficiency | Effect |
|---|---|
| Fighting Style — Weapon and shield (C) | +1 AC |
| Swashbuckling (C)(P) | +1/+2/+3 AC when wearing leather or less and free to move (at levels 1/7/13) |
| Armor Training (C) | May wear armor up to 2 points heavier than class allows (does not enable spellcasting or thief skills in heavy armor) |

**System requirements:**
- Armor weight check for Swashbuckling (leather or lighter + unencumbered)
- Class armor permission override for Armor Training (shift permitted armor ceiling by 2)

### 1.4 Initiative & Surprise

**Hook:** Modify initiative rolls and surprise checks.

| Proficiency | Effect |
|---|---|
| Combat Reflexes (C) | +1 initiative, +1 surprise (does not apply when casting spells) |
| Alertness (C) | +4 hear noises, +4 detect secret doors; notice secret doors on casual 18+; +1 avoid surprise |
| Fighting Style — Pole weapon (C) | +1 initiative with pole weapons |

**System requirements:**
- Initiative modifier stack from proficiencies
- Surprise modifier stack (both granting and denying surprise)
- Spellcasting-state check (Combat Reflexes disabled while casting)

### 1.5 Combat Maneuvers

**Hook:** Enable and improve special combat actions.

| Proficiency | Effect |
|---|---|
| Combat Trickery (C) | Choose one maneuver (Disarm, Force Back, Incapacitate, Knock Down, Overrun, Sunder, Wrestle): -2 to normal attack penalty, -2 on opponent's save to resist |
| Acrobatics (C) | Tumble behind opponent (proficiency throw 20+ minus level); success grants +2 attack, no shield benefit for target; backstab-eligible characters get full backstab |
| Dungeon Bashing (C) | +4 on throws to force open doors and brute-strength acts |
| Unarmed Fighting (C) | Brawling deals lethal damage; can punch metal armor without self-damage |

**System requirements:**
- Combat maneuver system with per-maneuver attack penalty and opponent save
- Proficiency-modified penalty/save values
- Tumble action as alternative to normal movement (Acrobatics)
- Door-forcing throw modifier (Dungeon Bashing)

### 1.6 Defensive & Survival in Combat

**Hook:** Modify saves, grant immunities, enable tactical options.

| Proficiency | Effect |
|---|---|
| Divine Blessing (C) | +2 all saving throws |
| Divine Health (C) | Immune to all disease including magical (mummy rot, lycanthropy) |
| Illusion Resistance (C) | +4 saving throws to disbelieve magical illusions |
| Vermin-Slaying (C) | +1 saving throws vs vermin special attacks; identify vermin abilities on 11+ |
| Blind Fighting (C) | Attack invisible or unseen opponents at only -2 instead of -4 |
| Berserkergang (C) | Enter berserk rage: +2 attack, -2 AC, immune to fear; cannot retreat; ends when all enemies down or character incapacitated |
| Skirmishing (C) | Withdraw or retreat from melee without pre-declaring defensive movement |
| Endurance (G) | No rest required every 6 turns; can force march 1 + CON bonus days |
| Wakefulness (C) | Only 4 hours sleep needed per night |
| Running (C) | +30' base movement in chainmail or lighter |

**System requirements:**
- Global save modifier from Divine Blessing
- Disease immunity flag (Divine Health)
- Illusion-specific save bonus
- Blind Fighting: reduce invisible-opponent penalty from -4 to -2
- Berserk state: attack bonus, AC penalty, fear immunity, no-retreat flag, auto-end trigger
- Retreat-without-declaration flag (Skirmishing)
- Rest interval modification (Endurance: 6-turn rest skipped)
- Movement rate modifier (Running: +30' base)

### 1.7 Spell Interaction in Combat

**Hook:** Modify spellcasting behavior during combat.

| Proficiency | Effect |
|---|---|
| Battle Magic (C) | Damage spells deal +1 per die; save-or-die spells impose -2 on target saves |
| Elementalism (C) | Chosen element spells deal +1 per die, -2 target save; summoned elementals of type gain +1 hp/HD; Magic Missile can be typed |
| Quiet Magic (C) | Casting can only be detected by hear noise throw |
| Unflappable Casting (C) | If interrupted, lose spell but keep action (may move/attack); without this, interruption loses entire action |
| Contemplation (C) | After 1 hour meditation, regain 1 expended spell level (max once per day per spell level) |
| Transmogrification (C) | Polymorph spells as if 2 levels higher; targets suffer -2 save vs polymorph other |

**System requirements:**
- Per-die damage bonus for blast spells (Battle Magic, Elementalism)
- Save penalty for applicable spells
- Spell detection: Quiet Magic makes casting audible only on successful hear noise
- Interruption recovery: Unflappable Casting converts full-action-loss to spell-only-loss
- Spell slot recovery mechanic (Contemplation)
- Caster-level override for polymorph spells (Transmogrification)

---

## 2. Character Data & State

### 2.1 Character Creation & Class Selection

**Hook:** Modify class permissions and starting capabilities.

| Proficiency | Effect |
|---|---|
| Martial Training (C) | Add one weapon group to class permitted weapons |
| Armor Training (C) | Wear armor 2 points heavier than class allows |
| Apostasy (C) | Add 4 divine spells from outside deity's normal list to repertoire |
| Arcane Dabbling (C) | Attempt mage-only items: 18+ at level 1, improving by 2/level to minimum 3+ |
| Language (G) | Learn one additional language (speak, read, write per INT literacy rules) |

**System requirements:**
- Weapon permission expansion (Martial Training: add weapon group to class list)
- Armor ceiling override (Armor Training)
- Spell repertoire expansion outside normal lists (Apostasy)
- Magic item use throw for non-caster classes (Arcane Dabbling)
- Language list on character record

### 2.2 HP & Recovery

**Hook:** Modify healing rates and mortal wounds outcomes.

| Proficiency | Effect |
|---|---|
| Healing (G)(P) | Rank 1: diagnose disease 11+, patients heal +1d3 hp/day. Rank 2: neutralize poison/cure disease/cure light wounds on 18+ once/day/patient. Rank 3: same on 14+ including cure serious wounds. 3+ patients/day per selection |
| Laying on Hands (C) | Once/day heal 2 hp per level; additional selections grant extra uses |
| Animal Husbandry (G)(P) | Same as Healing but for animals; Rank 3 adds cure mortal wounds on 18+ |

**System requirements:**
- Natural healing rate modifier per caretaker (Healing rank 1: +1d3 hp/day)
- Non-magical condition cure throws (Healing rank 2+: neutralize poison, cure disease on proficiency throw)
- Per-day patient capacity tracking (3 base + 1 per additional Healing selection)
- Laying on Hands: daily use counter, scales with level
- Animal vs humanoid patient distinction

### 2.3 Familiar

**Hook:** Create and maintain a permanent companion entity.

| Proficiency | Effect |
|---|---|
| Familiar (C) | Gain magical animal companion: HD = half master's, INT = master's INT, same proficiency count, +1 master saves within 30'; if slain: master saves vs Death or takes familiar's max HP as damage; no replacement until level-up |

**System requirements:**
- Familiar entity: derived stat block (half master HD, master INT)
- Proximity-based save bonus (+1 within 30')
- Death penalty mechanic (save vs Death, HP damage)
- Replacement cooldown (next level-up)

---

## 3. NPC Systems (Reactions, Henchmen, Morale)

### 3.1 Reaction Roll Modifiers

**Hook:** Apply bonuses to NPC reaction rolls.

| Proficiency | Effect |
|---|---|
| Diplomacy (G) | +2 reaction rolls when attempting to parley |
| Intimidation (G) | +2 reaction rolls when threatening violence (target ≤5 HD or outnumbered/outranked) |
| Mystic Aura (C) | +2 reaction rolls to impress/intimidate; if result ≥12, targets act as charmed in presence |
| Seduction (G) | +2 reaction rolls with potentially attracted creatures |
| Bargaining (C) | +2 reaction rolls in commercial transactions (Venturer class) |
| Bribery (C) | Know who to bribe and how much; +2 reaction when offering bribes |

**System requirements:**
- Contextual reaction roll modifier (parley, threat, impression, seduction, commercial, bribe)
- Mystic Aura charm-like threshold (total reaction ≥12 → charmed-in-presence behavior)
- HD/power check for Intimidation eligibility

### 3.2 Henchman & Mercenary Morale

**Hook:** Modify henchman and mercenary morale scores.

| Proficiency | Effect |
|---|---|
| Command (C) | Henchmen and mercenaries gain +2 morale |
| Leadership (G) | May hire 1 extra henchman beyond CHA limit; domain base morale +1 |
| Manual of Arms (C)(P) | Train troops (light infantry in 1 month, etc.); each selection adds training capability; 60 soldiers per training period |
| Military Strategy (G)(P) | Recognize battles/generals 11+; forces gain +1 mass combat initiative per selection (max +3) |

**System requirements:**
- Morale modifier stack from proficiencies (Command: +2, Leadership: domain morale +1)
- Henchman cap modification (Leadership: +1 slot)
- Troop training pipeline (Manual of Arms: trainee type × duration × capacity)
- Mass combat initiative modifier (Military Strategy)

### 3.3 NPC Interaction Utility

**Hook:** Enable special interaction modes with NPCs.

| Proficiency | Effect |
|---|---|
| Lip Reading (G) | Read lips on 11+; follows normal eavesdropping rules for range and conditions |
| Mimicry (G) | Imitate animal calls and foreign accents on 11+ |
| Disguise (G) | Create disguise on 11+; intimates see through on 14+ + WIS modifier |
| Eavesdropping (C) | Hear noises as a thief of class level |

**System requirements:**
- Lip reading as alternative to hearing (within line of sight)
- Disguise identity layer on character (see also spell system §4.2)
- Eavesdrop throw using thief hear-noise progression

---

## 4. Dungeon Exploration

### 4.1 Dungeon Navigation & Detection

**Hook:** Modify dungeon exploration throw targets.

| Proficiency | Effect |
|---|---|
| Alertness (C) | +4 hear noises; +4 detect secret doors; notice secret doors on casual 18+ |
| Mapping (G) | Understand/make maps even if illiterate; interpret complex layouts on 11+ |
| Caving (C) | Detect false walls, hidden construction, sloped passages underground on 14+ (dwarven class abilities often duplicate or improve this) |
| Land Surveying (C) | Predict sinkholes, deadfalls, collapses on 11+ entering area; +4 dungeon cover throws |
| Trap Finding (C) | +2 find/remove trap throws; may find traps in 1 round at -4 instead of 1 turn |
| Cat Burglary (C) | +2 climb walls; +2 hear noise |
| Skulking (C) | +2 hide in shadows; +2 move silently |

**System requirements:**
- Proficiency throw modifier system on exploration actions (hear noise, detect secret doors, find traps, climb walls, hide, move silently)
- Casual secret door detection (Alertness: passive 18+ roll on room entry)
- Rapid trap-find option (Trap Finding: 1 round at -4 penalty)

### 4.2 Dungeon Physical Actions

**Hook:** Enable/modify physical actions in dungeons.

| Proficiency | Effect |
|---|---|
| Climbing (C) | Climb walls as thief of class level |
| Contortionism (C) | Escape bonds or slip through bars on 18+ per round |
| Dungeon Bashing (C) | +4 force doors |
| Lockpicking (C) | Open locks as thief of class level |
| Mountaineering (C) | Use gear to climb difficult surfaces; rig lines for others |

**System requirements:**
- Thief-skill-equivalent throws for non-thief classes (Climbing, Eavesdropping, Lockpicking)
- Contortionism as escape-from-restraint mechanic
- Door-force modifier

---

## 5. Wilderness & Hex Exploration

### 5.1 Wilderness Travel & Survival

**Hook:** Modify travel speed, getting-lost checks, and foraging.

| Proficiency | Effect |
|---|---|
| Navigation (G) | Use sun/stars for position; +4 avoid getting lost; can serve as ship navigator |
| Endurance (G) | Force march 1 + CON bonus extra days without penalty; no 6-turn rest needed |
| Running (C) | +30' base movement in chainmail or lighter |
| Survival (G) | Auto-forage for self in fertile areas; group foraging at +4 |
| Passing Without Trace (C) | Leave no tracks; cover 1 companion per 3 levels |
| Tracking (G)(P) | Track creatures on 11+ with circumstance modifiers; half speed while tracking |
| Naturalism (G) | Know plants, animals, edible/poisonous foods, healing herbs, unnatural danger signs on 11+ in familiar terrain |

**System requirements:**
- Getting-lost throw modifier (Navigation: +4)
- Force march duration extension (Endurance: 1 + CON bonus days)
- Base movement rate modifier (Running: +30')
- Foraging throw modifier (Survival: +4 for group, auto-success for self)
- Track-negation flag (Passing Without Trace)
- Tracking subsystem: base throw 11+, circumstance modifiers (creature count, ground, weather, time elapsed), half movement
- Terrain familiarity for Naturalism knowledge checks

### 5.2 Wilderness Traps & Animal Interaction

**Hook:** Enable wilderness-specific actions.

| Proficiency | Effect |
|---|---|
| Trapping (G) | Build pits, snares, deadfalls for up to elephant-size on 11+; detect/disable wilderness traps as thief of class level |
| Beast Friendship (C) | Wild animals react positively; +2 reaction from normal animals; may take animals as henchmen |
| Animal Training (G) | Train one animal type; tame in 1 month; teach tricks (2d4 max); additional selections for other types |
| Animal Husbandry (G)(P) | Diagnose/treat animal disease and wounds (see §2.2) |

**System requirements:**
- Wilderness trap placement and detection mechanics
- Animal reaction modifier (Beast Friendship: +2)
- Animal-as-henchman entity type
- Animal training pipeline (taming time, trick count, trick learning time)

---

## 6. Domain Play

### 6.1 Domain Administration & Morale

**Hook:** Modify domain morale and administration checks.

| Proficiency | Effect |
|---|---|
| Leadership (G) | Domain base morale +1 |
| Command (C) | Henchmen/mercenaries +2 morale (applies to domain garrison) |
| Theology (G) | Identify religious symbols/holy days automatically (own faith) or on 11+ (other faiths) |
| Diplomacy (G) | +2 reaction (applies to vassal/liege negotiations) |

**System requirements:**
- Domain morale base modifier from ruler proficiencies
- Garrison morale modifier
- Religious identification for domain religious events

### 6.2 Domain Construction & Economics

**Hook:** Enable or improve construction and economic activities.

| Proficiency | Effect |
|---|---|
| Engineering (G)(P) | Evaluate structures on 11+; each selection supervises 25,000gp construction; at rank 4 = engineer specialist |
| Siege Engineering (G)(P) | Rank 1: construct/place fieldworks, operate siege engines. Rank 2: also construct siege engines and towers |
| Craft (G)(P) | Rank 1: 10gp/month income. Rank 2: 20gp/month + 3 apprentices. Rank 3: 40gp/month + journeymen + apprentices. At rank 3 = craft specialist |
| Art (G)(P) | Same progression as Craft but for art forms |
| Profession (G)(P) | Rank 1: 25gp/month. Rank 2: 50gp/month. Rank 3: 100gp/month = specialist |
| Labor (G) | 3d4 gp/month; relevant interpretation on 11+ |

**System requirements:**
- Construction supervision capacity (Engineering: 25,000gp per selection)
- Specialist-equivalence flags at rank 3+ (engineer, craftsman, etc.)
- Income generation from proficiency rank (monthly gp by proficiency and rank)
- Siege engine operation/construction permission (Siege Engineering)

### 6.3 Military & Warfare

**Hook:** Affect army-scale operations.

| Proficiency | Effect |
|---|---|
| Military Strategy (G)(P) | +1 mass combat initiative per selection (max +3) |
| Manual of Arms (C)(P) | Train specific troop types (light infantry, heavy infantry, cavalry, bowmen, etc.) at specific timelines; 60 soldiers per period |
| Siege Engineering (G)(P) | Operate and construct siege equipment |
| Signaling (G) | Transmit messages between signaling specialists of same force/culture |
| Riding (G) | Control mount in combat; required for mounted combat |

**System requirements:**
- Mass combat initiative modifier
- Troop training system: trainee type depends on Manual of Arms rank + Riding + Weapon Focus combinations
- Signal communication range/capability between army units

---

## 7. Spells & Magic System

### 7.1 Magic Research & Identification

**Hook:** Enable or improve magic item and spell research.

| Proficiency | Effect |
|---|---|
| Magical Engineering (C)(P) | Rank 1: identify magic items, constructs, enchantments on 11+. Higher ranks: supervise magic item creation, construct automata. At rank 3 = magical engineer specialist |
| Alchemy (G)(P) | Rank 1: identify alchemical substances, potions, poisons on 11+. Rank 2: apothecary. Rank 3: alchemist |
| Loremastery (C) | Decipher obscure languages, codes, old maps, almanacs on 11+; identify the purpose of magic items on 11+; on throw of 1, cursed item appears normal |
| Dwarven Brewing (C) | Taste-identify potion/oil properties on 11+; +4 craft alcoholic beverages |
| Collegiate Wizardry (C) | +1 on spell research throws; +1 repertoire capacity; gain access to guilds |
| Sensing Power (C) | Detect spellcasters within 60' + estimate relative power; detect arcane magic used within 24 hours |
| Sensing Evil (C) | At will, detect evil as the spell within 60' (1 turn concentration) |

**System requirements:**
- Magic item identification throws (Magical Engineering, Loremastery, Alchemy, Dwarven Brewing)
- Spell research throw modifier (Collegiate Wizardry: +1)
- Repertoire capacity modifier (Collegiate Wizardry: +1 slot)
- Spellcaster detection (Sensing Power: range, relative power estimate, recent-use detection)
- Evil detection as proficiency-granted ability (Sensing Evil: functions as Detect Evil spell)

### 7.2 Codex & Scroll Authority (from `ax_codex_and_scroll_magic`)

**Hook:** Proficiency combinations serve as prerequisites for codex/scroll authority topics.

| Authority Domain | Required Proficiency Combination |
|---|---|
| Blast spells | Battle Magic + Elementalism + Military Strategy |
| Death/necromancy | Black Lore + 2 of (Loremastery, Knowledge (occult), Sensing Evil) |
| Detection spells | 3 of (Prophecy, Second Sight, Soothsaying, Sensing Evil, Sensing Power) |
| Elemental spells (per element) | Elementalism (type) + Battle Magic + relevant utility (Navigation/Engineering/Alchemy/Seamanship) |
| Enchantment spells | Mastery of Charms and Illusions + Mystic Aura + (Diplomacy or Intimidation or Seduction) |
| Healing spells | Healing rank 3 |
| Illusion spells | Mastery of Charms and Illusions + 2 of (Illusion Resistance, Loremastery, Second Sight) |
| Movement spells | 3 of (Climbing, Riding, Running, Seamanship) |
| Protection spells | 3 of (Battle Magic, Bright Lore, Military Strategy, Theology) |
| Summoning spells | (Black Lore or Bright Lore) + 2 of (Beast Friendship, Elementalism, Loremastery) |
| Transformation spells | Transmogrification + 2 of (Alchemy, Animal Husbandry, Healing) |
| Any general proficiency authority | That proficiency at rank 3 |

**System requirements:**
- Authority prerequisite check: given a proficiency set, determine which codex/scroll authorities are available
- Rank-awareness for prerequisite checks (e.g., Healing rank 3)

### 7.3 Turn Undead Modification

**Hook:** Improve turn undead effectiveness.

| Proficiency | Effect |
|---|---|
| Righteous Turning (C) | Add WIS bonus to both turning throw and HD turned on success |

**System requirements:**
- Turn undead throw modifier (WIS bonus via Righteous Turning)
- Turned-HD bonus (WIS bonus)

---

## 8. Treasure & Economics

### 8.1 Appraisal & Trade

**Hook:** Identify items and improve economic outcomes.

| Proficiency | Effect |
|---|---|
| Adventuring (auto) | Rough valuation of common coins, gems, jewelry, trade goods |
| Bargaining (C) | +2 reaction in commercial contexts (Venturer) |
| Gambling (G)(P) | Earn 1d6 gp/month per selection; contested gambling mechanic |

**System requirements:**
- Item valuation throw (Adventuring: auto for common items)
- Commercial reaction modifier (Bargaining)
- Gambling minigame (contested d6 rolls with raise/fold mechanic)

### 8.2 Monster Part Harvesting

**Hook:** Enable harvesting of monster special components.

| Monster Type | Required Proficiency |
|---|---|
| Animal | Animal Husbandry, Labor (Butchery), or Trapping |
| Beastmen | Animal Husbandry and/or Healing (combined rank 2) |
| Construct | Magical Engineering |
| Fantastic Creature | Animal Husbandry and/or Healing (combined rank 3) |
| Giant | Healing |
| Humanoid | Healing |
| Oozes | Alchemy |
| Summoned | Alchemy rank 2 |
| Undead (incorporeal) | Alchemy rank 2 |
| Undead (corporeal) | Healing rank 2 |
| Vermin | Animal Husbandry rank 2 |

**System requirements:**
- Harvesting permission check: monster type → required proficiency + rank
- Harvesting time: proficiency-gated components = 1 turn per 100gp value
- Mortal Wounds table roll to check component survival when monster is slain
- +2 treatment modifier if harvester has prerequisite proficiency

---

## 9. Campaign Play (Hijinks, Timekeeping, Research)

### 9.1 Hijinks

**Hook:** Enable monthly criminal/economic activities in settlements.

| Proficiency | Effect |
|---|---|
| All thief skills (class) | Thief skill throws feed into hijink success rates |
| Bribery (C) | Know who to bribe; +2 reaction when offering bribes |
| Cat Burglary (C) | +2 climb walls; +2 hear noise (used in burglary hijinks) |
| Skulking (C) | +2 hide; +2 move silently (used in assassination/smuggling hijinks) |

**System requirements:**
- Hijink success calculation references thief skill values
- Proficiency modifiers applied to hijink-specific throws

### 9.2 Divination-Like Proficiencies

**Hook:** Grant periodic information-gathering abilities.

| Proficiency | Effect |
|---|---|
| Prophecy (C) | Cryptic visions; once/week use Commune (3 yes/no questions) |
| Soothsaying (C) | Cryptic visions; once/week use Contact Other Plane |

**System requirements:**
- Weekly divination cooldown tracking
- Interface with divination spell hooks (Commune → §3.2 in spell system map; Contact Other Plane → §3.2)

---

## 10. Visibility & Stealth

**Hook:** Modify stealth throw targets.

| Proficiency | Effect |
|---|---|
| Skulking (C) | +2 hide in shadows; +2 move silently |
| Cat Burglary (C) | +2 climb walls; +2 hear noise |
| Passing Without Trace (C) | Untrackable in wilderness; cover companions (1 per 3 levels) |
| Quiet Magic (C) | Casting detectable only by hear noise throw |

**System requirements:**
- Stealth throw modifiers stacking with thief skill base values
- Track-immunity flag (Passing Without Trace)

---

## 11. Illusions & Information

**Hook:** Modify illusion and information-gathering interactions.

| Proficiency | Effect |
|---|---|
| Illusion Resistance (C) | +4 saving throws to disbelieve illusions |
| Knowledge (G)(P) | Recall expert information in chosen field on 11+ |
| Naturalism (G) | Know flora/fauna, edible/poisonous, healing herbs on 11+ in familiar terrain |

**System requirements:**
- Illusion save modifier (Illusion Resistance)
- Knowledge check system: field-specific proficiency throw on 11+
- Terrain-keyed knowledge (Naturalism: familiar terrain only)

---

## 12. Sea Travel (When Applicable)

**Hook:** Enable/modify sea travel capabilities.

| Proficiency | Effect |
|---|---|
| Seafaring (G)(P) | Rank 1: crew large ships. Rank 2: captain. Rank 3: master mariner (tacking penalty reduced, +5% evasion) |
| Navigation (G) | Serve as ship navigator; +4 avoid getting lost |

**System requirements:**
- Ship role assignments (crew, captain, navigator) keyed to proficiency rank
- Tacking movement penalty reduction (Seafaring rank 3)
- Ship evasion modifier (Seafaring rank 3: +5%)

---

## 13. Automaton System (Dwarven Machinist)

**Hook:** Enable automaton construction, repair, and operation.

| Proficiency | Effect |
|---|---|
| Inventing (C) | Design automatons as if 2 levels higher; -20% design time |
| Tinkering (C) | Build automatons as if 2 levels higher; -20% build time |
| Jury-Rigging (C) | Repair as if 2 levels higher; hasty repair in 1 turn (lasts 4d6 turns) |
| Mechanical Engineering (C) | +1 automaton throws; recognize automaton types/functions |
| Scavenging (C)(P) | -10% automaton build/design cost per selection |
| Personal Automaton (C)(P) | Build smaller personal automaton with adjusted build rules |

**System requirements:**
- Automaton construction pipeline (design → build → operate → repair)
- Effective-level override for design/build/repair (Inventing, Tinkering, Jury-Rigging)
- Cost reduction stacking (Scavenging)
- Hasty repair mechanic (Jury-Rigging: temporary HP, secret duration)
- Note: Full automaton system is post-v1 scope but hooks should exist in character data model

---

## 14. Specialization Framework

**Hook:** Provide closed, selectable lists for open-ended proficiencies at runtime.

**GDD:** `gdd-proficiency-specializations.md` — canonical specialization enumerations (weapon categories, mount species, art forms, knowledge fields, craft trades), three-layer registry (base catalog / setting-generated / campaign-created), trained-creature entity model.

**Affected proficiencies:** Weapon Focus (weapon category), Riding (mount species), Craft (trade), Art (form), Knowledge (field), Animal Training (species), Animal Husbandry (species), Prophecy/Soothsaying (domain — handled by codex authority system), Siege Engineering (ranked type), Specialized Fighting Style variants.

**System requirements:**
- Composite key on proficiency selections: `proficiency_id` + `specialization_id`
- Registry composition: union of base catalog + setting-generated + campaign-created layers
- Dynamic registry extension during play (crossbreeding, homebrew, LLM content)
- Per-proficiency specialization picker in character creation UI
- Trained-creature entity model: derived from mount/animal proficiency + specialization + trainer level

---

## Cross-Reference: Proficiencies by System Priority

For quick lookup when building a specific system, proficiencies sorted by which system they primarily affect:

| System | Proficiencies |
|---|---|
| **Combat** | Acrobatics, Alertness, Ambushing, Armor Training, Battle Magic, Berserkergang, Blind Fighting, Combat Reflexes, Combat Trickery, Divine Blessing, Divine Health, Dungeon Bashing, Elementalism, Fighting Style, Goblin-Slaying, Illusion Resistance, Kin-Slaying, Precise Shooting, Running, Skirmishing, Sniping, Swashbuckling, Unarmed Fighting, Unflappable Casting, Vermin-Slaying, Weapon Finesse, Weapon Focus |
| **Character Data** | Apostasy, Arcane Dabbling, Armor Training, Contemplation, Elven Bloodline, Familiar, Language, Laying on Hands, Martial Training |
| **NPC Systems** | Bargaining, Beast Friendship, Bribery, Command, Diplomacy, Disguise, Intimidation, Leadership, Lip Reading, Manual of Arms, Mimicry, Mystic Aura, Seduction, Signaling |
| **Dungeon Exploration** | Alertness, Cat Burglary, Caving, Climbing, Contortionism, Dungeon Bashing, Land Surveying, Lockpicking, Mapping, Mountaineering, Skulking, Trap Finding |
| **Wilderness Exploration** | Animal Husbandry, Animal Training, Beast Friendship, Endurance, Naturalism, Navigation, Passing Without Trace, Riding, Running, Survival, Tracking, Trapping |
| **Domain Play** | Command, Craft, Engineering, Labor, Leadership, Military Strategy, Profession, Siege Engineering, Theology |
| **Spells & Magic** | Alchemy, Black Lore of Zahar, Collegiate Wizardry, Dwarven Brewing, Elementalism, Loremastery, Magical Engineering, Quiet Magic, Righteous Turning, Sensing Evil, Sensing Power, Transmogrification |
| **Treasure & Economics** | Adventuring, Alchemy, Animal Husbandry, Bargaining, Gambling, Healing, Magical Engineering |
| **Campaign Play** | Art, Craft, Gambling, Healing, Knowledge, Labor, Performance, Profession, Prophecy, Soothsaying |
| **Sea Travel** | Navigation, Seafaring |
| **Specialization Framework** | `gdd-proficiency-specializations.md` — composite `proficiency_id` + `specialization_id` key for all open-ended proficiencies; three-layer registry; trained-creature entity model |

---

## Build Agent Implementation Notes

### Hook Pattern

Each proficiency effect resolves to one of these patterns (same taxonomy as `spell_system_map.md`):

- **Modifier**: Numeric adjustment (attack throw, damage, AC, save, movement, reaction roll, morale, throw target)
- **Flag**: Boolean state (disease immunity, track immunity, berserk, can-fire-into-melee, blind-fighting)
- **Enabler**: Permission grant (climb walls, hear noise, operate siege engines, train troops, harvest components)
- **Threshold gate**: Ranked prerequisite check (codex authority, specialist equivalence, monster harvesting)
- **Entity**: Created game object (familiar, trained animal, wilderness trap)
- **Income**: Monthly gp generation from ranked trade proficiency

### Ranked Proficiency System

Many proficiencies have ranks (1/2/3) or level-scaling bonuses. The character data model needs:

- `proficiency_id` + `rank` (integer, default 1)
- `selections_count` (for proficiencies taken multiple times with cumulative effect, e.g., Scavenging, Precise Shooting)
- Level-scaling lookup for proficiencies with breakpoints (Goblin-Slaying: levels 1/7/13; Swashbuckling: levels 1/7/13)

### What Gets Checked Most Often at Runtime

In approximate frequency order during gameplay:

1. **Combat modifiers** — every combat round (attack, damage, AC, initiative, saves)
2. **Exploration throws** — every room/hex (hear noise, find traps, secret doors, track)
3. **Reaction modifiers** — every NPC encounter
4. **Movement modifiers** — every travel segment
5. **Monthly income/domain** — each game-month
6. **Magic research** — during campaign downtime
