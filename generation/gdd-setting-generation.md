# GDD: Setting and World Generation Pipeline

**Authority:** PROJECT-DESIGNED — the generation algorithms are not derived from any ACKS sourcebook. ACKS demographic, economic, and realm-sizing constraints are defined in the XML rules reference library and applied as constraints on the generation output.
**Status:** Draft
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (realm sizing, population density, territory classification, settlement size/market class tables, domain economics that constrain viable realm configurations), `acore_axioms_strongholds_and_domains.xml` (stronghold and domain rules), `ax_domains_of_chaos.xml` (beastman clanhold demographics, geographic distribution by terrain, chaotic domain rules)
**Depends on project GDDs:** `gdd-terrain-system.md` (terrain tag definitions, biome mapping, deforestation rules), `gdd-dungeon-layout.md` (dungeon seed requirements), gdd-calendar-seasons.md(season definitions consumed during narrative generation),gdd-weather-generation.md (downstream consumer of Layer 2 output), , gdd-poi-generation.md (wilderness POI placement in Layer 6, rumor seed output), `gdd-quest-rumor-system.md` (quest generation in Layer 6, rumor seed aggregation)
**Integrates (engine GDDs, 2026-06-03 rework):** `gdd-culture-catalog.md` (Layer 3 culture selection/seeding), `gdd-history-simulation.md` (Layer 4 — replaces the old §6.2 Voronoi borders and §7.1 culture diffusion), `gdd-religion-system.md` (Layer 4 religion overlay), `gdd-region-painting.md` (region pass in Layers 3 & 5). **Supersedes** the LLM-generated-culture model and 1:1 culture-religion seeding of `gdd-cultural-religious-generation.md`.
**Modifiable by Claude Code:** Yes — all algorithms, parameters, and generation logic are engineering decisions.
**Last updated:** 2026-06-03

---

## 1. Purpose

Generate a complete campaign setting from scratch: a 24-mile hex map with physical geography, climate, political entities, cultural groups, demographic distributions, infrastructure, and enough narrative context for the player to understand the world. This is the highest-level generation procedure and produces the data that all downstream systems consume — region zoom-in, settlement stocking, dungeon placement, encounter tables, NPC generation, and domain simulation.

The pipeline runs once at campaign creation and is never re-run. Its output becomes permanent campaign data.

---

## 2. ACKS Constraints

These come from the sourcebooks and MUST be respected. The generation pipeline can produce any world it wants physically, but the demographic and economic layer must satisfy these constraints:

**Realm sizing (ACore Ch.10):**
- Realms have population densities driven by families-per-hex by terrain
- Realm area in hexes corresponds to domain tier (barony → march → county → duchy → principality → kingdom → empire)
- Each tier has a ruler level range (fighters hold domains, higher-level = larger domain)

**Settlement distribution (ACore Ch.10):**
- Number and size of settlements is a function of total realm population
- Market class (I through VI) determined by settlement population
- Formulaic: given population, the number of class I, II, III... settlements is deterministic

**Territory classification:**
- Civilized, borderlands, and wilderness derive from population density and political control
- These classifications drive encounter frequency, movement rules, and lair density

**Domain economics:**
- Domain income, garrison costs, and population growth rates are published tables
- A generated realm must be economically viable — income must cover garrison costs or the realm collapses

---

## 3. Pipeline Overview

Eight layers, run in sequence. Each layer's output constrains the next.

```
Layer 1: Physical Geography ─── heightmap, coastlines, ocean/land
Layer 2: Climate ──────────────── temperature, precipitation, Köppen codes, biomes
Layer 3: Culture Seed + Geometry ─ select & seed canonical cultures in wilderness; paint coarse region shapes
Layer 4: History Simulation ────── grow the world → present-day political map, substrate weights, event log
Layer 5: Name Generation ──────── pre-built name banks per culture, applied to everything
Layer 6: Infrastructure ────────── roads, trade routes, dungeons, lairs, fortifications
Layer 7: LLM Narrative ─────────── history, politics, conflicts, flavor text
Layer 8: Validation & Review ──── mechanical checks, player parameter adjustment, approval
```

**Critical principle:** Each layer is deterministic given its inputs and random seed. The LLM (Layer 7) narrates retroactively — it explains what the generator built, it does not decide what to build. If the generator placed a Chaotic empire in the river valley, the LLM must explain why a Chaotic empire thrives in a river valley. It cannot move the empire or change its alignment. **The historical timeline is likewise *simulated*** in Layer 4, not invented — Layer 7 narrates real logged events (a "Battle of Three Rivers" exists in the narrative because the simulation actually fought it). This supersedes the old §14 "LLM invents the timeline" decision.

---

## 4. Layer 1: Physical Geography

### 4.1 Heightmap Generation

**Tool:** Godot's built-in `FastNoiseLite` class provides Simplex/Perlin noise with fractal octaves (fBm), cellular noise, and value noise. No external libraries needed.

**Procedure:**

```
1. Create a FastNoiseLite instance with the campaign seed
2. Set noise type: TYPE_SIMPLEX_SMOOTH
3. Set fractal type: FRACTAL_FBM
4. Set fractal octaves: 6 (produces good continental-scale detail)
5. Set frequency: 0.003-0.005 (lower = larger landmasses)
6. Sample noise at each hex center position to get raw elevation value (-1.0 to 1.0)
7. Normalize to 0.0-1.0 range
8. Apply continental shaping mask (see §4.2)
9. Apply elevation curve to exaggerate peaks and flatten lowlands (see §4.3)
10. Assign elevation tags per gdd-terrain-system.md §8.1:
    - 0.0–0.3: below sea level (ocean)
    - 0.3–0.55: flat
    - 0.55–0.75: hills
    - 0.75–1.0: mountains
```

### 4.2 Continental Shaping

Raw noise produces scattered islands. To create continent-like landmasses:

**Method: Distance-from-center falloff combined with a second noise layer.**

```
1. Calculate distance of each hex from map center (normalized 0.0 to 1.0)
2. Generate a second FastNoiseLite with different seed (continent_shape_noise)
   - Lower frequency (0.001-0.002) for broad continental shapes
   - Fewer octaves (3-4) for smooth boundaries
3. Blend: final_elevation = terrain_noise * (1.0 - distance_falloff * continent_influence)
                           + continent_shape_noise * continent_influence
4. continent_influence parameter (default 0.4) controls how much the continent shaper
   overrides raw noise. Higher = more defined continents, lower = more scattered islands.
```

**User parameter:** `land_mass_style`
- `"continental"` — large connected landmasses (continent_influence = 0.5, strong center bias)
- `"archipelago"` — scattered islands (continent_influence = 0.2, weak center bias)
- `"pangaea"` — single massive continent (continent_influence = 0.7, very strong center bias)

### 4.3 Elevation Curve

Apply a power curve to the raw heightmap to make mountains rarer and more dramatic:

```
shaped_elevation = pow(raw_elevation, exponent)
```

- `exponent = 1.0` — linear (flat distribution of elevations)
- `exponent = 1.5` — default (mountains occupy less area, lowlands more common)
- `exponent = 2.0` — dramatic (sharp peaks, vast plains)

**User parameter:** `mountain_frequency` (maps to exponent: Low=2.0, Medium=1.5, High=1.0)

### 4.4 Hydrology

**Rivers:**

```
1. Identify local elevation maxima (mountain peaks/ridgelines)
2. For each peak above a threshold, trace a path downhill:
   a. From current hex, move to the lowest adjacent hex
   b. Mark traversed hexes with river water tag
   c. Continue until reaching ocean or a lake
   d. If path reaches a local minimum that isn't ocean, flood-fill to create a lake
      (lake surface elevation = the elevation of the lowest outlet)
3. River width increases downstream: each tributary junction doubles width category
   (stream → creek → river → major river)
```

**Lakes:** Formed when rivers reach inland depressions. The lake fills until it overflows at its lowest rim hex, then continues as a river from there.

**User parameter:** `river_density` — controls the elevation threshold for river sources. Low = few major rivers only. High = many rivers and streams.

### 4.5 Coastline

Hexes with elevation below sea level (0.3 threshold) are ocean. Hexes at the sea level boundary are coastal. Coastal hexes get the `ocean` water tag from `gdd-terrain-system.md`.

**Sea level is a user parameter** (default 0.3). Raising it floods more land. Lowering it exposes more.

### 4.6 Map Size

| Setting Size | Hex Grid (24-mile hexes) | Approximate Area | Suitable For |
|---|---|---|---|
| Small | 15 × 12 (~180 hexes) | ~100,000 sq mi | Single kingdom + borderlands |
| Medium | 25 × 20 (~500 hexes) | ~290,000 sq mi | Multiple kingdoms, varied terrain |
| Large | 40 × 30 (~1,200 hexes) | ~690,000 sq mi | Subcontinental, many realms |
| Huge | 60 × 45 (~2,700 hexes) | ~1,550,000 sq mi | Full continent |

**User parameter:** `map_size` — one of the above presets or custom dimensions.

---

## 5. Layer 2: Climate

### 5.1 Temperature

Derived from latitude (position on the map's north-south axis) and elevation:

```
base_temperature = latitude_curve(hex.y / map_height)
elevation_adjustment = -hex.elevation * lapse_rate
temperature = base_temperature + elevation_adjustment
```

- `latitude_curve`: warmest at the equator (map center or configurable), cooling toward poles
- `lapse_rate`: temperature drop per elevation unit (default ~6.5°C per 1000m equivalent)

**User parameter:** `latitude_range` — determines how much temperature varies north-to-south. "Tropical" = narrow range, "Temperate" = moderate, "Polar" = wide range.

**Latitude range presets (canonical values):**

| latitude_range | South Edge | North Edge | Span |
|---|---|---|---|
| Tropical | 5°N | 20°N | 15° |
| Subtropical | 20°N | 38°N | 18° |
| Temperate | 35°N | 55°N | 20° |
| Continental | 45°N | 65°N | 20° |
| Polar | 60°N | 75°N | 15° |

**User parameter:** `hemisphere` — north (default) or south. Affects season-to-climate mapping per `gdd-calendar-seasons.md` §4.

**Effective latitude per hex** (stored as persistent hex data, consumed by `gdd-weather-generation.md` for dawn/dusk):
```
effective_latitude = map_south_latitude + (hex.y / map_height) * latitude_span
```

### 5.2 Precipitation

Derived from a second noise layer plus geographic modifiers:

```
1. Generate precipitation noise (FastNoiseLite, different seed, frequency ~0.004)
2. Apply rain shadow: hexes downwind of mountains get reduced precipitation
   - Determine prevailing wind direction (configurable, default: west-to-east)
   - For each mountain hex, reduce precipitation in hexes directly downwind
     by 30-60% for 3-5 hexes (rain shadow decay)
3. Apply coastal moisture: hexes within 3 of ocean get +20% precipitation
4. Normalize to 0.0-1.0 range (bone dry to very wet)
```

### 5.3 Köppen Classification

Map each hex to a Köppen code using temperature and precipitation per the standard classification rules. This is a direct algorithmic implementation of the real Köppen system, simplified to the major groups:

```
IF temperature < cold_threshold:
  IF precipitation < dry_threshold: EF (ice cap) → biome: desert
  ELSE: ET (tundra) → biome: clear

ELSE IF precipitation < arid_threshold:
  IF temperature > hot_threshold: BWh (hot desert) → biome: desert
  ELSE: BWk (cold desert) → biome: desert

ELSE IF precipitation < semiarid_threshold:
  IF temperature > hot_threshold: BSh (hot steppe) → biome: clear
  ELSE: BSk (cold steppe) → biome: clear

ELSE IF temperature > tropical_threshold:
  IF precipitation > wet_threshold: Af (tropical rainforest) → biome: jungle
  ELSE IF seasonal_variation > monsoon_threshold: Am (monsoon) → biome: jungle
  ELSE: Aw (tropical savanna) → biome: clear

ELSE IF temperature > temperate_threshold:
  IF summer_dry: Csa/Csb (Mediterranean) → biome: clear
  ELSE: Cfa/Cfb (oceanic/humid) → biome: woods

ELSE: # continental
  Dfa/Dfb/Dfc (continental/subarctic) → biome: woods
```

The exact thresholds are tunable parameters. The biome assignment follows the mapping in `gdd-terrain-system.md` §7.1.

### 5.4 Swamp Placement

After biome assignment, apply swamp conversion:
- Hexes with `woods` or `clear` biome at `flat` elevation adjacent to rivers have a 10-15% chance of becoming `swamp`
- Hexes in tropical zones (`Af`, `Am`) at flat elevation near rivers have a 20% chance of `swamp`
- The swamp chance is configurable

### 5.5 Layer 2 Output

Each hex now has: elevation tag, biome tag, water tags, a Köppen code, and an effective latitude. This feeds directly into `gdd-terrain-system.md` for encounter and movement resolution. After all hexes are assigned, the weather system scans the map to build the **active Köppen set** — the unique codes actually present — and loads only those climate profiles (see `gdd-weather-generation.md` §5.6).

---

## 6. Layer 3: Culture Seeding & Coarse Region Geometry

**This replaces the old static political layer.** Borders, realms, vassal chains, and demographics are no longer drawn here — they are *grown* by the Layer-4 history simulation. Layer 3 only prepares that simulation's inputs and runs the terrain-only region geometry.

### 6.1 Culture selection & seeding → `gdd-culture-catalog.md` §6

Given the Layer-1/2 biome map, select the campaign's cultures from the canonical catalog and seed their homelands:

- **Select** human cultures whose seed-biomes the map can satisfy (a constraint-satisfaction draw — ~10 human seed points scaled to map size, plus ≤3 elf and ≤3 dwarf seed points where suitable terrain exists), respecting the phonemic-adjacency rule. Apply per-campaign seeded jitter and draw each culture's alignment (even split for humans; explicit weights for demihumans).
- **Seed** each as a small polity on **wilderness** hexes matching its seed-biomes — the universal wilderness-seeding model (catalog §6.3). Nothing political exists yet; realms, vassals, and cities *emerge* during Layer 4.

### 6.2 Coarse region geometry → `gdd-region-painting.md` Phase 1

Run region-painting's geometric detection over the 24-mile terrain (it depends only on Layers 1–2): continents, terrain-cluster regions, coastal & landform features, and the hydronym graph. This yields *unnamed* coarse region shapes; naming waits for Layer 5 (once cultures and history exist). Fine (6-mile) region geometry is painted lazily at play (region-painting §3.4), not here.

### 6.3 Baseline wilderness beastmen → `ax_domains_of_chaos.xml`

Seed never-settled wilderness with baseline beastman clanholds from the sacred `ax_domains_of_chaos.xml` demographic tables (clanholds always wilderness; per-terrain race/family/territory counts; ≤125 families per 6-mile hex; mixed-race clusters ruled by the dominant race; all Chaotic), plus savage-human clanholds per the chaotic-domain rules in suitable open terrain. These become political entities under chieftain rulers, and their lair-strongholds double as dungeon seeds (§9.3). The Layer-4 simulation later *adds* more beastmen and ruins to regions that collapse and depopulate. `wilderness_beastman_density` (default 1.0, range 0.0–2.0) scales the baseline; 0 yields an empty wilderness.

### 6.4 Layer 3 output

The map now carries: seeded culture-polities in wilderness, unnamed coarse region shapes per hex, and baseline beastman/savage-human clanholds. This is the starting state the Layer-4 simulation runs forward.

---

## 7. Layer 4: History Simulation

**The new core of the pipeline.** This replaces the old single-pass culture diffusion and the Voronoi borders of the former Layer 3: the present-day world is the *output of a deterministic simulation*, not a one-shot draw.

### 7.1 Run the simulation → `gdd-history-simulation.md`

Run the history simulation forward from the Layer-3 seed state — ~160 generation ticks over ~4,000 years. Each tick, the seeded culture-polities expand (size-exponent growth, biome-weighted), contest borders, migrate, and rise or collapse against a size+age+overextension stability curve. Collapses yield rump states, successor states, alignment drift, and depopulation → wilderness → beastmen + ruins. Demihumans peak early and fall to enclaves. The whole simulation is seed-deterministic.

### 7.2 Simulation outputs (the permanent present-day data)

- **Political map** — realms, vassal chains, borders, capitals, rulers (class biased by culture sphere-weights), alignments. *(Replaces the old Layer 3.)*
- **Substrate weights** — per-hex `culture_weights`, `religion_weights`, `racial_weights`, `alignment_weights`. The former static "weighted demographic distributions" are now the **evolving output** of the sim, with the minimum presence floor retained (default 0.1% — traders, refugees, persecuted minorities appear anywhere).
- **Territory classification** — civilized / borderlands / wilderness emerge from the simulated population bands; Layer 6 only finalizes settlement-local detail (no more preliminary + second pass).
- **Event log** — founding / expansion / war / conquest / migration / schism / collapse / depopulation events, significance-ranked, feeding region naming (Layer 5), dungeon provenance + quests/rumors (Layer 6), and the timeline (Layer 7).

### 7.3 Religion overlay → `gdd-religion-system.md`

Religion is the one shared canonical pantheon read through each culture's alignment-family (Lawful henotheist / Chaotic polytheist / Neutral ancestor-way), with per-culture deity names, holy symbols, and saints. The simulation propagates `religion_weights` (syncretic diffusion, conquest conversion at the religion-change morale cost, schism on collapse). This supersedes the old 1:1 culture-religion seeding and `gdd-cultural-religious-generation.md` §3–§4.

### 7.4 Present-day handoff

The final tick's surviving polities hand off to the runtime ACKS domain/morale/economic systems with **seeded morale** (alignment- and religion-mismatch penalties, garrison/overextension state), validated against ACKS realm-sizing, density (~5,000 families per 24-mile hex; ~50% wilderness), and economic viability (`gdd-history-simulation.md` §12). Validation runs in Layer 8.

### 7.5 User parameters

| Parameter | Default | Effect |
|---|---|---|
| Culture seed points | ~10 human, ≤3/demihuman race | Diversity & density of starting peoples (catalog §6.1) |
| Collapse temperament | Moderate | Turbulence of history — ruin / successor-state density (history-sim §13) |
| History length | ~4,000 yr / 160 ticks | Depth of history; older = more ruins |
| Migration rate | Moderate | How readily displaced cultures relocate |
| Demihuman presence | on | Whether demihuman seeds are placed |
| Non-human ratio | ~1:5 | Overall non-human demographic share |
| Minority weight floor | 0.1% | Minimum demographic presence anywhere |
| Wilderness beastman density | 1.0 | Baseline (§6.3) + collapse-driven beastman scaling |

---

## 8. Layer 5: Name Generation

> **Updated for the new model:** name banks are now **static canonical assets per culture** (one per catalog culture, generated once at development time — not per campaign). Layer 5 also runs **region-painting Phase-2 naming** (`gdd-region-painting.md` §5): the coarse region shapes from Layer 3 are named from the culture banks, descriptive templates, and the Layer-4 event log (historical & fallen-polity names), with multilingual alternates for major features. Fine 6-mile region names are generated lazily at play, not here. The banks need new region/feature categories and per-culture deity-name sub-tables (`gdd-region-painting.md` §11, `gdd-religion-system.md` §5.2).

### 8.1 Pre-Built Name Banks (Development-Time LLM Task)

During development, use the LLM to generate large name banks per cultural group:

- 500+ settlement names (tagged by size: hamlet, village, town, city)
- 200+ realm/province names
- 1000+ personal names (first names by gender + surnames/clan names)
- 50+ religious order names per tradition
- 100+ geographic feature names (rivers, mountains, forests)

Each cultural group's names share a phonemic palette so they sound related. The names are pre-generated and stored as JSON data files, not generated at runtime.

### 8.2 Runtime Name Assignment

```
1. For each settlement: sample from the hex's ethnic_weights, pick the
   corresponding cultural name bank, draw a settlement name of appropriate size
2. For each realm: use the dominant culture of the capital hex
3. For each NPC: sample from the hex's ethnic_weights for cultural context
4. For geographic features: use the dominant culture of the region
5. Track used names to avoid duplicates within a campaign
```

### 8.3 User Override

Players can rename any generated name. The original generated name is preserved as metadata.

---

## 9. Layer 6: Infrastructure and Content Seeding

> **Updated for the new model:** three inputs now come from the Layer-4 simulation. **Dungeon/lair seeds** are driven by the sim's collapse/depopulation events — fallen realms emit ruins carrying provenance (culture, era, name) — supplementing the baseline beastman lairs from §6.3. **Territory classification** is a sim *output* (§7.2), so this layer only finalizes settlement-local detail instead of the old preliminary + second pass. **Road naming** of the trunk/highway tier is delegated to `gdd-region-painting.md` §6 (network density set by culture `road_propensity`).

### 9.1 Settlement Placement

Using ACKS settlement distribution tables (from XML rules reference):

```
1. For each realm, calculate total population from hex count × families-per-hex by terrain
2. Look up the settlement distribution table: how many Class I, II, III... settlements
3. Place settlements:
   - Capital is already placed (Layer 3)
   - Larger settlements placed first, preferring:
     a. River hexes (trade)
     b. Coastal hexes (port)
     c. Road intersection hexes (after roads are placed)
     d. Productive terrain (flat clear/woods near water)
   - Minimum distances between settlements scale with market class
     (Class I cities are far apart; Class VI hamlets can be close)
4. Each settlement gets: population, market class, name (from Layer 5)
```

### 9.2 Road Network

```
1. Connect all settlements within a realm using weighted pathfinding:
   - Path cost = terrain movement cost (from ACKS rules)
   - Prefer connecting to existing roads (reduces total road length)
   - Capital connects to all major cities first
   - Then connect secondary settlements to nearest road
2. Connect realms: major trade roads between capitals of allied/neutral realms
3. Mark road hexes: road presence reduces movement cost to road rate
```

### 9.3 Dungeon and Lair Seeding

Per ACKS guidance (ACore p.235), a regional map of ~30 dungeon sites per region:

```
1. Calculate target dungeon count from map size and population:
   - ~3 large dungeons per ~80 24-mile hexes
   - ~10 medium dungeons per ~80 hexes
   - ~17 lair dungeons per ~80 hexes
   (Scale proportionally for larger/smaller maps)

   NOTE: Beastman lair-strongholds placed in §6.5 count toward these
   targets. Subtract beastman medium dungeons and lair dungeons from
   the remaining target before placing additional sites. Large dungeons
   are always placed independently — beastman lairs do not satisfy
   the large dungeon requirement.

2. Place large dungeons:
   - Must be in wilderness or deep borderlands hexes
   - Minimum 8 hexes from any Class III+ settlement
   - Minimum 12 hexes from each other
   - Prefer dramatic terrain (mountains, deep forest, swamp)

3. Place medium dungeons:
   - Prefer borderlands and wilderness hexes
   - Minimum 3 hexes from other medium/large dungeons
   - Can be within 4-5 hexes of Class IV-V settlements

4. Place lair dungeons:
   - Can be anywhere in borderlands or wilderness
   - Can be within 3-5 hexes of any settlement including Class III
   - Some can be VERY close (adjacent hex) to smaller settlements

5. Exception: one large dungeon may be placed beneath a major settlement
   (there is published precedent for this)

6. Each dungeon seed gets:
   - Type (rolled on the d20 dungeon flavor table from gdd-dungeon-layout.md)
   - Size category (lair/small/medium/large)
   - Level range (based on distance from civilization — farther = higher level)
   - Theme (from dungeon type)
   - Name placeholder (from Layer 5)
   - A one-paragraph hook (generated in Layer 7)
```

### 9.4 Deforestation and Forestation Pass

After settlements are placed, apply the deforestation/forestation rules from `gdd-terrain-system.md` §6:

```
1. For each non-elven settlement, iterate outward:
   - Convert woods/jungle hexes to clear based on market class and distance formula
2. For each elven settlement, iterate outward:
   - Convert clear hexes to woods based on same formula
3. Preserve original_biome on all modified hexes
```

### 9.5 Fortification Placement

```
1. Place border forts along realm frontiers (every 3-5 hexes along borders)
2. Place castle/stronghold at each major settlement (Class I-III)
3. Place watchtowers along major roads through borderlands (every 4-6 hexes)
```

### 9.6 Territory Classification (Second Pass)

With settlements and roads placed, recalculate territory classification:

```
- Civilized: within 2 hexes of a Class I-IV settlement, OR on a road within a realm
- Borderlands: within realm borders but not civilized, OR contested territory
- Wilderness: everything else
```

This overwrites the preliminary classification from Layer 3.

### 9.7 Wilderness POI Placement

After territory classification is finalized, generate wilderness points of interest per `gdd-poi-generation.md`:

Calculate POI budget: clamp(30 - actual_dungeon_count, 5, 10)
Roll POI types on the d20 distribution table
Select hexes using terrain affinity, distance constraints, and territory weighting
Roll mechanical skeletons (type-specific random tables)
Assign cultural/historical context from the setting's timeline and culture data
Generate rumor seeds (1-2 per POI) as inputs to §9.8


POIs fill the "special areas" slice of the ACKS 30 non-settlement static POI target — the locations that are neither full dungeons nor monster lairs.

### 9.8 Quest and Rumor Seeding

After all map features are placed (settlements, dungeons, lairs, forts, POIs), generate the initial quest and rumor pool per `gdd-quest-rumor-system.md`:

Aggregate rumor seeds from all sources:

POI rumor seeds (from §9.7)
Dungeon hooks (from §9.3, one per dungeon seed)
Lair threats (from dynamic lair data)
Historical rumors (from Layer 5/7 timeline)


Enrich each seed into a full Rumor record (assign accuracy, distribution range,
knowledge category, freshness)
Scan for quest-eligible threats:

Monster lairs near settlements or roads
Dungeons producing active threats
Hostile factions occupying territory


Match threats to nearby NPC authorities who meet quest conditions
Generate 3-8 initial quests with reward calculations
Generate quest-sourced rumors (accuracy = "true") for each quest
All quest/rumor text is placeholder — LLM narration happens in Layer 7

---

## 10. Layer 7: LLM Narrative Synthesis

### 10.1 Principle

The LLM **explains** what the generator built. It does NOT decide what to build. Every mechanical fact (this realm is Chaotic, this city is on a river, these two cultures are rivals) is already determined. The LLM's job is to make it make sense narratively. In the new model the **historical timeline is the Layer-4 event log** (`gdd-history-simulation.md` §11): the LLM selects the significant logged events per epoch and narrates them — inventing names for rulers, battles, and treaties consistent with what the simulation actually did — but never adding, moving, or inventing events.

### 10.2 Generation Prompts

The LLM receives the complete mechanical data for the setting and generates:

**Per realm:**
- Political summary (2-3 sentences: who rules, how, what their priorities are)
- Current situation (is the realm at war? facing a plague? in a golden age?)
- Relationship descriptions with neighboring realms
- Recent history (past 300 years): 2-4 paragraphs covering political succession, wars, treaties, religious movements, economic shifts, named rulers and battles. This is what living NPCs remember.

**Per cultural group:**
- Cultural flavor text (1 paragraph: what makes this culture distinctive)
- Behavioral tendencies (mercantile, militaristic, scholarly, pastoral, etc.)

**Per religious tradition:**
- Description (1 paragraph: what followers believe and practice)
- Relationship with political power (state religion? persecuted minority? underground cult?)

**Per dungeon seed:**
- One-paragraph hook (why this place exists, what draws adventurers, what danger lurks)
- This is the "Judge's one paragraph per point of interest" from ACore p.235

**Per wilderness POI** (from `gdd-poi-generation.md` §5):
- Name (proper name drawn from the appropriate cultural name bank)
- Description (1 paragraph: appearance, history, significance)
- Rumor text (1-2 sentences per rumor seed, in NPC voice)
- Linked POIs receive their descriptions together for narrative consistency

**Per quest** (from `gdd-quest-rumor-system.md` §3.6 step 6):
- Quest title (short, evocative)
- Quest description (2-3 sentences: what the problem is, what the questgiver wants)
- Questgiver dialogue (what the NPC says when offering the quest)
- Completion dialogue (what the NPC says when the quest is turned in)

**Per rumor** (from `gdd-quest-rumor-system.md` §2.2):
- Narrated text (1-2 sentences in NPC voice, calibrated to the rumor's accuracy level — exaggerated rumors sound breathless, misleading rumors sound confident but wrong, false rumors sound like secondhand gossip)

**Setting-wide historical timeline:**
- Deep history (4,000–1,500 years ago): 8-12 bullet points, one sentence each. Rise and fall of ancient empires, great migrations, cataclysms, founding of religions. These explain why ancient ruins and lost civilizations exist.
- Middle history (1,500–300 years ago): 15-20 bullet points, 1-2 sentences each. Formation of current realms, major wars, religious schisms, non-human realm interactions.
- Near history, the last 300 years, 10-15 bullet points, 1-2 sentences each. Focus on development of current conflicts and civilizational threats.
- All events tagged to specific realms, regions, and cultural groups for LLM context retrieval.

**Setting overview:**
- A player-facing setting brief (1-2 pages) that a player would read before starting a campaign
- The "story so far" — what's happening in the world right now, derived from the recent history of each realm

### 10.3 Constraints on LLM Output

- The LLM cannot change any mechanical facts (realm alignment, settlement placement, cultural distributions)
- Names are already assigned by Layer 5 — the LLM uses them, not replaces them
- The LLM adds narrative causation ("the Keshites control the river valley because their ancestors followed the river inland from the coast three centuries ago") but cannot contradict the generated geography or politics
- All LLM output is cached as campaign data after generation

---

## 11. Layer 8: Validation and Player Review

> **Updated for the new model:** Layer 8 also runs the **present-day ACKS-validity handoff** from the history simulation (`gdd-history-simulation.md` §12): surviving polities become ACKS domains with seeded morale, checked for realm-sizing, population density (~5,000 families per 24-mile hex; ~50% wilderness), territory classification, and economic viability before the campaign locks.

### 11.1 Mechanical Validation

Automated checks before presenting to the player:

```
- Every hex has all required fields (elevation, biome, political entity or wilderness, demographic weights)
- All demographic weight arrays sum to 100% (within floating-point tolerance)
- Minimum weight floors applied
- Settlement count matches ACKS tables for realm population
- Market class assignments are consistent with settlement population
- Realm sizes are consistent with ruler levels (an empire can't be 3 hexes)
- All settlements are connected by roads (within their realm)
- Domain economics are viable (realm income covers garrison costs)
- No orphaned data (settlement with no road, realm with no capital, etc.)
```

### 11.2 Player Parameter Adjustment

Before generation begins, present the full parameter set:

**Physical (Layer 1-2):**
- Map size, land mass style, mountain frequency, river density, sea level, latitude range

**Political (Layer 3):**
- Number of empires/kingdoms, alignment distribution, wilderness ratio

**Demographic (Layer 4):**
- Number of cultures, number of religions, ethnic-political alignment, non-human ratio, religious exclusivism, minority floor

**Content (Layer 6):**
- Dungeon density multiplier, road density, fortification density, POI density multiplier, POI danger level

All parameters have sensible defaults. Players who just want to play skip the sliders.

### 11.3 Player Review and Approval

After generation:

1. Display the generated map with political overlay
2. Show the setting brief (from Layer 7)
3. Show the major realms, cultures, and conflicts
4. Player can:
   - **Accept** — setting becomes permanent campaign data
   - **Regenerate specific elements** — re-roll one realm's alignment, move a mountain range, rename a culture, regenerate a single dungeon seed
   - **Regenerate everything** — new seed, start over
5. **Post-approval lock** — once approved, the setting data is canonical. It is never regenerated. All downstream generation treats it as fixed ground truth.

---

## 12. Godot Implementation Notes

### 12.1 Key Godot Classes

- `FastNoiseLite` — heightmap and precipitation noise generation (built-in, no plugins needed)
- `RandomNumberGenerator` — seeded RNG for all random decisions
- `Image` — heightmap stored as Image for efficient per-pixel sampling
- `TileMap` / `TileMapLayer` — renders the hex map from generated terrain data
- `AStarGrid2D` — road pathfinding between settlements

### 12.2 Performance Considerations

- Heightmap generation for a Large map (~1,200 hexes) should complete in under 1 second
- River tracing is O(n) per river source — fast even for many rivers
- Voronoi territory expansion: use a priority queue flood-fill, O(n log n)
- LLM narrative synthesis (Layer 7) is the slowest step — expect 30-60 seconds for a full setting depending on model. Show a progress bar. Generate in parallel where possible (each realm's description is independent).

### 12.3 File Organization

```
engine/subsystems/generation/world/
  setting_generator.gd          # Orchestrates the 8-layer pipeline
  heightmap_generator.gd        # Layer 1: FastNoiseLite heightmap + hydrology
  climate_generator.gd          # Layer 2: temperature, precipitation, Köppen
  political_generator.gd        # Layer 3: realms, borders, alignment
  demographic_generator.gd      # Layer 4: cultures, religions, racial weights
  name_generator.gd             # Layer 5: name bank sampling
  infrastructure_generator.gd   # Layer 6: settlements, roads, dungeons, deforestation
  narrative_generator.gd        # Layer 7: LLM prompt assembly and caching
  setting_validator.gd          # Layer 8: mechanical validation
  setting_parameters.gd         # User parameter definitions and defaults

data/name_banks/
  culture_keshite.json          # Pre-generated name banks per culture
  culture_aldaran.json          # (actual names generated during development)
  ...
```

---

## 13. Integration Points

### 13.1 Downstream Consumers

- **Region zoom-in** (`gdd-hex-subdivision.md`, future) — reads 24-mile hex data to generate 6-mile hex detail
- **Settlement stocking** — reads settlement size, market class, demographic weights
- **Dungeon generation** (`gdd-dungeon-layout.md`) — reads dungeon seeds to generate dungeon maps
- **Encounter system** — reads terrain tags and territory classification for encounter table selection
- **Weather system** (`gdd-weather-generation.md`) — reads Köppen codes, effective latitude, elevation, coastal proximity, and prevailing wind direction
- **Calendar/seasons system** (`gdd-calendar-seasons.md`) — reads hemisphere parameter- **Domain simulation** — reads realm data, ruler profiles, economic parameters
- **LLM context assembly** — reads setting narrative, cultural data, faction relationships
- **NPC generation** — reads demographic weights for name/culture/religion selection
- **Quest and rumor system** (`gdd-quest-rumor-system.md`) — reads dungeon seeds, lair data, POI data, NPC ruler profiles, domain economics for quest generation and rumor distribution
- **POI generation** (`gdd-poi-generation.md`) — reads terrain tags, cultural data, dungeon placements, territory classification for POI placement

### 13.2 What This Generator Does NOT Produce

- 6-mile hex detail (that's region zoom-in, a separate GDD)
- Individual dungeon maps (that's `gdd-dungeon-layout.md`)
- Individual settlement maps (that's `gdd-settlement-layout.md`)
- NPC stat blocks (that's NPC generation at encounter/settlement stocking time)
- Encounter table contents (that's encounter table composition from monster catalog)

This generator produces the **24-mile hex campaign map** and the **setting metadata** that all other generators consume.

---

## 14. Design Decisions (Resolved)

- **Tectonic plates: NO.** Use directional noise bias to create linear mountain ranges without plate simulation. If mountains look too random, add ridge-line tracing as a post-process (connect nearby mountain peaks into chains). No tectonic sim.
- **Historical depth: SUPERSEDED — now simulated (2026-06-03).** The timeline is produced by the Layer-4 history simulation (`gdd-history-simulation.md` §4, §11), not invented by the LLM. The depth targets below remain only as *narration-density guidance* for how much of the simulated event log Layer 7 surfaces per epoch:
  - **Deep history (4,000–1,500 years ago):** Bullet-point timeline. 8-12 major events (rise/fall of ancient empires, great migrations, cataclysms, founding of old religions). One sentence per event. These are the "ancient ruins" and "lost civilizations" that explain dungeon origins.
  - **Middle history (1,500–300 years ago):** Double-density bullet-point timeline. 15-20 events covering the formation of current political entities, major wars, religious schisms, non-human realm interactions. Two sentences per event where needed.
  - **Recent history (past 300 years):** Generous narrative summary. 2-4 paragraphs per realm covering political succession, recent wars, treaties, religious movements, economic shifts, and the current situation. This is what living NPCs and their grandparents remember. Named rulers, named battles, named treaties. Enough that an NPC can say "my grandfather fought at the Battle of Three Rivers" and there IS a Battle of Three Rivers in the history.
  - All historical events are tagged to specific realms, regions, and cultural groups so the LLM context assembler can pull relevant history for NPC conversations in specific locations.
- **Ocean hexes: NO variation for v1.** All ocean hexes are uniform. Sea voyage encounters use the single Ocean encounter table regardless. Depth/reef/current variation can be added later if sea voyages get expanded.

---

## 15. Worked Example: Layer 1 → Layer 2

To illustrate how the layers chain together:

```
Map size: Medium (25 × 20 = 500 hexes)
Seed: 42

Layer 1 runs:
  - FastNoiseLite(seed=42, type=SIMPLEX_SMOOTH, octaves=6, frequency=0.004)
  - Continental shaping applied (default "continental" style)
  - Result: ~60% land, ~40% ocean
  - Mountains in the northwest and a ridge through the center
  - Major river flowing from central mountains southeast to the coast
  - A large lake in the eastern lowlands

Layer 2 runs:
  - Latitude: warm south, cold north (default temperate range)
  - Precipitation noise(seed=43) + rain shadow from central mountains
  - Eastern side of mountains is drier (rain shadow)
  - Result:
    - Northwest mountains: Dfc (subarctic) → woods biome at lower elevations, 
      ET (tundra) → clear biome at peaks
    - Central river valley: Cfa (humid temperate) → woods biome
    - Eastern rain shadow: BSk (cold steppe) → clear biome, 
      some BWk (cold desert) → desert biome in the driest area
    - Southern coast: Csa (Mediterranean) → clear biome
    - Southern jungle coast: Af (tropical rainforest) → jungle biome
    - Swamp forms where river meets the lake at flat elevation
  - Terrain tags assigned per gdd-terrain-system.md
  - Köppen codes stored for weather system

Ready for Layer 3 (political placement).
```

---

## 16. Revision History

- **2026-06-03:** **Layer 3–4 rework.** Replaced the static political layer and demographic layer with the four-engine model: Layer 3 = culture seeding (`gdd-culture-catalog.md`) + coarse region geometry (`gdd-region-painting.md` Phase 1) + baseline wilderness beastmen; Layer 4 = the history simulation (`gdd-history-simulation.md`) producing the present-day political map, substrate weights, territory classification, and event log, with religion as the shared-pantheon overlay (`gdd-religion-system.md`). Updated the pipeline overview, the timeline principle (now simulated, not LLM-invented), Layer 5 (static canonical banks + region naming), Layer 6 (sim-fed dungeon seeds, territory classification as output, delegated road naming), Layer 8 (ACKS present-day handoff), and superseded the §14 historical-depth decision. Thin-orchestrator style — detail delegated to the engine GDDs.
- **2026-03-19:** Initial draft. 8-layer pipeline designed. Physical geography uses Godot FastNoiseLite. Climate uses simplified Köppen. Downstream integration documented.
- **2026-03-19 (rev 2):** All open questions resolved. No tectonic plate simulation (use directional noise bias for mountain chains). Historical depth specified: 4,000-year bullet timeline with double density for recent 1,500 years and generous narrative for past 300. No ocean hex variation for v1.
