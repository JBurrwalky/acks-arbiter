# GDD: Henchman Class Selection (0th → 1st Level)

**Authority:** PROJECT-DESIGNED — ACKS states that 0th-level characters advance to 1st level at 500 XP but leaves class selection to Judge discretion. This GDD systematizes that decision.
**Status:** Draft
**Depends on ACKS rules:** `acore_basics_and_characters.xml` (0th-level advancement, XP threshold), `acore_core_classes.xml`, `acore_demihuman_classes.xml`, `acore_campaign_classes.xml`, and `pc_classes_*.xml` (class requirements — minimum ability scores, race restrictions)
**Depends on project GDDs:** `gdd-npc-personality.md` (henchman personality, motivation), `gdd-cultural-religious-generation.md` (culture's magic attitude, military tradition)
**Modifiable by Claude Code:** Yes.
**Last updated:** 2026-03-19

---

## 1. Purpose

When a 0th-level henchman reaches 500 XP, the game must select a class for them to enter at 1st level. The selection must be deterministic, respect ACKS class requirements (ability score minimums, race restrictions), feel narratively plausible, and account for what the henchman has actually experienced while adventuring.

---

## 2. Selection Procedure

### 2.1 Step 1: Build the Eligible Class List

```
1. Start with ALL classes available in the campaign
2. REMOVE classes whose ability score requirements the henchman does not meet
3. REMOVE classes restricted to races the henchman is not
4. REMOVE classes whose alignment requirement conflicts with the henchman's 
   alignment (if the henchman has one; 0th-level characters are typically Neutral)
5. What remains is the ELIGIBLE class list
```

If the eligible list is empty (extremely unlikely — Fighter has no minimum requirements), default to Fighter.

### 2.2 Step 2: Score Each Eligible Class

Each eligible class receives a score from five weighted factors:

```
CLASS_SCORE = (ability_fit × 4) + (proficiency_fit × 3) + (mentor_influence × 3) + (experience_fit × 2) + (cultural_fit × 1)
```

The weights ensure ability scores dominate, proficiencies and mentorship are strong secondary signals, lived experience differentiates close cases, and cultural background is a tiebreaker.

#### Factor 1: Ability Score Fit (0–10 points)

How well the henchman's ability scores match the class's key attributes:

```
For each key attribute of the class:
  score_contribution = (ability_score - 9) / 2    (clamped to 0–5)
  
  9 = average → 0 points (no special aptitude)
  13 = +1 modifier → 2 points
  16 = +2 modifier → 3.5 points
  18 = +3 modifier → 4.5 points

Sum across all key attributes, cap at 10.

Example: Fighter key attribute is STR.
  Henchman has STR 15 → (15-9)/2 = 3 points
  
Example: Mage key attribute is INT.
  Henchman has INT 8 → (8-9)/2 = -0.5 → clamped to 0

Example: Assassin key attributes are STR and DEX.
  Henchman has STR 12, DEX 14 → (12-9)/2 + (14-9)/2 = 1.5 + 2.5 = 4 points
```

#### Factor 2: Mentor Influence (0–10 points)

Who has the henchman been traveling with? The employer's class (and the party composition) matters — people learn from those they serve.

```
If the henchman's direct employer (the PC they are henchman to) is:
  Same class as candidate → 8 points
  Same combat progression type → 5 points
  Different progression type → 0 points

If the party contains other members of the candidate class 
(not the employer, but other PCs or henchmen):
  +2 points per party member of that class (cap at +4)

Spellcasting exception:
  Arcane classes (mage, elven spellsword, etc.) get 0 mentor points 
  UNLESS the employer or a party member is an arcane caster.
  You don't just pick up wizardry from watching a fighter.
  
  Divine classes (cleric, bladedancer, etc.) get 0 mentor points 
  UNLESS the employer or a party member is a divine caster 
  OR the henchman's religion has a special_class that matches.
```

#### Factor 3: Experience Fit (0–10 points)

What has the henchman actually DONE? The game tracks broad experience categories during play:

```
Experience categories (tracked as simple counters on the henchman record):
  combat_encounters: int      — fights participated in
  traps_encountered: int      — traps found, disarmed, or triggered nearby
  spells_witnessed: int       — spells cast by party members in henchman's presence
  divine_events: int          — turn undead, healing received, religious ceremonies attended
  wilderness_travel: int      — days spent traveling in wilderness
  stealth_situations: int     — situations where sneaking, scouting, or hiding occurred
  social_encounters: int      — negotiations, parley, information gathering
  dungeon_delves: int         — dungeon expeditions participated in

Scoring per class:
  Fighter:     combat_encounters × 1.0 (cap 10)
  Mage:        spells_witnessed × 1.5 (cap 10)
  Cleric:      divine_events × 1.5 (cap 10)
  Thief:       (traps_encountered + stealth_situations) × 0.8 (cap 10)
  Explorer:    (wilderness_travel + dungeon_delves) × 0.6 (cap 10)
  Assassin:    (combat_encounters + stealth_situations) × 0.5 (cap 10)
  Bard:        (social_encounters + combat_encounters) × 0.5 (cap 10)

  For classes not listed above: use the score of the combat progression 
  type they belong to:
    fighter progression → use Fighter formula
    cleric progression → use Cleric formula
    thief progression → use Thief formula
    mage progression → use Mage formula
```

#### Factor 4: Cultural Fit (0–10 points)

Does the henchman's culture encourage this class?

```
Military tradition alignment:
  If the culture's military_tradition.fighting_style matches the class's 
  combat style → +3 points
  (e.g., 'mounted_nomadic' culture → explorer or fighter with cavalry focus)

Magic attitude:
  If candidate is arcane class AND culture.magic_attitude.arcane == 'forbidden' → 0 points
  If candidate is arcane class AND culture.magic_attitude.arcane == 'revered' → +4 points
  If candidate is arcane class AND culture.magic_attitude.arcane == 'feared' → +1 point
  
  If candidate is divine class AND culture.magic_attitude.divine == 'central' → +4 points
  If candidate is divine class AND culture.magic_attitude.divine == 'indifferent' → +1 point

Social structure alignment:
  'warrior_caste' culture → fighter/explorer +3
  'theocratic' culture → cleric +3
  'mercantile_republic' culture → thief/bard +2
  'tribal_warband' culture → fighter/barbarian +3

Cap cultural fit at 10.
```

### 2.3 Step 3: Select Class

```
1. Calculate CLASS_SCORE for each eligible class
2. Select the class with the highest score
3. Ties broken by: ability_fit (highest wins) → proficiency_fit →
   mentor_influence → experience_fit → alphabetical (stable deterministic fallback)
4. The selection is FINAL — henchmen are hired NPCs, not secondary PCs.
   The player does not choose their henchman's class any more than they 
   choose how an NPC levels up at the table. This is by ACKS design.
```

### 2.4 Step 4: Notify Player

When the henchman levels up, present the result:

```
"[Henchman Name] has gained enough experience to advance to 1st level!

Based on their aptitude, training, and experiences, they have become a [Class].

[1-2 sentence narrative justification, e.g., 'After months of watching 
Ser Aldric's swordwork and holding the line in three dungeon battles, 
Torben has developed into a capable Fighter.']"
```

The narrative justification is LLM-generated from the scoring factors. Template fallback: "Having shown aptitude in [highest factor], [Name] has become a [Class]."

---

## 3. Proficiency Influence

### 3.1 Proficiency-to-Class Mapping

0th-level henchmen are assigned general proficiencies when they enter the game (from ACKS hireling generation). These proficiencies are strong signals for class selection — a character who already knows Lockpicking has clearly been on the thief track.

Each proficiency maps to one or more classes with a point value:

```
STRONG SIGNAL (6 points) — proficiency appears on exactly one class's list:
  Lockpicking → Thief
  Tracking → Explorer
  Apostasy → Cleric (inverted — but signals divine awareness)
  Mystic Aura → Mage
  Prophecy → Cleric
  Prestidigitation → Mage
  Acrobatics → Thief, Assassin (3 points each — split)
  Skulduggery → Thief, Assassin (3 points each)

MODERATE SIGNAL (4 points) — proficiency appears on 2-3 class lists:
  Weapon Focus → Fighter, Explorer
  Manual of Arms → Fighter
  Combat Reflexes → Fighter, Assassin
  Healing → Cleric, Explorer
  Theology → Cleric
  Naturalism → Explorer
  Alchemy → Mage, Assassin
  Intimidation → Fighter, Assassin
  Disguise → Thief, Assassin, Bard
  Lip Reading → Thief, Assassin
  
WEAK SIGNAL (2 points) — proficiency is broadly useful across many classes:
  Alertness → (many classes)
  Endurance → (many classes)
  Leadership → (many classes)
  Diplomacy → (many classes)
  Bargaining → (many classes)
```

The full mapping table is maintained in `data/tables/proficiency_class_signals.json` and covers all proficiencies in the game. Classes not listed above follow the same pattern — proficiencies unique to a class's list are strong signals; proficiencies shared across many lists are weak signals.

### 3.2 Scoring

```
For each eligible class:
  proficiency_score = sum of signal points from all henchman proficiencies 
                      that map to this class
  Cap at 10.
```

A henchman with Lockpicking and Skulduggery scores 6 + 3 = 9 points for Thief. A henchman with Manual of Arms and Combat Reflexes scores 4 + 4 = 8 for Fighter.

---

## 4. Experience Tracking

### 4.1 What Gets Tracked

The eight experience counters (§2.2 Factor 3) are incremented automatically during play:

```
combat_encounters:   +1 each time the henchman is present during a combat encounter
traps_encountered:   +1 each time a trap is found, disarmed, or triggered in the 
                     henchman's presence (same room/corridor)
spells_witnessed:    +1 each time any party member casts a spell while the henchman 
                     is present (cap +3 per session to avoid inflation)
divine_events:       +1 for each turn undead, healing spell received, or religious 
                     ceremony attended (cap +3 per session)
wilderness_travel:   +1 per day of wilderness travel
stealth_situations:  +1 each time the party engages in sneaking, scouting, or hiding 
                     with the henchman present
social_encounters:   +1 each time the party engages in negotiation, parley, or 
                     information gathering with the henchman present
dungeon_delves:      +1 per dungeon expedition (entering and leaving a dungeon = 1)
```

### 4.2 Storage

These counters are stored on the henchman's record in the campaign database. They are lightweight (8 integers) and only tracked for 0th-level henchmen. Once the henchman levels up, the counters are archived (retained for narrative reference) but no longer incremented.

---

## 5. Edge Cases

**Demi-human henchmen:** Racial class restrictions apply in Step 1. A dwarven 0th-level henchman can only become a dwarven class (Vaultguard, Craftpriest, etc.). The eligible list is naturally constrained.

**Multiple classes tie perfectly:** The stable tiebreaker (§2.3) prevents true ties. In the astronomically unlikely event of identical scores across all five factors for two classes, alphabetical order selects deterministically.

**Henchman has been with the party for 5 minutes:** If a freshly hired 0th-level henchman somehow hits 500 XP immediately (e.g., party kills a dragon and shares XP), all experience counters are near zero. Ability score fit and proficiency fit dominate — the henchman becomes whatever their stats and existing skills point toward.

**Proficiency strongly signals one class but abilities signal another:** A henchman with Lockpicking (strong thief signal) but STR 16 / DEX 9 will score high on proficiency for Thief but high on ability for Fighter. With ability weight ×4 vs. proficiency weight ×3, ability usually wins unless multiple proficiencies stack toward one class. This is intentional — you can know how to pick a lock and still be built like a fighter.

**No arcane or divine mentor but high INT/WIS:** A henchman with INT 16 and no mage in the party will still score well on ability fit for Mage, but mentor influence will be 0 and spells_witnessed will be 0. They'll likely become a Mage only if ability fit is overwhelmingly strong AND proficiency or cultural fit supports it. Otherwise they'll become a thief (INT helps), explorer, or fighter. This is intentional — you don't become a wizard without exposure to magic.

**Henchman's personality motivation:** Motivation from `gdd-npc-personality.md` is NOT a scoring factor. A henchman motivated by `faith` doesn't automatically become a cleric — they need the WIS score, divine exposure, relevant proficiencies, and/or cultural support. Motivation influences how they roleplay the class they get, not which class they get.

---

## 6. Output Data

```
HenchmanClassSelection:
  henchman_id: string
  eligible_classes: Array[string]           # All classes that passed Step 1
  scores: Dictionary                        # { class_name: { total, ability_fit,
                                            #   proficiency_fit, mentor, experience, 
                                            #   cultural } }
  selected_class: string                    # Highest-scoring class (FINAL)
  narrative_justification: string           # LLM or template explanation
  experience_counters_at_selection: Dictionary  # Snapshot of the 8 counters
  proficiencies_at_selection: Array[string]    # Snapshot of proficiencies used in scoring
```

---

## 7. Revision History

- **2026-03-19:** Initial draft. Four-factor weighted scoring system (ability fit, mentor influence, experience fit, cultural fit). Eight experience counters tracked during play. Edge cases documented.
- **2026-03-19 (rev 2):** Added proficiency fit as a fifth scoring factor (weight ×3, tied with mentor influence). Proficiency-to-class signal mapping with strong/moderate/weak tiers. Removed player override — henchmen are hired NPCs and class selection is not player-controlled per ACKS design. Selection is final and deterministic.
