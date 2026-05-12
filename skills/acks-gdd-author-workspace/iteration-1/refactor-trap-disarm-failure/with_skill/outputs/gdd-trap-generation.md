# GDD: Trap Generation

**Authority:** PROJECT-DESIGNED — trap generation procedures are not published in ACKS. ACKS provides trap encounter placement (as part of dungeon stocking), trap detection/disarming rules (thief skills, proficiency throws), and some example traps. This GDD provides the parametric system that generates specific trap instances when the stocking procedure calls for one.
**Status:** Draft — adds §11 Disarming Failure Consequences (2026-05-12)
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (stocking procedure — when a room gets a trap), `acore_combat_and_wounds.xml` (saving throw categories, damage types), `acore_adventures_and_encounters.xml` (trap detection throws, thief skill targets), `ax_thief_skill_update.xml` (Axioms-updated find_traps / remove_traps failure rules)
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

**Saving throws:** ACKS uses five saving throw categories: Petrification & Paralysis, Poison & Death, Blast & Breath, Staffs & Wands, Spells. Trap effects that allow saves use one of these.

**Disarming failure (Axioms — `ax_thief_skill_update.xml`):** The Axioms thief skill update is the canonical source for what happens when a remove_traps attempt fails. The relevant rules:

> **RAW citation:** `rules/ax_thief_skill_update.xml:33-39` — Remove Traps:
> - May only remove traps that are found (not merely suspected).
> - Requires 1 turn and a successful proficiency throw.
> - May attempt in 1 round at -10 penalty.
> - Retries allowed.
> - On `failure_by >= 10 OR natural_1`: Trap triggered.

The implications, taken as binding constraints for §11 below:

1. A "miss" by less than 10 (and not a natural 1) is *not* a triggering event. The trap is simply still armed. Retries are explicitly allowed.
2. A failure by 10 or more, or a natural 1, *triggers* the trap. ACKS does not distinguish "fumble" from "near miss" — both are simply "Trap triggered."
3. Find Traps has the parallel rule (`rules/ax_thief_skill_update.xml:22-31`): a major-failure or natural 1 while *searching* also triggers the trap if one is present. The disarm path therefore is not the only way the party can self-trigger.
4. Thieves' tools (`rules/acore_equipment.xml:521-531`) are required to make proficiency throws to open locks and remove traps. The Axioms open_locks rule (`rules/ax_thief_skill_update.xml:14-20`) tells us that picking-lock fumbles break the tools; remove_traps does not have an explicit tool-breaking clause, so we do NOT add one here. (See §11.6 architectural note.)

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

## 11. Disarming Failure Consequences

This section is PROJECT-DESIGNED. The ACKS rule (cited in §2 above) is short: "On `failure_by >= 10 OR natural_1`: Trap triggered." Everything in §11 fills out the engineering details — when does the trap fire, who is in the blast radius, what is the post-trigger state, can the party try again — without contradicting or expanding the RAW rule.

### 11.1 Outcome Classes

Every disarm attempt resolves into exactly one of four outcomes. The classification is driven by the d20 result against `disarm_target` (from §7.3), plus the magical-trap modifier and any character bonuses.

```
roll_total = 1d20 + character_modifiers - magical_trap_penalty
margin     = roll_total - disarm_target
```

| Outcome | Condition | Effect |
|---|---|---|
| `success` | `margin >= 0` | Trap is neutralized. See §11.3. |
| `near_miss` | `-9 <= margin <= -1`, AND not natural 1 | Trap remains armed and unmodified. Retries allowed. See §11.2. |
| `triggered` | `margin <= -10` (failure by 10+) | Trap fires. See §11.4. |
| `fumble` | natural 1 on the d20, regardless of margin | Trap fires AND the trap becomes `stuck` (see §11.5). |

**Anchor to RAW:** `success` and `near_miss` are the natural complement of the Axioms triggering condition (`failure_by >= 10 OR natural_1`). `fumble` is the natural-1 case; we split it from generic `triggered` so the project can attach an additional consequence — a stuck mechanism — that is *not* mandated by RAW but is a project-designed elaboration. (See §11.6 architectural note.)

### 11.2 Near-Miss: Trap Is Still Disarm-able

A near-miss leaves the trap fully armed and unmodified. The character knows the attempt failed but has not committed any action that physically triggers the mechanism. Per `rules/ax_thief_skill_update.xml:33-39`, retries are explicitly allowed.

```
On near_miss:
  trap.state = ARMED            # unchanged
  trap.disarm_target            # unchanged (no escalating penalty)
  character may retry           # next attempt is a fresh roll
```

The character may also abandon the attempt and try a bypass option (§11.7), search for more information, or fetch a thief.

**No accumulating penalty.** ACKS does not introduce a "you've already failed, this is now harder" rule for remove_traps. We do not invent one.

### 11.3 Success: Trap Is Neutralized

```
On success:
  trap.state = DISARMED
  trap will not trigger on its current trigger condition
  the trap's physical components (darts, blade, pressure plate) remain
    in place and visible — the LLM narrates how the disarm was achieved
    (wedge, cut wire, spring removed, glyph defaced)
```

A disarmed trap stays disarmed. The faction-replenishment system (see `gdd-dungeon-factions.md`) treats a disarmed trap the same as a manual-reset trap that has fired: faction members in the trap's territory may rebuild it during replenishment, on the same schedule. Unallied or eliminated factions never rebuild.

### 11.4 Triggered: The Trap Fires Now

When the trap is triggered by a failed disarm attempt, it resolves *exactly as if the trigger condition had been met normally*. There is no "punishment damage" multiplier for failing the disarm — ACKS does not call for one, and we do not add one.

```
On triggered:
  resolve trap.effect against the disarming character (primary target)
  resolve trap.effect against other characters in the trap's area of
    effect, per §11.4.1 below
  apply trap.reset_type (single_use / resetting / manual_reset) as
    normal — a triggered-via-disarm trap behaves the same as a
    triggered-via-trigger trap for reset purposes
```

#### 11.4.1 Area of Effect on Disarm Trigger

The disarming character is always the primary target. Whether bystanders are affected depends on the trap's effect category and location:

| Effect Category | Disarm-trigger AoE |
|---|---|
| Damage — `falling`, `piercing`, `slashing`, `needle` | Primary target only (the character handling the trap) |
| Damage — `crushing`, `fire`, `acid`, `lightning`, `cold`, `poison_damage` (gas form) | Primary target + any character within 5' of the trap location |
| Save-or-suffer — `needle`-delivered (poison, etc.) | Primary target only |
| Save-or-suffer — gas, magical aura, area effect | Primary target + any character within the trap's normal AoE |
| Environmental — `pit_open`, `door_lock`, `flooding`, `darkness`, `alarm`, `collapse`, `portcullis`, `rotating_room`, `illusory_floor`, `gas_obscuring` | Resolves normally — the trap affects whoever is in its area regardless of who triggered it |

**Rationale:** the disarming character is the one with their hands on the mechanism, so single-point effects (needle, dart) hit them. Wide effects (gas, fire burst, falling ceiling) hit everyone present, just as they would on a normal trigger. The trap generator already records the AoE implicit in the effect type; this section simply tells the engine to use it the same way on a disarm-trigger as on a step-on-the-tile trigger.

#### 11.4.2 Saving Throws Still Apply

If the trap normally grants a saving throw (save for half damage, save vs. poison, etc.), the disarming character gets that save. Per the §2 ACKS Constraints, the save modifier from §7.4 still applies. Failing the disarm does not consume the save.

### 11.5 Fumble: Trap Is Stuck

A natural 1 on the disarm roll triggers the trap *and* leaves the mechanism in a damaged, partially-engaged state — wires snapped halfway through a cut, a pressure plate jammed at an angle, a glyph half-defaced. Mechanically:

```
On fumble:
  resolve trap firing per §11.4 (trap is triggered)
  trap.state = STUCK
  trap.disarm_target += 4       # mechanism is now harder to work with
  trap.retries_blocked_until_repaired = true
```

**Stuck state semantics:**
- The trap *has fired*, so its reset behavior (single_use / resetting / manual_reset) plays out normally. A single_use trap that fumbled is now both spent AND stuck; the location is hazardous (open pit, exposed needle, sprung wires) but the *trigger mechanism* is jammed and won't fire again.
- For resetting and manual_reset traps, the stuck state matters: the trap *will* attempt to reset, but the mechanism is partially broken. The engine should treat a stuck trap as having an unpredictable trigger — see §11.5.1.
- Disarm retries on a stuck trap suffer the +4 penalty. A character with the Trap Finding proficiency (`rules/acore_proficiencies_rules_and_catalog.xml:998-1008`, +2 to find/remove traps) still gets the proficiency bonus; the proficiency does not specifically address stuck traps but applies generally.
- A successful disarm against the elevated target finalizes the trap as DISARMED. A near-miss leaves it STUCK. A second triggered/fumble outcome is treated by the engine as a no-op for already-fired single_use traps (it's already spent) and as a fresh firing for resetting traps that have completed their reset cycle.

#### 11.5.1 Stuck Resetting Traps — Unpredictable Trigger

A resetting trap that fumbled has a partially-engaged mechanism. After the trap completes its reset delay (1d6 turns mechanical, instant magical), the engine should mark it as `armed_unstable`:

```
On any subsequent passage through trigger zone:
  roll 1d20
  on 1-10: trap fires (mechanism engages prematurely)
  on 11-20: trap does not fire (mechanism slips)

Faction members do NOT receive their normal "knows about and bypasses"
treatment for stuck traps — the mechanism is no longer predictable, so
even faction members are at risk. Faction characters traversing a stuck
trap roll the 1-10 / 11-20 check like anyone else.
```

This is a project-designed elaboration intended to make fumbles feel consequential without violating the ACKS RAW (which is silent on the post-fumble mechanism state).

### 11.6 Architectural Concerns and Open Questions

- **Stuck-trap mechanic is a project-design elaboration, not RAW.** ACKS RAW says only "Trap triggered" on fumble. The §11.5 "stuck" state, the +4 disarm penalty, and the §11.5.1 unstable-trigger behavior are project decisions that fill in what a video-game engine needs and that the books leave unstated. If Jedidiah prefers a closer-to-RAW reading (natural 1 = trap triggers, full stop, no stuck state), §11.5 can collapse into §11.4 with no other consequences. Flagged for review.
- **No thieves' tools breakage on remove_traps.** The Axioms open_locks rule explicitly breaks thieves' tools on `failure_by >= 10 OR natural_1`; the remove_traps rule does *not* include that clause. We follow RAW and do not break tools on a remove_traps fumble. If Jedidiah wants symmetry, that's a rule change to flag; we won't introduce it silently.
- **1-turn vs. 1-round attempts.** RAW allows a 1-round attempt at -10. The disarm-failure consequences in §11 do not distinguish between the two. A -10 penalty makes both `triggered` and `fumble` substantially more likely, which is the intended ACKS tradeoff. The engine should expose both options in the UI and apply the -10 to the roll only; consequence resolution is identical.
- **Non-thief disarmers.** The §2 ACKS Constraints note that non-thieves can attempt disarm with a proficiency throw (typically 18+). The §11 outcome classes apply identically — `near_miss` for margins -1 to -9, `triggered` for -10 or worse, `fumble` on natural 1. The base 18+ is the equivalent of `disarm_target = 18`; the §7.3 dungeon-level scaling already produces targets in that range and above, so non-thieves face roughly RAW-equivalent difficulty.
- **Magical traps and "disarm" by spell.** A wizard who dispels a magical trap with `dispel magic` is not making a remove_traps throw and §11 does not apply. The trap is simply suppressed per the spell's rules. If the dispel fails, the trap is unaffected; it does not fire from the failure. This is consistent with `rules/acore_spell_catalog_a-i_summary.xml:888-898` (Find Traps spell explicitly does not reveal how to disarm), implying that magical disarm is a separate mechanic from the proficiency throw.
- **Find Traps fumble can trigger too.** Per `rules/ax_thief_skill_update.xml:22-31`, a major-failure or natural 1 on Find Traps also triggers the trap if one is present. This GDD does not cover the detection path in depth; the trap engine should resolve a search-fumble trigger exactly as §11.4 (trap fires on detector), without the §11.5 stuck-state treatment (the searcher is not handling the mechanism, just inspecting it).

### 11.7 Bypass Options Remain Available

Independent of disarm outcomes, the trap's `bypass_option` field (§11 of the data structure, now §12) still applies. A character who fails or fumbles a disarm can fall back to:

- Jumping over the pit (DEX check)
- Wedging the door against the mechanism
- Triggering the trap deliberately from a safe position (10' pole, summoned creature)
- Going around (if the dungeon graph allows)
- Bringing a thief to retry (no penalty if the previous attempt was a near-miss; +4 if stuck)

The bypass option's target value is set at trap generation and is not modified by disarm-attempt history.

---

## 12. Output Data Structure

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
  disarm_target: int              # Throw target to disarm (effective, including stuck penalty)
  disarm_target_base: int         # Original disarm target before stuck penalty (§11.5)
  magical: bool                   # Is this a magical trap? (+2 disarm difficulty)
  bypass_option: string or null   # "Jump over the pit (DEX check 11+)",
                                  #  "Avoid the third tile", null if no bypass
  
  # Disarm state — §11
  state: string                   # "ARMED", "DISARMED", "STUCK", "SPENT", "ARMED_UNSTABLE"
  fumbled: bool                   # Has a fumble ever occurred? (§11.5)
  
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

**State transitions (§11):**

```
ARMED  --(success)-->        DISARMED
ARMED  --(near_miss)-->      ARMED (no change)
ARMED  --(triggered)-->      SPENT (single_use) | ARMED (resetting, after delay)
                              | requires-manual-reset (manual_reset)
ARMED  --(fumble)-->         STUCK + trap fires (then SPENT or ARMED_UNSTABLE)
STUCK  --(success)-->        DISARMED
STUCK  --(near_miss)-->      STUCK (no change)
STUCK  --(triggered/fumble)--> per reset_type; remains STUCK if it resets
ARMED_UNSTABLE --(any pass)--> 50% fires, 50% does not (§11.5.1)
```

---

## 13. Worked Examples

### 13.1 Level 1 — Simple Pit Trap

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

**Disarm scenario (§11):** A thief with a 14 in find_traps and a 12 disarm-target-after-modifiers attempts to disarm. Roll 1d20: result 3, total 3, margin -9. That's a near_miss — trap is still armed, retry allowed. Roll again: result 1 — natural 1, FUMBLE. The pit opens under the thief (resolve fall damage, 1d6 bludgeoning), and the trap is now SPENT + STUCK (already single_use, so the location is just a hazardous open pit; no further mechanism state matters).

### 13.2 Level 4 — Poison Needle on Chest

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

**Disarm scenario (§11):** Thief with disarm modifier +6 attempts. Target 18, modifier +6, so needs a raw 12+. Rolls a 7: total 13, margin -5. Near_miss — chest is untouched, retry allowed. Rolls a 1 next: FUMBLE. The needle fires into the thief's finger; they save vs. Poison & Death at -1. On failure, death. On success, "the needle scratches but the poison has partially dried." Either way, the trap is now SPENT (single_use needle) AND STUCK; the chest can still be opened, but anyone fiddling with the lock mechanism in the future is touching a jammed assembly with the depleted needle housing exposed — narratively, a fresh hazard, but mechanically the trap is finished.

### 13.3 Level 6 — Complex Room Trap

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

**Disarm scenario (§11):** Thief approaches the crystal orb (the visible mechanism) with disarm modifier +7 against target 22. Needs raw 15+. Rolls an 8: total 15, margin -7 — near_miss. The orb is untouched, runes still inert. Rolls a 4 next: total 11, margin -11 — TRIGGERED. The runes flare, the doors slam (resolve doors-lock environmental against everyone in the room), the disarming thief saves vs. Spells at -2 against teleportation, and darkness floods the chamber. The trap is resetting (magical, instant), so the room is dangerous again immediately. It is *not* stuck (no natural 1).

---

## 14. Godot Implementation Notes

### 14.1 File Organization

```
engine/subsystems/generation/traps/
  trap_generator.gd              # Main pipeline: location → trigger → effect → scaling
  trap_tables.gd                 # All weighted random tables from §4-6
  trap_scaler.gd                 # Dungeon level scaling (damage, detection, saves)
  trap_themer.gd                 # Dungeon theme flavor application
  trap_disarm_resolver.gd        # §11 outcome classification, state transitions
  trap_templates.json            # Flavor descriptions per delivery method and theme
```

### 14.2 Generation Performance

Trap generation is a sequence of weighted table lookups and simple arithmetic. A single trap generates in under 1ms. Batch generation for an entire dungeon level (5-15 traps) is instantaneous.

### 14.3 Disarm Resolution (§11)

The disarm resolver is a pure function over `(TrapRecord, d20_roll, character_modifiers)` → `(new_state, fired_bool, affected_characters[])`. No randomness inside the resolver itself; the d20 is rolled by the caller. This keeps the resolver deterministic and unit-testable. Use banker's rounding (round half to even) on any computed targets — there should be no fractional intermediate values in this section, but the project convention applies.

---

## 15. Revision History

- **2026-03-19:** Initial draft. Four-category trap location system. Trigger tables per location type. Three effect categories (damage, save-or-suffer, environmental) with dungeon-level scaling. Complex trap patterns. Theme flavoring per dungeon type. Faction vs. dungeon trap distinction. Reset and persistence model. Detection/disarm scaling. Three worked examples across levels 1, 4, and 6.
- **2026-05-12:** Added §11 Disarming Failure Consequences. Anchored to `rules/ax_thief_skill_update.xml:33-39` (remove_traps RAW: `failure_by >= 10 OR natural_1` = Trap triggered). Defined four outcome classes (success / near_miss / triggered / fumble), the disarm-trigger area of effect, the project-designed "stuck" state on fumbles (with +4 disarm penalty and `ARMED_UNSTABLE` semantics for resetting traps), state transitions, and architectural concerns. Updated §2 ACKS Constraints to surface the RAW excerpt. Renumbered Output Data Structure (now §12), Worked Examples (§13 with disarm scenarios added), Godot Implementation Notes (§14), and Revision History (§15). Bumped status to "Draft — adds §11 Disarming Failure Consequences."
