# GDD: Settlement Layout Generation

**Authority:** PROJECT-DESIGNED — the layout generation algorithm is not derived from any ACKS sourcebook. ACKS provides settlement demographics, market class, and service availability rules (defined in the XML rules reference library). This GDD provides the spatial layout those rules populate.
**Status:** Draft
**Depends on ACKS rules:** `acore-setting-construction-rules.xml` (market class, specialist availability, temple counts, settlement size tables, NPC demographics by market class)
**Depends on project GDDs:** `gdd-terrain-system.md` (hex terrain for settlement context), `gdd-setting-generation.md` (settlement placement and population)
**Modifiable by Claude Code:** Yes — all algorithms, parameters, and layout logic are engineering decisions.
**Last updated:** 2026-03-19

---

## 1. Purpose

Generate a settlement map — city blocks, a street graph, districts, POIs, walls, and gates — given a settlement's population, market class, terrain context, and cultural group. The output is the spatial structure that the ACKS settlement stocking procedure (§14A.5 of the design brief) then populates with NPCs, shops, services, and encounters.

The generator must produce settlements that feel like medieval fantasy towns: organic irregular blocks (not grid cities), a street network of avenues and alleys, functional districts, defensive walls for larger settlements, and appropriate scaling from hamlets to major cities.

> **Note:** The street graph is consumed by the travel time calculator in `gdd-settlement-exploration-ui.md`, not rendered as an interactive navigable map. Settlement exploration uses a menu-driven PoI panel overlay; the street graph provides block distances, avenue/alley routing, and encounter frequency data under the hood.

**Critical design constraint:** The ACKS movement model for settlements uses **avenues** (streets around blocks — the primary movement network) and **alleys** (shortcuts through blocks — 1 turn to traverse regardless of block size). The generator must produce a street graph that supports this avenue/alley distinction. See design brief §4.2.

---

## 2. ACKS Constraints

**Market class and population (ACore Ch.10):**

| Market Class | Population (families) | Settlement Type | Approximate Buildings |
|---|---|---|---|
| VI | 75-249 | Small town / Large village | 15-50 |
| V | 250-624 | Large town | 50-125 |
| IV | 625-2,499 | Small city | 125-500 |
| III | 2,500-4,999 | City | 500-1,000 |
| II | 5,000-19,999 | Large city | 1,000-4,000 |
| I | 20,000+ | Metropolis | 4,000+ |

**Thieves' Quarter:** The only mechanically defined district type. Larger towns and cities (Market Class III+) have one. Higher criminal encounter frequency.

**Specialist availability, temple counts, hireling availability:** All driven by market class. These determine what POIs must exist — the layout generator places them spatially but doesn't determine their existence (that's the stocking procedure's job).

**Walls:** Settlements of Market Class IV and better are typically walled. Villages and small towns may or may not be.

---

## 3. Settlement Size Categories

The generator uses five size categories that map to different generation strategies:

| Category | Market Class | Blocks | Strategy | Examples |
|---|---|---|---|---|
| Hamlet | — (< Class VI) | 3-8 | Template-based | Crossroads, riverside cluster |
| Village | VI | 10-25 | Seed growth | Market square with radiating streets |
| Town | V-IV | 25-80 | Ward subdivision | Walled center, market, residential wards |
| City | III-II | 80-250 | Multi-ward with districts | Multiple districts, walls, gates, thieves' quarter |
| Metropolis | I | 250+ | District-first subdivision | Major districts, inner/outer walls, sprawl |

---

## 4. Algorithm Overview

### 4.1 Core Pipeline

```
1. SEED PARAMETERS → settlement size, terrain, culture, coastal/riverside, walled
2. PLACE ANCHOR FEATURES → center point, water features, main road approach
3. GENERATE WARD SEEDS → place seed points for Voronoi partitioning
4. GROW WARDS → expand wards outward from seeds, constrained by terrain/water
5. SUBDIVIDE WARDS INTO BLOCKS → split each ward polygon into city blocks
6. GENERATE STREET GRAPH → avenues from block boundaries, intersections at vertices
7. ASSIGN ALLEY SHORTCUTS → implicit connections through blocks
8. PLACE WALLS AND GATES → defensive perimeter for walled settlements
9. ASSIGN DISTRICT TYPES → label groups of wards
10. PLACE POIs → position points of interest on block perimeters along the street graph
11. GENERATE VERTICAL LAYERS → undercity (sewers, catacombs) and upper levels (sky-districts, elevated walkways) with transition points mapped to surface blocks
12. OUTPUT → SettlementLayout data structure ready for stocking
```

### 4.2 Design Principles

- **Growth from center outward** — settlements grow organically from a nucleus (market square, castle, river crossing, crossroads). Older/wealthier areas are central; newer/poorer areas are peripheral.
- **Terrain-responsive** — rivers, coastlines, and hills shape the settlement. A riverside town elongates along the river. A hilltop town is compact. A coastal town has a harbor district.
- **Organic irregularity** — blocks are irregular polygons, not grid squares. Streets curve. No two settlements look identical.
- **Mechanically navigable** — despite visual irregularity, the street graph is a clean node-and-edge structure that the movement system can traverse.

---

## 5. Hamlet Generation (Template-Based)

Hamlets are too small for procedural ward generation. Use templates instead.

### 5.1 Hamlet Templates

Each template defines a fixed arrangement of buildings and paths:

**Crossroads Hamlet** (3-6 buildings):
```
- Two roads cross at center
- Buildings placed at 2-3 of the 4 quadrants
- One building is the prominent structure (inn, mill, or chapel)
- No walls, no formal blocks
```

**Riverside Hamlet** (4-8 buildings):
```
- Buildings line one or both banks of a river
- A bridge or ford at center
- Path runs parallel to river connecting buildings
- Possible: a mill on the river, a dock
```

**Hilltop Hamlet** (3-6 buildings):
```
- Buildings clustered at the top of a rise
- Single winding path up from the road
- One prominent building (watchtower, chapel, manor house)
```

**Roadside Hamlet** (3-5 buildings):
```
- Buildings along one side of a road
- One is a waystation or tavern
- Minimal street structure — just the main road
```

**Cluster Hamlet** (4-8 buildings):
```
- Buildings around a central open area (village green, well, pond)
- Paths radiate outward to surrounding fields
- Most organic/random arrangement
```

The generator selects a template based on terrain context (river = riverside, hill = hilltop, road junction = crossroads, etc.) and places buildings with randomized positions within the template's constraints.

For hamlets, there are no formal blocks or street graphs — the movement model falls back to simple point-to-point navigation between buildings.

---

## 6. Village and Town Generation (Seed Growth)

### 6.1 Ward Seed Placement

Wards are the intermediate spatial unit between "the whole settlement" and "individual blocks." Each ward becomes a cluster of 3-8 blocks.

**Procedure:**

```
1. Place the ANCHOR ward seed at the settlement center:
   - Crossroads settlement: at road intersection
   - Riverside: at the river bank or bridge
   - Coastal: at the harbor
   - Hilltop: at the hill crest
   - Default: at the geographic center

2. Calculate target ward count from settlement size:
   - Village: 3-6 wards
   - Town: 6-15 wards
   - City: 15-40 wards
   - Metropolis: 40-80 wards

3. Place additional ward seeds outward from the anchor:
   - Use a Poisson disk sampling pattern for even spacing
   - Minimum distance between seeds scales with settlement size
   - Seeds placed along major approach roads get priority
   - River/coast features attract seeds (waterfront wards)
   - Seeds avoid terrain obstacles (water, steep slopes)

4. Add jitter to seed positions (±15-25% of spacing distance)
   for organic irregularity
```

### 6.2 Ward Boundary Generation (Voronoi)

```
1. Compute Voronoi diagram from ward seed points
   - Use Fortune's algorithm or incremental insertion
   - Clip to settlement boundary (circular + terrain mask)
2. Relax boundaries with 2-3 iterations of Lloyd relaxation
   (move each seed toward its cell centroid, recompute Voronoi)
   - This produces more evenly-sized wards while keeping irregularity
3. Snap ward boundaries to terrain features where close:
   - River within 1 cell width of a boundary → boundary follows river
   - Coastline within 1 cell → boundary follows coast
   - Major road within 1 cell → boundary follows road
4. Each ward is now an irregular polygon
```

### 6.3 Block Subdivision Within Wards

Each ward polygon is subdivided into city blocks:

```
1. For each ward:
   a. Calculate target block count from ward area:
      - Dense wards (central, commercial): 5-8 blocks per ward
      - Normal wards (residential): 3-6 blocks per ward
      - Sparse wards (industrial, outskirts): 2-4 blocks per ward
   
   b. Place block seed points within the ward polygon:
      - Poisson disk sampling within the polygon boundary
      - Seeds biased toward the ward center (denser center, sparser edges)
   
   c. Compute sub-Voronoi within the ward boundary:
      - Voronoi of block seeds, clipped to the ward polygon
      - 1-2 Lloyd relaxation iterations
   
   d. Each resulting cell is a city block polygon

2. Post-process blocks:
   - Merge any block smaller than minimum size with its largest neighbor
   - Split any block larger than maximum size along its longest axis
   - Minimum block size: ~2,000 sq ft (a few buildings)
   - Maximum block size: ~40,000 sq ft (before it feels like empty space)
```

---

## 7. Street Graph Generation

### 7.1 Avenues from Block Boundaries

The street network emerges naturally from the negative space between blocks:

```
1. For each shared edge between two adjacent blocks:
   - This edge IS an avenue segment

2. For each vertex where 3+ block corners meet:
   - This vertex IS an intersection node

3. Build the graph:
   - Nodes = all intersections + settlement entry points (gates, road entries)
   - Edges = avenue segments connecting adjacent nodes
   - Each edge stores: connecting nodes, length (from geometry), 
     bordering block IDs (left and right)

4. Ensure connectivity:
   - Run a graph connectivity check (BFS/DFS from any node)
   - If disconnected components exist, add bridge avenues to connect them
   - This can happen when terrain features (river) split the settlement
```

### 7.2 Avenue Classification

Not all streets are equal. Classify avenues by importance:

```
1. MAIN ROADS: Avenues that continue the approach roads into the settlement
   - Identified by tracing approach road direction into the street graph
   - These are wider, busier, more commercially important

2. SECONDARY AVENUES: Streets connecting main roads to each other
   - Identified as shortest paths between main road segments
   - Medium importance

3. MINOR AVENUES: All remaining streets
   - Typically residential side streets
   - Narrower, quieter

Classification affects:
- POI placement priority (shops prefer main roads)
- Encounter frequency (more traffic on main roads)
- Visual rendering (wider drawn lines for main roads)
```

### 7.3 Alley Shortcuts

Per the design brief §4.2, alleys are implicit connections through blocks:

```
For each block:
1. IF block.alley_traversable == true (most blocks; walled compounds = false):
   a. For each pair of avenue nodes on opposite sides of the block:
      - Add an implicit alley edge to the street graph
      - Alley edge cost = 1 turn (fixed, regardless of block size)
      - Alley edges are NOT drawn on the map as paths
      - They ARE available as movement options ("Cut through block")
   b. Typically 1-2 alley shortcuts per block (connecting most-distant 
      perimeter nodes)
```

---

## 8. Settlement Shape and Terrain Response

### 8.1 Settlement Boundary

The overall settlement shape is controlled by a boundary mask applied before ward generation:

```
Base shape: elliptical, centered on anchor point
  - Aspect ratio: 1.0 (circular) for hilltop/no-feature settlements
  - Aspect ratio: 1.5-2.0 (elongated) along rivers or coastlines
  - Aspect ratio: 1.3 (slightly elongated) along major roads

Terrain modifications:
  - River: boundary follows river on one side, extends opposite
  - Coast: boundary truncated at coastline, harbor indent
  - Hill: boundary compressed to hilltop area (smaller but denser)
  - Multiple roads: boundary extends along each approach road (star shape)
  - Bridge/ford: settlement may extend to both banks (two lobes connected)

Size scaling:
  - Boundary radius scales with sqrt(target_block_count)
  - This maintains roughly constant density as settlements grow
```

### 8.2 Water Features

```
Rivers:
  - River cuts through the settlement boundary
  - Blocks adjacent to the river are waterfront blocks
  - Bridges placed at 1-3 points (more for larger settlements)
  - Bridge locations become major intersection nodes
  - Waterfront blocks get dock/warehouse/fishmarket POI bias

Coast:
  - Settlement boundary truncated at coastline
  - Harbor area: concave indent in the coastline, 3-8 waterfront blocks
  - Harbor blocks get dock/warehouse/shipyard/fish market bias
  - Main gate faces inland; harbor gate faces the water
```

---

## 9. Walls and Gates

### 9.1 Wall Placement

Settlements of Market Class IV+ are typically walled:

```
1. Compute the convex-ish hull of all block polygons
   (convex hull with concavity tolerance — follows block perimeters 
   rather than cutting across them)
2. Smooth the hull to produce a wall path
3. Place towers at wall vertices (corners) and at regular intervals
4. Wall path becomes a drawn feature on the settlement map
5. Blocks inside the wall = "inner city"
6. For cities with sprawl beyond the walls:
   - Inner wall encloses the original settlement
   - Outer blocks (shanty towns, suburbs) lie outside the wall
   - Metropolises may have concentric walls (inner wall + outer wall)
```

### 9.2 Gate Placement

```
1. Place gates where major approach roads meet the wall
   - One gate per approach road (typically 2-4 gates)
2. Each gate is a node in the street graph connecting inner and outer networks
3. Gates are named POIs (e.g., "North Gate," "River Gate," "King's Gate")
4. For walled settlements, entry to the settlement requires passing through a gate
   (this matters for the movement system and for encounter triggers)
```

---

## 10. District Assignment

### 10.1 Procedure

After wards and blocks are generated, group wards into districts:

```
1. Assign the CENTER ward(s) as the MARKET district
   - 1-3 wards closest to the anchor point
   - Commercial, high-traffic, main POIs

2. IF settlement has a castle/citadel:
   - Assign 1-2 wards as CASTLE district
   - Typically at the highest elevation or most defensible position
   - For a hilltop town: the hilltop ward
   - For a riverside town: on a bluff or island

3. IF settlement is Market Class III+ (city):
   - Assign 1-3 peripheral wards as THIEVES' QUARTER
   - Located away from the market and castle
   - Typically near the walls or outside them
   - Higher criminal encounter frequency (ACKS rule)

4. IF settlement has waterfront wards:
   - Assign them as DOCKS/HARBOR district

5. IF settlement has a major temple (from ACKS temple count):
   - Assign 1-2 wards as TEMPLE district
   - Near the center but not the market wards

6. Assign remaining wards:
   - Wards adjacent to the market: MERCHANT/CRAFTSMEN
   - Wards between center and walls: RESIDENTIAL
   - Wards at the periphery or outside walls: OUTSKIRTS/SLUMS
   - Wards along major approach roads: GATE DISTRICT
```

### 10.2 District Types and Encounter Effects

| District Type | POI Bias | Encounter Character | Notes |
|---|---|---|---|
| Market | Shops, merchants, money-changers | Commercial, busy, pickpockets | Settlement center |
| Castle | Garrison, barracks, armory | Military, patrols | Fortified area |
| Thieves' Quarter | Fences, gambling dens, black market | Criminal, dangerous | ACKS mechanical type |
| Docks/Harbor | Warehouses, shipwrights, taverns | Sailors, smugglers, foreign traders | Waterfront only |
| Temple | Temples, monasteries, healers | Religious, peaceful | Major religious structures |
| Craftsmen | Workshops, smiths, tanners | Working-class, industrious | Near market |
| Residential | Houses, small shops, inns | Domestic, quieter | Bulk of the settlement |
| Outskirts | Farms, hovels, stables | Rural, poorer | Outside or at walls |

Districts are freeform labels (per design brief §4.2), not a rigid taxonomy. The generator assigns types based on ward position and settlement features. Players and the LLM can rename districts.

---

## 11. POI Placement

### 11.1 Recommended POIs by Settlement

ACKS recommends the following points of interest for most settlements. The number and grandeur scale with settlement size and market class:

| POI Type | Description | Placement Bias | Market Class Threshold |
|---|---|---|---|
| Barracks / Watch House | Military garrison, city watch, legion post | Castle district or gate district | VI+ (every settlement has some guard presence) |
| Tavern / Inn / Bathhouse / Bawdyhouse | Rumor-gathering, gold-spending, social hubs | Distributed across all districts; main roads preferred | VI+ (at least 1 tavern per settlement) |
| Dock / Harbor | Maritime hub, fishing, shipping | Waterfront blocks only | Only if riverside or coastal |
| Emporium / Bazaar / Market | Equipment purchase, merchandise | Market district, main road frontage | VI+ (at least a general store) |
| Merchant's Guildhouse / Bank | Investing, lending, trade contracts | Market district | V+ |
| Mercenary's Guildhouse | Hireling recruitment, mercenary contracts, job board | Near market or gate district | IV+ |
| Municipal Building / Palace / Court | Seat of government, legal proceedings | Castle district or market center | V+ (village elder's house at VI) |
| Temple | Worship, healing, divine services | Temple district or market district | See §11.2 Temple Rule |
| Thieves' Quarter | Criminal syndicate, fences, black market, assassination contracts | Peripheral wards, away from castle/market | III+ (ACKS mechanical type) |
| Tower of Knowledge / Wizard's College | Arcane study, sage consultation, spell research | Near temple district or castle district | III+ |

### 11.2 Temple Count Rule

The number of temples in a settlement is directly tied to the cleric population:

```
1. Determine the number of clerics level 6+ in the settlement
   (from ACKS NPC demographics by market class, defined in XML rules reference)
2. Each cleric level 6 or higher has their own temple → 1 temple per 6+ cleric
3. Clerics below level 6 are apprenticed to a level 6+ cleric's temple
4. Exception: if the settlement has NO cleric level 6+, the highest-ranking 
   cleric (whatever level) runs the settlement's single temple
5. Minimum: 1 temple per settlement (even a hamlet has a shrine or chapel)
```

This means a Market Class III city with three 7th-level clerics and one 9th-level cleric has **4 temples**. A Market Class V town with one 6th-level cleric and two 3rd-level clerics has **1 temple** (the 6th-level cleric's, with the two juniors as apprentices).

Temple placement priority: the highest-level cleric's temple is placed in the most prominent location (temple district center or market square). Additional temples are distributed across remaining districts.

### 11.3 POI Scaling by Market Class

| Market Class | Taverns/Inns | Shops/Vendors | Temples | Guilds | Military | Criminal |
|---|---|---|---|---|---|---|
| VI | 1 | 1-2 | 1 (chapel) | 0 | 1 (watch post) | 0 |
| V | 2-3 | 3-6 | 1-2 | 1 (merchants) | 1 (barracks) | 0 |
| IV | 3-5 | 8-15 | 2-3 | 2 (merchants + mercenary) | 1-2 | 0 |
| III | 5-10 | 15-30 | 3-5 | 3+ | 2-3 | 1 (thieves' quarter) |
| II | 10-20 | 30-60 | 5-10 | 5+ | 3-5 | 1-2 |
| I | 20+ | 60+ | 10+ | 8+ | 5+ | 2+ |

These counts are guidelines. Exact numbers are determined by the stocking procedure from the XML rules reference (NPC demographics drive temple count per §11.2; market class drives service availability). The layout generator reserves placement capacity for these POI counts.

### 11.4 POI Placement Procedure

```
1. Receive POI list from stocking procedure (type, count, importance)

2. Place POIs in priority order (most important first):
   a. Municipal building → castle or market district center
   b. Main temple (highest-level cleric) → temple district center or 
      market square, prominent main-road position
   c. Additional temples → temple district, then distributed
   d. Barracks → castle district or main gate
   e. Merchant guild / bank → market district, main road
   f. Mercenary guild → near market or gate, main road
   g. Thieves' quarter POIs → thieves' quarter district
   h. Tower of knowledge → near temple or castle district
   i. Emporium / main market → market district center
   j. Docks → waterfront blocks
   k. Taverns / inns → distributed, bias toward main roads and gate areas
   l. Remaining shops → market and craftsmen districts, then distributed

3. For each POI:
   a. Select a block in the target district
   b. Select an avenue node on that block's perimeter
   c. Prefer main road and secondary avenue nodes for commercial POIs
   d. Prefer minor avenue nodes for residential POIs
   e. Record: POI at this node, on this block's perimeter, facing this avenue

4. Track node occupancy — don't stack POIs on the same node
   (spread them along block perimeters)
```

### 11.5 POI Data

```
POI:
  id: string
  name: string                    # "The Red Lantern Tavern" (from stocking/LLM)
  type: string                    # "tavern", "temple", "shop", "guild", etc.
  subtype: string                 # "weapon_shop", "temple_of_war", "thieves_guild", etc.
  block_id: int                   # Which block it's on
  street_node_id: int             # Which street graph node (its "address")
  avenue_segment_id: int          # Which avenue it faces
  district_id: string             # Which district it belongs to
  layer: string                   # "surface", "upper_1", "undercity_1", etc.
  importance: string              # "major", "minor" — affects rumor/NPC reference frequency
  associated_npc_id: string       # E.g., the temple's head cleric, the guild master
  contents: null                  # Interior developed on interaction per city stocking rules
```

---

## 12. Vertical Layer Generation

All vertical layers are generated up front during settlement creation. Connection points between layers are mapped to specific surface blocks, and POIs on sub-surface or upper layers are registered in the settlement data so they can be referenced in rumor tables and NPC dialogue from the start.

### 12.1 Layer Types

| Layer | Exists When | Description |
|---|---|---|
| Surface | Always | The main settlement map (all blocks, streets, walls) |
| Undercity Level 1 (Sewers) | Market Class IV+ | Sewer tunnels beneath the streets; connects to thieves' quarter |
| Undercity Level 2 (Catacombs) | Market Class III+ or temple district | Deeper tunnels; burial chambers, smuggler routes, hidden shrines |
| Undercity Level 3+ (Deep) | Market Class II+ or special | Ancient ruins, underground rivers, deep dungeons beneath the city |
| Upper Level 1 | Special (cliff cities, tree cities, magical) | Elevated walkways, sky-bridges, upper-tier districts |

### 12.2 Undercity Generation

```
1. SEWER NETWORK (Undercity Level 1):
   a. For each main road and secondary avenue on the surface:
      - Create a corresponding sewer tunnel beneath it
      - Sewer follows the same path but as a simplified corridor
   b. Place sewer access points (grates, manholes):
      - 1 per 5-8 blocks in the surface layout
      - At least 1 in the thieves' quarter
      - At least 1 near the docks (if present)
      - Each access point is a transition node linking surface ↔ undercity
   c. Place sewer POIs:
      - Thieves' guild secondary entrance
      - Smuggler stash rooms (1-3)
      - Sewer junction rooms (larger open areas at major intersections)
   d. The sewer map uses the dungeon grid format (5' squares)
      not the surface block format
   e. All undercity levels use the `DoorData` schema from `gdd-dungeon-layout.md`,
      including `door_material` and `is_evil` fields required by the dungeon
      interaction system (`gdd-dungeon-map-ui.md`)

2. CATACOMBS (Undercity Level 2, if applicable):
   a. Beneath the temple district and/or castle district
   b. Generated using the dungeon layout generator (gdd-dungeon-layout.md)
      with type = "Catacombs" and size = small-to-medium
   c. Connected to the sewer level via stairs/ladders at 1-2 points
   d. Connected to the surface via a temple crypt entrance or castle cellar
   e. POIs: burial chambers, hidden shrine, possible undead lair

3. DEEP LEVELS (Undercity Level 3+, if applicable):
   a. Generated as full dungeon levels using gdd-dungeon-layout.md
   b. Connected to catacombs via stairs/shafts
   c. These are effectively dungeons beneath the city
   d. The "one large dungeon beneath a major settlement" from the dungeon
      placement rules (gdd-setting-generation.md §9.3) connects here
```

### 12.3 Transition Point Data

```
TransitionPoint:
  id: string
  surface_block_id: int          # Which surface block this is in/near
  surface_node_id: int           # Street graph node (if accessible from a street)
  source_layer: string           # "surface", "undercity_1", etc.
  target_layer: string           # "undercity_1", "undercity_2", etc.
  type: string                   # "sewer_grate", "cellar_stairs", "crypt_entrance",
                                 #  "ladder", "magical_lift", "hidden_passage"
  position_on_target: Vector2    # Where you arrive on the target layer
  visibility: string             # "obvious", "hidden", "secret"
  locked: bool                   # Requires a key or action to use
```

### 12.4 Cross-Layer POI Referencing

POIs on non-surface layers are registered in the settlement's master POI list with their `layer` field set appropriately (e.g., `"undercity_1"`). This means:

- Rumor tables can reference "the thieves' guild beneath the docks" even if the player hasn't been there
- NPCs can give directions: "go through the sewer grate behind the fishmonger's stall, then follow the left tunnel"
- Quest hooks can point to undercity/upper-level locations from the start of play

---

## 13. Output Data Structure

```
SettlementLayout:
  settlement_id: string
  name: string
  market_class: int               # I through VI
  population_families: int
  terrain_context: string         # "riverside", "coastal", "hilltop", "crossroads", "plain"
  
  bounds: Rect2                   # Bounding rectangle of the settlement
  
  blocks: Array[BlockData]
  # BlockData:
  #   id: int
  #   polygon: Array[Vector2]     # Vertices of the block boundary
  #   ward_id: int                # Which ward this block belongs to
  #   district_id: string         # Which district
  #   block_type: string          # Freeform label
  #   alley_traversable: bool     # Can alleys be used to cross this block?
  #   pois: Array[int]            # POI IDs on this block's perimeter
  #   waterfront: bool            # Adjacent to river/coast?
  
  street_graph: StreetGraph
  # StreetGraph:
  #   nodes: Array[StreetNode]
  #   edges: Array[StreetEdge]
  #
  # StreetNode:
  #   id: int
  #   position: Vector2
  #   type: string               # "intersection", "gate", "entry", "poi"
  #   poi_id: int or null        # If this node is a POI location
  #
  # StreetEdge:
  #   id: int
  #   node_a: int                # Connecting node IDs
  #   node_b: int
  #   type: string               # "main_road", "secondary", "minor", "alley"
  #   length: float              # In map units (for movement cost)
  #   left_block_id: int         # Block on the left side
  #   right_block_id: int        # Block on the right side
  
  districts: Array[DistrictData]
  # DistrictData:
  #   id: string
  #   name: string               # "Market District", "Dockside", etc.
  #   type: string               # From §10.2 table
  #   ward_ids: Array[int]       # Wards in this district
  #   encounter_modifier: string # Normal, elevated (thieves' quarter)
  
  walls: WallData or null
  # WallData:
  #   path: Array[Vector2]       # Wall path vertices
  #   towers: Array[Vector2]     # Tower positions
  #   gates: Array[GateData]
  #   inner_wall: bool           # Is there an inner wall? (metropolises)
  #
  # GateData:
  #   position: Vector2
  #   street_node_id: int        # Node in the street graph
  #   name: string               # "North Gate", etc.
  #   approach_road_direction: string  # Which direction this gate faces
  
  water_features: WaterFeatures or null
  # WaterFeatures:
  #   river_path: Array[Vector2] or null
  #   coastline: Array[Vector2] or null
  #   bridges: Array[BridgeData] or null
  #   harbor_blocks: Array[int]  # Block IDs in the harbor area
  
  pois: Array[POI]               # All POIs across all layers (see §11.5)
  
  vertical_layers: Array[VerticalLayer]
  # VerticalLayer:
  #   id: string                   # "surface", "undercity_1", "undercity_2", "upper_1"
  #   name: string                 # "Sewers", "Catacombs", "Sky Bridge District"
  #   layer_type: string           # "surface", "undercity", "upper"
  #   depth: int                   # 0 for surface, -1 for undercity_1, -2 for undercity_2, +1 for upper_1
  #   map_type: string             # "settlement" (block-based) or "dungeon" (grid-based)
  #   blocks: Array[BlockData]     # If map_type == "settlement"
  #   dungeon_layout_id: string    # If map_type == "dungeon" (references a DungeonLayout)
  #   pois: Array[int]             # POI IDs on this layer
  
  transition_points: Array[TransitionPoint]  # See §12.3
  
  generation_seed: int
  culture_id: string              # Cultural group (for name generation, architecture style)
```

---

## 14. Godot Implementation Notes

### 14.1 No Built-In Settlement Generation

Godot provides no settlement or city generation tools. The entire algorithm is pure GDScript operating on `Vector2` arrays and `Dictionary` structures. Rendering uses Godot's `Polygon2D` for block fills, `Line2D` for streets and walls, and the street graph drives the party movement system.

### 14.2 Voronoi Implementation

Godot does not include a Voronoi library. Options:

1. **Implement Fortune's algorithm in GDScript** — well-documented, O(n log n), straightforward to port. Recommended for correctness and control.
2. **Use Delaunay triangulation (dual of Voronoi)** — compute Delaunay, then derive Voronoi cells. Godot's `Geometry2D` class has some triangulation helpers but not full Delaunay.
3. **Approximate with iterative relaxation** — start with random cells, iteratively adjust boundaries. Simpler but slower and less precise.

**Recommendation:** Implement Fortune's algorithm. It's a one-time cost, runs fast for the cell counts we need (< 100 seeds), and produces exact Voronoi boundaries that block subdivision and street generation depend on.

### 14.3 Key Godot Classes

- `Polygon2D` — renders block fills and wall outlines
- `Line2D` — renders streets, rivers, walls
- `Geometry2D` — polygon clipping, point-in-polygon tests, convex hull
- `AStar2D` — pathfinding on the street graph (for party movement and NPC navigation)
- `RandomNumberGenerator` — seeded RNG for reproducible generation

### 14.4 File Organization

```
engine/subsystems/generation/settlement_layout/
  settlement_generator.gd       # Main generator orchestrating the pipeline
  hamlet_templates.gd            # Template definitions for hamlets
  ward_generator.gd              # Ward seed placement + Voronoi
  block_subdivider.gd            # Ward → block subdivision
  street_graph_builder.gd        # Avenue/alley graph from block boundaries
  wall_generator.gd              # Walls, towers, gates
  district_assigner.gd           # District type assignment
  poi_placer.gd                  # POI positioning on block perimeters
  voronoi.gd                     # Fortune's algorithm implementation
  settlement_templates.json      # Hamlet template data
```

---

## 15. Scaling Examples

### 15.1 Village (Market Class VI, ~150 families)

```
- 4 wards, 15 blocks total
- No walls
- 1 district (the whole village)
- Main road passes through, market square at center
- POIs: 1 tavern/inn, 1 temple, 1 general store, 1 blacksmith, village elder's house
- Hamlet-to-village transition: big enough for blocks and streets, 
  small enough to traverse quickly
```

### 15.2 Town (Market Class IV, ~1,000 families)

```
- 10 wards, 50 blocks total
- Walled with 3 gates
- 3 districts: Market, Residential, Outskirts
- Main road bisects the town, secondary avenues connect districts
- POIs: 3-4 taverns, 2 temples, 10-15 shops, guild hall, town hall, barracks
- 10-15 minute play traversal from gate to gate
```

### 15.3 City (Market Class II, ~8,000 families)

```
- 30 wards, 180 blocks total
- Walled with inner and outer sections, 5 gates
- 6 districts: Market, Castle, Temple, Docks, Craftsmen, Thieves' Quarter
- Complex street network with main roads, secondary avenues, many minor streets
- POIs: 15+ taverns, 6 temples, 50+ shops, multiple guilds, government buildings,
  thieves' guild, fences, black market
- Major play area — multiple sessions' worth of content
```

---

## 16. Design Decisions (Resolved)

- **Building-level detail: DECIDED.** Individual buildings within blocks are artistic representations only, not mechanically significant. The movement and interaction systems operate at block level (avenues between blocks, alleys through blocks). Individual buildings are rendered as visual fill within block polygons but are NOT discrete game entities. A building becomes a developed game entity only when interacted with — when a player enters a shop, the stocking procedure generates its interior, inventory, and NPC per the city stocking rules in the XML rules reference. Until then, it's just art.

- **Vertical layers: DECIDED.** The generator produces ALL vertical layers up front (surface, upper levels, undercity levels) during initial settlement generation. This is necessary because connection points (stairs, sewer grates, ladders, magical lifts) between layers must be properly mapped at generation time, and POIs on sub-surface or upper layers must be referenceable in rumor tables and NPC dialogue from the start. An undercity thieves' guild or an upper-level sky-temple needs to exist in the data even before the player visits it, so NPCs can talk about it and rumors can point to it.

- **Settlement growth: DECIDED.** Growth during campaigns is numeric data only (population count, market class changes, revenue adjustments) — it does NOT add blocks or alter the map layout in v1. Settlements are generated once and their spatial layout is fixed. Growth is slow enough in ACKS that this is rarely an issue during typical campaign timescales. Physical expansion of the map layout is deferred to post-v1.

---

## 17. Revision History

- **2026-03-19:** Initial draft. Ward-based Voronoi subdivision with block sub-partitioning. Street graph derived from block boundaries. Five settlement size categories with template-based hamlets. ACKS market class integration. Avenue/alley movement model supported.
- **2026-03-19 (rev 2):** All open questions resolved. Vertical layers generated up front with mapped transition points and cross-layer POI referencing. Individual buildings are artistic only, developed on interaction. Settlement growth is numeric-only in v1. ACKS recommended POI list integrated with market class scaling. Temple count rule based on 6th+ level cleric population. POI placement procedure expanded with priority ordering and district assignment.
- **2026-04-14:** Removed "navigable" framing from §1 — street graph is consumed by travel time calculator (`gdd-settlement-exploration-ui.md`), not rendered as interactive map. Added DoorData cross-reference note in §12 for undercity layers.
