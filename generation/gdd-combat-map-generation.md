# GDD: Combat Map Generation

**Authority:** PROJECT-DESIGNED — the combat map generation algorithm, terrain-to-map-feature mapping, elevation modeling, and rendering approach are not derived from any ACKS sourcebook. ACKS combat rules (initiative, attack throws, movement, cover, climbing, falling) are defined in the XML rules reference library and applied on top of the generated map.
**Status:** Revised for the voxel architecture — v2 (2026-07-17). The original draft predated the voxel migration and described a 2D elevation-score grid; this revision retargets every section onto `VoxelMapData` / `VoxelCell` and adds the terrain-driven wilderness generator requirements (dynamic heightfields, terrain-keyed obstacles, surface painting, movement-mode gating, spawn-reachability validation, split-map policy).
**Depends on ACKS rules:** `acore_combat_and_wounds.xml` (combat movement, cover penalties, missile range bands, charging, defensive movement), `acore_adventures_and_encounters.xml` (wilderness encounter distance by terrain), `ax_conditions_catalog.xml` (engaged, prone, exhausted, and other combat-relevant conditions)
**Depends on project GDDs:** `gdd-voxel-tactical-architecture.md` (THE tactical grid data model — 5' voxel cells, solidity/feature/floor vocabulary, support rules), `gdd-continuous-geography.md` (hex terrain fields — elevation + biome + subtype + water + civilization), `gdd-dungeon-contiguous-3d.md` (one-movement-predicate rule; `MovementRules` is the single home for ground-step legality), `gdd_combat_behavior_tags.md` (AI engagement profiles, aggression, positioning)
**Implementing files:** `engine/subsystems/generation/battlemap/battle_map_generator.gd`, `battle_map_templates.gd`, `battle_map_obstacle_catalog.gd`, `battle_map_validator.gd`; consumed by `engine/subsystems/session/states/combat_state.gd`; rendered by `scenes/ui/combat/combat_map_renderer_3d.gd` via `scenes/maps/tactical_grid_3d.gd`. Obstacle placeholder key: `docs/tactical-map-obstacle-key.md`.
**Modifiable by Claude Code:** Yes — all algorithms, feature tables, placement logic, and rendering parameters are engineering decisions.
**Last updated:** 2026-07-17

---

## 1. Purpose

Define the procedural generation of tactical battle maps for combat encounters that occur outside of dungeons or building interiors, on the project's unified 5' voxel grid. Dungeons, interiors, and strongholds already have voxel maps and are used directly as the combat map when combat triggers inside them. This GDD covers:

- **Wilderness encounters** — combat triggered by wandering monster checks, lair encounters, or ambushes while traveling overland. The battle map is generated dynamically from the hex's terrain fields: height variation, obstacles, watercourses, and surface painting all keyed to terrain type.
- **Urban encounters** — combat triggered inside a settlement but outside a building interior. (Template defined here; generation deferred — see §6.)

The generated map must support all ACKS combat mechanics (movement, missile fire, cover, charging, defensive movement, engagement, climbing, falling) AND present clean, queryable data to the two downstream consumers that reason about the battlefield: the monster/NPC combat AI pathfinding (future session — more advanced than dungeon wall/door/open pathing) and the line-of-sight/cover resolvers (`VoxelLOS`). Every generation output must be expressible entirely in `VoxelMapData` cell fields plus the small set of extensions defined in §9 — no side-channel data structures that the AI or LOS resolvers would have to learn separately.

---

## 2. When Battle Maps Are Used

### 2.1 Dungeon and Interior Combat — No Generation Needed

When combat triggers inside a dungeon, building interior, or any other space that already has a voxel map, that existing map IS the battle map. No generation occurs, no data conversion occurs (the `VoxelMapData` is shared).

### 2.2 Wilderness Combat — Procedural Generation

When a wilderness encounter triggers combat, the engine generates a temporary battle map from the hex's terrain fields (biome, elevation, biome_subtype, water tag, river adjacency, civilization class). The map is generated at combat trigger time and, by default, discarded after combat resolves.

**Exception — Lair encounters:** a lair's generated battle map persists as campaign data attached to the lair location and is reused on return visits (see §8).

### 2.3 Urban Combat — Procedural Generation (deferred)

Urban street encounters use the Town Street template (§6). Not yet implemented; wilderness combat that triggers in a civilized hex uses the civilized-grassland wilderness template until the urban generator exists.

### 2.4 Pre-Keyed Battle Maps

Specific locations may have hand-authored or previously generated battle maps attached as campaign data (persisted lair maps, stronghold footprints, scripted encounter locations). These override procedural generation — `CombatState` honors a `voxel_map` supplied in its context before invoking the generator.

### 2.5 Stronghold Assaults

Stronghold battle maps are generated by the stronghold construction system, not by this GDD.

---

## 3. Map Geometry

### 3.1 Grid Model

All tactical maps use the voxel grid defined in `gdd-voxel-tactical-architecture.md`: sparse `Vector3i(col, row, level)`-keyed 5-foot cube cells, diamond (isometric) presentation, level = 5 vertical feet. There is no separate battle-map grid type.

### 3.2 Map Dimensions

| Context | World Size | Grid Size | Cell Size |
|---|---|---|---|
| Wilderness battle map | 350' × 350' | **70 × 70 cells** | 5' × 5' |
| Urban battle map | 250' × 250' | 50 × 50 cells | 5' × 5' |
| Dungeon/interior (existing) | Varies | Varies | 5' × 5' |

**v2 change:** wilderness maps shrank ~30% linearly from the original 100 × 100 (500' × 500'). The 500' size was chosen to swallow extreme plains encounter-distance rolls, but in practice those rolls are edge-capped anyway (§7.3) and the extra area was dead space that hurt readability and generation/render cost. At 70 × 70 the map diagonal is ~495', which still contains the full rolled distance for every terrain except plains/desert/mountains outliers, which continue to edge-cap.

### 3.3 Vertical Budget

Wilderness maps use levels 0 through 7 (0'–35' of relief):

| Elevation tag | Typical surface levels | Character |
|---|---|---|
| flat | 0–1 | Small fluctuations; the occasional 5' rise or dip |
| hills | 0–3 | Rolling slopes, walkable almost everywhere, crest lines |
| mountains | 0–7 | Steep grades, bluffs, 10'–25' cliff faces, plateaus |

Levels are relative to the map's lowest carved point (watercourse beds may sit 1–2 levels below the base terrain around them).

---

## 4. Elevation Model

### 4.1 Terrain Columns

Elevation is expressed directly in voxels. For a column at (col, row) with surface height `h`:

- Cells `level 0 .. h-1`: `solidity: "solid"`, `feature: "earth"` — the ground mass. Full stacks are stamped (not just the exposed shell) so LOS rays, climbing checks ("adjacent solid" rule), and burrowing all behave correctly with zero special-casing.
- Cell `level h`: the **surface cell** — `solidity: "air"`, `floor_type` = surface material (§5.4), `feature` = `"open"` or an obstacle feature (§5.5). Walkers stand here; support comes from `floor_type != "none"` per `FallingResolver.has_support`.
- Cells above `h`: absent (sparse default = open air).

### 4.2 Natural Slopes — the ±1 Level Rule

Dungeon ground movement requires a stair/ramp feature for any level change (`MovementRules.connects_via_feature`). Outdoor terrain instead uses **natural slopes**: on a map flagged `natural_slopes = true` (§9.2), a ground walker may step between horizontally-adjacent surface cells whose levels differ by exactly 1 (a 5' grade) with no feature required. The clause lives inside `MovementRules` itself — the project's single movement predicate — so combat pathing, exploration pathing, the reachability validator, and future AI all inherit it from one place.

| Adjacent surface Δlevel | Ground walker | Meaning |
|---|---|---|
| 0 | Free | Flat ground |
| ±1 (5') | Free (natural slope) | Walkable grade |
| ±2+ (10'+) | Blocked | Bluff/cliff — requires the `"climbing"` movement mode, flight, or a generated ramp/switchback |

Pure-vertical movement (same column) still requires a ladder/spiral feature — natural slopes are always diagonal.

Falling: ACKS fall damage is 1d6 per 10' (`FallingResolver`, floor(distance/10) d6), so a 1-level drop (5') deals no damage — consistent with the slope rule. A 2-level drop is damaging terrain; the reachability guarantee (§7.5) never requires one.

### 4.3 Cliff Faces and Climbing

Where adjacent surface levels differ by 2+, the exposed solid cells form a cliff face. Crossing requires the existing `"climbing"` movement mode (air cell adjacent to solid), flight, or a route around. The generator treats deliberate cliff bands as **dividers** (§7.4) and everything else as local texture that the validator may soften (§7.5).

---

## 5. Wilderness Battle Map Templates

### 5.1 Template Selection Inputs

Templates key off the live hex-terrain vocabulary (from `hex_cells` / `HexTerrainData`), not the older draft tag names:

```
biome:          clear | woods | jungle | swamp | desert
elevation:      flat | hills | mountains
biome_subtype:  "" | forest_dense | forest_taiga | mountains_volcanic |
                mountains_glacial | clear_tundra | clear_savanna |
                clear_grassland | clear_steppe | clear_scrub | desert_badlands
water tag:      "" | ocean | lake
river adjacency: HexTerrainData.has_river() (rivers are edge overlays, not a water tag)
civilization:   civilized | borderlands | wilderness
```

Selection pipeline:

```
1. Base template from biome (+ subtype refinements).
2. Elevation tag drives the heightfield profile (§3.3 amplitudes).
3. Water overlays:
   - has_river()        → large watercourse (§5.6)
   - water == "lake"    → pond/shore blob on one map region
   - water == "ocean"   → coastline along one map edge
   - otherwise          → chance of a small watercourse (stream), except deserts
4. Civilization overlay (clear biome): civilized → field boundaries
   (hedgerows, fences, low walls), chance of a farmstead;
   borderlands/wilderness → lone trees, boulders, brush.
5. Subtype overlays: mountains_volcanic → lava flow; tundra/glacial → snow
   surfaces; desert_badlands → mesas and rock; taiga/dense → conifer/denser
   tree coverage.
6. Universal: small chance of ruined wall fragments in ANY locale.
```

### 5.2 Heightfield Profiles

Seeded `FastNoiseLite` heightfield, quantized to integer levels, then feature carving:

| Elevation | Noise amplitude | Post passes |
|---|---|---|
| flat | levels 0–1, long wavelength | Clamp neighbor deltas to ≤1 (everything walkable) |
| hills | levels 0–3, medium wavelength | Clamp deltas to ≤1 except 0–2 short crest steps; ridge/valley shaping |
| mountains | levels 0–6 (+1 for peaks), short wavelength | Allow deltas ≥2 (bluffs); optional escarpment band (§7.4); guarantee walkable switchback routes between major height tiers (validator, §7.5) |

`desert_badlands` uses the hills profile with plateau quantization (flat-topped mesas, sharp 2-level edges).

### 5.3 Obstacle Tables by Terrain

Densities are for the 70 × 70 map; the obstacle catalog (§5.5) defines each feature's passability/LOS/cover data once, shared by generator, renderer, and docs. Counts scale with map area if dimensions change.

**Clear (grassland/savanna/steppe/scrub), civilized:**
| Feature | Density | Notes |
|---|---|---|
| hedgerow | 2–4 lines, 6–18 cells each | Field boundaries; tall, blocks LOS |
| fence | 2–4 lines/enclosure arcs | Low, does not block LOS |
| low_wall | 0–2 lines, 4–10 cells | Low stone, does not block LOS |
| farmstead | 35% chance of 1 | 3×4 to 5×6 solid building footprint + yard fence |
| tree | 2–5 lone | |
| brush | 3–6 patches of 2–5 cells | |

**Clear, borderlands/wilderness:**
| Feature | Density |
|---|---|
| tree (lone) | 2–6 |
| boulder | 2–5 |
| brush | 4–8 patches of 2–6 cells |
| tall grass (floor paint only) | ambient |

**Woods (light forest; `forest_dense`/`forest_taiga` bump density one band):**
| Feature | Density |
|---|---|
| tree | 12–20% of cells, organic clusters with clearings |
| brush | 6–10% of cells, clustered in low ground |
| fallen_log | 2–5 segments of 2–4 cells |
| boulder | 1–3 (hills/mountains only) |

**Jungle:**
| Feature | Density |
|---|---|
| tree | 22–30% of cells |
| brush | 15–20% of cells |
| clearing | exactly 1, 8–15 cells |

**Swamp:**
| Feature | Density |
|---|---|
| shallow pools (water_shallow) | 25–35% of cells, connected blobs |
| deep pools (water_deep) | 3–8% of cells inside shallow zones |
| dead_tree | 4–8 |
| reeds | 6–10 patches of 2–4 cells |
| mud (floor paint) | remaining low ground |

**Desert (rocky/sandy):**
| Feature | Density |
|---|---|
| boulder | 3–6 |
| rock_pile | 2–5 |
| outcrop (multi-cell solid rock) | 1–3 of 3–6 cells |
| scrub | 4–8 |
| NO watercourses | dry by rule |

**Mountains / rocky hills (any biome with elevation mountains):** add boulder 4–8, rock_pile 3–6, outcrop 2–4, scree (gravel floor paint) on steep faces.

**`mountains_volcanic`:** 60% chance of a lava flow — a meandering 1–3 cell wide `lava` band (impassable liquid, damage hazard hook, emissive rendering). A crossing gap is guaranteed unless the flow is the map's rolled divider (§7.4).

**Any locale:** 15% chance of 1–2 `wall_ruined` fragments (3–7 cells, low, LOS-transparent) — old foundations, a collapsed watchtower course.

### 5.4 Surface Painting

Each surface cell's `floor_type` is painted from the template plus local rules (elevation band, slope steepness, water proximity, noise-driven patchiness):

| floor_type | Used for |
|---|---|
| grass | clear/woods base ground (bright/dark patch variation) |
| dirt | worn ground, forest floor, farmstead yards |
| stone | rocky ground, high mountain surfaces, outcrop bases |
| sand | desert base, riverbanks in desert, beaches |
| mud | swamp ground, riverbanks, rain-soaked lowland |
| snow | tundra/glacial surfaces |
| gravel | scree slopes, badlands floors |
| water | the floor of shallow-water cells |
| lava_rock | volcanic ground near lava flows |

The renderer maps floor_type → texture/color (reusing the wilderness hexmap texture set where it fits); the data layer knows only the floor_type string.

### 5.5 Obstacle Catalog (single source of truth)

`battle_map_obstacle_catalog.gd` defines every obstacle feature once: cell stamping (solidity, floor, cover_value, water_depth), LOS class, and the placeholder rendering spec (color + shape code). The human-readable version is maintained at [docs/tactical-map-obstacle-key.md](../docs/tactical-map-obstacle-key.md). Three passability classes exist:

1. **Solid blockers** (tree, boulder, outcrop, hedgerow, farmstead walls, dead_tree): `solidity: "solid"` — block walkers, flyers at that level, and (unless low) LOS.
2. **Low solids** (low_wall, fence, wall_ruined, rock_pile, fallen_log): `solidity: "solid"` but in `VoxelCell`'s low-feature LOS exception list — they block movement through the cell but NOT line of sight, and they grant cover (cover_value 1–3) via `VoxelLOS.get_cover_value`. (Vaulting/climbing over low obstacles is a future enhancement; v1 walkers path around.)
3. **Soft cover** (brush, reeds, scrub): `solidity: "air"`, passable, cover_value 1, LOS-transparent. Difficult-terrain movement cost is deferred to the combat-AI pathfinding session (the BFS is currently uniform-cost); the features are stamped now so the cost layer has data to key off.

### 5.6 Watercourses and Standing Water

Water is expressed per-cell with two feature values plus an integer depth field (§9.1):

- **`water_shallow`** — `solidity: "air"`, `floor_type: "water"`, `water_depth: 0` (less than one voxel of water). Wadeable: any ground walker may enter without swimming. Streams, fords, banks, swamp pools, lake/ocean rims.
- **`water_deep`** — `solidity: "liquid"`, `water_depth ≥ 1` (one or more full 5' voxels of water). Blocks ground walkers; requires the `"swimming"` movement mode (hook, §9.3), flight, or a crossing. River channels, deep pools, open lake/ocean water.

Placement:

- **Small watercourse (stream):** any non-desert template, ~35% chance. 1–2 cells wide, meandering edge-to-edge, ALL shallow — never splits the map. Banks may drop 1 level (walkable slope).
- **Large watercourse (river):** only when the hex is river-adjacent (`has_river()`). 3–5 cells wide, meandering across the map; deep center line(s), shallow edges; banks carved 1 level down. Crossing roll: ford 45% / bridge 20% / none 35%. "None" makes the river a divider → split map (§7.4).
- **Lake / ocean tag:** deep water mass on one region/edge with a shallow rim; one-sided, never a divider by itself.
- **Bigger creatures:** creature size will eventually raise the wadeable threshold (a size-N creature wades `water_depth ≤ f(size)`). The hook exists now (`MovementRules.can_wade(cell, wade_depth_allowance)`); the sizing build session supplies the allowance. Until then all walkers use allowance 0 (shallow only).

---

## 6. Urban Battle Map Template

Unchanged from v1 draft in intent; renumbered dimensions only (50 × 50 cells, level-based building shells). Deferred until after the wilderness generator ships. District-specific variants remain post-v1 (§13.1).

---

## 7. Generation Algorithm

### 7.1 Core Pipeline

```
1. CONTEXT    — receive terrain context (biome, elevation, subtype, water,
                has_river, civilization, terrain_category fallback) + seed.
2. TEMPLATE   — select per §5.1.
3. HEIGHTFIELD— seeded FastNoiseLite → integer surface levels per column,
                elevation-profile shaping + slope clamps (§5.2).
4. WATER      — carve watercourses / lake / ocean; stamp water cells + depth;
                roll crossing (ford/bridge) or divider status.
5. DIVIDER    — mountains/badlands only: optional chasm or escarpment band
                (§7.4) with crossing roll.
6. VOXELIZE   — stamp solid earth stacks + surface cells (§4.1).
7. OBSTACLES  — scatter per template tables (§5.3): Poisson-style min-distance
                for lone features, cluster growth for brush/trees/pools,
                line-walks for hedgerows/fences/walls, rectangle stamp for
                farmstead. Never on water, never inside the party spawn
                clearing, never sealing the guaranteed crossing.
8. SURFACES   — paint floor_type per §5.4.
9. VALIDATE   — reachability analysis + fix-up (§7.5). Stamp component ids.
10. SPAWN ZONES — party anchor + enemy anchor/zone (§7.6); set entry_pos.
11. FINALIZE  — fog all "visible" (open daylight), natural_slopes = true,
                generation_seed recorded → VoxelMapData + result metadata.
```

### 7.2 Encounter Distance Integration

The ACKS Wilderness Encounter Distance table (`acore_adventures_and_encounters.xml` §encounter_distance_table — rolled in `CombatState._roll_encounter_distance_cells`) provides the starting separation. Distances that exceed the 70 × 70 map are edge-capped per §7.3:

| Terrain | Encounter Distance | Fits in 350' map? |
|---|---|---|
| Heavy forest / jungle | 5d4 yards (15'-60') | Always |
| Light forest | 5d8 yards (15'-120') | Always |
| Marsh | 8d10 yards (24'-240') | Always |
| Mountains / desert | 4d6 × 10 yards (120'-720') | Median rolls fit (~420' avg); high rolls edge-cap |
| Plains | 5d20 × 10 yards (150'-3000') | Low rolls fit; most edge-cap |

### 7.3 Handling Extreme Encounter Distances

Unchanged policy: when the rolled distance exceeds the map, monsters are placed at the far edge, party at the near edge — both sides have spotted each other and must close. For very long plains distances where neither side commits, the encounter resolves at overland scale without a battle map.

### 7.4 Split Maps — Policy

A **split map** is one intentionally divided into two mutually-unreachable (for ground walkers) major regions by a river, chasm, or cliff face. Such encounters are ranged-only unless a side can fly, swim, or climb — this is desirable texture, but must stay uncommon.

Rules:

1. A split can ONLY arise from a rolled divider: a river with no ford/bridge (35% of river maps), or a mountains/badlands chasm/escarpment without a ramp (divider roll 15%, of which 30% uncrossed). Ordinary obstacle scatter and heightfield noise must never split the map — the validator repairs accidental splits (§7.5).
2. Expected split-map rates: river-adjacent hexes ~35% of encounters; mountain/badlands hexes ~4–5%; everything else 0%. Global incidence stays well under "ubiquitous."
3. A split map's two major regions must EACH hold ≥25% of the walkable surface (no sliver sides), and both sides get spawn zones (§7.6) — party on one side, monsters on the other.
4. The result metadata flags `is_split` and names the divider so the encounter UI/AI can reason about it.

### 7.5 Reachability Validation (pre-pathfinding)

Run at generation time, before any combatant is placed. This is the guarantee the pathfinding AI builds on:

1. Build the **walkable surface graph**: nodes = standable surface cells (air + support, including shallow water); edges = legal ground steps per `MovementRules.is_ground_step_open` with natural slopes. By construction an edge never requires a climbing throw and never includes a drop ≥2 levels (i.e., no forced falling damage).
2. Flood-fill connected components. Stamp each surface cell's component id into `VoxelCell.zone_index` (reusing the dungeon zone field — documented dual use, §9.1) so ANY downstream consumer can answer "can A ground-walk to B?" with two dictionary reads.
3. **Non-split maps:** the main component must contain ≥85% of walkable surface cells. Smaller components (a boulder top, an islet in a pond, a mesa without a ramp) are legal scenery but are excluded from spawn placement. If the main component is under threshold, repair deterministically: carve 1-level ramp steps through the offending height edges / remove the blocking obstacle cells nearest between the two largest components, re-flood, repeat (bounded iterations).
4. **Split maps:** exactly the two divider-side components are spawn-eligible; each must meet the 25% floor or the divider is downgraded (a ford/ramp is carved) and the map becomes non-split.
5. **Spawn-cell guarantee:** every cell used for ANY combatant spawn (party or monster) lies in a spawn-eligible component. No character can spawn on an isolated pillar, behind a sealed cliff, or on an island in a lake/river (unless that island IS the enemy side of a split map — and then only deliberately).

### 7.6 Spawn Zones

- **Party anchor** = `entry_pos`: a passable surface cell in the (party-side) main component near one map edge, with a cleared radius-2 pocket (no solid obstacles stamped there).
- **Enemy anchor**: a passable surface cell in the enemy-side component at approximately the rolled encounter distance from the party anchor (edge-capped), preferring similar elevation unless the template placed the enemy zone on high ground.
- Both zones are emitted as cell arrays (anchor + nearby passable same-component cells) in the generator result; `CombatState` walks these lists for actual placement instead of probing raw radii.

### 7.7 Seeding and Determinism

One seed drives the entire generation (`hash(encounter_id)` by default; lair maps store their seed). All randomness flows through a single seeded `RandomNumberGenerator` plus seeded `FastNoiseLite` instances — same context + seed ⇒ byte-identical `to_dict()` output. No wall-clock, no global RNG.

---

## 8. Persistence Rules

Unchanged from v1: wandering-monster and urban maps are discarded; lair maps persist attached to the lair location (full `VoxelMapData` via the existing voxel persistence path, plus the generation seed); pre-keyed maps override generation.

---

## 9. Data Model

### 9.1 VoxelCell — battle-map usage and extensions

The battle map introduces NO parallel cell type. Extensions to `VoxelCell`:

- **`water_depth: int = 0`** (serialized) — full voxels of water below the surface of a water cell. 0 on `water_shallow` (wadeable), ≥1 on `water_deep` (swim). 0 and meaningless on dry cells.
- **Low-solid LOS exceptions** — `blocks_los()` returns false for the low obstacle features (`low_wall`, `fence`, `wall_ruined`, `rock_pile`, `fallen_log`) in addition to the existing `arrow_slit`/`window`/`portcullis` exceptions. These cells still block movement (solid) and carry `cover_value`.
- **`zone_index` dual use** — on dungeon maps: room zone membership (DG-C3D §5.3). On battle maps: walkable-component id from §7.5. The map-level `natural_slopes` flag disambiguates which regime a map is in.
- New `feature` vocabulary: `earth` (terrain mass), `tree`, `boulder`, `rock_pile`, `outcrop`, `brush`, `reeds`, `scrub`, `dead_tree`, `fallen_log`, `hedgerow`, `fence`, `low_wall`, `wall_ruined`, `lava`, plus the existing `water_shallow` / `water_deep`. New `floor_type` values per §5.4.

### 9.2 VoxelMapData — extensions

- **`natural_slopes: bool = false`** (serialized) — outdoor-terrain flag. Enables the ±1 natural-slope clause in `MovementRules` and surface-tracking movement in `MovementResolver`. Always false for dungeons/interiors; true for generated wilderness battle maps.
- **`surface_level_at(col, row) -> int`** — topmost standable surface level in a column (−1 sentinel if none). The single helper the renderer (click picking, overlay projection), spawn placement, and movement wrappers use to resolve a 2D cell reference onto the terrain surface.

### 9.3 Movement-Mode Gating

`MovementRules` (the single step-legality home) gains:

- The natural-slope clause (§4.2), gated on `map.natural_slopes`.
- **`can_wade(cell, wade_depth_allowance := 0) -> bool`** — the water-depth gate: a ground walker may enter a water cell when `cell.water_depth <= allowance`. Default allowance 0 = shallow-only, matching "most characters traverse water less than 1 voxel deep without swimming." The creature-size build session will supply per-creature allowances; nothing else changes when it does.
- `MovementResolver._can_enter_3d` gains a `"swimming"` movement-mode branch (liquid water cells passable, `lava` never) as the hook for swim-capable creatures; v1 has no swimmers wired.

### 9.4 Generator Result Contract

`BattleMapGenerator.generate(context) -> Dictionary`:

```
{
  "map":          VoxelMapData,       # natural_slopes=true, fog visible, zone_index stamped
  "party_zone":   Array[Vector3i],    # spawn-eligible cells, anchor first
  "is_split":     bool,
  "divider":      String,             # "" | "river" | "chasm" | "cliff" | "lava"
  "template_key": String,             # e.g. "clear_hills_civilized"
  "components":   int,                # walkable component count after validation
}
```

Enemy placement depends on the encounter-distance roll, which happens at combat
time — so it is resolved by two static helpers rather than pre-baked in the
result: `BattleMapGenerator.pick_enemy_anchor(map, party_anchor, desired_cells,
is_split)` (nearest standable cell to the ideal spot that satisfies the
component rule — party's component normally, the OTHER major component on a
split map) and `BattleMapGenerator.spawn_cells_near(map, anchor, count)`
(nearest-first standable same-component cells for group placement).

`context` keys: `seed:int`, `terrain_category:String` (fallback), and optionally the rich fields `biome`, `elevation`, `biome_subtype`, `water`, `has_river:bool`, `civilization` (attached to `encounter_data` by `SessionRunner.spawn_encounter_data`), `width`/`height` overrides.

### 9.5 The AI / LOS Data Contract

Everything the future combat-AI pathfinder and the LOS/cover resolvers need is answerable from `VoxelMapData` alone:

| Question | Answer source |
|---|---|
| Can a walker stand here? | air + `FallingResolver.has_support` |
| Can a walker step A→B? | `MovementRules.is_ground_step_open` (slope-aware) |
| Can A reach B at all? | `zone_index` equality (surface cells) |
| Does this cell need swimming? | `solidity == "liquid"` + `water_depth` vs. wade allowance |
| Does this cell block sight? | `VoxelCell.blocks_los()` (low solids excepted) |
| How much cover on this shot? | `VoxelLOS.get_cover_value` (max `cover_value` along the ray) |
| Where is the surface? | `VoxelMapData.surface_level_at(col, row)` |
| Is this map slope-walkable? | `VoxelMapData.natural_slopes` |

---

## 10. Line of Sight

`VoxelLOS` (3D DDA, `blocks_los()` per intermediate cell) already handles terrain columns and elevation correctly: ridges block valley-to-valley shots, high ground sees over low obstacles, and the low-solid exception list keeps fences/ruins from blacking out sight while still granting cover through `get_cover_value`. No LOS algorithm changes are required by this GDD; wiring `get_cover_value` into ranged to-hit remains an open combat-system item (§15).

---

## 11. Integration Points

### 11.1 Data Flow

1. `SessionRunner.spawn_encounter_data` attaches terrain context (biome, elevation, subtype, water, has_river, civilization — additive keys) to `encounter_data`.
2. `CombatState.enter` — if no pre-keyed `voxel_map` in context — calls `BattleMapGenerator.generate` with that context and a seed derived from the encounter id, then places the party from `party_zone` and monsters from `enemy_zone` at the rolled ACKS encounter distance.
3. Combat runs on the returned map through the untouched controller/resolver stack.
4. Lair persistence per §8.

### 11.2 Rendering

`combat_map_renderer_3d.gd` (via `TacticalGrid3D` builders) renders:
- All levels present in the map (terrain columns; the level-0-only combat assumption is retired).
- Per-floor-type surface painting (texture/color batches per floor_type).
- Water/lava surfaces reusing the hexmap water treatment (river shader/material) per the project's asset-reuse ruling.
- Obstacle placeholders color/shape-coded from the obstacle catalog ([docs/tactical-map-obstacle-key.md](../docs/tactical-map-obstacle-key.md)) until real assets land.
- Surface-aware click picking and overlay projection via `surface_level_at`.

---

## 12. Godot Implementation Notes

- `FastNoiseLite` + seeded `RandomNumberGenerator` for all generation randomness.
- Generation target: < 200 ms for 70 × 70 (≈5k surface cells + ≈10–20k solid cells worst case in mountains).
- Rendering: MultiMesh batches per level per category (existing pattern); camera bounds computed once from all levels and cached (the per-frame all-positions scan does not survive 20k-cell maps); `ZOOM_MAX` raised to frame the 70-cell diamond.
- The renderer never invents passability — every visual derives from cell fields.

---

## 13. Future Expansion

13.1 District-specific urban templates (unchanged).
13.2 Weather effects on battle maps (precipitation → mud/snow surface swaps, visibility caps) — unchanged plan.
13.3 Time-of-day light sources — unchanged plan.
13.4 Sea battle maps — unchanged plan.
13.5 Difficult-terrain movement costs (brush/mud/scree/shallow water) — lands with the combat-AI pathfinding session on top of the features stamped now.
13.6 Vaulting/climbing low obstacles; swimming creatures; creature-size wade allowances (size build session).

---

## 14. Design Decisions (Resolved)

- **Voxel-native elevation: DECIDED (v2).** Terrain height is whole 5' voxel levels on the shared grid — the old 2.5'-unit elevation score is retired with the 2D model. FFT-style presentation survives via true world-height rendering.
- **70 × 70 wilderness map: DECIDED (v2).** ~30% linear shrink from 100 × 100; edge-capping absorbs extreme encounter distances.
- **Natural slopes as a MovementRules clause, not stamped ramp features: DECIDED (v2).** Slope-walkability is a property of outdoor terrain geometry (±1 level), not of authored features; keeping it in the single movement predicate means zero drift between combat, exploration, validation, and AI.
- **Water as shallow-air / deep-liquid with an integer depth field: DECIDED (v2).** Wading gate = `water_depth ≤ allowance`, defaulting to shallow-only; size systems plug in later without schema changes.
- **Split maps allowed, rare, divider-only: DECIDED (v2)** per §7.4.
- **Obstacle catalog as single source of truth: DECIDED (v2)** — generator stamping, renderer placeholders, and the docs key all read one table.
- **Lava contact: DECIDED (Jedidiah ruling, 2026-07-17).** ACKS 1e has no environmental lava rule (rules corpus searched; the only mention is a monster ability, `rules/le_monster_catalog_2_summary.xml:1522-1533`, lava projection for 2d6 burning — not an environment rule). Project ruling: a creature that contacts a lava surface makes a **saving throw versus Poison & Death**; on a failure it is **instantly killed**; on a success it takes **2d6 fire damage**. Implemented as `FallingResolver.resolve_lava_contact()`; every path that can put a creature in a lava cell resolves it: falls (`resolve_fall()` flags `lava_contact` landings), teleport mishaps, and the **force back** maneuver (2026-07-17 follow-up ruling: a push stopped by a lava flow forces the victim in — the lava contact REPLACES the RAW wall-collision knockdown, and the victim ends at the brink cell either way, never standing in the flow). Overrun moves the attacker through the target, never the target (`rules/acore_combat_and_wounds.xml:633-643`), so it cannot cause lava contact. Voluntary movement can never enter lava (liquid, not wadeable, not swimmable).
- **Lair maps persist, wandering maps do not: DECIDED (v1, unchanged).**
- **Templates not hand-authored maps: DECIDED (v1, unchanged).**
- **No project-invented elevation combat modifiers: DECIDED (v1, unchanged).** Elevation data serves climbing, falling, LOS, and presentation only.

---

## 15. Open Questions

- **Cover wiring:** `cover_value` is stamped and `VoxelLOS.get_cover_value` computes it, but ranged to-hit does not yet consume it. Combat-system session item.
- **Difficult terrain cost:** brush/mud/scree/shallow-water are stamped but the BFS is uniform-cost until the AI pathfinding session adds weighted movement.
- **Vegetation regrowth in persisted lair maps:** still deferred (static maps).
- **Large-creature placement:** the generator keeps spawn pockets obstacle-free but multi-cell occupancy remains a combat-system concern; revisit at the size build session together with wade allowances.

---

## 16. Revision History

- **2026-03-25:** Initial draft. Diamond maps, elevation 0-30 at 2.5'/unit, terrain templates, urban template, persistence rules, FFT-style rendering.
- **2026-07-17:** v2 — voxel-architecture retarget. 70×70 map (30% shrink), voxel-level elevation + natural-slope rule, live hex-terrain vocabulary (subtypes incl. volcanic/badlands/tundra), civilized-clear obstacle set (hedgerows/fences/farmsteads), watercourse model with water_depth + wading gate, split-map policy, reachability validation with component stamping, obstacle catalog + placeholder key doc, movement-mode gating hooks (swim/wade/size), AI+LOS data contract.
