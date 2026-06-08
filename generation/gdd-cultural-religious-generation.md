# GDD: Cultural and Religious Generation

**Authority:** PROJECT-DESIGNED — cultural and religious content generation is not an ACKS procedure. ACKS provides cleric spell lists, temple mechanics, domain ruler behavior, and alignment definitions. This GDD defines what a culture and a religion ARE as data structures and how they are generated.
**Status:** Draft
**Depends on ACKS rules:** `acore_core_classes.xml` (cleric class, turn undead, spell access), `acore-setting-construction-rules.xml` and `acore_axioms_strongholds_and_domains.xml` (domain economics, stronghold types), `acore-setting-construction-rules.xml` (NPC demographics)
**Depends on project GDDs:** `gdd-setting-generation.md` (cultural group placement, religious tradition placement), `gdd-npc-personality.md` (personality trait axes — culture provides weight biases), `gdd-name-generation.md` (name banks keyed to culture_id), `gdd-settlement-layout.md` (architecture tags, district flavor)
**Modifiable by Claude Code:** Yes.
**Last updated:** 2026-06-08

---

## 1. Purpose

Define the complete data structures for **cultures** and **religions** so that:

1. A lightweight LLM can mass-generate culture and religion files during development for pre-loading and non-LLM testing
2. The integrated runtime LLM can generate them during campaign creation
3. All downstream systems (NPC personality, settlement rendering, domain AI, cleric mechanics, LLM narration) have a concrete, typed data contract to consume

Every culture file and every religion file must conform exactly to the schemas in this document. No freeform fields. Every value is either an enum, a number, or a bounded string.

---

## 2. Culture Data Structure

A culture file is a single JSON object representing one human or demi-human cultural group. One file per culture per campaign.

```json
{
  "culture_id": "string — unique snake_case identifier, e.g. 'keshite', 'valonian', 'dwarven_deephold'",
  "display_name": "string — human-readable name, e.g. 'Keshite', 'Valonian', 'Deephold Dwarf'",
  "race": "string — enum: 'human', 'dwarf', 'elf', 'halfling', 'gnome', 'zaharan', 'thrassian', 'other'",
  
  "terrain_affinity": {
    "primary": "string — enum: 'plains', 'forest', 'mountains', 'desert', 'steppe', 'coast', 'river_valley', 'jungle', 'tundra', 'swamp', 'island'",
    "secondary": "string — same enum, or null if monocultural terrain",
    "avoidance": "string — same enum, or null — terrain this culture rarely inhabits"
  },

  "climate_preference": {
    "temperature": "string — enum: 'tropical', 'subtropical', 'temperate', 'subarctic', 'arctic', 'any'",
    "moisture": "string — enum: 'arid', 'dry', 'moderate', 'wet', 'any'"
  },

  "alignment_tendency": {
    "dominant": "string — enum: 'Lawful', 'Neutral', 'Chaotic' — REQUIRED, every culture trends one direction at runtime regardless of historical complexity",
    "secondary": "string — same enum, or null — if present, must differ from dominant",
    "distribution": {
      "Lawful": "float — 0.0 to 1.0, must sum to 1.0 with other two",
      "Neutral": "float",
      "Chaotic": "float"
    },
    "notes": "The dominant alignment must have the highest distribution value and must be ≥ 0.40. A culture's LLM-generated history may describe past alignment shifts, but at runtime the culture IS its dominant alignment. This is a hard constraint."
  },

  "values": {
    "core_values": ["string — exactly 3 values from enum: 'honor', 'duty', 'freedom', 'knowledge', 'piety', 'wealth', 'family', 'glory', 'tradition', 'cunning', 'hospitality', 'strength', 'beauty', 'law', 'independence', 'community'"],
    "taboos": ["string — 1-3 short phrases, max 60 chars each, e.g. 'oath-breaking', 'cowardice in battle', 'disrespect to elders'"],
    "social_structure": "string — enum: 'feudal', 'tribal', 'theocratic', 'mercantile_republic', 'caste', 'egalitarian', 'imperial_bureaucracy', 'clan_confederation'",
    "gender_roles": "string — enum: 'patriarchal', 'matriarchal', 'egalitarian', 'role_divided'",
    "attitude_toward_outsiders": "string — enum: 'xenophobic', 'wary', 'tolerant', 'cosmopolitan'"
  },

  "personality_weight_biases": {
    "epistemic_curiosity": "float — mean-shift, -2.0 to +2.0, on the 1-10 axis (Dogmatic↔Inquisitive)",
    "societal_orthodoxy": "float — -2.0 to +2.0 (Iconoclast↔Traditionalist)",
    "affective_compassion": "float — -2.0 to +2.0 (Callous↔Self-Sacrificing)",
    "stress_reactivity": "float — -2.0 to +2.0 (Unflappable↔Volatile)",
    "self_interest": "float — -2.0 to +2.0 (Opportunistic↔Principled)",
    "in_group_loyalty": "float — -2.0 to +2.0 (Mercenary↔Zealot)",
    "mysticism": "float — -2.0 to +2.0 (Materialist↔Fanatical)",
    "expressiveness": "float — -2.0 to +2.0 (Laconic↔Theatrical)",
    "civility": "float — -2.0 to +2.0 (Vulgar↔Exquisitely Courteous)",
    "jocularity": "float — -2.0 to +2.0 (Grim↔Frivolous)",
    "amorousness": "float — -2.0 to +2.0 (Prudish↔Shameless)",
    "epicureanism": "float — -2.0 to +2.0 (Ascetic↔Decadent)"
  },

  "military_tradition": {
    "preferred_troop_types": ["string — 2-3 from enum: 'heavy_infantry', 'light_infantry', 'heavy_cavalry', 'light_cavalry', 'horse_archers', 'archers', 'crossbowmen', 'pikemen', 'chariots', 'war_elephants', 'marines', 'berserkers', 'militia'"],
    "fighting_style": "string — enum: 'disciplined_formation', 'skirmish', 'shock_charge', 'guerrilla', 'naval', 'defensive', 'mounted_nomadic', 'mixed_arms'",
    "military_culture": "string — enum: 'professional_standing', 'feudal_levy', 'citizen_militia', 'warrior_caste', 'tribal_warband', 'mercenary_tradition'"
  },

  "economy": {
    "primary_livelihood": "string — enum: 'agriculture', 'pastoralism', 'trade', 'fishing', 'mining', 'raiding', 'crafts', 'hunting_gathering'",
    "secondary_livelihood": "string — same enum, or null",
    "trade_goods": ["string — 2-4 short strings, max 30 chars each, e.g. 'spices', 'silk textiles', 'iron ore', 'salted fish'"],
    "currency_attitude": "string — enum: 'coin_economy', 'barter_primary', 'mixed', 'gift_economy'"
  },

  "magic_attitude": {
    "arcane": "string — enum: 'revered', 'respected', 'regulated', 'feared', 'forbidden', 'commonplace', 'indifferent'",
    "divine": "string — enum: 'central', 'respected', 'regulated', 'feared', 'forbidden', 'commonplace', 'indifferent'",
    "notes": "string — max 120 chars, e.g. 'Arcane magic viewed as ancestral gift; wild magic distrusted'"
  },

  "architecture_style": {
    "primary_material": "string — enum: 'stone', 'timber', 'mudbrick', 'marble', 'thatch_and_wattle', 'ice_and_hide', 'living_wood', 'coral', 'tent_and_hide'",
    "aesthetic": "string — enum: 'monumental', 'ornate', 'austere', 'organic', 'fortified', 'colorful', 'utilitarian', 'elegant'",
    "signature_feature": "string — max 60 chars, e.g. 'onion domes', 'terraced ziggurats', 'carved stone facades', 'elevated stilt houses'"
  },

  "language": {
    "language_name": "string — the name of this culture's language, e.g. 'Keshiri', 'Valon', 'Deepspeak'",
    "language_family": "string — shared family for mutual intelligibility, e.g. 'Thanic', 'Elvish', 'Old Imperial'",
    "script": "string — enum: 'own_script', 'shared_regional', 'borrowed', 'none_oral_only'"
  },

  "flavor_text": {
    "one_line": "string — max 120 chars, single-sentence cultural identity summary",
    "one_paragraph": "string — max 500 chars, paragraph-length cultural description for LLM context and player display"
  }
}
```

### 2.1 Personality Weight Bias Rules

`personality_weight_biases` is a **flat map of twelve mean-shifts**, one per dispositional axis defined in `gdd-npc-personality.md` §3.2. Each value is a **mean-shift on the 1–10 axis scale**, in the range **−2.0 to +2.0**. These are applied during NPC generation as the **cultural** mean-shift in the fixed bias stack (`gdd-npc-personality.md` §4.1: sample → ability → **culture** → faction → alignment → clamp). Motivation is **not** biased here — Motivation is biased by alignment per `gdd-npc-personality.md` §3.3; the culture's other fields (`core_values`, `alignment_tendency`, etc.) continue to feed downstream systems directly and are not subsumed by these biases.

**Constraints the LLM must follow when generating biases:**
- Each value is a single float per axis in [−2.0, +2.0]. There is no per-axis "sum to zero" rule — these are direct mean-shifts, not a redistribution within a tag table.
- Most axes should be near 0.0; a culture is defined by a handful of strong shifts (typically 3–6 axes shifted by ≥ |1.0|), not by nudging all twelve.
- The bias profile must be internally consistent with the culture's `core_values`, `alignment_tendency`, `attitude_toward_outsiders`, and `military_tradition`. Examples of consistent profiles:
  - A **martial honor-culture** shifts Stress Reactivity **negative** (toward Unflappable), In-Group Loyalty **positive**, Civility **positive**, Self-Interest **positive** (toward Principled).
  - A **mercantile cosmopolitan culture** shifts Epistemic Curiosity **positive**, Self-Interest **negative** (toward Opportunistic), Mysticism **negative**.

**Worked example (`personality_weight_biases` for a steppe horse-nomad raiding culture):**
```json
"personality_weight_biases": {
  "epistemic_curiosity": 0.0,
  "societal_orthodoxy": -0.5,
  "affective_compassion": -1.0,
  "stress_reactivity": 1.0,
  "self_interest": -0.5,
  "in_group_loyalty": 1.5,
  "mysticism": 0.5,
  "expressiveness": 0.5,
  "civility": -1.0,
  "jocularity": 0.0,
  "amorousness": 0.0,
  "epicureanism": -1.0
}
```
This reads as: fiercely loyal to the clan (In-Group Loyalty +1.5), quick-tempered and aggressive (Stress Reactivity +1.0), callous toward outsiders (Affective Compassion −1.0), blunt and rough-mannered (Civility −1.0), spurning luxury (Epicureanism −1.0), with a streak of opportunism (Self-Interest −0.5) and totemic spirituality (Mysticism +0.5).

> **Migration note.** This schema replaces the retired four-axis tag schema (`temperament` / `motivation` / `social_style` / `moral_compass` sub-objects of `personality_weight_biases`). **Any pre-generated culture JSON files under `data/cultures/` that use the old schema must be regenerated** against this twelve-axis schema. Do **not** attempt to migrate old files automatically — regenerate them with the §9.1 culture prompt and re-validate per §10.1.

---

## 3. Religion Data Structure

A religion file is a single JSON object representing one religious tradition. One file per religion per campaign.

```json
{
  "religion_id": "string — unique snake_case identifier, e.g. 'ammonar_faith', 'chthonic_mysteries'",
  "display_name": "string — human-readable, e.g. 'The Faith of Ammonar', 'The Chthonic Mysteries'",

  "theology": {
    "type": "string — enum: 'polytheist', 'henotheist', 'monotheist', 'dualist', 'animist', 'ancestor_worship', 'non_theist'",
    "syncretism": "string — enum: 'exclusivist', 'inclusivist', 'syncretist'",
    "afterlife_belief": "string — enum: 'paradise_and_damnation', 'reincarnation', 'ancestral_realm', 'oblivion', 'spirit_world', 'judgment_and_rebirth', 'unknown'"
  },

  "alignment": "string — enum: 'Lawful', 'Neutral', 'Chaotic'",

  "associated_cultures": ["string — culture_id values of cultures where this religion is dominant or significant"],

  "clergy": {
    "title_hierarchy": [
      "string — ordered lowest to highest, e.g. 'Acolyte', 'Priest', 'High Priest', 'Patriarch'"
    ],
    "title_level_mapping": {
      "1": "string — title for level 1 clerics",
      "3": "string — title for level 3 clerics",
      "5": "string — title for level 5 clerics",
      "7": "string — title for level 7+ clerics",
      "9": "string — title for level 9+ clerics (name level)"
    },
    "gender_restriction": "string — enum: 'male_only', 'female_only', 'none'",
    "special_class": "string or null — if this religion uses a specific class other than Cleric, e.g. 'bladedancer', 'shaman'. null for standard Cleric",
    "vestments": "string — max 80 chars, e.g. 'white robes with gold sun embroidery', 'black hooded cloaks with silver skull clasps'",
    "holy_symbol": "string — max 60 chars, e.g. 'golden sun disk', 'silver crescent and star', 'iron fist grasping a lightning bolt'"
  },

  "practices": {
    "holy_days_per_year": "int — 2-12, number of major holy days",
    "holy_day_character": "string — enum: 'festival', 'solemn', 'sacrificial', 'martial', 'charitable', 'mystical'",
    "worship_style": "string — enum: 'congregational', 'private_devotion', 'ecstatic', 'ritual_sacrifice', 'meditative', 'oracular'",
    "dietary_restrictions": "string or null — max 60 chars, e.g. 'no pork', 'ritual fasting on holy days', 'vegetarian clergy'. null if none",
    "funerary_practice": "string — enum: 'burial', 'cremation', 'sky_burial', 'entombment', 'sea_burial', 'mummification'",
    "stance_on_undead": "string — enum: 'abomination', 'natural_cycle', 'tool_of_faith', 'feared_but_accepted', 'venerated'"
  },

  "political_role": {
    "church_state_relationship": "string — enum: 'state_religion', 'influential', 'independent', 'persecuted', 'underground', 'theocratic_ruler'",
    "temporal_authority": "string — enum: 'extensive', 'moderate', 'minimal', 'none'",
    "military_involvement": "string — enum: 'holy_warriors', 'chaplains_only', 'pacifist', 'none', 'crusading'"
  },

  "cosmology": {
    "opposing_view": "string — enum: 'demons', 'false_gods', 'misguided', 'equal_and_opposite', 'irrelevant'",
    "opposing_view_detail": "string — max 200 chars, how this religion regards opposing-alignment supernatural beings",
    "notes": "See §3.3 Alignment Cosmology Rules for the hard constraints governing this field."
  },

  "pantheon": [
    {
      "deity_id": "string — unique snake_case, e.g. 'ammonar', 'calefa', 'nasga'",
      "display_name": "string — e.g. 'Ammonar', 'Calefa the Dawnmother', 'Nasga'",
      "epithets": ["string — 1-3 titles, e.g. 'Lord of Light', 'The Undying Sun'"],
      "alignment": "string — enum: 'Lawful', 'Neutral', 'Chaotic'",
      "portfolios": ["string — 2-4 from enum: 'sun', 'moon', 'war', 'death', 'harvest', 'sea', 'fire', 'earth', 'air', 'water', 'love', 'beauty', 'knowledge', 'magic', 'trickery', 'justice', 'mercy', 'plague', 'fertility', 'storms', 'night', 'forge', 'nature', 'hunt', 'travel', 'trade', 'luck', 'darkness', 'undead', 'madness', 'prophecy', 'protection', 'destruction'"],
      "holy_symbol": "string — max 60 chars, specific to this deity",
      "favored_weapon": "string — weapon name from ACKS equipment list, e.g. 'mace', 'sword', 'spear'",
      "clergy_alignment_requirement": "string or null — if this deity's clerics must be a specific alignment. null = same as religion alignment",
      "sacred_animal": "string or null — e.g. 'eagle', 'serpent', 'bull'. null if none",
      "domains_summary": "string — max 120 chars, what this deity governs in plain language"
    }
  ],

  "flavor_text": {
    "one_line": "string — max 120 chars, single-sentence religious identity summary",
    "one_paragraph": "string — max 500 chars, paragraph-length description for LLM context",
    "creation_myth_summary": "string — max 300 chars, the core creation or origin story in brief",
    "moral_code_summary": "string — max 300 chars, what the faithful are expected to do and avoid"
  },
}
```

### 3.1 Pantheon Rules

- **Polytheist** religions: 4-12 deities in the pantheon array
- **Henotheist** religions: 1 supreme deity + 2-6 subordinate deities
- **Monotheist** religions: exactly 1 deity in the pantheon (may have saints/angels as non-deity entries, but only 1 true deity object)
- **Dualist** religions: exactly 2 deities (one Lawful, one Chaotic)
- **Animist** religions: 0 deities in the pantheon array (spirits, not gods). Add a `spirits` array instead with the same structure minus `clergy_alignment_requirement` and `favored_weapon`
- **Ancestor worship** religions: 0-2 deified ancestors as deities, plus a `"ancestor_veneration": true` flag
- **Non-theist** religions: 0 deities (philosophy, not worship). Omit the pantheon array entirely.

### 3.2 Deity Portfolio Constraint

No two deities within the same pantheon should share more than 1 portfolio. This prevents redundant gods and ensures each deity has a distinct identity.

### 3.3 Alignment Cosmology Rules

**This is a hard constraint.** A religion's alignment determines how it views supernatural beings of opposing alignments. The `cosmology.opposing_view` field must follow these rules:

**Lawful religions:**
- The religion's own gods are Lawful (or Neutral, for tolerant Lawful faiths)
- Chaotic supernatural beings are regarded as **demons, fiends, or abominations** — not as legitimate gods
- `opposing_view` must be `"demons"` or `"false_gods"`
- The religion's moral code must include opposition to Chaos
- Chaotic deities from other religions are referred to in this religion's texts as demons, dark powers, or deceivers — never as valid gods

**Chaotic religions:**
- The religion's own gods are Chaotic (or Neutral, for pragmatic Chaotic faiths)
- Lawful supernatural beings are regarded as **tyrant-gods, false idols, or imprisoners** — not as legitimate benevolent powers
- `opposing_view` must be `"demons"`, `"false_gods"`, or `"misguided"`
- The religion's moral code frames Lawful deities as oppressors, jailers, or deceivers who deny freedom and truth

**Neutral religions:**
- The religion may view BOTH Lawful and Chaotic beings as valid supernatural powers (`"equal_and_opposite"`) — this is a "both are real gods" cosmology
- OR the religion may view BOTH Lawful and Chaotic beings as deceivers, extremists, or forces to be kept in balance (`"false_gods"` or `"misguided"`)
- OR the religion may be non-cosmological (`"irrelevant"`) — focused on nature, ancestors, or philosophy without engaging in the god/demon debate
- `opposing_view` may be any value

**Cross-religion deity mapping:**
When two religions of opposing alignments exist in the same campaign, the same supernatural being may appear in both pantheons — as a god in one and a demon in the other. The setting generation LLM (Layer 7) should identify these mappings and note them in the narrative:

```
Example:
  - Lawful religion "Faith of Ammonar" worships Ammonar (sun, justice)
  - Chaotic religion "Chthonic Mysteries" names Ammonar as "The Burning Tyrant" — 
    a demon who imprisons souls in false light
  - Chaotic religion worships Nasga (darkness, freedom)
  - Lawful religion names Nasga as "The Corruptor" — a demon who lures 
    the faithful into wickedness
```

This duality is narrative, not mechanical. Both religions use the same ACKS cleric mechanics. But it provides rich LLM context for NPC dialogue, religious conflict, and political tension.

---

## 4. Culture-Religion Seeding Relationship

**Hard rule:** Every culture seeds exactly one religion at creation time. The culture and its religion are generated as a pair — 1 culture = 1 religion with a defined pantheon and cosmology.

```
Seeding rules:
1. Every culture has exactly one dominant alignment (§2 alignment_tendency.dominant)
2. When a culture is generated, a religion is generated alongside it:
   - religion.alignment == culture.alignment_tendency.dominant
   - religion.associated_cultures initially contains ONLY this culture
   - The religion's pantheon, practices, and cosmology are generated to
     fit the culture's values, terrain, and alignment
3. This is the STARTING CONDITION. During setting generation
   (gdd-setting-generation.md §7.2), religions may spread or drift:
   - A syncretist religion may be adopted by neighboring cultures
   - Conquest may impose one culture's religion on another
   - Trade may introduce minority religious presence in foreign territory
   - The result: religions start 1:1 with cultures but may end up
     shared across multiple cultures after demographic spreading
4. Regardless of spreading, a culture's PRIMARY religion (highest weight
   in hex demographic data) always matches its dominant alignment
5. Minority religions of opposing alignment (introduced by spreading)
   should be rare (≤15% of the culture's religious distribution)

Validation:
  - At generation time: each culture produces exactly 1 religion file
  - After demographic spreading: the religion with highest weight for
    a given culture must have alignment == culture.alignment_tendency.dominant
  - Any religion with alignment opposed to the culture's dominant
    (L↔C) must have ≤15% weight in that culture's religious distribution
```

### 4.1 Worked Example

```
Culture: Keshite (dominant alignment: Lawful)
  Religious distribution:
    Faith of Ammonar (Lawful): 65%     ← primary, matches dominant ✓
    Path of the Ancestors (Neutral): 20% ← minority, compatible ✓
    Chthonic Mysteries (Chaotic): 8%    ← opposing, ≤15% ✓
    Other/None: 7%

  - Keshite clerics are overwhelmingly Ammonite
  - Ammonite doctrine teaches that Chthonic deities are demons
  - The 8% Chthonic followers are an underground cult, persecuted
  - A Keshite NPC is most likely Lawful and Ammonite, but occasionally 
    the generator produces a Chaotic Keshite who secretly follows the 
    Chthonic Mysteries — that's an interesting NPC, not a bug
```

---

## 5. Cross-References Between Culture and Religion

```
At generation time (1:1 seeding):
  - Each culture file is generated alongside exactly 1 religion file
  - The religion's associated_cultures array starts with [this_culture_id]
  - The culture does not store a religion_id directly — the link
    is through the religion's associated_cultures and through
    hex-level demographic weights

After setting generation (spreading may occur):
  - A religion's associated_cultures may grow to include additional cultures
  - Hex religious_weights may show multiple religions per culture territory
  - The PRIMARY religion for each culture's homeland always matches
    the origin culture

Runtime linkage:
  - A hex's religious_weights (from setting generation) determine which 
    religion a generated NPC follows
  - The NPC's culture_id determines naming and personality biases
  - The NPC's religion_id determines deity allegiance, clergy titles, 
    and behavioral constraints for clerics
```

---

## 6. How Culture Data Feeds Downstream Systems

| System | What It Consumes | Example |
|---|---|---|
| NPC personality generation | `personality_weight_biases` | Steppe nomad culture biases Stress Reactivity +1.0, In-Group Loyalty +1.5, Civility −1.0, Epicureanism −1.0 |
| Settlement rendering | `architecture_style` | Mudbrick + ornate + "onion domes" → visual style tags for settlement display |
| Domain ruler AI | `values.core_values` + `military_tradition` | Honor-culture ruler with shock_charge tradition → high expansion + military weights |
| Encounter narration (LLM) | `flavor_text.one_paragraph` + `values` + `magic_attitude` | LLM knows this culture fears arcane magic and values hospitality |
| Trade system | `economy` | Pastoral culture trades livestock and wool; fishing culture trades salted fish |
| Military recruitment | `military_tradition` | Culture with `warrior_caste` + `heavy_cavalry` → available troop types |
| Reaction rolls | `values.attitude_toward_outsiders` | Xenophobic culture → -1 reaction to foreign PCs; cosmopolitan → +1 |

---

## 7. How Religion Data Feeds Downstream Systems

| System | What It Consumes | Example |
|---|---|---|
| Cleric creation | `clergy.title_level_mapping`, `clergy.gender_restriction`, `clergy.special_class` | Level 5 cleric of Ammonar → title "Sun Priest", wears white robes with gold sun |
| Temple stocking | `clergy.title_hierarchy`, `pantheon[].holy_symbol` | Temple has a shrine to each deity; head cleric's title from hierarchy |
| Temple count rule | (from gdd-settlement-layout.md §11.2) — each 6+ cleric runs a temple dedicated to a specific deity from the pantheon | 3 clerics level 6+ in a polytheist city → 3 temples, each to a different deity |
| Turn undead behavior | `practices.stance_on_undead` | "abomination" → clerics always turn; "tool_of_faith" → Chaotic clerics may command |
| Funeral encounters | `practices.funerary_practice` | Cremation culture → funeral pyres; entombment → catacombs beneath temples |
| Holy day events | `practices.holy_days_per_year`, `holy_day_character` | Festival holy day → market bonuses, NPC morale boost; sacrificial → encounter hooks |
| Political simulation | `political_role` | State religion with extensive temporal authority → church taxes, clergy in government |
| LLM narration | `flavor_text`, `moral_code_summary`, `creation_myth_summary` | LLM knows what a priest of this faith would say and believe |

---

## 8. LLM Generation Prompts

### 9.1 Culture Generation Prompt

```
Generate a complete fantasy culture file conforming exactly to the 
provided JSON schema.

Parameters:
  culture_id: {id}
  race: {race}
  terrain_affinity.primary: {terrain}
  climate_preference.temperature: {climate}
  alignment_tendency.dominant: {alignment}

Constraints:
  - All enum values must be from the allowed lists (provided below)
  - personality_weight_biases: a flat map of the twelve dispositional axes
    (gdd-npc-personality.md §3.2); each value a mean-shift in [-2.0, +2.0]
  - Most axes near 0.0; define the culture with a handful of strong shifts
    (typically 3-6 axes at >= |1.0|), consistent with core_values, alignment,
    attitude_toward_outsiders, and military_tradition
  - core_values: exactly 3, from the allowed enum
  - taboos: 1-3 entries, max 60 chars each
  - trade_goods: 2-4 entries, max 30 chars each
  - All flavor text must be original, not copied from real-world cultures
  - The culture must feel internally consistent — values, economy, 
    military, and personality biases should reinforce each other
  - Output valid JSON only. No commentary, no markdown fencing.

[Insert full schema with enum lists here]
```

### 9.2 Religion Generation Prompt

```
Generate a complete fantasy religion file conforming exactly to the 
provided JSON schema.

Parameters:
  religion_id: {id}
  alignment: {alignment}
  theology.type: {theology_type}
  associated_cultures: [{culture_ids}]

Constraints:
  - Pantheon size per theology type rules (§3.1)
  - No two deities share more than 1 portfolio
  - All enum values must be from the allowed lists (provided below)
  - clergy title_level_mapping must cover levels 1, 3, 5, 7, 9
  - holy_days_per_year: 2-12
  - All flavor text must be original
  - Creation myth and moral code must be consistent with alignment 
    and theology type
  - Output valid JSON only. No commentary, no markdown fencing.

[Insert full schema with enum lists here]
```

### 9.3 Batch Generation (Pre-Loaded Stock)

Pre-loaded cultures and their paired religions are generated in batches during development. Each batch call produces one culture-religion pair:

```
Generate a fantasy culture and its paired religion as a JSON object 
containing two top-level keys: "culture" and "religion".

Culture parameters:
  culture_id: {id}
  race: human
  terrain_affinity.primary: {terrain}
  climate_preference.temperature: {climate}
  alignment_tendency.dominant: {alignment}

Religion parameters:
  religion.alignment: {alignment}  (must match culture dominant)
  religion.theology.type: {theology_type}

Constraints:
  - Culture and religion must be internally consistent
  - Religion's pantheon, practices, and cosmology must fit the culture
  - See §10.3 for diversity constraints across the full stock
  - Output valid JSON only. No commentary, no markdown fencing.

[Insert full schemas with enum lists here]
```

To generate the full 26-culture stock, run this prompt 20 times for human cultures (one per terrain × alignment slot in the §10.2 matrix), once for lawful elves, once for lawful dwarves, once for neutral elves, once for neutral dwarves, once for chaotic elves, and once for chaotic dwarves. Validate each output per §9, then validate cross-stock constraints per §10.3.

---

## 10. Validation Rules

After LLM generation, validate each file programmatically:

### 10.1 Culture Validation

```
- culture_id is unique and snake_case
- race is a valid enum value
- terrain_affinity.primary is a valid enum value
- climate_preference values are valid enums
- alignment_tendency.distribution sums to 1.0 (±0.01 tolerance)
- alignment_tendency.dominant has the HIGHEST value in distribution (hard rule)
- alignment_tendency.dominant value is ≥ 0.40 (hard rule)
- alignment_tendency.secondary (if present) differs from dominant
- core_values has exactly 3 entries, all from the allowed enum
- taboos has 1-3 entries, each ≤60 chars
- personality_weight_biases has exactly the twelve axis keys (gdd-npc-personality.md §3.2),
  each a float in [-2.0, +2.0]; no `temperament`/`social_style`/`moral_compass`/`motivation`
  sub-objects (those belonged to the retired four-axis tag schema)
- preferred_troop_types has 2-3 entries from the allowed enum
- trade_goods has 2-4 entries, each ≤30 chars
- All flavor_text fields are within char limits
- No field is null unless explicitly allowed (secondary terrain, 
  secondary livelihood, dietary restrictions)
```

### 10.2 Religion Validation

```
- religion_id is unique and snake_case
- alignment is a valid enum
- theology.type is a valid enum
- Pantheon size matches theology type rules (§3.1)
- No two deities share >1 portfolio
- Each deity has 2-4 portfolios from the allowed enum
- clergy.title_level_mapping has entries for keys "1", "3", "5", "7", "9"
- holy_days_per_year is 2-12
- All enum fields use valid values
- All flavor_text fields are within char limits
- Every deity_id is unique within the pantheon
- cosmology.opposing_view is valid for the religion's alignment (§3.3):
    Lawful → must be "demons" or "false_gods"
    Chaotic → must be "demons", "false_gods", or "misguided"
    Neutral → any value allowed
- All deities in the pantheon must have alignment compatible with the 
  religion's alignment (same alignment, or Neutral for tolerant faiths;
  no Chaotic deities in a Lawful pantheon)
```

### 10.3 Cross-File Alignment Coherence Validation

```
- For each culture, its primary associated religion (highest demographic 
  weight) must have alignment == culture.alignment_tendency.dominant
- Any religion with alignment opposing the culture's dominant (L↔C) 
  must have ≤15% weight in that culture's religious distribution
- All associated_cultures listed in a religion file must reference 
  existing culture_ids
```

---

## 11. Pre-Loaded Default Sets

### 11.1 Purpose

The project ships with a complete stock of pre-generated cultures and religions that serve three roles:

1. **LLM-free testing.** The entire setting generation pipeline (demographics, name generation, NPC creation, settlement stocking) can run and be tested without any LLM calls. Pre-loaded cultures and religions provide all the structured data these systems consume.
2. **LLM fallback.** If the LLM is unreachable during campaign creation, the system falls back to selecting from the pre-loaded stock rather than failing. The player gets a functional campaign setting; it just uses pre-built cultural content instead of freshly generated content.
3. **Variety baseline.** 22 cultures with diverse terrain affinities, alignments, and phonemic palettes ensure that any randomly generated map can find culturally appropriate content for its geography.

### 11.2 Pre-Generated Culture Stock

**26 cultures total:** 20 human + 3 elf + 3 dwarf. Each culture is generated as a complete JSON file conforming to §2, paired with exactly 1 religion conforming to §3 (per the 1:1 seeding rule in §4). This produces 26 religion files alongside the 22 culture files.

**Coverage matrix (20 human cultures).** The 20 human cultures cover a 7-terrain × 3-alignment matrix with one intentional gap:

| Terrain Affinity | Lawful | Neutral | Chaotic |
|---|---|---|---|
| Plains (settled agrarian) | ✓ | ✓ | ✓ |
| Steppe (nomadic pastoral) | ✓ | ✓ | ✓ |
| Forest / Woods | ✓ | ✓ | ✓ |
| Mountains | ✓ | ✓ | ✓ |
| Desert / Barren | ✓ | ✓ | ✓ |
| Coast / Sea (seafaring) | ✓ | ✓ | ✓ |
| Swamp | — | ✓ | ✓ |

The swamp-Lawful slot is left empty because it is the least commonly needed combination. If a generated map requires it, the system substitutes the nearest match (swamp-Neutral with a Lawful minority, or plains-Lawful placed in a swamp-adjacent hex).

**Non-human cultures:**

| Culture | Terrain Affinity | Alignment | Notes |
|---|---|---|---|
| Elf (1 culture) | Forest | Lawful | Includes elven religion (nature/ancestor-focused). Serves all elven classes. |
| Dwarf (1 culture) | Mountains | Lawful | Includes dwarven religion (forge/ancestor-focused). Serves all dwarven classes. |
| Elf (1 culture) | Forest | Neutral | Includes elven religion (nature/asceticism-focused). Serves all elven classes. |
| Dwarf (1 culture) | Mountains | Neutral | Includes dwarven religion (wealth/ancestor-focused). Serves all dwarven classes. |
| Elf (1 culture) | Forest | Chaotic | Includes elven religion (nature/immortality-focused). Serves all elven classes. |
| Dwarf (1 culture) | Mountains | Chaotic | Includes dwarven religion (forge/vengeance-focused). Serves all dwarven classes. |

No halfling culture is pre-generated. Halflings use the human culture of the region they inhabit, per ACKS convention that halflings integrate into human communities.

**Additional stripped-down cultures (not counted in the 22):**

- **2 beastman cultures** (orc, goblin) — minimal format: values, military style, personality biases, and flavor text only. No economy, architecture, or religion fields. These are used for beastman NPC generation in clanhold encounters (§6.5 of `gdd-setting-generation.md`).

### 11.3 Pre-Generation Constraints

Each pre-generated culture must satisfy:

```
- Unique phonemic palette (no two cultures should sound similar)
- Unique core_values triad (no two cultures share all 3 values)
- Theology type diversity across the 22 religions:
    At least 3 polytheist, 2 monotheist, 2 animist, 1 dualist,
    1 ancestor worship, 1 non-theist. Remaining slots vary.
- Syncretism diversity: at least 5 exclusivist, 5 syncretist, remainder inclusivist
- Climate preferences distributed across temperature and precipitation ranges
- Each religion has a pantheon conforming to §3.1 rules
  (polytheist: 4-12 gods, monotheist: 1, dualist: 2, etc.)
- All validation rules from §9 pass
```

### 11.4 Selection Algorithm (Fallback Mode)

When the LLM is unavailable during setting generation, the system selects cultures from the pre-loaded stock:

```
1. For each cultural group needed (per gdd-setting-generation.md §7.1):
   a. Identify the homeland terrain affinity from the map
   b. Identify the realm alignment from Layer 3
   c. Select the pre-loaded culture matching (terrain, alignment)
   d. If exact match unavailable (already used or gap slot):
      select nearest match (same terrain + adjacent alignment,
      or same alignment + adjacent terrain)
2. Each selected culture brings its paired religion automatically
3. Demographic spreading (§7.2 of setting generation) proceeds normally
   using the selected cultures and religions
```

---

## 12. File Organization

```
data/cultures/
  culture_keshite.json
  culture_valonian.json
  culture_dwarven_deephold.json
  ...
  
data/religions/
  religion_ammonar_faith.json
  religion_chthonic_mysteries.json
  ...

data/schemas/
  culture_schema.json            # JSON Schema for programmatic validation
  religion_schema.json           # JSON Schema for programmatic validation
```

---

## 13. Revision History

- **2026-03-19:** Initial draft. Full culture data structure with 13 top-level sections. Full religion data structure with pantheon, clergy, practices, and political role. Personality weight biases feeding NPC generation. Downstream system integration mapped. LLM generation prompts with batch support. Validation rules. Pre-loaded default set requirements.
- **2026-03-19 (rev 2):** Added alignment coherence as a hard constraint. Culture dominant alignment must be ≥40% of distribution. Culture's primary religion must match its dominant alignment. Opposing-alignment religions capped at ≤15% of cultural distribution. Added cosmology section to religion schema with deity/demon duality rules — Lawful religions regard Chaotic beings as demons and vice versa, Neutral religions may view both as valid or both as false. Cross-religion deity mapping documented. Alignment coherence validation rules added.
- **2026-03-24:** Established 1:1 culture-religion seeding model — each culture generates exactly one religion at creation time; religions may spread during setting generation but start tied to their origin culture. Expanded pre-loaded default sets from 8 human + 3 non-human + 5 religions to 20 human + 3 elf + 3 dwarf cultures (26 total), each with a paired religion (26 religions). Coverage matrix: 7 terrain affinities × 3 alignments with one gap (swamp-Lawful). Added fallback selection algorithm for LLM-free operation. Removed halfling as standalone culture (halflings use regional human culture per ACKS convention).
- **2026-06-08:** Reworked `personality_weight_biases` from the retired four-axis tag schema (temperament/motivation/social_style/moral_compass tag tables, modifiers −0.3..+0.3 summing to ~0 per axis) to the **flat twelve-axis mean-shift schema** matching the `gdd-npc-personality.md` twelve continuous dispositional axes; range widened to −2.0..+2.0 mean-shifts on the 1–10 axis scale, applied as the **cultural** step in the NPC generation bias stack. Motivation is no longer biased here (Motivation is alignment-biased in `gdd-npc-personality.md` §3.3). Rewrote §2.1 bias rules and added a twelve-axis worked example (steppe horse-nomad). Updated the §6 downstream NPC-personality row, the §9.1 culture-prompt constraints, and the §10.1 culture validation rules to the new schema. Added a migration note: pre-generated culture JSON using the old schema must be regenerated, not auto-migrated.
