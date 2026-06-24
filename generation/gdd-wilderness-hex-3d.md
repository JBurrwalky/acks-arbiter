# GDD: Wilderness Hex 3D Renderer

**Document type:** Game Design Document (project-designed, modifiable)
**Authority:** PROJECT-DESIGNED — rendering architecture, procedural terrain synthesis, and asset integration. Subordinate to `acks_arbiter_design_brief_v11.md`. **The brief was amended 2026-06-24 (Jedidiah) to permit a flag-gated 2D/3D hex presentation (§5.1 table + §6.1)** — the 2D→3D change is approved.
**Status:** Draft v0.3 — design only, no code. **Reassessed 2026-06-24:** the two systems this was tabled on are now landed — setting→runtime **materialization (M0–M4)** produces a playable 6-mile map, and the **region-scale system** (24-mile view-only world-map tab + "Enter Region" + Strategic/Regional toggle) works — so the "24-mile stays 2D / 3D = 6-mile" recommendation in §4 is **realized**. The remaining gap is *continuous 6-mile height* (today `region_zoom_in.gd` flat-copies the parent's 24-mile `elevation_raw` → 16-hex plateaus). The new [`gdd-continuous-geography.md`](gdd-continuous-geography.md) refactor closes that gap and makes this renderer's `RAW_FIELD` height path the default (§4). Pending: (a) architectural approval of the 2D→3D change; (b) the continuous-geography refactor (its own GDD).
**Depends on ACKS rules:** None new. This is a rendering layer over an existing, already-RAW-grounded terrain data model; the RAW citations live in [`gdd-terrain-system.md`](gdd-terrain-system.md). This GDD introduces no new ACKS interpretation (see §2).
**Depends on project GDDs:** [`gdd-continuous-geography.md`](gdd-continuous-geography.md) (**the world-gen refactor that produces the continuous field this renderer consumes via `RAW_FIELD`** — the proper height source; §4); [`gdd-terrain-system.md`](gdd-terrain-system.md) (the terrain tag taxonomy, elevation thresholds, and the §10 *2D* visual model this GDD supersedes for the 3D path); [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) + [`gdd-region-zoom-in.md`](gdd-region-zoom-in.md) (the 6-mile-from-24-mile derivation — now BUILT as `region_zoom_in.gd`, but flat-copies `elevation_raw`; the continuous-geography refactor replaces its stochastic deviation-budget model with field-sampling); [`gdd-setting-runtime-materialization.md`](gdd-setting-runtime-materialization.md) (M0–M4 — the now-landed handoff that makes the 6-mile map the play surface); [`gdd-dungeon-asset-integration-plan.md`](gdd-dungeon-asset-integration-plan.md) (the asset-kit + Blender→glTF pipeline this mirrors; that plan explicitly defers wilderness scenery to "a future wilderness/hex visual-pass GDD" — **this is that GDD**); [`gdd-character-creation-pipeline.md`](gdd-character-creation-pipeline.md) (the headless Blender bake/export recipe reused for tree assets); [`gdd-region-painting.md`](gdd-region-painting.md) (LOD label overlays that ride on top of the map).
**Modifiable by Claude Code:** Yes within constraints. The mesh algorithm, shaders, asset mappings, and pipeline are engineering decisions. The **2D→3D architectural change (§3)** and the **scale strategy (§4)** are project-direction and need Jedidiah's sign-off before build.
**Last updated:** 2026-06-24

---

## 1. Purpose and Scope

Render the wilderness hex map as a **true 3D heightmap** — a continuous terrain surface displaced by per-hex elevation, textured by biome, scattered with vegetation, with the hex grid drawn on top — replacing (behind a feature flag) the current flat 2D `TileMapLayer` renderer. The goal is a readable, attractive strategic/tactical map that conveys relief, biome, water, and settlement at a glance, while preserving every gameplay behavior the existing renderer drives (movement, fog, picking, context menus, entry points).

This GDD covers: the height-synthesis source decision, terrain mesh construction, texturing/materials, surface features (lava/snow patches, river depressions, water), vegetation scatter, the hex-grid overlay, camera and interaction, the asset pipeline and inventory (with gaps), the feature-flag renderer swap, and data-model/migration impact. It does **not** redesign the hex *data model* or *gameplay logic* — `HexMapController`, `HexMapData`, `HexTerrainData`, pathfinding, fog, and all gameplay consumers are unchanged. It does not cover the dungeon or settlement views (separate renderers), nor the 2D strategic-overview map, which this GDD recommends keeping 2D (§4).

**Design principle (project doctrine):** *Build mechanically, narrate retroactively; engine-first.* The renderer is a pure **view** over deterministic data. It reads terrain; it never authors gameplay state. All randomness (noise displacement, scatter placement) is **seeded** from the campaign's deterministic world seed so the same world renders identically every time, consistent with the setting-generation determinism doctrine.

---

## 2. ACKS Constraints

This is a rendering layer; it inherits — and must **faithfully represent without reinterpreting** — the RAW-grounded data model owned by [`gdd-terrain-system.md`](gdd-terrain-system.md). The constraints below bind the renderer:

- **Three hex scales only:** Campaign (24-mile), Regional (6-mile), Local (1.5-mile), flat-top hexes — per design brief §5.1. The renderer must not invent intermediate scales.
- **Terrain taxonomy is fixed:** elevation (`flat`/`hills`/`mountains`), biome (`clear`/`woods`/`jungle`/`swamp`/`desert`), water (`""`/`ocean`/`lake`), civilization (`civilized`/`borderlands`/`wilderness`), and the eight subtypes — owned by [`gdd-terrain-system.md`](gdd-terrain-system.md) §3.4 (`gdd-terrain-system.md:150-172`). The renderer maps these to visuals; it must not add or rename terrain categories.
- **Elevation tags derive from thresholds:** `hills ≥ 0.55`, `mountains ≥ 0.75` of normalized height ([`gdd-terrain-system.md`](gdd-terrain-system.md) §8, `:453-471`; matches `heightmap_generator.gd:22-23`). When the renderer displaces geometry it must keep the visual band consistent with the tag (a `mountains` hex must read as mountainous).
- **Three territory classifications only:** Civilized, Borderlands, Wilderness. No "Outlands"/"Unsettled" (project-wide rule). Civilization affects overlays (fields, settlement icons), never the terrain taxonomy.
- **Rivers are edges, not tiles:** rivers live on hex edges (`HexRiverEdgeData`), with `navigability` and `crossing`; the renderer carves/water-fills along edges, never as full-hex water (full-hex water is the `ocean`/`lake` tag).
- **Banker's rounding** anywhere the renderer quantizes (round half to even), per project convention (`coding_conventions.md:385-403`). Visual-only continuous math (noise, vertex heights) is exempt — it produces no game numbers.

This GDD adds **no new RAW citation.** If a rendering choice ever appears to require one, that is a signal the choice belongs in `gdd-terrain-system.md`, not here.

---

## 3. Architectural Position — the 2D→3D swap

### 3.1 What changes and what does not

The 2D/3D split is clean because the existing stack already separates logic from rendering. The 2D→3D conversion touches **three files plus a flag**, and preserves the rest:

**Unchanged (engine + data + gameplay):**
- `HexMapController` ([`hex_map_controller.gd`](engine/subsystems/exploration/hex_map_controller.gd)) — all hex math, A* pathfinding, fog, river-crossing, the signal surface.
- `HexMapData` / `HexTerrainData` / `HexRiverEdgeData` / `HexOverlayData` — data only.
- Every gameplay consumer (travel, foraging, weather, lairs, encounters, surveying, trade routes, world-gen).

**Replaced (the renderer, behind a flag):**
- `scenes/maps/hex_map_renderer.gd` (Node2D) → a new `scenes/maps/hex_map_renderer_3d.gd` (Node3D).
- `scenes/maps/hex_map.tscn` (Node2D tree) → `scenes/maps/hex_map_3d.tscn` (Node3D tree), mirroring `dungeon_map_3d.tscn`.
- `scenes/maps/hex_map_landmark_icons.gd` (Node2D) → `Sprite3D`/`Label3D` markers in the 3D renderer.

**The interaction contract that MUST be preserved verbatim** (the state machine depends on it — `wilderness_explore_state.gd:28-44`):
- Signals the 3D renderer must re-emit identically (now **five** — `hex_clicked` was added since v0.2): `hex_clicked(coord: Vector2i)`, `party_token_clicked(party_id: String, coord: Vector2i)`, `hex_context_menu_requested(coord: Vector2i, screen_pos: Vector2)`, `dungeon_entry_requested(entrance: Dictionary, spawn_cell: Vector2i)`, `settlement_entry_requested(entrance: Dictionary, entry_poi_id: String)` (`hex_map_renderer.gd:153-157`).
- Methods: `setup(controller: HexMapController)`, `center_on_hex(coord: Vector2i)`, plus `visible` / `process_mode` honored as today.
- It connects to the controller's `map_loaded`, `visibility_updated`, `party_moved`, `hex_terrain_updated`, `hex_overlay_updated` signals.

> **Note — coords stay axial `Vector2i` at the seam.** The dungeon uses `Vector3i`; the wilderness contract is `Vector2i(q, r)`. Keep the wilderness seam on `Vector2i` so no consumer changes. Internally the 3D renderer maps `(q,r) ↔ world Vector3` (XZ = hex layout, Y = height).

### 3.2 Reuse map from the existing 3D dungeon renderer

The dungeon already renders in 3D; ~70–80% of its camera/picking/asset/token machinery lifts directly. Concrete seams:

| Capability | Reuse source | Adapt |
|---|---|---|
| Orthographic isometric camera, pan/zoom/recenter | `dungeon_map_renderer_3d.gd:25-29` (PAN_SPEED 8, ZOOM_MIN 4, ZOOM_MAX 30, ZOOM_STEP 1), `:226-227` (pitch −35.264°, yaw 0), `dungeon_map_3d.tscn` (`projection=1`, `size=12`, `far=200`), basis vectors `:44-48` | Widen zoom range for a large map (§11); compute zoom-to-fit |
| Mouse pick: screen→cell via ray + plane | `tactical_grid_3d.gd:987-997` `screen_to_cell_voxel()`, `:56-62` `screen_to_world_on_plane()` (`project_ray_origin/normal`, plane-Y intersection) | Intersect the **base plane** (Y=0), then convert world-XZ→axial analytically — picking is elevation-independent (§11.2) |
| Feature-flag renderer branch | `dungeon_map_renderer_3d.gd:114` `acks/rendering/dungeon_asset_mode`, `:685-686` reader, `:691-699` registry lazy-load | New key `acks/rendering/wilderness_hex_mode` (§13) |
| MultiMesh instancing | `tactical_grid_3d.gd:312-353` (floor MultiMesh), `:362-404` (walls) | Mirror for chunked terrain tiles + scatter (§9) |
| Asset registry + glTF instantiation + cel shader | `dungeon_asset_registry.gd` (export dicts, `kit_scale`, `use_cel_environment`, lookup methods), `dungeon_asset_builder.gd:220-239` (`_instance`/`_load_scene` cache), `:293-305` (`_apply_environment_materials`), cel shader `res://engine/shaders/cel_environment.gdshader` | New `WildernessAssetRegistry` + `res://data/wilderness_assets.tres` (§12) |
| Tokens (Node3D + procedural anim) | `combatant_token_3d.gd` / `character_token_3d.gd` `setup()/update_position()/set_facing()`; instantiation `dungeon_map_renderer_3d.gd:752-769` | Party tokens snap Y to terrain height (sample the §5 height fn). Heraldry: a SubViewport `ViewportTexture` **does** render on a 3D `Sprite3D`/quad material in 4.6, **but** the SubViewport must be in-tree and have rendered ≥1 frame before the texture is assigned in code (set `render_target_update_mode`). Per-party only — never per-hex/per-scatter (viewport textures aren't batchable). |

**The shared world-XZ→hex math is the high-leverage piece** — it serves **three** systems: picking (§11.2), the hex-grid overlay shader (§10), and scatter placement (§9). Implement it once as a static helper (`WildernessHexMath.world_to_axial(world_xz) -> Vector2i` and inverse), reusing the existing `HexMapController.axial_to_godot_map` parity.

> **Correction from review — picking is NOT elevation-independent on a displaced surface.** The dungeon's `screen_to_world_on_plane` works because dungeon floors *are* flat at Y=0. Under the pitched (−35°) orthographic camera the picking ray is **not vertical**, so a peak displaced to height `H` appears shifted ~`H/tan(35°) ≈ 1.43·H` in world XZ ("downhill toward the camera"); flat-plane picking would then select a hex 2–3 rows *behind* the summit the player clicked, and cliffs occlude hexes a flat pick would still return. **Therefore the default pick is a real surface raycast against the per-chunk `ConcavePolygonShape3D` (which §6.2 already builds), with flat-plane intersection only as the off-map fallback.** See §11.2.

### 3.3 What is genuinely new (not in the dungeon)
The dungeon is voxels (discrete cubes); the wilderness is a continuous heightmap. New work: the terrain mesh from a height field (§5–6), multi-texture splat with edge dithering (§7), surface features (§8), the draped/shader hex grid (§10), and the height-synthesis source (§4). The dungeon's flat-floor MultiMesh does not carry over for terrain (only for scatter).

---

## 4. Scale strategy — largely resolved (2026-06-24)

The v0.2 "scale-consistency problem" assumed the materialization + region-scale systems were unbuilt. **They have since landed**, and they implement exactly the split this section recommended. What remains is a *data-quality* gap (height is coarse, not absent), which the [`gdd-continuous-geography.md`](gdd-continuous-geography.md) refactor closes at the source.

### 4.1 The actual data situation (re-verified 2026-06-24)

- The world generator still produces **one 24-mile field**: `heightmap_generator.gd:17` `HEX_MILES := 24.0`, one noise sample per 24-mile hex center; continuous `elevation_raw` (0–1) persisted to `setting_hexes.elevation_raw` (`schema.sql:3586`).
- **Materialization (M0–M4) is LANDED** ([`gdd-setting-runtime-materialization.md`](gdd-setting-runtime-materialization.md); MCP-verified playable). It produces a `regional_6mi` play map (~40×32 hexes) by procedural zoom-in: `region_zoom_in.gd` expands each 24-mile parent into 16 six-mile children.
- **6-mile children now DO carry `elevation_raw`** (`region_zoom_in.gd:135` writes the column) — **but** `_children_for_parent` flat-copies the *parent's* 24-mile value to all 16 children (`:212, :307`; edge children borrow a neighbor's parent value). So the "continuous height" is **stair-stepped at 24-mile resolution**: a 3D renderer reading it gets 16-hex-wide flat plateaus with cliffs at parent boundaries — categorical inheritance + coherent-noise variation handles the *tags*, not a true finer surface. This is the [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) §6.6 "inherit flat, let the renderer synthesize later" MVP.
- The **region-scale system is LANDED**: a 24-mile **view-only** "World Map" Notebook tab with Biome/Elevation/Territory/Culture layer toggles (`scenes/ui/notebook/tab_pages/world_map_tab_page.gd`), an "Enter Region" button + Strategic/Regional view toggle (`session_status_bar.gd`), migration-119 cross-scale linkage. Party plays on the 6-mile map; 24-mile is strategic-only.

**Net:** the recommended split (24-mile 2D, 3D = 6-mile) is **already the shipped architecture.** The only thing missing for a *smooth* 3D surface is sub-24-mile continuous height — which is precisely what the continuous-geography refactor provides (§4.4).

### 4.2 Three options

1. **Read a real continuous field (NOW THE CHOSEN PATH).** In v0.2 this meant "block on the unbuilt subdivision pipeline" and was rejected. As of 2026-06-24 materialization + region-zoom are built, and the project direction is to make the *source* continuous via [`gdd-continuous-geography.md`](gdd-continuous-geography.md): generate geography as a continuous (non-hex) field, then sample it at 6-mile (and any) resolution. The renderer then reads a genuine sub-hex surface (`RAW_FIELD`), not a flat-copied plateau. This is option #1's spirit delivered at the source rather than blocked behind a stochastic subdivision.
2. **Renderer-owned procedural height synthesis (RECOMMENDED).** The renderer synthesizes a continuous, deterministic height field at load time from whatever it has:
   - **If** the map's parent 24-mile `setting_hexes.elevation_raw` is reachable (via migration-119 linkage), use it as a **low-frequency guide** — sample/interpolate the parent value across the child footprint so the 6-mile terrain trends with the continent.
   - **Else** (hand-authored fixtures, no parent height), derive a base height per hex from the **categorical tag** (`flat`/`hills`/`mountains` → base bands) and let seeded noise (§5) supply the relief.
   - Either way, layer biome-keyed noise distortion (§5.3) on top. The renderer is a **pure view**: it persists nothing, depends on no unbuilt system, and renders the maps that exist now.
3. **Two-tier presentation split (RECOMMENDED, complementary to #2).** Keep the **24-mile campaign map 2D** (the existing flat renderer — a strategic abstraction, which is what a 24-mile "what kingdom owns what" view wants anyway) and make **3D the 6-mile (and finer) scale**, where relief and terrain texture actually matter to the player on the ground. This **sidesteps cross-scale texture continuity entirely** — you never have to make a 24-mile hex's texture tile seamlessly into its 16 constituent 6-mile hexes, because the two scales use different renderers with different jobs.

### 4.3 Why the split (4.2 #3) dissolves the "consistency" worry

The original concern — *consistent texturing between 24-mile and 6-mile* — only bites if **both** scales are 3D heightmaps that must look like continuous zoom levels of the same surface. By rendering the 24-mile map as a 2D strategic overlay (biome color + relief hint + political tint, per `gdd-terrain-system.md:506-526`) and only the 6-mile map as 3D terrain, the scales are deliberately *different views*, not *zoom levels of one mesh*. Within the 3D 6-mile map, continuity is automatic because it's one mesh built from one (synthesized) field (§5–6). **Recommendation:** adopt #2 + #3 for V1. Reserve full multi-scale 3D (consuming subdivision-derived `elevation_raw`) for a later version once [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) is built — at which point option #2's "use parent guide" hook becomes "use the real derived field," with no renderer rewrite.

### 4.4 Height source — `RAW_FIELD` is the target, synthesis is the interim
The height function takes a `height_source`:
- **`RAW_FIELD` (target default):** call [`gdd-continuous-geography.md`](gdd-continuous-geography.md)'s `field_sampler.sample(x, y)` for true sub-hex height at the rendered point. Available once that refactor lands. This is the proper end state — the renderer stops *synthesizing* and renders the real simulated surface.
- **`PARENT_GUIDE` (interim):** interpolate today's 24-mile `elevation_raw` across the child footprint (smooths the flat-copied plateaus into something renderable before the refactor lands).
- **`TAG_ONLY` (fallback):** categorical bands + seeded noise, for hand-authored fixtures with no field.

The renderer ships against `PARENT_GUIDE`/`TAG_ONLY` if it's built before the continuous-geography refactor; flipping to `RAW_FIELD` is a one-line change. **Recommended sequencing: land the continuous-geography refactor first** (it benefits world-gen, the 2D maps, and materialization regardless of the 3D renderer), then build this renderer straight onto `RAW_FIELD`.

---

## 5. Height synthesis pipeline

```
HEIGHT SYNTHESIS (per map load, deterministic from world seed + map id)
1. RESOLVE SOURCE     → RAW_FIELD | PARENT_GUIDE | TAG_ONLY  (§4.4)
2. BASE HEIGHT/HEX    → continuous h0(q,r) in [0,1] from the source
3. CORNER HEIGHTS     → corner = mean of the ≤3 hexes sharing it (C0-continuous seam)
4. TRIANGULATE        → center + 6 corners per hex; optional 1–2 subdivisions
5. BIOME DISTORTION   → add world-space seeded noise, amplitude/frequency by terrain class
6. RIVER CARVE        → lower vertices along river edges with falloff (§8.3)
7. SEA/LAKE CLAMP     → flatten water hexes to their water-level Y (§8.4)
8. VERTICAL SCALE     → multiply by HEIGHT_GAIN (world units) for the final mesh Y
```

### 5.1 Base height per hex (step 2) — source priority
Runtime priority is **PARENT_GUIDE → TAG_ONLY**, with **RAW_FIELD** reserved for when subdivision lands (§4.4):
- **PARENT_GUIDE (V1 default when reachable):** interpolate the parent 24-mile `elevation_raw` across the child footprint (bilinear-ish over axial neighbors) so 6-mile terrain trends with the continent.
- **TAG_ONLY (V1 fallback — hand-authored maps with no parent height):** map the categorical tag to a base band midpoint, using the generator's own thresholds so a later switch to a real field is visually continuous: `flat → 0.20`, `hills → 0.65` (midpoint of 0.55–0.75), `mountains → 0.875` (midpoint of 0.75–1.0). Water hexes → below `sea_level`.
- **RAW_FIELD (future):** `h0 = elevation_raw` read directly, once [`gdd-hex-subdivision.md`](gdd-hex-subdivision.md) writes per-child values.

### 5.2 Smooth triangulation (steps 3–4)
Per the Godot-technique survey: place a vertex at each **hex center** (height = hex base) and each **hex corner** (height = mean of the up-to-3 hexes sharing it), then fan-triangulate each hex into 6 triangles, **wound CCW viewed from +Y** (Godot front-faces CCW; wrong winding back-faces the whole terrain under `cull_back`). Corner-averaging makes vertex **positions** continuous across hex boundaries **for free** and reads as rolling terrain while staying faithful to the per-hex field. Optionally subdivide each triangle 1–2 levels for smoother hills (watch the vertex budget, §6.3). **Do not** render literal flat-top hex prisms — that gives a stepped, discontinuous look.

> **Position continuity ≠ shading continuity.** Corner-averaging fixes positions, but per-triangle-fan normals will *not* match across a shared edge — and with per-chunk meshes (§6.1) a boundary vertex lives in two chunks, each computing its normal from only its own triangles, giving a visible lighting crease down every chunk seam. **Fix: compute normals analytically from the height function** (we have it) rather than from mesh topology, **or** generate them over a 1-hex apron beyond each chunk and discard the apron triangles. `SurfaceTool.generate_normals()` only averages within one surface, so it does **not** solve the cross-chunk case — flag for the build phase.

### 5.3 Biome distortion (step 5) — the user's "gentle waves / sharp waves"
Add `FastNoiseLite` displacement, sampled in **world space** (so chunk boundaries don't seam), with amplitude/frequency looked up **per vertex at mesh-build time** (deterministic — not in the fragment shader) from the owning hex's terrain class:

| Terrain class | Amplitude | Frequency | Fractal | Read |
|---|---|---|---|---|
| flat / water-adjacent | very low | low | FBM | near-flat, gentle undulation |
| hills | low–medium | medium | FBM | gentle rolling waves |
| mountains | high | high | **Ridged** (`FRACTAL_RIDGED`) | sharp crests/ridgelines |
| `mountains_volcanic` | high | high | Ridged | sharp + lava patches (§8.1) |
| `mountains_glacial` | high | medium | Ridged | sharp + snow cap (§8.2) |
| `desert_badlands` | medium | high | Ridged | eroded, broken even when "flat"-tagged |

Amplitude/frequency are **blended across the hex's corner region** (lerp toward neighbors by barycentric weight) so a mountain hex bordering plains doesn't produce a cliff seam unless intended.

> **Anchor handling — resolved from review.** Do *not* pin corners/centers to zero noise: that leaves every hex-boundary edge a noise-free "rail," which on high-amplitude mountains re-introduces a faint hex-shaped lattice of un-displaced ridgelines (the very grid §10 is supposed to be the only source of). Instead, keep corner **position** continuous for seams (the §5.2 mean, computed identically from both sides), but let noise **amplitude** taper only to ~50–70% at corners, not 0. Combined with the apron-normal approach (§5.2), this keeps seams smooth without a visible lattice.

Seed the noise deterministically (§5.4) so terrain is reproducible. `HEIGHT_GAIN` (step 8) is a single tunable controlling overall vertical exaggeration — note its interaction with picking parallax (§11.2): higher gain → more visible relief but larger flat-plane-pick error, which is exactly why §11.2 raycasts the surface instead.

### 5.4 Determinism and seeding
Height and scatter must regenerate identically every load (project doctrine; guarantees save/load terrain consistency without persisting the mesh). Seed from a **stable per-campaign seed × map id × hex coord**, sourced from the campaign record (the same seed the setting generator used — `world_gen_rng.gd` derives sub-seeds this way). **Use an explicit, documented integer-mixing function — not GDScript's built-in `hash()`** — because `hash()` semantics can change across engine versions and would re-roll every forest. Always draw from a seeded `RandomNumberGenerator` instance, never the global `randf()`. The exact campaign-seed accessor is a build-time wiring detail (flagged in §15).

---

## 6. Terrain mesh construction

**Coordinate anchor (binding):** **1 world unit = 1 hex footprint.** Axial `(q,r)` → world XZ follows the existing `HexMapController.axial_to_godot_map` layout (flat-top), Y = synthesized height × `HEIGHT_GAIN`. This 1-unit-per-hex choice is load-bearing for three reasons: it keeps a 60×45 map's camera `size` far under the 16384 ortho clamp (§11.2); it keeps float precision clean for sub-hex scatter jitter; and it fixes the scale every glTF asset is fit to via `kit_scale` (§12.3). The whole map sits near the origin (0…~60 units), so float32 has ~4 significant figures of sub-hex headroom — precision is a non-issue.

### 6.1 ArrayMesh, chunked
Build the surface as `ArrayMesh` surfaces (`add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, …)`) with packed `ARRAY_VERTEX/NORMAL/TANGENT/TEX_UV/COLOR/INDEX`. Compute **normals analytically from the height function** (or via the apron method, §5.2) — not from per-chunk topology — to avoid lighting creases at chunk seams. **Chunk** the map into fixed regions, each its own `MeshInstance3D` + collision body + scatter MultiMeshes; chunks are the unit of frustum/occlusion culling and of partial rebuild. A prototype may use `SurfaceTool` (free `generate_normals()`/`generate_tangents()`), but note it cannot reconcile cross-chunk normals; production uses hand-built packed arrays (faster regen, gives per-vertex `ARRAY_COLOR` used as the splat control in §7).

**Chunk size:** ~8×8 hexes is the default (≈1–2k triangles/chunk). For maps under ~2k hexes total, 16×16 cuts mesh count and load time; above ~4k hexes drop to 4×4 for finer culling. The trade is culling granularity vs. rebuild cost vs. draw calls (§6.3, §16).

**Live edits:** on the controller's `hex_terrain_updated(coord)` signal, synchronously rebuild the affected chunk's mesh **and** its `ConcavePolygonShape3D` collision body (and re-run analytic normals over its apron) before returning, so picking/pathfinding never see a stale surface.

`ARRAY_COLOR` per vertex doubles as the **biome splat weight** (§7) — write it during this build pass, no extra texture.

### 6.2 Collision and picking
Each chunk gets a `StaticBody3D` + `ConcavePolygonShape3D` built from the **same triangle soup** as the render mesh — pixel-exact for token placement and picking. (Reject `HeightMapShape3D`: it's a square grid and won't match the noisy hex-anchored surface, so tokens would float/sink near corners.) **Hex picking raycasts this surface** (`PhysicsDirectSpaceState3D.intersect_ray`), reads the hit point's world-XZ, and converts to axial — this lands on the *visible* surface and respects occlusion, unlike flat-plane picking (§3.2, §11.2). The flat-plane intersection (`screen_to_world_on_plane`) is the off-map fallback only. The height **field** is precomputed for the whole map at load (scatter in §9 samples it everywhere); collision **bodies** may still be built lazily for chunks near the party on very large maps, but at sub-2k hexes build all up front.

### 6.3 Vertex budget
Center + corner + 1–2 subdivisions ≈ tens of triangles per hex; a few thousand hexes ≈ low-hundred-thousand triangles — trivial for desktop. Raise noise *frequency* rather than vertex count to chase detail. Let Godot's automatic mesh LOD reduce far-chunk triangles.

---

## 7. Texturing and materials

### 7.1 Splat shader
A custom `shader_type spatial` shader does texture splatting. The control weights are written into the mesh during the §6.1 build pass: each hex carries **one** terrain class (its biome/subtype tag); its center + corner vertices get that class's weight in `ARRAY_COLOR`, and corner vertices **interpolate weights from the 1–3 adjacent hexes**, so the GPU blends across the triangle ring at hex boundaries with no splatmap image to author. The fragment shader then adds the §7.2 noise perturbation per pixel.

- **≤4 blended classes (prototype):** RGBA `ARRAY_COLOR` = (weight0…weight3); 4 PBR sets, roughness+AO+(metallic) packed into one **ORM** sampler each → albedo+normal+ORM = 12 samplers. This is comfortable on Forward+ (desktop GPUs report far more than the 16-sampler *minimum-spec* floor; that floor is a red herring at this count — don't let it scare the prototype off the simple RGBA path).
- **Full biome set (>4) — production target:** `sampler2DArray` (TextureArray) — one albedo array + one normal array + one ORM array = **3 samplers regardless of layer count** (the palette exceeds 4). Per-vertex layout: `ARRAY_COLOR.rgba` = the four nearest-class weights, plus a layer index packed in a spare channel (e.g. `ARRAY_TANGENT.w` or a custom attribute). All AmbientCG sets must share resolution (1K — they do).
- **Normal-map blending caveat:** when blending normal maps by weight, **renormalize** (or reorient) the blended normal in-shader, or transition bands read flat. Albedo blends linearly; normals do not.

### 7.2 Edge dithering (the user's "dithering at the edges")
Two layers, both in-shader:
1. **Noise-perturbed blend (default, ships in V1 — not polish):** in the fragment shader perturb the interpolated weight by a world-space noise sample — `weight += (noise(world_xz * k) - 0.5) * blend_jitter` — turning a straight hex edge into an organic, irregular transition. This is *required*: the §7.1 vertex-density blend alone is only ~1–2 verts wide and reads as a hard geometric seam without it.
2. **Ordered (Bayer) dither (optional, stylized):** threshold the blend against a 4×4 Bayer matrix for a visible dithered checker. Dither by **world** position (not `SCREEN_UV`) so it doesn't shimmer when the camera pans — important under the orthographic camera.

### 7.3 Biome → texture mapping (from the asset library)
Source: `C:\Users\jttau\OneDrive\Pictures\Terrain\hexmap textures\` (import → §12). Each set is an AmbientCG PBR pack (Color / NormalGL / Roughness / Displacement / usually AO).

| Terrain (biome[/subtype/elev]) | Texture folder | Notes |
|---|---|---|
| clear (flat) | `clear\Grass001` | |
| clear_grassland | `grassland\Grass004` | |
| clear_savanna | `savanna\Ground003` | no AO map (synthesize flat AO) |
| clear_tundra | `tundra\Snow015` | |
| woods / forest_dense | `forest_floor\Ground037` | one floor serves both densities |
| jungle | `jungle_floor\Grass003` | |
| desert | `desert\Ground087` | |
| desert_badlands | `badlands\Rock029` | |
| mountains | `mountain\Rock030` | |
| mountains_volcanic | `mountain_volcanic\Rock035` + `lava\Lava004` (Emission map) | lava as shader layer (§8.1) |
| mountains_glacial | `mountain\Rock030` + `snow\Snow008A` | snow as shader layer (§8.2) |
| **swamp** | — **MISSING** | needs a mud/bog set (§12.4) |
| **water (ocean/lake/river)** | — **MISSING** | water is a shader, not a tiled texture (§8.4) |
| forest_taiga | reuse `forest_floor` (or pine-duff if added) | optional |
| hills (any biome) | reuse the biome's flat texture | relief from §5 distortion; optionally blend toward `mountain` rock above a slope threshold |

### 7.4 Climate-modulated tinting (optional polish)
`setting_hexes` carries `temperature`, `precipitation`, `effective_latitude`, `koppen` (`climate_generator.gd`). When available, modulate albedo: low temperature → snow/desaturation and a lower mountain snow line (via lapse rate, already in `climate_generator.gd`); low precipitation → drier/sparser; seasonal autumn tint at moderate temperature. Pure polish; degrade gracefully when these fields are absent (hand-authored maps).

### 7.5 PBR pitfalls
AmbientCG normal maps are OpenGL (+Y) — what Godot expects (use NormalGL, not NormalDX). Do **not** vertex-displace from the Displacement map (height already comes from §5); use it only as optional parallax up close — likely skip under the ortho camera.

---

## 8. Surface features

### 8.1 Lava patches (volcanic) — shader layer, not Decal
Render lava as an **extra emissive layer in the splat shader**, keyed to the `mountains_volcanic` weight × a high-elevation/slope mask, scrolling a flow texture and writing `EMISSION` from `lava\Lava004_Emission`. (`Decal` nodes can't take a custom/animated material — `godot-proposals#4938` — so a stock Decal can't do flowing lava.) This batches into the terrain draw and animates freely.

### 8.2 Snow caps (glacial) — shader layer
A 5th splat layer keyed to `mountains_glacial` weight + elevation above the snow line (computed from `effective_latitude` + lapse-rate when climate data is present, else a fixed high-Y threshold). Uses `snow\Snow008A`. Also applies to high peaks generally in cold climates (not only the glacial subtype) if climate data supports it.

### 8.3 River depressions — bake-time mesh deformation
Read river edges (`HexRiverEdgeData`: `hex_q/hex_r/edge/flow_clockwise/navigability/crossing`). For each river edge, lower the vertices along that hex boundary by a small delta with a falloff to either side, widening by `navigability` (creek < river < large craft). Do this in the §5 build pass — it's "real" geometry, collides correctly, and reads honestly under the ortho camera (a faked normal-map groove looks flat). The carved channel becomes the basin the water mesh (§8.4) sits in. Honor `crossing` (bridge/ford/ferry) with a small placed asset/decal at the edge midpoint (mirrors the 2D renderer's crossing markers).

### 8.4 Water — shared spatial water shader on a separate mesh
Build a water mesh (once per load, static for V1) from the `ocean`/`lake` hex set and the river channels, at each body's water-level Y. One shared `shader_type spatial` water material instance (draw-call economy) with: depth-fade (sample `DEPTH_TEXTURE`), shore foam at shallow edges (watch the classic inverted-mask bug that puts foam in *deep* water), Fresnel, and Gerstner vertex waves for ocean (rivers/lakes near-flat). Drive river flow direction from `flow_clockwise`. This is the asset gap from §7.3 — water needs a shader (V1 can ship a simple depth-faded flat material and add waves/foam later).

> **Depth/z-fighting risk (from review).** Depth-fade requires the water render in the **transparent queue**, which by default does **not** write depth — so water-behind-water and water-vs-scatter sorting can pop, and Godot's open `next_pass`/transparent depth bug (#95419) is worst at grazing angles, exactly where the −35° camera views the surface. Mitigations: keep the carved channel floor (§8.3) a few units *below* the faded water edge so the depth-fade fully hides the terrain intersection; use `depth_draw_opaque` where it doesn't break the fade; treat **ocean/lake as the well-behaved cases** and thin **river ribbons as the hard case** (the V1 flat-material fallback de-risks rivers). Per-body params (flow) ride on vertex data so the single shared material still batches.

---

## 9. Vegetation scatter

### 9.1 MultiMesh, chunked, seeded
Scatter trees/rocks/bushes via `MultiMeshInstance3D` — one MultiMesh per (variant × chunk). **Critical:** a MultiMesh has **no per-instance culling** (the whole MultiMesh is one cull unit — `godot-proposals#10669`), so it *must* be chunked or off-screen trees still cost draw time — doubly important under an orthographic camera that shows the whole far field at full detail. **Set `custom_aabb` on every scatter MultiMeshInstance3D** — the auto-computed AABB only covers the mesh at origin, so without it culling and visibility-range math are wrong from the start (the single most common scatter bug). Placement is **deterministic** per §5.4 (explicit mixing function + seeded `RandomNumberGenerator`, never built-in `hash()`/global `randf()`): pick a variant by biome, jitter position within the hex, snap Y to the terrain (sample the §5 height function — cheaper than raycasting), randomize yaw/scale. Same world → identical forests.

### 9.2 Biome → scatter mapping (from the asset library)
Source: `C:\Users\jttau\OneDrive\Pictures\Terrain\Quaternius Wilderness\Blends\` (import → §12).

| Biome / context | Objects |
|---|---|
| woods (temperate) | `CommonTree_1-5`, `BirchTree_1-5` (+Autumn/Dead by climate/season) |
| forest_taiga (boreal) | `PineTree_1-5` (+Snow) |
| jungle | `PalmTree_1-4`, `Plant_1-5` (canopy tree is a gap — §12.4) |
| swamp | `Willow_1-5`, `Lilypad` (reeds are a gap — §12.4) |
| desert | `Cactus_1-5`, `CactusFlower(s)_*`, `Rock_*` |
| clear / grassland | `Grass*`, `Flowers`, sparse `Bush_*`/`CommonTree` |
| savanna | sparse `CommonTree` + grass (acacia substitute) |
| tundra / glacial | `Rock_Snow_*`, `Bush_Snow_*`, `PineTree_Snow_*`, `*_Dead_Snow` |
| mountains | `Rock_1-7`, `Rock_Moss_*` (+Snow), sparse pine |
| civilized farmland | `Corn_1/2`, `Wheat` |
| river/lake margins | `Lilypad`, `Willow` |

Density scales with `precipitation` when present; sparse in desert/tundra, dense in woods/jungle.

### 9.3 LOD / imposters
Use `GeometryInstance3D.visibility_range_*` HLOD: near MultiMesh = full glTF mesh, far MultiMesh = billboarded quad imposter, beyond = off. Pitfalls (all current in 4.6): MultiMesh visibility is measured from the node **origin** while distance-*fade* uses the **AABB** (`godot#114500` is a 4.6 regression, `#79471`) — keep chunks small so origin≈AABB and prefer hard visibility swaps over fade. Three things to budget that the camera makes worse:
- **Shadows:** a MultiMesh casts shadows as one unit, so off-screen up-sun trees still cast into view and the shadow pass renders *every* instance in every visible chunk. Use a shadow LOD — `SHADOW_CASTING_SETTING_OFF` (or drop scatter shadows beyond N units) on far-LOD MultiMeshes.
- **Full zoom-out is a distinct render path, not just a density knob:** at max zoom-out thousands of transparent imposter quads overlap → severe overdraw (the ortho worst case). Far chunks should switch to a **merged low-poly/ground-tint HLOD**, not per-tree billboards.
- Cap far-LOD instance density regardless.

---

## 10. Hex-grid overlay (the "hexgrid on top")

Draw the grid **inside the splat shader's own fragment** (single pass): pass interpolated `world_position` to the fragment, convert world-XZ→axial, compute a line mask where the fragment is within `line_width` of a hex boundary using `fwidth()`/`smoothstep` (resolution-independent — stays ~1px crisp at any zoom), and `ALBEDO = mix(terrain_color, grid_color, grid_mask)`, gated by a `uniform bool show_grid`. This follows terrain height exactly (computed on the surface), adds zero geometry, and reuses the **same world-XZ→hex math** as picking (§11.2) and scatter (§9.1).

> **Why single-pass, not `next_pass` (corrected from review).** `next_pass` re-rasterizes the whole terrain a second time, renders in the transparent queue, hits Godot's open `next_pass` depth bug (#95419) at the grazing angles this camera uses, and **can't read the first pass's result** (`COLOR` in a next-pass is vertex color, not the splat output — `godot-proposals#7870`). Folding the grid into the splat fragment with a uniform toggle avoids all of that and keeps the independent on/off. Keep `next_pass` (or a draped line `ArrayMesh` slightly above the surface) only as a fallback.

Pitfall: fade the grid on steep slopes where the world-XZ→axial gradient explodes, keying the fade on **world-space slope (`NORMAL.y`)**, not the screen derivative, so it doesn't shimmer when the snapped-yaw camera rotates. Selection/hover highlight of a single hex can be a `Decal` or a brightened grid cell.

Fog of war rides on the same surface: tint/darken `HIDDEN`/`EXPLORED` hexes via a per-hex fog value (reuse the dungeon's fog-overlay pattern, `tactical_grid_3d` fog), driven by the controller's `visibility_updated`.

---

## 11. Camera and interaction

### 11.1 Camera (isometric default, not locked — per direction)
`Camera3D`, `PROJECTION_ORTHOGONAL`, fixed pitch (~−35.264° true-iso, or −30°/−45° to taste), default yaw 45°. Pan in local XZ; zoom by lerping `size`. **Rotation is allowed but snapped** to hex-friendly facings (60°/90° yaw steps) rather than free orbit, so hex-coordinate readability and the grid/labels stay sane; pitch stays fixed. (Free orbit can be revisited; the user is open to it. Snapped yaw is the safe default.)

### 11.2 The zoom-out fix (essential, both renderers)
Two distinct issues:
- **2D renderer bug — LANDED 2026-06-16 (independent of 3D):** the old `ZOOM_MIN := 1.0` floor forbade zooming out below 100%, so large generated maps couldn't be viewed whole. Fixed in `hex_map_renderer.gd`: replaced the fixed floor with a per-map **fit-to-screen** minimum (`_recompute_zoom_min()` computes `min(vp/contentₓ, vp/content_y)` from the cached padded map extent, clamped to `(ZOOM_MIN_FLOOR 0.15, ZOOM_DEFAULT 1.0]`), recomputed on each zoom so it survives window resizes; small maps keep the 100% floor, large maps can zoom out to fit. `_apply_zoom` now clamps to `_zoom_min`.
- **3D camera caveat:** `Camera3D` orthographic `size` is silently clamped to **≤ 16384** (`godot-proposals#5736`). `size` is the view *diameter* along the kept axis. Compute zoom-to-fit from the map AABB and **choose world scale so the full-map `size` lands well under 16384** — recommend **1 world unit = 1 hex** (a 60×45 map → ~60 units, far under the cap). Do **not** model the map in feet (a 6-mile map in feet ≈ 31,000 units > 16384 → that *is* the "can't zoom out far enough" symptom). Set `far` generously (the camera is pitched over the whole map).

### 11.3 Picking and input contract
Left-click: ray → **surface raycast against the chunk collision mesh** (§6.2) → hit-point world-XZ→axial (flat-plane intersection only if the ray misses the terrain, i.e. off-map) → bounds-check against `HexMapData` (return "no hex" if out of range) → if a party token's hex, emit `party_token_clicked`; else emit nothing (movement is via right-click menu, as today). Right-click: same conversion → `hex_context_menu_requested(coord, screen_pos)` (pass the real screen pixel for menu placement). The surface raycast (not flat-plane) is what makes the picked hex match the hex *under the cursor* on displaced terrain (§3.2 parallax). Token proximity hit-test mirrors the dungeon's `unproject_position` distance check. Tooltips/HUD stay on a `CanvasLayer` (portable from the 2D renderer). Pan/zoom/recenter input handlers lift from `dungeon_map_renderer_3d.gd:253-303`.

---

## 12. Asset pipeline and inventory

### 12.1 Source library (to import)
`C:\Users\jttau\OneDrive\Pictures\Terrain\` (outside the repo):
- `hexmap textures\<biome>\` — 12 AmbientCG PBR sets (Color/NormalGL/NormalDX/Roughness/Displacement/AO JPG + .png/.blend/.mtlx/.usdc/.tres). The ~1 KB `.tres` files may be pre-authored Godot materials/import sidecars — **inspect on import** (could save material-building).
- `Quaternius Wilderness\Blends\` — ~150 `.blend` scenery objects (trees/bushes/cactus/rocks/ground cover/stumps/logs) with Autumn/Dead/Snow variants; shared `Bark_Texture.jpg` + `Leaf_Texture.png`.
- `Quaternius Dungeon\Blends\` — already imported for dungeons (`assets/dungeon_kit/`); a few props reusable.

### 12.2 Import path (mirror the dungeon kit)
Reuse the proven headless converter pattern from `assets/dungeon_kit/_convert.py` (Blender headless: open `.blend` → apply rotation/scale → export self-contained `.glb` Z-up→Y-up → categorized folder) and the [`acks-blender-pipeline`](.claude/skills/acks-blender-pipeline) skill (decimate/UV/export scripts). Trees land at **`assets/wilderness_kit/<subcategory>/<snake_case>.glb`** (`tree/`, `bush/`, `rock/`, `groundcover/`, `cactus/`, …). Textures import as Godot `StandardMaterial3D`/shader inputs under `assets/wilderness_textures/<biome>/`. Catalog every imported asset (mirror `assets/characters/catalog.json`).

### 12.3 Registry
New `WildernessAssetRegistry` (mirror `dungeon_asset_registry.gd`): exported dicts mapping biome/subtype → texture-set paths and → scatter-variant lists, plus **per-category `kit_scale`** and `use_cel_environment`. Persisted at **`res://data/wilderness_assets.tres`**, lazy-loaded with a code-default fallback (mirror `dungeon_map_renderer_3d.gd:691-699`).

> **`kit_scale` is load-bearing, not optional** (coupled to the 1-unit-hex anchor in §6). Quaternius trees authored at ~real-world meters would be ~10–30 *units* tall in a world where a hex is 1 unit — wildly oversized. A **per-category** scale (trees vs rocks vs bushes vs tokens) is required so each asset class reads at the right size against a 1-unit hex.

**Cel/environment shader is an explicit verification item, not an assumption.** The dungeon's `res://engine/shaders/cel_environment.gdshader` matte was tuned for an enclosed interior; a continuous *outdoor* heightmap under a directional sun is a different lighting regime. Whether the cel look reads well on rolling, vertex-color-splatted terrain must be tested in W-2/W-4 (godot-ai MCP screenshot) before committing to it — it may want a distinct outdoor environment.

### 12.4 Asset gaps (decisions in §15)
- **Texture — swamp/bog:** no swamp ground set. Need one (or substitute a darkened `jungle_floor` for V1).
- **Texture/shader — water:** no water asset; needs a water shader (§8.4).
- **Object — reeds/cattails** (swamp/riverbank): none; `Willow`+`Lilypad` approximate.
- **Object — jungle canopy tree:** only `PalmTree`; a broadleaf would help.
- **Object — savanna acacia:** reuse `CommonTree` (acceptable).
- **Object — settlement/landmark meshes:** none for the strategic view; **decision:** keep billboarded 2D-style icons (port `hex_map_landmark_icons` to `Sprite3D`) vs. source simple keep/village meshes. V1: billboard icons.
- **Object/shader — roads:** no wilderness road asset; render as a draped decal/ribbon along `road_edges` (mirror the 2D overlay), with the Dungeon kit `BridgeSection` for crossings.
- Optional: taiga pine-duff floor, coast/beach sand blend (reuse desert).

---

## 13. Feature flag, renderer swap, integration

### 13.1 Flag
New `ProjectSettings` key **`acks/rendering/wilderness_hex_mode`**, values `"flat_2d"` (default) | `"heightmap_3d"`, read by a reader mirroring `dungeon_map_renderer_3d.gd:685-686`. Default preserves shipped behavior; flipping the flag swaps renderers. This mirrors the established `acks/rendering/dungeon_asset_mode` pattern exactly.

### 13.2 Swap mechanics
**Updated 2026-06-24 — the host changed.** The wilderness `HexMap` no longer sits at the `Main.tscn` root; it was reparented under a **bar-tracking SubViewport** so the map renders only above the resizable status bar (coding_conventions §84): the tree is now `Main/WorldViewport (SubViewportContainer, world_viewport_frame.gd, stretch=true)/WorldSubViewport/HexMap`. `SessionRunner` resolves it via `find_child("HexMap", true, false)` and exposes `get_world_viewport()` (`session_runner.gd:177-181`); `WildernessExploreState` toggles `WorldViewport.visible` alongside the renderer. The dungeon uses the *same* pattern with its own frame built at runtime (`dungeon_explore_state.gd:160-171`, `own_world_3d=true`).
- **A (recommended):** the 3D renderer scene mounts under the **same `WorldSubViewport`** (it inherits bar-tracking + the SubViewport's `own_world_3d` for its Camera3D — mirror the dungeon frame's `own_world_3d=true`). `SessionRunner.get_hex_map_renderer()` returns whichever renderer the flag (§13.1) selected; the other stays out of the tree. `SessionLoadState` calls `setup(controller)` once (guard `if renderer._controller == null`, `session_load_state.gd:74-79`); `WildernessExploreState` toggles visibility + connects the five signals (`wilderness_explore_state.gd:28-44`) — unchanged, because the 3D renderer honors the same API (§3.1).
- This keeps the state machine, `SettlementExploreState`, and every consumer untouched. The SubViewport already solves "the status bar occludes the map," which the 3D renderer inherits for free.

### 13.3 Coordinate convention note
The dungeon uses `Vector3i` entity positions (`coding_conventions.md:1881`); the wilderness gameplay seam stays `Vector2i(q,r)`. The 3D renderer is the *only* place that knows about Y/world space, converting `(q,r) ↔ Vector3` internally. Document this boundary so the convention's `Vector3i`-everywhere note isn't misread as requiring a wilderness-data change.

---

## 14. Data model and migrations

### 14.1 Height source plumbing — mostly already done
**Updated 2026-06-24.** `hex_cells.elevation_raw` **now exists and is populated** for 6-mile maps — `region_zoom_in.gd:135` writes it (flat-copied from the parent, §4.1). So the interim renderer can read `hex_cells.elevation_raw` directly today (no schema change, no parent-join), it's just coarse. The earlier "migration 163" prediction is moot — the migration counter is now at **175** (`db/migrations/175_campaigns_start_settlement.sql`); any future column lands at the next free number at build time. The real work is upstream: `gdd-continuous-geography.md` changes what value gets written into `elevation_raw` (a true field-sample instead of a parent copy) and adds the field representation it samples from — see that GDD's data-model section. Migrations remain sequential, integer-prefixed, non-destructive, append-only; update `db/schema.sql` after (`coding_conventions.md:760-776`).

### 14.2 No new gameplay state
The renderer persists nothing. Scatter, noise, and mesh are regenerated deterministically on load (§5.4). **Save/load guarantee:** because height and scatter are seeded from a stable per-campaign seed, reloading the same map yields byte-identical terrain — so a mid-exploration save/reload shows the same world, and tuning noise/scatter parameters does not break save compatibility (nothing terrain-visual is in the save). Fog/terrain/river *gameplay* state remain owned by the existing tables. Rough cost: height synthesis is O(hexes), scatter O(density × hexes); a 60×45 map with moderate scatter should synthesize in well under ~100 ms at load — confirm in the W-7 performance pass (§16).

---

## 15. Open Questions / Architectural Concerns

- **[DONE 2026-06-24] Design-brief amendment:** Jedidiah approved; the brief §5.1 table + §6.1 now document the flag-gated 2D/3D hex presentation (`acks/rendering/wilderness_hex_mode`). The 2D→3D change is unblocked.
- **[RESOLVED 2026-06-24] Scale strategy (§4):** the "24-mile 2D / 3D = 6-mile" split is now the **shipped architecture** (materialization M0–M4 + region-scale system landed; 24-mile World Map tab live). No longer an open fork.
- **[DEPENDENCY → SEQUENCING] Continuous-geography refactor first.** The 6-mile-derivation pipeline is BUILT (`region_zoom_in.gd`) but flat-copies height. Recommended order: land [`gdd-continuous-geography.md`](gdd-continuous-geography.md) (continuous field → `RAW_FIELD`) **before** this renderer, so the 3D map renders a true surface from day one and the renderer never needs the `PARENT_GUIDE` interim. That refactor pays off independently (better 2D maps, watershed, climate), so it's the right next build regardless of when the 3D renderer follows.
- **[OVERLAP] `gdd-terrain-system.md` §10:** that GDD owns the *2D* visual model (elevation overlays, river arrows). This GDD supersedes it **only for the 3D path**; §10 still governs the 2D renderer. Recommend a one-line cross-reference added to §10 pointing here, rather than moving content.
- **[ASSET GAPS] §12.4:** swamp texture, water shader, reeds, jungle canopy tree, settlement/road representation. Confirm fill-vs-substitute for V1 (recommended substitutes noted inline).
- **[DECISION] Landmarks/settlements in 3D:** billboard icons (port existing) vs. structure meshes (no assets). Recommend billboard icons for V1.
- **[DONE] 2D `ZOOM_MIN` fix (§11.2):** LANDED 2026-06-16 — fit-to-screen minimum zoom in `hex_map_renderer.gd`; parse-clean + clean real-engine boot. (Sub-1.0 zoom-out is only *observable* on a large map, which isn't playable until the setting-gen→game-day handoff lands.)
- **[POLISH] Climate-driven tinting (§7.4)** and **water waves/foam (§8.4)** are V2 polish; V1 ships flat-but-correct versions.
- **[VERIFY, build-time] Outdoor cel look (§12.3):** the dungeon's cel/matte environment is unproven on rolling sunlit terrain — a W-2/W-4 screenshot gate, not an owner decision; may need a separate outdoor environment.
- **[BUILD DETAIL] Seed source (§5.4):** wire height/scatter RNG to the stable per-campaign seed via an explicit mixing function (not built-in `hash()`); confirm the campaign-seed accessor at build time.
- **[RESOLVED in v0.2 review]** Picking now raycasts the collision surface (not the flat plane — parallax, §3.2/§11); the hex grid is single-pass (not `next_pass`, §10); cross-chunk normals use analytic/apron computation (§5.2/§6.1); MultiMesh scatter sets `custom_aabb` + shadow LOD (§9). No outstanding *technical* blockers — the gates below are design/asset decisions.
- **None blocking on ACKS rules.** This GDD adds no RAW interpretation (§2); if a rendering choice seems to need one, it belongs in `gdd-terrain-system.md`.

---

## 16. Suggested build phasing

1. **W-0 (independent) — DONE 2026-06-16:** 2D fit-to-screen zoom-out fix landed (§11.2).
2. **W-1:** import assets (§12) — textures → materials, trees → glTF, build `WildernessAssetRegistry` + `wilderness_assets.tres`; fill/substitute the swamp + water gaps.
3. **W-2:** flag + scene scaffold (`hex_map_renderer_3d.gd`, `hex_map_3d.tscn`), camera, picking, signal-contract parity (§3, §11, §13) — render a flat textured hex grid in 3D with full interaction parity (no relief yet). Verify via godot-ai MCP (project_run + screenshot).
4. **W-3:** height synthesis + smooth mesh + chunking + collision (§5–6); biome distortion.
5. **W-4:** splat texturing + edge dithering + fog + hex-grid shader (§7, §10).
6. **W-5:** surface features — lava/snow layers, river depressions, water (§8).
7. **W-6:** vegetation scatter + LOD (§9); landmark icons; roads.
8. **W-7:** climate tinting, polish, performance pass (§7.4, §8.4, §6.3).

Each phase is independently testable and leaves the 2D renderer as a working fallback.
