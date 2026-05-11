# GDD: Terrain System and Hex Generation

**Authority:** PROJECT-DESIGNED — the terrain tag system, biome/elevation layering, encounter table selection logic, and deforestation/forestation rules are not derived from any ACKS sourcebook. The encounter tables themselves and movement costs are ACKS rules defined in the XML rules reference library.
**Status:** Draft
**Depends on ACKS rules:** `acore_adventures_and_encounters.xml` (movement costs by terrain), `acore-monster-stocking-rules.xml` (wilderness encounter tables by terrain), `acore-setting-construction-rules.xml` (territory classification, population density), gdd-weather-generation.md
**Modifiable by Claude Code:** Yes — the tag system, generation algorithms, and weighting formulas are all engineering decisions.
**Last updated:** 2026-05-11

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

**Layer C — Water** (derived from hydrology). Ocean and lake are **full-hex** water tiles, mutually exclusive with all land biomes/elevations — they override the land cascade entirely. Rivers are **not** a water-axis value; they live on the per-edge `HexOverlayData` overlay and coexist with any land biome.

| Tag | Encounter Column | Description |
|-----|-----------------|-------------|
| `""` (none) | — | No water tile; land hex. May still carry a river overlay. |
| `ocean` | Ocean | Open sea or coastal-water hex |
| `lake` | Lake (placeholder column) | Inland water body filling the whole hex |

Small islands inside an ocean or lake hex are modeled as Points of Interest, not as a terrain combination. River and road edges are stored on `HexOverlayData` (see §3.3).

**Layer D — Civilization** (derived from domain data):

| Tag | Encounter Column | Threshold |
|-----|-----------------|-----------|
| `city` | City | Hex contains a city (Market Class I-III) |
| `inhabited` | Inhabited | Hex is in civilized or borderlands territory (see §4.3) |

### 3.2 How Tags Combine

A land hex carries exactly **one** elevation tag, exactly **one** biome tag, exactly one civilization tag, and optionally a biome subtype (§3.4) and/or a river/road overlay. A water hex (`water = ocean | lake`) ignores the elevation/biome/subtype axes for resolver purposes.

Examples:
- Open plains: `elevation=flat, biome=clear`
- Forested hills: `elevation=hills, biome=woods`
- Desert mountains: `elevation=mountains, biome=desert`
- Swampy lowlands with river overlay: `elevation=flat, biome=swamp, overlay.river`
- Boreal forest: `elevation=flat, biome=woods, subtype=forest_taiga`
- Tropical volcano: `elevation=mountains, biome=jungle, subtype=mountains_volcanic`
- Broken desert: `elevation=flat, biome=desert, subtype=desert_badlands`
- Coastal water tile: `water=ocean` (biome/elevation/subtype ignored)

### 3.3 Tag Storage

```
HexTerrainData:
  elevation: string          # "flat" | "hills" | "mountains"
  biome: string              # "clear" | "woods" | "jungle" | "swamp" | "desert"
  biome_subtype: string      # "" (parent default) | see §3.4 for full list
  water: string              # "" (none) | "ocean" | "lake"
  civilization: string       # "civilized" | "borderlands" | "wilderness"
  has_city: bool             # True if hex contains a city
  original_biome: string     # Pre-deforestation/forestation biome (preserved for reversal)
  settlement_ids: Array      # Settlements in this hex, if any
  overlay: HexOverlayData    # River/road edges; null = no overlays
```

### 3.4 Biome Subtypes

A biome subtype is an optional refinement of the parent biome (or, for elevation-rooted subtypes, the parent elevation). Subtypes never invent new RAW encounter columns — they remap a hex to an existing column and modify ancillary values (movement cost, navigation TN, encounter distance, lair density column, creature-type tilt). An empty subtype (`""`) preserves the §4–§5 default cascade and is the value for every hex by default.

**Why subtypes:** RAW vocabularies for terrain are descriptive and overlap inconsistently across the encounter-frequency, encounter-distance, navigation, movement, and lair-density tables (see §4 intro). The biome+elevation+water axes alone cannot encode "Badlands" (RAW encounter-distance) or "Forest, Heavy" (RAW encounter-distance) or the GDD-design distinction between Tundra/Savanna/Grassland (all Köppen-mapped to `clear` in §7.1). The subtype axis is the minimum-additional-data layer needed to keep RAW fidelity without inventing new columns.

#### Table 3.4.1 — Subtype Specification

| Subtype | Parent | Allowed elevation | Allowed biome | Enc. column | Movement bucket | Nav TN | Enc. distance | Lair column |
|---|---|---|---|---|---|---|---|---|
| `forest_dense` | woods | any | woods | Woods | x1/2 (jungle-tier) | 7+ | 5d4 yd | mtn/woods |
| `forest_taiga` | woods | any | woods | Woods | x2/3 (woods) | 7+ | 5d8 yd | mtn/woods |
| `mountains_volcanic` | mountains (elev-rooted) | mountains | clear, woods, jungle, desert | Mtn/Hills | x1/2 | 7+ | 4d6×10 yd | mtn/woods |
| `mountains_glacial` | mountains (elev-rooted) | mountains | clear, desert | Mtn/Hills | x1/2 | 7+ | 4d6×10 yd | mtn/woods |
| `clear_tundra` | clear | flat, hills | clear | Clear/Grass/Scrub | x1 | 4+ | 5d20×10 yd | clear/grass |
| `clear_savanna` | clear | flat, hills | clear | Clear/Grass/Scrub | x1 | 4+ | 5d20×10 yd | clear/grass |
| `clear_grassland` | clear | any | clear | Clear/Grass/Scrub | x1 | 4+ | 5d20×10 yd | clear/grass |
| `desert_badlands` | desert | flat, hills | desert | Barren/Desert | x2/3 (hills-tier even on flat) | 7+ | 2d6×10 yd | barren/desert |

Rivers (overlay) and roads (overlay) are allowed on **all** land subtypes. Water tags (`ocean`, `lake`) are mutually exclusive with any subtype — a water hex never has a subtype.

#### Table 3.4.2 — Creature-Type Tilt

When a subtype produces a creature-type tilt, the resolver multiplies the RAW d8 creature-type weights for the resolved column by the multipliers below. Multipliers <1.0 reduce the chance of that type; >1.0 increase it. Unmentioned types use 1.0. An empty tilt (default) uses the RAW column straight.

| Subtype | Tilt |
|---|---|
| `forest_dense` | — (parent woods) |
| `forest_taiga` | Animal ×1.5, Humanoid ×0.75 |
| `mountains_volcanic` | Dragon ×1.5, Unusual ×1.5, Animal ×0.75 |
| `mountains_glacial` | Humanoid ×1.25, Dragon ×1.25, Unusual ×1.25, Insect ×0.25 |
| `clear_tundra` | Animal ×1.5, Humanoid ×0.5, Insect ×0.5 |
| `clear_savanna` | Animal ×1.5, Humanoid ×1.25 |
| `clear_grassland` | — (RAW baseline) |
| `desert_badlands` | — (column itself is Barrens, which already carries the tilt) |

Specific-monster selection within a creature type (the sub-table roll for Men / Animals / Humanoids / Flyers / Swimmers) is the encounter spawner's responsibility and is not modulated by subtype at this layer — the column choice plus creature-type tilt is enough to bias the result toward the desired creature population.

---

## 4. Encounter Table Selection Logic

When the engine rolls a wilderness encounter, it must select which of the 10 ACKS encounter table columns to use. The selection follows a priority cascade:

### 4.1 Priority Cascade

```
1. IF water = ocean → use OCEAN table (100%)
2. ELSE IF water = lake → use LAKE table (100%; placeholder column)
3. ELSE IF hex has_city → use CITY table (100%)
4. ELSE IF hex is civilized → use INHABITED table (100%)
5. ELSE IF hex is borderlands → 50% INHABITED table, 50% natural terrain
6. ELSE (wilderness) → use natural terrain (100%)
```

Ocean and lake short-circuit before territory because they are full-hex water tiles (§3.1).

### 4.2 Natural Terrain Selection

When natural terrain is selected (steps 5–6 above), the hex may have multiple applicable tables. The selection logic:

```
0. IF biome_subtype is set:
   - forest_dense, forest_taiga → Woods column at the same 60/40 split as
     parent `woods` (60% Woods / 40% Mtn/Hills if elevation is hills or
     mountains; 100% Woods if flat).
   - mountains_volcanic, mountains_glacial → 100% Mountains/Hills column.
   - clear_tundra, clear_savanna, clear_grassland → Clear column at the
     parent-clear split (40% Clear / 60% Mtn/Hills if elevation is hills or
     mountains; 100% Clear if flat).
   - desert_badlands → 100% Barren/Desert column. (Note: this differs from
     plain desert+hills/mountains, which is 60/40 Barren/Mtn — badlands
     uses the column without elevation weighting because the subtype itself
     supplies the broken-terrain encounter character.)
   In all subtype cases, the creature-type tilt (Table 3.4.2) is applied
   to the resolved column's d8 weights before the creature-type roll.

1. ELSE IF hex has a river overlay AND encounter involves water context:
   - Use RIVER table.
   (Water context = party is traveling by boat, crossing a river, fishing.)

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
- The hex carries a river overlay and a random check determines the encounter involves the water

For hexes with a river overlay where the party is traveling overland (not interacting with the river), use the normal biome/subtype/elevation selection. The river overlay doesn't automatically replace the biome table — it's contextual.

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

**Subtype overrides** (per Table 3.4.1) replace the biome+elevation calculation:
- `forest_dense` uses x1/2 (jungle-tier), reflecting the RAW Forest Heavy / Jungle pairing.
- `desert_badlands` uses x2/3 (hills-tier) even when elevation is flat, reflecting eroded terrain.
- All other subtypes inherit their parent biome's movement bucket.

When a subtype override and the elevation cascade disagree, the costlier of the two wins (e.g. forest_dense on mountains stays at mountains x1/2).

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

When the generator assigns a biome from Köppen climate, it may also assign a subtype refinement (§3.4). The "default subtype" column gives the most common subtype the generator should produce for that Köppen group; alternatives can override during local variation.


The setting generation pipeline (§14A.2) assigns a Köppen climate code to each hex based on latitude, elevation, and proximity to water. This GDD defines how those codes map to biome tags:

| Köppen Group | Codes | Default Biome | Default Subtype | Notes |
|---|---|---|---|---|
| **Af** — Tropical rainforest | Af | `jungle` | — | Hot, wet year-round |
| **Am** — Tropical monsoon | Am | `jungle` | — | Seasonal heavy rain |
| **Aw** — Tropical savanna | Aw | `clear` | `clear_savanna` | Dry winters, wet summers |
| **BWh/BWk** — Hot/cold desert | BWh, BWk | `desert` | — | Arid; `desert_badlands` for eroded regions |
| **BSh/BSk** — Hot/cold steppe | BSh, BSk | `clear` | `clear_grassland` | Semi-arid grassland/scrubland |
| **Cfa/Cfb/Cfc** — Temperate oceanic/humid | Cfa, Cfb, Cfc | `woods` | `clear_grassland` if open, else — | Temperate forest default |
| **Csa/Csb** — Mediterranean | Csa, Csb | `clear` | `clear_grassland` | Dry summers; scrubland/open woodland |
| **Cwa/Cwb** — Subtropical highland | Cwa, Cwb | `woods` | — | Monsoon-influenced forest |
| **Dfa/Dfb** — Humid continental | Dfa, Dfb | `woods` | `forest_dense` in deep interior | Deciduous/mixed forest |
| **Dfc/Dfd** — Subarctic/boreal | Dfc, Dfd | `woods` | `forest_taiga` | Boreal forest |
| **Dwa/Dwb/Dwc/Dwd** — Monsoon continental | Dwa-Dwd | `woods` | — | Cold monsoon forest |
| **ET** — Tundra | ET | `clear` | `clear_tundra` | Cold treeless plains |
| **EF** — Ice cap | EF | `desert` | — | Permanent ice (or use `mountains_glacial` if elevation=mountains) |

Volcanic and glacial mountain subtypes are assigned by the geological-feature pass during world generation, not by Köppen climate — they require additional inputs (tectonic activity, latitude/elevation combination) that climate alone does not provide.

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
- **Weather system** (gdd-weather-generation.md) — reads Köppen code, elevation tags, and coastal proximity for seasonal climate profile selection and weather generation
- **LLM narration** — receives terrain description for narrative context
- **Domain system** — reads terrain for agricultural productivity, population capacity

### 11.2 Producers

- **Setting generation pipeline** (§14A.2) — produces the initial heightmap, Köppen codes, and biome assignments
- **Deforestation/forestation pass** (§6) — modifies biome tags based on settlement proximity
- **Region zoom-in** — produces 6-mile hex terrain from 24-mile parent terrain

---

## 12. Open Questions

- **Coastal vs. inland ocean:** Should coastal hexes (land hex adjacent to ocean) use a different encounter distribution than open-ocean hexes? ACKS uses one Ocean column for both. Probably fine for v1.
- **Elevation encounter weighting:** The 60/40 biome/elevation split is an initial estimate. Playtesting may reveal that certain combinations feel wrong (swampy mountains might want different weights than forested mountains). These are tunable parameters.
- **Creature-type tilt magnitudes:** The multipliers in Table 3.4.2 are first-pass estimates. Playtest may indicate that taiga's Humanoid ×0.75 is too soft (boreal forest is famously human-sparse) or that volcanic Dragon ×1.5 is too aggressive. All tilt values are tunable.
- **Lake encounter column:** Currently a placeholder ("lake" column). Probably wants to share most of the River column with extra weighting toward Swimmers, but RAW doesn't define this — defer until lake content is needed.

---

## 13. Revision History

- **2026-05-11:** Added biome subtype axis (§3.4) with eight subtypes — forest_dense, forest_taiga, mountains_volcanic, mountains_glacial, clear_tundra, clear_savanna, clear_grassland, desert_badlands. Each subtype carries explicit overrides for encounter column, movement bucket, navigation TN, encounter distance, lair density column, and creature-type tilt. Resolved the §12 Tundra open question. Corrected stale §3.1 Layer C — lake is a full-hex water tag like ocean (not a river-tag value); rivers are overlay data, not a water-axis value. Updated §4.1 cascade to show ocean/lake short-circuiting before territory. Updated §4.2 to apply subtype overrides before the biome/elevation cascade. Updated §5 to note subtype movement overrides. Updated §7.1 to assign default subtypes per Köppen group.
- **2026-03-19:** Initial draft. Terrain tag layering system designed. Encounter table selection logic defined from ACKS 1e Wilderness Encounters table. Deforestation/forestation rules defined. Köppen-to-biome mapping established.
