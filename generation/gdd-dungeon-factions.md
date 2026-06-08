# GDD: Dungeon Faction Generation

**Authority:** PROJECT-DESIGNED — faction identification, territory assignment, and inter-faction relationship generation are not derived from any ACKS sourcebook. ACKS provides dungeon stocking procedures (which monsters go where), lair rules, wandering monster tables, and monster intelligence/alignment data. This GDD takes stocking output and imposes factional structure on it.
**Status:** Draft
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (stocking procedure, room contents), `le_monster_characteristics_stats.xml` and `acore_monster_catalog_*.xml` (monster intelligence, alignment, organization), `acore_adventures_and_encounters.xml` (wandering monster tables, encounter frequency)
**Depends on project GDDs:** `gdd-dungeon-layout.md` (room graph, corridor connectivity, doors, chokepoints), `gdd-npc-personality.md` (faction leader personality for intelligent factions)
**Modifiable by Claude Code:** Yes — all grouping rules, territory algorithms, and relationship generation are engineering decisions.
**Last updated:** 2026-06-08

---

## 1. Purpose

After the dungeon stocking procedure places monsters in rooms, this system groups those monsters into **factions** — coherent territorial groups that behave as a unit for purposes of alert propagation, wandering monster assignment, diplomacy, and dungeon ecology. Factions give dungeons political structure: the goblins in rooms 4-9 are not just isolated encounters — they're the Broken Fang tribe, they control the east wing, their chieftain is in room 7, and they hate the hobgoblins in rooms 14-20.

Factions are the primary unit of dungeon-level strategic play. The party can fight a faction, negotiate with it, play factions against each other, or ally with one to destroy another. The combat engine treats faction members as potential reinforcements. The wandering monster system draws from the faction controlling the territory the party is in.

---

## 2. What Is a Faction?

A faction is a group of monsters within a single dungeon level (or spanning connected levels) that:

1. **Share species identity** — same monster type, or closely related types under a single leadership
2. **Occupy contiguous territory** — their rooms connect without passing through another faction's territory (or contested/unclaimed space)
3. **Have a lair** — at least one room designated as their lair (central strongpoint)
4. **Share alert state** — when one group is alerted, the faction can mobilize
5. **Contribute wandering monsters** — the dungeon's wandering monster encounters in faction territory draw from that faction's roster

### 2.1 What Is NOT a Faction

- **Unintelligent monsters** (intelligence rating "Non" or "Animal" in ACKS terms) do not form factions unless magically controlled or tamed by an intelligent creature that IS part of a faction. A giant spider in room 12 is just a hazard, not a faction. A giant spider kept as a pet by the goblin chieftain in room 7 is part of the goblin faction.
- **Solitary monsters** that occupy a single room with no organizational ties are not factions. A troll squatting in room 22 is an independent threat.
- **Traps and dungeon features** are not factions.
- **Undead without a controller** are not a faction (they're mindless hazards), but undead commanded by a necromancer or vampire ARE a faction under that controller.

### 2.2 Faction Personality Biases (Member NPC Generation)

When the personality generator (`gdd-npc-personality.md`) creates the personality of any **intelligent** faction member or faction leader (Tier B+ NPCs — faction leaders are generated at faction-stocking time per §10.1 of the personality GDD), the faction contributes a **twelve-axis mean-shift** applied as the **faction step** of the generation bias stack:

```
sample → ability → culture → FACTION → alignment → clamp   (gdd-npc-personality.md §4.1)
```

This is a **second mean-shift on top of the cultural mean-shift** (cultural biases come from `gdd-cultural-religious-generation.md` §2; faction biases stack on top). It uses the **same flat twelve-axis schema and the same −2.0..+2.0 range** as cultural biases:

```
personality_weight_biases: {
  epistemic_curiosity: float,   # all twelve axes from gdd-npc-personality.md §3.2
  societal_orthodoxy: float,
  affective_compassion: float,
  stress_reactivity: float,
  self_interest: float,
  in_group_loyalty: float,
  mysticism: float,
  expressiveness: float,
  civility: float,
  jocularity: float,
  amorousness: float,
  epicureanism: float
}                               # each value a mean-shift in [-2.0, +2.0]
```

The profile should be consistent with `faction_type` and `alignment`. Examples:
- A **military** faction (`faction_type: "military"`, e.g. a disciplined orc warband): In-Group Loyalty **+1.5**, Stress Reactivity **−1.0** (drilled to stay steady), Societal Orthodoxy **+1.0** (chain of command), Civility **−0.5**.
- A **cult** faction (`faction_type: "cult"`, e.g. a necromancer's circle): Mysticism **+2.0**, In-Group Loyalty **+1.0**, Affective Compassion **−1.0**, Self-Interest **−0.5** (toward Opportunistic).
- A **tribal** faction (`faction_type: "tribal"`, e.g. a goblin tribe): In-Group Loyalty **+1.0**, Stress Reactivity **+1.0** (excitable), Self-Interest **−1.0** (toward Opportunistic), Civility **−1.0**.

Most faction members are Tier C transients (three sampled axes + Motivation per the personality GDD §4.2); the faction bias is applied to whichever axes are sampled. The faction leader is the primary consumer, since intelligent-faction leaders get full twelve-axis generation.

> **Note (rework history):** this GDD never used the retired four-axis tag vocabulary (`stoic`, `aggressive`, `evasive`, `righteous`, `pragmatic`, etc.) — it had no `personality_weight_biases` field at all before this rework. The twelve-axis faction bias above is **added** to fulfill the "faction biases apply as a second mean-shift after cultural biases" design, not converted from old tags.

---

## 3. Faction Identification Procedure

This runs AFTER dungeon stocking has placed all monsters in rooms. It reads the stocking output and produces faction records.

### 3.1 Step 1: Identify Candidate Groups

```
1. Collect all stocked monster placements on this dungeon level:
   - For each room: monster type, number appearing, lair flag, 
     intelligence rating, alignment

2. Group by species:
   - All orcs → one candidate group
   - All goblins → one candidate group
   - All giant rats → one candidate group (but see §3.2 for intelligence filter)
   - All skeletons → one candidate group (but see §3.2 for controller check)

3. Filter by intelligence:
   - Monster intelligence "Non" or "Animal" → EXCLUDE from faction candidates
     UNLESS the room's stocking notes indicate they are controlled/tamed
     (e.g., "6 giant rats, trained by the goblin shaman")
   - Monster intelligence "Semi" → INCLUDE only if organized by the 
     monster's published organization data (e.g., wolves in a pack have 
     semi intelligence but pack behavior — include them as a faction)
   - Monster intelligence "Low" or higher → INCLUDE

4. Check for controllers:
   - Unintelligent undead (skeletons, zombies) in the same dungeon as 
     a necromancer or vampire → assign to that controller's faction
   - Tamed beasts near an intelligent monster → assign to the tamer's faction
   - Summoned/bound creatures → assign to the summoner's faction
```

### 3.2 Step 2: Merge Related Groups (Eclectic Dungeons)

In dungeons with many small groups of different species, strict same-species grouping produces too many tiny factions. Merge when appropriate:

```
Merge candidate groups into a single faction when:

1. BEASTMAN ALLIANCE: Multiple beastman types with compatible alignment 
   AND a leader strong enough to dominate them
   - E.g., goblins + hobgoblins under a hobgoblin chieftain
   - E.g., orcs + ogre (ogre is the muscle, orcs are the troops)
   - Merge condition: same alignment, shared rooms or adjacent rooms, 
     one group has a published leader type that outranks the other
   
2. MASTER-SERVANT: An intelligent creature controls less-intelligent ones
   - E.g., evil cleric + undead; wizard + summoned creatures; 
     dragon + kobold servants; vampire + charmed humanoids
   - Merge condition: controller-type relationship exists in the 
     stocking or can be inferred from published monster behavior
   
3. ECOLOGICAL SYMBIOSIS: Monsters described as living together in ACKS
   - E.g., kobolds + giant rats (kobolds commonly keep rats)
   - E.g., bugbears + goblins (bugbears often bully goblins into service)
   - Merge condition: the ACKS monster entry explicitly describes 
     the cohabitation or servitude relationship

4. ECLECTIC DUNGEON RULE: If the dungeon has 6+ distinct intelligent 
   monster types on one level, AND multiple types share alignment AND 
   occupy adjacent rooms with no barrier between them → merge into a 
   "coalition faction" with the strongest HD creature as faction leader
   - This prevents a 20-room level from having 10 one-room factions
   - The coalition gets a descriptive name reflecting its mixed nature
     (e.g., "The Chaos Band" for a chaotic coalition of mixed humanoids)
```

### 3.3 Step 3: Identify Solitary Threats

After grouping, any remaining intelligent monster that:
- Occupies only 1 room
- Has no organizational ties to any faction
- Is powerful enough to hold territory alone (4+ HD, or any creature with special abilities)

...is tagged as a **solitary threat**, not a faction. These get a simplified record (see §7.2). They are relevant for dungeon ecology (other factions may avoid them or pay tribute to them) but don't have faction territory or wandering monster contributions.

Weak solitary monsters (< 4 HD, single room, no ties) are simply independent encounters — no faction record needed.

---

## 4. Territory Assignment

### 4.1 Lair as Territory Center

Every faction's territory is anchored on its **lair room(s)** — the room(s) flagged as lairs during dungeon stocking. The lair is the faction's strongpoint: where treasure is stored, where the leader resides, where reinforcements rally.

```
For each faction:
1. Identify all lair rooms (stocking flag: "lair = true" for this monster type)
2. If multiple lairs of the same type exist on one level:
   - If they are connected (reachable without crossing another faction's territory):
     → single faction with multiple lair rooms
   - If they are separated by another faction's territory:
     → two separate factions of the same species (rival clans, splinter groups)
3. The lair room(s) form the faction's CORE territory — always controlled
```

### 4.2 Territory Expansion from Lair

Territory expands outward from the lair along the room graph, stopping at boundaries:

```
1. Start from the lair room(s)
2. Flood-fill outward along the room graph (rooms connected by doors/corridors):
   a. Add each adjacent room to the faction's territory IF:
      - The room contains members of this faction, OR
      - The room is empty/unoccupied AND is closer to this lair than 
        to any other faction's lair (by graph distance)
   b. STOP expansion at:
      - A room occupied by a DIFFERENT faction
      - A defensible chokepoint (see §4.3) — even if the next room is empty
      - A room with a solitary threat that the faction cannot overpower
      - The dungeon boundary (stairs, dead ends)
3. Mark each room in the territory:
   - "core" — lair room(s) and rooms containing faction members
   - "patrol" — empty rooms the faction controls (wandering monsters patrol here)
   - "frontier" — rooms at the edge of territory, adjacent to another 
     faction or contested zone
```

### 4.3 Chokepoint Detection

Territory boundaries should fall at defensible positions, not arbitrary midpoints. The dungeon layout generator (gdd-dungeon-layout.md) produces room and corridor connectivity data that enables chokepoint detection:

```
A chokepoint exists when:
1. A single corridor or door is the ONLY connection between two 
   sections of the dungeon graph
   - Formally: removing this edge from the room graph disconnects 
     the graph (it's a bridge edge)
   - These are natural faction boundaries

2. A narrow corridor (5' width, or a single door) connects two 
   larger areas
   - Even if not a true bridge edge, narrow passages are defensible
   - Factions preferentially claim territory up to these points

3. A locked, barred, stuck, or secret door separates two areas
   - These are strong boundaries — factions on either side may not 
     even know the other exists

4. A vertical transition (stairs, ladder, pit) between levels
   - Faction territory rarely spans levels unless the faction is 
     large enough to dominate both sides of the transition

Detection algorithm:
  - Run bridge-edge detection on the room graph (DFS-based, O(V+E))
  - Flag all bridge edges as potential faction boundaries
  - Flag all doors (especially locked/barred) as potential boundaries
  - Flag all narrow corridors (width < 10') as potential boundaries
  - Territory expansion (§4.2) uses these flags as stop conditions
```

### 4.4 Contested and Unclaimed Territory

Not every room belongs to a faction:

```
UNCLAIMED territory:
  - Rooms equidistant from two or more faction lairs with no 
    faction members present
  - Rooms beyond all factions' patrol range
  - Rooms separated from all factions by chokepoints with no 
    faction on either side
  - These rooms have no faction-specific wandering monsters — 
    they use the dungeon-level wandering monster table instead

CONTESTED territory:
  - Rooms where two factions' expansion zones overlap
  - Both factions patrol here; encounters may include either
  - Higher encounter frequency in contested rooms (both factions 
    send patrols, plus they fight each other)
  - Contested zones are natural sites for inter-faction skirmishes 
    that the party may stumble into
```

---

## 5. Faction Relationships

### 5.1 Relationship Types

Each pair of factions on the same dungeon level (or connected levels) has a relationship:

| Relationship | Description | Mechanical Effect |
|---|---|---|
| `allied` | Cooperate, share information, reinforce each other | Alert propagation crosses faction lines; combined defense |
| `neutral` | Aware of each other, no active conflict | No alert sharing; ignore each other's territory |
| `rival` | Compete for territory or resources, occasional skirmishes | Contested zones between them; will not reinforce each other |
| `hostile` | Active warfare, kill on sight | Frequent skirmishes in contested zones; can be leveraged by the party |
| `vassal` | One faction serves the other (tribute, obedience) | Vassal reinforces master; master protects vassal territory |
| `unaware` | Don't know the other exists (separated by secret doors, distance) | No interaction until discovered |

### 5.2 Relationship Generation

```
For each pair of factions on the same level:

1. CHECK AWARENESS:
   - If separated by a secret door or more than 8 rooms of unclaimed 
     territory → "unaware"
   - Otherwise → aware (proceed to step 2)

2. CHECK ALIGNMENT COMPATIBILITY:
   - Same alignment → bias toward allied or neutral
   - One step apart (L-N or N-C) → bias toward neutral or rival
   - Opposed (L-C) → bias toward rival or hostile

3. CHECK SPECIES RELATIONSHIP:
   - Published enmities (e.g., dwarves vs. goblins, elves vs. orcs) → 
     bias toward hostile
   - Published alliances (e.g., kobolds serve dragons) → bias toward vassal
   - Same species but separate factions (rival clans) → rival

4. CHECK POWER BALANCE:
   - If one faction has 3x+ the total HD of the other → bias toward vassal
   - If roughly equal → no modifier
   - If one is much weaker but occupies a defensible position → rival 
     (they can hold their ground despite being outmatched)

5. ROLL relationship from weighted table using the biases above:
   - Default weights: allied 10%, neutral 30%, rival 30%, hostile 20%, vassal 10%
   - Modify weights based on steps 2-4
   - Select one relationship
```

### 5.3 Relationship Effects

**Allied factions:**
- Alert in one faction propagates to the allied faction after 1d4 rounds
- If the party attacks one, the other may send reinforcements (morale check for the allied faction leader; success = reinforcements arrive in 2d4 rounds)
- Negotiating with one gives advantage with the other (+1 reaction)

**Rival factions:**
- Contested territory between them
- The party can play them against each other (reaction bonus when offering to hurt the rival: +2)
- Neither will reinforce the other
- May actively give the party information about the rival's weaknesses

**Hostile factions:**
- Active skirmishing — the party may encounter inter-faction battles in contested zones
- Strong incentive to ally with the party against their enemy (+3 reaction when offering to fight the enemy)
- Dead members of the hostile faction found in frontier rooms (evidence of ongoing conflict)

**Vassal factions:**
- Alert propagates upward to master faction immediately
- Master can order vassal to attack (vassal morale check; failure = vassal cowers but doesn't help)
- Killing the master may cause the vassal faction to flee, surrender, or declare independence

---

## 6. Wandering Monster Integration

### 6.1 Faction-Aware Wandering Monsters

The standard ACKS wandering monster check (1-in-6 per 2 turns) still applies. What changes is the *source* of the wandering monster:

```
When a wandering monster check succeeds:

1. Determine which territory the party is in:
   - Faction core/patrol → draw from THAT faction's roster
   - Contested zone → 50/50 between the two contesting factions
   - Unclaimed territory → draw from the dungeon-level general table

2. Draw from the faction roster:
   - The wandering monster is a PATROL from that faction
   - Size: 1d4 members for small factions, 2d4 for large factions,
     or use the faction's published patrol size from ACKS organization data
   - These are NOT new monsters — they're drawn from the faction's 
     existing population. Killing wandering patrols depletes the faction.

3. Patrol behavior:
   - Patrols from the faction's own territory are confident (normal morale)
   - Patrols in contested territory are cautious (-1 morale)
   - Patrols in enemy territory are either raiding parties (+1 morale, 
     aggressive) or scouts (-2 morale, will flee if spotted)
```

### 6.2 Faction Population and Depletion

Wandering monster patrols are drawn directly from the faction's stocked room population — there is no separate patrol pool. The monsters patrolling the corridors ARE the monsters from the rooms, temporarily away from their posts.

```
1. Each faction has a STARTING POPULATION (sum of all stocked members)
   and a CURRENT POPULATION (decremented as members are killed)

2. When a wandering monster encounter produces a faction patrol:
   - The patrol members are temporarily absent from their rooms
   - If the party then enters those rooms, they find fewer monsters
   - If the patrol is killed, the faction's current population drops permanently
   - If the patrol returns (party evades or parleys), members return to rooms

3. When the party kills faction members in rooms, current population drops,
   which means fewer members available for future patrols

4. At 50% population loss: faction morale degrades (-1 to all morale checks)
   At 75% population loss: faction may abandon territory, retreat to lair,
   attempt to flee the dungeon, or surrender to the party

5. When a faction is wiped out in its lair (current population = 0):
   - Faction is removed from the wandering monster table entirely
   - Faction territory becomes unclaimed
   - Adjacent factions may expand into the vacated territory over time

6. REPLENISHMENT: Each faction recovers 1d6 members per week, up to 
   its starting population maximum. This represents reinforcements 
   arriving from the broader monster population outside the dungeon 
   (beastmen from the wilderness, new undead raised by the necromancer, 
   etc.). Replenishment only occurs while the faction still holds its 
   lair — a faction driven from its lair cannot replenish.
   - Replenished members are distributed back to their original rooms
   - If original rooms are now occupied by another faction or the party,
     replenished members go to the lair instead
```

This unified model means the party faces a strategic choice: clear rooms systematically to deplete the faction before hitting the lair, or strike the lair directly while patrols are still out (fewer defenders at home, but risk patrols returning mid-fight). It also means that a party who clears half a faction and then leaves for a week returns to find the faction partially recovered — pressure to finish the job.

---

## 7. Output Data Structures

### 7.1 Faction Record

```
DungeonFaction:
  id: string                      # "faction_goblin_east_wing"
  dungeon_id: string              # Which dungeon this faction belongs to
  dungeon_level: int              # Which level (factions rarely span levels)
  
  # Identity
  name: string                    # "Broken Fang Tribe" (LLM-generated or template)
  species: string                 # Primary species: "goblin", "orc", "skeleton", etc.
  secondary_species: Array[string]  # For coalition factions: ["goblin", "hobgoblin"]
  alignment: string               # Lawful, Neutral, Chaotic
  faction_type: string            # "tribal", "military", "cult", "pack", "coalition", "undead_horde"
  
  # Leadership
  leader_npc_id: string or null   # NPC personality record for the faction leader
  leader_room_id: int             # Which room the leader is in (usually the lair)
  leader_hd: float                # Leader's HD (for quick power comparisons)
  
  # Population
  starting_population: int        # Sum of all stocked members at generation
  current_population: int         # Decremented as members are killed
  patrol_size: string             # Dice expression for wandering encounter size: "1d4", "2d4"
  members_on_patrol: int          # Currently out of rooms on patrol (0 when no active patrol)
  
  # Territory
  lair_room_ids: Array[int]       # Room IDs flagged as lairs
  core_room_ids: Array[int]       # Rooms containing faction members
  patrol_room_ids: Array[int]     # Empty rooms the faction controls
  frontier_room_ids: Array[int]   # Rooms at faction boundary
  
  # Relationships
  relationships: Array[FactionRelationship]
  
  # Behavioral (from combat_behavior_tags on the monster profile)
  alert_state: string             # "unaware", "cautious", "alerted", "mobilized"
  default_reaction_modifier: int  # Applied to reaction rolls with this faction

  # Personality biasing for member NPC generation (twelve-axis, see §2.2)
  personality_weight_biases: Dictionary  # { axis_name: float } — twelve-axis mean-shifts
                                  # (gdd-npc-personality.md §3.2), each in [-2.0, +2.0];
                                  # applied as the FACTION step (second mean-shift, after culture)
  
  # Morale tracking
  morale_modifier: int            # Cumulative modifier from losses, leader death, etc.
  population_loss_percent: float  # Tracked for morale degradation thresholds
```

### 7.2 Solitary Threat Record

```
SolitaryThreat:
  id: string
  dungeon_id: string
  dungeon_level: int
  room_id: int                    # The one room they occupy
  monster_type: string            # "troll", "owlbear", etc.
  hd: float
  alignment: string
  territory_radius: int           # Rooms adjacent that other factions avoid (usually 1-2)
  tribute_from: Array[string]     # Faction IDs that pay tribute to avoid this creature
  notes: string                   # E.g., "The troll in room 22; goblins leave food outside"
```

### 7.3 Faction Relationship Record

```
FactionRelationship:
  faction_a_id: string
  faction_b_id: string
  relationship: string            # From §5.1
  contested_room_ids: Array[int]  # Rooms disputed between these factions (if rival/hostile)
  notes: string                   # "Goblins pay tribute in food; hobgoblins demand 
                                  #  more each month" or "Active border skirmishing 
                                  #  in the connecting corridor"
```

### 7.4 Territory Map

The territory map is a lookup from room ID to faction control status:

```
TerritoryMap:
  room_assignments: Dictionary    # { room_id: TerritoryEntry }

TerritoryEntry:
  status: string                  # "core", "patrol", "frontier", "contested", "unclaimed",
                                  #  "solitary_threat_zone"
  controlling_faction_id: string or null    # null for unclaimed
  contesting_faction_ids: Array[string]     # For contested rooms, which factions claim it
  solitary_threat_id: string or null        # For solitary threat zones
```

---

## 8. Alert Propagation

### 8.1 How Alerts Spread

When the party engages a faction (combat, detected by guards, triggers an alarm):

```
1. IMMEDIATE: The room where combat/detection occurs is alerted
   - Monsters in adjacent rooms connected by open doors/corridors 
     hear the noise immediately

2. ROOM-BY-ROOM: Alert spreads through faction territory at 1 room per round
   - Closed doors slow propagation by 1 additional round
   - Locked/barred doors block propagation entirely until someone opens them
   - Alert ONLY spreads through rooms controlled by the same faction
     (it does not cross into rival/hostile territory)

3. ALLIED FACTION ALERT: If the alerted faction has allies:
   - Alert reaches the allied faction after 1d4 rounds AFTER reaching 
     the frontier room closest to the ally
   - The allied faction's leader makes a morale check:
     Success → sends reinforcements (arriving in 2d4 rounds from their lair)
     Failure → stays put, defends own territory

4. FACTION RESPONSE by alert level:
   - "cautious": guards double, patrols increase, doors barred
   - "alerted": all members move to defensive positions, lair fortified
   - "mobilized": entire faction converges on the threat location
   - Escalation depends on the severity of the triggering event:
     Noise/detection → cautious
     Combat with a patrol → alerted
     Assault on core territory → mobilized
```

### 8.2 Alert Decay

```
- If the party retreats and is not pursued:
  - Alert state downgrades by one step every 3 turns of quiet
  - mobilized → alerted → cautious → unaware
- If the party returns the same day: alert resets to "cautious" at minimum
- If the party returns the next day: faction has reset defenses but 
  reverts to "unaware" unless they posted extra guards (intelligent 
  factions with leader HD 3+ do this automatically)
```

---

## 9. Faction Names and Flavor

### 9.1 Name Generation

Faction names are generated from templates or by the LLM:

**Template pattern:** `[Adjective] [Noun] [Group-word]`

```
Adjective pool (by alignment):
  Lawful:  Iron, Steel, Sworn, Faithful, Silver, Sacred, Crown
  Neutral: Grey, Shadow, Stone, Silent, Old, Pale, Bone
  Chaotic: Broken, Bloody, Black, Wretched, Vile, Burning, Rotting

Noun pool (by species):
  Goblin:  Fang, Claw, Rat, Skull, Eye, Tooth, Ear
  Orc:     Axe, Blood, War, Skull, Iron, Thunder, Flame
  Undead:  Grave, Bone, Dust, Shade, Crypt, Hollow, Wail
  Human:   Blade, Shield, Crown, Tower, Gate, Dawn, Hawk

Group-word pool (by faction_type):
  tribal:    Tribe, Clan, Band, Horde
  military:  Company, Legion, Guard, Brigade, Warband
  cult:      Cult, Brotherhood, Circle, Order, Covenant
  pack:      Pack, Swarm, Brood, Nest
  coalition: Alliance, Pact, Host
  undead:    Horde, Host, Legion, Throng
```

**Example outputs:** "Broken Fang Tribe" (chaotic goblin tribal), "Iron Axe Warband" (lawful orc military), "Pale Bone Host" (neutral undead horde), "Shadow Blade Company" (neutral human military).

The LLM can override template names with more creative alternatives during dungeon narrative generation.

---

## 10. Multi-Level Faction Considerations

### 10.1 When Factions Span Levels

Most factions are confined to a single dungeon level. A faction spans levels only when:

```
1. The faction is large enough to occupy rooms on both sides of 
   a level transition (stairs/ramp)
2. The faction controls the transition point (guards posted at the stairs)
3. The monster type is described as spanning levels in ACKS 
   (e.g., a dragon whose lair is on level 5 but whose hoard chamber 
   is on level 6)
```

When a faction spans levels, it is still ONE faction record, but its territory data includes room IDs from multiple levels. Alert propagation through level transitions takes an extra 2 rounds (someone has to go up/down the stairs).

### 10.2 Level-Appropriate Faction Strength

Deeper dungeon levels have stronger factions. The stocking procedure handles this (deeper = higher HD monsters), but the faction system should validate:

```
- Level 1: faction leaders typically 2-4 HD
- Level 2-3: faction leaders typically 3-6 HD
- Level 4-5: faction leaders typically 5-8 HD
- Level 6+: faction leaders typically 8+ HD, possibly with spellcasting
```

A faction whose leader is significantly weaker than the dungeon level suggests is either a vassal of a stronger faction or doomed to be displaced soon (flavor note for the LLM).

---

## 11. Integration Points

### 11.1 Consumers of Faction Data

- **Combat engine** — alert propagation, reinforcement timing, morale modifiers from faction state
- **Wandering monster system** — faction-aware encounter source selection (§6)
- **Reaction roll system** — faction relationship modifiers applied to NPC reactions
- **Encounter narrative** — LLM receives faction context (name, relationships, alert state) for narrating encounters
- **Player knowledge tracking** — which factions the party has discovered, what they know about each
- **Rumor system** — NPCs in nearby settlements may have rumors about dungeon factions ("the goblins in the old mine are warring with the hobgoblins — might be a good time to strike")

### 11.2 What This System Does NOT Generate

- Individual monster stat blocks (that's the stocking procedure + monster catalog XML rules)
- Room-level encounter content (that's the stocking procedure)
- Dungeon map layout (that's `gdd-dungeon-layout.md`)
- Treasure placement (that's the stocking procedure)

This system takes stocking output as input and adds factional structure on top of it.

---

## 12. Worked Example

```
Dungeon: Abandoned Dwarven Mine, Level 1 (15 rooms)
Stocking output:
  Room 1: Empty (entrance)
  Room 2: 4 goblins
  Room 3: Empty
  Room 4: 6 goblins (LAIR)
  Room 5: 3 goblins + 2 trained giant rats
  Room 6: Empty
  Room 7: Locked door → 8 skeletons
  Room 8: 4 skeletons
  Room 9: Necromancer (level 3 mage, Chaotic) + 2 skeletons (LAIR)
  Room 10: Empty
  Room 11: Giant spider (unintelligent, solitary)
  Room 12: Empty
  Room 13: 5 orcs
  Room 14: 8 orcs + 1 orc sub-chieftain (LAIR)
  Room 15: 3 orcs

Chokepoints detected: 
  - Narrow corridor between rooms 6 and 7 (bridge edge)
  - Locked door at room 7 entrance
  - Single corridor from room 10 to rooms 11-12

Step 1 — Candidate groups:
  - Goblins (rooms 2, 4, 5): intelligent, lair in room 4 → candidate
  - Giant rats (room 5): animal intelligence, but trained by goblins → 
    assign to goblin group
  - Skeletons (rooms 7, 8, 9): non-intelligent, but controlled by 
    necromancer → assign to necromancer group
  - Necromancer (room 9): intelligent, lair in room 9 → candidate
  - Giant spider (room 11): animal intelligence, no controller → NOT a faction
  - Orcs (rooms 13, 14, 15): intelligent, lair in room 14 → candidate

Step 2 — Merge check:
  - Goblins + giant rats → merged (rats are trained by goblins)
  - Skeletons + necromancer → merged (necromancer controls skeletons)
  - Orcs → remain separate (no alliance with goblins or necromancer)
  - No eclectic dungeon rule needed (only 3 intelligent groups)

Step 3 — Solitary threats:
  - Giant spider in room 11: unintelligent, solitary, 2 HD → too weak 
    for solitary threat status. Tagged as independent encounter only.

Result: 3 factions identified.

Faction 1: "Broken Tooth Clan" (goblins)
  Species: goblin (+ trained giant rats)
  Lair: room 4
  Core territory: rooms 2, 4, 5
  Patrol territory: rooms 1, 3 (empty rooms on their side of the dungeon)
  Frontier: room 6 (stops at chokepoint before room 7)
  Leader: goblin chieftain (2 HD, in room 4)
  Population: 13 goblins + 2 giant rats = 15
  Patrol size: 1d4

Faction 2: "Pale Grave Cult" (necromancer + undead)
  Species: human (necromancer) + skeleton (controlled)
  Lair: room 9
  Core territory: rooms 7, 8, 9
  Patrol territory: none (compact, fully occupied)
  Frontier: room 7 (locked door = strong boundary)
  Leader: necromancer (level 3 mage, in room 9)
  Population: 1 necromancer + 10 skeletons = 11
  Patrol size: 1d4

Faction 3: "Iron Axe Warband" (orcs)
  Species: orc
  Lair: room 14
  Core territory: rooms 13, 14, 15
  Patrol territory: room 10 (empty room between orcs and spider)
  Frontier: room 10 (toward spider/unclaimed zone), room 12 (if expanding)
  Leader: orc sub-chieftain (2 HD, in room 14)
  Population: 16 orcs + 1 sub-chieftain = 17
  Patrol size: 1d6

Unclaimed territory: rooms 6 (between goblins and undead, neither claims 
  it because of chokepoint), 11 (spider room), 12 (empty, distant from all lairs)

Relationships:
  Goblins ↔ Undead: "unaware" (locked door at room 7; goblins don't know 
    what's behind it)
  Goblins ↔ Orcs: "hostile" (both are beastmen competing for the dungeon; 
    goblins are weaker and stay on their side)
  Undead ↔ Orcs: "unaware" (separated by unclaimed rooms and the spider)

Territory map:
  Room 1: patrol (Broken Tooth Clan)
  Room 2: core (Broken Tooth Clan)
  Room 3: patrol (Broken Tooth Clan)
  Room 4: core (Broken Tooth Clan) — LAIR
  Room 5: core (Broken Tooth Clan)
  Room 6: unclaimed
  Room 7: core (Pale Grave Cult) — locked door boundary
  Room 8: core (Pale Grave Cult)
  Room 9: core (Pale Grave Cult) — LAIR
  Room 10: patrol (Iron Axe Warband)
  Room 11: unclaimed (spider hazard)
  Room 12: unclaimed
  Room 13: core (Iron Axe Warband)
  Room 14: core (Iron Axe Warband) — LAIR
  Room 15: core (Iron Axe Warband)
```

---

## 13. Godot Implementation Notes

### 13.1 File Organization

```
engine/subsystems/generation/dungeon_factions/
  faction_identifier.gd          # Step 1-3: group, merge, filter
  territory_assigner.gd          # Step 4: flood-fill territory with chokepoint detection
  relationship_generator.gd      # Step 5: inter-faction relationships
  faction_wandering.gd           # Faction-aware wandering monster source selection
  alert_propagation.gd           # Runtime alert state management
  faction_names.gd               # Template-based name generation
```

### 13.2 Key Algorithms

- **Bridge edge detection:** DFS-based, O(V+E) on the room graph. Run once after dungeon generation.
- **Territory flood-fill:** BFS from each lair room, O(V+E). Runs in parallel for all factions, with conflict resolution for contested rooms.
- **Alert propagation:** BFS from the alert source, 1 room per round, respecting door/faction boundaries. Runs during combat as a real-time system.

### 13.3 Runtime Performance

Faction identification and territory assignment for a 30-room dungeon level with 3-5 factions: under 10ms. This is pure graph traversal on a small graph. Alert propagation is also trivial — BFS on a graph with < 50 nodes.

---

## 14. Revision History

- **2026-03-19:** Initial draft. Same-species faction grouping with intelligence filter. Lair-centered territory expansion with chokepoint boundaries. Contested and unclaimed territory. Five-type relationship system. Faction-aware wandering monsters with depletion tracking. Alert propagation through faction territory. Multi-level considerations. Full worked example.
- **2026-03-19 (rev 2):** Simplified patrol model — wandering patrols draw directly from stocked room population (no separate patrol pool). Added ACKS-compatible replenishment: 1d6 members per week up to starting max, only while faction holds its lair. Faction wipeout removes them from wandering monster table entirely.
- **2026-06-08:** Added faction-level **twelve-axis `personality_weight_biases`** (new §2.2 and a field on the `DungeonFaction` record) consistent with the `gdd-npc-personality.md` rework. Faction biases apply as a **second mean-shift on top of cultural biases** (stack order: sample → ability → culture → faction → alignment → clamp), using the same flat twelve-axis schema and −2.0..+2.0 range as cultural biases. Documented `faction_type`-consistent example profiles (military / cult / tribal). Audit note: this GDD never used the retired four-axis tag vocabulary and had no personality bias field previously, so this is an addition rather than a tag conversion.
