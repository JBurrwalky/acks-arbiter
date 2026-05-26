# GDD: Hex Subdivision and Cross-Scale Terrain Consistency

**Document type:** Game Design Document (architecture / umbrella)
**Authority:** PROJECT-DESIGNED — the cross-scale relationship between hex maps and the aggregation/inheritance rules between scales are not derived from ACKS RAW. The scale hierarchy itself (24-mile, 6-mile, 1.5-mile) and the 16-contiguous-sub-hexes-per-coarse-hex ratio come from `acore_axioms_strongholds_and_domains.xml`.
**Status:** Draft — describes the schema landed in migration 119 and codifies the aggregation rule (§5), inheritance rule (§6) including the complete terrain-tag inheritance algorithm, and the consistency-check semantics (§7) that the existing helpers (`check_domain_cross_scale_consistency`, `compute_consistent_domain_hex_set`) already enforce or are expected to extend to terrain tags. Three sub-passes (overlay child-scale path generation, coastline geometry, settlement placement) explicitly bounded out to `gdd-region-zoom-in.md` and `gdd-settlement-stocking.md`; this GDD specifies their invocation conditions.
**Depends on ACKS rules:** [`acore_axioms_strongholds_and_domains.xml:14-21`](../rules/acore_axioms_strongholds_and_domains.xml) (the 1.5/6/24 mile hex hierarchy and the "sixteen contiguous sub-hexes per coarse hex" relationship); [`ax_domains_of_chaos.xml:8-14`](../rules/ax_domains_of_chaos.xml) (population caps per 6-mile hex and per 24-mile hex, establishing 6-mile as the canonical resolution for domain-scale territory); [`acore-setting-construction-rules.xml:32-39`](../rules/acore-setting-construction-rules.xml) (campaign 24-mile + regional 6-mile as the standard setting-construction map pair).
**Depends on project GDDs:** [`gdd-terrain-system.md`](gdd-terrain-system.md) (the layered tag system whose values flow up and down between scales); [`gdd-setting-generation.md`](gdd-setting-generation.md) (the top-down procedural producer of 24-mile campaign maps); [`gdd-realtime-scheduler.md`](gdd-realtime-scheduler.md) (the scheduler under which any future procedural zoom-in pass would run as a scheduled event); [`gdd-poi-generation.md`](gdd-poi-generation.md) and [`gdd-settlement-stocking.md`](gdd-settlement-stocking.md) (downstream consumers that key off the resolved hex tags at whichever scale the party is currently on).
**Implementing files:** `db/migrations/119_hex_map_cross_scale_linkage.sql`, `engine/shared_types/hex_map_data.gd`, `engine/autoloads/campaign_repository.gd` (`validate_hex_map_parent_linkage`, `transition_party_to_map`, `check_domain_cross_scale_consistency`, `compute_consistent_domain_hex_set`, `get_hex_map_parent_id`, `get_hex_map_parent_footprint`, `list_child_maps`, `get_domain_hexes_on_map`).
**Modifiable by Claude Code:** Yes within constraints. The parent/child schema, the aggregation rule thresholds, the inheritance variation parameters, and the consistency-check semantics are all engineering decisions. The scale hierarchy (`campaign_24mi > regional_6mi > local_15mi`) and the 16:1 sub-hex ratio are RAW and may NOT be changed.
**Last updated:** 2026-05-22

---

## 1. Purpose and Scope

This GDD defines how hex maps of different scales relate to one another in the ACKS Arbiter data model. A campaign produces multiple `hex_maps` rows simultaneously — a 24-mile coarse map covering the campaign's political/strategic geography, and one or more 6-mile insets covering regions the party actually adventures in. This document specifies:

1. The **spatial containment relationship** (parent ↔ child) between maps of adjacent scales.
2. The **authorship direction** (authored ↔ derived) as an independent axis: which scale was produced by hand or by world-gen, and which was extrapolated from the other.
3. The **aggregation rule** that flattens child hexes into a coarser parent tag (used for bottom-up authorship and for the cross-scale consistency check).
4. The **inheritance rule** that expands a coarse parent tag into finer child hexes (used for top-down procedural zoom-in).
5. The **consistency-check semantics** that the repository enforces when both scales exist for the same region.

Scope boundaries:

- This GDD **does** specify the complete terrain-tag inheritance algorithm for procedural zoom-in (§6.3–§6.6) — deterministic seeding, layer-ordered variation application, spatial coherence model, deviation distributions, and water resolution. It does **not** specify three sub-passes that consume the inherited tags as input: overlay path generation between boundary constraints, coastline geometry re-authoring for coastal parents, and settlement placement against the city-carrier child. Those are owned by [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md) (planned) and [`gdd-settlement-stocking.md`](gdd-settlement-stocking.md). The invocation conditions for those sub-passes are stated here; the algorithms themselves live there.
- This GDD does **not** specify the UI for switching between scales. That is handled by the Strategic ⇄ Regional camera-mode toggle (see the 2026-05-19 session entries in `build_log.md` for the shipped implementation); the UI consumes this GDD's data model but does not extend it.
- This GDD does **not** restate the ACKS encounter / movement / lair derivation rules from each hex tag — that's [`gdd-terrain-system.md`](gdd-terrain-system.md). The tags that flow between scales are the same tags `gdd-terrain-system.md` defines.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **Three canonical hex scales** ([`acore_axioms_strongholds_and_domains.xml:14-21`](../rules/acore_axioms_strongholds_and_domains.xml)):
  - **1.5-mile hex** on a local map (≈ 2 sq mi per hex).
  - **6-mile hex** on a regional map (≈ 32 sq mi per hex), or **sixteen contiguous 1.5-mile hexes** on a local map.
  - **24-mile hex** on a continental map (≈ 500 sq mi per hex), or **sixteen contiguous 6-mile hexes** on a regional map.
- **16:1 sub-hex ratio between adjacent scales** (same citation). A coarse hex aggregates approximately sixteen sub-hexes of the next-finer scale. The schema's `parent_hex_footprint` is the explicit list of parent hex coordinates an inset covers; the 16:1 ratio is the *expected* count when an inset is roughly square but is not enforced (a hand-authored inset can be any shape).
- **Standard setting-construction map pair** ([`acore-setting-construction-rules.xml:32-39`](../rules/acore-setting-construction-rules.xml)): one campaign map at 24-mile hex scale, one regional map at 6-mile hex scale. The default content shape is "one coarse map plus one finer inset"; multi-inset and 3-level-nested arrangements (24mi → 6mi → 1.5mi) are project extensions, not RAW deviations.
- **6-mile hex is the canonical domain-scale resolution** ([`ax_domains_of_chaos.xml:8-14`](../rules/ax_domains_of_chaos.xml)): maximum 125 peasant families per 6-mile hex and 2,000 per 24-mile hex. This establishes 6-mile as the unit ACKS uses for fine-grained territorial measurement, and 24-mile as the unit for aggregated continental measurement. Domain population and economy systems read at the resolution the domain itself occupies.

---

## 3. Spatial Containment — Parent and Child

Parent/child vocabulary in this codebase refers **exclusively to spatial containment**, not to authorship direction or data-flow direction.

### 3.1 Definitions

- **Parent map**: the coarser of two linked maps; the map whose hexes geographically contain the other.
- **Child map**: the finer of two linked maps; the map whose hexes are geographically contained by the other; also called an **inset**.
- **Top-level map**: a map with no parent. `parent_map_id IS NULL`. Always exists at the coarsest scale present in the campaign (typically `campaign_24mi`).
- **Footprint**: the list of parent-map hex coordinates that a child inset covers. Stored on the child as `parent_hex_footprint` (JSON array of `[q, r]` pairs).
- **Anchor**: the parent-map hex coordinate that corresponds to the child's `(0, 0)`. Stored on the child as `parent_anchor_q` / `parent_anchor_r`. The anchor is the geometric registration point; the footprint is the area of validity.

### 3.2 Scale ordering

Coarser → finer:

```
campaign_24mi  >  regional_6mi  >  local_15mi
```

A child's scale must be *strictly finer* than its parent's scale. Same-scale linkage is illegal and is rejected at the repository write-boundary by `validate_hex_map_parent_linkage`. Three-level nesting is legal (a 1.5-mile local inset inside a 6-mile regional inset inside a 24-mile campaign map); the consistency rules apply recursively at each level.

### 3.3 Schema (recap from migration 119)

The migration 119 schema is the authoritative implementation of §3.1–§3.2:

```sql
ALTER TABLE hex_maps ADD COLUMN parent_map_id TEXT REFERENCES hex_maps(id);
ALTER TABLE hex_maps ADD COLUMN parent_anchor_q INTEGER;
ALTER TABLE hex_maps ADD COLUMN parent_anchor_r INTEGER;
ALTER TABLE hex_maps ADD COLUMN parent_hex_footprint TEXT NOT NULL DEFAULT '[]';

-- domain_hexes rebuilt to include map_id; UNIQUE widened.
-- Each domain_hexes row carries the map_id of the hex it claims,
-- letting a domain own hexes on multiple maps simultaneously.
```

The "child scale must be strictly finer than parent scale" rule is enforced in `validate_hex_map_parent_linkage` (repository boundary), not in SQL — SQLite cannot express a cross-row scale-comparison CHECK as a column-level constraint. The same boundary enforces "parent must exist," "parent must be in the same campaign as the child," and "a map cannot be its own parent."

### 3.4 Parent/child is **not** a derivation direction

The parent/child labels describe spatial containment only. They say nothing about which map was authored first, which one was generated procedurally, or which one is the "source of truth" for terrain tags. Two scenes with identical schema:

- **Procedural campaign**: the 24-mile parent was generated by `gdd-setting-generation.md`; the 6-mile child inset will be procedurally derived from it at zoom-in time. *Authorship flows parent → child.*
- **Hand-authored dev test map**: the 6-mile child inset was hand-drawn in Worldographer; the 24-mile parent's footprint hexes were aggregated up from the child while the off-camera parent hexes were hand-authored directly. *Authorship flows child → parent within the footprint, and direct everywhere else.*

Both arrangements use the same `parent_map_id` linkage. The distinction lives in §4 (Authorship Direction), not in the schema.

---

## 4. Authorship Direction — Authored and Derived

The second axis, independent of parent/child. Names the data-flow direction for terrain content.

### 4.1 Definitions

- **Authored**: the map's hex tags were placed directly — by a human in Worldographer (hand-authoring) or by `gdd-setting-generation.md`'s procedural producer (world-gen).
- **Derived**: the map's hex tags (or some subset of them) were computed from another map at a different scale, via the aggregation rule (§5) or the inheritance rule (§6).

Authorship is a property of *a hex's tag values*, not of the map as a whole. A single map can mix authored and derived hexes — most commonly, a hand-authored 24-mile campaign map has its footprint hexes derived (from the inset that covers them) and its off-camera hexes authored.

### 4.2 The two production modes the project supports

| Mode | Primary content source | Authorship direction within inset footprint | Authorship outside footprint |
|---|---|---|---|
| **Procedural campaign** (production launch) | World-gen pipeline | 24-mile parent **authored** (world-gen); 6-mile child **derived** by zoom-in (§6) | N/A — top-level map has no surrounding context |
| **Hand-authored test map** (dev scaffolding; planned DLC) | Human authorship in Worldographer | 6-mile child **authored**; 24-mile parent footprint **derived** by aggregation (§5) | 24-mile parent off-camera hexes **authored** directly |

The shipped game uses the procedural mode for all production content. Hand-authored test maps are dev-stage scaffolding used to exercise systems before procgen is mature; they may return as DLC modules. The data model treats both modes as first-class — neither mode is a "fallback" for the other.

### 4.3 Authorship is a content provenance concern, not a runtime concern

At runtime, the engine reads `hex_cells` rows and does not distinguish authored from derived. The distinction matters at:

- **Authorship-time**: when a human or world-gen is producing the content.
- **Consistency-check time**: when the repository verifies that parent and child agree on the regions they both cover (§7).
- **Round-trip time**: when a derived layer is re-derived (e.g., a procedural inset is re-generated after the parent is edited).

For derived content, the project does NOT currently store a "derived from" pointer on individual rows. The directionality is recovered from context: if a child inset has `parent_hex_footprint` set, and the parent hexes in that footprint pass the consistency check, the relationship is intact regardless of which side was authored first.

### 4.4 What happens when both sides are authored

This is the hand-authored test-map case: the human draws the 6-mile inset *and* hand-places the 24-mile footprint tags. The consistency check (§7) treats this exactly like any other consistency check — both sides must satisfy the aggregation rule. If the human's manual 24-mile footprint tags disagree with what the 6-mile child would aggregate to, the consistency check surfaces the diff, and the human chooses which to revise. The check never auto-fixes.

This is the recommended workflow for hand-authoring: draw the 6-mile inset first, run the aggregation rule mentally (or via tooling) to seed the 24-mile footprint, then hand-tune the parent hexes only where the aggregation feels wrong, accepting the consistency diff as documentation of the disagreement.

---

## 5. Aggregation Rule (Child → Parent)

Used when authorship flows up: hand-authored 6-mile inset → derived 24-mile footprint tags. Also used by the consistency check (§7) to verify that an authored parent and an authored child agree.

For each parent hex `P` that lies in some child's `parent_hex_footprint`, the aggregation rule produces a set of derived tag values for `P` by examining the set of child hexes `C₁, C₂, … Cₙ` that lie within `P`. The number of children per parent is typically 16 (the RAW ratio) but is determined by the inset's actual coverage, not by formula.

### 5.1 Per-tag aggregation

| Tag layer | Aggregation rule | Rationale |
|---|---|---|
| **elevation** | Highest wins (`mountains` > `hills` > `flat`). | Even one mountain ridge through a 24-mile hex makes the abstracted hex functionally mountainous for travel speed, encounter distance, and lair density. Travel and encounter modeling at the coarse scale should be conservative against terrain difficulty. |
| **biome** | Highest impedance wins among the majority bloc: `swamp` > `jungle` > `woods` > `desert` > `clear`. If the majority biome is `clear` but ≥30% of children are `woods`, parent = `woods`. | Conservative for travel/lair-density modeling; matches the player's intuition that "a 24-mile hex with half a forest in it is functionally a forest hex at coarse scale." The 30% threshold for woods-over-clear catches mixed landscapes where a forest is a defining feature without being numerically dominant. |
| **biome_subtype** | Adopt the dominant subtype if ≥50% of children share it; else clear it (`""`). | Subtypes are refinements of an already-classified biome (per [`gdd-terrain-system.md`](gdd-terrain-system.md) §3.4). A mixed-subtype parent shouldn't pretend to be uniformly e.g. `clear_tundra`; falling back to the parent biome with no subtype is the honest aggregation. |
| **water (ocean)** | Parent = `ocean` ONLY if ≥40% of children are `ocean`. | An "any child = ocean" rule would expand the apparent ocean footprint at the 24-mile view by up to ~16× per ocean-touching coarse hex, which is misleading on the strategic map. The 40% threshold treats a coastal parent as "land with a coast" until ocean genuinely dominates the cell. |
| **water (lake)** | Parent = `lake` ONLY if ≥40% of children are `lake`. Same threshold as ocean. | Lakes are smaller than oceans on average; the same 40% threshold means a small lake inside a parent hex stays a land hex at the coarse view (correct — a 24-mile hex around Lake Ashford is still a land hex with a notable lake feature, not a "lake hex" in the encounter-table sense). |
| **civilization** | Lowest wins (`wilderness` > `borderlands` > `civilized`) UNLESS a `has_city` child is present, in which case the minimum is `borderlands`. | Conservative for encounter rolls — a 24-mile hex with one fortified village and 15 wilderness sub-hexes is functionally wilderness with a strongpoint. The `has_city` override prevents the absurdity of a city-bearing parent hex being classified `wilderness` (a contradiction at the coarse scale's resolution). |
| **has_city** | Any child true → parent true. | Cities are point features (one settlement per child hex, per [`gdd-terrain-system.md`](gdd-terrain-system.md) §3.1). They propagate up unambiguously; the city is just *somewhere in* the coarser hex from the strategic view. |
| **original_biome** | Highest impedance wins among children with non-empty `original_biome`. Empty if all children are empty. | The deforestation/forestation system needs to know what the parent "would have been" in its natural state. Same impedance ordering as the biome rule, restricted to children with a deforestation history. |

### 5.2 Overlay aggregation

Rivers and roads aggregate differently because their data models differ ([`gdd-terrain-system.md`](gdd-terrain-system.md) §3.5 / §3.6). Rivers are first-class edge entities between hexes; roads are cell-attached overlays on `road_edges`. The aggregation rules reflect that split.

#### 5.2.1 Child-to-parent containment

Given the inset's `parent_anchor = (anchor_q, anchor_r)` and the parent/child scale ratio (4 for 24-mile → 6-mile, 4 for 6-mile → 1.5-mile), each child cell `C = (c_q, c_r)` maps to a containing parent hex `P(C)` by integer-floor division on the child's offset from anchor:

```
P(C).q = anchor_q + floor(c_q / 4)
P(C).r = anchor_r + floor(c_r / 4)
```

This is an **approximate** mapping. Hex-in-hex tessellation at the same orientation is not exact — 16 small hexes cannot tile a single large hex cleanly without overlap or fractional cells along the boundary. The integer-floor formula is the project's canonical resolution: each child cell is assigned to exactly one parent, boundary children fall to the parent on the lower-coordinate side, and `parent_hex_footprint` must list every parent hex any child maps to. Hand-authored insets that violate this (e.g., a child cell whose computed `P(C)` is not in the declared footprint) are rejected at the repository write-boundary as a footprint mismatch.

The `parent_hex_footprint` JSON list is the **authoritative** statement of containment when authored content disagrees with the formula. A hand-authored inset may declare a child belongs to a specific parent even if the formula would place it differently (e.g., a coastline that bulges into an adjacent parent hex). When the authored footprint and the formula disagree, the authored mapping wins for that child; the formula is the default.

#### 5.2.2 River aggregation algorithm

Rivers as edge entities make aggregation nearly trivial. A child river edge lies between two child hexes; the parent edge it contributes to is determined by whether the two child hexes are in the same parent hex or different parents.

Given the inset and its footprint:

1. **Identify parent-boundary child river edges.** For each row in the inset's `hex_river_edges` table, examine the two adjacent child hexes `A` and `B` (the owner from §3.6.2 and its neighbor across the edge). Compute `P(A)` and `P(B)` via §5.2.1.
   - If `P(A) == P(B)`, the river edge is **internal** to a single parent hex. Skip it — internal rivers are below the parent scale's resolution and produce no parent overlay.
   - If `P(A) ≠ P(B)`, the river edge is a **parent-boundary edge**. Its parent-edge correspondence is the edge on `P(A)` facing `P(B)` (equivalently, the edge on `P(B)` facing `P(A)`).
2. **Emit one parent river edge per qualifying child edge.** For each parent-boundary child river edge, write a parent river edge row with:
   - `hex_q, hex_r, edge` = the canonical-owner side per §3.6.2 (lower-lex parent owns).
   - `flow_clockwise` = the child edge's `flow_clockwise` value. (The flow direction at the parent edge is the same as at the child edge — they're geometrically aligned, just at different scales.)
   - `navigability` = the child edge's `navigability` value, possibly upgraded (see step 4).
   - `crossing` = the child edge's `crossing` value.
3. **Deduplicate.** If multiple child edges along the same parent edge are all rivers (a typical case — a river running along a parent boundary covers ~4 child edges in succession), they all describe the same parent edge. Emit only one parent river edge entry; resolve conflicts by:
   - Flow direction: all aligned child edges must agree on `flow_clockwise` (a river doesn't reverse direction along its own length); if they disagree, surface as an authoring error.
   - Navigability: take the maximum tier (the most-navigable child segment determines the parent's tier — a river that's navigable as `large_craft` for any part of its length within the parent boundary is `large_craft` at parent scale).
   - Crossing: if any child edge has `crossing != "none"`, the parent edge carries that crossing. If multiple crossings exist (e.g., two bridges in the same 24-mile span), pick the most permissive in this order: `ferry > bridge > ford > none`.
4. **No river on parent if no parent-boundary child edges.** Rivers that exist entirely within a single parent hex (all child river edges are internal per step 1) produce no parent river. Correct: a stream that meanders within one 24-mile hex isn't visible on the strategic map.

The algorithm is O(child river edges) — one pass over the inset's river table.

#### 5.2.3 Road aggregation algorithm

Roads remain cell-attached (`road_edges` on `HexOverlayData` per [`gdd-terrain-system.md`](gdd-terrain-system.md) §3.5), so road aggregation uses the cell-boundary-crossing logic.

1. For each child cell `C` with non-empty `C.road_edges`, examine each edge `e ∈ C.road_edges`. Compute the neighbor child cell `C' = neighbor(C, e)`.
2. If `P(C') ≠ P(C)` (or `C'` is outside the inset), edge `e` is a parent-boundary road crossing. Record `(P(C), parent_edge_e_corresponds_to)`.
3. For each parent `P` with recorded road crossings: `P.road_edges = unique set of parent_edge values`.
4. Parents with no road crossings get no parent-scale road. (Roads that exist entirely within a single parent hex's child cells produce no parent road — same below-resolution principle as rivers.)
5. A parent road's edges are a list of 0–6 boundary crossings; a single-crossing road is a terminus (semantically: "the road enters this 24-mile hex and ends here," likely at a settlement).

#### 5.2.4 Worked example

Consider a 6-mile inset of 16 child cells covering one 24-mile parent hex `P = (0,0)`, with a river running along the inset's N–S axis. The river is stored as 4 edge entries in `hex_river_edges`:

```
hex_river_edges in inset (canonical owner shown):
  {hex: (1,0), edge: 0, flow_clockwise: true, navigability: "river_craft", crossing: "bridge"}
  {hex: (1,1), edge: 0, flow_clockwise: true, navigability: "river_craft", crossing: "none"}
  {hex: (1,2), edge: 0, flow_clockwise: true, navigability: "river_craft", crossing: "none"}
  {hex: (1,3), edge: 0, flow_clockwise: true, navigability: "river_craft", crossing: "ford"}
```

The four child edges run along the boundary between children `(1, 0..3)` and children `(2, 0..3)`. Under the integer-floor mapping with `anchor=(0,0)` and ratio 4: all of `(1,*)` map to parent `(0,0)`, and all of `(2,*)` also map to parent `(0,0)`. So `P(A) == P(B)` for all four edges — **all four are internal to the same parent** and produce no parent overlay.

The river is invisible at the 24-mile scale because it doesn't cross a parent boundary anywhere in this inset. Correct: the river is wholly inside one 24-mile cell, so the strategic view shouldn't show it as a regional feature.

Now consider the alternative — the inset covers two adjacent 24-mile parents `(0,0)` and `(1,0)`, and the same river runs along the boundary between them. Now `P((1, k))` and `P((2, k))` produce different parent hexes for each `k`, so all four child edges are parent-boundary edges. They all describe the same parent edge — the boundary between `P=(0,0)` and `P=(1,0)`. Step 3 deduplicates and emits one parent river edge:

```
parent_hex_river_edges:
  {hex: (0,0), edge: <facing (1,0)>, flow_clockwise: true,
   navigability: "river_craft", crossing: "ferry"}
   # crossing resolved to "ferry" because the most-permissive
   # child crossing was the bridge or ford — wait, neither is ferry,
   # so the resolution picks "bridge" as most-permissive.
   # (Corrected example: crossing = "bridge".)
```

The single parent river edge correctly summarizes "this 24-mile parent boundary carries a navigable river with a bridge somewhere along it." The exact location of the bridge within the boundary is detail recoverable only by re-zooming.

### 5.3 Reversibility note

The aggregation rule is intentionally lossy. Reversing it to recover the child detail from the parent is the inheritance rule's job (§6), and the result is not (and cannot be) bit-identical to the original child. Aggregation + inheritance is a *resolution-changing* projection, not an isomorphism. The consistency check (§7) accommodates this: it requires the parent to be "at least as conservative as" the aggregation, not bit-exactly equal to it.

---

## 6. Inheritance Rule (Parent → Child)

Used when authorship flows down: procedural 24-mile parent → procedurally generated 6-mile inset at zoom-in time. This section specifies the complete terrain inheritance algorithm. Three concerns that touch other systems — settlement/POI re-keying, coastline geometry re-authoring for coastal parents, and overlay child-scale detail expansion — are owned by [`gdd-poi-generation.md`](gdd-poi-generation.md), a future water-geometry sub-pass, and [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md) respectively. This GDD specifies the *terrain tag* inheritance; those three concerns consume the resulting tags but produce their own outputs on top.

### 6.1 Principles

1. **Parent tags seed the child distribution.** The 16 children of a parent hex inherit the parent's `biome`, `elevation`, `civilization`, and `biome_subtype` as their default starting values, then deviate per the variation budget (§6.4).
2. **Variation is deterministic and seeded.** Each child's deviation uses a noise source seeded by `(campaign_seed, parent_q, parent_r, child_local_q, child_local_r)`. Re-running zoom-in on the same parent must produce the same children, bit-for-bit, regardless of when it is run.
3. **Variation is spatially coherent, not salt-and-pepper.** Deviating children cluster — a "woods" parent with 25% biome variation produces 2–3 contiguous clearings, not 4 scattered single-cell clearings. The clustering model is specified in §6.5.
4. **Water tags do not propagate by area.** A pure `ocean` parent produces 16 ocean children; a *coastal* parent (where aggregation produced `ocean` because ≥40% of original children were ocean but <100%) cannot be faithfully re-expanded from the parent alone — the coastline geometry was lost in the aggregation. Procedural zoom-in treats the parent's water tag as a *constraint* ("this region has coastline somewhere") and invokes a coastline placement sub-pass to re-author the boundary. The coastline sub-pass is owned by a future water-geometry GDD; this GDD specifies only the *invocation condition* (§6.6).
5. **Overlay edges constrain children to touch parent-edge crossings.** A parent river entering on edge N must produce a child cell on the inset's N boundary that carries a river entry on its N edge, and similarly for the flow exit. The child-scale path between entry and exit (meander, side channels, exact cell sequence) is detail added by zoom-in's overlay-expansion sub-pass, owned by [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md). This GDD specifies the *boundary constraint*, not the path generation.
6. **Consistency invariant.** Zoom-in output must satisfy the aggregation rule (§5) when fed back through it. For each parent `P`, the children produced must aggregate back to tags the consistency check (§7) accepts as agreeing with `P`. The inheritance rule is the inverse-consistent dual of aggregation, though not a bit-exact inverse (§5.3).

### 6.2 Child indexing

Within a parent hex, child cells are indexed by their offset from the parent's containing region. For a parent at `(parent_q, parent_r)` and the canonical 4× scale ratio, the 16 children are addressed by `(child_local_q, child_local_r)` for `child_local_q, child_local_r ∈ {0, 1, 2, 3}` with the global child coordinate computed as:

```
child.q = parent_q * 4 + child_local_q
child.r = parent_r * 4 + child_local_r
```

This matches the integer-floor containment formula in §5.2.1 (each child's `P(child)` recovers `(parent_q, parent_r)` exactly).

### 6.3 Algorithm — terrain tag inheritance

For each parent hex `P` to be zoomed:

```
1. SEED → derive a per-parent seed:
     parent_seed = hash(campaign_seed, P.q, P.r)
2. PRODUCE 16 CHILDREN → for each (cqi, cri) in {0..3} × {0..3}:
     child = new HexCell at (P.q*4 + cqi, P.r*4 + cri)
     child.elevation     = P.elevation     (default; deviates in step 4)
     child.biome         = P.biome         (default; deviates in step 4)
     child.biome_subtype = P.biome_subtype (default; deviates in step 4)
     child.water         = (see step 5)
     child.civilization  = P.civilization  (default; deviates in step 4)
     child.has_city      = false           (set true on one child in step 6)
3. PER-CHILD NOISE → for each child, compute:
     child_noise = hash(parent_seed, cqi, cri)  → uniform float in [0, 1]
4. APPLY VARIATION → for each layer in the order
     [elevation, biome, biome_subtype, civilization]:
       a. select_deviating_children(layer) via §6.4 + §6.5
       b. assign deviation values via §6.4 (deviation distribution)
5. WATER RESOLUTION → §6.6
6. CITY RE-KEY → if P.has_city, select exactly one child as the
   city carrier via deterministic noise; that child gets has_city=true.
   Selection: pick the child with the highest child_noise. Tied case
   broken by lowest (cqi, cri) lexicographic order. Settlement record
   itself is placed by gdd-settlement-stocking.md against the new child.
7. OVERLAY EXPANSION → handle rivers and roads separately:
   a. RIVERS: for each parent river edge between P and P_neighbor,
      pick a child edge (or short chain of child edges) along the
      corresponding inset boundary and emit it as a child river edge
      in the new inset's hex_river_edges table. The chosen edge
      inherits the parent's flow_clockwise, navigability, and
      crossing fields. The child edge selection prefers the edge
      whose noise-perturbed position best matches the parent's edge
      midpoint; sub-hex meander is added by gdd-region-zoom-in.md's
      overlay-detail sub-pass.
   b. ROADS: for each parent road edge, mark the corresponding inset
      boundary child cells with a road_edges entry pointing along
      that parent edge. Road path interior to the inset is generated
      by gdd-region-zoom-in.md, biased toward cleared and civilized
      terrain.
8. EMIT → write 16 new hex_cells rows for the new child map.
```

The algorithm is total (every layer is resolved for every child) and deterministic (same parent + same seed produces identical children every time).

### 6.4 Variation budget and deviation distribution

For each varying layer, two parameters: the **budget** (what fraction of children may deviate) and the **deviation distribution** (which tag values deviating children receive).

| Layer | Budget | Deviation distribution |
|---|---|---|
| `elevation` | ≤10% of children deviate. Min 0, max ~1–2 children of 16. | A deviating child shifts one step in the ordering `flat ↔ hills ↔ mountains`. From `flat`: 100% become `hills`. From `hills`: 50% `flat`, 50% `mountains`. From `mountains`: 100% become `hills`. Two-step jumps (`flat → mountains`) are not produced by inheritance. |
| `biome` | ≤25% of children deviate. ~3–4 children of 16. | A deviating child picks from biomes one impedance step away in the ordering `swamp > jungle > woods > desert > clear`. From `clear`: 70% `woods` (groves/copses), 30% `desert` (rocky patches). From `woods`: 70% `clear` (clearings), 30% `jungle` only if parent latitude permits, else 30% redirected to `clear`. From `desert`: 60% `clear`, 40% `desert` with `desert_badlands` subtype. From `jungle`: 80% `woods`, 20% `swamp`. From `swamp`: 80% `jungle`, 20% `woods`. The asymmetric percentages reflect ecological transition realism — jungles fray to woods more than to swamps. |
| `biome_subtype` | ~20% of children deviate from the parent's subtype, but only if the parent has a non-empty subtype. The deviation is "clear the subtype" (revert to parent biome with no refinement). | Deviating children's subtype is set to `""` (no refinement). Inheritance does NOT introduce a new subtype where the parent has none, nor switch one subtype to another. Subtypes are introduced by world-gen at the parent scale; zoom-in only relaxes them. |
| `civilization` | ≤5% of children deviate. ~0–1 children of 16. | A deviating child shifts one step in `civilized ↔ borderlands ↔ wilderness`. From `civilized`: 100% `borderlands` (outlying hamlets, contested edges). From `borderlands`: 60% `civilized` (interior strongpoints), 40% `wilderness` (unsettled gaps). From `wilderness`: 100% `borderlands` (occasional outposts). |
| `water` | Not varied by budget; resolved by §6.6. | — |
| `has_city` | Not varied; carried over exactly per §6.3 step 6. | — |

The percentages are deterministic given the seed: the algorithm computes `child_noise` per child, sorts children by noise within each layer, and the top-`budget` slice deviates. The deviation distribution then determines what each deviating child becomes by a second hash on `(parent_seed, cqi, cri, layer)`.

### 6.5 Spatial coherence

Naive per-child noise produces salt-and-pepper patterns: deviating children scattered randomly across the parent. Real terrain has clustered variation — clearings are connected, hills form ridges, civilized pockets are contiguous. The inheritance algorithm imposes spatial coherence by **noise post-processing**:

After computing `child_noise` per child (§6.3 step 3), apply a single round of neighborhood smoothing:

```
smoothed_noise[c] = 0.5 * child_noise[c]
                  + 0.5 * average(child_noise[c'] for c' in neighbors_in_parent(c))
```

where `neighbors_in_parent(c)` is the set of child cells in the same parent that are adjacent to `c` (1–6 cells, depending on `c`'s position within the parent — corner children have fewer in-parent neighbors). Smoothing happens once; further iterations would blur the noise to uniformity.

Selection then uses `smoothed_noise` instead of raw `child_noise` for the per-layer top-budget slice. The effect: deviating children tend to cluster because adjacent children share neighborhood averages and therefore receive similar smoothed values. A child whose own noise is high but whose neighbors' noise is low gets pulled toward the parent default; a child whose own noise is moderate but whose neighbors' noise is high gets pulled toward deviation. Net: clusters of 2–3 contiguous deviating children, with isolated single-cell deviations suppressed.

This is intentionally simple. More sophisticated coherence (Voronoi region assignment, true cellular automata, learned terrain templates) is a future tuning opportunity, but the single-round smoothing is sufficient for the corpus of biome/elevation/civilization variation that ACKS terrain needs at the inset scale.

### 6.6 Water resolution

Water tags do not propagate by area; the resolution depends on the parent's water tag and the original aggregation context.

- **Parent `water = ""` (none).** All 16 children get `water = ""`. No lake/ocean introduction by inheritance.
- **Parent `water = "ocean"` AND the parent is fully oceanic (no land children in any plausible reconstruction).** All 16 children get `water = "ocean"`. Recognition: the parent has no land neighbors in any direction at parent scale — interior open ocean.
- **Parent `water = "ocean"` AND the parent is coastal (has at least one land neighbor at parent scale).** Inheritance defers coastline placement to a coastline sub-pass owned by a future water-geometry GDD. That sub-pass receives the parent's land-neighbor directions and produces a coastline geometry consistent with them. Until that sub-pass exists, the placeholder behavior is: 8 children on the side toward land neighbors get the parent's pre-aggregation biome (typically `clear`), 8 children on the opposite side get `water = "ocean"`. The exact assignment is parameterized but predictable; the placeholder is good enough to not crash downstream consumers, and the proper sub-pass replaces it later.
- **Parent `water = "lake"`.** All 16 children get `water = "lake"` (same logic as fully-oceanic ocean — lakes large enough to register at 24-mile scale fully cover their parent hex). Note that under the §5 aggregation, a parent only becomes `lake` if ≥40% of children were lake; in practice a lake covering an entire 24-mile hex is enormous (e.g., a Great-Lakes-tier feature) and its full-coverage children are correct.
- **Children in a non-water parent never get `water` tags by inheritance.** Small lakes inside a `clear` 24-mile parent are below the abstraction's resolution and are not introduced by zoom-in; they would be introduced by content-placement passes (POI generation, hand-authoring DLC).

### 6.7 What inheritance does NOT produce

- **Settlements, lairs, POIs, dungeons.** Placed by [`gdd-poi-generation.md`](gdd-poi-generation.md) and `gdd-settlement-stocking.md` against the resolved child map. Step 6 of the §6.3 algorithm selects *which child* a parent-scale city resides on; the settlement record itself is placed by the stocking system, not by terrain inheritance.
- **Encounter tables.** Computed per hex from the resolved tags, identically at every scale ([`gdd-terrain-system.md`](gdd-terrain-system.md) §4). Inheritance does not pre-compute encounter weights.
- **Fog of war / exploration state.** Per-map runtime data keyed to `(party_id, map_id, q, r)`. Not migrated across scales by inheritance or by anything else. See §9.
- **Overlay child-scale detail.** The §6.3 step 7 boundary constraints fix where rivers/roads must touch the inset boundary, but the actual path between constraints (meander, branch points, side channels) is produced by an overlay-expansion sub-pass owned by [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md). That sub-pass uses the terrain tags inheritance just produced as input (rivers prefer to flow through swamp and jungle; roads prefer cleared, civilized terrain).
- **Coastline geometry for coastal parents.** Owned by a future water-geometry sub-pass per §6.6. Inheritance specifies the invocation condition; the sub-pass owns the algorithm.

---

## 7. Consistency Check Semantics

The repository helpers `check_domain_cross_scale_consistency` and the broader cross-scale invariants enforce that linked maps agree on the regions they both cover. The semantics below extend the migration-119 implementation to terrain tags (the migration shipped domain-membership consistency only; terrain-tag consistency is the natural next layer).

### 7.1 Terrain-tag consistency

Given a parent map `M_p` and a child map `M_c` with `parent_map_id = M_p.id`, for each parent hex `P` in `M_c.parent_hex_footprint`:

1. Compute the aggregated tags `A(P)` by running §5 against the child cells inside `P`.
2. Compare `A(P)` to `P`'s actually-stored tags.
3. The check **passes** for `P` if, for each tag layer, `P`'s stored value is **at least as conservative as** `A(P)`. Conservatism per layer:
   - **elevation**: `P ≥ A(P)` in the order `mountains > hills > flat`. Parent can claim mountains where aggregation says hills (legal; conservative for travel). Parent cannot claim flat where aggregation says hills (illegal; understates impedance).
   - **biome**: `P ≥ A(P)` in the impedance order `swamp > jungle > woods > desert > clear`. Same direction as elevation.
   - **water**: `P` must match `A(P)` exactly. Water is too significant a feature to be "approximately."
   - **civilization**: `P ≤ A(P)` in the order `civilized > borderlands > wilderness`. Parent can claim borderlands where aggregation says civilized (conservative for encounter rolls). Parent cannot claim civilized where aggregation says wilderness (overstates the security of the region).
   - **has_city**: must match exactly.
   - **subtype**: parent may have a different subtype than `A(P)` produces only if the parent's subtype is a strict refinement of the aggregated parent biome. A mismatched parent biome with mismatched subtype fails.
4. If the check fails for any layer of `P`, the diff is surfaced in the helper's return value. The helper never auto-fixes.

### 7.2 Domain-membership consistency (shipped in migration 119)

Already implemented in `check_domain_cross_scale_consistency`. Restated here for completeness:

1. **Parent-claim implies child-claim**: if a domain owns parent hex `P` and `P` lies in some child inset's footprint, the domain must also own every child hex inside `P` that lies in the inset — *unless* those child hexes are owned by a different domain (in which case the helper flags `blocked_by_other_domain` rather than `missing_child_hexes`).
2. **Child-claim implies parent-claim**: if a domain owns any child hex `C` and `C` lies inside parent hex `P` for some inset, the domain must also own `P`.

`compute_consistent_domain_hex_set` iterates these two rules to a fixed point (bounded at 8 passes) and returns the union the caller would need to commit to make the domain consistent. The caller chooses whether to commit.

### 7.3 Conservative-direction principle

Both consistency layers share the same design principle: **the parent is allowed to be at least as conservative as aggregation, but never less conservative**.

- "Conservative" for terrain means "represents the region as harder to travel through / harder to find friendly faces in / harder to predict encounters in." This is the safer direction for player expectation — the strategic map should not promise the player a clear plain that turns out to be a forest at the regional view.
- "Conservative" for domain membership means "the domain's claimed hex set is the closure of its claims under the cross-scale rules." A domain that claims a parent hex implicitly claims the inset region within; refusing to commit those child hexes is a partial claim, and the helper flags that gap.

The asymmetry is intentional. Players are forgiving of "the strategic view oversimplified — the actual region is harder than the map suggested." They are not forgiving of the inverse. Conservative aggregation matches that asymmetry.

### 7.4 What the check does NOT enforce

- **POI/lair/settlement placement.** Those are point features with their own placement systems; they pass through the linkage but are not part of the terrain consistency invariant.
- **Cross-scale fog of war.** Exploration state is per-map; see §9.
- **Realm hierarchy.** The realm/vassalage relationships between domains are a separate concern (see `gdd-domain-tab.md`); cross-scale consistency only governs the hex membership of a single domain.

---

## 8. Integration Points

### 8.1 Consumers

- **`hex_map_renderer`** ([`scenes/maps/hex_map_renderer.gd`](../scenes/maps/hex_map_renderer.gd)): consumes `parent_map_id`, `parent_anchor`, and `parent_hex_footprint` to decide which map to render under the Strategic ⇄ Regional camera-mode toggle. Walks the `parent_map_id` chain to find the topmost ancestor for Strategic view. Resolves party-token render positions across scales via `_resolve_party_render_position`.
- **Party movement** ([`engine/autoloads/campaign_repository.gd:transition_party_to_map`](../engine/autoloads/campaign_repository.gd)): the shipped data-layer write that moves a party between linked maps. Emits `EventBus.party_map_changed(party_id, from_map_id, to_map_id)`. Does not migrate per-hex state.
- **Domain system** ([`gdd-domain-tab.md`](gdd-domain-tab.md), `treasury.gd`, `stronghold_repository.gd`, `domain_handlers.gd`): reads `get_domain_hexes(domain_id)` which now returns rows across all maps the domain touches. Single-map call sites continue to use `(hex_q, hex_r)` match and ignore `map_id`; multi-map awareness uses `get_domain_hexes_on_map(domain_id, map_id)` or the cross-scale helpers.
- **Encounter / movement systems**: read terrain tags at whichever scale the party currently occupies. The scale a party operates at is `parties.current_map_id`'s scale; no cross-scale composition of encounters or movement is performed at runtime.
- **Procedural zoom-in pass** (planned, [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md)): consumes §6 (Inheritance Rule) as its design contract.
- **Setting-generation pipeline** ([`gdd-setting-generation.md`](gdd-setting-generation.md) §13): the existing reference to "Region zoom-in (`gdd-hex-subdivision.md`, future)" is now satisfied by this document for the *rules*; the *implementation* awaits `gdd-region-zoom-in.md`.

### 8.2 Producers

- **`gdd-setting-generation.md`**: produces 24-mile campaign maps procedurally. After this GDD is in place, the setting-generator's output is the **authored parent** in mode "procedural campaign" (§4.2).
- **Hand-authoring (Worldographer + JSON conversion)**: produces 6-mile insets and the surrounding 24-mile context. Authored child + authored parent footprint, in mode "hand-authored test map" (§4.2).
- **Region zoom-in pass** (planned): produces 6-mile insets from a 24-mile parent, satisfying §6.

### 8.3 Cross-cutting interfaces

- **`HexMapData` shared type**: carries `parent_map_id`, `parent_anchor`, `parent_hex_footprint` and exposes `has_parent()`, `footprint_to_json_array()`, `footprint_from_json_string()`, `scale_compare_coarseness()`.
- **`CampaignRepository` cross-scale methods** (shipped in migration 119): `validate_hex_map_parent_linkage`, `transition_party_to_map`, `check_domain_cross_scale_consistency`, `compute_consistent_domain_hex_set`, `get_hex_map_parent_id`, `get_hex_map_parent_footprint`, `list_child_maps`, `get_domain_hexes_on_map`.
- **`EventBus.party_map_changed(party_id, from_map_id, to_map_id)`**: the cross-scale party transition signal.
- **Camera-mode UI** (`WildernessExploreState`, [`scenes/maps/hex_map_renderer.gd`](../scenes/maps/hex_map_renderer.gd)): consumes the linkage to provide Strategic ⇄ Regional projection. Documented in the 2026-05-19 `build_log.md` entry; not redocumented here.

### 8.4 EventScheduler interaction

[`gdd-realtime-scheduler.md`](gdd-realtime-scheduler.md) is the project's event-driven game-clock. Any future procedural zoom-in pass operates as a **scheduled event** triggered by a `zoom_in_requested` action (e.g., the party approaches the edge of an existing region and a new region needs lazy-generation). The scheduler runs the zoom-in to completion before resuming party movement, since the new child map must exist before the party can be relocated onto it. The scheduler is not modified by this GDD; the integration is purely "future zoom-in events use this GDD's rules."

---

## 9. Open Questions / Architectural Concerns

- **Fog-of-war cross-scale propagation.** If the party fully explored a 6-mile inset that sits inside a 24-mile parent, should the parent's footprint hexes appear "explored" in Strategic view? The intuitive answer is yes — the player obviously knows what's in those hexes at the coarse scale. But the data is per-map; no system currently composes fog across scales. Recommend: when a child hex's `fog_state = 'visible'` or `'explored'`, the corresponding parent hex (if in the inset's footprint) is shown as at least `'explored'` in Strategic view. Defer the implementation rule until the Strategic-view "has inset" highlight (the deferred polish from the 2026-05-19 entry) is being added; bundle the two visual treatments.
- **Reverse direction: parent-view exploration revealing child hexes.** If the party scouts a 24-mile hex via aerial reconnaissance (a future system) without entering the inset, should the inset's child hexes become `'explored'`? Probably no — coarse-scale knowledge does not constitute fine-scale knowledge. But if/when aerial scouting ships, this needs a decision.
- **3-level nesting (`local_15mi` insets inside `regional_6mi` insets).** Schema supports it; aggregation and inheritance rules apply recursively. No use case is currently defined. The Strategic camera-mode toggle already walks to the topmost ancestor, so it handles 3-level depth correctly. Tactical/dungeon-overworld use is the most likely consumer (a 1.5-mile overland inset around a major dungeon entrance). Treat as reserved for future tactical work; no new features needed until a concrete consumer appears.
- **Boundaries between this GDD and `gdd-region-zoom-in.md`.** This GDD specifies terrain-tag inheritance fully (§6.3–§6.6). Three sub-passes are explicitly out-of-scope and owned by the future zoom-in GDD: (1) overlay child-scale detail — the path generation between the boundary constraints §6.3 step 7 produces; (2) coastline geometry for coastal parents — invoked by §6.6 but the algorithm is water-geometry-owned; (3) settlement placement against the city-carrier child §6.3 step 6 selects — placement is `gdd-settlement-stocking.md`'s job. When `gdd-region-zoom-in.md` is written, it should cite this GDD as its terrain-tag input and own only those three sub-passes.
- **Hex-in-hex containment is approximate.** §5.2.1 uses integer-floor division to assign each child to one parent, but hex-on-hex tessellation at same orientation does not tile cleanly — there's an unavoidable approximation along parent boundaries. The chosen formula is deterministic and reversible (the §6.2 child-indexing formula recovers the parent), so the system is self-consistent. It may produce slightly counterintuitive boundary assignments in edge cases (e.g., a child cell whose "geometric center" is near a parent corner). Acceptable for v1; if playtest surfaces concrete confusion, switch to a more sophisticated point-in-hex test.
- **Terrain-tag consistency check is not yet implemented.** Migration 119 shipped the domain-membership consistency check; the terrain-tag consistency check (§7.1) is specified here but not yet in code. Should be added when the first multi-source map pair is committed (hand-authored child + hand-authored parent), since that's the first scenario where the parent and child can be authored to disagree. Until then the check is moot — the only existing test data has a single source per region.
- **Aggregation thresholds (30% for woods-over-clear, 40% for water, 50% for subtype) are first-pass estimates.** They are tunable engineering decisions. Playtesting hand-authored maps may reveal that woods bleed at 30% feels too aggressive (every grassland with a small wood becomes "woods") or too soft (real forest hexes get demoted to clear). Treat the values as draft parameters; revise when concrete cases surface.
- **Conservative-direction asymmetry assumes player expectation patterns.** §7.3 asserts that players are forgiving of "the strategic map oversimplified the terrain as easier than it is" and unforgiving of the reverse. If playtesting shows the opposite — players want the strategic map to optimistically project clear paths — flip the asymmetry. The rule itself is a one-line change; the implications for content authoring are larger.
- **Hand-authored DLC is a stated future direction.** The 2026-05-19 design discussion captured in `build_log.md` notes that hand-authored content may return as DLC modules. This GDD's hand-authoring workflow (§4.2 "hand-authored test map" mode) is the path that supports that — the same tooling that builds dev test maps will build DLC modules. No additional architecture needed; just naming the dual purpose so future sessions don't strip the hand-authoring path under the assumption that "production is all procgen."

---

## 10. Revision History

- **2026-05-22 (revision):** §5.2 river aggregation rewritten for the edge-based river model (see `gdd-terrain-system.md` §3.6). River aggregation collapses to a single-pass scan of `hex_river_edges`, classifying each child river edge as parent-internal (drop) or parent-boundary (emit). Deduplication, flow-direction agreement check, navigability max-tier, and most-permissive crossing resolution specified. §6.3 step 7 split into rivers (emit child river edge along parent boundary with inherited fields) and roads (cell-attached, generated by zoom-in). Worked example replaced.
- **2026-05-22:** Initial draft. Codifies the cross-scale terrain model that the migration-119 schema (2026-05-19) and the Option 4 camera-mode UI (2026-05-19) jointly imply. Distinguishes spatial parent/child from authorship direction; specifies the complete aggregation rule including the river/road overlay algorithm (§5), the complete terrain-tag inheritance algorithm (§6) with deterministic seeding, deviation distributions, and spatial coherence, and consistency-check semantics extended to terrain tags (§7). Bounds three sub-passes (overlay path generation, coastline geometry, settlement placement) out to [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md) and [`gdd-settlement-stocking.md`](gdd-settlement-stocking.md) by their invocation conditions, not by hand-waving. Fills the placeholder reference in [`gdd-setting-generation.md`](gdd-setting-generation.md) §13 and the corresponding integration point in [`gdd-terrain-system.md`](gdd-terrain-system.md) §11.
