# GDD: Stronghold & Building Construction

**Authority:** HYBRID — Structure catalog, construction rates, supervision rules, materials rules, magic-assisted construction, and domain stronghold value thresholds come from ACKS sourcebooks (DaW, ACore, Axioms) and are sacred. Grid placement logic, the commission pipeline, size preset definitions, accessory sub-menu behavior, NPC stronghold generation, and construction interruption handling are PROJECT-DESIGNED and may be modified freely.
**Status:** Draft
**Depends on ACKS rules:** `daw_equipment_and_construction.xml` (structure catalog, accessories, civilian structures, construction projects, worker rates, supervision, materials, magic assistance), `acore_axioms_strongholds_and_domains.xml` (minimum stronghold value, domain classification, followers)
**Depends on GDDs:** `gdd-ui-ux-design.md` (G-08 Domain Management, G-10 Stronghold Planner), `gdd-settlement-layout.md` (market class for hiring workers), `gdd-dungeon-layout.md` (shared cell-based wall model, dungeon-to-stronghold claiming), `gdd-combat-map-generation.md` (unified diamond grid system, cell-based wall model definition)
**Modifiable by Claude Code:** Sections marked PROJECT-DESIGNED — yes, suggest improvements freely. Sections marked ACKS RULES — never modify.
**Last updated:** 2026-03-25

---

## 1. Purpose

Define how the player designs, commissions, tracks, and completes stronghold and building construction within the app. This GDD bridges the gap between the ACKS construction rules (which assume a human Judge tracking costs and timelines on paper) and the in-app experience (which needs a visual planner, automated cost calculation, worker hiring pipeline, monthly progress tracking, and integration with domain management).

This GDD also defines how the app auto-generates structurally valid strongholds for NPC domains during world simulation.

**Scope:** Strongholds, fortifications, civilian buildings, dungeon construction (underground rooms/corridors built by the PC), and associated accessories. Ships, siege engines, and field fortifications are out of scope — they will be covered in a separate GDD.

---

## 2. ACKS Rules Summary (Sacred)

These rules come from DaW Equipment & Construction, ACore Strongholds & Domains, and Axioms. They are not modifiable. The engine must implement them faithfully.

### 2.1 Structure Catalog

**Stronghold structures:**

| Structure | Standard Dimensions | Cost | SHP | AC | Unit Capacity |
|---|---|---|---|---|---|
| Barbican (gatehouse + 2 small towers + drawbridge) | Composite | 38,000gp | 2,500 | 6 | 4 |
| Battlement (crenellated parapets) | 100' long | 500gp | 100 | 6 | — |
| Building, stone | 20' high, 30' square | 3,000gp | 200 | 5 | 1 |
| Building, wood | 20' high, 30' square | 1,500gp | 60 | 2 | 1 |
| Corridor, dungeon | 10' × 10' × 10' section | 500gp | 80 | 6 | — |
| Drawbridge, wood | 10' wide, 20' high, 1' thick | 250gp | 7 | 2 | — |
| Gatehouse | 20' high, 30' × 20' | 6,500gp | 1,000 | 6 | 2 |
| Keep, square | 80' high, 60' square | 75,000gp | 15,000 | 6 | 12 |
| Moat, unfilled | 100' × 20' × 10' deep | 400gp | (500) | 0 | — |
| Moat, filled | 100' × 20' × 10' deep | 800gp | (1,000) | 0 | — |
| Palisade, wood | 10' high, 100' long, 1' thick | 125gp | 5 | 2 | 1 |
| Rampart, earthen | 10' high, 100' long, 15' thick | 2,500gp | 750 | 4 | 1 |
| Tower, small round | 30' high, 20' diameter | 15,000gp | 750 | 7 | 1 |
| Tower, medium round | 40' high, 20' diameter | 22,500gp | 1,000 | 7 | 1 |
| Tower, large round | 40' high, 30' diameter | 30,000gp | 1,600 | 7 | 2 |
| Tower, huge round | 60' high, 30' diameter | 54,000gp | 2,400 | 7 | 5 |
| Wall, stone (20' high) | 100' long, 10' thick | 5,000gp | 1,500 | 6 | 1.5–3 |
| Wall, stone (30' high) | 100' long, 10' thick | 7,500gp | 2,250 | 6 | 1.5–4.5 |
| Wall, stone (40' high) | 100' long, 10' thick | 12,500gp | 3,000 | 6 | 1.5–6 |
| Wall, stone (50' high) | 100' long, 10' thick | 17,500gp | 3,750 | 6 | 1.5–7.5 |
| Wall, stone (60' high) | 100' long, 10' thick | 22,500gp | 4,500 | 6 | 1.5–9 |

**Variant dimension rules (ACKS):** Dimensions marked as alterable may be changed so long as square footage remains the same. Cost and SHP adjust proportionately. Square towers cost 50% less than round but lose 1 AC. Round keeps cost 50% more and gain +1 AC. Walls over 60' high double cost. Walls may be built up to 200' high.

**Structure accessories:**

| Accessory | Cost | SHP | AC |
|---|---|---|---|
| Arrow slit / window | 10gp | 2 | 0 |
| Door, wood (3' × 7') | 10gp | 3 | 1 |
| Door, reinforced wood (3' × 7') | 20gp | 5 | 2 |
| Door, iron/stone (3' × 7') | 50gp | 12 | 6 |
| Door, secret (3' × 7') | material × 5 | by material | by material |
| Floor/roof, flagstone or tile (10' × 10') | 40gp | 5 | 4 |
| Floor/roof, wood (10' × 10') | 10gp | 3 | 2 |
| Shutters (window) | 5gp | 1 | 2 |
| Shifting wall (10' × 10') | 1,000gp | 60 | 6 |
| Stairs, wood (one flight, 3' × 10') | 20gp | 5 | 2 |
| Stairs, stone (one flight, 3' × 10') | 60gp | 15 | 6 |

Upgrading a structure to include accessories during construction costs 25% of the accessories' base cost. Adding accessories after construction costs full price.

**Civilian structures:**

| Structure | Dimensions | Cost | SHP | AC |
|---|---|---|---|---|
| Cottage, wood | 20' high, 30' square | 300gp | 6 | 1 |
| Hut, pit | 8' high, 8' square | 15gp | 1 | 1 |
| Hut, sod or wattle | 10' high, 10' square | 25gp | 1 | 1 |
| Hut, mudbrick or wood | 10' high, 10' square | 50gp | 2 | 1 |
| Longhouse, wood | 15' high, 30' × 15' | 300gp | 5 | 1 |
| Roundhouse, wood | 15' high, 15' diameter | 125gp | 4 | 1 |
| Townhouse, stone | 20' high, 30' square | 1,200gp | 100 | 4 |

**Structure AC classes (ACKS):** Ordinary wood = AC 1, reinforced wood = AC 2, earthen = AC 4, soft stone = AC 5, thick heavy stone = AC 6, round structures gain +1 AC. When a structure reaches 0 SHP it collapses in 1d10 rounds.

**Damage resistance (ACKS):** Man-sized weapons and light ballista cannot damage wooden structures. Huge creatures and magic deal 1/5 damage to wooden structures. Wood-throwing artillery and huge creatures cannot damage stone or earthen structures. Stone-throwing artillery and gigantic creatures deal 1/10 damage to stone structures. Colossal creatures and magic deal 1/5 damage to stone structures. Petards deal normal damage to stone.

### 2.2 Construction Project Rules

**Cost and rate:** Construction cost equals base cost in GP. Each worker contributes a construction rate (GP value per day) toward the cost. A worker's construction rate normally equals their wage rate.

**Worker rates:**

| Worker | Construction Rate (month) | Construction Rate (day) | Wage (month) |
|---|---|---|---|
| Unskilled laborer | 3gp | 1sp | 3gp |
| Skilled laborer | 6gp | 2sp | 6gp |
| Apprentice craftsman | 10gp (15gp if managed) | 3.3cp (5sp if managed) | 10gp |
| Journeyman craftsman | 20gp (30gp if managed) | 6.6cp (1gp if managed) | 20gp |
| Master craftsman | 40gp (30gp while managing) | 1gp 3.3cp (1gp while managing) | 75gp |
| Master + 2 journeymen + 4 apprentices (team) | 150gp | 5gp | 150gp |
| Siege engineer | 20gp | 6.6cp | 50gp |
| Engineer | 40gp | 1gp 3.3cp | 250gp |

About 1 in 4 laborers is usually skilled. A master craftsman may manage up to 2 journeymen and 4 apprentices to increase their rate by 50%, but the master's own rate drops by 25% on large-scale projects. Usually no more than 1 master per 100 laborers.

**Supervision:** Every project requires a supervisor. A siege engineer may supervise up to 25,000gp construction cost. An engineer may supervise up to 100,000gp. Multiple engineers/siege engineers may combine for larger projects.

**Construction sites:** A site is approximately 1/2 mile in diameter. All similar construction at the same site must be one project. Maximum 12,000 workers per site. The first 3,000 workers operate at full rate; additional workers beyond 3,000 operate at 33% rate but draw full wages.

**Materials:** Nearby forests and quarries are assumed (local gathering included in cost). If raw materials must be transported from long distance, labor cost increases by 10–20%+. Buying materials at market costs 25% of project cost but reduces labor cost by 25%. Scavenging from nearby buildings reduces labor cost by 25% but reduces those buildings' value by 2× the savings.

**Magic-assisted construction (ACKS):**

| Spell(s) | Effect |
|---|---|
| Move earth | 12,500gp/turn construction rate on ditches, moats, and ramparts only |
| Transmute rock to mud | +50% to workers' construction rate for 3d6 days |
| Move earth + transmute rock to mud | +100% to workers' construction rate |
| Move earth + transmute rock to mud + wall of stone | +500gp per wall of stone casting |
| Wall of stone (alone) | Resurface 5,000gp of existing stone, OR erect up to 250gp stone structure instantly (critically weak to dispel magic) |

A spellcaster must have Engineering proficiency, or work under an engineer, to assist construction with magic.

### 2.3 Minimum Stronghold Values

From Axioms — the stronghold must meet these minimums to properly secure a domain:

| Classification | Per 1.5-mile hex | Per 6-mile hex | Per 24-mile hex |
|---|---|---|---|
| Civilized | 1,000gp | 15,000gp | 240,000gp |
| Borderlands | 1,500gp | 22,500gp | 360,000gp |
| Wilderness | 2,000gp | 32,000gp | 512,000gp |

If total stronghold value is insufficient, domain morale suffers (insufficient stronghold penalties: -1 if at least 1/2 minimum, -2 if at least 1/4 minimum, -3 if below 1/4 minimum).

### 2.4 Stronghold Repair

After siege damage, repair is a construction project. Wooden construction repairs at 5 SHP per 1gp of construction rate. Stone construction repairs at 1 SHP per 1gp. During an active siege, only half of damage sustained can be repaired; the remainder requires full rebuild cost after the siege.

### 2.5 Class-Specific Stronghold Types

Different classes unlock different stronghold types at level 9 (ACKS):

- **Fighters, clerics, bladedancers, dwarven classes:** Standard stronghold (fortress, castle, vault, fastness). Attracts peasant families and domain followers.
- **Thieves, assassins, elven nightblades:** Hideout. Attracts syndicate followers (2d6 1st-level characters of the boss's class, +1d6 per level beyond 9th).
- **Mages:** Sanctum (often a tower). Attracts 1d6 apprentices and 2d6 normal men. May also build a dungeon beneath/near the sanctum to attract monsters for arcane power.
- **Explorers:** May only build in borderlands or wilderness.
- **Elven fastnesses and dwarven vaults:** May only be built in wilderness, or in civilized/borderlands areas of their own race.

### 2.6 Followers and Construction Milestones

Half of followers (rounded up) arrive when the stronghold is halfway complete. An additional quarter (rounded up) arrive when the stronghold is complete. The remainder arrive over the following months per ACKS domain procedures. Peasant families begin generating income only once the stronghold is sufficient to secure the domain.

---

## 3. Stronghold Archetypes (PROJECT-DESIGNED)

The G-10 Stronghold Planner is a single tool with archetype-specific palettes and validation. The archetype is determined by the commissioning character's class and selected when the planner opens.

### 3.1 Archetype Definitions

| Archetype | Triggered By | Structure Palette | Grid Expectations | Validation |
|---|---|---|---|---|
| **Fortress** | Fighter, cleric, bladedancer, dwarf classes | Full fortification catalog: keeps, towers, walls, gatehouses, barbicans, moats, ramparts, battlements, buildings | Perimeter-focused: walls forming enclosures, towers at corners/gates, keep as centerpiece | Warns if perimeter is open, if gates don't connect to walls, if below minimum stronghold value for target domain |
| **Hideout** | Thief, assassin, nightblade | Buildings (wood and stone), dungeon corridors, dungeon rooms, secret doors, shifting walls, trap infrastructure (per gdd-trap-generation.md) | Interior-focused: rooms connected by corridors, concealed entrances, escape routes | Warns if no secret door or concealed entrance exists. No perimeter wall requirement. |
| **Sanctum** | Mage | Towers (all sizes), buildings, dungeon corridors and rooms, libraries, workshops (use building with tagged purpose) | Vertical-focused: tower as primary structure with optional underground dungeon annex | Warns if no tower is present. Dungeon rooms beneath sanctum are optional but flagged as "arcane power attractor" if present. |
| **Fastness/Vault** | Elf / dwarf (racial variants) | Same as Fortress but adds racial-specific decorative tags (aesthetic only, no mechanical difference) | Same as Fortress | Same as Fortress, plus enforces location restriction (wilderness only, or own-race civilized/borderlands) |

All archetypes share the same underlying grid, cell-based wall model, and structure data format. The archetype only controls which structures appear in the palette, what validation warnings fire, and what follower mechanics apply on completion.

### 3.2 Archetype Selection Flow

1. Player opens G-10 from G-08 (Domain Management) or from a downtime action declaration.
2. System identifies the commissioning character and determines the available archetype(s) based on class.
3. If only one archetype is valid, it is auto-selected.
4. If the class supports multiple options (e.g., a multi-class character), the player chooses.
5. The palette, validation, and follower preview update to match the selected archetype.

---

## 4. Grid Placement System (PROJECT-DESIGNED)

### 4.1 Grid Specification

The planner uses the project's unified 5' diamond grid (per `gdd-combat-map-generation.md` §3). The stronghold footprint IS the battle map if the stronghold is ever attacked.

- **Grid size:** The planner starts with a default 200' × 200' (40 × 40 cells) grid. The player can expand the grid in 50' (10-cell) increments up to a maximum of 500' × 500' (100 × 100 cells). Larger strongholds may use multiple adjacent grids if needed, but this is a v2 consideration.
- **Cell-based walls:** Walls are impassable cells, consistent with the project-wide wall model (per `gdd-combat-map-generation.md` §9.2). A 5' wall is 1 cell thick; a 10' wall is 2 cells thick. Doors are cells that toggle between passable and impassable.
- **Elevation:** The grid is 2D (top-down). Height information is stored per-structure-piece as metadata (a 60' wall is placed on the grid as a 2-cell-thick line with `height: 60` in its data). The isometric renderer uses per-cell elevation scores (0-30, each unit = 2.5 feet, per `gdd-combat-map-generation.md` §4) to render height during battle map view.

### 4.2 Structure-to-Grid Mapping

Each structure from the ACKS catalog is mapped to a grid footprint using **size presets**. The player selects a structure type, then chooses from available size presets for that type.

**Wall presets:**

| Preset | Length | Thickness | Height Options | Grid Footprint |
|---|---|---|---|---|
| Short segment | 50' | 10' | 20'/30'/40'/50'/60' | 10 × 2 cells |
| Standard segment | 100' | 10' | 20'/30'/40'/50'/60' | 20 × 2 cells |
| Long segment | 150' | 10' | 20'/30'/40'/50'/60' | 30 × 2 cells |
| Custom | Player-defined (multiples of 5') | 10' | 20'/30'/40'/50'/60' | Calculated |

Height is selected from a dropdown when placing the wall. Cost, SHP, and unit capacity scale proportionately from the ACKS base values per the standard wall entries.

**Tower presets:**

| Preset | Matches ACKS Entry | Grid Footprint | Shape |
|---|---|---|---|
| Small round | Small round tower (30' high, 20' dia) | 4 × 4 cells (circular mask) | Round |
| Medium round | Medium round tower (40' high, 20' dia) | 4 × 4 cells (circular mask) | Round |
| Large round | Large round tower (40' high, 30' dia) | 6 × 6 cells (circular mask) | Round |
| Huge round | Huge round tower (60' high, 30' dia) | 6 × 6 cells (circular mask) | Round |
| Small square | Derived: 50% less cost, -1 AC | 4 × 4 cells | Square |
| Medium square | Derived: 50% less cost, -1 AC | 4 × 4 cells | Square |
| Large square | Derived: 50% less cost, -1 AC | 6 × 6 cells | Square |
| Huge square | Derived: 50% less cost, -1 AC | 6 × 6 cells | Square |
| Custom | Player-defined height and diameter (multiples of 10') | Calculated | Round or square |

Round towers on the diamond grid use a circular occupancy mask: cells whose center falls within the circle are marked as tower interior. This produces an approximate circle. The isometric renderer draws the actual round shape; the grid stores the cell mask.

**Keep presets:**

| Preset | Dimensions | Grid Footprint |
|---|---|---|
| Standard square | 80' high, 60' × 60' | 12 × 12 cells |
| Small square | 60' high, 40' × 40' | 8 × 8 cells |
| Large square | 80' high, 80' × 80' | 16 × 16 cells |
| Standard round | +50% cost, +1 AC | 12 × 12 cells (circular mask) |
| Custom | Player-defined (multiples of 10') | Calculated |

**Other structures** (gatehouse, barbican, moat, palisade, rampart, buildings) each have 2–3 presets following the same pattern: a standard size matching the ACKS listed dimensions, one smaller variant, and one larger variant. Custom is always available. Cost and SHP scale proportionately from the base entry.

### 4.3 Proportional Scaling Formula

When the player uses a custom size or a non-standard preset, cost and SHP are recalculated proportionately:

```
scale_factor = custom_square_footage / standard_square_footage
scaled_cost = ROUND_HALF_EVEN(base_cost × scale_factor)
scaled_shp = ROUND_HALF_EVEN(base_shp × scale_factor)
```

For walls, where height is an independent variable, cost scales with both length and height:

```
length_factor = custom_length / 100   (standard is 100')
height_factor = custom_height / 20    (base entry is 20' wall)
scaled_cost = ROUND_HALF_EVEN(5000 × length_factor × height_factor)
```

If custom height exceeds 60', the cost doubles per ACKS rules (applied after the proportional calculation).

Unit capacity scales proportionately with the structure's defending surface area, using banker's rounding.

### 4.4 Placement Rules

- **Snap to grid:** All structures snap to 5' cell boundaries.
- **Wall connection:** Walls connect end-to-end and to tower/gatehouse cells. The system highlights valid connection points when a wall cell is adjacent to a compatible structure. Walls placed adjacent to towers share perimeter cells — the tower's outer wall cells and the connecting wall cells form a continuous barrier.
- **Tower anchoring:** Towers may be placed freestanding or at wall corners/midpoints. When placed at a wall junction, the tower's footprint abuts or overlaps the wall's endpoint cells, forming a continuous run of impassable cells.
- **Moat adjacency:** Moats must be placed adjacent to walls, ramparts, or palisades (on the exterior side). The system prevents moat placement on the interior of an enclosure.
- **Building placement:** Buildings may be placed anywhere on the grid — inside or outside wall perimeters.
- **Dungeon corridors/rooms:** For hideout and sanctum archetypes, dungeon corridors and rooms are placed on underground layer toggles. The planner supports up to 3 layers for v1: surface, underground level 1, and underground level 2. Stairs connect adjacent layers. Claimed dungeons (§8.4) may display more layers if the source dungeon had them, but new PC-built underground construction is capped at 2 underground levels.
- **Overlap prevention:** Structures may not overlap except at designed connection points (wall-to-tower, gate-in-wall). The system rejects invalid placements with a visual indicator.

### 4.5 Accessory Sub-Menu

When a structure piece is placed on the grid, the player may immediately configure its accessories via a sub-menu panel that appears on the right side (below the structure palette). The sub-menu shows only accessories valid for that structure type.

**Accessory rules by structure:**

| Structure | Available Accessories |
|---|---|
| Wall | Arrow slits (per 5' per story), battlements (auto-sized to wall length), doors (in wall for interior passages) |
| Tower | Arrow slits (per story), doors (ground floor), stairs (wood or stone, internal), shutters |
| Keep | Arrow slits, doors, stairs, floors/roofs (per level), shutters, shifting walls |
| Gatehouse | Doors (reinforced/iron default), portcullis (included in gatehouse base) |
| Building | Doors, stairs, windows, shutters, floors/roofs |
| Dungeon corridor | Doors (any type including secret), shifting walls |

**Default accessories:** Each structure type comes with sensible defaults pre-selected:

- Walls: 1 arrow slit per 5' per story (ACKS standard density), battlements on top.
- Towers: 1 door (ground floor, wood), internal wood stairs, 1 arrow slit per 5' per story.
- Keeps: 1 main door (reinforced wood), internal wood stairs between all floors, wood floors/roofs, 1 arrow slit per 5' per story.
- Gatehouses: Portcullis (included), reinforced wood doors.
- Buildings: 1 wood door, 1 wood floor/roof.

The player can modify all defaults. Accessory cost during construction is 25% of the accessory's base cost (ACKS rule). The sub-menu shows both the discounted construction cost and the full retrofit cost so the player understands the savings.

---

## 5. Commission Pipeline (PROJECT-DESIGNED)

After the player finalizes a stronghold design in G-10 and presses "Confirm Design," the system executes a multi-step commission pipeline that determines workforce, cost, and timeline.

### 5.1 Step 1 — Cost Summary

The system totals:

- **Structure cost:** Sum of all placed structures at their (possibly scaled) costs.
- **Accessory cost:** Sum of all accessories at the 25% construction discount.
- **Total construction cost:** Structure cost + accessory cost. This is the GP value that workers must contribute through construction rate to complete the project.

Displayed to the player as a line-item breakdown before proceeding.

### 5.2 Step 2 — Supervisor Requirement

The system checks whether the construction cost requires an engineer, siege engineer, or multiple supervisors:

- Cost ≤ 25,000gp: 1 siege engineer required.
- Cost ≤ 100,000gp: 1 engineer required.
- Cost > 100,000gp: Multiple engineers/siege engineers required (each additional engineer adds 100,000gp capacity; each additional siege engineer adds 25,000gp).

The system checks the nearest settlement's market class for engineer/siege engineer availability using the standard hireling availability tables. If no suitable supervisor is available:

- The player is notified of the shortfall.
- Options: wait for the next monthly hiring cycle, travel to a larger market, or use a PC/henchman with Engineering or Siege Engineering proficiency as the supervisor.

Supervisor hiring cost is added to the project's ongoing wage expenses.

### 5.3 Step 3 — Workforce Calculation

The system determines the available labor pool based on the nearest settlement's market class and the domain's peasant population:

**Available laborers:** The system uses the hireling availability tables from the equipment rules to determine how many laborers can be hired per week at the nearest market. The player accumulates workers over multiple hiring weeks until satisfied or until the market is exhausted.

**Workforce composition:** The system assumes the ACKS default ratio: 3 unskilled laborers per 1 skilled laborer. Craftsmen (apprentice, journeyman, master) are hired separately at their market availability rates.

**Blended construction rate:** The system calculates the total daily construction rate of the assembled workforce:

```
daily_rate = (num_unskilled × 1sp) + (num_skilled × 2sp) + (craftsman_team_rate)
```

If the workforce exceeds 3,000, the excess workers contribute at 33% rate:

```
if total_workers > 3000:
    base_rate = rate_of_first_3000_workers
    excess_rate = rate_of_excess_workers × 0.33
    daily_rate = base_rate + excess_rate
```

**Player-facing presentation:** The system shows a workforce summary panel with:

- Current workforce count and blended daily rate.
- Estimated construction time at current workforce.
- Monthly wage cost at current workforce.
- A highlighted comparison: "Hiring 500 more workers costs X gp/month more in wages and saves Y months of construction time."
- If the workforce exceeds 3,000: a clear warning — "Workers beyond 3,000 operate at 33% efficiency but draw full wages. Current excess: N workers. Monthly cost of excess wages: X gp. Time saved by excess workers: Y months." The player can then adjust the workforce count up or down.

The system does not auto-optimize. The player makes the call.

### 5.4 Step 4 — Materials Decision

The player chooses a materials sourcing strategy:

- **Local sourcing (default):** No cost adjustment. Forests/quarries assumed nearby.
- **Purchased materials:** Costs 25% of project cost upfront. Reduces labor cost by 25%. Available only if a suitable market exists (Class IV or better for stone; Class V or better for wood).
- **Scavenged materials:** Reduces labor cost by 25%. Requires selecting existing structures to scavenge from. Those structures lose 2× the savings in value. Only available if suitable structures exist within the construction site's hex.
- **Long-distance materials:** Increases labor cost by 10–20% (system calculates based on distance to nearest quarry/forest if known, otherwise a flat 15% default). Used when the construction site is in barren/desert terrain or similar.

The chosen strategy adjusts the total labor cost and is locked for the duration of the project (changeable only with a project modification action, which may add delay).

### 5.5 Step 5 — Magic Assistance (Optional)

If the party includes a spellcaster with Engineering proficiency (or the project has an engineer supervisor and a spellcaster available), the system presents magic assistance options:

- **Move earth:** Applicable only to moats, ramparts, ditches. Adds 12,500gp/turn construction rate during casting.
- **Transmute rock to mud:** +50% to all workers' rate for 3d6 days (rolled when cast).
- **Combined move earth + transmute rock to mud:** +100% to workers' rate.
- **Wall of stone:** Various effects per ACKS table.

Magic assistance is declared per-month during the monthly resolution cycle (§7). The spellcaster must be present at the construction site and not adventuring during the month they provide assistance. The system tracks which spells were cast and adjusts that month's construction progress accordingly.

### 5.6 Step 6 — Confirmation and Gold Commitment

The system presents a final summary:

- Total construction cost.
- Supervisor cost (hiring + ongoing wage).
- Workforce monthly wage.
- Materials cost (if purchased).
- Estimated completion time (months).
- Follower arrival milestones (halfway point, completion).
- "This stronghold will qualify for a domain of up to X 6-mile hexes in [classification] territory."

The player commits gold. The committed gold covers the first month's wages and any upfront materials cost. Ongoing wage payments are deducted monthly during domain resolution (§7).

If the player cannot afford the first month's costs, the system blocks confirmation and displays the shortfall.

---

## 6. Monthly Construction Progress (PROJECT-DESIGNED)

### 6.1 Integration with Domain Resolution

Construction progress is resolved during the monthly domain resolution cycle (design brief §13.3, step 7). Each month:

1. **Deduct wages:** Worker wages and supervisor wages are deducted from the domain's treasury (or the PC's personal gold if no domain exists yet).
2. **Calculate monthly construction progress:** Sum of all workers' monthly construction rates, adjusted for magic assistance (if any that month), materials strategy, and the 3,000-worker efficiency cliff.
3. **Apply progress:** Subtract the monthly construction progress from the remaining construction cost.
4. **Check milestones:**
   - If remaining cost ≤ 50% of total: trigger "halfway complete" — first batch of followers arrives (half, rounded up).
   - If remaining cost = 0: trigger "construction complete" — second batch of followers arrives (quarter, rounded up). Stronghold is fully operational.
5. **Update hex map:** Show "construction in progress" marker with percentage complete. On completion, replace with the stronghold marker.

### 6.2 Progress Display in G-08

The Domain Management screen (G-08) shows active construction projects in the Stronghold panel:

- Project name (auto-generated from archetype + location, e.g., "Stone Fortress at Hex 1214").
- Progress bar: GP completed / GP total, with percentage.
- Estimated months remaining at current workforce.
- Monthly wage cost.
- Current workforce count.
- "Modify Project" button (opens options to adjust workforce size, change materials strategy, or add/pause magic assistance).
- "Open in Planner" button (opens G-10 in read-only mode showing the design — modifications to the design itself during construction are a separate action, see §6.3).

### 6.3 Mid-Construction Design Changes

If the player wants to modify the stronghold design while construction is in progress:

- **Adding structures:** New structures are treated as additional construction cost added to the remaining total. Workers continue at the same rate.
- **Removing structures:** If the structure hasn't been started yet (its portion of the cost hasn't been reached in the build order), it is removed at no penalty. If partially or fully built, the invested GP are lost (the structure is demolished/abandoned in place).
- **Build order:** The system constructs structures in the order they were placed on the grid, with some heuristics: foundations and underground work first, then walls, then towers, then interior buildings, then accessories and finishing. The player cannot reorder this directly, but the system's order is displayed so the player knows what's being built when.

---

## 7. Construction Interruption (PROJECT-DESIGNED)

If a construction site is attacked (monster incursion, raid, siege, wandering encounter), the following procedure applies:

### 7.1 Interruption Trigger

An interruption occurs when:

- A hostile force enters the hex containing the construction site.
- A random domain event targets the construction site (e.g., bandit raid, monster attack).
- The PC orders construction to halt (voluntary pause).

### 7.2 Immediate Effects

- **Construction pauses.** No progress is made during any month in which the site is attacked, regardless of when in the month the attack occurs.
- **Workers flee.** Unskilled laborers disperse. After the threat is resolved, rehiring takes 1 week per 500 workers at the nearest market. Skilled laborers and craftsmen are retained (they shelter but do not flee) unless the interruption lasts more than 1 month, at which point they must be re-hired.
- **Supervisor retained.** Engineers and siege engineers remain unless killed in the attack.

### 7.3 Partial Damage to Incomplete Structures

If the attack involves combat at the construction site:

- **Completed structures** (structures whose construction cost has been fully paid) use their normal SHP and AC for damage resolution.
- **Partially completed structures** (construction cost partially paid) have SHP proportional to their completion percentage: `current_shp = ROUND_HALF_EVEN(full_shp × (gp_invested / structure_cost))`. Their AC is reduced by 1 (minimum 0) to represent incomplete construction (no battlement, no roof, scaffolding exposed).
- **Unstarted structures** (no GP invested yet) do not exist on the map and cannot be damaged.

### 7.4 Cost to Resume

After an interruption:

- **No damage sustained:** Construction resumes at current progress with no additional cost beyond rehiring dispersed workers.
- **Damage sustained:** Damaged incomplete structures must be repaired before construction can continue. Repair cost uses the ACKS repair rules: stone repairs at 1 SHP per 1gp of construction rate; wood repairs at 5 SHP per 1gp. This repair cost is added to the project's remaining total. If damage exceeds 50% of a partially completed structure's current SHP, the structure must be rebuilt from scratch (total cost of that structure is re-added to the remaining total; previously invested GP in that structure are lost).

---

## 8. NPC Stronghold Generation (PROJECT-DESIGNED)

The world simulation needs to generate structurally valid strongholds for NPC-ruled domains without running the player-facing planner. This procedure auto-composes a stronghold that meets the ACKS minimum value threshold for the domain and produces a battle map definition for potential siege/assault encounters.

### 8.1 Inputs

- **Domain classification:** Civilized, borderlands, or wilderness.
- **Domain size:** Number of 6-mile hexes.
- **Required minimum stronghold value:** Looked up from the §2.3 table.
- **NPC ruler class:** Determines stronghold archetype.
- **NPC ruler wealth/realm tier:** Determines budget (may exceed minimum).
- **Terrain of stronghold hex:** Influences material availability and structural style.

### 8.2 Generation Procedure

1. **Determine budget.** The budget is the greater of: the minimum stronghold value for the domain, or the NPC's available construction gold (determined by realm tier, income, and duration of rule). NPCs typically build 10–50% above minimum when they can afford it.

2. **Select archetype template.** Based on ruler class, choose from a library of stronghold composition templates. Each template defines a proportional allocation of budget across structure types:

**Fortress template (fighters, clerics, dwarves):**

| Component | Budget Allocation | Required? |
|---|---|---|
| Keep | 30–40% | Yes (1) |
| Walls | 25–35% | Yes |
| Towers | 15–20% | Yes (2–6 depending on budget) |
| Gatehouse/barbican | 5–10% | Yes (1) |
| Moat | 5–10% | If budget > 50,000gp |
| Buildings (interior) | 0–10% | Optional |

**Hideout template (thieves, assassins):**

| Component | Budget Allocation | Required? |
|---|---|---|
| Buildings (stone, concealed) | 40–50% | Yes |
| Dungeon corridors/rooms | 30–40% | Yes |
| Secret doors | 5–10% | Yes (minimum 2) |
| Escape tunnel | 5–10% | Yes (1) |

**Sanctum template (mages):**

| Component | Budget Allocation | Required? |
|---|---|---|
| Tower (primary) | 50–60% | Yes (1, large or huge) |
| Dungeon (beneath) | 20–30% | Optional |
| Buildings (auxiliary) | 10–20% | Optional |
| Wall (perimeter) | 0–10% | Only if budget > 80,000gp |

3. **Allocate budget to components.** For each component in the template, allocate a GP amount within the specified range. Ensure total allocation matches budget. Select the size preset for each structure that best matches its allocated GP (nearest preset ≤ allocated GP).

4. **Compose grid layout.** Place structures on a grid using a simplified placement algorithm:
   - Place the keep/primary tower near grid center.
   - Place walls in a rectangular or roughly circular perimeter around the keep.
   - Place towers at wall corners and midpoints.
   - Place the gatehouse in the perimeter wall facing the nearest road or settlement direction.
   - Place moat (if any) adjacent to exterior wall.
   - Place interior buildings in the courtyard.
   - For hideouts: place buildings with connecting corridors and secret exits.

   The layout does not need to be architecturally elegant — it needs to be structurally valid (enclosed perimeter, connected structures, no overlaps) and produce a usable battle map. A randomized jitter on tower and building placement prevents cookie-cutter uniformity.

5. **Apply accessories.** Use the standard defaults from §4.5 (arrow slits at standard density, battlements on walls, doors on buildings/towers/gatehouses).

6. **Validate.** Confirm total stronghold value ≥ minimum. Confirm perimeter is closed (fortress/fastness archetypes). Confirm at least 1 gate exists. Store the layout as a battle map definition.

### 8.3 Output

The NPC stronghold is stored as the same `StrongholdLayout` data structure the player planner produces (§9). This means any NPC stronghold can be viewed in the planner (read-only) and used directly by the combat system for siege/assault battles.

### 8.4 Claiming Existing Structures (Dungeon-Stronghold Bridge)

Per ACKS rules, if an existing suitable structure is present in the domain hex, the ruler may claim it as their stronghold rather than building new. This is the primary bridge between the dungeon generation system (`gdd-dungeon-layout.md`) and the stronghold construction system.

**When claiming is available:**

A player who clears a dungeon, ruin, or pre-existing fortification may claim it as a stronghold or sanctum if:

- The character meets ACKS class/level requirements for domain rulership
- The hex is secured (no hostile forces remaining)
- The structure type is compatible with the character's stronghold archetype (a fighter can claim a fortress-like dungeon; a mage can claim any dungeon as a sanctum; a thief can claim a suitable hideout)
- **The dungeon type is claimable** (see eligibility below)

**Dungeon type eligibility:**

Not all dungeons are suitable for conversion to a stronghold. Only dungeon types that represent deliberate construction — or are strongly analogous to it — can be claimed. Natural formations and unintelligent creature burrows lack the structural regularity needed for stronghold use.

```
CLAIMABLE dungeon types (from ACKS d20 flavor table):
  Abandoned mine, Barrow mound, Catacombs, Cliff city, Crumbling castle,
  Humanoid warren, Maze, Prison, Ruined manor, Sewers, Sunken city,
  Temple, Tomb, Tower, Wizard's dungeon

NOT CLAIMABLE:
  Giant burrow, Giant insect hive, Monster lair, Natural caverns,
  Underground river

Rule of thumb: if the dungeon was built by intelligent beings with
tools, it is claimable. If it was dug by animals, shaped by water,
or is a natural geological feature, it is not.

The "Claim as Stronghold" option does not appear in the hex interaction
menu for non-claimable dungeon types.
```

**Appraisal procedure (PROJECT-DESIGNED):**

ACKS does not publish rules for appraising existing structures as stronghold value. This procedure is entirely project-designed, extrapolating from the construction and equipment cost tables that DO exist in `daw_equipment_and_construction.xml` and `acore_axioms_strongholds_and_domains.xml`. Where no exact table entry exists (particularly for walls thinner than 10'), the system uses proportional fractional pricing.

When a player initiates a claim, the system appraises the existing structure's GP value by mapping its dungeon layout to equivalent stronghold construction costs:

```
1. Measure and price interior space:
   - Count all open cells in the DungeonLayout
   - Classify each as underground room, underground corridor, or
     surface structure
   - Underground rooms/corridors: value at dungeon construction rate
     (500gp per 10' × 10' section = 500gp per 4 cells, per DaW)
   - Surface structures (if any): value at equivalent building type rate
     from the structure catalog

2. Count and price walls:
   - For each wall cell run in the layout, determine wall thickness:
     a. Standard dungeon walls (10'+ thick, matching a catalog entry):
        value at the published stone wall rate per linear foot
     b. Thinner walls (5' or less, common in dungeon interiors):
        value at a fractional rate proportional to thickness:
        thin_wall_value = ROUND_HALF_EVEN(standard_wall_rate
                          × (actual_thickness / standard_thickness))
        Example: a 5' interior wall at half the 10' wall rate
     c. Natural rock walls (in partially natural dungeons like
        abandoned mines): value at 50% of equivalent constructed
        wall rate — the rock provides structural mass but was not
        shaped to fortification standard

3. Count and price features:
   - Doors: value per door at accessory rates from the catalog
     (wood, reinforced, iron, etc.)
   - Stairs: value per stair at stair accessory rate
   - Special features (portcullis, secret doors, arrow slits,
     shifting walls): value at accessory rates
   - Traps: NOT valued. Traps are hazards, not structural
     improvements. They contribute 0gp to stronghold value.
     (The player may choose to disarm and remove them, or leave
     them as defenses — but they don't count toward the minimum.)

4. Apply condition modifier:
   - Intact (cleared dungeon, no structural damage): 100%
   - Damaged (partial collapse, battle damage): 50-90% based on extent
   - Ruined (major structural failure): 25-50%, requires significant repair
   - The condition is assessed from the dungeon's state at claiming time

5. Total appraised value = (space value + wall value + feature value)
                           × condition modifier
   Rounded using banker's rounding.

Design note: This appraisal will tend to produce conservative values.
Most dungeons — especially lair-sized ones — will fall short of the
minimum stronghold value for a fortress or fastness archetype. This
is intentional: claiming a dungeon gives you a head start on a
stronghold, not a free one. The player commissions expansion
construction to make up the difference.
```

**Claiming flow:**

```
1. Player selects "Claim as Stronghold" from the hex interaction menu
2. System displays the appraisal: itemized value breakdown and total
3. System compares appraised value to minimum stronghold value for archetype:
   - If value ≥ minimum: claimable at no cost. "This structure meets
     the minimum value of [X]gp for a [archetype]."
   - If value < minimum: claimable, but shortfall must be addressed.
     "This structure is worth [X]gp. A [archetype] requires [Y]gp.
     You must commission [Y-X]gp of additional construction."
4. Player confirms the claim
5. System wraps the DungeonLayout in a StrongholdLayout shell:
   - The dungeon's grid, cells, rooms, doors, and stairs are
     preserved exactly as-is
   - A StrongholdLayout record is created with:
     - source_type: "claimed_dungeon"
     - source_dungeon_id: the original dungeon's ID
     - The dungeon's cell-based wall model becomes the stronghold's
       battle map AND interior navigation map
   - The stronghold appears in G-10 (planner) in edit mode
6. If shortfall exists, the planner opens with the existing layout
   displayed and the player commissions new construction to expand it
   (new walls, towers, buildings, additional underground rooms)
```

**Grid compatibility:** Both systems use the same 5' diamond grid with cell-based walls (per `gdd-combat-map-generation.md` §3 and §9.2). A DungeonLayout can be directly embedded in a StrongholdLayout without grid conversion. New construction placed via the planner must connect to existing dungeon corridors/rooms at valid door or opening positions — the overlap prevention system treats existing dungeon cells as occupied space that new structures connect to but do not overwrite.

**Post-claiming modifications:** Once claimed, the structure is editable through the stronghold planner's edit mode (§8.5). The player can commission demolitions (clearing rubble, removing walls, widening corridors) and expansions (adding surface fortifications, extending underground areas, adding accessory features). All modifications follow the standard commission pipeline (§5).

### 8.5 Editing Existing Strongholds (Demolitions and Expansions)

After a stronghold reaches `construction_state: "complete"` (or is claimed per §8.4), the player can reopen it in the G-10 planner in **edit mode** to commission modifications. This is distinct from mid-construction design changes (§6.3) — edit mode operates on finished structures.

**Entering edit mode:**

From G-08 (Domain Management), the player selects a completed stronghold and chooses "Edit Stronghold." The G-10 planner opens with the existing layout displayed, all structures shown as locked (not draggable), and a toolbar offering three actions: Expand, Demolish, and Retrofit Accessories.

**Expansion:**

```
1. Player places new structures on the existing grid using the
   standard placement system (§4)
2. New structures must connect to existing structures at valid
   connection points (wall endpoints, door positions, corridor openings)
3. The grid may be expanded (§4.1) if the new construction extends
   beyond the current grid boundary
4. New construction follows the standard commission pipeline (§5):
   cost summary → workforce hiring → monthly progress tracking
5. The existing stronghold remains fully functional during expansion
   construction — only the new portions are "under construction"
6. When expansion construction completes, the new structures merge
   into the stronghold layout and the battle map is regenerated
```

**Demolition:**

```
1. Player selects an existing structure and chooses "Demolish"
2. System displays:
   - The structure being demolished (highlighted in red on the grid)
   - Demolition cost: 10% of the structure's original construction cost
     (covers labor to safely tear down — ACKS does not specify demolition
     cost, so this is a project-designed rate)
   - Demolition timeline: same workforce mechanics as construction, but
     the "cost" to be worked through is the demolition cost, not the
     original build cost. Demolition is faster than construction.
   - Salvage value: 50% of the original materials cost is recovered
     as salvaged stone/timber (credited as a lump sum on completion)
   - WARNING if demolition would break perimeter enclosure (fortress/
     fastness archetypes) or eliminate required structures (e.g.,
     removing the only gatehouse)
3. Player confirms the demolition order
4. Demolition enters the construction project queue
   - While in progress, the structure is flagged as "demolishing"
   - It retains its SHP and defensive properties until demolition
     completes (workers are carefully dismantling, not destroying)
   - If attacked during demolition, the structure is still defensible
5. On completion: the structure's grid cells become passable (open ground
   or revert to rock for underground), and the battle map is regenerated
6. Recovered salvage materials are added to the domain treasury
```

**Retrofit accessories:**

```
1. Player selects an existing structure and chooses "Modify Accessories"
2. The accessory sub-menu (§4.5) opens, showing current accessories
3. Player may add new accessories or remove existing ones
4. Adding accessories to a completed structure costs 100% of accessory
   cost (not the 25% discount available during initial construction)
5. Removing accessories has no cost but also no salvage value
   (arrow slits are filled in, battlements removed, etc.)
6. Accessory changes are instantaneous — they do not require a
   construction project (the work is minor enough to be handled
   by the domain's regular maintenance workforce)
```

**Palisade-to-wall upgrade (resolves Open Question #3):** Upgrading a wooden palisade to a stone wall is handled as a demolition of the palisade followed by construction of a wall in the same grid position. The system offers this as a combined "Upgrade" action when a palisade is selected in edit mode: it queues the demolition and the replacement construction as a single project, with the demolition phase completing before wall construction begins. The palisade's salvage value offsets part of the wall cost. During the transition, the hex has no perimeter defense at that segment — a vulnerability the player must account for.

### 8.6 Navigable Stronghold Interiors

Every stronghold — player-built and NPC-generated — must have navigable interiors in all buildings, towers, keeps, and gatehouses. This is required so that:

1. **NPC strongholds can be raided** by players in a manner similar to dungeon crawling — entering through gates or breaches, moving room-to-room through doors, fighting defenders in corridors, and looting specific chambers.
2. **Player strongholds can be defended** with interior tactical positioning during sieges that breach the outer perimeter.
3. **Strongholds claimed from dungeons** (§8.4) seamlessly integrate their existing interior layout.

**Interior generation principle:** When a structure piece (building, tower, keep, gatehouse) is placed on the grid, the system auto-generates a simple interior layout within the structure's footprint. The interior uses the same cell-based wall model as dungeons — walls are impassable cells, doors are cells with open/closed state, stairs are passable cells connecting floors.

**Auto-generated interior rules by structure type:**

```
Tower:
  - Ground floor: single room filling the tower's circular/square mask
  - One entry door cell on a perimeter wall (facing courtyard or wall walk)
  - Internal stairs (wood or stone, per accessory selection) connecting
    each floor to the one above
  - Each upper floor: single room with arrow slit cells on exterior walls
  - Top floor: open battlement ring (if battlements accessory is present)
  - Total rooms = number of stories (height / 10', typically 3-6)

Keep:
  - Ground floor: great hall (large central room) + 1-2 side chambers
  - One main entry door (reinforced) + optional secondary/postern door
  - Internal stairs connecting all floors
  - Upper floors: 2-4 rooms per floor (lord's quarters, armory, chapel,
    storage) sized proportionally to the keep's footprint
  - Top floor: battlement ring + possible tower peak room
  - Underground level (if applicable): dungeon cells or vault rooms

Building (civilian):
  - Single-story building: 1 room filling the footprint, 1 door
  - Multi-story building: 1 room per floor, internal stairs, 1 ground-floor door
  - Small buildings (≤20' × 20'): always single room per floor
  - Large buildings (>20' × 20'): may be subdivided into 2-3 rooms per floor

Gatehouse:
  - Ground floor: gate passage (open corridor through the structure)
    with portcullis cell and door cells at both ends
  - Upper floor(s): guard room(s) overlooking the gate passage
    (murder holes represented as a special floor cell type)
  - Arrow slit cells on exterior walls

Dungeon corridors/rooms (underground layer):
  - Already use the cell-based wall model natively
  - No additional interior generation needed — they ARE the interior
```

**Player customization (tweak mode):**

After a structure is placed and its interior auto-generated, the player may tweak the interior layout with limited controls:

```
Allowed tweaks:
  - Move doors: relocate a door cell to a different perimeter position of the same room
    (cannot remove the last door from a room — every room must have
    at least one door or stair access)
  - Move stairs: relocate internal stairs to a different cell within
    the structure's footprint
  - Add/remove interior doors: subdivide a large room by converting a
    wall cell to a door cell, or open up two adjacent rooms by converting
    a wall cell to an open passable cell or door cell
  - Door type selection: change any door between open archway, wood
    door, reinforced door, iron door, locked, trapped, or secret door
    (costs apply per accessory rates for non-standard doors)

NOT allowed (to keep the planner manageable):
  - Moving exterior walls (the structure's footprint is fixed by its preset)
  - Adding rooms beyond the structure's footprint
  - Changing floor count (determined by structure height)
  - Freeform interior wall drawing (rooms are auto-sized subdivisions)
```

**NPC stronghold interiors:**

NPC strongholds (§8) use the auto-generated interiors directly with no player tweaking. This produces structurally valid, raidable interiors for every NPC stronghold in the game. The auto-generated layouts are deterministic given the stronghold's structure list and a seed value, so the same NPC stronghold always produces the same interior.

**Raid gameplay:**

When a player party enters a hostile stronghold (through assault, infiltration, or parley breakdown), the stronghold's interior becomes a navigable space using the same movement, visibility, and encounter rules as dungeon exploration:

```
- Movement: room-to-room through doors, corridor-by-corridor
- Doors: locked/barred doors must be forced or picked
- Visibility: fog of war applies; rooms are revealed on entry
- Encounters: garrison units are positioned in rooms per §11.2
  (auto-suggested defender positions). Alert propagation follows
  the same faction-alert rules as dungeon factions
  (gdd-dungeon-factions.md) — guards in one room can alert
  adjacent rooms through open doors
- Treasure: domain treasury, armory contents, and personal effects
  of the domain ruler are placed in specific rooms (vault, armory,
  lord's quarters respectively)
- The stronghold IS the battle map — no separate map generation needed
```

---

## 9. Data Model (PROJECT-DESIGNED)

### 9.1 StrongholdLayout

```
StrongholdLayout:
  stronghold_id: string
  archetype: string               # "fortress" | "hideout" | "sanctum" | "fastness" | "vault"
  owner_character_id: string
  domain_id: string or null       # Linked domain, if any
  hex_id: string                  # Location on the campaign map
  
  grid_width: int                 # In 5' cells
  grid_height: int
  layers: int                     # 1 = surface only, 2 = surface + 1 underground, 3 = surface + 2 underground (v1 max)
  
  structures: Array[PlacedStructure]
  # PlacedStructure:
  #   structure_id: string          # Unique ID for this placed piece
  #   structure_type: string        # "wall" | "tower" | "keep" | "gatehouse" | etc.
  #   preset: string                # "standard" | "small" | "large" | "custom"
  #   dimensions: { length: int, width: int, height: int }  # In feet
  #   shape: string                 # "square" | "round"
  #   material: string              # "wood" | "stone" | "earthen"
  #   grid_origin: Vector2i         # Top-left cell of this structure's footprint
  #   grid_cells: Array[Vector2i]   # All cells occupied
  #   layer: int                    # 0 = surface, 1 = underground
  #   cost: int                     # GP (scaled from base)
  #   shp: int                      # Structural HP (scaled from base)
  #   current_shp: int              # Current SHP (may differ from max after damage)
  #   ac: int
  #   unit_capacity: float          # Garrison capacity in units
  #   accessories: Array[PlacedAccessory]
  #   connections: Array[string]    # IDs of structures this piece connects to
  
  # PlacedAccessory:
  #   accessory_type: string        # "arrow_slit" | "door_wood" | "door_reinforced" | etc.
  #   count: int                    # Number of this accessory on this structure
  #   cost: int                     # Total cost (at 25% if during construction, 100% if retrofit)
  #   shp: int                      # Per-unit SHP
  #   cell_positions: Array[...]    # Which cells on the structure (for battle map rendering)
  
  total_value: int                # Sum of all structure + accessory costs
  total_shp: int                  # Sum of all SHP
  total_unit_capacity: float      # Sum of garrison capacity
  
  construction_state: string      # "planned" | "in_progress" | "complete" | "damaged" | "ruined"
  construction_project: ConstructionProject or null   # Active project data if in_progress
  
  # Claiming / source tracking
  source_type: string             # "built" | "claimed_dungeon" | "claimed_ruin" | "npc_generated"
  source_dungeon_id: string or null  # If claimed from a dungeon, the original DungeonLayout ID
  appraised_value: int or null    # GP value at time of claiming (null if built from scratch)
  
  # Interior navigation (§8.6)
  interior_layouts: Dictionary    # structure_id → StructureInterior
  # StructureInterior:
  #   floors: Array[FloorLayout]
  #   FloorLayout:
  #     floor_number: int           # 0 = ground, 1 = first upper, -1 = underground
  #     cells: Array[Array[CellData]]  # Cell-based wall model, same as dungeon
  #     rooms: Array[RoomData]      # Same RoomData format as DungeonLayout
  #     stairs: Array[StairData]    # Connects to floor_number ± 1
  #   NOTE: For claimed dungeons, interior_layouts is populated directly
  #   from the DungeonLayout's rooms/cells. For built structures, interior
  #   is auto-generated per §8.6 rules.
  
  # Battle map integration
  battle_map_cells: Array[Array[CellData]]   # Cell-based wall model, same format as dungeon layouts
  # Generated from structures array + interior_layouts; rebuilt whenever the layout changes
```

### 9.2 ConstructionProject

```
ConstructionProject:
  project_id: string
  stronghold_id: string
  total_cost: int                 # GP total to complete
  gp_completed: int               # GP worth of work done so far
  gp_remaining: int               # total_cost - gp_completed
  
  workforce: WorkforceData
  # WorkforceData:
  #   unskilled_count: int
  #   skilled_count: int
  #   apprentice_count: int
  #   journeyman_count: int
  #   master_count: int
  #   managed_teams: int            # Number of master-led teams
  #   total_workers: int
  #   daily_construction_rate: float  # GP per day, accounting for 3k cliff
  #   monthly_construction_rate: float
  #   monthly_wage_cost: float
  
  supervisor: SupervisorData
  # SupervisorData:
  #   type: string                  # "engineer" | "siege_engineer" | "pc_proficiency"
  #   character_id: string or null  # If PC/henchman is supervising
  #   monthly_wage: float
  #   capacity: int                 # GP of project they can supervise
  
  materials_strategy: string      # "local" | "purchased" | "scavenged" | "long_distance"
  materials_cost_modifier: float  # Multiplier on labor cost (e.g., 0.75 for purchased/scavenged)
  materials_upfront_cost: int     # One-time cost if purchased
  
  magic_assistance_this_month: Array[string]   # Spells applied this month
  magic_rate_modifier: float      # Current month's multiplier from magic
  
  start_date: string              # Campaign date construction began
  estimated_completion_date: string
  
  # Milestones
  halfway_reached: bool
  halfway_followers_arrived: bool
  complete: bool
  completion_followers_arrived: bool
  
  # Interruption tracking
  interrupted: bool
  interruption_months: int        # Months lost to interruptions
  damage_repair_cost: int         # Additional cost from interruption damage
```

---

## 10. Validation System (PROJECT-DESIGNED)

The planner runs continuous validation while the player designs. Warnings are displayed in the right panel's validation feedback area. Warnings do not block placement — the player can build whatever they want — but the system clearly communicates structural and mechanical consequences.

### 10.1 Structural Warnings

- **Open perimeter (fortress/fastness/vault only):** "Your wall perimeter has gaps. Attackers can bypass walls through these openings." Fires when wall segments don't form a closed polygon around the keep/interior.
- **Gate not connected:** "This gate is not connected to walls on both sides." Fires when a gatehouse is placed but not adjacent to wall endpoints.
- **No entrance (hideout):** "This hideout has no entrance. Add at least one door or secret door connecting to the surface." Fires when all dungeon rooms are sealed.
- **No tower (sanctum):** "Sanctums typically feature a tower as the primary structure." Fires when a sanctum archetype has no tower placed.

### 10.2 Domain Value Warnings

- **Below minimum:** "Total stronghold value (X gp) is below the minimum for a [classification] domain of Y hexes (Z gp). Domain morale will suffer." Includes the specific morale penalty.
- **Approaching minimum:** "Total stronghold value (X gp) is within 20% of the minimum for [classification]. Consider adding structures for a safety margin."
- **Qualifies for domain:** "This stronghold qualifies for a [classification] domain of up to X 6-mile hexes." Updated live as structures are added/removed.

### 10.3 Budget Warnings

- **Exceeds available gold:** "Total project cost (X gp) exceeds your available gold (Y gp)." Blocks the Confirm Design button.
- **High monthly wage:** "Monthly workforce wages (X gp) exceed your monthly domain income (Y gp). You will need supplemental funding." Informational only — doesn't block.

---

## 11. Defense Integration (PROJECT-DESIGNED)

The completed (or in-progress) stronghold layout doubles as the battle map for any combat at the stronghold site.

### 11.1 Battle Map Generation

When the stronghold is attacked:

1. Convert `StrongholdLayout.structures` to `battle_map_cells` using the project's cell-based wall model (per `gdd-combat-map-generation.md` §9.2).
2. Each structure's footprint becomes wall cells (impassable) on the grid.
3. Doors become door cells (passable when open, impassable when closed; type: wood/reinforced/iron/secret).
4. Arrow slits become special wall cells that grant the -4 ranged attack penalty and +4 save bonus to defenders behind them.
5. Battlements grant their defensive bonuses to units positioned on top of walls.
6. Moats become impassable terrain cells (or passable only with fascines/bridges).
7. Interior spaces become open passable cells for defender positioning.

This conversion is deterministic and produces identical results each time. The battle map is cached and only regenerated if the stronghold layout changes.

### 11.2 Garrison Positioning

The battle map system auto-suggests defender positions based on unit capacity. Each structure with unit capacity > 0 gets defender placement zones. The player (or NPC AI) can then assign garrison units to specific zones before combat begins. Overflow units (garrison exceeding capacity) are placed in the courtyard or interior spaces.

---

## 12. Design Decisions (Resolved)

- **Grid tool, not freeform drawing: DECIDED.** Structures are placed as discrete grid-snapped pieces, not drawn freeform. This ensures every stronghold produces a valid battle map and allows deterministic cost calculation. The tradeoff is less artistic freedom — mitigated by the isometric preview and the variety of size presets.
- **Presets with custom option: DECIDED.** Size presets per structure type for quick selection. Custom entry available for power users. Presets cover 80%+ of expected use cases.
- **Accessories during placement: DECIDED.** Each placed structure immediately offers an accessory sub-menu. Defaults are pre-populated. Players who don't care about arrow slit counts get sensible defaults; players who do care can customize per-structure.
- **Single tool, archetype palettes: DECIDED.** One G-10 planner tool serves all stronghold archetypes. The archetype controls the palette, validation, and follower mechanics — not the grid system itself.
- **Player chooses workforce size: DECIDED.** The 3,000-worker efficiency cliff is presented transparently with cost/time comparisons. The app does not auto-optimize. Players who want to overspend for speed can do so.
- **Moderate interruption depth: DECIDED.** Attacks pause construction and may damage incomplete structures. Workers disperse and must be rehired. Severe damage (>50% of a structure's current SHP) requires rebuild. No worker casualty tracking or morale effects on workers.
- **Strongholds and buildings only: DECIDED.** Ships, siege engines, and field fortifications are separate GDDs. This document does not cover them.
- **NPC generation included: DECIDED.** Auto-composition of valid NPC strongholds is defined here, using template-based budget allocation and simplified grid placement.
- **Dungeon-stronghold bridge via shared grid: DECIDED.** Dungeons and strongholds share the same 5' diamond grid with cell-based walls. A claimed dungeon wraps its DungeonLayout in a StrongholdLayout shell with no grid conversion. Appraised value calculated from equivalent construction costs. Shortfalls addressed by expansion through the planner. (§8.4)
- **Post-completion edit mode: DECIDED.** Completed strongholds can be reopened in G-10 in edit mode for expansions, demolitions, and accessory retrofits. Demolition costs 10% of original construction cost with 50% materials salvage. Expansions follow the standard commission pipeline. Accessory changes are instantaneous. (§8.5)
- **Auto-generated navigable interiors: DECIDED.** Every placed structure gets an auto-generated interior (rooms, doors, stairs per floor) using the cell-based wall model. Players can tweak door/stair placement but not exterior walls or room count. NPC strongholds use auto-generated interiors directly, making them raidable as dungeon-like spaces. (§8.6)
- **Interior tweak scope limited: DECIDED.** Players can move doors, move stairs, add/remove interior doors, and change door types. Players cannot move exterior walls, add rooms beyond the footprint, change floor count, or draw freeform interior walls. This keeps the planner manageable while allowing meaningful customization.
- **Barbican as atomic unit: DECIDED.** Barbicans are placed as a single grid stamp (gatehouse + 2 towers + drawbridge) matching the ACKS fixed-price listing. No component-level assembly.
- **Two underground levels for v1: DECIDED.** The planner supports up to 2 underground levels for new construction. Claimed dungeons may display deeper levels from their source layout. Expansion to deeper PC-built construction is post-v1.

---

## 13. Open Questions

All open questions have been resolved.

**Resolved:**
1. ~~**Barbican as composite vs. atomic:**~~ **RESOLVED.** Barbicans are placed as a single atomic piece (one grid stamp = gatehouse + 2 towers + drawbridge), matching the ACKS listing as a single fixed-price unit. The player places one barbican piece; its internal components are not individually configurable beyond accessory defaults.
2. ~~**Underground dungeon depth for sanctums:**~~ **RESOLVED.** The planner supports up to 2 underground levels for v1. This covers the typical sanctum (tower above, dungeon beneath) and hideout (surface concealment, 2-level underground complex). Claimed dungeons (§8.4) may display and navigate more than 2 levels if the original dungeon had them, but new PC-built underground construction is capped at 2 levels. Expansion to deeper construction is a post-v1 enhancement once the system is proven.
3. ~~**Palisade-to-wall upgrade path:**~~ **RESOLVED in §8.5.** Demolition of the palisade followed by construction of a wall in the same position, offered as a combined "Upgrade" action. Salvage value of the palisade offsets part of the wall cost. The hex has no perimeter defense at that segment during the transition.
4. ~~**Existing dungeon integration:**~~ **RESOLVED in §8.4.** Both systems use the same 5' diamond grid with cell-based walls. DungeonLayout is wrapped directly in a StrongholdLayout shell with no grid conversion. The dungeon's rooms, doors, corridors, and stairs become the stronghold's interior navigation map. Shortfalls in value are addressed by commissioning new construction through the planner's edit mode.
