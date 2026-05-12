# GDD: Trap Generation

**Authority:** PROJECT-DESIGNED — trap generation procedures are not published in ACKS. ACKS provides trap encounter placement (as part of dungeon stocking), trap detection/disarming rules (thief skills, proficiency throws), and some example traps. This GDD provides the parametric system that generates specific trap instances when the stocking procedure calls for one.
**Status:** Draft — disarm-failure consequences added 2026-05-12 (revision 2)
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (stocking procedure — when a room gets a trap), `acore_combat_and_wounds.xml` (saving throw categories, damage types), `acore_adventures_and_encounters.xml` (trap detection throws, thief skill targets, Remove Traps skill failure)
**Depends on project GDDs:** `gdd-dungeon-layout.md` (room graph, door data, corridor geometry for trap placement context)
**Modifiable by Claude Code:** Yes — all tables, probabilities, and generation logic are engineering decisions.
**Last updated:** 2026-05-12

---

## 1. Purpose

When the dungeon stocking procedure determines that a room contains a trap, this system generates the specific trap: what is trapped, how it triggers, what it does, how hard it is to detect, and how hard it is to disarm. The output is a complete trap record that the encounter engine can resolve mechanically and the LLM can narrate.

Traps should feel dangerous, varied, and appropriate to the dungeon's level and theme. A level 1 dungeon has pit traps and poison needles. A level 6 dungeon has disintegration beams and rooms that flood with acid.

---

## 2. ACKS Constraints

**Trap placement:** The stocking procedure determines which rooms have traps. This GDD does not decide IF a room has a trap — only WHAT that trap is.

**Trap detection (ACore Ch.4):**
- Any character can search for traps: find traps throw (typically 18+ on 1d20, modified by INT and proficiency)
- Thieves have the Find Traps skill with better targets by level
- Dwarves detect stone-based traps on 14+ (architectural sense)
- Elves detect secret doors on 8+ (which sometimes conceal traps)

**Trap disarming (ACore Ch.4):**
- Thieves have the Remove Traps skill with targets by level
- Non-thieves can attempt to disarm with a proficiency throw (typically 18+)
- Some traps can be bypassed without disarming (jump over the pit, wedge the mechanism)
- **A failed Remove Traps roll has consequences.** ACKS specifies that thieves who fail a Remove Traps attempt may set off the trap they are trying to disarm. The published rule does not specify the precise threshold or all edge cases (e.g., whether the trap is still disarm-able after a near-miss, whether broken mechanisms can be re-attempted). §15 of this GDD provides a project-designed disarm-failure model that respects the ACKS principle that failure is dangerous while filling the procedural gaps.

**Saving throws:** ACKS uses five saving throw categories: Petrification & Paralysis, Poison & Death, Blast & Breath, Staffs & Wands, Spells. Trap effects that allow saves use one of these.

---

## 3. Generation Pipeline

```
1. DETERMINE TRAP LOCATION → what is trapped (door, floor, chest, room)
2. DETERMINE TRIGGER → what sets it off (pressure, opening, proximity, etc.)
3. DETERMINE EFFECT → what happens (damage, save-or-suffer, environmental)
4. SCALE TO DUNGEON LEVEL → damage dice, save difficulty, detection target
5. APPLY DUNGEON THEME → flavor the trap to match the dungeon type
6. ASSEMBLE TRAP RECORD → complete mechanical + narrative data
```

---

## 4. Step 1: Trap Location

What is trapped? Roll on the location table, weighted by dungeon context:

| Location Type | Weight | Description |
|---|---|---|
| `door` | 25% | The door itself is trapped — opening, touching, or forcing it triggers the trap |
| `floor` | 25% | A section of corridor or room floor is trapped — stepping on it triggers |
| `object` | 25% | A chest, statue, altar, lever, throne, sarcophagus, or other interactable object is trapped |
| `room` | 15% | The entire room is the trap — entering, lingering, or performing a specific action triggers it |
| `corridor` | 10% | A section of hallway between rooms is trapped |

### 4.1 Context Modifiers

Adjust weights based on dungeon stocking context:

```
- Room contains treasure → object +15% (trapped chest/container)
- Room is a dead end → floor +10% (pit before the dead end)
- Room has a door the party hasn't opened → door +10%
- Room is large (4+ cells) → room +10%
- Room is on a major corridor → corridor +10%
- Dungeon theme is "tomb" or "crypt" → object +10% (sarcophagi, altars)
- Dungeon theme is "lair" or "cavern" → floor +10% (natural hazard traps)
```

---

## 5. Step 2: Trigger Mechanism

How is the trap set off? The trigger depends on the location type:

### 5.1 Door Triggers

| Trigger | Weight | Description |
|---|---|---|
| `open` | 40% | Trap fires when the door is opened normally |
| `force` | 20% | Trap fires when the door is forced or bashed |
| `touch` | 15% | Trap fires on contact (handle, surface, knocker) |
| `unlock` | 15% | Trap fires when a lock is picked or the wrong key is used |
| `threshold` | 10% | Trap fires when someone passes through the doorway after opening |

### 5.2 Floor Triggers

| Trigger | Weight | Description |
|---|---|---|
| `pressure_plate` | 40% | Specific tiles depress under weight |
| `weight_threshold` | 20% | Floor gives way when enough weight is on it (pit trap) |
| `tripwire` | 20% | A wire at ankle or shin height across the floor |
| `proximity` | 10% | Magical or mechanical sensor detects movement |
| `timed` | 10% | Trap fires a set time after someone enters the area |

### 5.3 Object Triggers

| Trigger | Weight | Description |
|---|---|---|
| `open` | 35% | Trap fires when the container is opened (chest lid, sarcophagus) |
| `touch` | 25% | Trap fires on contact (picking up item, touching statue) |
| `remove` | 20% | Trap fires when an item is removed from a surface (weight-sensitive pedestal) |
| `needle` | 15% | Concealed needle in a lock, handle, or hidden compartment |
| `read` | 5% | Magical trap fires when an inscription is read aloud |

### 5.4 Room Triggers

| Trigger | Weight | Description |
|---|---|---|
| `entry` | 30% | Trap fires when someone enters the room |
| `center` | 25% | Trap fires when someone reaches the room's center area |
| `timed` | 20% | Trap fires after a set duration in the room (doors lock, then effect) |
| `action` | 15% | Trap fires when a specific action is performed (sitting on throne, pulling lever) |
| `exit` | 10% | Trap fires when someone tries to leave (doors seal, trap activates) |

### 5.5 Corridor Triggers

| Trigger | Weight | Description |
|---|---|---|
| `pressure_plate` | 35% | As floor |
| `tripwire` | 30% | As floor |
| `proximity` | 20% | Detecting movement through the corridor |
| `midpoint` | 15% | Fires when someone reaches the corridor's midpoint (maximizes distance from exits) |

---

## 6. Step 3: Trap Effect

The effect is the core of the trap — what happens when it fires. Effects fall into three categories: **damage**, **save-or-suffer**, and **environmental**. The ratio shifts with dungeon level.

### 6.1 Effect Category Distribution

| Dungeon Level | Damage | Save-or-Suffer | Environmental |
|---|---|---|---|
| 1-2 | 60% | 15% | 25% |
| 3-4 | 50% | 25% | 25% |
| 5-6 | 40% | 35% | 25% |
| 7+ | 30% | 45% | 25% |

As dungeon level increases, traps shift from straightforward damage toward nastier save-or-die and save-or-suffer effects. Environmental traps stay constant — they're always useful for variety.

### 6.2 Damage Effects

Direct hit point damage. The core scaling rule:

```
Damage dice = dungeon_level ± 1 (minimum 1)

Roll 1d3 to determine variance:
  1 → dungeon_level - 1 dice (minimum 1)
  2 → dungeon_level dice (standard)
  3 → dungeon_level + 1 dice

Die type: d6 (standard ACKS trap damage)

Save: 50% of damage traps allow a save vs. Blast for half damage
```

| Dungeon Level | Damage Range | Average Damage (no save) |
|---|---|---|
| 1 | 1d6 to 2d6 | 3.5–7 |
| 2 | 1d6 to 3d6 | 3.5–10.5 |
| 3 | 2d6 to 4d6 | 7–14 |
| 4 | 3d6 to 5d6 | 10.5–17.5 |
| 5 | 4d6 to 6d6 | 14–21 |
| 6 | 5d6 to 7d6 | 17.5–24.5 |

**Damage delivery methods** (rolled from a table, themed to dungeon type):

| Method | Compatible Locations | Description |
|---|---|---|
| `falling` | floor, corridor | Pit trap — fall damage, possibly with spikes |
| `piercing` | door, object, corridor | Darts, arrows, spears from walls/ceiling |
| `slashing` | door, corridor | Blade swings from wall or ceiling |
| `crushing` | floor, room, corridor | Falling block, closing walls, ceiling drop |
| `fire` | any | Flame jet, fire burst, burning oil |
| `acid` | object, room | Acid spray, dissolving pool, acid-coated needle |
| `lightning` | room, corridor | Electrical discharge (magical) |
| `cold` | room, corridor | Freezing blast (magical) |
| `poison_damage` | object, door | Poison needle or gas — deals damage (not save-or-die) |

### 6.3 Save-or-Suffer Effects

These require a saving throw. Failure produces a severe or fatal effect. Success means either no effect or reduced effect.

| Effect | Save Category | Failure Result | Success Result | Min Level |
|---|---|---|---|---|
| `poison_lethal` | Poison & Death | Death | No effect | 2 |
| `poison_debilitating` | Poison & Death | 1d6 turns incapacitated | Half duration | 1 |
| `paralysis` | Petrification & Paralysis | Paralyzed 2d4 turns | No effect | 2 |
| `petrification` | Petrification & Paralysis | Turned to stone | No effect | 5 |
| `polymorph` | Spells | Polymorphed into a harmless creature | No effect | 5 |
| `sleep_gas` | Spells | Fall asleep for 2d6 turns | No effect | 1 |
| `charm` | Spells | Charmed (treats trap creator/faction as friend) | No effect | 3 |
| `energy_drain` | Spells | Lose 1 level (or 1d2 levels at deep levels) | No effect | 6 |
| `disintegration` | Poison & Death | Destroyed utterly | No effect | 7 |
| `teleportation` | Spells | Teleported to a distant dungeon room (usually deeper) | No effect | 3 |
| `curse` | Spells | Bestow curse (random or thematic) | No effect | 4 |

**Minimum level column:** The trap generator will not produce these effects on dungeon levels below the minimum. No disintegration traps on level 1.

### 6.4 Environmental Effects

These change the physical environment rather than directly harming characters. They create tactical problems that require problem-solving rather than hit points.

| Effect | Description | Resolution |
|---|---|---|
| `pit_open` | Floor opens into a pit (10' per dungeon level deep) | Climb out, lower a rope, find another route |
| `door_lock` | Doors seal shut, trapping the party in the room | Force doors, pick locks, find hidden exit, wait for mechanism to reset |
| `flooding` | Room begins filling with water (or sand, or grain) | Find the drain, break the source, escape before full |
| `darkness` | Magical darkness fills the room | Dispel magic, continual light, or navigate blind |
| `alarm` | Loud noise alerts nearby monsters (no direct harm) | Faction alert propagation (see gdd-dungeon-factions.md §8) |
| `collapse` | Partial ceiling collapse blocks a passage | Dig out (1d6 turns), find another route |
| `portcullis` | Iron gate drops, splitting the party | Lift gate (combined STR check), go around |
| `rotating_room` | Room rotates, exits now connect to different corridors | Map carefully; exploration challenge |
| `illusory_floor` | Floor appears solid but is an illusion over a pit | As pit, but detection is harder (find traps or disbelieve) |
| `gas_obscuring` | Non-damaging fog/smoke fills the area | Wait to clear (2d6 rounds), or push through blind |

---

## 7. Step 4: Scaling to Dungeon Level

### 7.1 Damage Scaling

Already defined in §6.2: damage dice = dungeon level ± 1.

### 7.2 Detection Difficulty

The base detection target (for non-thieves using the find traps throw) scales with level:

```
detection_target = 14 + dungeon_level (maximum 24)

Level 1: 15+
Level 2: 16+
Level 3: 17+
Level 4: 18+
Level 5: 19+
Level 6: 20+
Level 7+: 21+ (effectively requires magical detection or thief skills)
```

Thief Find Traps skill uses its own progression from class data — the dungeon level doesn't modify it. This means deeper dungeons increasingly require a thief to detect traps, which is intended.

### 7.3 Disarm Difficulty

```
disarm_target = 14 + dungeon_level (maximum 24)

Same scale as detection. Some traps have a disarm modifier:
  Mechanical traps: no modifier
  Magical traps: +2 to disarm target (harder to neutralize)
  Combined (mechanical trigger + magical effect): +1 to disarm target
```

### 7.4 Save Modifier

For save-or-suffer traps, deeper levels may impose a save penalty:

```
Level 1-3: no modifier
Level 4-5: -1 to save
Level 6-7: -2 to save
Level 8+: -3 to save
```

This is applied to the victim's saving throw roll, making deeper traps harder to resist.

---

## 8. Step 5: Dungeon Theme Flavoring

The dungeon type (from `gdd-dungeon-layout.md` §5) influences trap presentation. The mechanical effect stays the same; the flavor and delivery method change.

| Dungeon Type | Flavor Bias | Preferred Methods | Preferred Effects |
|---|---|---|---|
| Tomb / Crypt | Ancient, ornate, curse-themed | Needle, crushing, acid | Curse, poison_lethal, petrification |
| Temple / Shrine | Divine punishment, holy wrath | Fire, lightning | Energy_drain, charm, polymorph |
| Fortress / Castle | Military, engineered, efficient | Piercing (arrow slits), slashing, portcullis | Damage, alarm, portcullis |
| Cavern / Natural | Camouflaged natural hazards | Falling (pits), crushing (rockfall), flooding | Pit_open, collapse, flooding |
| Wizard's Tower | Magical, bizarre, experimental | Lightning, cold, any magical | Teleportation, polymorph, disintegration |
| Sewer / Underground | Corrosive, diseased, slippery | Acid, poison_damage | Poison_debilitating, flooding, gas |
| Mine / Excavation | Structural, industrial | Crushing, falling, collapse | Collapse, pit_open, alarm |
| Bandit Lair | Crude, practical, alarm-focused | Tripwire, piercing (crossbow) | Damage (low), alarm, portcullis |
| Dragon Lair | Fire-themed, treasure-protecting | Fire, acid, crushing | Fire damage (high), door_lock, alarm |
| Undead Stronghold | Necromantic, draining, cursed | Cold, darkness, needle | Energy_drain, paralysis, curse |

The generator selects delivery methods and effects from the compatible subset for the dungeon theme, falling back to the general tables for variety if the themed subset is too narrow.

---

## 9. Trap Complexity

### 9.1 Simple vs. Complex Traps

Most traps are **simple**: one trigger, one effect, one resolution. But deeper dungeons occasionally produce **complex traps** — multi-stage or combined mechanisms.

```
Complex trap chance: 5% × dungeon_level
  Level 1: 5% (rare)
  Level 3: 15%
  Level 5: 25%
  Level 7: 35%
```

### 9.2 Complex Trap Patterns

| Pattern | Description | Example |
|---|---|---|
| `two_stage` | Trigger causes effect A, which sets up effect B | Pit opens (environmental) → spikes at bottom deal damage |
| `combined` | Single trigger causes two simultaneous effects | Poison gas (save-or-suffer) + doors lock (environmental) |
| `bait` | Obvious trap conceals a second hidden trap | Visible tripwire (easy to step over) → pressure plate behind it |
| `cascading` | Disarming incorrectly triggers a worse effect | Trap needle on chest → failed disarm triggers acid spray |

For complex traps, generate each component separately then combine:
- Roll location and trigger once (shared)
- Roll two effects (one per component)
- The detection target is the HARDER of the two components + 1
- The disarm target applies to the first component; the second may require a separate disarm

---

## 10. Trap Reset and Persistence

### 10.1 Reset Behavior

```
Single-use traps (50%):
  - Fire once, then spent (pit stays open, darts expended, gas released)
  - The location remains hazardous (open pit) but won't trigger again
  - Faction replenishment does NOT reset single-use traps

Resetting traps (35%):
  - Automatically reset after a delay (1d6 turns for mechanical, 
    instant for magical)
  - Can trigger multiple times if the party passes through again
  - Faction members know the trap location and avoid or bypass it

Manual-reset traps (15%):
  - Require someone to manually reset (reload darts, reset mechanism)
  - Faction members reset them during replenishment if the trap is 
    in their territory
  - If the faction is eliminated, manual-reset traps stay spent
```

### 10.2 Faction Traps vs. Dungeon Traps

```
Faction traps: placed by an intelligent faction to protect their territory
  - Located at faction frontiers, chokepoints, and lair approaches
  - Faction members know the trap and bypass it safely
  - If the party allies with the faction, they may be told about the traps
  - More likely to be alarm traps or non-lethal (the faction wants 
    warning, not dead allies)

Dungeon traps: part of the dungeon's original construction or inherent hazards
  - Located anywhere the stocking procedure places them
  - No one may know they exist (ancient, forgotten)
  - More likely to be lethal or save-or-suffer (the original builders 
    didn't care about current inhabitants)
```

---

## 11. Output Data Structure

```
TrapRecord:
  id: string
  dungeon_id: string
  dungeon_level: int
  room_id: int                    # Room or corridor where the trap is located
  
  # Location
  location_type: string           # "door", "floor", "object", "room", "corridor"
  location_detail: string         # "iron-bound chest", "third flagstone from door",
                                  #  "stone sarcophagus lid", "entire chamber"
  
  # Trigger
  trigger_type: string            # From §5 tables
  trigger_detail: string          # "pressure plate beneath the welcome mat",
                                  #  "needle concealed in the lock mechanism"
  
  # Effect
  effect_category: string         # "damage", "save_or_suffer", "environmental"
  effect_type: string             # From §6 tables: "piercing", "poison_lethal", "flooding"
  
  # Damage (if effect_category == "damage")
  damage_dice: string             # "3d6", "5d6", etc.
  damage_type: string             # "piercing", "fire", "acid", "bludgeoning", "cold", etc.
  save_for_half: bool             # Does a save reduce damage by half?
  save_category: string or null   # "blast", "spells", etc. (null if no save)
  
  # Save-or-suffer (if effect_category == "save_or_suffer")
  save_category: string           # "poison_death", "petrification_paralysis", "spells"
  save_modifier: int              # Penalty to save (0, -1, -2, -3)
  failure_effect: string          # "Death", "Paralyzed 2d4 turns", "Turned to stone"
  success_effect: string          # "No effect", "Half duration", "Half damage"
  
  # Environmental (if effect_category == "environmental")
  environmental_type: string      # From §6.4 table
  environmental_detail: string    # "Room floods to 4' depth in 6 rounds"
  resolution: string              # "Find drain plug in east wall (Search 14+) or 
                                  #  swim to the ceiling air pocket"
  
  # Complexity
  is_complex: bool                # Multi-stage trap?
  complex_pattern: string or null # "two_stage", "combined", "bait", "cascading"
  secondary_effect: TrapEffect or null  # Second component (if complex)
  
  # Detection and disarming
  detection_target: int           # Throw target to find the trap
  disarm_target: int              # Throw target to disarm
  magical: bool                   # Is this a magical trap? (+2 disarm difficulty)
  bypass_option: string or null   # "Jump over the pit (DEX check 11+)",
                                  #  "Avoid the third tile", null if no bypass
  
  # Disarm state (see §15)
  disarm_state: string            # "untouched", "partially_disarmed", "disarmed",
                                  #  "jammed", "broken_sprung", "destroyed"
  disarm_attempts: int            # How many times has someone tried? (for re-attempt penalty)
  disarm_fail_profile: string     # "standard", "fragile", "vindictive", "stubborn"
                                  #  (see §15.3)
  
  # Persistence
  reset_type: string              # "single_use", "resetting", "manual_reset"
  reset_delay: string or null     # "1d6 turns", "instant", null for single-use
  triggered: bool                 # Has this trap already been triggered?
  
  # Faction association
  faction_id: string or null      # Which faction placed/maintains this trap (null = dungeon trap)
  faction_aware: bool             # Does the faction know this trap exists?
  
  # Theme
  dungeon_theme: string           # From the dungeon type, for flavor
  flavor_description: string      # LLM-friendly description for narration:
                                  #  "A thin wire stretches across the corridor at 
                                  #   shin height. Behind the wire, you notice tiny 
                                  #   holes in the stone walls on both sides."
```

---

## 12. Worked Examples

### 12.1 Level 1 — Simple Pit Trap

```
Dungeon level: 1, Theme: Natural Cavern
Pipeline:
  Location: floor (rolled)
  Trigger: weight_threshold (rolled — floor gives way)
  Effect category: damage (60% at level 1, rolled)
  Damage dice: 1d6 (level 1, rolled low variance)
  Delivery: falling (themed to cavern)
  Save for half: no (pit traps don't usually allow saves, you just fall)
  Complex: no (5% chance, missed)
  Detection: 15+ (14 + 1)
  Disarm: 15+ (but bypass: "Jump over — DEX check 9+; or use 10' pole to probe")
  Reset: single_use (pit stays open)
  
Output:
  location_detail: "A section of cavern floor concealed with a thin 
    layer of dried mud and sticks"
  trigger_detail: "Any weight over 50 lbs causes the covering to collapse"
  damage_dice: "1d6"
  damage_type: "bludgeoning"
  flavor_description: "The cavern floor ahead looks slightly different — 
    the mud here is drier and crackles faintly underfoot."
```

### 12.2 Level 4 — Poison Needle on Chest

```
Dungeon level: 4, Theme: Tomb
Pipeline:
  Location: object (room has treasure → +15% object weight)
  Trigger: needle (rolled — concealed in the lock)
  Effect category: save_or_suffer (25% at level 3-4, rolled)
  Effect: poison_lethal (themed to tomb)
  Save: Poison & Death
  Save modifier: -1 (level 4-5)
  Complex: no (20% chance, missed)
  Detection: 18+ (14 + 4)
  Disarm: 18+ (mechanical)
  Reset: single_use (needle expended)

Output:
  location_detail: "An ornate stone chest with bronze fittings, 
    resting at the foot of a carved sarcophagus"
  trigger_detail: "A spring-loaded needle concealed inside the lock 
    mechanism, coated in preserved venom"
  save_category: "poison_death"
  save_modifier: -1
  failure_effect: "Death"
  success_effect: "No effect — the needle scratches but the 
    poison has partially dried"
  flavor_description: "The chest's lock is unusually ornate, with 
    tiny serpent motifs coiled around the keyhole."
```

### 12.3 Level 6 — Complex Room Trap

```
Dungeon level: 6, Theme: Wizard's Tower
Pipeline:
  Location: room (large room → +10% room weight)
  Trigger: timed (doors lock 1 round after entry, then effect)
  Effect category: save_or_suffer (35% at level 5-6, rolled)
  Effect: teleportation (themed to wizard's tower)
  Complex: yes (30% chance at level 6, rolled)
  Complex pattern: combined
  Secondary effect: environmental — darkness
  Detection: 20+ (14 + 6)
  Disarm: 22+ (14 + 6 + 2 magical)
  Reset: resetting (magical, instant)

Output:
  location_detail: "A circular chamber with glowing runes on the floor 
    and a crystal orb on a pedestal at the center"
  trigger_detail: "1 round after anyone enters, the iron doors seal 
    (STR 20+ to force) and the runes flare"
  save_category: "spells"
  save_modifier: -2
  failure_effect: "Teleported to room 23 on level 8 (alone, 
    separated from party)"
  success_effect: "No effect — the runes flare but the magic 
    fails to take hold"
  environmental_type: "darkness"
  environmental_detail: "Magical darkness fills the room simultaneously, 
    blinding those who remain"
  flavor_description: "The room hums with arcane energy. Runes 
    carved into the floor pulse with a cold blue light, and a 
    crystal orb at the room's center seems to watch you."
```

---

## 13. Godot Implementation Notes

### 13.1 File Organization

```
engine/subsystems/generation/traps/
  trap_generator.gd              # Main pipeline: location → trigger → effect → scaling
  trap_tables.gd                 # All weighted random tables from §4-6
  trap_scaler.gd                 # Dungeon level scaling (damage, detection, saves)
  trap_themer.gd                 # Dungeon theme flavor application
  trap_disarm_resolver.gd        # Disarm-attempt resolution and failure outcomes (§15)
  trap_templates.json            # Flavor descriptions per delivery method and theme
```

### 13.2 Generation Performance

Trap generation is a sequence of weighted table lookups and simple arithmetic. A single trap generates in under 1ms. Batch generation for an entire dungeon level (5-15 traps) is instantaneous.

---

## 14. Revision History

- **2026-03-19:** Initial draft. Four-category trap location system. Trigger tables per location type. Three effect categories (damage, save-or-suffer, environmental) with dungeon-level scaling. Complex trap patterns. Theme flavoring per dungeon type. Faction vs. dungeon trap distinction. Reset and persistence model. Detection/disarm scaling. Three worked examples across levels 1, 4, and 6.
- **2026-05-12:** Added §15 — Disarm-Failure Consequences. Defines the disarm-attempt resolution model: margin-of-failure tiers (slip, fumble, catastrophe), four failure-profile archetypes per trap (standard, fragile, vindictive, stubborn), six post-attempt disarm states, and re-attempt rules. Extended `TrapRecord` in §11 with `disarm_state`, `disarm_attempts`, and `disarm_fail_profile` fields. Added a `trap_disarm_resolver.gd` file to §13.1. Status note updated to reflect revision 2.

---

## 15. Disarm-Failure Consequences

**Status of this section:** PROJECT-DESIGNED. ACKS specifies that a failed Remove Traps roll may set off the trap, but the published rule does not exhaustively cover (a) how badly a roll can fail, (b) whether a near-miss damages the mechanism short of firing it, (c) whether a failed attempt can be retried, or (d) what happens to magical traps whose disarm goes wrong. This section fills those gaps in a way that is consistent with the ACKS principle that trap-handling is dangerous and that thieves are the appropriate specialists.

### 15.1 Design Goals

The disarm-failure system should:

1. **Make failure interesting, not just "trap fires."** A binary success/fail collapses to "thief always disarms" at high level and "thief always dies trying" at low level. Margin-of-failure tiers create texture.
2. **Preserve thief specialization.** Thieves should be meaningfully better at disarming, including at failing gracefully.
3. **Distinguish mechanical and magical traps.** Magical traps "fail differently" — they tend to discharge rather than jam.
4. **Be deterministic.** The engine resolves the throw and looks up the outcome on a table; the LLM narrates the result the engine produces.
5. **Interact with reset/persistence.** A jammed trap is different from a sprung trap; the dungeon state should reflect both.

### 15.2 Resolution: Margin-of-Failure Tiers

When a character attempts to disarm a trap, the engine rolls the appropriate throw (thief Remove Traps, or non-thief proficiency throw, against the trap's `disarm_target`). The outcome is determined by the **margin of failure** — how far short the roll fell:

```
result = roll - disarm_target

  result >= 0          → SUCCESS — trap disarmed (transition disarm_state to "disarmed")
  result == -1 or -2   → SLIP    — minor failure, mechanism unaffected
  result == -3 to -5   → FUMBLE  — significant failure, may trigger or jam
  result <= -6         → CATASTROPHE — major failure, near-certain trigger
  natural 1            → CATASTROPHE regardless of math
```

A natural 20 always succeeds with no margin penalty (in line with ACKS conventions for thief skill throws).

### 15.3 Failure Profiles

Different trap types fail differently. At generation time each trap is assigned a `disarm_fail_profile` based on its effect category and whether it is mechanical or magical:

| Profile | Assigned To | Failure Character |
|---|---|---|
| `standard` | Most mechanical damage traps (piercing, slashing, crushing, falling) | Slip → no effect; Fumble → 40% trigger, 60% jam; Catastrophe → trap fires |
| `fragile` | Delicate mechanical traps (needles, tripwires, small darts) | Slip → no effect; Fumble → 25% trigger, 75% broken_sprung (single-use traps cannot be re-armed; they are now safely spent); Catastrophe → trap fires |
| `vindictive` | All magical traps and save-or-suffer traps with magical components | Slip → 15% trigger; Fumble → trap fires; Catastrophe → trap fires AND backlash (disarmer suffers a secondary effect, see §15.5) |
| `stubborn` | Heavy mechanical and environmental traps (portcullis, flooding, rotating room, collapse) | Slip → no effect; Fumble → no effect (the mechanism is too robust to be hurt by a near-miss), but disarm_target +1 for future attempts; Catastrophe → trap fires |

Profile assignment heuristic (used by the generator):

```
if magical == true:
    profile = "vindictive"
elif effect_category == "environmental" and effect_type in 
     ["portcullis", "flooding", "rotating_room", "collapse", "door_lock"]:
    profile = "stubborn"
elif effect_type in ["needle", "tripwire", "piercing"] and damage_dice <= "2d6":
    profile = "fragile"
else:
    profile = "standard"
```

### 15.4 Disarm States and What They Mean

After every disarm attempt the engine sets the trap's `disarm_state`. This field controls whether the trap can be triggered, re-attempted, or bypassed:

| State | Meaning | Can Re-Attempt? | Can Still Trigger? | Effect on Reset |
|---|---|---|---|---|
| `untouched` | Initial state | Yes (at normal target) | Yes | Resets normally |
| `partially_disarmed` | A previous attempt damaged but didn't disable the trap | Yes, at `disarm_target -2` (work in progress) | Yes, but on a +2 to the trigger sensitivity (less reliable) | Does not reset until disarmed or fully sprung |
| `disarmed` | Trap is neutralized | No (no need) | No | Does not reset (faction can re-arm if `manual_reset` and not destroyed) |
| `jammed` | Mechanism is stuck in a non-firing position | Yes, at `disarm_target +2` (working around the jam) | No | Cannot fire while jammed; resetting/manual_reset clears the jam on next replenishment cycle |
| `broken_sprung` | Mechanism is destroyed by a clumsy attempt — fired itself harmlessly or broke open | No (no working trap to disarm) | No | Single-use: permanently inert. Resetting/manual_reset: requires a full faction repair cycle (10× normal reset delay) before functional again |
| `destroyed` | Mechanism deliberately wrecked (e.g., smashed pit cover, ripped-out rune plate) | No | No | Permanently inert; no reset |

### 15.5 Backlash (Vindictive Profile, Catastrophe Only)

When a `vindictive` trap fires due to catastrophe, the disarmer suffers a **backlash** in addition to the trap firing normally. This represents the magical mechanism lashing out at the person tampering with it. The backlash is rolled separately:

```
Backlash effect (roll 1d6):
  1-2: Disarmer takes 1d6 damage per 2 dungeon levels (minimum 1d6),
       damage type matching the trap (fire trap → fire damage, etc.)
  3-4: Disarmer must save vs. Spells or be affected by the trap's effect
       at half intensity, even if the trap is environmental or hits
       the room rather than them
  5:   Disarmer is the only target of the trap; other party members
       in the same area are unaffected (the magic homes on the meddler)
  6:   Disarmer's next disarm attempt against any trap is at -2
       (a temporary curse-of-clumsiness, lasts 24 hours)
```

Backlash applies once per failed attempt, not per trap effect.

### 15.6 Re-Attempt Rules

A character may attempt to disarm a trap multiple times — within reason. Each retry assumes the disarmer has new tools, fresh perspective, or has examined the previous failure. To prevent re-attempt grinding:

1. **Each re-attempt takes one full turn** (10 minutes of game time). Re-attempts trigger faction wandering monster checks per the standard dungeon turn cadence.
2. **The trap must currently be in a re-attemptable state** (`untouched` or `partially_disarmed`; `jammed` is also re-attemptable but at +2 difficulty).
3. **After three failed attempts in a row,** the disarm target increases by +1 permanently for that trap — the mechanism has been worried into a more sensitive configuration (max +3 from this rule).
4. **A different character may attempt** even after three failures. Their attempt counter is independent for the +1 escalation, but they inherit the current `disarm_state` and any `+2 jammed` penalty.
5. **The party may also choose to bypass instead.** If a `bypass_option` exists, taking it does not change the trap state — the trap remains live for anyone who returns later.

### 15.7 Non-Thief Disarming

Non-thieves attempting to disarm use a proficiency throw (typically 18+, modified by relevant proficiencies — Engineering for mechanical traps, Knowledge (arcane) for magical traps). The same margin-of-failure tiers and failure profiles apply.

However, non-thieves have **one extra slip into fumble**: a result of `-1` or `-2` for a non-thief counts as FUMBLE instead of SLIP. This represents the thief's defining specialty — they fail more safely. Thieves using their own Remove Traps skill use the standard tier table from §15.2.

### 15.8 Bypass vs. Disarm

A trap with a `bypass_option` can be circumvented without engaging the disarm mechanism at all (jumping over a pit, wedging a portcullis open, etc.). Bypass is resolved by whatever check the bypass option specifies (DEX, STR, etc.) and has its own failure consequences:

- Failed bypass typically triggers the trap as if the character had walked into it normally.
- Bypass does NOT change the trap's `disarm_state` — the trap remains live for anyone who returns later and does not bypass.
- Bypass cannot be combined with a disarm attempt on the same trap in the same turn (the choice is exclusive — commit to disarming or commit to going around).

### 15.9 Worked Disarm-Failure Examples

#### 15.9.1 Level 1 pit trap, thief rolls a 12 against target 15

```
disarm_target: 15, roll: 12, margin: -3 → FUMBLE
disarm_fail_profile: "standard" (mechanical damage, falling)
Fumble outcome (40% trigger / 60% jam): rolls 65 → JAM
  → disarm_state: "jammed"
  → Trap cannot fire (covering is now wedged)
  → Re-attempt at target 17 (15 + 2 jam penalty)
Narration cue: "The covering creaks and shifts as you probe it.
  It sags but doesn't give way — you've wedged it deeper into the
  frame. The pit is stuck open at the edges but won't snap shut on
  anyone now."
```

#### 15.9.2 Level 4 poison needle chest, thief rolls a natural 1 against target 18

```
disarm_target: 18, roll: 1, margin: -17 → CATASTROPHE (also natural 1)
disarm_fail_profile: "fragile" (needle, small mechanical)
Catastrophe outcome: TRAP FIRES
  → Disarmer is the target of the poison needle
  → Save vs. Poison & Death at -1 or die
  → disarm_state: "broken_sprung" (single-use needle is expended)
  → Trap is permanently inert
Narration cue: "Your pick slips. The needle whips out and catches
  the back of your hand — make a save versus poison."
```

#### 15.9.3 Level 6 magical teleportation room, mage rolls a 16 against target 22

```
disarm_target: 22, roll: 16, margin: -6 → CATASTROPHE
disarm_fail_profile: "vindictive" (magical)
Catastrophe outcome: TRAP FIRES + BACKLASH
  → Doors seal, teleport effect triggers
  → Mage saves vs. Spells at -2 or be teleported to deep room
  → Backlash roll: 1d6 → 3-4 → mage also saves vs. Spells at half
    intensity (random close room instead of deep room, if main save
    succeeds)
  → disarm_state: "untouched" — magical traps reset themselves;
    the runes flare and re-stabilize
  → Re-attempts possible (the trap is back to its starting state)
    but the mage may not be around to make them
Narration cue: "You touch the rune plate with your dagger tip.
  The runes flash white and the entire pattern lights up — the
  trap has noticed you specifically."
```

#### 15.9.4 Level 3 stubborn portcullis trap, fighter rolls a 9 against target 17

```
disarm_target: 17, roll: 9, margin: -8 → CATASTROPHE
disarm_fail_profile: "stubborn" (environmental portcullis)
Catastrophe outcome: TRAP FIRES
  → Portcullis drops, splitting the party
  → disarm_state: "broken_sprung" — counterweight chain snapped
  → Faction will need full repair cycle (10× normal reset) before
    re-arming
Narration cue: "You jam your sword into the gear assembly. There's
  a deep clunk, then a much louder bang as the iron gate slams down
  through the doorway."
```

### 15.10 Faction Interaction

Faction-aware traps (§10.2) factor into disarm-failure handling:

- If the disarmer triggers a faction trap audibly (any catastrophe outcome on a faction trap), the faction is alerted per the alarm effect's normal propagation rules (`gdd-dungeon-factions.md §8`), regardless of whether the trap's effect itself was an alarm.
- Faction members performing routine replenishment (per §10.1) check each trap in their territory. They will:
  - Repair `broken_sprung` traps over the appropriate reset delay × 10.
  - Clear `jammed` traps and return them to `untouched`.
  - Leave `destroyed` traps as-is (these require a builder, not a faction member).
- The party can sometimes negotiate with a faction to have traps disarmed on their behalf — this bypasses the failure system entirely but costs reputation or gold.

### 15.11 LLM Narration Hooks

The engine produces a structured disarm result; the LLM narrates it. The relevant narration fields are:

```
DisarmResult:
  outcome: string          # "success", "slip", "fumble", "catastrophe"
  triggered: bool          # Did the trap fire?
  new_state: string        # The disarm_state after this attempt
  backlash: bool           # Was backlash applied?
  backlash_detail: string  # Empty if no backlash; otherwise the backlash effect text
  damage_dealt: dict       # Per-character damage from trap fire or backlash
  narration_hint: string   # Short engine-supplied phrase to seed the LLM's narration,
                           #   e.g. "needle whips out", "gears grind to a halt",
                           #   "runes flash and stabilize"
```

The narration hint is chosen from a small per-(profile, outcome, effect_type) table so that even the mock provider can produce evocative text. The LLM elaborates within the hint's frame but cannot contradict `triggered`, `new_state`, or `damage_dealt`.
