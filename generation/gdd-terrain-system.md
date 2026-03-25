# GDD: Terrain System and Hex Generation

**Authority:** PROJECT-DESIGNED — the terrain tag system, biome/elevation layering, encounter table selection logic, and deforestation/forestation rules are not derived from any ACKS sourcebook. The encounter tables themselves and movement costs are ACKS rules defined in the XML rules reference library.
**Status:** Draft
**Depends on ACKS rules:** `acore_adventures_and_encounters.xml` (movement costs by terrain), `acore-monster-stocking-rules.xml` (wilderness encounter tables by terrain), `acore-setting-construction-rules.xml` (territory classification, population density)
**Modifiable by Claude Code:** Yes — the tag system, generation algorithms, and weighting formulas are all engineering decisions.
**Last updated:** 2026-03-19

---

## 1. Purpose

Define the terrain representation system used across all hex maps (24-mile, 6-mile, and 1.5-mile scales). This GDD solves a specific problem: ACKS encounter tables use single terrain columns, but real terrain is a combination of elevation and ground cover. A hex can be forested hills, desert mountains, or swampy flatlands. This system models terrain as layered tags and defines how those tags map to the published encounter tables, movement costs, and visual rendering.

---

## 2. ACKS Constraints

### 2.1 Encounter Table Columns (ACore Ch.6)

The published Wilderness Encounters by Terrain table has **10 columns**, each rolled on d8 to produce a creature type category (Men, Flyer, Humanoid, Animal, Insect, etc.), which then references a sub-table for the specific monster:

| Column | Terrain |
|--------|---------|
| 1 | Clear, Grass, Scrub |
| 2 | Woods |
| 3 | River |
| 4 | Swamp |
| 5 | Mountains, Hills |
| 6 | Barren, Desert |
| 7 | Inhabited |
| 8 | City |
| 9 | Ocean |
| 10 | Jungle |

Each column produces different probability distributions of creature types. For example, Woods encounters are weighted toward Men, Animals, and Unusual creatures; Swamp is weighted toward Swimmers and Undead; Mountains/Hills toward Flyers and Dragons.

### 2.2 Movement Costs (ACore Ch.6)

ACKS defines movement costs per terrain type. When a hex has multiple terrain tags, the costliest tag determines movement cost.

### 2.3 Territory Classification (ACore Ch.10)

ACKS defines three territory classifications that affect encounter frequency and settlement density:
- **Civilized** — settled, patrolled, low encounter frequency
- **Borderlands** — partially settled frontier, moderate encounter frequency
- **Wilderness** — unsettled, high encounter frequency

### 2.4 Dungeon/Lair Placement (ACore p.235)

Per ACKS, a regional map should contain approximately 30 dungeon/lair sites with a mix of sizes (§2 in gdd-dungeon-layout.md). Large/dangerous dungeons should be placed in wilderness or hard-to-access areas. Lairs and small dungeons can be within 3-5 hexes of settlements.

---

## 3. Terrain Tag System

### 3.1 Two Independent Layers

Each hex carries tags from two independent layers:

**Layer A — Elevation** (derived from heightmap):

| Tag | Description | Heightmap Threshold |
|-----|-------------|---------------------|
| `flat` | Plains, valleys, lowlands | Below hill threshold |
| `hills` | Rolling hills, elevated terrain | Between hill and mountain thresholds |
| `mountains` | Peaks, high passes, alpine | Above mountain threshold |

**Layer B — Biome / Ground Cover** (derived from Köppen climate + precipitation):

| Tag | Encounter Column | Description |
|-----|-----------------|-------------|
| `clear` | Clear, Grass, Scrub | Open grassland, scrubland, prairie, farmland |
| `woods` | Woods | Temperate or boreal forest |
| `jungle` | Jungle | Tropical dense forest |
| `swamp` | Swamp | Wetland, marsh, bog, fen |
| `desert` | Barren, Desert | Arid wasteland, sand desert, rocky barren |

**Layer C — Water Features** (derived from hydrology):

| Tag | Encounter Column | Description |
|-----|-----------------|-------------|
| `river` | River | Hex contains a significant river or lake |
| `ocean` | Ocean | Coastal hex or open sea |

**Layer D — Civilization** (derived from domain data):

| Tag | Encounter Column | Threshold |
|-----|-----------------|-----------|
| `city` | City | Hex contains a city (Market Class I-III) |
| `inhabited` | Inhabited | Hex is in civilized or borderlands territory (see §4.3) |

### 3.2 How Tags Combine

Every hex has exactly **one** elevation tag and exactly **one** biome tag. It may optionally have a water tag and/or a civilization tag.

Examples:
- Open plains: `[flat, clear]`
- Forested hills: `[hills, woods]`
- Desert mountains: `[mountains, desert]`
- Swampy lowlands with river: `[flat, swamp, river]`
- Settled farmland near a city: `[flat, clear, inhabited]`
- Jungle highlands: `[hills, jungle]`
- Coastal mountains: `[mountains, clear, ocean]`

### 3.3 Tag Storage

```
HexTerrainData:
  elevation: string          # "flat" | "hills" | "mountains"
  biome: string              # "clear" | "woods" | "jungle" | "swamp" | "desert"
  water: string or null      # "river" | "ocean" | null
  civilization: string       # "civilized" | "borderlands" | "wilderness"
  territory_classification: string  # Same as civilization (ACKS term)
  has_city: bool             # True if hex contains a city
  original_biome: string     # Pre-deforestation/forestation biome (preserved for reversal)
  settlement_ids: Array      # Settlements in this hex, if any
```

---

## 4. Encounter Table Selection Logic

When the engine rolls a wilderness encounter, it must select which of the 10 ACKS encounter table columns to use. The selection follows a priority cascade:

### 4.1 Priority Cascade

```
1. IF hex has_city → use CITY table (100%)
2. ELSE IF hex is civilized → use INHABITED table (100%)
3. ELSE IF hex is borderlands → 50% INHABITED table, 50% natural terrain
4. ELSE (wilderness) → use natural terrain (100%)
```

### 4.2 Natural Terrain Selection

When natural terrain is selected (step 3-4 above), the hex may have multiple applicable tables. The selection logic:

```
1. IF hex has water tag AND encounter involves water context:
   - River: use RIVER table
   - Ocean: use OCEAN table
   (Water context = party is traveling by boat, crossing a river, on the coast)

2. ELSE IF hex has ONLY a biome tag relevant to encounters (elevation is flat):
   - Use the biome's encounter column (100%)
   - flat + clear → Clear/Grass/Scrub
   - flat + woods → Woods
   - flat + jungle → Jungle
   - flat + swamp → Swamp
   - flat + desert → Barren/Desert

3. ELSE IF hex has BOTH a non-flat elevation AND a biome tag:
   - 60% chance: use biome encounter column
   - 40% chance: use Mountains/Hills encounter column
   
   Examples:
   - [hills, woods] → 60% Woods, 40% Mountains/Hills
   - [mountains, desert] → 60% Barren/Desert, 40% Mountains/Hills
   - [hills, clear] → 60% Clear/Grass/Scrub, 40% Mountains/Hills
   - [mountains, jungle] → 60% Jungle, 40% Mountains/Hills

4. IF elevation is hills or mountains AND biome is clear:
   - This is the "pure hills/mountains" case
   - 40% Clear/Grass/Scrub, 60% Mountains/Hills
   (Reversed weighting — hills with no forest/jungle/swamp are primarily mountain terrain)
```

### 4.3 Inhabited Table Threshold

| Territory Classification | Chance of Using Inhabited Table |
|---|---|
| Civilized | 100% — always use Inhabited |
| Borderlands | 50% — roll; on failure, use natural terrain per §4.2 |
| Wilderness | 0% — never use Inhabited |

When a borderlands hex rolls to use natural terrain (the 50% failure case), the natural terrain selection in §4.2 applies normally.

### 4.4 River Encounters

The River column is used when:
- The party is actively crossing a river in this hex, OR
- The party is traveling along a river in this hex, OR
- The hex's primary feature is a river/lake (water tag present) and a random check determines the encounter involves the water

For hexes with a river tag where the party is traveling overland (not interacting with the river), use the normal biome/elevation selection. The river tag doesn't automatically replace the biome table — it's contextual.

---

## 5. Movement Cost Selection

When a hex has multiple terrain tags, the **costliest** tag determines movement cost.

Movement cost hierarchy (slowest to fastest):
1. Mountains (most expensive)
2. Swamp
3. Jungle
4. Woods / Hills (roughly equal)
5. Desert
6. Clear (cheapest)

So `[mountains, woods]` uses the Mountains movement cost. `[hills, swamp]` uses the Swamp cost. `[flat, clear]` uses the Clear cost.

Exact movement point costs per terrain are defined in the ACKS rules in `acore_adventures_and_encounters.xml` and are NOT defined in this GDD.

Roads override terrain cost — a road through mountains still provides road movement speed.

---

## 6. Deforestation and Forestation

### 6.1 Deforestation (Human/Non-Elven Settlements)

Settlements with non-elven majority populations cause deforestation of surrounding hexes. Forest (`woods` or `jungle`) biome tags are converted to `clear` based on proximity to settlements.

**Deforestation chance per hex:**

| Market Class | Adjacent Hex (distance 0) | Reduction per hex of distance |
|---|---|---|
| I | 100% | -5% per 6-mile hex |
| II | 80% | -5% per 6-mile hex |
| III | 60% | -5% per 6-mile hex |
| IV | 50% | -5% per 6-mile hex |
| V | 45% | -5% per 6-mile hex |
| VI | 40% | -5% per 6-mile hex |

**Procedure:** For each settlement on the map, iterate outward hex by hex. For each hex containing `woods` or `jungle` biome:
1. Calculate distance (in 6-mile hexes) to the nearest non-elven settlement
2. Look up that settlement's market class
3. Calculate deforestation chance = base chance - (distance × 5%)
4. If chance ≤ 0%, stop (no deforestation at this distance)
5. Roll against the chance. On success: set `biome = "clear"`, preserve `original_biome = "woods"` (or `"jungle"`)

If multiple settlements overlap in their deforestation zones, use the **highest** deforestation chance (don't stack).

The `original_biome` field is preserved so the hex "remembers" it was once forested. If the settlement is later destroyed or abandoned (during campaign play), regrowth can restore the original biome over time.

### 6.2 Forestation (Elven Settlements)

Settlements with majority elven populations cause the reverse: `clear` biome tags are converted to `woods` in surrounding hexes.

The same formula applies with the same market class base chances and distance reduction. For each hex containing `clear` biome within range of an elven settlement:
1. Calculate distance to the nearest elven settlement
2. Calculate forestation chance using the same table as §6.1
3. On success: set `biome = "woods"`, preserve `original_biome = "clear"`

Elven forestation and human deforestation can conflict in border regions. Resolution: if a hex is in range of both an elven and a human settlement, **the closer settlement wins**. On equal distance, the larger settlement (lower market class number) wins.

### 6.3 Application Timing

Deforestation/forestation is applied:
1. During initial world generation (after biomes are assigned, after settlements are placed)
2. During region zoom-in (when 6-mile hex detail is generated within a 24-mile parent)
3. Potentially during campaign play if settlements are founded or destroyed (long-term regrowth)

---

## 7. Biome Generation from Köppen Climate

### 7.1 Köppen-to-Biome Mapping

The setting generation pipeline (§14A.2) assigns a Köppen climate code to each hex based on latitude, elevation, and proximity to water. This GDD defines how those codes map to biome tags:

| Köppen Group | Codes | Default Biome | Notes |
|---|---|---|---|
| **Af** — Tropical rainforest | Af | `jungle` | Hot, wet year-round |
| **Am** — Tropical monsoon | Am | `jungle` | Seasonal heavy rain |
| **Aw** — Tropical savanna | Aw | `clear` | Dry winters, wet summers; grassland/savanna |
| **BWh/BWk** — Hot/cold desert | BWh, BWk | `desert` | Arid, minimal vegetation |
| **BSh/BSk** — Hot/cold steppe | BSh, BSk | `clear` | Semi-arid grassland/scrubland |
| **Cfa/Cfb/Cfc** — Temperate oceanic/humid | Cfa, Cfb, Cfc | `woods` | Temperate forest default |
| **Csa/Csb** — Mediterranean | Csa, Csb | `clear` | Dry summers; scrubland/open woodland |
| **Cwa/Cwb** — Subtropical highland | Cwa, Cwb | `woods` | Monsoon-influenced forest |
| **Dfa/Dfb** — Humid continental | Dfa, Dfb | `woods` | Deciduous/mixed forest |
| **Dfc/Dfd** — Subarctic/boreal | Dfc, Dfd | `woods` | Taiga/boreal forest |
| **Dwa/Dwb/Dwc/Dwd** — Monsoon continental | Dwa-Dwd | `woods` | Cold monsoon forest |
| **ET** — Tundra | ET | `clear` | Tundra scrub; treated as clear for encounters |
| **EF** — Ice cap | EF | `desert` | Permanent ice; treated as barren for encounters |

### 7.2 Biome Variation

The Köppen mapping produces the **default** biome, but local variation is applied:
- A `woods` hex has a 10% chance of being `swamp` if it's in low-elevation terrain adjacent to a river
- A `clear` hex in BSh/BSk zones has a 15% chance of being `desert` in the driest areas
- A `jungle` hex at higher elevations can become `woods` (montane forest)

These variation rules are tunable parameters, not hard rules.

---

## 8. Elevation Generation from Heightmap

### 8.1 Heightmap to Elevation Tags

The setting generation pipeline produces a heightmap (continuous elevation values per hex). This GDD defines the thresholds for converting to discrete elevation tags:

| Elevation Tag | Heightmap Range | Description |
|---|---|---|
| `flat` | 0–40% of max elevation | Lowlands, plains, valleys |
| `hills` | 40–70% of max elevation | Elevated terrain, rolling hills |
| `mountains` | 70–100% of max elevation | Mountain ranges, peaks |

These thresholds are configurable parameters. The heightmap itself is generated by the terrain generation algorithm (noise-based, with erosion) defined in a future `gdd-terrain-heightmap.md`.

### 8.2 Elevation and Water

- Hexes at 0% elevation adjacent to ocean are coastal (`ocean` water tag)
- Hexes below a "sea level" threshold are ocean hexes (biome irrelevant, elevation irrelevant)
- Rivers flow downhill from high elevation to low; hexes along the river path get the `river` water tag

---

## 9. Complete Tag-to-Table Reference

For quick implementation reference, here is the complete mapping from tag combinations to encounter table columns:

| Elevation | Biome | Water | Civilization | Encounter Table |
|---|---|---|---|---|
| any | any | any | city | City |
| any | any | any | civilized | Inhabited |
| any | any | any | borderlands | 50% Inhabited / 50% natural |
| flat | clear | — | wilderness | Clear, Grass, Scrub |
| flat | woods | — | wilderness | Woods |
| flat | jungle | — | wilderness | Jungle |
| flat | swamp | — | wilderness | Swamp |
| flat | desert | — | wilderness | Barren, Desert |
| hills | clear | — | wilderness | 40% Clear / 60% Mountains, Hills |
| hills | woods | — | wilderness | 60% Woods / 40% Mountains, Hills |
| hills | jungle | — | wilderness | 60% Jungle / 40% Mountains, Hills |
| hills | swamp | — | wilderness | 60% Swamp / 40% Mountains, Hills |
| hills | desert | — | wilderness | 60% Barren, Desert / 40% Mountains, Hills |
| mountains | clear | — | wilderness | 40% Clear / 60% Mountains, Hills |
| mountains | woods | — | wilderness | 60% Woods / 40% Mountains, Hills |
| mountains | jungle | — | wilderness | 60% Jungle / 40% Mountains, Hills |
| mountains | swamp | — | wilderness | 60% Swamp / 40% Mountains, Hills |
| mountains | desert | — | wilderness | 60% Barren, Desert / 40% Mountains, Hills |
| any | any | river | (context) | River (when water-relevant) |
| any | any | ocean | (context) | Ocean (when water-relevant) |

**Note:** The 60/40 and 40/60 splits are the default weighting. The `[hills/mountains, clear]` case reverses to 40% Clear / 60% Mountains because "open hills" are more mountain-encounter territory than grassland territory. All other biome + elevation combinations weight toward biome (60%) because the ground cover drives more encounter variety than the elevation alone.

---

## 10. Visual Rendering

Each tag combination maps to a visual tile for hex map rendering. The rendering system needs tiles for all valid combinations:

**Primary visual** is driven by biome (the dominant visual character of the hex):
- `clear` → grassland/farmland art
- `woods` → forest art
- `jungle` → dense tropical forest art
- `swamp` → wetland art
- `desert` → arid/sandy art

**Elevation overlay** modifies the base art:
- `flat` → no overlay
- `hills` → rolling terrain modifier (elevated contour lines or hill silhouettes)
- `mountains` → mountain peaks overlaid on base biome

**Water overlay** adds river lines or coastal edges to the hex.

**Civilization overlay** adds settlement icons, road markings, cultivated-field patterns for settled hexes.

Placeholder rendering can use simple colored hexes with text labels during development. Proper art assets come later.

---

## 11. Integration Points

### 11.1 Consumers

- **Encounter system** — reads hex terrain tags to select encounter table column (§4)
- **Movement system** — reads terrain tags to determine movement cost (§5)
- **Exploration system** — reads terrain for visibility, foraging, getting lost probabilities
- **Region zoom-in** — reads 24-mile hex tags to generate constituent 6-mile hex tags (terrain inheritance with variation)
- **Dungeon/lair placement** — reads territory classification and terrain for placement logic
- **Weather system** — reads Köppen code (stored alongside tags) for weather table selection
- **LLM narration** — receives terrain description for narrative context
- **Domain system** — reads terrain for agricultural productivity, population capacity

### 11.2 Producers

- **Setting generation pipeline** (§14A.2) — produces the initial heightmap, Köppen codes, and biome assignments
- **Deforestation/forestation pass** (§6) — modifies biome tags based on settlement proximity
- **Region zoom-in** — produces 6-mile hex terrain from 24-mile parent terrain

---

## 12. Open Questions

- **Tundra encounters:** Tundra (`ET`) is mapped to `clear` for encounter purposes, but tundra encounters should feel different from temperate grassland. Consider a separate tundra sub-table or weighted creature type modification (more animals, fewer men). Low priority — can be handled as a regional encounter table modifier.
- **Coastal vs. inland ocean:** Should coastal hexes (land hex adjacent to ocean) use a different encounter distribution than open-ocean hexes? ACKS uses one Ocean column for both. Probably fine for v1.
- **Elevation encounter weighting:** The 60/40 biome/elevation split is an initial estimate. Playtesting may reveal that certain combinations feel wrong (swampy mountains might want different weights than forested mountains). These are tunable parameters.

---

## 13. Revision History

- **2026-03-19:** Initial draft. Terrain tag layering system designed. Encounter table selection logic defined from ACKS 1e Wilderness Encounters table. Deforestation/forestation rules defined. Köppen-to-biome mapping established.
