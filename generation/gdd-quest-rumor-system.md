# GDD: Quest and Rumor System

**Authority:** PROJECT-DESIGNED — the quest generation pipeline, rumor distribution mechanics, reward valuation formula, and quest completion detection are not derived from any ACKS sourcebook. ACKS provides the carousing hijink, reaction roll mechanics, treasure-to-XP conversion, and domain economics that constrain reward scaling.
**Status:** Draft
**Depends on ACKS rules:** `acore-campaign-hijinks.xml` (carousing hijink — Hear Noise throw, rumor value formula), `ax_reactions_and_influencing.xml` (reaction rolls, attitude framework, interaction tones), `acore_adventures_and_encounters.xml` (treasure XP rules, encounter distance), `acore_treasure_and_magic_items_rules.xml` (treasure type average values, special treasure tables), `acore_axioms_strongholds_and_domains.xml` (domain income, vassal duties, land grants, stronghold minimums, titles of nobility)
**Depends on project GDDs:** `gdd-poi-generation.md` (POI rumor seeds), `gdd-setting-generation.md` (dungeon seeds, political entities, factions, historical timeline, NPC ruler profiles), `gdd-npc-personality.md` (NPC knowledge categories, motivations, relationship data), `gdd-dungeon-layout.md` (dungeon size categories, level ranges), `gdd-dungeon-factions.md` (faction threat data), `gdd-terrain-system.md` (territory classification for encounter frequency), `gdd-settlement-layout.md` (settlement POIs, notice board locations), `gdd-cultural-religious-generation.md` (cultural and religious context for quest flavor)
**Modifiable by Claude Code:** Yes — all generation tables, reward formulas, distribution logic, and quest templates are engineering decisions.
**Last updated:** 2026-03-28

---

## 1. Purpose

Generate and manage the two primary information channels through which players learn about adventuring opportunities: **rumors** (unverified information gathered socially) and **quests** (specific tasks offered by specific NPCs with defined rewards). Together they form the connective tissue between the game's procedurally generated world features — dungeons, lairs, POIs, factions, domain politics — and the player's decision about what to do next.

### 1.1 Design Principle

Rumors and quests are views into the same underlying world data. A dungeon two hexes south of a trade road exists whether or not anyone mentions it. The rumor system controls *when and how* the player learns about it. The quest system controls *whether anyone is paying them to deal with it*.

Both systems are deterministic at the data layer. The LLM narrates quest descriptions and rumor phrasing but does not decide what quests exist, what they pay, or whether rumors are true. "Build mechanically, narrate retroactively" applies here as everywhere else.

### 1.2 Rumors vs. Quests

| Dimension | Rumor | Quest |
|---|---|---|
| Source | Any NPC, overheard, notice board, carousing | A specific named NPC (the questgiver) |
| Veracity | True, partially true, or false | Always factually accurate (the questgiver knows the situation) |
| Reward | No reward — the rumor points to explorable content that has its own treasure | Explicit reward attached (gold, item, land, political favor) |
| Obligation | None — the player can ignore it | Soft obligation — declining is fine, but the questgiver may remember |
| Completion | No tracking — the player discovers the truth by visiting the location | Tracked — specific completion condition triggers reward |
| Availability | Passive (reaction rolls) or active (carousing hijink, asking NPCs) | Available at the questgiver's location; some posted publicly |

---

## 2. Rumor System

### 2.1 Rumor Sources

Rumors are generated from existing world data. Every rumor points to a real map feature, a real NPC, or a real event — even false rumors are *about* a real thing (they just get the details wrong).

| Source | Rumor Content | Generated When |
|---|---|---|
| Wilderness POI | POI description, treasure, hazard, or magical effect | Setting generation (§4.6 of `gdd-poi-generation.md`) |
| Dungeon seed | Dungeon type, approximate danger, notable feature | Setting generation (Layer 7 narrative) |
| Monster lair | Creature type, approximate location, threat level | Lair placement (setting gen or dynamic lair placement) |
| Domain politics | Ruler actions, inter-realm tensions, succession crises | Domain simulation tick (monthly) |
| Settlement events | Crime wave, trade disruption, festival, plague, shortage | Settlement simulation tick (monthly) |
| NPC activities | NPC faction moves, hijink results, personal schemes | NPC action resolution |
| Active quests | The existence of a quest itself ("Baron Morson is offering a bounty...") | Quest generation |
| Historical | Ancient events, legendary figures, lost treasures | Setting generation (Layer 7 historical timeline) |

### 2.2 Rumor Record

```
Rumor:
  id: string                    # Unique identifier
  source_type: string           # "poi", "dungeon", "lair", "political", "settlement",
                                #   "npc", "quest", "historical"
  source_id: string             # ID of the world feature this rumor is about
  
  content_hint: string          # Mechanical fact for LLM to narrate
                                # e.g., "dungeon in hex 0812 contains undead, level 3-5"
  narrated_text: string         # LLM-generated NPC-voice version of the rumor
                                # e.g., "Miners from Valetown say the old silver mine
                                #   crawls with the restless dead. They sealed the
                                #   entrance last winter but the hammering hasn't stopped."
  
  accuracy: string              # "true" | "exaggerated" | "misleading" | "false"
  accuracy_detail: string       # What specifically is wrong (if not true)
                                # e.g., "treasure value doubled" or "wrong creature type"
  
  knowledge_category: string    # From gdd-npc-personality.md §6.2:
                                # "local", "professional", "political", "criminal",
                                # "religious", "military", "dungeon", "personal", "historical"
  
  # Distribution constraints
  origin_hex: string            # Hex ID where the rumor's subject is located
  settlement_range: int         # Max hex distance for NPCs to know this rumor
  min_npc_tier: string          # Minimum NPC tier to know this: "C" (anyone), "B", "A"
  freshness: string             # "persistent" (always available) | "current" (decays after
                                #   1d6 months) | "stale" (already widely known, no value)
  
  # State
  known_to_party: bool          # Has any PC heard this rumor?
  verified: bool                # Has the party visited the source and learned the truth?
  created_turn: int             # Game turn when the rumor was generated
```

### 2.3 Rumor Accuracy

Not all rumors are true. Accuracy is assigned at generation time based on source type:

| Source Type | True | Exaggerated | Misleading | False |
|---|---|---|---|---|
| POI | 50% | 25% | 15% | 10% |
| Dungeon | 40% | 30% | 20% | 10% |
| Lair | 50% | 25% | 15% | 10% |
| Political | 60% | 20% | 15% | 5% |
| Settlement | 70% | 15% | 10% | 5% |
| NPC | 40% | 20% | 20% | 20% |
| Quest | 100% | — | — | — |
| Historical | 30% | 30% | 25% | 15% |

**Accuracy types defined:**

- **True:** All material facts are correct (location, creature, treasure, danger level).
- **Exaggerated:** Core facts correct but magnitude inflated — treasure is described as 2× actual, monster is described as stronger than it is, danger is overstated.
- **Misleading:** Location or target is correct but key details are wrong — wrong creature type, wrong treasure type, wrong faction involved. Following the rumor leads to the right place but with wrong expectations.
- **False:** The rumor is fabricated or garbled beyond usefulness — the location is wrong, the threat doesn't exist, or the treasure was already taken. False rumors still point to a real hex (they don't reference nonexistent map features), but what the party finds there won't match the rumor.

Quest-sourced rumors (§2.1, "Active quests" row) are always accuracy = "true" because they come from the questgiver, who has firsthand or reliable information. The questgiver wouldn't post a bounty on a threat they aren't sure exists.

### 2.4 Rumor Distribution

Which NPCs know which rumors depends on geography, NPC knowledge categories, and NPC tier.

```
An NPC can share a rumor IF:
1. The NPC's settlement is within the rumor's settlement_range of the rumor's origin_hex
2. The NPC has a matching knowledge_category 
   (e.g., a guard knows "military" rumors, a priest knows "religious" rumors)
   OR the rumor's knowledge_category is "local" (everyone knows local rumors)
3. The NPC's tier meets or exceeds the rumor's min_npc_tier
4. The rumor's freshness is not "stale"

Special cases:
- Travelers and merchants know rumors from settlements they've visited 
  (extend effective settlement_range by their trade route distance)
- Adventurers and mercenaries know "dungeon" rumors at double range
- Rulers and their courts know "political" rumors realm-wide
- Thieves' guild members know "criminal" rumors city-wide regardless of range
```

### 2.5 Rumor Acquisition

Players acquire rumors through three channels:

#### 2.5.1 Carousing Hijink (ACKS Rules — Sacred)

Per `acore-campaign-hijinks.xml`: a character assigned to carousing makes a Hear Noise throw. On success, they learn one valuable rumor. The rumor's GP value for hijink income purposes is 3d12 × 5 gp per level of the perpetrator.

**Arbiter implementation:**

```
1. Character makes Hear Noise throw (per ACKS rules, including class modifiers)
2. On success:
   a. Build the eligible rumor pool for this settlement (per §2.4 filters)
   b. Weight rumors by value:
      - Rumors pointing to higher-treasure targets weigh more
      - Unheard rumors (known_to_party = false) weigh 3× vs. already-known
      - Quest-pointing rumors weigh 2× (they lead to additional rewards)
   c. Select one rumor from the weighted pool
   d. Mark rumor as known_to_party = true
   e. Calculate hijink GP value: 3d12 × 5 × perpetrator_level
   f. Present the rumor's narrated_text to the player
3. On failure: no rumor learned; check for "caught" per ACKS hijink rules
```

#### 2.5.2 Positive Reaction Roll (ACKS Rules — Sacred)

When a PC interacts with an NPC and the interaction result is **friendly** (per `ax_reactions_and_influencing.xml`), and the player asks about rumors, news, or local happenings, the NPC shares a rumor from their knowledge pool.

**Arbiter implementation:**

```
1. NPC attitude is friendly (from interaction roll or influence attempt)
2. Player asks about rumors/news/local information (detected by LLM from
   player dialogue, or via explicit "Ask about rumors" dialogue option)
3. Build the NPC's personal rumor pool:
   a. All rumors this NPC qualifies to know (per §2.4)
   b. Further filtered by conversational relevance:
      - If the player asked about a specific topic ("any trouble on the 
        south road?"), prioritize rumors matching that topic
      - If the player asked generally, select by recency and value
4. Select one rumor and present via LLM-narrated NPC dialogue
5. Mark rumor as known_to_party = true
6. NPCs with neutral attitude share rumors only with a successful 
   additional reaction check (roll ≥ 9 on the influence attempt)
7. Unfriendly/hostile NPCs never share rumors voluntarily
```

#### 2.5.3 Notice Boards and Public Postings

Settlements of Market Class IV or better have a public notice board (or equivalent — town crier, temple announcements, guild postings). The notice board displays:

```
1. All active quests whose questgiver is in this settlement or whose
   posting_range includes this settlement (see §3.5)
2. 1d3 general rumors from the settlement's rumor pool, selected for
   freshness and public relevance (knowledge_category = "local", 
   "military", or "political" only — not "criminal" or "personal")
3. Notice board content refreshes monthly (domain simulation tick)
```

The notice board is a settlement POI accessible on the street graph. When the party examines it, all posted content is revealed without any throw required.

### 2.6 Rumor Lifecycle

```
1. GENERATION: Rumors are created during setting generation (POI, dungeon, 
   historical rumors) or during play (political, settlement, NPC, quest rumors).

2. DISTRIBUTION: Each rumor exists in the settlement rumor pools of all 
   qualifying settlements (per §2.4). It is available to NPCs in those 
   settlements.

3. ACQUISITION: The player hears the rumor via carousing, reaction roll, 
   or notice board. The rumor is marked known_to_party = true.

4. VERIFICATION: When the party visits the rumor's source location and 
   discovers the truth, the rumor is marked verified = true. If the rumor 
   was false or misleading, the player sees the discrepancy.

5. DECAY: Rumors with freshness = "current" become "stale" after 1d6 months 
   of game time. Stale rumors are removed from NPC pools but remain in the 
   party's journal if already acquired. Persistent rumors (POI, dungeon, 
   historical) never decay. Political and settlement rumors are typically 
   current. Quest rumors decay when the quest expires or is completed.

6. INVALIDATION: If the rumor's source is destroyed (dungeon cleared, lair 
   eliminated, NPC killed, POI exhausted), the rumor becomes stale immediately.
```

---

## 3. Quest System

### 3.1 What Generates a Quest

Quests are not randomly scattered — they emerge from the needs and motivations of domain rulers, settlement authorities, religious leaders, guild masters, and other NPCs with both a **problem** and the **resources to offer a reward**. A quest exists when:

```
ALL of the following are true:
1. A THREAT or NEED exists in the game world
   (monster lair near a trade route, dungeon disgorging undead, 
    brigands seizing a settlement, artifact needing recovery, 
    missing person, contested territory)

2. An NPC with AUTHORITY is aware of the threat
   (domain ruler, settlement governor, temple high priest, guild master, 
    wealthy merchant — someone who can credibly offer a reward)

3. The NPC's own forces are INSUFFICIENT to handle it
   (garrison committed elsewhere, problem outside their jurisdiction, 
    threat too dangerous for available troops, political constraints 
    prevent direct action)

4. The NPC's MOTIVATION aligns with offering a reward
   (per gdd-npc-personality.md: security, duty, revenge, faith, power — 
    motivations that drive quest-giving behavior.
    An NPC motivated by "pleasure" or "survival" is less likely to 
    post bounties than one motivated by "duty" or "security")
```

### 3.2 Quest Generation Timing

Quests are generated at two points:

**At setting generation (Layer 6.5, after POIs and before LLM narration):**
- Scan all dungeon seeds, lair placements, and POIs
- For each, check if a nearby NPC authority figure meets the quest conditions (§3.1)
- Generate 1 quest per ~4 eligible threats (not every problem has a bounty on it)
- Target: 3–8 initial quests per standard region, scaling with map size

**During play (domain simulation tick, monthly):**
- New threats emerge: dynamic lairs placed, domain-level encounters, faction movements
- NPC authorities reassess: garrison losses, new intelligence, political shifts
- New quests generated when conditions in §3.1 are newly met
- Old quests expire when conditions change (threat eliminated by NPCs, questgiver dies, political situation shifts)

### 3.3 Quest Record

```
Quest:
  id: string
  status: string                  # "available" | "accepted" | "completed" | 
                                  #   "failed" | "expired" | "abandoned"
  
  # Questgiver
  questgiver_id: string           # NPC ID of the quest-offering authority
  questgiver_title: string        # "Baron Morson", "High Priestess Valenna"
  questgiver_settlement_id: string  # Where to find/return to the questgiver
  questgiver_motivation: string   # Primary motivation driving this quest offer
  
  # The Problem
  threat_type: string             # "monster_lair", "dungeon", "brigands", "creature", 
                                  #   "recovery", "escort", "domain_conquest",
                                  #   "reconnaissance", "construction", "diplomatic"
  threat_source_id: string        # ID of the dungeon, lair, POI, NPC, or hex involved
  threat_hex: string              # Primary hex where the problem is located
  threat_description_hint: string # Mechanical summary for LLM narration
  
  # Completion
  completion_type: string         # "clear_dungeon", "clear_lair", "kill_target",
                                  #   "retrieve_item", "escort_npc", "hold_territory",
                                  #   "deliver_message", "scout_hex", "build_structure"
  completion_target_id: string    # Specific target (dungeon_id, lair_id, npc_id, item_id)
  completion_verified_by: string  # "questgiver_report" (return to NPC) | 
                                  #   "automatic" (system detects completion) |
                                  #   "witness" (NPC in the field confirms)
  is_complete: bool               # Has the completion condition been met?
  
  # Reward
  reward: QuestReward             # See §3.4
  
  # Narration (LLM-generated)
  title: string                   # "The Ogre of the South Road"
  description: string             # 2-3 sentence quest description
  questgiver_dialogue: string     # What the NPC says when offering the quest
  completion_dialogue: string     # What the NPC says when the quest is turned in
  
  # Distribution
  posting_type: string            # "personal" (must speak to questgiver) |
                                  #   "posted" (on notice boards in range) |
                                  #   "broadcast" (town crier, widely known)
  posting_range: int              # Hex radius for notice board visibility
  
  # Timing
  created_turn: int               # Game turn when quest was generated
  expiry_turn: int or null        # Game turn when quest expires (null = no expiry)
  accepted_turn: int or null      # Game turn when player accepted
  completed_turn: int or null     # Game turn when completed
  
  # Party tracking
  accepting_pc_id: string or null # Which PC formally accepted (for reward targeting)
  reward_recipient_pc_id: string or null  # Which PC receives the reward (player chooses)
```

### 3.4 Quest Reward Structure

```
QuestReward:
  reward_type: string             # "gold", "item", "domain", "political", "mixed"
  
  # Gold component
  gold_value: int                 # GP amount offered (0 if no gold component)
  
  # Item component  
  item_id: string or null         # Specific magic item (if any)
  item_description: string or null  # "A sword of ancient make" (LLM narrated)
  
  # Domain component
  domain_grant: DomainGrant or null  # See §3.4.3
  
  # Political component
  political_favor: string or null # Description of non-material reward:
                                  #   "Imperial rank of Patrician (baron equivalent)"
                                  #   "Membership in the Merchant Guild"  
                                  #   "Formal alliance with House Valdris"
                                  #   "Right to recruit from the Legate's garrison"
  
  # Computed values
  total_gp_value: int             # Estimated total GP equivalent of all components
  variance_applied: float         # The ±10% variance factor actually applied
```

#### 3.4.1 Gold Rewards — Valuation Formula

The core design problem: ACKS provides no explicit guidance on quest reward values. What it does provide is a calibrated treasure economy: average lair treasure ≈ 4× the total XP value of the lair's monsters. Quest rewards must fit within this economy without breaking it.

**Principle:** The quest reward is a *bonus* on top of treasure the party finds at the threat site, not a replacement for it. The player's primary reward for clearing a dungeon is the dungeon's treasure. The quest reward is the premium for doing it on someone else's timetable and reporting back.

**Formula:**

```
base_reward = estimated_threat_xp × reward_multiplier

Where:
  estimated_threat_xp = total XP value of all monsters at the threat site
                        (sum of individual monster XP from the ACKS Monster 
                        Experience Points table)

  reward_multiplier = lookup by threat_type:
    monster_lair:      0.50  (lair has its own treasure; reward is modest bonus)
    dungeon:           0.25  (dungeon treasure is large; reward is smaller share)
    brigands:          0.75  (political urgency; less recoverable treasure)
    creature:          1.00  (single creature, little or no lair treasure)
    recovery:          *     (see §3.4.2)
    escort:            0.50  (per day of travel × party_level_gp_rate)
    domain_conquest:   *     (see §3.4.3)
    reconnaissance:    0.25  (low risk, low reward)
    construction:      *     (material cost provided, not a reward)
    diplomatic:        0.50  (per day of travel × party_level_gp_rate)

Apply variance: final_gold = base_reward × (0.90 + random(0, 0.20))
  # This is the ±10% variance from the base

Round to nearest 25 gp (for values < 500) or nearest 100 gp (for values ≥ 500).
  # Quest rewards should feel like round numbers an NPC would actually offer.
```

**Party level GP rate** (for time-based quests like escort and diplomatic):

```
party_level_gp_rate = average_party_level × 25 gp per day
  # A level 3 party earns ~75 gp/day for time-based quests
  # A level 7 party earns ~175 gp/day
  # This scales with the XP curve: higher-level parties need proportionally
  # more gold to make a quest worth their time
```

**Sanity bounds:**

```
minimum_reward = 25 gp    (no quest is worth posting for less)
maximum_gold_reward = 25,000 gp  (above this, rewards shift to domain grants 
                                   or political favors)
```

#### 3.4.2 Recovery Quests — Item Value

Recovery quests ("retrieve the stolen chalice," "find the lost codex") have a reward based on the item's value to the questgiver, not its market price.

```
recovery_reward = item_gp_value × 0.25 to 0.75 (based on questgiver motivation)
  # A desperate questgiver (motivation = security, faith) pays 50-75%
  # A calculating questgiver (motivation = power, wealth) pays 25-40%
  # The item itself may also be kept if the questgiver doesn't insist on return

If the item is a magic item: recovery_reward = item_sale_value × 0.50
  # Magic items don't grant XP if used, but do if sold.
  # The questgiver offering half the sale value is a fair trade for guaranteed 
  # payment vs. finding a buyer.
```

#### 3.4.3 Domain Grant Quests — Land Rewards

Domain grants are the highest-tier quest reward. They are offered only by rulers of Count rank or higher (per ACKS vassal rules, only rulers with vassals can grant sub-domains). The PC who receives the grant becomes a vassal of the questgiver's liege structure.

```
DomainGrant:
  hex_ids: Array[string]          # The 6-mile hex(es) being granted
  territory_class: string         # "civilized", "borderlands", "wilderness"
  estimated_families: int         # Current population (may be 0 for wilderness)
  stronghold_present: bool        # Is there an existing stronghold?
  stronghold_value: int           # GP value of existing stronghold (0 if none)
  vassal_obligations: string      # What the new vassal owes the liege
                                  # (per ACKS vassal duties: tribute, call to arms, etc.)
  title_granted: string           # "Baron", "Patrician", etc.

Domain grant conditions:
  1. The quest must involve securing the granted territory 
     (clearing monsters, driving out occupiers, building a stronghold)
  2. The granting NPC must be the legitimate ruler of the territory 
     or hold the authority to grant it
  3. Accepting the grant makes the PC a vassal — this has ongoing 
     mechanical consequences (tribute, call to arms, fealty)
  4. The PC who receives the domain MUST be of sufficient level to 
     hold it (level 9+ for a domain, per ACKS rules)
  5. If no PC is level 9+, the grant is held in trust until one qualifies
     (the territory is "reserved" but not yet a formal domain)
```

**GP-equivalent valuation for domain grants** (used only for quest value sorting and display, not for XP):

```
domain_gp_equivalent = stronghold_value 
                     + (estimated_families × monthly_income_per_family × 12)
  # Stronghold value is the big upfront component.
  # A borderlands domain of 1 hex with 100 families and a 22,500gp fort 
  # has a gp_equivalent of ~22,500 + (100 × 6 × 12) = ~29,700 gp
  # This is an enormous reward — appropriate for clearing a major dungeon 
  # or conquering a fortified settlement.
```

#### 3.4.4 Political Favor Rewards

Some quests pay in influence rather than gold. Political favors are non-tradeable rewards that unlock future options:

```
Political favors include:
  - Title/rank without land (honorary position, opens social doors)
  - Guild membership (access to guild markets, hirelings, services)
  - Military alliance (NPC will send troops if the PC is attacked)
  - Trade rights (monopoly on a trade route or commodity — per ACKS Charter of Monopoly)
  - Legal immunity (charges dropped, outstanding warrants cleared)
  - Recruitment access (hire from the NPC's garrison or retinue at favorable rates)
  - Information (the NPC shares strategic intelligence — treasure map, dungeon location, 
    political secrets — this is effectively a high-value rumor as additional reward)

Political favors do not have a clean GP equivalent. For quest sorting purposes, 
estimate at 1,000–5,000 gp based on the granting NPC's domain tier.
```

#### 3.4.5 Mixed Rewards

Many quests combine components. The total_gp_value is the sum of all components:

```
Examples:
  "500 gp and a healing potion" 
    → gold_value: 500, item_id: potion_healing, total_gp_value: ~1,000

  "The Barony of Valetown and 200 gp for provisions"
    → gold_value: 200, domain_grant: {valetown}, total_gp_value: ~30,000

  "Imperial rank of Patrician and 1,000 gp"
    → gold_value: 1000, political_favor: "Patrician rank", total_gp_value: ~4,000
```

### 3.5 Quest Type Templates

Each threat_type maps to a generation template defining what the quest looks like, what completion requires, and how reward scales.

#### 3.5.1 Monster Lair Quest

```
Trigger: Monster lair within 5 hexes of a settlement is causing problems
         (raids, attacks on travelers, livestock kills)
Questgiver: Domain ruler, settlement governor, or affected merchant
Completion: Lair is cleared (all monsters killed or driven off, 
            confirmed by return to questgiver)
Reward: gold = estimated_lair_xp × 0.50, ±10%
Example: "An ogre lair 2 hexes south has been killing livestock.
          Baron Morson offers 500 gp for its elimination."
```

#### 3.5.2 Dungeon Quest

```
Trigger: Dungeon is producing threats (undead, raiders, cult activity)
         that affect a nearby settlement or trade route
Questgiver: Domain ruler, temple authority, or affected guild
Completion: Primary dungeon threat neutralized (varies by dungeon:
            clear the top level, kill the boss faction leader, 
            seal the entrance, recover a specific item)
Reward: gold = estimated_dungeon_xp × 0.25, ±10%
        (lower multiplier because dungeon treasure is the big payout)
Example: "The old silver mine is disgorging undead. The Temple of Dawn
          offers 800 gp for anyone who cleanses it."
```

#### 3.5.3 Brigand/Occupier Quest

```
Trigger: Bandits, brigands, hostile warband, or enemy faction has seized
         a location (trade post, border town, road checkpoint)
Questgiver: The dispossessed ruler, their liege lord, or a trade guild
Completion: Occupying force defeated or driven out, location secured
Reward: gold = estimated_enemy_xp × 0.75, ±10%
        May include domain_grant if the location is a settlement/stronghold
Example: "Brigands have seized Valetown. Duke Hasfeld offers the Barony
          to anyone who drives them out and swears fealty."
```

#### 3.5.4 Creature Bounty Quest

```
Trigger: A specific dangerous creature (not a full lair — a lone monster
         or small group) is terrorizing an area
Questgiver: Domain ruler, village elder, affected farmer collective
Completion: Target creature(s) killed, proof brought to questgiver
            (head, hide, trophy — determined by creature type)
Reward: gold = creature_xp × 1.00, ±10%
        (high multiplier because no lair treasure to supplement)
Example: "A wyvern has been taking sheep from the high pastures.
          Palatine Telpirion offers 600 gp for its head."
```

#### 3.5.5 Recovery Quest

```
Trigger: An item of value has been lost or stolen — stolen relic, 
         missing artifact, lost trade goods, kidnapped person
Questgiver: The item's owner, a religious authority, or the person's family
Completion: Item/person returned to questgiver (or to a designated location)
Reward: gold = item_value × 0.25 to 0.75 (per §3.4.2), ±10%
        May include the item itself if the questgiver offers a copy or 
        the item is sacred to them (they pay gold, you keep the item's 
        mundane duplicate)
Example: "The Codex of Amber Rites was stolen from our library. 
          We offer 1,200 gp for its safe return."
```

#### 3.5.6 Escort Quest

```
Trigger: An NPC needs safe passage through dangerous territory
Questgiver: The NPC themselves, or their employer/family
Completion: NPC arrives safely at destination
Reward: gold = party_level_gp_rate × travel_days × 0.50, ±10%
        (half the daily rate because the party travels anyway — the 
        escort is a side obligation, not a full-time job)
Example: "I need safe passage to Azen Radokh. I can offer 225 gp
          for three days' protection through the mountains."
```

#### 3.5.7 Domain Conquest Quest

```
Trigger: A ruler wants territory secured that they cannot take themselves
         (hex clearing for domain expansion, wilderness fortress assault)
Questgiver: Domain ruler of Count rank or higher
Completion: Territory cleared per ACKS hex-clearing rules 
            (all lairs in target hexes eliminated)
Reward: domain_grant (the cleared hexes) + optional gold bonus
        See §3.4.3 for domain grant valuation
Example: "Clear the hexes south of my border and the land is yours.
          I will grant you the title of Baron and recognize your claim."
```

#### 3.5.8 Reconnaissance Quest

```
Trigger: A ruler or authority needs information about unexplored territory,
         a dungeon interior, enemy troop disposition, or a distant location
Questgiver: Domain ruler, military commander, merchant guild, mage
Completion: Return with verified intelligence (hex explored, dungeon 
            entrance mapped, troop count reported)
Reward: gold = party_level_gp_rate × travel_days × 0.25, ±10%
        May include a bonus rumor (intelligence reward — a free, guaranteed-true 
        rumor about a nearby high-value target)
Example: "Scout the three hexes beyond the Dark Wall and report what 
          you find. I will pay 150 gp for a reliable account."
```

### 3.6 Quest Generation Procedure

```
1. IDENTIFY ELIGIBLE THREATS
   Scan all map features within settlement_range of each NPC authority:
   a. Monster lairs within 5 hexes of a settlement or road
   b. Dungeons producing active threats (threat flag from domain simulation)
   c. Hostile factions occupying territory
   d. Dangerous creatures (dynamic lair encounters that aren't full lairs)
   e. Missing items or persons (from NPC event simulation)
   f. Unsecured territory on realm borders

2. FILTER BY NPC CAPABILITY
   For each eligible threat, find the nearest NPC authority who:
   a. Is aware of the threat (threat is within their intelligence range)
   b. Has resources to offer a reward (domain income > 0, or personal wealth)
   c. Cannot handle it themselves (garrison BR insufficient, or forces 
      committed elsewhere)
   d. Has a motivating personality trait (security, duty, revenge, faith, 
      power — not pleasure, survival, freedom)
   e. Has not already posted a quest for this threat

3. PROBABILITY GATE
   Not every eligible pairing becomes a quest. Roll:
   - 50% chance for threats within 3 hexes of the NPC's settlement
   - 25% chance for threats 4-8 hexes away
   - 10% chance for threats 9+ hexes away
   This prevents every lair from having a bounty on it.

4. SELECT QUEST TYPE
   Match the threat to the appropriate template (§3.5).

5. CALCULATE REWARD
   Apply the reward formula for the selected type (§3.4).
   Check questgiver's available wealth:
   - Gold reward cannot exceed 10% of the questgiver's monthly domain income
     × 12 (one year's discretionary spending) for ongoing rulers
   - One-time rewards (domain grants, political favors) have no income cap
   - If calculated gold exceeds the questgiver's means, reduce gold and 
     substitute political favors or future promises

6. GENERATE NARRATION (Layer 7)
   Pass to LLM: threat data, questgiver NPC profile, reward structure,
   cultural context. LLM produces: title, description, questgiver_dialogue, 
   completion_dialogue.

7. SET DISTRIBUTION
   - posting_type: "posted" if threat is urgent and public (monster attacks);
     "personal" if sensitive (political, criminal, recovery);
     "broadcast" if domain-level crisis
   - posting_range: 3 hexes for personal, 8 for posted, 15 for broadcast
   - expiry_turn: current_turn + 3d6 months (most quests don't wait forever)

8. CREATE QUEST-SOURCED RUMOR
   Generate a rumor with accuracy = "true" and source_type = "quest"
   pointing to this quest. The rumor enters NPC pools so players can 
   hear about quests even without visiting the notice board.
```

### 3.7 Quest Acceptance and Tracking

```
1. DISCOVERY: Player encounters the quest via notice board, NPC dialogue, 
   or rumor. Quest details are displayed in the quest journal UI.

2. ACCEPTANCE: Player can formally accept by speaking to the questgiver 
   (or for posted quests, by selecting "Accept" in the UI). Acceptance is 
   optional — the player can pursue the objective without accepting and 
   still claim the reward afterward if the questgiver is satisfied.

3. TRACKING: The quest journal tracks:
   - Quest status (available, accepted, completed, failed, expired)
   - Completion progress (for multi-step quests: "3 of 5 hexes cleared")
   - Time remaining before expiry
   - Questgiver location for turn-in

4. COMPLETION DETECTION:
   The engine monitors completion conditions automatically:
   - "clear_dungeon": all faction leaders in the target dungeon are dead
   - "clear_lair": all creatures in the target lair are dead or fled
   - "kill_target": the specific target NPC/creature is dead
   - "retrieve_item": the target item is in the party's inventory
   - "escort_npc": the NPC has arrived at the destination hex
   - "hold_territory": the target hex(es) have no hostile lairs for 1 month
   - "scout_hex": the party has entered and explored the target hex(es)
   
   When the condition is met, is_complete = true. The player must still 
   return to the questgiver (or designated turn-in point) to claim the reward.

5. TURN-IN: Player returns to the questgiver with completion verified.
   a. Questgiver dialogue plays (completion_dialogue from LLM)
   b. Player selects which PC receives the reward (§3.8)
   c. Reward is disbursed
   d. Quest status → "completed"
   e. If the quest had a quest-sourced rumor, that rumor becomes stale
```

### 3.8 Reward Recipient Selection

When a quest is completed and the player returns to the questgiver, the game presents the reward recipient selection:

```
GOLD REWARDS:
  - Player selects one PC to receive the gold
  - The PC can then redistribute to other party members manually
  - Gold grants 1 XP per 1 gp to the receiving character 
    (per ACKS treasure XP rules)
  - This is identical to treasure division — the game doesn't enforce 
    equal splitting; the player decides

ITEM REWARDS:
  - Player selects one PC to receive the item
  - Item goes into that PC's inventory
  - Magic items do not grant XP (per ACKS rules — items only grant XP if sold)
  - The player can transfer the item to another PC afterward

DOMAIN GRANTS:
  - Player selects one PC to receive the domain
  - That PC MUST be level 9+ (or the grant is held in trust per §3.4.3)
  - The receiving PC becomes a vassal of the questgiver's realm
  - This is a permanent, binding political relationship with ongoing obligations
  - Domain grants CANNOT be easily transferred between PCs
  - The game should present a clear confirmation dialog:
    "[PC Name] will become a vassal of [Questgiver] with the title of 
     [Title]. This carries ongoing duties including [obligations]. 
     Confirm?"

POLITICAL FAVORS:
  - Player selects one PC to receive the favor
  - Favor is recorded on that PC's character sheet
  - Some favors (guild membership, military alliance) can benefit the 
    whole party indirectly
  - Political favors cannot be transferred between PCs
```

---

## 4. Quest–Rumor Integration

Quests and rumors are tightly coupled. The flow from world state to player awareness works like this:

```
WORLD STATE (dungeon, lair, POI, domain event)
    ↓
RUMOR GENERATED (points to the world feature)
    ↓
PLAYER HEARS RUMOR (carousing, reaction roll, notice board)
    ↓
[Optional] QUEST GENERATED (NPC authority responds to the same world feature)
    ↓
PLAYER DISCOVERS QUEST (notice board, NPC dialogue, quest-sourced rumor)
    ↓
PLAYER PURSUES (explores the location, deals with the threat)
    ↓
PLAYER CLAIMS REWARD (if quest existed) + KEEPS TREASURE (always)
```

**Key interactions:**

- A rumor may point to a quest ("I hear Baron Morson is offering gold for someone to deal with that ogre") — this is a quest-sourced rumor with accuracy = "true"
- A rumor may point to a threat that has no quest attached ("There's something in the old mine") — the player can still explore for treasure, but there's no bonus reward
- A quest may exist that the player hasn't heard about — it sits on a distant notice board or in an NPC's dialogue tree until the player encounters it
- Completing a quest invalidates its quest-sourced rumors (they become stale)
- Clearing a threat without having accepted a quest can still result in reward if the player later visits the questgiver ("You're the ones who cleared the ogre? Here, take this — you've earned it")
- If the threat is eliminated by something other than the party (NPC forces, another faction, natural causes), the quest expires and any associated rumors become stale

---

## 5. Scaling and Balance

### 5.1 Reward vs. Treasure Economy

The quest reward system is calibrated to remain a *supplement* to the treasure economy, not a replacement.

```
Expected adventuring income per session (4 hours of play):
  - Treasure from exploration: the primary income source
  - Monster XP: secondary
  - Quest rewards: tertiary bonus (when available)

Target ratio of quest reward to total session income:
  - 10-25% for dungeon quests (dungeon treasure dominates)
  - 25-50% for lair quests (lair treasure is smaller)
  - 50-100% for creature bounties (little or no lair treasure)
  - N/A for domain grants (these are transformative, not incremental)
```

### 5.2 Quest Density

```
At any given time, a standard region should have:
  - 3-8 active quests (generated at setting creation)
  - 1-3 new quests generated per game month (from domain simulation)
  - 0-2 quests expiring per game month

The player should never lack for things to do, but should not be 
overwhelmed with obligations. Quests compete with freeform exploration 
for player attention — the balance should favor player choice, not 
checklist completion.
```

### 5.3 Level-Appropriate Quest Targeting

The quest generation system does not explicitly filter by party level — ACKS expects the party to assess risk themselves. However, the system naturally scales because:

```
1. Nearby threats are lower-level (lair density and dungeon placement 
   put weaker threats closer to starting settlements)
2. Distant threats are higher-level (and have higher rewards)
3. Domain grant quests only appear at high tier (requires Count+ questgiver)
4. Low-level quest rewards are small (tied to monster XP)
5. High-level quest rewards are large (tied to bigger threats)

The party can take a quest too dangerous for them. That's their problem.
ACKS does not protect players from overcommitting.
```

---

## 6. Data Model Summary

### 6.1 Persistence

```
Quest and Rumor data lives in SQLite:

tables:
  rumors:
    - All fields from §2.2 Rumor Record
    - Indexed by: source_id, origin_hex, knowledge_category, freshness

  quests:
    - All fields from §3.3 Quest Record
    - Indexed by: status, questgiver_settlement_id, threat_hex, threat_type

  quest_rewards:
    - All fields from §3.4 QuestReward
    - Foreign key: quest_id

  domain_grants:
    - All fields from §3.4.3 DomainGrant
    - Foreign key: quest_reward_id

  rumor_npc_pool:
    - Junction table: (rumor_id, settlement_id)
    - Precomputed during rumor distribution for fast NPC lookups
```

### 6.2 Integration Points

| System | Integration |
|---|---|
| Setting generation (Layer 6) | Initial quests and rumors generated after content seeding |
| Setting generation (Layer 7) | LLM narrates quest/rumor text |
| Domain simulation (monthly) | New quests/rumors from political events, threat emergence |
| NPC interaction | Friendly NPCs share rumors from their pool |
| Carousing hijink | Draws from settlement rumor pool |
| Notice board (settlement POI) | Displays posted quests and public rumors |
| Quest journal (UI) | Player tracks accepted quests, discovered rumors |
| Completion detection | Engine monitors quest conditions in real time |
| Treasure/XP system | Quest gold rewards grant 1 XP per 1 gp per ACKS rules |
| Domain management | Domain grants create new vassal relationships |
| Fog of war | Rumor locations shown as "rumored" markers on map until verified |

---

## 7. Worked Example

### 7.1 Setup

The setting generator has placed:
- A medium dungeon (old silver mine, undead-themed, level 3–5) in hex 0812, 3 hexes south of the trade road between Innford (hex 0710) and Stonehaven (hex 1010)
- A monster lair (ogre, 1 creature) in hex 0809, 2 hexes south of the trade road
- Baron Morson rules from Stonehaven (hex 1010), a Class V settlement with 120 families, borderlands territory

### 7.2 Rumor Generation

**Dungeon rumor (from setting gen):**
- content_hint: "old silver mine in hex 0812 infested with undead, level 3-5"
- accuracy: d100 → 35 → "true"
- knowledge_category: "dungeon"
- settlement_range: 8
- LLM narrated_text: "Miners sealed the old Silvervein shaft last winter after three men went in and didn't come back. The foreman says he heard scratching from behind the timbers."

**Ogre lair rumor (from lair placement):**
- content_hint: "ogre lair in hex 0809, attacks livestock on south road"
- accuracy: d100 → 80 → "exaggerated" (detail: "described as a pair of ogres, actually just one")
- knowledge_category: "local"
- settlement_range: 5
- LLM narrated_text: "A pair of ogres have moved into the ravine south of the road. They've taken three cows from Farmer Edric's herd this month alone."

### 7.3 Quest Generation

**Ogre quest:**
- Trigger: Ogre lair in hex 0809 is within 3 hexes of Baron Morson's settlement
- NPC filter: Baron Morson has motivation = "duty" + "security", domain income = 720 gp/month, garrison BR committed to road patrols
- Probability: 50% (within 3 hexes) → passes
- Quest type: creature bounty (single ogre, not a full lair faction)
- Reward: ogre XP = 200 (4+1 HD) → base_reward = 200 × 1.00 = 200 gp → variance → 210 gp → rounded to 200 gp
- Check questgiver means: 200 gp < 10% of (720 × 12) = 864 gp → fine
- posting_type: "posted" (public threat)
- posting_range: 8 hexes

**Dungeon quest:**
- Trigger: Undead from dungeon in hex 0812 are not yet actively threatening (no domain event), but Baron Morson is aware of the sealed mine
- Probability: 25% (4-8 hexes) → let's say it fails this time
- No dungeon quest generated at setting creation. It may be generated later if undead start emerging.

**Quest-sourced rumor:**
- content_hint: "Baron Morson of Stonehaven offers 200 gp bounty for killing an ogre on the south road"
- accuracy: "true"
- knowledge_category: "local"
- settlement_range: 8

### 7.4 Player Experience

1. Party arrives in Innford. A thief in the party attempts carousing (Hear Noise throw succeeds). The weighted pool includes the dungeon rumor, the ogre rumor (exaggerated), and the quest-sourced rumor. The quest-sourced rumor has 2× weight. Roll selects the quest rumor.

2. Player hears: *"Baron Morson over in Stonehaven is offering two hundred gold for anyone who deals with an ogre that's been killing livestock on the south road."*

3. Party decides to check the notice board in Innford (Market Class V — it has one). The board shows the ogre quest posted formally, plus one unrelated rumor about a sacred spring in the hills.

4. Party travels south, finds the ogre in hex 0809, kills it, takes proof (the head).

5. Party also finds the ogre's small cache: 350 gp in stolen goods (the lair's actual treasure, rolled from the ogre's treasure type).

6. Party returns to Stonehaven, speaks to Baron Morson. Quest completion detected (target creature dead). Player selects the fighter to receive the 200 gp quest reward.

7. Total haul: 350 gp (treasure) + 200 gp (quest reward) + ogre XP. The quest reward was ~36% of total gold income — within the target 25-50% range for lair quests.

---

## 8. Parameter Exposure

No player-facing parameters for this system. Quest density and reward scaling are functions of the generated world — more threats mean more quests, richer rulers offer bigger rewards. The POI density multiplier (from `gdd-poi-generation.md`) indirectly affects rumor volume (more POIs = more rumor seeds).
