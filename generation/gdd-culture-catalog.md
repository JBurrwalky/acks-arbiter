# GDD: Canonical Culture Catalog

**Document type:** Game Design Document (project-designed schema and algorithms, with explicit ACKS Constraints).
**Status:** Draft
**Version:** v0.1
**Authority:** PROJECT-DESIGNED — the record schema, selection/placement, per-campaign variation, and derivation algorithms are engineering decisions. The canonical culture *identities*, *allowed-alignment sets*, *seed biomes*, and *real-world synthesis sources* originate in `gdd-setting-lore.md` §5 and are mirrored here, not reinvented. The shared pantheon they draw on lives in `gdd-setting-lore.md` §4.
**Depends on project GDDs:** `gdd-setting-lore.md` (§4 pantheon, §5 culture canon, alignment definitions), `gdd-npc-personality.md` (personality trait axes consumed by `personality_weight_biases`), `gdd-name-generation.md` (name-bank keys).
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (population density, territory classification), `acore_axioms_strongholds_and_domains.xml` (domain morale, alignment/religion morale modifiers — the present-day handoff target), `ax_domains_of_chaos.xml` (beastman clanhold demographics and population caps), `acore_demihuman_classes.xml` (demihuman classes; domain caps lookup pending — see §8.3).
**Replaces:** the LLM-generated culture model in `gdd-cultural-religious-generation.md` §2 (culture data structure), §4 (1:1 culture-religion seeding), and §11 (pre-loaded LLM stock). See §1.3.
**Blocks:** `gdd-setting-generation.md` (Layer 4 rewrite), `gdd-history-simulation.md` (future), `gdd-region-painting.md` (future).
**Modifiable by Claude Code:** Schema and algorithms — yes. Canonical identity fields and allowed-alignment sets — only in sync with `gdd-setting-lore.md` §5.
**Last updated:** 2026-06-08

---

## 1. Purpose and Relationship to Other Documents

### 1.1 Purpose

Define the **canonical culture** as a data record, and the deterministic rules for **selecting, placing, and varying** canonical cultures when generating a campaign setting. This document is the data foundation that the setting-generation pipeline, the history simulation, region painting, NPC generation, name generation, and the domain/army systems all consume.

The defining shift from the prior model: cultures are **no longer invented per campaign by an LLM**. They are a fixed catalog of authored records (the 45 human cultures of `gdd-setting-lore.md` §5.2, plus demihuman and beastman tiers). Each new campaign **draws a subset**, **places** them on the generated map, **assigns** each an alignment from its allowed set, and **perturbs** their numeric attributes with small seeded jitter. This trades the unbounded variety of LLM generation for controlled quality, internal consistency, asset-matching, and a defensible IP claim (`gdd-setting-lore.md` §1.2).

### 1.2 The culture-vs-polity distinction (read this first)

This catalog describes **cultures**, not **polities**. The two are different objects and behave differently. Getting them confused is the most likely source of design bugs downstream.

- A **culture** is an ethno-linguistic-religious substrate (a people, a language, a pantheon-interpretation, a set of customs). Cultures spread *slowly and demographically* and largely *survive* political collapse — when an empire dies, its people and language usually remain. The culture layer is the per-hex weight data in `gdd-setting-generation.md` §7.3.
- A **polity** is a domain or realm with a ruler, an alignment, and (at game-start) an ACKS domain morale score. Polities *rise, expand, and collapse* into rump and successor states.

A single culture spans many polities; a polity collapse does not erase the culture beneath it. This document defines what a culture *is* and the **inputs** it contributes to the history simulation. The simulation's collapse curve, rump/successor logic, and depopulation rules live in `gdd-history-simulation.md` (future); they are **project-designed at the polity/generation scale** and hand off to the actual ACKS domain systems only at game-start (§8.1). This catalog deliberately does **not** contain collapse mechanics — only the per-culture knobs the simulation reads.

### 1.3 What this replaces in `gdd-cultural-religious-generation.md`

That GDD was built around per-campaign LLM generation of self-contained cultures and **independent per-culture pantheons**. Two parts of it are superseded:

1. **The culture data structure (§2) and pre-loaded LLM stock (§11)** are replaced by the schema (§3) and catalog (§5) here.
2. **The 1:1 culture↔religion seeding (§4) and per-culture pantheon generation (§3)** conflict with `gdd-setting-lore.md` §4, which establishes a **single shared canonical pantheon** (12 Lawful + 13 Chaotic powers) that all cultures interpret through their alignment lens — same gods everywhere, differing only by translated names, local saints/heroes, emphasis, and whether a given power is venerated or named-as-demon. Religion therefore becomes *(canonical pantheon) × (culture's alignment interpretation)*, not a per-culture invented pantheon. The religion-system rework is its own deliverable; this catalog only stores the **religion hooks** a culture needs (§3.2: alignment lens, local-saint slots, name-bank key), and defers the full religion schema to that rework.

Until the religion rework lands, treat `gdd-cultural-religious-generation.md` as **historical** for the culture and pantheon sections, authoritative only where it is not contradicted here or in setting-lore.

---

## 2. Design Principles (decisions locked 2026-06-03)

These were resolved with Jedidiah and are binding for this document:

1. **Canonical, not generated.** Cultures come from the fixed catalog; LLMs do not invent new ones at campaign start.
2. **Fixed canon + seeded jitter.** Every mechanical attribute is an authored constant. Per campaign, the engine perturbs it slightly from the campaign seed (§7). Recognizable cultures, run-to-run texture.
3. **Base scalars + biome-derived terrain behavior.** Expansion and defense are authored as single scalars per culture; per-terrain rates are *derived* from the culture's seed/affinity biomes (§4.1) rather than authored as a full matrix.
4. **Demihumans are capped sim participants.** Elves and dwarves found, expand, and lose domains like humans, bounded by ACKS demihuman demographic caps (§8.3). They are living powers, just rarer and slower.
5. **Sphere weights tilt a fighter-leaning baseline.** The four sphere weights bias ruler/henchman class away from a martial default but keep non-fighter supreme rulers uncommon; they more strongly govern court composition and mercenary availability (§4.3).
6. **Mechanical core / flavor pack split.** Engine-consumed numbers and enums are separated from LLM/art-consumed prose so the deterministic engine never parses flavor text (§3).
7. **Shared pantheon.** Religion is a cultural interpretation of the one canonical pantheon (§1.3), not a per-culture pantheon.
8. **Historical-only cultural toponyms.** Region names derived from a culture/polity (the "Germany-as-region" layer) are produced only for *fallen* polities, by the history simulation and region painter — never as a live overlay competing with active polity names. This catalog supplies the durable `toponym` root that the history log can later resurrect.

---

## 3. Culture Record Schema

Each canonical culture is one record with two top-level objects: `mechanical` (deterministic, engine-facing) and `flavor` (LLM/art-facing). Stored one file per culture in `data/cultures/`.

### 3.1 Mechanical core

```json
{
  "schema_version": 1,
  "mechanical": {
    "identity": {
      "culture_id": "string — unique snake_case, e.g. 'agrippan'",
      "catalog_number": "int — the §5.2 list number, e.g. 1 (stable cross-reference)",
      "demonym": "string — e.g. 'Agrippan'",
      "toponym": "string — durable region-name root, e.g. 'Agrippa' (used by region painter for fallen-polity names)",
      "tier": "string — enum: 'human' | 'demihuman' | 'beastman'",
      "race": "string — enum: 'human' | 'elf' | 'dwarf' | 'orc' | 'goblin' | 'gnoll' | ... (beastman races per ax_domains_of_chaos)",
      "civ_or_clan": "string — enum: 'civ' | 'clan' (starting organization propensity; the sim may promote a clan culture to civ over history — §4.7)",
      "synthesis_sources": ["int — §5.1 real-world analog numbers, e.g. [7, 10] for Celtic+Japanese"]
    },

    "alignment": {
      "allowed": ["string — subset of ['Lawful','Neutral','Chaotic'] from setting-lore §5.2 (human tier); demihumans open to all three. NOT ranked — default prevalence is an EVEN split across the listed alignments (§4.2)."],
      "weights": "object — OPTIONAL explicit prevalence map, e.g. {'Lawful':0.4,'Chaotic':0.4,'Neutral':0.2}. Must cover exactly the 'allowed' members and sum to 1.0. When present, overrides the §4.2 even-split default. Humans normally omit it; the demihumans use it.",
      "rigidity": "float 0.0–1.0 — resistance to alignment drift when a polity of this culture collapses (1.0 = never drifts; consumed by history sim, §4.5)"
    },

    "terrain": {
      "seed_biomes": ["string — biome tags from gdd-terrain-system.md, from setting-lore §5.2 'Seed Biomes'"],
      "affinity_secondary": ["string — biomes the culture tolerates well, optional"],
      "avoided": ["string — biomes the culture rarely inhabits, optional"],
      "coastal_start": "string — enum: 'Y' | 'N' | 'E' (either), from setting-lore §5.2"
    },

    "expansion": {
      "aggression": "float 0.0–1.0 — base outward expansion drive per generation",
      "defense": "float 0.0–1.0 — base resistance to being expanded into when fronts meet",
      "size_exponent_bias": "float -0.2–+0.2 — per-culture nudge to the global size→expansion-rate exponent (small polities expand faster; this biases how sharply). Optional; defaults 0."
    },

    "conquest": {
      "base_subjugation_vs_genocide": "float 0.0–1.0 — default conquest behavior: 0 = governance only (vassalage; substrate unchanged), 1 = full culture+religion imposition (rewrites conquered hexes' weights). Chaotic-biased.",
      "modifiers": [
        {
          "when": "string — condition on the conquered target's context. Enum: 'target_in_my_seed_biome' | 'target_outside_my_seed_biome' | 'target_is_demihuman' | 'target_same_alignment' | 'target_opposite_alignment'",
          "set": "float 0.0–1.0 — overrides svg when the condition holds (omit if using 'adjust')",
          "adjust": "float -1.0–+1.0 — additive nudge to svg when the condition holds, clamped to [0,1] (omit if using 'set')"
        }
      ],
      "modifiers_note": "Evaluated against each conquest target; first matching 'set' wins, then 'adjust' modifiers apply. Most cultures need only base_subjugation_vs_genocide; demihumans use modifiers heavily (§5.2)."
    },

    "lifecycle": {
      "peak_strength": "float 0.0–1.0 — golden-age expansion/power multiplier the history sim applies during a culture's ascendancy, before age/size decline sets in. Humans ~0.5 (moderate); demihumans high.",
      "collapse_proneness": "float 0.0–1.0 — per-culture steepness modifier on the sim's size+age stability curve. High = peaks then falls hard. Humans moderate; demihumans high.",
      "end_state": "string — enum: 'enduring' | 'enclave' | 'fading' — the arc the sim should steer toward by game-start (advisory, not guaranteed). Humans 'enduring'; demihumans 'enclave'. Consumed by the deferred gdd-history-simulation; recorded here as the per-culture input.",
      "lifecycle_note": "These three feed the project-designed history sim's stability curve (§1.2); this catalog does not implement the curve, only supplies the knobs."
    },

    "infrastructure": {
      "road_propensity": "float 0.0–1.0 — drives road-network density for this culture's realms (§4.6); civ cultures high, nomadic clans low"
    },

    "rulership": {
      "sphere_weights": {
        "military": "float", "mercantile": "float", "religious": "float", "arcane": "float"
      },
      "sphere_weights_note": "Four non-negative weights, normalized to sum 1.0. They TILT a fighter-leaning baseline (§4.3); they do not directly set ruler class.",
      "preferred_troop_types": ["string — 2–4 from the troop-type enum (§3.3)"]
    },

    "npc": {
      "personality_weight_biases": "object — flat twelve-axis mean-shift map per gdd-npc-personality.md §3.2 (epistemic_curiosity, societal_orthodoxy, affective_compassion, stress_reactivity, self_interest, in_group_loyalty, mysticism, expressiveness, civility, jocularity, amorousness, epicureanism); each value a mean-shift in [-2.0, +2.0]"
    }
  }
}
```

### 3.2 Flavor / asset pack

```json
{
  "flavor": {
    "name_bank_key": "string — key into data/name_banks/, e.g. 'agrippan' (one static authored bank per canonical culture — §6.6)",
    "phonemic_palette": "string — single-source: the language/conlang palette; multi-source: the authored blended palette (§4.8)",
    "phenotype_notes": "string — authored physical-description guidance; for synthesis cultures, the explicit blend rule (which features from which source) per setting-lore §5.3",
    "language": { "language_name": "string", "language_family": "string", "script": "string — enum per name-gen GDD" },
    "social_structure": "string — FLAVOR ONLY (narrative cultural character): 'feudal'|'tribal'|'theocratic'|'mercantile_republic'|'caste'|'egalitarian'|'imperial_bureaucracy'|'clan_confederation'. The MECHANICAL government is set by civ_or_clan — only **feudal** (civ) and **clanhold** (clan) are modeled; the rest are narrative flavor laid over one of those two until supplemental government rules are implemented.",
    "values": { "core_values": ["3 from the values enum"], "taboos": ["1–3 short phrases"], "attitude_toward_outsiders": "enum: 'xenophobic'|'wary'|'tolerant'|'cosmopolitan'" },
    "magic_attitude": { "arcane": "enum", "divine": "enum", "notes": "string ≤120 chars" },
    "architecture_style": { "primary_material": "enum", "aesthetic": "enum", "signature_feature": "string ≤60 chars" },
    "religion_hooks": {
      "alignment_lens": "string — resolved per campaign from the culture's chosen alignment (setting-lore §4.2): Lawful → venerate the 12 Lawful powers, name the 13 as demons; Chaotic → venerate the 13, name the 12 as tyrant-gods; Neutral → primarily venerate this culture's ANCESTRAL SAINTS (local_saint_slots), invoking the great gods (law or chaos) only situationally. Stored as a template; resolved at runtime. See §3.4.",
      "local_saint_slots": "int 0–6 — culture-specific venerated saints/heroes/ancestors generated atop the shared pantheon (setting-lore §4.3). HIGH (4–6) for cultures whose allowed set prominently includes Neutral, because Neutral cultures pray chiefly to their saints rather than the great gods; LOWER (1–3) for purely Lawful/Chaotic cultures, where saints are intercessors beneath the great gods.",
      "patron_powers": ["string — alignment-AGNOSTIC portfolio/domain concepts this culture emphasizes (e.g. 'sea','war','mountains','harvest','death','trade'), drawn from the portfolio vocabulary (§3.4). The alignment lens + religion system resolve each concept to the venerated **being**: the Lawful god of that domain for a Lawful culture, the *distinct* Chaotic god of that domain for a Chaotic culture (a separate being, not a re-skin), or the matching ancestral saint for a Neutral culture (§3.4). NEVER alignment-specific deity names."]
    },
    "flavor_text": { "one_line": "string ≤120 chars", "one_paragraph": "string ≤500 chars" }
  }
}
```

### 3.3 Enums and scales

- **Numeric scalars** (`aggression`, `defense`, `rigidity`, `subjugation_vs_genocide`, `road_propensity`, `sphere_weights`): all `0.0–1.0`. Author to **one decimal** (0.0, 0.1, … 1.0); finer precision is false confidence given the jitter (§7).
- **Troop-type enum** (reused from `gdd-cultural-religious-generation.md` §2, retained as still-valid): `heavy_infantry, light_infantry, heavy_cavalry, light_cavalry, horse_archers, archers, crossbowmen, pikemen, chariots, war_elephants, marines, berserkers, militia`. Authoring must respect ACKS troop availability (`daw_campaigns_troop_tables_summary.xml`) — a culture cannot "prefer" a troop type ACKS does not let its terrain/tech field.
- **Values enum** (reused): `honor, duty, freedom, knowledge, piety, wealth, family, glory, tradition, cunning, hospitality, strength, beauty, law, independence, community`.
- **Personality axes**: defined by `gdd-npc-personality.md`. This catalog does not redefine them; it only stores per-culture modifiers. If that GDD's axes change, the modifiers are revalidated, not the schema.
- **Biome tags**: must be valid tags from `gdd-terrain-system.md`. Author seed biomes by copying setting-lore §5.2 verbatim, then mapping any prose terms (e.g. "glacial mountains") to the canonical tag.

### 3.4 `patron_powers` and the shared pantheon (PROVISIONAL — pending religion rework)

`gdd-setting-lore.md` §4 establishes two pantheons — 12 Lawful powers and 13 Chaotic powers — that are **entirely distinct beings**, not two faces of one force. The Chaotic pantheon mirrors the Lawful pantheon **in aggregate** (the whole opposes the whole), but the gods do **not** pair off 1:1. Where a Lawful and a Chaotic god have overlapping provenance (both touch war, or the sea) they are **nemeses**; and across the board, regardless of overlap, the two pantheons are **enemies**.

A culture does not own a private pantheon; it venerates the shared powers through its alignment (setting-lore §4.2). So `patron_powers` stores alignment-**agnostic portfolio concepts** — the divine domains the culture cares about — which resolve as:

| Culture's chosen alignment | A `patron_powers` concept resolves to… |
|---|---|
| Lawful | the Lawful god whose provenance covers that portfolio (a specific being) |
| Chaotic | a Chaotic god whose provenance covers that portfolio — a **distinct being**, nemesis of the Lawful one, never a re-skin |
| Neutral | the culture's matching **ancestral saint** (`local_saint_slots`); Neutral cultures pray chiefly to venerated ancestors, not the great gods (setting-lore §4.2) |

The concept vocabulary is the portfolio enum (`sun, moon, war, sea, harvest, death, trade, knowledge, night, forge, nature, hunt, storms, fire, fertility, …`).

**This whole block is provisional and will be revisited.** The religion-system rework (§12) owns the real model: which Lawful and which Chaotic beings cover each portfolio and their nemesis relationships, the **per-culture canonical names** for each deity, and **cultural holy symbols**. Until then `patron_powers` records concepts only — no deity name or symbol is resolved here.

---

## 4. Derived Behaviors (how the engine reads the core)

The mechanical core is intentionally small. These rules expand it into runtime behavior. All are deterministic given the campaign seed.

### 4.1 Per-terrain expansion / defense derivation

There is no authored per-terrain matrix. The engine derives a per-terrain rate from the base scalar and the culture's biome lists:

```
terrain_multiplier(culture, terrain):
    if terrain in culture.seed_biomes:          return 1.5
    elif terrain in culture.affinity_secondary:  return 1.15
    elif terrain in culture.avoided:             return 0.5
    else:                                         return 1.0   # neutral

expansion_rate(culture, terrain) = clamp01( aggression  × terrain_multiplier(culture, terrain) )
defense_rate(culture, terrain)   = clamp01( defense     × terrain_multiplier(culture, terrain) )
```

Multipliers (1.5 / 1.15 / 1.0 / 0.5) are tunable global constants, not per-culture. This is what makes the Vargari (seed: tundra, taiga, mountains, glacial mountains) surge across the cold north while crawling through their `avoided` desert, without authoring 24 numbers per culture.

### 4.2 Per-campaign alignment selection

The `alignment.allowed` list is **not ranked**. For human cultures it simply names the alignments that may appear (from setting-lore §5.2), and a culture's polities are assigned a dominant alignment by an **even (uniform) draw** across them:

```
2 allowed  -> 50% / 50%
3 allowed  -> ~33% each
1 allowed  -> always that alignment
```

**Override — `alignment.weights`.** A culture that genuinely leans specifies an explicit prevalence map, which replaces the even split. Used by the demihumans, authored per-branch: the three elf branches (Aelvaneth/Xilvaneth/Thalvaneth) and three dwarf dialects (Khordurn/Gormdurn/Khraaldurn) each carry their own weights (setting-lore §5.2 #48–53; detailed in §5.2 here). Human cultures normally omit `weights` and take the even split.

A culture's *individual NPCs* still vary regardless — a dominant-Lawful polity produces occasional Neutral or (if allowed) Chaotic individuals via the demographic weight floor in `gdd-setting-generation.md` §7.3. The alignment drawn here is the **starting** dominant; the history sim may shift it on collapse, bounded by §4.5.

### 4.3 Sphere weights → ruler and henchman class bias

`sphere_weights` (military / mercantile / religious / arcane) **tilt** a martial-leaning baseline; they do not directly set the ruler's class. Mapping of sphere → ACKS class family (project-design, not an ACKS rule):

| Sphere | Class family it favors |
|---|---|
| military | Fighter (and fighter-type campaign/demihuman classes) |
| religious | Cleric (and cleric-type campaign classes) |
| arcane | Mage (and mage-type campaign classes) |
| mercantile | Thief / Venturer (`ax_venturer_class.xml`) |

```
ruler_class_distribution(culture):
    base = { fighter: 0.60, cleric: 0.15, mage: 0.10, thief_venturer: 0.15 }   # martial-leaning baseline (tunable)
    tilt = normalize(sphere_weights) mapped onto the four class families
    dist = lerp(base, tilt, BLEND)      # BLEND ≈ 0.5 — sphere weights move the odds, don't replace them
    return normalize(dist)
```

The same `sphere_weights` more strongly govern (a) the **composition of a ruler's henchmen/court** and (b) **which mercenaries a culture's settlements offer** — there the weights are applied at full strength rather than blended, because exotic supporting cast is cheap to the world's coherence while exotic supreme rulers are not. A high-`arcane` culture rarely has a mage *king* but reliably staffs courts with magist advisors and offers arcane mercenaries; a high-`religious` culture trends toward theocratic government (`flavor.social_structure`) and clerical advisors.

### 4.4 Conquest behavior (subjugation ↔ genocide)

When a polity of culture C conquers a hex held by another culture, the **effective** subjugation-vs-genocide for that act is computed from the base and the conditional modifiers (§3.1 `conquest`):

```
effective_svg(C, target):
    svg = C.conquest.base_subjugation_vs_genocide
    for m in C.conquest.modifiers:           # 'set' modifiers first (first match wins), then 'adjust'
        if condition_holds(m.when, C, target):
            apply m.set  (override)  or  m.adjust (clamp01)
    return svg

per generation the hex is held:
    governance change is immediate (the hex's political_entity_id flips at conquest)
    culture/religion substrate shifts toward C at rate ≈ effective_svg × ASSIMILATION_STEP
    effective_svg ≈ 0.0  -> substrate essentially unchanged (vassalage; the conquered remain themselves)
    effective_svg ≈ 1.0  -> substrate converts within a few generations (absorbed or displaced)
```

This is the mechanism behind "impose culture vs. merely impose governance," and the modifiers make it **context-sensitive** — central to demihuman behavior (§5.2), where a conquered target's biome and race flip the same culture between vassalizing and exterminating. It interacts with ACKS morale at game-start: a hex still culturally/religiously distinct from its ruler carries the ACKS alignment- and religion-mismatch morale penalties (§8.1), the correct rules-grounded tension for a recently-conquered, unassimilated province.

### 4.4a Lifecycle (golden age and decline)

The `lifecycle` block supplies per-culture modifiers to the history sim's size+age stability curve (which the sim owns, §1.2): `peak_strength` scales a culture's ascendant-phase expansion before decline; `collapse_proneness` steepens the age/size-driven fall; `end_state` is the advisory target the arc steers toward by game-start. This is how a tier can be authored to **rise high and fall hard** rather than simply grind upward — the demihuman arc (§5.2). The catalog records the knobs; the curve lives in `gdd-history-simulation.md`.

### 4.5 Alignment rigidity (collapse drift hook)

This catalog does not own collapse, but it supplies the drift constraint. When the history sim collapses a polity and rolls for alignment change, the result is bounded twice: (1) it can only land within the **culture's** `alignment.allowed` set (so an Agrippan rump can slide Lawful→Neutral but never to Chaotic, which Agrippa does not allow — setting-lore §5.2), and (2) the **probability** of any drift at all is `(1 − rigidity)` scaled by the sim's collapse severity. High-rigidity cultures (rigid theocracies, tradition-bound clans) hold their alignment through collapse; low-rigidity cultures fragment ideologically.

### 4.6 Road propensity → road density

`road_propensity` scales the road-network density produced in `gdd-setting-generation.md` §9.2 for this culture's realms, and feeds the "major road" definition the region painter will use. Provisional definition of a **major** road (to be finalized in `gdd-region-painting.md`): a route is *major* if it connects two Class III+ settlements or crosses a realm border as a trunk trade road; only major roads receive culturally-appropriate proper names. `road_propensity` controls how many minor connectors exist and how aggressively the network reaches into borderlands — a Roman-analog civ (Agrippan) builds a dense named-highway lattice; a steppe clan (Orkhan) leaves mostly tracks.

### 4.7 Civ/clan promotion over history

`civ_or_clan` is a **starting** propensity, not a permanent label. A `clan` culture whose polity survives, grows, and settles may be promoted to `civ` organization by the history sim (acquiring urban settlements, denser roads, bureaucratic government). The reverse — a `civ` culture's collapsed remnant reverting to clan organization in depopulated borderlands — is also permitted. The catalog stores only the start state; the sim owns transitions.

### 4.8 Multi-source synthesis (authored, not algorithmic)

Cultures with multiple `synthesis_sources` (e.g. Shidhean = [7,10], Celtic+Japanese) have their blended phonemic palette, phenotype rule, and aesthetic **hand-authored**, per the locked principle of controlled quality. The schema stores the source numbers for reference and the *resulting* authored values; the engine never blends at runtime. `phenotype_notes` must state the explicit blend rule and exclude the inconsistent inverse, exactly as setting-lore §5.3 illustrates for Shidhean (Celtic hair/eyes/stature + Japanese skin tone/facial structure; not the reverse).

---

## 5. Culture Tiers

### 5.1 Human canon (the 45)

The 45 human cultures of `gdd-setting-lore.md` §5.2 are the human tier, one record each. Their `identity`, `alignment.allowed`, `seed_biomes`, `coastal_start`, `civ_or_clan`, and `synthesis_sources` are **copied from §5.2 and are sacred to this document** (mirror, don't reinvent). All remaining mechanical and flavor fields are authored here per §3. §9 gives three fully worked records; the rest are produced in the authoring pass (§10).

### 5.2 Demihuman canon (elf, dwarf)

Demihumans use the same schema with `tier: "demihuman"`. Per the locked decision they are **capped sim participants** — but with a deliberate **divergence from ACKS's default flavor** (see §8.3): rather than being a perpetually-declining elder race, elves and dwarves **begin the historical simulation strong and ascendant, then collapse hard into the defensive enclaves** the present-day ACKS rules describe. The catalog encodes that arc, not a steady decline.

- **Seed biomes (per branch).** The three elvish cultures are the forest-and-river **Aelvaneth** (`forest`, `dense_forest`), the jungle-and-river **Xilvaneth** (`jungle`, `dense_forest`), and the coastal sea-elven **Thalvaneth** (`forest`/`dense_forest`/`jungle`/`taiga` that is **also coastal**, at any elevation — where forest meets the sea); the three dwarven cultures are the mountain **Khordurn** (any `mountains` except glacial/volcanic), the volcanic **Gormdurn** (`volcanic mountains` only), and the glacial **Khraaldurn** (`glacial mountains` or `tundra hills` only). The three are branches of one people descended from a shared Proto-Elvish tongue ("Vanethir"; see the conlang `family_elvish.json`, where each branch is built as a deep ancestor of a cluster of the human language families: Aelvaneth->Germanic/Celtic/Slavic, Xilvaneth->Mesoamerican, Thalvaneth->Latinate/Hellenic/Punic). Their homelands originate in wilderness — as do **all** cultures' (the universal wilderness-seeding model, §6.3); this is not demihuman-specific.
- **Alignment.** Both races are open to all three and both use an explicit `weights` map (the even-split default is for humans, §4.2). **The three dwarf dialects each lean Neutral, differently** (setting-lore §5.2 #51–53): **Khordurn** `{Neutral: 0.60, Lawful: 0.30, Chaotic: 0.10}` (the orderly vault-kingdoms); **Gormdurn** `{Neutral: 0.60, Chaotic: 0.30, Lawful: 0.10}` (the volcanic fire-cult, human sacrifice); **Khraaldurn** `{Neutral: 0.80, Lawful: 0.10, Chaotic: 0.10}` (the withdrawn frost-holds). **The three elf branches each lean differently** (setting-lore §5.2 #48–50): the high-elven **Aelvaneth** are predominantly Lawful — `weights: {Lawful: 0.70, Neutral: 0.20, Chaotic: 0.10}` (the law-bound star-courts); the sea-elven **Thalvaneth** are predominantly Neutral — `weights: {Lawful: 0.20, Neutral: 0.60, Chaotic: 0.20}` (the worldly, trade-minded coast); and the jungle **Xilvaneth** (the setting's nearest 'dark-elf' analog — harsh of tongue and cruel of custom) are overwhelmingly Chaotic — `weights: {Lawful: 0.10, Neutral: 0.10, Chaotic: 0.80}`.
- **Seed-point cap.** Up to **3 seed points per race per campaign** (≤3 elf homelands + ≤3 dwarf homelands), versus ~10 for humans (§6.1).
- **Lifecycle (the arc).** Author **high `peak_strength`** and **high `collapse_proneness`** with `end_state: "enclave"`. During their golden age `expansion.aggression` is **high** (elf and dwarf both strong; elves somewhat slower expanders, dwarves stronger domain-builders); the hard collapse, not a low growth rate, is what leaves them as scattered enclaves by game-start. Their fallen realms are prime sources of ruins and dungeons for the history log.
- **Conquest (biome- and race-conditional).** In their strong years demihumans behave very differently by target, expressed through `conquest.modifiers`:
  - vs **humans inside the demihuman's own seed biome** → **genocide** (`when: target_in_my_seed_biome → set ≈ 0.9`): they cleanse their sacred forests/mountains.
  - vs **humans outside their seed biome** → **vassalize** (this is the low `base_subjugation_vs_genocide ≈ 0.2`): they rule, but do not absorb, lands they don't consider theirs.
  - vs **other demihumans** → **always genocide** (`when: target_is_demihuman → set ≈ 1.0`), softened slightly for kinship (`when: target_same_alignment → adjust ≈ −0.2`). Elf-and-dwarf (and rival same-race polities) compete for the same scarce biomes and exterminate rather than absorb one another.
- **Post-collapse handoff.** Once collapsed to enclaves, the surviving demihuman domains hand off at game-start to the ACKS rules, whose slow demihuman growth (elf −2 / dwarf −1 categories) and wilderness placement then **keep them fallen** — the rules reinforce the enclave end-state during play (§8.3).
- **Count.** Up to 3 seeds per race, each an instance assigned an alignment from the allowed set per §4.2; the same race may appear at more than one seed with different alignments (a Lawful dwarf-hold and a Chaotic dwarf-hold can coexist and, per the rule above, war to mutual extermination).
- **Halflings:** no standalone culture. Halflings adopt the regional human culture per ACKS convention (carried over from the superseded GDD §11.2).

### 5.3 Beastman tier (stripped)

Beastmen (`tier: "beastman"`: orc, goblin, gnoll, etc.) use a **reduced** schema: `identity`, `expansion` (for clanhold spread), `preferred_troop_types`/tribal-warrior availability, `personality_weight_biases`, `name_bank_key`, and `flavor_text` only. They have **no** `rulership.sphere_weights`, `conquest`, `road_propensity`, `architecture`, or `religion_hooks` — setting-lore §5.1 states no human culture maps to them and they are too degenerate for the full model. Their demographics, placement, and population caps come entirely from `ax_domains_of_chaos.xml` (always wilderness; ≤125 families per 6-mile hex; ≤2,000 per 24-mile hex; per-race clanhold demographics table) and are not re-authored here. Beastman records exist to drive NPC generation in clanhold encounters and the beastman repopulation outcome of polity collapse (`gdd-history-simulation.md`, future). NAMING/FLAVOR for beastmen now lives in a dedicated conlang kit (`data/conlang/family_beastman.json` "Kazhur" + 10 race kits: kobold/goblin/orc/hobgoblin/gnoll/troll/bugbear/troglodyte/lizardman/ogre): a harsh Old-Semitic sorcerer-tongue regressed per race into bestial sounds, with Chaotic totemic-shamanist flavor (race-totems; the Chaotic powers as Gul- prefixed morphs). This is the `name_bank_key` source and runtime naming/flavor ONLY — it does NOT add `religion_hooks` or any other mechanical field to the stripped beastman schema above.

---

## 6. Selection and Placement (per campaign)

Runs as the rewritten **Layer 4** of `gdd-setting-generation.md`, after geography (Layer 1–2) and the initial political seeding, and feeds the history simulation that replaces the static Voronoi/diffusion of the old §6.2/§7.1.

### 6.1 Seed points (how many, of what)

Selection works in **seed points** — starting homeland/origin clusters from which the history sim grows a culture and its first polity. One seed point = one homeland assigned one culture; two human seed points may carry different cultures (preferred, for variety) or, less often, the same culture in two places.

- **Human seed points:** up to **~10**, scaled to map size (provisional, tunable): Small 3–4, Medium 5–7, Large 8–10, Huge 10–12. The distinct human-culture count is ≤ the seed-point count.
- **Demihuman seed points:** up to **3 per race** (≤3 elf + ≤3 dwarf), gated on suitable seed biomes existing (forest/jungle for elves, hills/mountains for dwarves). Each is assigned an alignment from the all-three allowed set per §4.2; same-race seeds may differ in alignment.
- **Beastmen** are not "selected" here — they populate wilderness per the `ax_domains_of_chaos.xml` tables and, post-collapse, repopulate depopulated regions (history sim).

The demihuman seed-point cap (3/race) is much tighter than humans' (~10) by design — even at their golden-age peak, demihumans are fewer origin-points than humanity; their early *strength* comes from `lifecycle.peak_strength` and high in-biome aggression, not from numerous seeds.

### 6.2 Biome-coverage constraint satisfaction

Selection is a constraint-satisfaction draw, not a free random pick:

```
1. Read the generated map's biome histogram and coastline.
2. Build the candidate pool = all human cultures whose seed_biomes are
   present on the map in sufficient quantity, respecting coastal_start
   (a 'Y' culture needs a coastal homeland; 'N' needs inland; 'E' either).
3. Draw the target count from the pool, maximizing biome coverage
   (prefer adding a culture whose seed biomes are not yet represented)
   and respecting the phonemic-adjacency rule (§6.4).
4. If the map lacks a biome no candidate covers, that's fine — not every
   culture appears every campaign (this is the intended variety source).
```

### 6.3 Homeland placement — the universal wilderness-seeding model

Each seed point is placed as a small homeland cluster on **wilderness** hexes matching the culture's `seed_biomes` (and coastal flag), maximally separated from other homelands, biased toward productive terrain near water. **All** cultures — human and demihuman alike — seed in wilderness; this mirrors ACKS, where founding an independent realm (without a liege) requires uninhabited wilderness or borderlands (§8.3).

The crucial implication: at seed-time the map is **sparse wilderness dotted with culture origin-points.** Polities, vassal domains, cities, roads, and territory classification (civilized/borderlands) do **not** exist yet — they **emerge through expansion** in the history simulation as each culture grows outward from its seed, spawns vassal domains, and founds settlements. The rich political map is the *output* of the sim, not the seeding step.

### 6.4 Phonemic-adjacency constraint

No two cultures with the same or near-identical `phonemic_palette` may be placed in adjacent homelands, so neighboring peoples sound distinct (carried from `gdd-name-generation.md` §4.1). If the draw violates this, re-draw the offending culture.

### 6.5 Seeded jitter

After selection, apply per-campaign jitter to each selected culture's mechanical scalars (§7). Jitter is applied to the *campaign instance* of the culture, never written back to the canonical file.

### 6.6 Name banks are static assets

Because canonical cultures are stable across campaigns, each one's name bank (`gdd-name-generation.md`) is **authored once** and shipped as static data, keyed by `name_bank_key` — not generated per campaign. This is a significant simplification of the name-generation GDD, which currently assumes per-campaign banks for LLM-invented cultures; that GDD should be revised to reflect static canonical banks (follow-on, noted in §12). Geographic-feature and region names (rivers, ranges, fallen-polity toponyms) draw from these same banks plus the history log (§2 principle 8).

---

## 7. Per-Campaign Variation (what jitters, and bounds)

Variety comes from four sources, in rough order of impact: **(1) which cultures are drawn** (§6.2), **(2) where they are placed** (§6.3), **(3) which alignment each takes** (§4.2), and **(4) seeded numeric jitter**, the smallest. Jitter rules:

```
For each mechanical scalar s in {aggression, defense, rigidity,
                                 subjugation_vs_genocide, road_propensity}:
    s_campaign = clamp01( s_canon + uniform(-JITTER, +JITTER) )     # JITTER ≈ 0.08

sphere_weights: add uniform(-0.05, +0.05) to each, then renormalize to 1.0.

size_exponent_bias, personality biases: jitter at half magnitude or not at all.
identity, alignment.allowed, seed_biomes, civ_or_clan, synthesis_sources: NEVER jitter.
```

Jitter magnitude is a single global constant so balance stays predictable. The intent: a culture is always recognizably itself, with enough run-to-run texture that two campaigns featuring the Agrippans don't feel identical.

---

## 8. ACKS Constraints

The simulation that consumes this catalog is project-designed (§1.2), but its **inputs and present-day outputs** must satisfy ACKS. These come from the sourcebooks and must be respected.

### 8.1 Present-day handoff to the domain system

At game-start the simulation stops and every surviving polity becomes an ACKS domain/realm governed by the **real** rules in `acore_axioms_strongholds_and_domains.xml`. The catalog's `alignment` and `conquest` outputs must produce states those rules can represent:

- A ruler whose alignment mismatches the domain's population takes **base morale −1** (Neutral ruler in a L/C domain, or L/C ruler in a Neutral domain) or **−2** (Lawful ruler in a Chaotic domain or vice-versa). *(`acore_axioms_strongholds_and_domains.xml`, morale modifiers.)* An unassimilated conquered province (low `subjugation_vs_genocide`, §4.4) therefore correctly arrives as a hard-to-hold domain.
- A domain whose **religion** differs in alignment from a recently-imposed one suffers **−4 on the first month's morale roll, then −2 ongoing** until the old faith is restored or the domain converts. *(Same file.)* The catalog's religion hooks (§3.2) must leave conquered hexes in states consistent with this.
- Territory classification carries base morale penalties — **Borderlands −1, Wilderness −2** *(same file)* — so the catalog's expansion outputs must not, e.g., leave a "civilized" Agrippan core that the density rules would classify as wilderness.

The catalog does **not** re-implement morale; it ensures the worlds it helps build are ones the morale system accepts.

### 8.2 Population density and territory classification

Generated realm populations and territory classes must satisfy `acore-setting-construction-rules.xml`: a default settled region runs **~50 people per square mile = ~300 families per 6-mile hex = ~5,000 families per 24-mile hex**, and a healthy principality-scale regional map leaves **~50% of the map as unsettled wilderness**; unsettled hexes with no inhabitants and no garrison do not count toward density. Culture `aggression`/`road_propensity` tuning must not produce fully-settled maps with no wilderness — wilderness is required for the borderlands-structure play the rules assume (border forts, dungeons beyond the forts, rising danger deeper in — `acore-setting-construction-rules.xml`).

### 8.3 Demihuman caps (RESOLVED — cited 2026-06-03)

Lookup complete. Demihuman domains are bounded not by a lower per-hex population ceiling but by **slow growth and an own-race rule** — plus the wilderness-founding requirement they **share with humans** (below). All from `acore_axioms_strongholds_and_domains.xml` unless noted:

- **Placement (domain classification):** "Elven fastnesses and dwarven vaults may only be built in wilderness areas or civilized/borderlands areas of their own race." This is **not** a demihuman-specific penalty. It is the game-time expression of two facts: (a) founding an *independent* realm requires uninhabited wilderness for **everyone** — humans equally must claim wilderness/borderlands to found a realm without a liege, since civilized land needs a grant in exchange for fealty (same file, acquisition methods; "Explorers may only build strongholds in borderlands or wilderness domains"); and (b) demihumans **won't migrate in numbers to be ruled by a foreign liege**, so a demihuman cannot inherit a human domain and convert it to an elven/dwarven realm — demihuman realms grow only by their **own-race expansion** into new wilderness fastnesses/vaults. All seed points (human and demihuman) start in wilderness — see the universal seeding model (§6.3).
- **Per-hex population maximums are identical to humans** (limits-of-growth table): Wilderness 125, Borderlands 250, Civilized 780 families per 6-mile hex (and 8 / 15 / 50 per 1.5-mile hex). Demihumans have **no** lower per-hex cap.
- **Growth-rate throttle (domain-growth, racial modifiers):** "Elven domains increase as if two population categories larger; Dwarven domains increase as if one population category larger." Against the active-adventuring growth table (1–100 pop → +5d20, scaling down to 500+ → +1d10), this makes elves grow far slower than humans and dwarves intermediate. Slow growth + wilderness start = realms that stay small and sparse — the *de facto* cap.
- **Classification advancement is hard** (classification-advancement): reaching borderlands requires every 6-mile hex at 125 families across 16 hexes (2,000 total) or an urban settlement of ≥20% urban families with blocked expansion, etc. Demihumans climb this ladder slowly because of the growth throttle.
- **Name-level strongholds** (`acore_demihuman_classes.xml`, vault/fastness establishment, level 9): a Dwarven Vaultguard builds an underground vault — clan dwarves settle first, then other clans come to be ruled — and an elf establishes a forest/glen fastness; each draws **3d6×10 first-level same-race** settler-defenders at no cost.
- **Own-race rule** (same file): demihuman rulers employ only same-race soldiers (other races may be hired for non-military tasks), and their realms are peopled by their own kind, who will not come in numbers under a foreign liege. Consequence for the sim: a demihuman conquest of a human province imposes **governance** (vassalage) — the province stays human — whereas to people a biome with their own kind they must first **clear** it (the in-biome genocide of §5.2). This is what the conquest modifiers encode.

**Deliberate divergence from ACKS flavor.** ACKS's default assumption (Tolkien-style) is that elves and dwarves are a perpetually-declining elder race while the age of Men ascends. **Arbiter diverges:** in the history sim the demihumans **start strong and ascendant, then collapse hard** into enclaves (§5.2). The ACKS caps above therefore describe the demihuman **present-day end-state**, not their historical trajectory — they are what's left *after* the fall.

The two layers reconcile cleanly: the history sim is project-designed and does not run ACKS monthly domain growth, so demihumans can be powerful golden-age expanders within it (high `lifecycle.peak_strength`, high in-biome `expansion.aggression`); at game-start the surviving enclaves hand off to the ACKS rules, whose slow demihuman growth (elf −2 / dwarf −1 categories) and wilderness-placement restriction then **lock the survivors into decline during play** — the rules enforce "they cannot recover," which is exactly the enclave feel we want. **Authoring consequence:** set demihuman golden-age aggression **high** (not low), `lifecycle.collapse_proneness` **high**, `end_state` `"enclave"`, and conquest via the biome/race-conditional modifiers of §5.2 — never a flat low scalar.

### 8.4 Beastman demographics

Beastman placement and caps are entirely governed by `ax_domains_of_chaos.xml` (clanholds always wilderness; ≤125 peasant families per 6-mile hex; ≤2,000 per 24-mile hex; one warrior + noncombatants per family; ogre/troll families count as 4; per-race clanhold demographics table) and the beastman tier (§5.3) does not override them.

---

## 9. Worked Examples

Three records illustrating the full schema across the range: a settled lawful civ, a harsh-terrain clan, and a multi-source synthesis. **All numeric values below are provisional/illustrative, pending balance tuning** — they demonstrate the schema and the relationships among fields, not final figures.

### 9.1 Agrippan (catalog #1 — Roman analog, civ, Lawful-leaning)

```json
{
  "schema_version": 1,
  "mechanical": {
    "identity": { "culture_id": "agrippan", "catalog_number": 1, "demonym": "Agrippan", "toponym": "Agrippa",
      "tier": "human", "race": "human", "civ_or_clan": "civ", "synthesis_sources": [1] },
    "alignment": { "allowed": ["Lawful", "Neutral"], "rigidity": 0.8 },
    "terrain": { "seed_biomes": ["grassland", "scrubland", "hills"], "affinity_secondary": ["forest"],
      "avoided": ["tundra", "glacial_mountains"], "coastal_start": "Y" },
    "expansion": { "aggression": 0.7, "defense": 0.7, "size_exponent_bias": 0.0 },
    "conquest": { "base_subjugation_vs_genocide": 0.25, "modifiers": [] },
    "lifecycle": { "peak_strength": 0.6, "collapse_proneness": 0.4, "end_state": "enduring" },
    "infrastructure": { "road_propensity": 0.95 },
    "rulership": {
      "sphere_weights": { "military": 0.45, "mercantile": 0.25, "religious": 0.20, "arcane": 0.10 },
      "preferred_troop_types": ["heavy_infantry", "light_infantry", "archers"] },
    "npc": { "personality_weight_biases": "see gdd-npc-personality.md §3.2 — societal_orthodoxy +1.5, self_interest +0.5, in_group_loyalty +1.0, civility +0.5, stress_reactivity -0.5" }
  },
  "flavor": {
    "name_bank_key": "agrippan", "phonemic_palette": "Latinate; hard c/t, -us/-a/-um endings, penultimate stress",
    "phenotype_notes": "Mediterranean; olive skin, dark hair, medium stature",
    "language": { "language_name": "Agrippan", "language_family": "Old Imperial", "script": "own_script" },
    "social_structure": "imperial_bureaucracy",
    "values": { "core_values": ["law", "duty", "glory"], "taboos": ["betraying an oath", "desertion"], "attitude_toward_outsiders": "tolerant" },
    "magic_attitude": { "arcane": "regulated", "divine": "central", "notes": "State augury respected; freelance sorcery licensed and watched" },
    "architecture_style": { "primary_material": "stone", "aesthetic": "monumental", "signature_feature": "arched aqueducts and forums" },
    "religion_hooks": { "alignment_lens": "resolved per chosen alignment (setting-lore §4.2)", "local_saint_slots": 4,
      "patron_powers": ["justice", "war", "trade"] },
    "flavor_text": { "one_line": "Road-builders and law-givers who bind conquered peoples with citizenship rather than chains.",
      "one_paragraph": "..." }
  }
}
```

Reading the record: high `road_propensity` (0.95) + civ gives a dense named-highway lattice (§4.6); low `base_subjugation_vs_genocide` (0.25, no modifiers) means Agrippa absorbs by **governance and citizenship**, leaving conquered cultures largely intact (§4.4) — which, at game-start, yields multi-ethnic provinces carrying ACKS alignment-mismatch morale tension (§8.1). `military`-led sphere weights with mercantile/religious support produce mostly fighter rulers with magistrate-priest courts (§4.3). Its allowed set [Lawful, Neutral] is an **even 50/50** split (no `weights`, §4.2), so an Agrippa is equally likely to start Lawful or Neutral; high `rigidity` (0.8) means it fragments politically on collapse but rarely abandons whichever alignment it began with (§4.5).

### 9.2 Vargari (catalog #10 — Norse analog, clan, cold-frontier)

```json
{
  "schema_version": 1,
  "mechanical": {
    "identity": { "culture_id": "vargari", "catalog_number": 10, "demonym": "Vargari", "toponym": "Vargarheim",
      "tier": "human", "race": "human", "civ_or_clan": "clan", "synthesis_sources": [8] },
    "alignment": { "allowed": ["Neutral", "Chaotic"], "rigidity": 0.45 },
    "terrain": { "seed_biomes": ["tundra", "taiga", "grassland", "mountains", "glacial_mountains"],
      "affinity_secondary": ["hills"], "avoided": ["desert", "jungle"], "coastal_start": "Y" },
    "expansion": { "aggression": 0.85, "defense": 0.5, "size_exponent_bias": 0.1 },
    "conquest": { "base_subjugation_vs_genocide": 0.6, "modifiers": [] },
    "lifecycle": { "peak_strength": 0.7, "collapse_proneness": 0.6, "end_state": "enduring" },
    "infrastructure": { "road_propensity": 0.2 },
    "rulership": {
      "sphere_weights": { "military": 0.6, "mercantile": 0.2, "religious": 0.15, "arcane": 0.05 },
      "preferred_troop_types": ["heavy_infantry", "berserkers", "marines"] },
    "npc": { "personality_weight_biases": "stress_reactivity +1.0, in_group_loyalty +1.0, civility -1.0, affective_compassion -0.5, epicureanism -0.5" }
  },
  "flavor": {
    "name_bank_key": "vargari", "phonemic_palette": "Norse; thorn/eth, -r/-vid/-heim endings, initial stress",
    "phenotype_notes": "Northern; fair/ruddy skin, light hair common, tall",
    "language": { "language_name": "Vargic", "language_family": "Thanic", "script": "own_script" },
    "social_structure": "clan_confederation",
    "values": { "core_values": ["strength", "freedom", "glory"], "taboos": ["cowardice in battle", "kinslaying"], "attitude_toward_outsiders": "wary" },
    "magic_attitude": { "arcane": "feared", "divine": "respected", "notes": "Seers honored; wandering sorcerers distrusted" },
    "architecture_style": { "primary_material": "timber", "aesthetic": "fortified", "signature_feature": "longhouses and carved mead-halls" },
    "religion_hooks": { "alignment_lens": "resolved per chosen alignment", "local_saint_slots": 5,
      "patron_powers": ["sea", "war", "storms"] },
    "flavor_text": { "one_line": "Sea-raiders of the frozen coasts who measure a life by the saga it leaves.",
      "one_paragraph": "..." }
  }
}
```

Reading the record: high `aggression` (0.85) but modest `defense` (0.5) and a positive `size_exponent_bias` (0.1) makes the Vargari **explosive early expanders that overreach** — exactly the profile that feeds dramatic rise-and-collapse histories. `road_propensity` 0.2 + clan leaves them roadless raiders. Low `rigidity` (0.45) + a Neutral/Chaotic allowed set means a collapsing Vargari realm can readily slide into Chaos. Mid-high `base_subjugation_vs_genocide` (0.6): raiders impose themselves more than Agrippa does. High `local_saint_slots` (5) reflects that a Neutral-leaning Vargari prays chiefly to ancestral saga-heroes (§3.4).

### 9.3 Shidhean (catalog #29 — Celtic + Japanese synthesis, clan)

```json
{
  "schema_version": 1,
  "mechanical": {
    "identity": { "culture_id": "shidhean", "catalog_number": 29, "demonym": "Shidhean", "toponym": "Shidhe-Kyo",
      "tier": "human", "race": "human", "civ_or_clan": "clan", "synthesis_sources": [7, 10] },
    "alignment": { "allowed": ["Lawful", "Chaotic"], "rigidity": 0.7 },
    "terrain": { "seed_biomes": ["forest", "hills", "mountains"], "affinity_secondary": ["dense_forest"],
      "avoided": ["desert", "scrubland"], "coastal_start": "E" },
    "expansion": { "aggression": 0.55, "defense": 0.8, "size_exponent_bias": -0.05 },
    "conquest": { "base_subjugation_vs_genocide": 0.4, "modifiers": [] },
    "lifecycle": { "peak_strength": 0.4, "collapse_proneness": 0.35, "end_state": "enduring" },
    "infrastructure": { "road_propensity": 0.4 },
    "rulership": {
      "sphere_weights": { "military": 0.4, "mercantile": 0.1, "religious": 0.3, "arcane": 0.2 },
      "preferred_troop_types": ["light_infantry", "archers", "light_cavalry"] },
    "npc": { "personality_weight_biases": "societal_orthodoxy +1.0, self_interest +0.5, civility +1.0, expressiveness -1.0" }
  },
  "flavor": {
    "name_bank_key": "shidhean",
    "phonemic_palette": "AUTHORED BLEND of Celtic + Japanese: Celtic lenition and -dh/-gh clusters fused with Japanese open CV syllables and vowel runs (e.g. 'Shidhe', 'Aodhka', 'Rhynjo')",
    "phenotype_notes": "BLEND RULE per setting-lore §5.3: Celtic hair (blonde/red), light eyes, and Celtic stature; Japanese skin tone, epicanthic folds, and broader/flatter facial structure. EXCLUDE the inverse (Japanese hair/eyes/stature + Celtic facial structure).",
    "language": { "language_name": "Shidhe", "language_family": "Sylvan-Thanic creole", "script": "own_script" },
    "social_structure": "clan_confederation",
    "values": { "core_values": ["honor", "tradition", "cunning"], "taboos": ["dishonoring an ancestor", "breaking guest-right"], "attitude_toward_outsiders": "wary" },
    "magic_attitude": { "arcane": "revered", "divine": "respected", "notes": "Spirit-magic woven into clan rites" },
    "architecture_style": { "primary_material": "living_wood", "aesthetic": "elegant", "signature_feature": "shrine-gates and timber halls grown into the forest" },
    "religion_hooks": { "alignment_lens": "resolved per chosen alignment", "local_saint_slots": 3,
      "patron_powers": ["night", "knowledge", "nature"] },
    "flavor_text": { "one_line": "Forest-clan duelists bound by ancestor-honor and woven spirit-rites.",
      "one_paragraph": "..." }
  }
}
```

Reading the record: low `aggression` (0.55) with high `defense` (0.8) and negative `size_exponent_bias` makes the Shidheans **tenacious defenders, slow expanders** — survivors rather than conquerors. The `synthesis_sources` [7,10] drive the explicitly authored blended palette and the §5.3 phenotype blend rule, with the inverse excluded (§4.8). Note the Lawful/Chaotic allowed set with **no Neutral** — a Shidhean collapse drift can only swing between Law and Chaos (§4.5), a sharply bimodal culture. `local_saint_slots` 3 (no Neutral): saints are intercessors beneath the great gods, not the primary objects of worship.

### 9.4 Sylvan Elf (demihuman tier — illustrative; id/names provisional pending demihuman authoring)

Demonstrates the demihuman arc and the conditional conquest model. Numbers illustrative.

```json
{
  "schema_version": 1,
  "mechanical": {
    "identity": { "culture_id": "elf_sylvan", "catalog_number": null, "demonym": "Sylvan", "toponym": "Sylvanost",
      "tier": "demihuman", "race": "elf", "civ_or_clan": "civ", "synthesis_sources": [] },
    "alignment": { "allowed": ["Lawful", "Chaotic", "Neutral"], "weights": { "Lawful": 0.40, "Chaotic": 0.40, "Neutral": 0.20 }, "rigidity": 0.85 },
    "terrain": { "seed_biomes": ["forest", "jungle"], "affinity_secondary": ["dense_forest"],
      "avoided": ["desert", "scrubland", "tundra"], "coastal_start": "E" },
    "expansion": { "aggression": 0.8, "defense": 0.9, "size_exponent_bias": 0.0 },
    "conquest": {
      "base_subjugation_vs_genocide": 0.2,
      "modifiers": [
        { "when": "target_in_my_seed_biome", "set": 0.9 },
        { "when": "target_is_demihuman", "set": 1.0 },
        { "when": "target_same_alignment", "adjust": -0.2 }
      ]
    },
    "lifecycle": { "peak_strength": 0.9, "collapse_proneness": 0.85, "end_state": "enclave" },
    "infrastructure": { "road_propensity": 0.3 },
    "rulership": {
      "sphere_weights": { "military": 0.30, "mercantile": 0.10, "religious": 0.25, "arcane": 0.35 },
      "preferred_troop_types": ["archers", "light_infantry", "light_cavalry"] },
    "npc": { "personality_weight_biases": "stress_reactivity -1.5, epistemic_curiosity +1.0, societal_orthodoxy +0.5, expressiveness -0.5" }
  },
  "flavor": {
    "name_bank_key": "elf_sylvan", "phonemic_palette": "flowing vowels, soft l/r/n/th, long names (name-gen §6)",
    "phenotype_notes": "tall, slender, fair — per demihuman art canon",
    "language": { "language_name": "Sylvan", "language_family": "Elvish", "script": "own_script" },
    "social_structure": "caste",
    "values": { "core_values": ["tradition", "beauty", "knowledge"], "taboos": ["defiling the wood", "suffering a dwarf in the forest"], "attitude_toward_outsiders": "xenophobic" },
    "magic_attitude": { "arcane": "revered", "divine": "respected", "notes": "Arcane mastery is the elven birthright" },
    "architecture_style": { "primary_material": "living_wood", "aesthetic": "elegant", "signature_feature": "halls grown from living trees" },
    "religion_hooks": { "alignment_lens": "resolved per chosen alignment (PROVISIONAL, §3.4)", "local_saint_slots": 5,
      "patron_powers": ["nature", "knowledge", "night"] },
    "flavor_text": { "one_line": "Ancient forest-lords of a fallen golden age, jealous now of every last glade.",
      "one_paragraph": "..." }
  }
}
```

Reading the record: high `lifecycle.peak_strength` (0.9) + high in-biome `aggression` (0.8) make the Sylvans **dominant forest powers in deep history**; high `collapse_proneness` (0.85) with `end_state: "enclave"` brings them down hard to the scattered, defensive wood-realms of the present day (§5.2, §8.3) — and their fallen realms seed ruins and dungeons. The `conquest.modifiers` are the heart of the demihuman behavior: base **0.2** *vassalizes* humans conquered outside the forest, `target_in_my_seed_biome → 0.9` *cleanses* humans from woods they want for their own kind, and `target_is_demihuman → 1.0` (softened −0.2 when same alignment) means they *exterminate* rival elves and any dwarf alike — note the taboo "suffering a dwarf in the forest." Very high `defense` (0.9) makes the survivors nearly impossible to dig out of their last fastnesses. All three alignments are open but split **equally Law/Chaos with Neutral a 20% minority** (explicit `weights`, §4.2) — a pulled-to-the-poles people; `rigidity` 0.85 means a collapsing Sylvan realm rarely abandons whichever pole it holds.

---

## 10. Authoring Plan

The schema, derivations, and three worked records above are the reviewable deliverable. Filling the catalog is a separate, batched content pass to keep quality high:

1. **Resolve §8.3** — look up and cite demihuman domain/population caps before any demihuman authoring.
2. **Human batch A (single-source civ cultures)** — author the straightforward Roman/Greek/Egyptian/etc. records first; they calibrate the scalar ranges.
3. **Human batch B (single-source clan cultures)** — nomads, raiders, forest tribes.
4. **Human batch C (multi-source synthesis cultures)** — the hardest, each needs an authored blended palette + phenotype rule (§4.8); do after A/B set the baselines.
5. **Demihuman tier** — elf/dwarf records within the §8.3 caps.
6. **Beastman tier** — stripped records (§5.3), demographics deferred to `ax_domains_of_chaos.xml`.
7. **Static name banks** (§6.6) — one per authored culture, per `gdd-name-generation.md` element inventory.
8. **Balance pass** — sweep all scalars together once the set is complete; the §9 numbers are provisional until this.

Each batch is validated (§11) before the next begins.

## 11. Validation Rules

Per record, programmatically:

```
- culture_id unique, snake_case; catalog_number matches setting-lore §5.2 (human tier)
- identity/alignment.allowed/seed_biomes/civ_or_clan/synthesis_sources match setting-lore §5.2 exactly (human tier)
- all scalars in [0.0, 1.0]; size_exponent_bias in [-0.2, +0.2]
- alignment.allowed is a non-empty subset of {Lawful, Neutral, Chaotic}, no duplicates
- if alignment.weights present: keys exactly match the allowed members and sum to 1.0 (±0.01)
- sphere_weights are non-negative and normalize to 1.0 (±0.01)
- preferred_troop_types: 2–4 entries, all valid enum, all ACKS-fieldable for the culture's terrain/tech
- seed_biomes are valid gdd-terrain-system.md tags; coastal_start in {Y,N,E}
- personality_weight_biases conform to gdd-npc-personality.md §3.2 (flat twelve-axis mean-shift map; each axis a mean-shift in [-2.0,+2.0]; no temperament/social_style/moral_compass/motivation sub-objects)
- core_values: exactly 3 from the values enum; taboos 1–3
- flavor char limits respected; name_bank_key references an existing bank
- multi-source records (|synthesis_sources|>1): phonemic_palette and phenotype_notes are authored blends, and phenotype_notes states an explicit blend rule
- demihuman records: expansion scalars consistent with the §8.3 caps (once resolved)
- beastman records: reduced schema only; no rulership/conquest/road/architecture/religion fields present
```

Cross-record:

```
- no two selected-adjacent cultures share a phonemic_palette (enforced at placement, §6.4)
- the catalog covers enough biome×alignment combinations that any reasonable map can be populated (variety baseline)
```

## 12. Open Questions / Deferred

- **Demihuman domain/population caps** — ✅ RESOLVED 2026-06-03 (§8.3), cited from `acore_axioms_strongholds_and_domains.xml` + `acore_demihuman_classes.xml`. Demihuman authoring is now unblocked.
- **Religion-system rework (catalog religion fields are PROVISIONAL)** — the shared-pantheon model (setting-lore §4) needs its own GDD to replace `gdd-cultural-religious-generation.md` §3/§4. It owns: per-portfolio assignment of the **distinct** Lawful and Chaotic beings and their nemesis relationships (the §4.1 inversion is *aggregate*, not a 1:1 pairing), **per-culture canonical deity names**, and **cultural holy symbols**. The religion fields here (§3.2 `religion_hooks`, §3.4 `patron_powers`) store concept-level hooks only and will be revisited/superseded when that GDD lands.
- **`gdd-name-generation.md` revision** — to reflect static canonical name banks (§6.6) rather than per-campaign LLM banks.
- **`gdd-setting-generation.md` Layer 4 rewrite** — replace static culture diffusion (§7.1) and Voronoi borders (§6.2) with selection (§6) + the history simulation.
- **`gdd-history-simulation.md`** — the project-designed expansion/collapse sim that consumes this catalog's expansion/conquest/rigidity fields; owns the size-exponent and size+age stability curves, rump/successor logic, and depopulation→wilderness→beastman outcomes.
- **`gdd-region-painting.md`** — consumes `road_propensity` (major-road naming) and the `toponym` roots (fallen-polity region names).
- **setting-lore §5 slimming** — once this catalog is approved, reduce setting-lore §5.2/§5.3 to a pointer here (pending Jedidiah's go-ahead to edit setting-lore).
- **Balance** — all §9 scalar values are provisional pending the §10.8 balance pass.

## 13. Revision History

- **2026-06-08:** Updated `personality_weight_biases` to the reworked twelve-axis schema in `gdd-npc-personality.md` §3.2. The record-schema description (§3.x), the four worked culture examples (Agrippan, Vargari, Shidhean, Sylvan Elf `npc` blocks), and the §10 validation rule were converted from the retired four-axis tag vocabulary (`+duty/+honor/-nervous/-serene/-aggressive/-formal/-blunt/-gregarious/+cunning`, modifiers −0.3..+0.3 summing to ~0) to flat twelve-axis mean-shifts in [−2.0, +2.0] (e.g. `societal_orthodoxy`, `stress_reactivity`, `in_group_loyalty`, `civility`, `expressiveness`). No mechanical-core or canonical-identity fields changed.
- **2026-06-03 (rev 6):** Per Jedidiah, the setting-lore §5.2 alignment lists are **not ranked** — human cultures take an **even/uniform split** across the alignments in their row (§4.2 default rewritten). `alignment.weights` is now the explicit override for cultures that lean; dwarves moved onto an explicit weight `{Neutral 0.50, Lawful 0.30, Chaotic 0.20}` accordingly (§3.1, §4.2, §5.2, §9.1 worked example).
- **2026-06-03 (rev 5):** Demihuman alignment spreads set per Jedidiah: dwarves preference Neutral (default list-order weighting, allowed [Neutral, Lawful, Chaotic]); elves split equally Lawful/Chaotic with Neutral 20%, via a new optional `alignment.weights` override (§3.1, §4.2, §5.2, §9.4, §11).
- **2026-06-03 (rev 4):** Corrected per Jedidiah's notes. (1) Reframed the Lawful/Chaotic pantheons as **distinct beings** whose inversion is *aggregate* not 1:1 — nemeses where provenance overlaps, enemies throughout (§3.4); religion fields (§3.2/§3.4) marked **provisional** pending the religion rework, which will own per-culture canonical deity names and holy symbols (§12). (2) Reframed wilderness-start as the **universal** seeding model — all cultures seed in wilderness and grow polities/cities/vassals by expansion; the ACKS "own-race" rule is a game-time constraint on demihumans converting human domains, not a special founding penalty (§6.3, §8.3, §5.2). (3) Conformed all worked examples to the new conquest/lifecycle schema and concept-based `patron_powers`; swapped Vargari/Shidhean saint counts to match the Neutral-prominence rule; added a Sylvan Elf worked example (§9.4) demonstrating conditional conquest and the golden-age→enclave arc.
- **2026-06-03 (rev 3):** Demihuman golden-age→collapse arc (high `peak_strength`/`collapse_proneness`, `end_state: enclave`) diverging from ACKS decline flavor; elf seed forest+jungle, dwarf hills+mountains; all three alignments open; ≤3 seeds/race vs ~10 human seed points; biome/race-conditional conquest via generalized `conquest.modifiers`; added `lifecycle` block; Neutral cultures = ancestor/saint worship in `religion_hooks`.
- **2026-06-03 (rev 2):** Resolved demihuman caps (§8.3, §5.2, §12) with citations from `acore_axioms_strongholds_and_domains.xml` (placement restriction, per-hex maximums, growth-rate racial modifiers, classification advancement) and `acore_demihuman_classes.xml` (vault/fastness establishment, own-race soldiery). Demihuman authoring unblocked.
- **2026-06-03:** Initial draft. Established culture-vs-polity separation; mechanical-core/flavor-pack schema; locked design decisions (canonical+jitter, base-scalar+biome-derived expansion, capped demihuman sim participants, fighter-leaning sphere tilt, shared pantheon, historical-only cultural toponyms). Derivation rules for expansion, alignment selection, sphere→ruler bias, conquest assimilation, alignment rigidity, road propensity, civ/clan promotion, authored synthesis. Human/demihuman/beastman tiers. Selection/placement/jitter. ACKS constraints with present-day morale handoff. Three worked records (Agrippan, Vargari, Shidhean). Authoring plan, validation, deferred items.
