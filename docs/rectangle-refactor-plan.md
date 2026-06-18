# Rectangle Refactor Plan — axial-rectangle → offset-rectangle setting grid

**Status:** PRE-IMPLEMENTATION ANALYSIS — no code has been changed. This document is a green-light
package for Jedidiah. Nothing in `engine/`, no migration, and no generator run was touched producing it.

**Author:** Build agent (Opus 4.8), 2026-06-17. Method: 8-angle multi-agent code trace, each hypothesis
adversarially verified against source (16 agents). Every claim below carries a `file:line`.

**The decision (Jedidiah):** Generated worlds currently render as a **parallelogram**; make them render as a
clean **rectangle** by laying the generator's hexes on an **offset-rectangle** grid. Keep faithful axial hex
adjacency. Change the *shape the generator lays hexes onto* and the *latitude/visual-row mapping* — **not** the
shared axial coordinate core, and **not** the renderers.

---

## 0. The one-paragraph mental model

Today the generator's grid-creation loop treats `(q, r)` as **simultaneously** "the axial label" and "the
`(col, row)` I enumerate" — they coincide (`q == col`, `r == row`), so the stored hex set is an
*axial*-rectangle (`q∈[0,W), r∈[0,H)`). The shared even-q render transform
`axial_to_godot_map(q,r) = (q, r + (q-(q&1))/2)` ([hex_map_controller.gd:126-130](engine/subsystems/exploration/hex_map_controller.gd:126))
then shears that axial-rectangle into a **parallelogram** on screen. The refactor **separates the two roles**:
enumerate a clean rectangle in **offset space** (`for row: for col:`), derive the axial label for
storage+adjacency via the *inverse* even-q transform (`q = col; r = row - (col-(col&1))/2`, which is exactly
[`godot_map_to_axial`](engine/subsystems/exploration/hex_map_controller.gd:134)), and derive **semantic
latitude / visual-row from `row`, not from axial `r`**. Everything that consumes the axial label unchanged
(`_OFF` adjacency, `_hex_center` noise embedding, edge encoding, both renderers) keeps working untouched,
because the render transform `axial_to_godot_map` is the exact inverse of the offset→axial derivation — they
compose back to the clean `(col, row)` rectangle. **Net: one grid-creation site changes shape, one climate
line decouples latitude, ~8 full-grid re-walk loops route through a shared enumerator, and two small
outline-bbox bugs get fixed. Renderers and all runtime (combat/dungeon/exploration) are untouched.**

---

## A. IMPACT MAP

### A.0 — The load-bearing simplification: there is exactly ONE place hex keys are born

A repo-wide grep for `grid[...] = {` across `engine/subsystems/generation/world/*.gd` returns **exactly one
key-creation site**: [heightmap_generator.gd:59-63](engine/subsystems/generation/world/heightmap_generator.gd:59).
Every other `(q,r)` touch in the generators **re-indexes a pre-existing key** (and `KeyError`s if absent).
This means the *shape* of the world is defined in one loop; everything else either consumes that shape's keys
for adjacency (safe) or re-walks them assuming the axial-rectangle bounds (must be routed through a shared
enumerator).

### A.i — Sites that use `q`/`r` purely for ADJACENCY → SAFE, do not touch

These consume the axial label only for neighbor/distance/edge math. A relabel that preserves axial adjacency
(which this is) leaves them correct.

| Site | What | Verdict |
|---|---|---|
| [hex_map_controller.gd:69-90](engine/subsystems/exploration/hex_map_controller.gd:69) | `get_neighbors`, `hex_distance`, `is_adjacent`, `get_hex_ring` | Pure axial. Untouched. |
| `const _OFF` × **8 generator files** | `region_painter.gd:17`, `history_simulator.gd:25`, `heightmap_generator.gd:44`, `climate_generator.gd:63`, `culture_seeder.gd:71`, `infrastructure_generator.gd:34`, `name_generator.gd:24`, `poi_generator.gd:13` | **Byte-identical** `[(0,-1),(1,-1),(1,0),(0,1),(-1,1),(-1,0)]`, verified by normalized diff. Pure adjacency. **Do not reorder** (see edge-index note). Untouched. |
| [hex_river_edge_data.gd:31-38](engine/shared_types/hex_river_edge_data.gd:31) | `EDGE_NEIGHBOR_OFFSETS` (the canonical, edge-labelled copy: 0=N…5=NW) + `opposite_edge=(e+3)%6` | The de-facto single source the per-file `_OFF` copies mirror. Untouched. |
| [stronghold_repository.gd:245-257](engine/subsystems/strongholds/stronghold_repository.gd:245) | `_axial_neighbors` — a verbatim duplicate of `get_neighbors` | Pure adjacency. Untouched. |
| [culture_seeder.gd:187-199](engine/subsystems/generation/world/culture_seeder.gd:187) | `_coastal_set` — coast = "has an `_OFF` neighbor that is ocean", grid-membership gated | **This is the CORRECT outline-agnostic pattern.** Use it as the model for the bbox fixes below. |
| [culture_seeder.gd:565-568](engine/subsystems/generation/world/culture_seeder.gd:565) | `_hex_distance` axial cube distance | Invariant under relabel. |

**Edge-index sub-note (do NOT reorder `_OFF`):** index-into-`_OFF` **is** the stored river/road/vertex `edge`
id at [region_painter.gd:338](engine/subsystems/generation/world/region_painter.gd:338) /
[region_painter.gd:750](engine/subsystems/generation/world/region_painter.gd:750)/`:773`,
[history_simulator.gd:227](engine/subsystems/generation/world/history_simulator.gd:227)/`:244`,
[heightmap_generator.gd:279](engine/subsystems/generation/world/heightmap_generator.gd:279)/`:356`,
[climate_generator.gd:200](engine/subsystems/generation/world/climate_generator.gd:200). The relabel does
**not** require touching `_OFF`, and must not — reordering it would corrupt every river/road/coast edge. This
is the **only render-side contract the refactor must hold invariant.**

**Runtime (combat / dungeon / exploration) — H7 CONFIRMED shape-agnostic, UNTOUCHED:**
- Bounds are dictionary membership, never a rectangle: [hex_map_data.gd:75-77](engine/shared_types/hex_map_data.gd:75)
  `is_valid_coord = hexes.has(coord)`. Fog/move/path all clip through it or `get_neighbors`.
- Combat & dungeon do **not** use the world hex map — they run on a **separate** square/Chebyshev tactical grid
  ([isometric_grid.gd:50](engine/shared_types/isometric_grid.gd:50)) over a sparse `Vector3i` dict
  ([voxel_map_data.gd:62](engine/shared_types/voxel_map_data.gd:62)).
- **No `2D-array-by-(col,row)` store exists anywhere in runtime** (both `HexMapData.hexes` and
  `VoxelMapData._cells` are sparse Dictionaries) → **negative axial `r` introduced by the offset-rectangle is
  safe** at runtime. `grid_width/grid_height` appear only in dungeon-*layout* output docstrings, never as a
  world-map outline.
- Runtime weather ([weather_generator.gd:147](engine/subsystems/exploration/weather_generator.gd:147)) takes
  `hemisphere` as a passed String, **never** derives latitude from `hex_r`; `hex_q/hex_r` appear only as
  RNG-seed salt. Confirmed not a latitude coupling.

### A.ii — Sites that use `r` as LATITUDE / SEMANTICS / VISUAL-ROW / OUTLINE → **MUST decouple/fix**

This is the high-risk set. Four sites.

1. **`climate_generator.gd:108-115` — THE load-bearing latitude coupling (priority #1).**
   [climate_generator.gd:114](engine/subsystems/generation/world/climate_generator.gd:114):
   ```
   var lat: float = lat_south + lat_span * (float(height - 1 - r) / maxf(height - 1, 1))
   hex["effective_latitude"] = lat
   ```
   `r` is used as the visual north-south row (`r=0` = north edge). Temperature
   ([:117](engine/subsystems/generation/world/climate_generator.gd:117)) = `f(lat²)`, and the **entire climate
   cascade** hangs off it: `lat → temperature → Köppen → biome → swamp → land_value` (verified: `_assign_biome`,
   `_apply_swamp_pass`, `_assign_land_values` have **no independent r-dependence** — they inherit through
   temperature only). Exhaustive grep for any `r→fraction→semantics` computation across all of `world/` found
   **this is the unique site.** **Decouple: compute latitude from the offset `row`, not axial `r`.**
   - `effective_latitude` **is** a persisted column ([setting_repository.gd:22](engine/subsystems/generation/world/setting_repository.gd:22),
     `setting_hexes.effective_latitude REAL`) but is **read back only by tests** (`test_setting_stage1.gd:88`,
     `stage0:249`, `stage4a:49`) — **no runtime/generator consumer**. The materializer **drops it**
     (`hex_cells` has no such column). So the decouple is fully contained to the climate writer + its tests.

2. **`climate_generator.gd:156-165` — `_rain_shadow` directional `-q = west` (priority #3, decide consciously).**
   [climate_generator.gd:158](engine/subsystems/generation/world/climate_generator.gd:158)
   `upwind = Vector2i(key.x - k, key.y)` treats `-q` as "upwind/west" (prevailing wind W→E). `q` stays the
   column under even-q so this is *approximately* preserved, but a constant-`r`/`-q` step does **not** trace a
   flat visual west line (odd columns step a half-row). Local 4-hex modifier, low blast radius. **Decision
   needed:** leave as axial-`q` (cheap, slightly skewed) or walk the offset column for true visual-west.

3. **`region_painter.gd:685-690` — ocean-vs-sea bbox edge test (priority #2, genuine bug under relabel).**
   [region_painter.gd:687](engine/subsystems/generation/world/region_painter.gd:687)
   `if h.x == 0 or h.y == 0 or h.x == width-1 or h.y == height-1:` classifies open water as ocean (edge-touching)
   vs sea (enclosed). It assumes every visual row spans axial `q∈[0,W-1]` — **true only for the axial-rectangle.**
   Under offset-rectangle the stored axial `q` per visual row is sheared, so a hex on the visual border may have
   `q ∉ {0, W-1}` and an interior hex may spuriously hit `q==0`. **This is the only min/max-bounds edge test in
   the generators.** **Fix: replace with the off-grid-neighbor test** — the correct pattern already exists **in
   the same file 437 lines above** at [region_painter.gd:248-251](engine/subsystems/generation/world/region_painter.gd:248)
   (`_is_land(grid, nb)`, "touches only water/the map edge") and at `culture_seeder._coastal_set`.

4. **`heightmap_generator.gd:130-136` — continental falloff from assumed corners (priority #2).**
   [heightmap_generator.gd:130](engine/subsystems/generation/world/heightmap_generator.gd:130) computes the
   falloff center as the midpoint of `_hex_center(0,0)` and `_hex_center(W-1,H-1)`, and `max_dist` over the four
   axial corners `(0,0),(W-1,0),(0,H-1),(W-1,H-1)`. Those corners are the visual extremes **only for an
   axial-rectangle** (they form a parallelogram in `_hex_center` space). Under offset-rectangle the continents
   would be pushed off-center. **Fix (altitude — generalize, don't special-case): compute center and `max_dist`
   by min/max over `_hex_center` of the *actual enumerated hexes*, not from assumed corner coords.**

### A.iii — Grid-ENUMERATION sites (define / consume the shape)

**The shape-definition site (the only one that changes the key set):**
- [heightmap_generator.gd:59-63](engine/subsystems/generation/world/heightmap_generator.gd:59) — the `grid[key] = {…}`
  creation loop. **This is the minimal shape change.**

**Full-grid RE-WALK loops** (`for r in range(height): for q in range(width): … Vector2i(q,r)`) that re-index the
created keys and therefore assume the axial-rectangle bounds — each must iterate the **new** key set (via the
shared enumerator), or it will miss the sheared/negative-`r` keys and duplicate-miss:

| File | Lines | Role |
|---|---|---|
| `heightmap_generator.gd` | 141-142, 164-165, 189-190 | sibling fill / river-source loops |
| `climate_generator.gd` | 108-109, 173-174 (+ BFS/swamp passes) | latitude assign + ocean-distance + swamp |
| `region_painter.gd` | 135-136 (and 355/366/502/559) | connected-component scans |
| `culture_seeder.gd` | 189-190 (and 214/526/653/701) | substrate read/seed + `_pick_homeland` (**stream-order sensitive — see C**) |
| `history_simulator.gd:207-215` | `_build_ordered_keys` | builds `_ordered_keys` / `_land_keys` — **drives the replay RLE order (see C)** |
| `setting_generator.gd:117-126` | `_persist_hexes` | writes `q,r` rows to DB |

**Width/Height (`_MAP_DIMENSIONS`):** [setting_parameters.gd:74-79](engine/subsystems/generation/world/setting_parameters.gd:74)
(`small 15×12 … huge 60×45`) returned by `map_dimensions()` as `Vector2i(W,H)`. **Unchanged** — `W=columns`,
`H=rows` still holds; only the per-column `r`-derivation changes. The only semantic reuse of `H` is the
latitude formula (item A.ii.1).

**Materialization layer (UNMERGED — worktree `claude/kind-blackburn-c7a1b9`, NOT on `main`):**
- [setting_materializer.gd:128-157](.claude/worktrees/kind-blackburn-c7a1b9/engine/subsystems/generation/materialization/setting_materializer.gd) —
  `setting_hexes → hex_cells` is a **literal 1:1 axial copy** (`q,r` unchanged, identical PK vocab) and **drops
  `effective_latitude`** (not a `hex_cells` column). **Outline-agnostic; needs no change** — the relabel is
  entirely upstream of it. H6 CONFIRMED.
- [region_zoom_in.gd:170-220](.claude/worktrees/kind-blackburn-c7a1b9/engine/subsystems/generation/materialization/region_zoom_in.gd) —
  the 6-mile child subdivision `(pq,pr) → (pq*SUB+i, pr*SUB+j)`, `SUB=4`. Pure axial pass-through; inherits the
  world relabel safely. **Needs no change.**
- ⚠️ **`region_zoom_in.gd:63-71` — the 6-mile WINDOW selection RE-SHEARS (critical cross-cutting finding).**
  `build_start_region` carves the play window as a **fixed axial box**
  (`min_q = center.x - W/2; min_r = center.y - H/2; for dq: for dr: pq=min_q+dq, pr=min_r+dr`). That is an axial
  sub-rectangle → it renders as a **parallelogram window at the regional scale**, the *same shear bug one level
  down*. **Fixing only the world generator leaves the player's actual 6-mile play map a parallelogram.** When
  this branch merges, the window selection must enumerate by offset `col/row` (convert to axial), mirroring the
  heightmap fix. *(Plan-relevant now even though unmerged, because the world-gen fix is incomplete without it.)*

### A.iv — Render transforms → **NO CHANGE** (H3 CONFIRMED)

Both renderers funnel every `(q,r)` through the even-q transform and **measure their own extent from the data**,
so feeding them offset-rectangle axial coords renders a clean rectangle automatically:
- Gametime [hex_map_renderer.gd](scenes/maps/hex_map_renderer.gd): 15 `axial_to_godot_map`/`godot_map_to_axial`
  sites; iterates `_map_data.hexes.keys()` (never a `range` rectangle); camera limits
  ([:1250-1278](scenes/maps/hex_map_renderer.gd:1250)) are a measured pixel bbox. River-edge geometry
  ([:1103-1148](scenes/maps/hex_map_renderer.gd:1103)) is per-hex-local (edge `e` spans corners `(e+4)%6`,
  `(e+5)%6`), latitude/shape free.
- Review/replay [political_map_view.gd:326-333](scenes/ui/campaign_creation/political_map_view.gd:326) — post
  `31d8ad8`, `_center_of` inlines the even-q transform and `_neighbors`
  ([:411-415](scenes/ui/campaign_creation/political_map_view.gd:411)) returns axial deltas; extent measured in
  offset space ([:265-273](scenes/ui/campaign_creation/political_map_view.gd:265)). `_edge_vertex_offsets`
  ([:314-317](scenes/ui/campaign_creation/political_map_view.gd:314)) is a byte port of the gametime formula.

**One cosmetic caveat (verify, not block):** the two renderers share the axial→even-q *formula* but **not** a
pixel-identical layout — `hex_map_renderer` uses Godot's `TileMapLayer` (`TILE_OFFSET_AXIS_VERTICAL`), while
`political_map_view` hand-rolls the pixel layout and staggers the **even** column. They render the same axial
data with a column-parity difference. Harmless for the refactor (both reshape to a rectangle), but it means the
review-map outline and the gametime-map outline should be **eyeballed for true match** during verification.

### A.v — Persistence & determinism artifacts (cross-cutting)

| Artifact | File:line | Effect of relabel |
|---|---|---|
| `setting_hexes` PK `(campaign_id,q,r)` | [schema.sql:3586-3623](db/schema.sql:3586) | `INTEGER` cols; **negative `r` is fine**. Stores `effective_latitude` (the one r-derived semantic col). |
| `hex_cells` PK `(map_id,q,r)` | schema.sql:657-695 | Only `q,r` + outline-agnostic terrain. Clean. |
| `setting_river_edges (hex_q,hex_r,edge)` | [schema.sql:3630-3643](db/schema.sql:3630) | Lex-lower owner + edge via `EDGE_NEIGHBOR_OFFSETS`; canonicalized at write. **Relabel-safe** (edge index preserved; negative coords still lex-order). |
| `setting_replay_frames.owner_by_hex` RLE | schema.sql:3792-3802 | Run-length over **canonical `(r ASC, q ASC)`** order, no per-hex coords. **Encoder/decoder are paired by that order** — see C for the alignment requirement. |
| `SettingDatasetHasher` world hash | [setting_dataset_hasher.gd:28-35](engine/subsystems/generation/world/setting_dataset_hasher.gd:28) | Hashes `q,r` column *values* + `effective_latitude` + `r ASC,q ASC` row order → **world_hash changes for a given seed** (3 channels). |
| Post-lock guard | [setting_repository.gd:325-336](engine/subsystems/generation/world/setting_repository.gd:325) | `_reject_if_locked` freezes locked worlds — **no in-place rewrite of saved/locked worlds.** |
| Seed-share | [seed_share_codec.gd:4-24](engine/subsystems/campaign_creation/seed_share_codec.gd:4) | Encodes only `seed + params` → a shared code reproduces a **different** world post-refactor. |

---

## B. SEQUENCED IMPLEMENTATION PLAN

Each step is individually testable. Steps 1–3 are the spine; 4–6 are the must-fix coupled sites; 7–9 are the
materialization (gated on the unmerged branch) + verification + docs.

> **Illustrative pseudocode below is for the plan only — not final code.**

### Step 1 — Add the shared offset-rectangle enumerator (new, no behavior change yet)
Create one canonical helper (e.g. a static on a small `WorldGrid` util, or a static on `SettingParameters`/the
orchestrator — **do not** add an autoload). It returns the key set **already sorted in canonical `(r ASC,
q ASC)` order** so it matches `SettingRepository.list_hexes` and the replay RLE, with each entry carrying its
offset `(col,row)`:
```gdscript
# Returns Array of {key: Vector2i (axial), col: int, row: int}, sorted (r ASC, q ASC).
static func enumerate_offset_rect(width: int, height: int) -> Array:
    var cells := []
    for row in range(height):
        for col in range(width):
            var q := col
            var r := row - (col - (col & 1)) / 2      # inverse even-q == HexMapController.godot_map_to_axial
            cells.append({"key": Vector2i(q, r), "col": col, "row": row})
    cells.sort_custom(func(a, b): return HistorySimulator._canonical_less(a.key, b.key))
    return cells
```
**Test:** unit-test that (a) `axial_to_godot_map(entry.key) == Vector2i(entry.col, entry.row)` for every entry
(round-trip proof the data renders as a rectangle), (b) the set size is `W*H`, (c) the sort matches
`list_hexes` order. *This step alone is fully testable and lands green with zero generator change.*

### Step 2 — Switch the single shape-definition site
Replace the creation loop at [heightmap_generator.gd:59-63](engine/subsystems/generation/world/heightmap_generator.gd:59)
to build keys from `enumerate_offset_rect(dims.x, dims.y)`. **Test:** generate a small world; assert the stored
`setting_hexes` key set, when each is pushed through `axial_to_godot_map`, exactly covers `col∈[0,W)×row∈[0,H)`
with no gaps/dupes (the "is it a rectangle?" assertion).

### Step 3 — Route every full-grid re-walk through the enumerator
Convert the A.iii re-walk loops (heightmap siblings 141/164/189; climate 108/173 + passes; region_painter
135/355/366/502/559; culture_seeder 189/214/526/653/701; `history_simulator._build_ordered_keys`;
`setting_generator._persist_hexes`) to iterate the enumerator's sorted entries (or `grid.keys()` sorted
canonically). **Mandate:** never iterate raw `Dictionary.keys()` for seeded draws — sort first (conventions
§80). **Critical for `_build_ordered_keys`:** it must reproduce **`(r ASC, q ASC)` over the new key set** (an
explicit canonical sort — the old `for r: for q:` loop produced that order *coincidentally*; under shear it no
longer does) so the replay encoder stays aligned with the `list_hexes` decoder. **Test:** the determinism suite
(same-seed-twice == ) stays green; add an assertion that `_build_ordered_keys` order equals `list_hexes` order.

### Step 4 — Decouple latitude from axial `r` (priority #1)
At [climate_generator.gd:114](engine/subsystems/generation/world/climate_generator.gd:114), compute latitude
from the **offset `row`** carried by the enumerator entry, not axial `r`:
`lat = lat_south + lat_span * ((height-1-row)/(height-1))`. Update the `r=0 is north` comment. **Test:** rewrite
`test_setting_stage1.gd:93-102` (currently samples `int(hex.r)==0` vs `==19`) to sample by the **visual row** —
assert the northmost *offset row* averages colder than the southmost. *This is the one test that must move in
lockstep.*

### Step 5 — Fix the ocean/sea bbox test (priority #2)
Replace the axial-bbox edge test at [region_painter.gd:687](engine/subsystems/generation/world/region_painter.gd:687)
with the off-grid-neighbor pattern already used at `region_painter.gd:248-251`. **Test:** on an offset-rectangle
small world, assert a known edge-touching open-water body classifies as ocean and an enclosed one as sea.

### Step 6 — Fix continental falloff center/extent (priority #2)
At [heightmap_generator.gd:130-136](engine/subsystems/generation/world/heightmap_generator.gd:130), compute
center + `max_dist` by min/max over `_hex_center` of the actual enumerated hexes instead of assumed corners.
**Test:** assert the falloff center sits near the cartesian centroid of the generated hex set (not skewed off
one edge).

### Step 6.5 — Decide and apply the rain-shadow direction (priority #3)
Resolve open question E-2; if "visual-west" is chosen, walk the offset column at
[climate_generator.gd:158](engine/subsystems/generation/world/climate_generator.gd:158); otherwise leave as
axial-`q` with a comment. Low risk either way.

### Step 7 — Mirror the shape fix in the regional zoom-in window (gated on the unmerged branch)
When `claude/kind-blackburn-c7a1b9` merges (or as a coordinated edit on it), change
[region_zoom_in.gd:63-71](.claude/worktrees/kind-blackburn-c7a1b9/engine/subsystems/generation/materialization/region_zoom_in.gd)
to select the 6-mile window by offset `col/row` (convert to axial), so the **play map** is a rectangle too. The
1:1 hex copy and the `pq*SUB+i` child subdivision stay as-is.

### Step 8 — Full verification (see section D). Step 9 — Docs (conventions §80 note; brief amendment per E-3).

**Determinism/seed-stability note for B:** because positional noise samples `_hex_center(q,r)`, swamp/
expand_jitter/beastman draws key `'%d,%d'%[q,r]`, **and** culture-homeland seeding consumes a shared stream in
grid-enumeration order whose biome input moves, the offset-rectangle relabel **regenerates a materially
different world for every existing seed** (terrain + seed-capital positions + downstream history all shift). See
C for the blast-radius quantification — it is intended and acceptable, but it is the single biggest consequence.

---

## C. RISK ASSESSMENT

### C.1 — Determinism / seed-stability (the dominant risk; intended but must be owned)
**Regime (verified):** RNG is **per-key-seeded** — `WorldGenRng.derive_seed(seed, subsystem, tick, entity_id)`
([world_gen_rng.gd:28-43](engine/subsystems/generation/world/world_gen_rng.gd:28)), pinned FNV-1a, "no shared
sequential RNG whose draw order couples unrelated subsystems." So the relabel is **not** a global stream
reshuffle. **But the world still changes materially for a fixed seed**, via three channels:
1. **Positional noise** — `_hex_center(q,r)` ([heightmap_generator.gd:94](engine/subsystems/generation/world/heightmap_generator.gd:94))
   binds elevation/temperature/precip to a hex's axial `(q,r)`. The relabel **must** change many hexes' `(q,r)`
   (that is what makes the shape a rectangle), so terrain moves.
2. **Coordinate-keyed per-hex draws** — swamp ([climate:303](engine/subsystems/generation/world/climate_generator.gd:303)),
   expand_jitter ([history:1917](engine/subsystems/generation/world/history_simulator.gd:1917)),
   beastman_presence/race ([culture_seeder:669/833](engine/subsystems/generation/world/culture_seeder.gd:669),
   history:3198/3256) — all key `'%d,%d'%[q,r]`; move for any relabeled hex.
3. **Culture homeland seeding** — `culture_placement`/`culture_selection` are **shared sequential streams**
   consumed in a full-grid `for r: for q:` loop ([culture_seeder:459/541](engine/subsystems/generation/world/culture_seeder.gd:459),
   `:239/301`) whose draw subsequence + biome-derived `match_counts` both shift under the relabel → **seed
   CAPITAL positions move**, and all polity ids/history flow from the moved seeds.

**What is INVARIANT:** every polity-keyed draw (ruler/collapse/severity/shatter/secede/migrate/war) keys on
`'pol_NNNN'`/culture strings → label-stable. So per-pid *outcomes given a fixed seed-set* don't shift, but the
*seed-set itself* does (channel 3). **Net blast radius: a fixed seed → a different, still fully deterministic
and self-consistent world.** Acceptable per Jedidiah's prior ruling ("no determinism hash is pinned" for
end-user seed stability) — but **old screencaps/seeds will not reproduce.**

### C.2 — Replay-frame alignment (handle in Step 3)
RLE encode (`_rle_owners` over `_ordered_keys`) and decode (`ReplayFrameDecoder.decode_owner_map` zipped against
`list_hexes` = `r ASC, q ASC`, [replay_frame_decoder.gd:31-41](engine/subsystems/generation/world/setting_repository.gd))
are paired by canonical order. **Requirement:** `_build_ordered_keys` must emit `(r ASC, q ASC)` over the new
key set (explicit sort). If left as the bare `for r: for q:` loop it would emit row-major-by-offset, which is
**not** `(r ASC, q ASC)` under shear → replay would garble. No stored-data risk (frames regenerate per world);
purely an in-pipeline ordering invariant.

### C.3 — River-edge encoding (safe, with one invariant)
Edge index → physical boundary is fixed by `EDGE_NEIGHBOR_OFFSETS`/`_OFF`, untouched by an axial→axial relabel,
and canonicalized at write ([campaign_repository.gd:1418-1443](engine/autoloads/campaign_repository.gd:1418)).
**Invariant: do not renumber edges or reorder `_OFF`.** The unmerged materializer copies river edges 1:1
([setting_materializer.gd:160-181](.claude/worktrees/kind-blackburn-c7a1b9/engine/subsystems/generation/materialization/setting_materializer.gd)) —
the exact path a renumber would silently corrupt.

### C.4 — Climate cascade (handled by Step 4)
If only `climate:114` is changed but `_hex_center`/enumeration leave terrain sheared, biome would still be baked
on the old geometry. Step 2+4 together (rectangle keys + offset-row latitude) keep climate coherent. Verify
biome bands read as horizontal on the rendered rectangle.

### C.5 — Persisted / locked data
- **Locked worlds** (`is_locked=1`) are frozen behind `_reject_if_locked` — **cannot** be rewritten in place;
  only new (or pre-lock) worlds get the rectangle. A ~277 MB `campaign.db` exists in `%APPDATA%` assuming the
  current shape.
- **world_hash** changes for a given seed (q,r values + effective_latitude + row order). No **pinned golden
  world hash** exists in tests, so nothing goes red — but cross-refactor seed/world-hash reproduction breaks
  (expected).
- Negative axial `r`: safe in storage (`INTEGER`) and runtime (dict-membership). The only `≥0`-assuming site is
  `region_painter:687`, fixed in Step 5.

### C.6 — Things that do NOT garble (verified negatives)
Runtime combat/dungeon/exploration (separate grid + dict bounds); both renderers (data-measured extent);
materializer 1:1 copy + child subdivision; coastline detection (`_coastal_set`); hex distance; all polity-keyed
history draws. None require changes.

---

## D. VERIFICATION STRATEGY

**Baseline:** 461/17 net-zero via `tools/run_tests.ps1` (isolated APPDATA; **run twice, measure run 2** — run 1
shows fresh-DB FK noise). Bar = net-zero **new** failures.

**Headless suite blind spot:** the suite does **not** load scene scripts
([political_map_view.gd](scenes/ui/campaign_creation/political_map_view.gd),
[hex_map_renderer.gd](scenes/maps/hex_map_renderer.gd)) — so **visual correctness MUST be verified via the
godot-ai MCP**, not the test runner. After touching any `scenes/` script, also run `--check-only -s
res://<file>` and grep for `cannot infer|unexpected|expected ` (per the memory gotcha).

**Automated (headless):**
1. New enumerator unit test (Step 1): round-trip + size + canonical-sort.
2. "Is it a rectangle?" assertion (Step 2): every stored hex's `axial_to_godot_map` covers `col×row` exactly.
3. Latitude test rewritten to offset-row (Step 4).
4. Ocean/sea + falloff tests (Steps 5/6).
5. Determinism suite (same-seed-twice ==) stays green; `_build_ordered_keys == list_hexes` order assertion.

**Visual (godot-ai MCP — required):** `project_run` + `editor_screenshot` of **both**:
- the **campaign-creation review map** (`political_map_view`, Biome + Political modes), and
- the **gametime / materialized 6-mile play map** (after Step 7, when the branch is present).

**Representative seeds to eyeball** (from prior sessions, known good for structure):
`345235582`, `38045604`, `40847028` (the structural-diagnostic trio), plus `777207224` and `360202439` (the
phantom-sea-lane repro seeds — good for coastline/ocean classification after Step 5). Generate at least one
**Small** (15×12) and one **Large** (40×30).

**"Matches" means:**
- Review-map outline is a clean **rectangle** (no parallelogram shear), and **equals** the gametime/6-mile
  play-map outline (same convention — accounting for the A.iv column-parity caveat; if they differ, reconcile
  the parity before sign-off).
- **No realm renders split across a seam / no phantom gaps** (the orphan-render symptom from `31d8ad8`).
- **Biome bands read horizontal** on the rectangle (proves latitude decoupled correctly).
- **Rivers** sit on correct hex edges (proves edge encoding intact).

---

## E. OPEN QUESTIONS FOR JEDIDIAH

1. **Migration of existing worlds.** Locked/saved worlds **cannot** be rewritten in place (frozen behind the
   post-lock guard) and a fixed seed now yields a different world. **Recommend: rectangle applies to NEWLY
   generated worlds only**; existing locked campaigns keep their (parallelogram) shape. Confirm — or do you want
   a one-time "regenerate to rectangle" path for unlocked drafts?

2. **Rain-shadow direction (Step 6.5).** Keep "upwind = axial `-q`" (cheap, slightly skewed vs the visual map)
   or make it true visual-west (walk the offset column)? Low stakes either way. **Recommend: keep axial-`q`**
   unless the skew is visible at play scale.

3. **24-mile world-map screen vs 6-mile play map — same offset convention?** The renderers share the even-q
   *formula* but `political_map_view` and the gametime `TileMapLayer` stagger **opposite column parities**
   (A.iv). Do the world-map screen and the 6-mile play map need to be **pixel-parity identical**, or is "both
   are clean rectangles" sufficient? **Recommend: standardize on even-q everywhere** and reconcile the
   review-map parity so the two outlines are literally identical.

4. **even-q vs odd-q.** The whole project uses **even-q** (`axial_to_godot_map`); the offset→axial inverse
   reuses it exactly. **Recommend: stay even-q** (no reason to switch; odd-q would desync from the gametime
   renderer). Flagging only because the controller header comments mention an odd-q alternative.

5. **Negative axial `r`.** The offset→axial inverse yields **negative `r`** for high columns (safe everywhere
   verified). Acceptable, or do you want a uniform row-anchor (`r += floor((W-1)/2)`) to keep coords `≥0` for
   readability when debugging? **Recommend: allow negative `r`** (simpler; nothing depends on `≥0` after the
   `region_painter:687` fix).

6. **Sequencing vs the unmerged materialization branch.** The world-gen fix is **incomplete** without the
   `region_zoom_in` window fix (Step 7) — otherwise the actual 6-mile play surface stays a parallelogram.
   Should the rectangle refactor **land on `claude/kind-blackburn-c7a1b9`** (so both levels move together), or
   on `main` first with Step 7 tracked as a follow-on when that branch merges?

---

*Full per-angle evidence (16-agent trace, all `file:line` quotes and adversarial verifications) is preserved in
the build-log entry for this session.*
