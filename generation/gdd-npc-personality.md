# GDD: NPC Personality and Behavioral Generation

**Authority:** PROJECT-DESIGNED — NPC personality, motivation, relationship, and speech generation are not derived from any ACKS sourcebook. ACKS provides stat generation (class, level, ability scores, morale) and demographic distribution rules. This GDD covers everything that makes an NPC a *character* rather than a stat block. Where this GDD ties personality to ACKS ability scores, those ties are explicitly labeled as project engineering calls (see §2.5).
**Status:** Draft
**Depends on ACKS rules:** `acore_basics_and_characters.xml` (ability scores and their mechanical effects — CHA, WIS, INT; ability modifier table), `ax_reactions_and_influencing.xml` (five attitudes + two intimidation states, three interaction tones, 2d6 interaction roll), `acore-setting-construction-rules.xml` (NPC demographics, ability score generation, appearance tables), `ax_henchmen_recruitment_expanded.xml` and `acore_equipment.xml` (hiring procedures, loyalty, morale)
**Depends on project GDDs:** `gdd-setting-generation.md` (cultural groups, religions, political entities for context), `gdd-cultural-religious-generation.md` (twelve-axis cultural personality biases), `gdd-dungeon-factions.md` (faction-level personality biases), `gdd-settlement-layout.md` (POI placement, district assignment for NPC location)
**Consumed by (forward dependency):** `gdd-ruler-ai.md` (FUTURE, not yet authored) — consumes the `StrategicDisposition` struct and derivation formulas defined in §8. Do not author ruler AI here; this GDD's responsibility ends at producing `StrategicDisposition`.
**Modifiable by Claude Code:** Yes — axis definitions, generation algorithms, derivation formulas, and prompt designs are all engineering decisions.
**Last updated:** 2026-06-08

---

## 1. Purpose

Generate believable, mechanically functional NPC personalities for every named character in the game — from a tavern keeper the party meets once to a domain ruler who drives political events for months of campaign play. The output must serve two consumers simultaneously:

1. **The LLM narration system** — needs personality traits, speech patterns, knowledge, motivations, and relationships to produce consistent, distinctive NPC dialogue and behavior across multiple encounters.
2. **The deterministic game engine** — needs behavioral weights, loyalty modifiers, disposition scores, and reaction adjustments to make mechanical decisions without LLM calls.

Personality is modeled as **twelve continuous dispositional axes** (each scored 1–10) describing *how* an NPC is, plus an orthogonal **Motivation** system describing *what* the NPC wants. The twelve axes are a single source of truth feeding two consumers: seven are strategically active (read by reaction modifiers, loyalty calculations, the ruler AI, and dialogue), and five are expressive-only (dialogue flavor, never touching mechanical numbers). Motivation feeds quest hooks, betrayal conditions, and the ruler AI.

The generation system must work at three scales: individual NPC creation (one character at a time during encounters), batch creation (20+ NPCs when stocking a settlement), and ruler profiles (domain simulation behavioral AI).

---

## 2. ACKS Constraints

**NPC stat generation (ACore + L&E):**
- Class and level determined by demographics (market class → NPC count tables)
- Ability scores generated per L&E procedures (3d6, range 3–18; ability modifier table runs −3 to +3 per `acore_basics_and_characters.xml`)
- Equipment derived from class, level, and settlement wealth
- Morale score from ACKS loyalty tables (modified by CHA, treatment, etc.)

**Ability score mechanical effects (RAW, `acore_basics_and_characters.xml`).** These are rolled mechanical facts. Personality may *correlate* with an ability score, but personality never regenerates or overrides these numbers:
- **Charisma:** modifier applies to reaction rolls; maximum henchmen = 4 + CHA modifier (range 1–7); average henchman morale is 0, modified by CHA bonus/penalty.
- **Wisdom:** modifier applies to **all saving throws, regardless of cause**. That is its only universal mechanical effect in RAW.
- **Intelligence:** adds to starting proficiencies and to the number of languages a character may learn; prime requisite for arcane classes. No universal personality effect in RAW.

**Reaction and influencing (`ax_reactions_and_influencing.xml`):**
- An initial interaction is resolved with a **2d6 interaction roll + modifiers** establishing an attitude.
- Five attitudes: **hostile / unfriendly / neutral / indifferent / friendly**. Two intimidation-specific states: **fearful / cowed**.
- Three interaction tones: **diplomatic, intimidating, seductive**.
- Attempts to influence shift attitudes per the relevant reaction table.
- CHA modifier is added to the roll; the target's WIS modifier is subtracted.
- Personality data should INFORM situational modifiers; it does NOT replace the roll. This is the mechanical backbone of NPC first impressions.

**Henchman loyalty (`ax_henchmen_recruitment_expanded.xml`, `acore_basics_and_characters.xml`):**
- Loyalty / morale score tracked per henchman; average is 0, modified by employer CHA, pay, treatment, shared danger.
- Checked at specific trigger points (offered bribe, employer defeated, etc.).
- The In-Group Loyalty axis (§3.2) provides situational modifiers and flavor for loyalty decisions; it does NOT override the mechanical morale system, and it does NOT turn henchmen into AI-driven NPCs. **Henchmen are player-controlled** in both combat and dungeon exploration.

**Three-tier NPC persistence (design brief §12.3):**
- **Tier A (full PC):** Complete stat block, full personality (all twelve axes), persistent across sessions
- **Tier B (named NPC):** Simplified stats, personality summary (all twelve axes), persists while relevant
- **Tier C (transient):** Minimal stats, generated on encounter (three sampled axes + Motivation), not persisted unless promoted

Personality depth scales with tier. A Tier C guard gets three sampled axes and a one-line demeanor. A Tier B guild master gets all twelve axes. A Tier A henchman gets everything.

---

## 2.5 Ability Score Personality Biases (Project Engineering Call)

**This entire section is a PROJECT ENGINEERING CALL, not ACKS-derived.** ACKS assigns each ability score exactly the mechanical effects quoted in §2. ACKS does **not** state that any ability score shapes personality. The biases below are a project design decision to make ability scores feel expressed in character, applied **only at generation time** as mean-shifts on axis sampling. They never alter the rolled mechanical numbers: CHA's reaction/loyalty/henchmen-count, WIS's saving-throw modifier, and INT's language/proficiency effects remain exactly as rolled.

The shift driver is the ACKS ability **modifier** (range −3 to +3, per the ability bonus table in `acore_basics_and_characters.xml`). Shifts are applied during step 2 of the full generation procedure (§4.1) and clamped with all other shifts at the end.

| Ability | Mechanical effect (ACKS RAW — unchanged) | Personality mean-shift (PROJECT CALL) |
|---|---|---|
| CHA | Reaction mod; henchmen cap 4+mod (1–7); henchman morale mod | Light positive shift on **Civility** and **Expressiveness**: `+0.5 × CHA_mod` each. Does **not** regenerate reaction/loyalty/henchmen numbers. |
| WIS | Modifier to all saving throws | Negative shift on **Stress Reactivity** (high WIS → closer to Unflappable): `−0.7 × WIS_mod`. Slight positive shift on **Self-Interest** (toward Principled): `+0.4 × WIS_mod`. |
| INT | Languages, starting proficiencies, mage prime requisite | Positive shift on **Epistemic Curiosity**: `+0.7 × INT_mod`. |
| STR / DEX / CON | (STR: melee; DEX: missile/AC/initiative; CON: hp) | No personality bias by default. |

**Worked example.** An NPC with CHA 16 (mod +2), WIS 8 (mod −1), INT 17 (mod +2):
- Civility shift = `+0.5 × 2 = +1.0`; Expressiveness shift = `+1.0`
- Stress Reactivity shift = `−0.7 × −1 = +0.7` (low WIS nudges *toward* Volatile); Self-Interest shift = `+0.4 × −1 = −0.4` (toward Opportunistic)
- Epistemic Curiosity shift = `+0.7 × 2 = +1.4`

These ability shifts are applied **before** cultural, faction, and alignment biases (see §4.1 ordering). An "average NPC" with every ability at 9–12 (modifier 0) receives zero ability shift and therefore samples near the 5-baseline on every axis.

---

## 3. Personality Trait System

### 3.1 Trait Architecture

Each NPC personality is built from **twelve independent dispositional axes**, each a **1–10 integer**, plus an orthogonal **Motivation** system (§3.3). The twelve axes describe *how* the NPC is; Motivation describes *what they want*. Both feed the LLM and the ruler AI; both are retained for every Tier A/B NPC.

**The neutral baseline is 5.** An axis at 4–7 is unremarkable and is **never injected into LLM dialogue prompts** — only axes scoring **1–3 (strong low)** or **8–10 (strong high)** become hard behavioral directives (the "deviation from the mean" prompt strategy, §9). This keeps prompts token-efficient and prevents the LLM from being confused by a wash of mid-range traits.

The twelve axes split into two consumer groups served from one source of truth:

- **Strategically active (7 axes)** — read by reaction modifiers, loyalty calculations, the ruler AI (§8), **and** dialogue: Epistemic Curiosity, Societal Orthodoxy, Affective Compassion, Stress Reactivity, Self-Interest, In-Group Loyalty, Mysticism.
- **Expressive-only (5 axes)** — dialogue flavor exclusively; these **never** modify a mechanical number: Expressiveness, Civility, Jocularity, Amorousness, Epicureanism.

The axes are intentionally orthogonal. Civility and Affective Compassion are different traits (a courtly executioner is high-Civility, low-Compassion). Expressiveness and Civility are different (a theatrical brute is high-Expressiveness, low-Civility). The generator does not couple them.

### 3.2 The Twelve Dispositional Axes

Each axis below gives its 1↔10 spectrum, its consumer group, what it drives mechanically (for strategically-active axes), and prose anchors for the low (1), mid (5), and high (10) ends. Scores are integers 1–10; the anchors describe the endpoints and center, and intermediate values interpolate.

> **Source note (PROJECT CALL on wording):** the low/mid/high anchor prose below was authored for this GDD from the axis spectrum descriptors. If a canonical upstream wording exists in the original design document, substitute it verbatim; the mechanical scoring (1–10, baseline 5, deviation filter) is unaffected by the exact prose.

#### Strategically Active Axes

**Axis 1 — Epistemic Curiosity** *(Dogmatic 1 ↔ 10 Inquisitive)* — strategically active.
*Drives:* research weight, openness to foreign diplomacy, exploration.
- **Low (1):** Dogmatic. Holds received truths as settled; treats new ideas, foreigners, and unfamiliar practices as threats to be resisted. Closes inquiry rather than opening it.
- **Mid (5):** Accepts established knowledge but will entertain a genuinely useful new idea when pressed; neither seeks novelty nor flees it.
- **High (10):** Inquisitive. Hungers to learn, questions assumptions, welcomes the foreign and the strange, and pursues mysteries even at personal cost.

**Axis 2 — Societal Orthodoxy** *(Iconoclast 1 ↔ 10 Traditionalist)* — strategically active.
*Drives:* treaty-honoring, governance style, hierarchy enforcement.
- **Low (1):** Iconoclast. Distrusts inherited hierarchy and custom; bends or breaks rules and treaties when they obstruct; reforms or overturns institutions.
- **Mid (5):** Respects useful institutions and keeps ordinary agreements, but is not reverent toward tradition for its own sake.
- **High (10):** Traditionalist. Venerates hierarchy, precedent, and protocol; honors treaties and oaths as binding; enforces custom rigidly.

**Axis 3 — Affective Compassion** *(Callous 1 ↔ 10 Self-Sacrificing)* — strategically active.
*Drives:* oppression weight, treatment of subjects/prisoners, war-atrocity propensity.
- **Low (1):** Callous. Indifferent to others' suffering; treats subjects, prisoners, and rivals as instruments; readily resorts to cruelty when it is expedient.
- **Mid (5):** Ordinary human sympathy — moved by suffering nearby, but capable of hard decisions.
- **High (10):** Self-sacrificing. Feels others' pain acutely; protects the weak; will accept personal loss to spare suffering.

**Axis 4 — Stress Reactivity** *(Unflappable 1 ↔ 10 Volatile)* — strategically active.
*Drives:* crisis response category (see §8 `crisis_response`).
- **Low (1):** Unflappable. Calm under pressure; reacts to crisis deliberately and steadily; hard to rattle or provoke.
- **Mid (5):** Composed in normal stress, can be shaken by genuine emergencies.
- **High (10):** Volatile. Reacts sharply and quickly to threat or insult; emotions spike; decisions under pressure are impulsive.

**Axis 5 — Self-Interest** *(Opportunistic 1 ↔ 10 Principled)* — strategically active.
*Drives:* treachery probability, bribability, alliance reliability.
- **Low (1):** Opportunistic. Pursues personal advantage above commitments; easily bribed; abandons allies and bargains when a better deal appears.
- **Mid (5):** Generally keeps bargains but weighs serious cost against principle.
- **High (10):** Principled. Honors commitments even at personal cost; cannot be bought; a reliable ally and a predictable adversary.

**Axis 6 — In-Group Loyalty** *(Mercenary 1 ↔ 10 Zealot)* — strategically active.
*Drives:* henchman loyalty (bridges into the ACKS morale mechanic as a situational modifier, never a replacement), faction cohesion, vassal stability.
- **Low (1):** Mercenary. Bonds are transactional; serves whoever pays; feels no special duty to kin, crew, or cause.
- **Mid (5):** Loyal to those who have earned it, within reason.
- **High (10):** Zealot. Devoted to the in-group — clan, faction, faith, or lord — to the point of self-sacrifice; will not betray their own.

**Axis 7 — Mysticism** *(Materialist 1 ↔ 10 Fanatical)* — strategically active.
*Drives:* religious weight, reaction to clerics/undead, holy-war propensity.
- **Low (1):** Materialist. Sees the world in concrete, worldly terms; skeptical of the divine; unmoved by omens, relics, or clergy.
- **Mid (5):** Conventionally observant — respects the gods without zeal.
- **High (10):** Fanatical. Reads divine meaning into events; reveres (or dreads) the sacred and the undead intensely; drawn to holy causes and crusades.

#### Expressive-Only Axes

These shape dialogue voice **only**. They never modify reaction rolls, loyalty, ruler weights, or any other mechanical number.

**Axis 8 — Expressiveness** *(Laconic 1 ↔ 10 Theatrical)* — expressive only.
- **Low (1):** Laconic. Few words; long pauses; lets silence carry meaning. The LLM should keep replies to 1–2 short sentences.
- **Mid (5):** Speaks a normal amount for the situation.
- **High (10):** Theatrical. Expansive, performative, fond of flourish, gesture, and the grand statement.

**Axis 9 — Civility** *(Vulgar 1 ↔ 10 Exquisitely Courteous)* — expressive only.
- **Low (1):** Vulgar. Coarse, crude, blunt; ignores etiquette; may curse or insult casually.
- **Mid (5):** Ordinarily polite.
- **High (10):** Exquisitely courteous. Formal address, honorifics, elaborate manners; never coarse even when delivering bad news (or a death sentence).

**Axis 10 — Jocularity** *(Grim 1 ↔ 10 Frivolous)* — expressive only.
- **Low (1):** Grim. Humorless, severe, serious; finds little to laugh about.
- **Mid (5):** Normal sense of humor.
- **High (10):** Frivolous. Quick to joke, tease, and deflect with levity; rarely fully serious.

**Axis 11 — Amorousness** *(Prudish 1 ↔ 10 Shameless)* — expressive only.
- **Low (1):** Prudish. Reserved and modest about romance and the body; uncomfortable with flirtation or innuendo.
- **Mid (5):** Conventional about such matters.
- **High (10):** Shameless. Forward, flirtatious, uninhibited; comfortable with innuendo and open desire.

**Axis 12 — Epicureanism** *(Ascetic 1 ↔ 10 Decadent)* — expressive only.
- **Low (1):** Ascetic. Spurns luxury and indulgence; plain in food, dress, and habit; suspicious of excess.
- **Mid (5):** Enjoys comfort in moderation.
- **High (10):** Decadent. Devoted to pleasure, luxury, fine food and drink; surrounds themselves with indulgence.

### 3.3 Motivation Axis

What the NPC wants. This is the most gameplay-relevant trait because it drives quest hooks, betrayal conditions, and NPC decision-making. **Motivation is orthogonal to the twelve dispositional axes and is retained unchanged from prior versions of this GDD.**

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

### 3.4 Alignment Reconciliation

ACKS alignment (Lawful / Neutral / Chaotic) is a **cosmic axis** about one's relationship to civilization and the forces of order versus the forces that would destroy it (per the alignment definitions in `acore_basics_and_characters.xml`). It is **not the same as Societal Orthodoxy**, which is about reverence for hierarchy and tradition. State this distinction explicitly in implementation and content:

- A **Chaotic** NPC can be **high Societal Orthodoxy** — e.g., a tyrant-god priest who demands rigid protocol while serving cosmic evil.
- A **Lawful** NPC can be **low Societal Orthodoxy** — e.g., a reformer challenging corrupt institutions in the name of true law.
- A **Lawful** NPC can be **low Affective Compassion** — e.g., a stern executioner who believes the law's harshness is mercy.
- A **Chaotic** NPC can be **high Affective Compassion** — e.g., a clan-loyal raider who would die for kin while preying on outsiders.

Alignment continues to bias **Motivation** distributions exactly as in §3.3. Alignment does **not** directly constrain the twelve dispositional axes; it provides only weak **soft biases** on a few axes, applied at generation time. These alignment shifts are intentionally weaker than cultural biases (each shift ≤ ±0.5, versus ±2.0 for culture). They are applied after cultural and faction biases in the generation order (§4.1).

**Alignment → axis mean-shift table (each shift ≤ ±0.5):**

| Axis | Lawful | Neutral | Chaotic |
|---|---|---|---|
| Societal Orthodoxy | +0.5 | 0.0 | −0.3 |
| Self-Interest (→ Principled at high) | +0.3 | 0.0 | −0.4 |
| In-Group Loyalty | +0.2 | 0.0 | −0.2 |
| Affective Compassion | +0.2 | 0.0 | −0.2 |

All other axes receive a 0.0 alignment shift. (Rationale, project call: Lawful supports civilization and order, gently nudging toward tradition, principle, loyalty, and compassion; Chaotic seeks to tear down civil society, gently nudging the other way. These are *soft* — a Lawful iconoclast or a compassionate Chaotic raider remains entirely possible because cultural biases and the random draw dominate.)

---

## 4. Trait Generation Procedure

### 4.1 Full Generation (Tier A and B NPCs)

All twelve axes are generated. Each axis starts as a sample from a Gaussian centered on the neutral baseline, then receives a deterministic stack of mean-shifts, then is rounded and clamped to the 1–10 integer range.

```
1. DETERMINE CONTEXT:
   - NPC's class, level, alignment, ability scores (from ACKS stat generation)
   - NPC's role (ruler, merchant, guard, priest, thief, henchman, etc.)
   - Settlement culture and religion (from setting generation)
   - Faction membership, if any (from gdd-dungeon-factions.md or settlement factions)
   - District where the NPC is located (from settlement layout)

2. SAMPLE THE TWELVE AXES:
   For each of the twelve axes:
   a. Draw a base value from a Gaussian: base = Normal(mean = 5.0, sigma = 1.8)
      (sigma ≈ 1.8 keeps most draws within 1-3 of the mean; ~95% land in [1.5, 8.5]
       before shifts, so extremes are uncommon but reachable after biases)
   b. Apply ABILITY-SCORE mean-shifts (§2.5), using ACKS ability modifiers:
        Civility            += 0.5 × CHA_mod
        Expressiveness      += 0.5 × CHA_mod
        Stress Reactivity   += -0.7 × WIS_mod
        Self-Interest       += 0.4 × WIS_mod
        Epistemic Curiosity += 0.7 × INT_mod
   c. Apply CULTURAL mean-shifts (twelve-axis personality_weight_biases from
        gdd-cultural-religious-generation.md §2; range -2.0 to +2.0 per axis)
   d. Apply FACTION mean-shifts (twelve-axis biases from gdd-dungeon-factions.md;
        a SECOND mean-shift on top of cultural, same schema and range)
   e. Apply ALIGNMENT soft mean-shifts (§3.4 table; each ≤ ±0.5)
   f. Round to nearest integer and CLAMP to [1, 10]

   (Ordering is fixed: sample → ability → culture → faction → alignment → clamp.
    Clamping happens once, at the end, after all shifts accumulate.)

3. ROLL MOTIVATION (primary and secondary) — UNCHANGED from §3.3:
   - Build weighted table from alignment influence + role influence
   - Select primary motivation
   - Select secondary motivation (reroll if same as primary)
   - Role overrides: a merchant always has wealth as primary or secondary;
     a priest always has faith; a soldier always has duty
     (these are baseline, not absolute — the LLM can justify exceptions)

4. GENERATE DISTINCTIVE FEATURE:
   - One memorable physical or behavioral quirk (see §4.3)
   - This is the "you'd recognize them in a crowd" detail

5. ASSEMBLE PERSONALITY RECORD (see §7)
```

**Sanity property:** an NPC whose every ability score is 9–12 (modifier 0), with no cultural, faction, or alignment bias, samples near 5 on every axis — i.e., an unremarkable, mid-range personality.

### 4.2 Quick Generation (Tier C NPCs)

Tier C NPCs get a stripped-down personality — enough for a single interaction. Per the three-tier persistence model, Tier C stores **three sampled axes plus Motivation**, with all other axes defaulted to the neutral 5.

```
1. SELECT THREE AXES AT RANDOM from the twelve (without replacement).
   Sample each of the three per step 2 of §4.1 (Gaussian + applicable biases + clamp).
   Bias context is applied if cheaply available (culture/faction/alignment of the
   encounter); ability-score shifts apply only if the Tier C NPC has rolled abilities.
2. DEFAULT ALL OTHER NINE AXES TO 5 (neutral; they will not enter dialogue prompts).
3. Assign a default motivation from their role:
   - Guard → duty, Merchant → wealth, Priest → faith,
     Beggar → survival, Noble → power
   (Optionally roll a secondary motivation; primary is sufficient for Tier C.)
4. Generate one distinctive feature.
5. Store as a compact record (see §7.2) — only the three sampled axes are persisted.
```

If a Tier C NPC becomes important (the party keeps interacting with them), they're promoted to Tier B and the full generation procedure (§4.1) fills in the nine defaulted axes by sampling them (the three already-sampled axes are retained).

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
| `debtor` | Owes money, a favor, or a life debt | Obligated; resentful or grateful depending on Self-Interest |
| `mentor` | Taught or trained the other | Respect-based; the student may outgrow the teacher |
| `co-conspirator` | Shares a secret or illegal enterprise | Bound by mutual risk; betrayal is catastrophic for both |
| `unrequited` | One-sided attraction or admiration | Source of drama; the admirer is manipulable |

### 5.3 Relationship Generation Procedure (Settlement Batch)

```
1. For each Tier B+ NPC in the settlement:
   a. Generate 2-5 relationships with other NPCs in the settlement
   b. Relationship count scales with the NPC's SOCIABILITY, derived from the
      twelve axes (this replaces the old social-style tag rule). Evaluate these
      bands in order and use the first that matches:
      - "gregarious-equivalent": Expressiveness >= 7 AND Civility >= 7
        → 4-5 relationships
      - "withdrawn-equivalent": Expressiveness <= 3 OR Stress Reactivity >= 8
        (laconic, or guarded/volatile) → 1-2 relationships
      - otherwise ("reserved/formal-equivalent", the mid range)
        → 2-3 relationships

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
     historical (religious history), personal (confessions — if willing to share)

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

  # Personality — twelve dispositional axes (each 1-10 integer), from §3.2
  # Strategically active (7):
  epistemic_curiosity: int         # 1 Dogmatic .. 10 Inquisitive
  societal_orthodoxy: int          # 1 Iconoclast .. 10 Traditionalist
  affective_compassion: int        # 1 Callous .. 10 Self-Sacrificing
  stress_reactivity: int           # 1 Unflappable .. 10 Volatile
  self_interest: int               # 1 Opportunistic .. 10 Principled
  in_group_loyalty: int            # 1 Mercenary .. 10 Zealot
  mysticism: int                   # 1 Materialist .. 10 Fanatical
  # Expressive only (5):
  expressiveness: int              # 1 Laconic .. 10 Theatrical
  civility: int                    # 1 Vulgar .. 10 Exquisitely Courteous
  jocularity: int                  # 1 Grim .. 10 Frivolous
  amorousness: int                 # 1 Prudish .. 10 Shameless
  epicureanism: int                # 1 Ascetic .. 10 Decadent

  # Motivation (orthogonal, from §3.3) — retained unchanged
  motivation_primary: string       # Tag from §3.3
  motivation_secondary: string     # Tag from §3.3

  distinctive_feature: string      # From §4.3

  # LLM Context (assembled for narration)
  personality_summary: string      # 2-3 sentence human-readable summary for LLM prompts
  speech_notes: string             # Specific LLM instructions for dialogue voice

  # Relationships
  relationships: Array[Relationship]  # From §5.4

  # Knowledge
  knowledge: Array[KnowledgeEntry]    # From §6.4

  # Disposition toward party (runtime, updated during play)
  disposition: int                 # -5 to +5, starts at 0, modified by interactions
  disposition_history: Array       # Log of what changed disposition and why

  # Domain ruler fields (only for NPCs who rule domains, see §8)
  strategic_disposition: StrategicDisposition or null   # The ruler-AI handoff struct (§8)
  ruler_profile: RulerProfile or null                   # Derived weight-vector view (§8)
```

### 7.2 Compact NPC Personality (Tier C)

```
NPCPersonalityCompact:
  npc_id: string
  tier: "C"
  name: string
  role: string
  sampled_axes: Dictionary         # { axis_name: int } for exactly the 3 sampled axes (§4.2)
                                   # all other axes are implicitly 5 (neutral) and not stored
  motivation_primary: string       # Default from role
  distinctive_feature: string
  disposition: int                 # Default 0
  knowledge: Array[string]         # 3-5 plain-text facts (not full KnowledgeEntry objects)
```

---

## 8. Domain Ruler Behavioral Profiles

### 8.1 Purpose

NPCs who rule domains (barons, counts, kings, guild masters, high priests) need behavioral profiles that drive the domain simulation (design brief §13.5). These profiles determine what the ruler does during monthly domain turns — expand territory? raise taxes? build fortifications? wage war? — without requiring an LLM call for every ruler every month.

This section defines the **`StrategicDisposition`** struct: the clean, stable handoff that the future `gdd-ruler-ai.md` HTN-lite planner consults. `StrategicDisposition` is derived from the NPC's Motivation, the seven strategically-active axes, ability scores, and culture. The legacy **`RulerProfile`** weight vector is **one view computed from `StrategicDisposition`**; the HTN planner may additionally read the raw axis values inside `StrategicDisposition` for utility scoring on specific actions. **This GDD does not author the planner — only the struct and the derivation formulas.**

### 8.2 The StrategicDisposition Struct

```
StrategicDisposition:
  # From Motivation (primary and secondary, weighted 0.7 / 0.3)
  motivation_primary: string
  motivation_secondary: string

  # From the seven strategically-active axes (1-10, retained continuous/integer)
  epistemic_curiosity: int
  societal_orthodoxy: int
  affective_compassion: int
  stress_reactivity: int
  self_interest: int
  in_group_loyalty: int
  mysticism: int

  # Derived ruler-action weights (computed from the above, each clamped to 0.0-1.0)
  expansion_weight: float
  fortification_weight: float
  economic_weight: float
  military_weight: float
  diplomatic_weight: float
  religious_weight: float
  research_weight: float
  oppression_weight: float

  # Derived crisis response (categorical; computed from Stress Reactivity + Self-Interest)
  crisis_response: string   # "aggressive" | "defensive" | "diplomatic" | "cautious"

  # Relational (unchanged from prior §8)
  aggression_toward: Dictionary    # {realm_id: float}
  alliance_preference: Dictionary  # {realm_id: float}
```

The five expressive-only axes are deliberately **absent** from `StrategicDisposition`: they never inform strategic behavior.

`RulerProfile` is the legacy view — exactly the eight derived weights plus `crisis_response`, `aggression_toward`, and `alliance_preference`. It is computed from `StrategicDisposition` and stored alongside it for systems that only want the weight vector.

### 8.3 Derivation Formulas

The formulas are specified tightly so that two engineers compute identical numbers. Define two helpers over an axis value `a` (an integer 1–10):

```
u(a) = (a - 1) / 9          # normalize to 0.0 (at a=1) .. 1.0 (at a=10)
inv(a) = 1 - u(a)           # inverted normalization (1.0 at a=1 .. 0.0 at a=10)
```

Define a motivation helper. For a target motivation tag `t`:

```
mot(t) = 0.7 if motivation_primary == t
       + 0.3 if motivation_secondary == t
       (so mot(t) is 0.7, 0.3, or 0.0; primary and secondary are always distinct)
```

Each weight is computed, then **clamped to [0.0, 1.0]** (clamp01). All coefficients below are project-design constants (PROJECT CALL) and may be tuned in playtesting without changing the structure.

```
research_weight = clamp01(
    0.10
  + 0.45 * u(epistemic_curiosity)
  + 0.35 * mot("knowledge")
)

religious_weight = clamp01(
    0.08
  + 0.50 * u(mysticism)
  + 0.35 * mot("faith")
)

economic_weight = clamp01(
    0.12
  + 0.40 * mot("wealth")
  + 0.20 * mot("legacy")
  + 0.15 * mot("pleasure")
  + 0.10 * u(epistemic_curiosity)
)

military_weight = clamp01(
    0.10
  + 0.30 * inv(affective_compassion)        # callous -> more militarism
  + 0.25 * u(in_group_loyalty)              # zealous in-group cohesion -> standing forces
  + 0.30 * mot("power")
  + 0.30 * mot("revenge")
  + 0.25 * mot("security")
)

expansion_weight = clamp01(
    0.08
  + 0.40 * mot("power")
  + 0.20 * inv(affective_compassion)
  + 0.15 * inv(self_interest)               # opportunistic -> land-grabbing
)

fortification_weight = clamp01(
    0.12
  + 0.40 * mot("security")
  + 0.20 * mot("survival")
  + 0.20 * mot("legacy")
)

diplomatic_weight = clamp01(
    0.10
  + 0.30 * u(self_interest)                 # principled -> reliable alliances
  + 0.25 * u(epistemic_curiosity)           # open to foreigners
  + 0.30 * mot("knowledge")
  + 0.25 * mot("legacy")
  - 0.20 * inv(affective_compassion)        # callous rulers parley less
)

# Oppression: low Affective Compassion, plus an alignment-conditional orthodoxy term,
# plus power motivation; restrained by principled Self-Interest and by freedom motivation.
orthodoxy_term =
    u(societal_orthodoxy)            if alignment == "Lawful"     # "lawful oppression" via rigid enforcement
    inv(societal_orthodoxy)          if alignment == "Chaotic"    # chaotic oppression via lawless predation
    abs((societal_orthodoxy - 5.5) / 4.5)   if alignment == "Neutral"  # either extreme is oppressive

oppression_weight = clamp01(
    0.08
  + 0.40 * inv(affective_compassion)
  + 0.25 * orthodoxy_term
  + 0.30 * mot("power")
  - 0.20 * u(self_interest)
  - 0.25 * mot("freedom")
)
```

**Worked example.** Lawful baron, motivation_primary `power`, secondary `security`; affective_compassion 2, in_group_loyalty 8, societal_orthodoxy 9, self_interest 4, epistemic_curiosity 3, mysticism 3.
- `inv(2)=0.889`, `u(8)=0.778`, `u(9)=0.889`, `u(4)=0.333`, `u(3)=0.222`.
- military_weight = 0.10 + 0.30·0.889 + 0.25·0.778 + 0.30·0.7(power) + 0.30·0 + 0.25·0.3(security) = 0.10 + 0.267 + 0.194 + 0.210 + 0.075 = **0.846**
- oppression_weight (Lawful, orthodoxy_term = u(9)=0.889) = 0.08 + 0.40·0.889 + 0.25·0.889 + 0.30·0.7 − 0.20·0.333 − 0 = 0.08 + 0.356 + 0.222 + 0.210 − 0.067 = **0.801** ("lawful oppression" via rigid enforcement)
- diplomatic_weight = 0.10 + 0.30·0.333 + 0.25·0.222 + 0 + 0 − 0.20·0.889 = 0.10 + 0.100 + 0.056 − 0.178 = **0.078** (low — a callous, power-seeking enforcer rarely parleys)

**Relational dictionaries (unchanged from prior §8):**
```
aggression_toward[realm_id]   — base from inter-realm relationship state;
                                + 0.5 if motivation == "revenge" and target == revenge subject
alliance_preference[realm_id] — base from inter-realm relationship state;
                                scaled up by diplomatic_weight and u(self_interest)
```

### 8.4 Crisis Response Derivation (PROJECT CALL)

`crisis_response` is categorical, computed from **Stress Reactivity** and **Self-Interest**. The split point is the 5.5 midpoint of the 1–10 scale (axis ≥ 6 is "high", ≤ 5 is "low"). The mapping is a project engineering call:

```
if stress_reactivity >= 6:        # Volatile-leaning: reacts sharply to crisis
    crisis_response = "aggressive" if self_interest <= 5   # opportunistic + volatile -> lashes out
                    = "cautious"   if self_interest >= 6   # principled + volatile -> over-prepares, hedges
else:                             # Unflappable-leaning: reacts calmly to crisis
    crisis_response = "diplomatic" if self_interest <= 5   # opportunistic + calm -> negotiates self-interest
                    = "defensive"  if self_interest >= 6   # principled + calm -> holds the line steadily
```

(Rationale, project call: high Stress Reactivity yields the two "active" responses — aggressive or cautious — split by whether the ruler chases advantage or honors principle; low Stress Reactivity yields the two "measured" responses — diplomatic or defensive — on the same split.)

### 8.5 Monthly Domain AI

During the campaign monthly turn, the domain simulation evaluates each NPC ruler's available actions and scores them against the ruler's weights:

```
1. List available domain actions for this ruler (from XML rules reference)
2. Score each action: base_value × relevant_weight (from RulerProfile / StrategicDisposition)
   - The HTN-lite planner (gdd-ruler-ai.md, future) may instead read raw axis values
     from StrategicDisposition for finer per-action utility scoring
3. Apply situational modifiers (at war → military actions score higher;
   crisis_response biases the response to unexpected threats)
4. Select the highest-scoring action (or top 2-3 for large domains)
5. Execute deterministically — no LLM call needed
6. LLM narrates the outcome retroactively if the player interacts with it
```

---

## 9. LLM Integration

### 9.1 Personality Summary Generation — Deviation-From-the-Mean Prompt Strategy

The dialogue prompt is built on a **deviation filter**: only axes at the extremes drive dialogue, so prompts stay tight and the LLM is not buried in mid-range traits. The procedure has four steps.

**1. Filter.** Discard any axis scoring **4, 5, 6, or 7.** (PROJECT CALL: the prior design used a 4–6 filter; this GDD widens it to 4–7 so that only the strong extremes — scores of 1–3 or 8–10 — drive dialogue. This is a deliberate token-tightening decision.)

**2. Translate.** For each retained axis (scoring 1–3 or 8–10), emit a hard markdown directive describing the behavioral consequence at that end. Use this directive table:

| Axis | Directive at LOW (1–3) | Directive at HIGH (8–10) |
|---|---|---|
| Epistemic Curiosity | "Dogmatic: dismiss new ideas and foreign ways; defend received wisdom." | "Inquisitive: ask questions, probe, show open interest in the unfamiliar." |
| Societal Orthodoxy | "Iconoclast: disrespect hierarchy and custom; flout protocol." | "Traditionalist: invoke precedent, rank, and proper form; treat oaths as binding." |
| Affective Compassion | "Callous: show no sympathy for suffering; treat others as means." | "Compassionate: visibly moved by others' pain; protective of the weak." |
| Stress Reactivity | "Unflappable: stay calm and measured even under direct threat." | "Volatile: react sharply, emotionally, and impulsively to pressure or insult." |
| Self-Interest | "Opportunistic: hint at being for sale; weigh every exchange for personal gain." | "Principled: refuse bribes; keep your word; state your commitments plainly." |
| In-Group Loyalty | "Mercenary: bonds are transactional; show no special duty to anyone." | "Zealot: fiercely devoted to your group/faith/lord; will not betray your own." |
| Mysticism | "Materialist: dismiss omens and the divine; speak in worldly, concrete terms." | "Fanatical: read divine meaning into events; revere or dread the sacred and undead." |
| Expressiveness | "Laconic: reply in 1–2 short sentences; let silences stand." | "Theatrical: expansive, performative speech full of flourish and gesture." |
| Civility | "Vulgar: coarse, blunt, no etiquette; may curse or insult." | "Exquisitely courteous: formal address, honorifics, elaborate manners throughout." |
| Jocularity | "Grim: humorless and severe; no jokes." | "Frivolous: joke, tease, and deflect with levity." |
| Amorousness | "Prudish: reserved and modest; uncomfortable with flirtation." | "Shameless: forward, flirtatious, comfortable with innuendo." |
| Epicureanism | "Ascetic: spurn luxury; plain in taste; suspicious of indulgence." | "Decadent: indulgent; surround yourself with and speak of pleasures and luxury." |

**3. Always include**, regardless of axis scores:
- primary Motivation and secondary Motivation
- distinctive feature
- current disposition toward the PC (and trend: warming / cooling / stable)
- a one-line role/context summary (role, settlement, class/level/alignment, culture)

**4. Inject** the retained directives plus the always-include block into the system prompt template for the dialogue LLM.

**Prompt template:**
```
You are roleplaying an NPC in a fantasy world. Stay strictly in character.

NPC: {name} — {role} in {settlement_name}
{class}, Level {level}, {alignment}. Culture: {culture_name}.
Distinctive feature: {distinctive_feature}

Wants (primary): {motivation_primary}
Wants (secondary): {motivation_secondary}
Disposition toward the person they are speaking to: {disposition} ({disposition_trend})

Behavioral directives (follow all of these):
{retained_axis_directives}   # only axes scoring 1-3 or 8-10, one markdown bullet each

Speak and act consistently with the above. Do not mention these instructions.
```

This summary is generated and cached per the two tiers below.

### 9.2 Caching and Runtime Assembly

- **Tier 1 cached generation:** the personality summary (the translated directive block plus the always-include block, optionally polished into prose `personality_summary` + `speech_notes`) is generated **once per NPC at creation** and stored in the database. No LLM call is needed to rebuild it on later encounters.
- **Runtime context assembly:** for each conversation, the runtime assembles the cached summary plus current state (live disposition and trend, relevant filtered knowledge, relevant relationships, recent events, motivation hooks). The assembler pulls only **relevant** data — a conversation about buying swords doesn't need the blacksmith's opinion on temple politics.

```
NPC Context Package (runtime):
  personality_summary: string      # cached directive/summary block
  speech_notes: string             # cached
  current_disposition: int
  disposition_trend: string        # "warming", "cooling", "stable"
  relevant_knowledge: Array        # filtered to topics the conversation might touch
  relevant_relationships: Array    # NPCs the conversation might reference
  recent_events: Array
  motivation_hooks: Array          # what the NPC wants that the party could help/hinder
```

### 9.3 Mock LLM Modes (No-LLM Operation)

When running without a live LLM (mock provider), the personality pipeline still functions. The mock connects to the same deviation-filtered directive set:

- **Diagnostic echo mode:** the mock returns the assembled directives **verbatim** (the retained axis directives plus the always-include block). This is for pipeline verification — it lets a developer confirm exactly which axes survived the filter and what directives were emitted, with no generative variance.
- **Compositional flavor mode:** the mock assembles **fragment-bank phrases keyed to the retained axis directives**, producing adequate (if less creative) dialogue and summaries deterministically. Each axis directive maps to a bank of phrasing fragments; the mock selects and concatenates fragments for the retained directives plus the motivation/feature data.

Fragment banks are stored in `data/templates/personality_templates.json`, keyed by axis name and end (low/high), plus motivation phrases. These produce adequate but less creative results than live LLM generation.

---

## 10. Generation Timing and Performance

### 10.1 When NPCs Are Generated

| Trigger | NPCs Generated | Tier | Method |
|---|---|---|---|
| Settlement stocking | All named NPCs for that settlement | B | Batch generation |
| Encounter roll | Encountered creature leaders/spokespeople | C | Quick generation |
| Henchman hiring | Interview candidates | B (on hire) | Full generation at interview |
| Dungeon faction stocking | Faction leaders | B | Full generation during dungeon stocking |
| Domain creation | Domain ruler | A or B | Full generation with StrategicDisposition + RulerProfile |
| Tier promotion | C → B or B → A | upgraded tier | Sample the defaulted axes; fill in missing fields |

### 10.2 Batch Generation Performance

Settlement stocking for a Market Class III city may generate 30-50 Tier B NPCs. The axis sampling and bias-stacking (steps 1-2 in §4.1) are purely deterministic numeric operations — fast, under 100ms for the entire batch. The LLM personality summary generation (§9.1) is the bottleneck — 30 NPCs × ~400-500 tokens each. At typical API speeds, this takes 30-60 seconds. Show a progress bar.

**Optimization:** Generate LLM summaries in parallel (5-10 concurrent requests) and cache aggressively. A batch of 30 summaries parallelized 5-wide takes ~10 seconds instead of 60. In mock compositional-flavor mode (§9.3), generation is effectively instant.

---

## 11. Godot Implementation Notes

### 11.1 File Organization

```
engine/subsystems/generation/npcs/
  npc_personality_generator.gd   # Main generator: axis sampling, bias stacking, assembly
  axis_sampler.gd                # Gaussian draw + ability/culture/faction/alignment shifts + clamp
  relationship_generator.gd      # Relationship network creation (sociability from axes, §5.3)
  knowledge_assigner.gd          # Knowledge category assignment
  strategic_disposition.gd       # Domain ruler StrategicDisposition + RulerProfile derivation (§8)
  personality_mock.gd            # Mock-LLM diagnostic-echo and compositional-flavor modes (§9.3)

data/templates/
  personality_templates.json     # Fragment banks per axis end (low/high) + motivation phrases
  distinctive_features.json      # Feature tables (physical, behavioral, possessions)
  role_defaults.json             # Default motivation per NPC role
```

### 11.2 Key Godot Classes

- `RandomNumberGenerator` — seeded RNG for reproducible axis sampling (Gaussian via `randfn(5.0, 1.8)`)
- `Resource` — NPC personality records stored as Godot Resources for serialization
- `SQLite` — personality data persisted in the campaign database for Tier A and B NPCs

### 11.3 Numeric Conventions

- Axis values are stored as integers 1–10. All intermediate shift math is float; rounding to int and clamping to [1,10] happens once, at the end of sampling (§4.1 step 2f).
- Ruler weights are floats clamped to [0.0, 1.0] (§8.3). `u()`, `inv()`, `mot()`, `clamp01()`, and `orthodoxy_term` are implemented exactly as written in §8.3 so results are reproducible across engineers.

---

## 12. Open Questions / Flags

- **Axis anchor wording (FLAG):** the low/mid/high anchor prose in §3.2 was authored for this GDD from the axis spectrum descriptors, because the referenced upstream design document was not available in the project at rewrite time. If a canonical verbatim wording exists, substitute it into §3.2. The mechanical model (1–10 scoring, baseline 5, 4–7 deviation filter) does not depend on the exact prose.
- **Coefficient tuning:** all numeric coefficients in §2.5 (ability shifts), §3.4 (alignment shifts), §4.1 (Gaussian sigma), and §8.3 (ruler-weight coefficients) are project-design constants subject to playtest tuning. Their *structure* is fixed; their *values* are tunable.
- The `strategic_disposition` / `ruler_profile` consumer (`gdd-ruler-ai.md`) is not yet authored. This GDD's responsibility ends at producing the struct and formulas; the HTN-lite planner is a future session.

---

## 13. Revision History

- **2026-06-14:** Core layer IMPLEMENTED. The twelve-axis sampler (§4.1 bias stack: ability → culture → faction[reserved] → alignment → Banker's-round → clamp), Motivation roll (§3.3 with role guarantee), distinctive feature (§4.3), Tier C quick gen (§4.2), the deviation filter + mock-LLM diagnostic-echo / compositional-flavor modes (§9), and the §9.1 dialogue-prompt assembler are live in `engine/subsystems/generation/npcs/` (`personality_axes.gd`, `axis_sampler.gd`, `npc_personality_generator.gd`, `personality_mock.gd`) + `engine/shared_types/npc_personality.gd`, with data banks in `data/templates/{personality_templates,distinctive_features,role_defaults}.json`. Persisted as JSON in `characters.personality`. Wired into `ClassedNpcBuilder` (opts `generate_personality`/`culture_id`/`role`), `NpcRulerGenerator` (role "ruler"), and `BaselineNpcStocker` (+ `CampaignRepository.insert_baseline_npc_character` personality column). Cultural biases consumed via new `CultureCatalogLoader.biases_for_culture()`; faction + religion biases degrade to zero-shift (data absent). **NOT YET BUILT (deferred):** relationships (§5), knowledge (§6), `StrategicDisposition`/`RulerProfile` (§8), and the live-LLM summary (mock-only for now). Tests: `tests/test_npc_personality.gd` (17 tests; net-zero new suite failures).
- **2026-03-19:** Initial draft. Four-axis personality trait system (Temperament, Motivation, Social Style, Moral Compass). Three-tier generation scaling. Relationship network generation. Knowledge system. Domain ruler behavioral profiles derived from personality traits. LLM integration with template fallback. Batch generation performance considerations.
- **2026-06-08:** Major rework. Replaced the three dispositional tag-axes (Temperament, Social Style, Moral Compass) with a unified **twelve-axis continuous model** (1–10 per axis, baseline 5), split into seven strategically-active axes and five expressive-only axes; **Motivation retained unchanged** as the orthogonal "what they want" axis (§3.3). Added §2.5 Ability Score Personality Biases (explicitly labeled PROJECT CALL: CHA→Civility/Expressiveness, WIS→Stress Reactivity/Self-Interest, INT→Epistemic Curiosity). Added §3.4 Alignment Reconciliation (alignment ≠ Societal Orthodoxy; soft alignment→axis shifts ≤ ±0.5). Rewrote §4 generation to Gaussian sampling with a fixed bias-stack order (sample → ability → culture → faction → alignment → clamp); Tier C stores three sampled axes + Motivation. Rewrote §5.3 relationship-count biasing to derive sociability from the new axes. Rewrote §7 data structures to twelve integer axes + two motivation tags. Rewrote §8 around the new **`StrategicDisposition`** struct (the clean handoff to the future `gdd-ruler-ai.md`) plus tight, reproducible derivation formulas for the eight ruler weights and the `crisis_response` mapping (labeled PROJECT CALL). Rewrote §9 LLM integration around the **deviation-from-the-mean** prompt strategy (4–7 discard filter — widened from 4–6, a PROJECT CALL), per-axis dialogue directives, Tier-1 caching + runtime assembly, and mock-LLM diagnostic-echo / compositional-flavor modes. ACKS claims cited to `acore_basics_and_characters.xml` and `ax_reactions_and_influencing.xml`. §1, §2, §6, §10, §11 touched up for consistency; §6 Knowledge System logic preserved.
