# GDD: NPC Personality and Behavioral Generation

**Authority:** PROJECT-DESIGNED — NPC personality, motivation, relationship, and speech generation are not derived from any ACKS sourcebook. ACKS provides stat generation (class, level, ability scores, morale) and demographic distribution rules. This GDD covers everything that makes an NPC a *character* rather than a stat block.
**Status:** Draft
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (NPC demographics, ability score generation, appearance tables), `ax_henchmen_recruitment_expanded.xml` and `acore_equipment.xml` (hiring procedures, loyalty, morale), `acore-setting-construction-rules.xml` (NPC counts by market class)
**Depends on project GDDs:** `gdd-setting-generation.md` (cultural groups, religions, political entities for context), `gdd-settlement-layout.md` (POI placement, district assignment for NPC location)
**Modifiable by Claude Code:** Yes — trait lists, motivation tables, generation algorithms, and prompt designs are all engineering decisions.
**Last updated:** 2026-03-19

---

## 1. Purpose

Generate believable, mechanically functional NPC personalities for every named character in the game — from a tavern keeper the party meets once to a domain ruler who drives political events for months of campaign play. The output must serve two consumers simultaneously:

1. **The LLM narration system** — needs personality traits, speech patterns, knowledge, motivations, and relationships to produce consistent, distinctive NPC dialogue and behavior across multiple encounters.
2. **The deterministic game engine** — needs behavioral weights, loyalty modifiers, disposition scores, and reaction adjustments to make mechanical decisions without LLM calls.

The generation system must work at three scales: individual NPC creation (one character at a time during encounters), batch creation (20+ NPCs when stocking a settlement), and ruler profiles (domain simulation behavioral AI).

---

## 2. ACKS Constraints

**NPC stat generation (ACore + L&E):**
- Class and level determined by demographics (market class → NPC count tables)
- Ability scores generated per L&E procedures
- Equipment derived from class, level, and settlement wealth
- Morale score from ACKS loyalty tables (modified by CHA, treatment, etc.)

**Reaction rolls (ACore Ch.6):**
- 2d6 + CHA modifier + situational modifiers → reaction result
- Results range from hostile to friendly
- This is the mechanical backbone of NPC first impressions
- Personality data should INFORM reaction modifiers, not replace the roll

**Henchman loyalty (ACore Ch.3 + Ch.7):**
- Loyalty score tracked per henchman
- Modified by employer CHA, pay, treatment, shared danger
- Checked at specific trigger points (offered bribe, employer defeated, etc.)
- Personality traits can provide flavor for loyalty decisions but don't override the mechanical system

**Three-tier NPC persistence (design brief §12.3):**
- **Tier A (full PC):** Complete stat block, full personality, persistent across sessions
- **Tier B (named NPC):** Simplified stats, personality summary, persists while relevant
- **Tier C (transient):** Minimal stats, generated on encounter, not persisted unless promoted

Personality depth scales with tier. A Tier C guard gets a one-line demeanor. A Tier B guild master gets a full personality profile. A Tier A henchman gets everything.

---

## 3. Personality Trait System

### 3.1 Trait Architecture

Each NPC personality is built from **four independent trait axes**. Each axis has a value that can be expressed as a descriptive tag for the LLM and as a numeric weight for the game engine.

| Axis | What It Drives | Mechanical Effect |
|---|---|---|
| **Temperament** | How the NPC reacts emotionally to situations | Reaction roll modifier in specific contexts |
| **Motivation** | What the NPC wants long-term | Drives NPC decisions, quest hooks, betrayal conditions |
| **Social Style** | How the NPC interacts with others | LLM dialogue tone, negotiation behavior |
| **Moral Compass** | Where the NPC draws ethical lines | Alignment-adjacent but more granular; bribery/loyalty modifiers |

### 3.2 Temperament Axis

Temperament describes the NPC's default emotional posture. Selected from a weighted random table, influenced by class and alignment:

| Tag | Description | Engine Effect |
|---|---|---|
| `stoic` | Controlled, unemotional, hard to read | -1 to social proficiency throws to read this NPC |
| `jovial` | Cheerful, boisterous, quick to laugh | +1 reaction when first met in social settings |
| `nervous` | Anxious, jumpy, over-explains | -1 morale in dangerous situations; easier to intimidate |
| `aggressive` | Confrontational, quick to anger | -1 reaction in disputes; +1 morale in combat |
| `melancholic` | Sad, reflective, pessimistic about the future | Neutral mechanically; strong LLM voice signal |
| `cunning` | Calculating, watchful, says less than they know | +1 to resist interrogation/charm; -1 first reaction (suspicious) |
| `passionate` | Intense, emotional, committed to causes | +1 loyalty to causes they believe in; -1 loyalty when disillusioned |
| `serene` | Calm, patient, unflappable | +1 morale; resistant to provocation |
| `paranoid` | Distrustful, sees threats everywhere | -2 first reaction; +1 to detect ambushes/deception |
| `gregarious` | Social, talkative, knows everyone | +1 reaction; knows more rumors; harder to keep secrets from |

**Class influence on temperament weights:**
- Fighters: bias toward `stoic`, `aggressive`, `passionate`
- Clerics: bias toward `serene`, `passionate`, `stoic`
- Mages: bias toward `cunning`, `melancholic`, `stoic`
- Thieves: bias toward `cunning`, `nervous`, `gregarious`
- NPCs without a class: flat distribution

### 3.3 Motivation Axis

What the NPC wants. This is the most gameplay-relevant trait because it drives quest hooks, betrayal conditions, and NPC decision-making.

| Tag | Description | Quest/Hook Potential |
|---|---|---|
| `wealth` | Accumulate money, property, treasure | Will trade favors for gold; bribable; merchant quests |
| `power` | Gain authority, influence, control | Political intrigue; will betray for advancement |
| `knowledge` | Learn, discover, understand | Wants rare books, ruins explored, mysteries solved |
| `security` | Protect self, family, community from threats | Defensive quests; will pay for protection; risk-averse |
| `revenge` | Punish someone who wronged them | Assassination quests; long-term grudge plots |
| `faith` | Serve their deity, spread their religion | Temple quests; crusade hooks; alignment-driven |
| `legacy` | Build something lasting — a family, institution, monument | Construction quests; dynasty building; patronage |
| `freedom` | Escape constraints — debt, servitude, law, obligation | Smuggling; jail breaks; anti-authority plots |
| `pleasure` | Enjoy life — feasts, art, romance, adventure | Carousing; patron of arts; frivolous spending |
| `duty` | Fulfill their role — soldier, priest, ruler, parent | Reliable but predictable; follows orders; loyalty-driven |
| `survival` | Just get through today alive | Desperate; will do anything when cornered; low ambition |
| `redemption` | Atone for past wrongs | Confession hooks; willing to take risks for moral causes |

Each NPC gets a **primary motivation** (strongest driver) and a **secondary motivation** (fallback or complicating factor). The combination creates nuance: a guard motivated by `duty` + `wealth` is corruptible in the right circumstances. A thief motivated by `freedom` + `revenge` has a specific enemy.

**Alignment influence:**
- Lawful NPCs: bias toward `duty`, `faith`, `legacy`, `security`
- Neutral NPCs: bias toward `wealth`, `knowledge`, `survival`, `pleasure`
- Chaotic NPCs: bias toward `power`, `freedom`, `revenge`, `pleasure`

### 3.4 Social Style Axis

How the NPC talks and interacts. This directly shapes LLM dialogue generation.

| Tag | Description | LLM Prompt Effect |
|---|---|---|
| `formal` | Proper speech, titles, protocol | Uses complete sentences, honorifics, measured words |
| `blunt` | Says exactly what they mean, no diplomacy | Short sentences, direct statements, can be rude |
| `flattering` | Compliments, agrees, tells people what they want to hear | Sycophantic when it serves them; hard to get honest answers |
| `laconic` | Few words, long pauses, lets silence do the work | Very short responses; the LLM should use 1-2 sentences max |
| `verbose` | Talks at length, storyteller, over-explains everything | Long responses; tangents; hard to get to the point |
| `evasive` | Deflects questions, changes subject, speaks in riddles | Rarely gives straight answers; useful for mystery NPCs |
| `warm` | Friendly, empathetic, asks about the other person | Inclusive language; remembers details about the party |
| `intimidating` | Uses size, status, or menace to control conversation | Threats, implications, dominance displays |
| `scholarly` | Precise vocabulary, citations, analytical framing | Uses technical terms; explains reasoning; pedantic |
| `streetwise` | Slang, informal, code words, reads the room | Colloquial; drops hints; uses underworld terminology |

### 3.5 Moral Compass Axis

Where the NPC draws ethical lines. More granular than alignment — a Lawful NPC can still be `pragmatic`, and a Chaotic NPC can be `honorable` within their own code.

| Tag | Description | Mechanical Effect |
|---|---|---|
| `righteous` | Strong moral code, won't compromise principles | Cannot be bribed; will refuse immoral quests; +2 loyalty to aligned causes |
| `honorable` | Keeps their word, respects agreements, fair dealing | Moderate bribery resistance; reliable once committed |
| `pragmatic` | Does what works; morality is situational | No bribery modifier; evaluates cost/benefit |
| `opportunistic` | Looks for advantage; bends rules when profitable | -2 bribery resistance; may betray if the price is right |
| `ruthless` | Will do anything to achieve their goals | No ethical limits; dangerous ally; dangerous enemy |
| `conflicted` | Wants to do right but keeps failing or being forced | Internal drama; unreliable but sympathetic; redemption hooks |

---

## 4. Trait Generation Procedure

### 4.1 Full Generation (Tier A and B NPCs)

```
1. DETERMINE CONTEXT:
   - NPC's class, level, alignment (from ACKS stat generation)
   - NPC's role (ruler, merchant, guard, priest, thief, henchman, etc.)
   - Settlement culture and religion (from setting generation)
   - District where the NPC is located (from settlement layout)

2. ROLL TEMPERAMENT:
   - Build weighted table from class influence + alignment + random
   - Select one tag

3. ROLL MOTIVATION (primary and secondary):
   - Build weighted table from alignment influence + role influence
   - Select primary motivation
   - Select secondary motivation (reroll if same as primary)
   - Role overrides: a merchant always has wealth as primary or secondary;
     a priest always has faith; a soldier always has duty
     (these are baseline, not absolute — the LLM can justify exceptions)

4. ROLL SOCIAL STYLE:
   - Build weighted table from class + role + temperament
   - A cunning temperament biases toward evasive or flattering
   - A jovial temperament biases toward warm or verbose
   - Scholarly class (mage) biases toward scholarly or formal
   - Thief class biases toward streetwise or evasive

5. ROLL MORAL COMPASS:
   - Build weighted table from alignment:
     - Lawful: 40% righteous, 30% honorable, 20% pragmatic, 10% conflicted
     - Neutral: 10% righteous, 25% honorable, 35% pragmatic, 20% opportunistic, 10% conflicted
     - Chaotic: 5% honorable, 20% pragmatic, 35% opportunistic, 30% ruthless, 10% conflicted

6. GENERATE DISTINCTIVE FEATURE:
   - One memorable physical or behavioral quirk (see §4.3)
   - This is the "you'd recognize them in a crowd" detail

7. ASSEMBLE PERSONALITY RECORD (see §7)
```

### 4.2 Quick Generation (Tier C NPCs)

Tier C NPCs get a stripped-down personality — enough for a single interaction:

```
1. Roll ONE temperament tag
2. Assign a default motivation from their role:
   - Guard → duty, Merchant → wealth, Priest → faith, 
     Beggar → survival, Noble → power
3. Skip social style and moral compass (use defaults: 
   formal for nobles/priests, blunt for soldiers, streetwise for criminals)
4. Generate one distinctive feature
5. Store as a compact record (see §7.2)
```

If a Tier C NPC becomes important (the party keeps interacting with them), they're promoted to Tier B and the full generation procedure fills in the missing axes.

### 4.3 Distinctive Features

Every NPC gets one memorable detail. Rolled from a table (or LLM-generated for Tier A/B):

**Physical features:** scar across the cheek, missing finger, distinctive birthmark, unusually tall/short, limps, heterochromatic eyes, elaborate tattoo, always sweating, shock of white hair, missing teeth, branded mark, prosthetic hand.

**Behavioral features:** hums constantly, fidgets with a coin, speaks to an absent person, quotes scripture, writes everything down, never makes eye contact, laughs at inappropriate moments, always eating, compulsive hand-washer, collects something odd, refers to self in third person.

**Possessions:** wears a distinctive hat, carries an unusual weapon, always has a specific animal companion, wears mismatched boots, carries a book they're always reading, wears too much jewelry, has a lucky charm they touch when nervous.

These are stored as a string and passed to the LLM for incorporation into descriptions and dialogue. They're the detail that makes players remember "oh, the coin-flipping merchant" rather than "generic merchant #4."

---

## 5. Relationship Network Generation

### 5.1 When Relationships Are Generated

Relationships are generated at **settlement stocking time** (batch generation) and **during play** (as NPCs interact). The settlement generator creates the initial relationship web; gameplay modifies it.

### 5.2 Relationship Types

| Type | Description | Mechanical Effect |
|---|---|---|
| `family` | Blood relation or marriage | High loyalty baseline; betrayal is exceptional |
| `friend` | Personal affection and trust | Moderate loyalty; will share rumors and do favors |
| `rival` | Competition for the same goal or position | Negative disposition; will undermine; source of conflict |
| `enemy` | Active hostility | Will work against each other; may hire PCs to act |
| `employer` | Economic relationship (employs the other) | Loyalty driven by pay and treatment |
| `patron` | Supports the other's work or ambitions | Will fund, protect, or vouch for their client |
| `debtor` | Owes money, a favor, or a life debt | Obligated; resentful or grateful depending on moral compass |
| `mentor` | Taught or trained the other | Respect-based; the student may outgrow the teacher |
| `co-conspirator` | Shares a secret or illegal enterprise | Bound by mutual risk; betrayal is catastrophic for both |
| `unrequited` | One-sided attraction or admiration | Source of drama; the admirer is manipulable |

### 5.3 Relationship Generation Procedure (Settlement Batch)

```
1. For each Tier B+ NPC in the settlement:
   a. Generate 2-5 relationships with other NPCs in the settlement
   b. Relationship count scales with social style:
      - gregarious, warm: 4-5 relationships
      - formal, scholarly: 2-3 relationships
      - laconic, paranoid: 1-2 relationships
   
   c. Relationship type selection:
      - Same faction: bias toward friend, employer, patron, co-conspirator
      - Rival faction: bias toward rival, enemy
      - Same role (two merchants, two priests): bias toward rival or friend
      - Same district: bias toward friend, employer, family
      - Different class/level gap: bias toward patron/mentor (higher to lower)
   
   d. For each relationship, assign:
      - type (from §5.2)
      - strength: 1-5 (1 = acquaintance, 5 = defining relationship)
      - mutual: bool (is the feeling reciprocated?)
      - public: bool (is this relationship known to others?)
      - note: string (one-line context, e.g., "childhood friends who grew apart")

2. Validate network:
   - Every faction leader has at least 1 relationship with each other faction leader
   - The settlement ruler has relationships with major POI operators
   - The thieves' guild master has at least 1 co-conspirator and 1 enemy
   - No NPC is completely isolated (minimum 1 relationship)
```

### 5.4 Relationship Data

```
Relationship:
  npc_a_id: string
  npc_b_id: string
  type: string                # From §5.2
  strength: int               # 1-5
  mutual: bool                # Both feel this way?
  public: bool                # Known to others?
  note: string                # One-line context
```

---

## 6. NPC Knowledge System

### 6.1 Purpose

NPCs know things. What they know determines what they can tell the player during conversation, what rumors they can share, and what information the LLM can have them reveal. Knowledge is not infinite — an NPC knows things appropriate to their role, location, relationships, and motivation.

### 6.2 Knowledge Categories

| Category | Examples | Source |
|---|---|---|
| `local` | Settlement layout, shop locations, who lives where | Assigned to all resident NPCs |
| `professional` | Trade prices, craft techniques, spell components | Assigned based on class/role |
| `political` | Who rules, alliances, feuds, succession issues | Assigned to nobles, officials, guild leaders |
| `criminal` | Black market, thieves' guild, smuggling routes | Assigned to thieves' quarter NPCs, criminals |
| `religious` | Temple practices, religious conflicts, prophecies | Assigned to clerics, devout NPCs |
| `military` | Troop movements, fortification weaknesses, patrol routes | Assigned to soldiers, guards, mercenaries |
| `dungeon` | Rumors about nearby dungeons, monster sightings, treasure tales | Assigned randomly; adventurers and travelers know more |
| `personal` | Secrets about other NPCs, affairs, debts, crimes | Assigned based on relationships |
| `historical` | Local history, ancient ruins, legendary events | Assigned to scholars, elders, priests |

### 6.3 Knowledge Assignment

```
1. BASELINE KNOWLEDGE (all resident NPCs):
   - Local: settlement name, major POIs, ruler identity, market day
   - Scale: Tier C NPCs know 3-5 local facts; Tier B know 8-12; Tier A know 15+

2. ROLE-BASED KNOWLEDGE:
   - Each NPC role grants knowledge in specific categories
   - A merchant knows: professional (trade), local (shops, suppliers), 
     political (trade regulations, who controls what)
   - A guard knows: military (patrol routes, garrison strength), 
     local (who comes and goes), criminal (known troublemakers)
   - A priest knows: religious (theology, temple politics), 
     historical (religious history), personal (confessions — if moral compass allows sharing)

3. RELATIONSHIP-BASED KNOWLEDGE:
   - For each relationship, the NPC gains 1-3 personal knowledge items about 
     the other NPC (their habits, secrets, weaknesses)
   - co-conspirator relationships grant shared criminal knowledge
   - rival relationships grant knowledge of the rival's weaknesses

4. RUMOR KNOWLEDGE:
   - Each NPC has a rumor pool: 2-5 rumors they might share
   - Rumors are drawn from: dungeon hooks (from gdd-dungeon-layout.md seeds), 
     regional events (from gdd-setting-generation.md Layer 7), 
     NPC gossip (from relationships), and random/false rumors (10-20% are wrong)
   - Motivation influences which rumors an NPC shares:
     - wealth-motivated: rumors about treasure
     - faith-motivated: rumors about religious matters
     - revenge-motivated: rumors about their enemy
```

### 6.4 Knowledge Data

```
KnowledgeEntry:
  npc_id: string
  category: string            # From §6.2
  fact: string                # Plain-language statement
  accuracy: string            # "true", "partially_true", "false", "outdated"
  source: string              # How the NPC learned this ("personal observation", 
                              #  "heard from [npc_id]", "professional knowledge", "rumor")
  willingness_to_share: string  # "freely", "if_trusted", "if_paid", "never"
  shared_with_party: bool     # Has this already been revealed? (prevents repetition)
```

---

## 7. Output Data Structures

### 7.1 Full NPC Personality (Tier A and B)

```
NPCPersonality:
  npc_id: string
  tier: string                     # "A", "B", "C"
  
  # Identity (from ACKS stat generation)
  name: string                     # From name banks per cultural group
  class: string                    # Fighter, Mage, Cleric, Thief, etc.
  level: int
  alignment: string                # Lawful, Neutral, Chaotic
  race: string
  culture_id: string               # Cultural group for name/speech conventions
  religion_id: string              # Religious tradition (if any)
  role: string                     # "merchant", "guard", "priest", "ruler", "thief", etc.
  location_poi_id: string          # Which POI this NPC is associated with
  
  # Personality (from this GDD)
  temperament: string              # Tag from §3.2
  motivation_primary: string       # Tag from §3.3
  motivation_secondary: string     # Tag from §3.3
  social_style: string             # Tag from §3.4
  moral_compass: string            # Tag from §3.5
  distinctive_feature: string      # From §4.3
  
  # LLM Context (assembled for narration)
  personality_summary: string      # 2-3 sentence human-readable summary for LLM prompts
                                   # e.g., "Gruff and blunt retired soldier who runs the 
                                   # tavern. Motivated by security for his family and a 
                                   # lingering desire for revenge against the bandit lord 
                                   # who killed his brother. Speaks in short, direct 
                                   # sentences and fidgets with an old military medallion."
  speech_notes: string             # Specific LLM instructions for dialogue voice
                                   # e.g., "Short sentences. Military slang. Never says 
                                   # 'please.' Calls everyone 'lad' or 'lass.'"
  
  # Relationships
  relationships: Array[Relationship]  # From §5.4
  
  # Knowledge
  knowledge: Array[KnowledgeEntry]    # From §6.4
  
  # Disposition toward party (runtime, updated during play)
  disposition: int                 # -5 to +5, starts at 0, modified by interactions
  disposition_history: Array       # Log of what changed disposition and why
  
  # Domain ruler fields (only for NPCs who rule domains, see §8)
  ruler_profile: RulerProfile or null
```

### 7.2 Compact NPC Personality (Tier C)

```
NPCPersonalityCompact:
  npc_id: string
  tier: "C"
  name: string
  role: string
  temperament: string
  motivation_primary: string       # Default from role
  distinctive_feature: string
  disposition: int                 # Default 0
  knowledge: Array[string]         # 3-5 plain-text facts (not full KnowledgeEntry objects)
```

---

## 8. Domain Ruler Behavioral Profiles

### 8.1 Purpose

NPCs who rule domains (barons, counts, kings, guild masters, high priests) need behavioral profiles that drive the domain simulation (design brief §13.5). These profiles determine what the ruler does during monthly domain turns — expand territory? raise taxes? build fortifications? wage war? — without requiring an LLM call for every ruler every month.

### 8.2 Ruler Decision Weights

Each ruler has weighted preferences across domain action categories:

```
RulerProfile:
  expansion_weight: float       # 0.0-1.0, tendency to conquer/claim territory
  fortification_weight: float   # 0.0-1.0, tendency to build defenses
  economic_weight: float        # 0.0-1.0, tendency to invest in trade/markets
  military_weight: float        # 0.0-1.0, tendency to raise and maintain armies
  diplomatic_weight: float      # 0.0-1.0, tendency to form alliances and treaties
  religious_weight: float       # 0.0-1.0, tendency to support temples and religious works
  research_weight: float        # 0.0-1.0, tendency to sponsor magic research/learning
  oppression_weight: float      # 0.0-1.0, willingness to tax heavily, use force on populace
  
  aggression_toward: Dictionary  # {realm_id: float} — hostility toward specific neighbors
  alliance_preference: Dictionary  # {realm_id: float} — desire to ally with specific neighbors
  
  crisis_response: string       # "aggressive", "defensive", "diplomatic", "cautious"
                                # How the ruler reacts to unexpected threats
```

### 8.3 Deriving Ruler Weights from Personality

The ruler profile is derived from the NPC's personality traits, not generated independently:

```
Base weights from MOTIVATION:
  wealth → economic +0.3, oppression +0.1
  power → expansion +0.3, military +0.2
  knowledge → research +0.3, diplomatic +0.1
  security → fortification +0.3, military +0.2
  revenge → aggression toward target +0.5, military +0.2
  faith → religious +0.4, oppression +0.1 (enforce religious law)
  legacy → fortification +0.2, economic +0.2
  freedom → diplomatic -0.1, oppression -0.2
  duty → balanced weights, slight military bias
  
Modifiers from MORAL COMPASS:
  righteous → oppression -0.2, diplomatic +0.1
  honorable → diplomatic +0.2, oppression -0.1
  pragmatic → no modifier (balanced)
  opportunistic → expansion +0.1, oppression +0.1
  ruthless → expansion +0.2, oppression +0.3, diplomatic -0.2

Modifiers from TEMPERAMENT:
  aggressive → expansion +0.1, military +0.1
  stoic → fortification +0.1
  cunning → diplomatic +0.1, economic +0.1
  paranoid → fortification +0.2, military +0.1, diplomatic -0.1
  serene → diplomatic +0.1, religious +0.1

Normalize all weights to sum to ~1.0 (soft normalization — 
weights are relative preferences, not probabilities)
```

### 8.4 Monthly Domain AI

During the campaign monthly turn, the domain simulation evaluates each NPC ruler's available actions and scores them against the ruler's weights:

```
1. List available domain actions for this ruler (from XML rules reference)
2. Score each action: base_value × relevant_weight
3. Apply situational modifiers (at war → military actions score higher)
4. Select the highest-scoring action (or top 2-3 for large domains)
5. Execute deterministically — no LLM call needed
6. LLM narrates the outcome retroactively if the player interacts with it
```

---

## 9. LLM Integration

### 9.1 Personality Summary Generation

For Tier A and B NPCs, the `personality_summary` and `speech_notes` fields are generated by the LLM during NPC creation:

**Prompt structure:**
```
Generate a personality summary and speech notes for this NPC:
  Name: {name}
  Role: {role} in {settlement_name}
  Class: {class}, Level: {level}, Alignment: {alignment}
  Culture: {culture_name}
  Temperament: {temperament}
  Primary Motivation: {motivation_primary}
  Secondary Motivation: {motivation_secondary}
  Social Style: {social_style}
  Moral Compass: {moral_compass}
  Distinctive Feature: {distinctive_feature}
  Key Relationships: {relationship_summaries}

Write a 2-3 sentence personality summary that a game master could use 
to roleplay this character consistently. Then write specific speech 
notes (sentence length preference, vocabulary level, verbal tics, 
forms of address) in 1-2 sentences.
```

This is a **Tier 1 cached generation** — generated once, stored permanently. No LLM call on subsequent encounters.

### 9.2 Template Fallback (No LLM Mode)

When running without an LLM (mock provider), personality summaries are assembled from templates:

```
Template: "{temperament_phrase} {role} who {motivation_phrase}. 
           {social_style_phrase}. {distinctive_feature}."

Example output: "A cunning merchant who seeks wealth above all else. 
Speaks in flattering tones and rarely gives a straight answer. 
Always fidgets with a gold coin between his fingers."
```

Template phrases per trait tag are stored in `data/templates/personality_templates.json`. These produce adequate but less creative results than LLM generation.

### 9.3 Dialogue Context Assembly

When the player talks to an NPC, the LLM context includes:

```
NPC Context Package:
  personality_summary: string     # The cached 2-3 sentence summary
  speech_notes: string            # How they talk
  current_disposition: int        # Toward this PC
  disposition_trend: string       # "warming", "cooling", "stable"
  relevant_knowledge: Array       # Filtered to topics the conversation might touch
  relevant_relationships: Array   # NPCs the conversation might reference
  recent_events: Array            # What's happened recently that this NPC would know about
  motivation_hooks: Array         # What the NPC wants that the party could help/hinder
```

The context assembler pulls only **relevant** data, not the NPC's complete knowledge and relationship graph. A conversation about buying swords doesn't need the blacksmith's opinion on temple politics.

---

## 10. Generation Timing and Performance

### 10.1 When NPCs Are Generated

| Trigger | NPCs Generated | Tier | Method |
|---|---|---|---|
| Settlement stocking | All named NPCs for that settlement | B | Batch generation |
| Encounter roll | Encountered creature leaders/spokespeople | C | Quick generation |
| Henchman hiring | Interview candidates | B (on hire) | Full generation at interview |
| Dungeon faction stocking | Faction leaders | B | Full generation during dungeon stocking |
| Domain creation | Domain ruler | A or B | Full generation with ruler profile |
| Tier promotion | C → B or B → A | upgraded tier | Fill in missing fields |

### 10.2 Batch Generation Performance

Settlement stocking for a Market Class III city may generate 30-50 Tier B NPCs. The personality trait generation (steps 1-6 in §4.1) is purely deterministic table lookups — fast, under 100ms for the entire batch. The LLM personality summary generation (§9.1) is the bottleneck — 30 NPCs × ~500 tokens each = ~15,000 tokens. At typical API speeds, this takes 30-60 seconds. Show a progress bar.

**Optimization:** Generate LLM summaries in parallel (5-10 concurrent requests) and cache aggressively. A batch of 30 summaries parallelized 5-wide takes ~10 seconds instead of 60.

---

## 11. Godot Implementation Notes

### 11.1 File Organization

```
engine/subsystems/generation/npcs/
  npc_personality_generator.gd   # Main generator: trait selection, assembly
  trait_tables.gd                # Weighted random tables for each axis
  relationship_generator.gd      # Relationship network creation
  knowledge_assigner.gd          # Knowledge category assignment
  ruler_profile_generator.gd     # Domain ruler behavioral weights
  personality_templates.gd       # Template fallback for no-LLM mode

data/templates/
  personality_templates.json     # Template phrases per trait tag
  distinctive_features.json      # Feature tables (physical, behavioral, possessions)
  role_defaults.json             # Default motivation/social style per NPC role
```

### 11.2 Key Godot Classes

- `RandomNumberGenerator` — seeded RNG for reproducible trait selection
- `Resource` — NPC personality records stored as Godot Resources for serialization
- `SQLite` — personality data persisted in the campaign database for Tier A and B NPCs

---

## 12. Open Questions

*None at this time. All trait axes, generation procedures, and integration points are specified. Tuning of specific trait weights and template phrases will happen during implementation and playtesting.*

---

## 13. Revision History

- **2026-03-19:** Initial draft. Four-axis personality trait system. Three-tier generation scaling. Relationship network generation. Knowledge system. Domain ruler behavioral profiles derived from personality traits. LLM integration with template fallback. Batch generation performance considerations.
