# GDD — Cliffs & Canyons (impassable elevation gradient)

**Status:** DESIGN (rulings captured 2026-06-26; V1 = detect + store + render + block).
**Controlling renderer:** `scenes/maps/hex_map_renderer_3d.gd`. **Field:** `engine/subsystems/generation/world/geo_field*.gd`.

## 1. Overview & definitions

A **cliff** is a steep, effectively-vertical elevation gradient across a hex **edge** — too
steep to walk up or down. It is an *edge* feature (the impassable boundary between a high
hex and a low one), the same shape as a river, and rides on the existing edge machinery
(edges 0–5, canonical lex-lower ownership, `EDGE_NEIGHBOR_OFFSETS`, the single travel
chokepoint `HexMapController.can_cross_river_edge`).

A **canyon** is not its own object — it *emerges* as a chain of cliff edges flanking a
deeply river-incised valley (high-Strahler channel + deep `filled − surface` incision).
A "grand canyon" is a long run of such edges. The river runs on the canyon floor; the
walls are cliff edges to the surrounding plateau.

**Scale note:** at 6-mile hex resolution a cliff edge represents a *major* escarpment
(hundreds–thousands of feet), not every rock face. Sub-hex cliffs are not modeled. Steep
**lake rims** (post the 2026-06-26 lake-pour-level fix) and the steepest **mountain edges**
become cliffs naturally via the same detector; most mountain edges stay passable-but-slow.

## 2. ACKS Constraints (SACRED — from the books; implement faithfully)

- **No unaided crossing of sheer terrain.** Without a relevant proficiency/gear/magic a
  party simply cannot cross a cliff (`acore_proficiencies_rules_and_catalog.xml:590`;
  vehicles need roads through mountains `daw_equipment_and_construction.xml:87`).
- **Climbing proficiency / Thief — Climb Walls** (`acore_core_classes.xml:1447`): scale
  sheer surfaces with a **proficiency throw per 100' climbed**; on a failed throw, **fall a
  distance = half the attempted segment + the distance already climbed**, taking **1d6 per
  10'**; climb at **¼ combat movement**. Throw target = thief-of-level table
  (`acore_core_classes.xml:1475`; L1 6+, L3 5+, L4 4+ …). Climbing proficiency lets only
  the **individual** climb.
- **Mountaineering + gear** (`acore_proficiencies:855`): lets the **whole party** climb as
  thieves of their level (falling still a risk). **Required gear:** ≥ 50' rope, **1 iron
  stake per 50' of cliff height**, and a warhammer/small hammer/mallet. **Plus a grappling
  hook** if *no* party member has Climbing or is a Thief alongside the Mountaineer.
- Magic alternatives (out of scope V1): Spider Climb, Fly, climbing potion.

## 3. Data model

New per-edge table mirroring `hex_river_edges` (canonical lex-lower owner, no mirror entry):

```sql
CREATE TABLE hex_cliff_edges (
    map_id       TEXT NOT NULL REFERENCES hex_maps(id),
    hex_q        INTEGER NOT NULL,         -- canonical owner (lex-lower of the two hexes)
    hex_r        INTEGER NOT NULL,
    edge         INTEGER NOT NULL CHECK(edge BETWEEN 0 AND 5),
    cliff_type   TEXT NOT NULL DEFAULT 'cliff' CHECK(cliff_type IN ('cliff','canyon')),
    height_ft    INTEGER NOT NULL DEFAULT 0,   -- climb height (drives throws + stake count)
    high_side    INTEGER NOT NULL CHECK(high_side IN (0,1)),  -- 0 owner is top, 1 neighbour is top
    PRIMARY KEY (map_id, hex_q, hex_r, edge)
);
CREATE INDEX idx_hex_cliff_edges_owner ON hex_cliff_edges(map_id, hex_q, hex_r);
```

New shared type `HexCliffEdgeData` mirroring `HexRiverEdgeData` (canonicalize, neighbor
offset). `HexMapData` gains a `cliff_edges: Array[HexCliffEdgeData]`, loaded/saved like
rivers. `height_ft` and `high_side` feed the climb resolution + the render wall direction.

## 4. Detection (at materialization, from the GeoField)

Cliff/canyon edges are derived when the 6-mile play map is built (so travel + renderer read
one stored truth). Per shared edge between hexes A,B, sample the field cells:

- **Cliff** if the cross-edge height delta `|surface_rim(A) − surface_rim(B)|` ≥
  `CLIFF_DELTA` (the rim = pre-incision / `filled` height, not the incised channel floor).
- **Canyon** if additionally the lower side is a high-Strahler channel
  (`strahler ≥ CANYON_STRAHLER`) with deep incision (`filled − surface ≥ CANYON_INCISION`):
  tag `canyon` (same blocking; distinct for rendering/flavor).
- `high_side` = whichever hex's rim is higher. `height_ft` = delta → feet (see §10 — the
  open derivation question).

Thresholds calibrate with a probe like `tools/geo_slope_stats.gd` / `lake_level_probe.gd`.

## 5. Crossing resolution — REUSABLE sheer-surface climb (cliffs now, dungeon walls later)

Implement as a standalone service (grep tag `SHEER_SURFACE_CLIMB`) so wall-scaling reuses it.

**Party-travel gate (can the party attempt a cliff edge?):**
1. A member has **Mountaineering** proficiency, AND the party's **pooled** inventory holds the
   gear **per climber** — N = every member making the climb (PCs + henchmen + mercenaries):
   per climber → 50' rope ×1, iron stakes ×`ceil(height_ft / 50)`, hammer/mallet ×1, **plus a
   grappling hook ×1 unless** some party member has Climbing or is a Thief. Gear may sit in any
   inventory; what matters is the pooled total ≥ N × per-climber.
2. **Insufficient gear → block the attempt** and report the SHORTFALL, e.g. "Not enough gear —
   you require: grappling hooks: #, iron spikes: #, hammers: #, 50' rope: #" (counts = the
   amounts still missing). Missing **Mountaineering** → impassable (route around), no list.
3. (An individual with Climbing/Thief may climb *solo* — the wall-scaling reuse + single-
   character cases, not party wilderness travel.)
4. Gate satisfied → the whole party climbs as thieves of their level.

**Resolution (per climber, when the gate is open):** `ceil(height_ft / 100)` proficiency
throws vs the climber's thief-level target; on a failure, fall (half the current 100'
segment + distance already climbed) → `1d6 per 10'` damage. Time cost = ¼ movement on the
travel leg. (Throws are generous, so a small drop is a real climb; a tall sheer face is a
last resort — routing around is the norm for canyon walls; see §10.)

## 6. Travel integration

Generalize the chokepoint: `can_cross_river_edge` → also consult `cliff_edges`. A cliff edge
returns **impassable for routing** unless the party gate (§5.1) is satisfied, in which case
the leg is allowed but pays the climb time + triggers the per-member resolution. Pathfinding
(`find_path`) and `can_move_to` inherit this automatically. No new speed-table entry — the
climb cost is applied on the cliff leg specifically.

## 7. Rendering

A cliff edge draws a **vertical wall quad** (mountain texture for now): corners `(e+4)%6`,
`(e+5)%6`; XZ from `corner_offsets()`; floor Y from the low hex, top Y from the high hex's
rim (`high_side`). **Cliff-aware corners:** `_build_chunk` must *stop averaging* the shared
corners across a cliff edge (keep the discontinuity) and fill the gap with the wall — not
purely additive. Double-sided so it reads from inside a canyon. Canyon edges may later get a
distinct texture/strata; V1 uses the mountain layer for both.

## 8. Cross-system interactions

- **Lakes:** a lake in a steep basin → its rim edges are cliffs (consistent with the lake
  pour-level fix). The detector catches them; no special case.
- **Mountains:** only the steepest mountain *edges* become cliffs; the rest stay
  passable-but-slow (the per-hex gradient tag is unchanged).
- **Rivers/roads:** a canyon has a river on its floor; roads already route around impassable
  edges. Mountain *passes* (a road/trail crossing a cliff) are deferred.
- **Gradient tag (mountains/hills/flat)** is per-hex; cliffs are per-edge — complementary.

## 9. V1 build phases

1. **Data** — migration `hex_cliff_edges`; `HexCliffEdgeData`; `HexMapData.cliff_edges`
   load/save; repo round-trip + test.
2. **Detect** — materialization derives cliff/canyon edges from the field; calibrate
   thresholds; store on the play map.
3. **Render** — cliff-aware corners + wall quads (mountain texture); in-engine verify.
4. **Block** — generalize the edge chokepoint; `SHEER_SURFACE_CLIMB` service (gate + throws
   + fall); pathfinding routes around; crossing pays time + resolves falls.

## 10. RESOLVED — cliff CLIMB HEIGHT = full delta (2026-06-26)

Climb height = the true hex-to-hex elevation drop (raw cross-edge delta → feet via the
climate scale, ~7,778 m per raw unit above 0.55). The Climb-Walls throws are generous, so a
**small** drop is a real, survivable climb, but a tall sheer face (1,500'+) is a near-certain
fatal fall — climbing is for small drops or desperation; routing around is the norm for
canyon walls. No abstraction or cap. `height_ft` drives the throw count AND the per-climber
stake count (`ceil(height_ft / 50)`).
