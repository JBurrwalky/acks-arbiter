# GDD: Quaternius Dungeon Asset Integration — Investigation & Plan

**Document type:** Game Design Document (project-designed, modifiable). **Investigation/planning draft.**
**Status:** Draft v1 — Pre-implementation assessment (2026-06-01)
**Authority:** Subordinate to `gdd-dungeon-map-ui.md` and `gdd-voxel-tactical-architecture.md`. Authoritative on **how Quaternius dungeon assets bind to the existing voxel renderer**: asset organization in-repo, scale/offset conventions, asset-to-feature mapping, import pipeline.
**Depends on:**
- `gdd-voxel-tactical-architecture.md` v1.1 — 5' cube voxel grid, `Vector3i(col,row,level)`, `VoxelGrid.cell_to_world()` (declared in `scenes/maps/tactical_grid_3d.gd`).
- `gdd-dungeon-map-ui.md` v2 — door states, stair direction suffixes, fog model, multi-level rendering.
- `gdd-dungeon-layout.md` — `DoorData.door_material`, `door_type`, `door_state`; `VoxelCell.feature` vocabulary.
- `acore_adventures_and_encounters.xml` — dungeon mapping scale rules.

**Modifiable:** Yes (project-designed). No code changes are recommended in this document; it is an assessment + plan only.

---

## 0. Status of this document

This is an **investigation report and plan**. No assets have been imported, no code has been changed. The goal is to establish:

1. What Quaternius gives us (asset inventory and properties).
2. What the renderer currently does (the contract the new asset path must satisfy).
3. The conceptual mismatch between Quaternius modular-kit assumptions and the arbiter's voxel data model — and how to bridge it.
4. Where to put assets in the repo, how to name them, and how to convert them.
5. Concrete asset-to-feature mapping, with sizing and offset rules.
6. Open design questions for Jedidiah to resolve before implementation.

---

## 1. What we have (Quaternius pack inventory)

Three folders live at `C:\Users\jttau\OneDrive\Pictures\Terrain`:

| Folder | Contents | Relevance |
|---|---|---|
| `Quaternius Dungeon\Blends\` | 91 `.blend` files: floors, walls, doors, stairs, columns, arches, traps, chests, torches, statues, props, plus some overgrown variants (vegetation on stone). Single shared `Texture.png` atlas referenced by all materials. | **Primary** — covers the dungeon renderer. |
| `Quaternius Wilderness\Blends\` | 152 `.blend` files: trees (birch / common / pine / palm / willow, with autumn / dead / snow variants), bushes, rocks (mossed/snowed variants), cacti, plants, grass, wheat, logs, lilypads. **Scenery props, not modular tiles.** | Out of scope for this plan — the dungeon renderer doesn't consume these. They belong to a future wilderness/hex visual-pass GDD. Mentioned only to confirm. |
| `Quaternius Wilderness Textures\` | (Folder — not inspected in this pass; presumably loose texture atlases.) | Out of scope. |

**Confirmed asset properties (inspected via Blender MCP, samples enumerated in §1.1 below):**

- **Coordinate system:** Blender default Z-up. Floors lie on the XY plane (Z is "up"). Walls span Z=0 to Z≈2.0 (the wall *stands up* in Z).
- **Modular grid:** Quaternius dungeon kit uses a **2.0-Blender-unit cell**. All floor tiles, wall pieces, and door frames are sized to a 2×2 footprint. Columns and trim are smaller in footprint but designed to sit *within* a 2×2 cell.
- **Wall thickness:** ~0.29 Blender units thick (0.145 each side of the cell edge). Wall length spans the full 2.0-unit edge.
- **Wall height:** 2.0 Blender units (matches a cube; corresponds visually to roughly 10 ft tall at 1u = 5 ft).
- **Doors:** Two-piece (`Doors_*_L` and `Doors_*_R`), each ~1.15×0.27×2.97. Together they fill a 2-unit-wide opening. The doors are *taller* than walls (~3.0 vs 2.0) because the round/gothic arch above them rises above the wall plane.
- **Arches (`Arch_Gothic`, `Arch_Round`):** Wider than a single cell (~3.0 wide) and taller than walls (~3.76 tall). These are *frame* pieces meant to sit *above* a doorway — not floor-plane occupants.
- **Stairs:** A single 2×2 footprint, ~0.92 tall — rises roughly half a wall height per stair piece. To climb a full 5 ft (one voxel level) we need *two* Quaternius stair pieces stacked / pathed, OR we accept that a Quaternius stair cell rises less than a voxel level and treat it as decorative.
- **Materials:** Almost every dungeon asset shares a tiny palette of named materials (`Main`, `Highlights`, `Wood`, `DarkWood`, `Metal`, `Metal_Light`, `Fire`, `Green`, `Leaf_Texture`, etc.) that all sample the same `Texture.png` (a color-palette gradient atlas). This is **excellent** for draw-call batching — once converted to glTF the entire dungeon kit can share one (or a small number) of materials.
- **Origins:** All inspected dungeon pieces use **world-origin (0,0,0)** as their pivot, except door halves (which use ±1.0 X offset to position each half on the appropriate side of the doorway). This is the Quaternius convention.

### 1.1 Inspected sample

The following were opened and bbox-measured during this assessment:

| File | Dims (Blender units) | Notes |
|---|---|---|
| `Floor_Standard.blend` | 1.99 × 1.98 × 0.29 | Square floor tile, 1 cell footprint. |
| `Floor_SquareLarge.blend` | 1.98 × 1.98 × 0.11 | Thinner floor variant. |
| `Floor_Hole_Straight.blend` | 2.00 × 1.10 × 0.14 | Half-tile (pit/hole on one edge). |
| `Floor_Hole_Corner.blend` | 1.99 × 2.00 × 0.14 | Corner hole. |
| `Wall.blend` | 2.00 × 0.29 × 2.00 | Standard wall, 1 cell edge long. |
| `Wall_Hole.blend` | 2.00 × 0.29 × 2.00 | Wall with a hole/breach. |
| `Wall_Double_Hole.blend` | 1.99 × 1.98 × 0.57 | (Likely a wall section in a different orientation — rotation_euler[X] = -90°. Needs visual inspection to confirm role.) |
| `Wall_ArchRound.blend` | 4.00 × 4.00 × 0.31 | Wider-than-one-cell decorative arch piece. |
| `Doors_RoundArch.blend` | 2 objects, each 1.15 × 0.27 × 2.97, origins at ±1.0 X | Two-leaf door. |
| `Arch_Gothic.blend` | 3.09 × 0.49 × 3.76 | Decorative arch (wider than one cell). |
| `Stairs.blend` | 2.02 × 2.15 × 0.92 | One-cell stair rising ≈ 1u (half wall height). |
| `Column_Round.blend` | 0.66 × 0.66 × 3.99 | Tall slim column — 2 wall-heights. |
| `Support_Center.blend` | 3.00 × 0.66 × 4.11 | Multi-cell support beam. |
| `Chest.blend` | 1.14 × 0.82 × 0.57 (base) + lid | Two-object chest. |
| `Torch.blend` | 0.28 × 0.44 × 1.17 | Wall-mounted torch prop. |
| `Trapdoor.blend` | 1.74 × 1.57 × 0.22 | One-cell trapdoor (floor inset). |
| `BearTrap_Closed.blend` | 1.13 × 1.42 × 0.68 | Visible trap prop. |
| `Statue_Stag.blend` | 2.31 × 1.27 × 4.63 | Decorative statue, ~2 wall heights. |

**Materials shared across this sample:** `Main`, `Highlights`, `Wood`, `DarkWood`, `Metal`, `Metal_Light`, `Green`, `Leaf_Texture`, `Black`, `Fire`, `DarkMetal`. Single shared `Texture.png` atlas.

---

## 2. What the renderer currently does (the contract)

Inspected: `scenes/maps/tactical_grid_3d.gd` (1,034 lines) and `scenes/maps/dungeon_map_renderer_3d.gd` (1,634 lines).

### 2.1 Cell coordinate system

```
const CELL_SIZE := 1.0          # 1 world unit per cell edge
const HALF_CELL := 0.5
const ELEVATION_SCALE := 0.5    # 0.5 world units Y per voxel level (visual squash)
const WALL_HEIGHT := 1.4        # Code-generated walls drawn 1.4u tall (visual exaggeration)
```

`cell_to_world(col, row, elevation)` produces the **diamond-layout** isometric world position:
```
x = (col − row) × 0.5
y = elevation × 0.5
z = (col + row) × 0.5
```
The camera sits at the true isometric tilt (`−35.264°` X, `−45°` Y in scene; the `−45°` is baked into the diamond layout above). World units along the floor plane: **1 world unit = 1 cell edge = 5 ft.**

**Important:** Y is visually compressed. One voxel level (5 ft real-world height) renders as 0.5 world units Y, while one horizontal cell (also 5 ft) renders as 1.0 world units along the diamond axis. Wall meshes also exaggerate height (1.4 instead of 1.0). This is a *visual* decision baked into the existing renderer — see §6 Open Question O-DA-1.

### 2.2 Builder functions (current code-generated geometry)

In `tactical_grid_3d.gd`, all `build_*` functions are `static` and return `Node3D`/`MultiMeshInstance3D` subtrees that the renderer parents under `$GridMeshes`:

| Builder | Produces | Geometry |
|---|---|---|
| `build_floor_multimesh_voxel(map, level, color_func)` | One `MultiMeshInstance3D` per level | Flat diamond meshes textured with `assets/floors/slate_tile_light.png`, UV-tiled. |
| `build_walls_voxel(map, level)` | `MultiMeshInstance3D` (non-focus levels) | Cubes shrunk to 0.7×WALL_HEIGHT×0.7 at solid cells, rotated 45° around Y to align with diamond grid. Textured with `assets/walls/stone_brick_dark_01.png`. |
| `build_walls_voxel_individual(map, level)` | `Node3D` of `MeshInstance3D` (focus level) | One `BoxMesh` per solid cell so each wall can be camera-faded independently. |
| `build_doors_voxel(map, level)` | `Node3D` | Single thin `BoxMesh` per door cell, sized 0.6×0.7×0.08 for swing-doors, 0.6×0.8×0.05 for portcullises, rotated by `_compute_door_orientation_voxel()` (45° / −45° based on which neighbors are passable). Open swing-doors rotate +90°. Open portcullises translate Y up. |
| `build_features_voxel(map, level)` | `Node3D` | **DG-C3D.G placeholder primitives** (simple boxes — real Quaternius meshes still TODO): stepped stairs (3 rising treads + ▲/▼), spiral (central post + quarter-treads), ramp (inclined slab — previously rendered nothing), parapet rail on balcony-edge cells (`cover_value > 0`, on the void-facing side — previously rendered nothing). Ladder = vertical thin BoxMesh. Lever = Label3D gear icon. **[DG-C3D.G]** these are stand-ins; the asset path should supply real step/spiral/parapet/balcony-edge meshes (see contiguous GDD §12.7). |
| `build_fog_overlay_voxel(map, level)` | `MultiMeshInstance3D` | Diamond mesh with fog-tinted material at FOG_Y above floor. |
| `build_grid_lines_voxel(map, level)` | `MeshInstance3D` (LINES primitive) | Wireframe grid. |
| `build_highlight_voxel(...)` | `MultiMeshInstance3D` | Selection / move-range overlays. |

`dungeon_map_renderer_3d.gd::_on_map_loaded` and `_rebuild_*` methods call these builders per level and parent the results under `$GridMeshes`. Walls on the focus level are tracked in `_wall_meshes: Dictionary[Vector2i → MeshInstance3D]` for camera-occlusion fade.

### 2.3 Critical invariant: cells, not edges

In the voxel data model, a **cell is solid OR air** (`VoxelCell.solidity`). Walls **occupy whole cells** in the data model — there is no concept of "a wall on the north edge of cell (3, 5)". A 10-ft-wide corridor is two adjacent air cells flanked by solid cells; the wall is the *solid cell itself*.

The current code-generated renderer reflects this: walls are drawn *at the position of solid cells*. Doors are drawn at door cells (which are themselves passable, with `door_state` overlay).

**This is the central conceptual mismatch with Quaternius**, addressed in §3.

### 2.4 Textures already in repo

```
assets/floors/
  grass_green_bright.png, grass_green_dark.png, slate_tile_light.png
assets/walls/
  stone_brick_dark_01.png, wood_oak_weathered.png
```

These are 2D image atlases used by the code-generated geometry. They are **not Quaternius assets** — they are stand-in flat textures. We do not need to migrate them; the new asset path replaces them with textured 3D meshes.

---

## 3. The central conceptual mismatch (and how to bridge it)

**Quaternius convention:** Cells = floor tiles. Walls and doors sit **on cell edges** (between two cells). A corridor of N×1 cells is rendered as N floor tiles with wall pieces along the long edges.

**Arbiter convention:** Cells are solid (wall) or air. Walls live **at cell positions**. A corridor of N×1 air cells is implied by adjacent solid cells; nothing renders "between" cells.

We have three bridging strategies. **Strategy A is recommended.**

### 3.1 Strategy A — Edge-resolved rendering (recommended)

Keep the voxel data model exactly as it is (cells are solid or air). At render time, derive wall placements by walking each **air cell's perimeter** and emitting a wall piece for each edge where the neighbor is solid. The wall piece is positioned *on the edge between the air cell and the adjacent solid cell*, oriented perpendicular to that edge.

**Pros:**
- No data-model change. The voxel architecture is sacred and tested.
- Quaternius walls drop in naturally (they are designed for edges).
- Wall thickness sits in the "solid" half-cell space, so 5-ft passages remain visually 5-ft from inside-face to inside-face.
- Works identically for code-generated and asset-based rendering; we can keep a debug-toggle to flip between them.

**Cons:**
- The "wall cell" itself is still in the map data but is no longer a render target — it becomes *just a passability/LOS blocker*. The current `_wall_meshes` dictionary keyed by wall cell position must be re-keyed by **(air_cell, edge_direction)** pairs or by wall-mesh-instance ID directly.
- Camera-occlusion fade logic (which currently looks up a wall mesh by cell position) must adapt — easy fix, since the air cell on the "inside" of each wall edge is unique and reachable.
- Solid cells that are *fully interior* (surrounded by other solid cells — i.e. rock filler) emit nothing. That's correct: the player never sees them. (The current renderer over-renders here; this is a *win*, not a regression.)
- Corner pieces: at a corner where two perpendicular walls meet, two edge-walls render and may visually clip. Quaternius walls are short enough (0.29 thick) that this is usually invisible; if not, we can add a corner-detection pass and substitute a corner piece (the Quaternius pack does not appear to ship a dedicated corner mesh — walls are pure straight segments — but the visual clip is acceptable per Quaternius's own demo scenes).

### 3.2 Strategy B — Per-cell pillar rendering (rejected)

Keep walls as cell-occupying meshes (one Quaternius wall per solid cell, scaled to fill the cell). This is what the current code-generated path does, just swapped to Quaternius geometry.

**Rejected because:** Quaternius walls are *thin slabs*, not pillars. A 1-cell-wide solid wall rendered as a slab in a cell would either leave gaps (slab is thin, cell is 1 unit wide) or be visually wrong (a stretched slab to fill the cell looks like a thick wall, not a corridor edge).

### 3.3 Strategy C — Migrate to edge-based data model (rejected)

Refactor the voxel data model so walls are stored on edges rather than at cell positions. This is what most tactical RPGs do (D&D Beyond's maps, Solasta, etc.).

**Rejected because:** the voxel architecture is settled, well-tested, and consumed by pathfinding, fog, claim-based occupancy, LOS, and a dozen other subsystems. Touching this for visual reasons alone is a massive ripple. Strategy A delivers the same visual outcome without the refactor.

### 3.4 The plan from here proceeds with Strategy A

All asset-to-feature mappings, sizing, and offset rules in §5 assume Strategy A. The implementation work (out of scope for this document) is roughly:
1. Add a `WallEdgeResolver` that, given a `VoxelMapData` and a level, returns `Array[Dictionary]` of `{air_cell: Vector3i, edge_dir: int, neighbor_solid_cell: Vector3i}` records.
2. Add a `DungeonAssetRegistry` autoload-or-resource that maps logical asset slots (e.g. `"wall_straight"`, `"door_swing_round_arch"`, `"floor_standard"`) to scene paths or pre-loaded `PackedScene` / `MeshLibrary` entries.
3. Replace each `build_*_voxel` static call in `dungeon_map_renderer_3d.gd::_on_map_loaded` with an asset-instantiation pass guarded by a project setting toggle (so code-generated geometry remains the fallback during dev / tests).
4. Implement camera-occlusion fade against the new asset instances.

---

## 4. Repo organization and naming

### 4.1 Where to put the imported assets

```
acks-arbiter/
  assets/
    dungeon_kit/                         # NEW — Quaternius dungeon pack, glTF-converted
      _SOURCE.md                         # provenance, license, version, original folder
      shared_texture.png                 # the single Quaternius atlas (256×256 or whatever)
      shared_material.tres               # one StandardMaterial3D using shared_texture.png
      floor/
        floor_standard.glb               # converted from Floor_Standard.blend
        floor_diamond.glb
        floor_square_large.glb
        floor_standard_half.glb
        floor_hole_corner.glb
        floor_hole_straight.glb
        floor_tree.glb                   # decorative — root growing through floor
      wall/
        wall_straight.glb                # from Wall.blend
        wall_half.glb
        wall_broken.glb
        wall_hole.glb
        wall_double_hole.glb
        wall_overgrown.glb
        wall_arch_round.glb              # decorative — over a doorway
        wall_arch_gothic.glb
        wall_arch_round_broken.glb
        wall_arch_round_overgrown.glb
        window_open.glb
        window_open_double.glb
        window_bars.glb
        window_bars_overgrown.glb
        window_bars_double_overgrown.glb
      door/
        door_round_arch.glb              # two-leaf, from Doors_RoundArch.blend
        door_round_arch_covered.glb      # curtained variant
        door_gothic_arch.glb
        door_gothic_arch_covered.glb
        trapdoor.glb
      stair/
        stairs.glb
        stairs_2.glb                     # alt variant
      column/
        column_round.glb
        column_round_short.glb
        column_square.glb
        column_bridge_support.glb
        arch_round.glb                   # standalone arch (not the wall-arch variants)
        arch_round_round_column.glb
        arch_gothic.glb
        arch_gothic_round_column.glb
      structure/
        bridge_section.glb
        support_center.glb
        support_left.glb
        support_right.glb
        support_tall.glb
        rail_straight.glb
        rail_corner.glb
        rail_divider.glb
      trap/
        bear_trap_closed.glb
        bear_trap_open.glb
      container/
        chest.glb
        chest_gold.glb
        barrel.glb
        crate.glb
        cart.glb
        bookcase_empty.glb
        bookcase_full.glb
        pot1.glb
        pot1_broken.glb
        pot2.glb
        pot2_broken.glb
        pot3.glb
        pot3_broken.glb
      prop/
        torch.glb                         # wall-mounted, prop
        candles_1.glb
        candles_2.glb
        skull.glb
        brick.glb                         # debris
        bricks.glb                        # debris pile
        flag_wall.glb
        flag_wall2.glb
        flag_round_arch.glb
        flag_gothic_arch.glb
        statue_fox.glb
        statue_stag.glb
      overgrowth/                         # vegetation through dungeon stonework
        bush_1x1.glb
        bush_2x1.glb
        bush_2x2.glb
        bush_round.glb
        bush_large.glb
        grass.glb
        dead_tree_1.glb
        dead_tree_2.glb
        dead_tree_3.glb
        tree_1.glb
        tree_2.glb
        tree_3.glb
        curve_1.glb                       # curved path piece
        curve_1_overgrown.glb
        curve_2.glb
        curve_2_overgrown.glb
```

**Naming convention:** `snake_case` filenames matching the existing repo conventions (per `CLAUDE.md` §Naming). Original Quaternius filenames (PascalCase, `Doors_RoundArch.blend`) are lowercased+snake_cased at conversion time. The asset registry resolves logical IDs → file paths so the rest of the engine never sees the on-disk names.

**Why glTF (`.glb`)?** Godot 4 imports glTF natively, fast and zero-friction. Blender's "Export as glTF" honors object pivots, applies modifiers, embeds materials, and bakes scale into vertex positions — so we sidestep the "scale not applied" weirdness in the source `.blend` files (`Floor_Standard.blend` has scale `(1, 1, 0.06)` not applied; glTF export bakes it). Godot does not natively import `.blend` outside the editor (the optional "Use Blender to import" project setting requires every dev to have Blender installed and configured — too brittle).

**Why `.glb` (binary) rather than `.gltf` + buffer?** Single-file is easier to git-track and reduces filesystem churn. The shared `Texture.png` becomes embedded per-file (small cost, ~50 KB per file given the atlas is tiny) **OR** we configure the Blender exporter to share an external texture and Godot's importer to share it across `.glb` files — see §4.3.

**Provenance file (`_SOURCE.md`):** Records that these came from the Quaternius free pack, license terms (CC0), original folder name, conversion date, conversion script. CC0 means no attribution required, but we list it anyway for posterity.

### 4.2 Asset registry resource

```
data/dungeon_assets.tres   # Resource — DungeonAssetRegistry
```

The registry is a `Resource` with dictionaries mapping logical IDs to scene paths and per-asset metadata:

```gdscript
# engine/shared_types/dungeon_asset_registry.gd
class_name DungeonAssetRegistry extends Resource

@export var floors: Dictionary = {
    "standard": "res://assets/dungeon_kit/floor/floor_standard.glb",
    "diamond":  "res://assets/dungeon_kit/floor/floor_diamond.glb",
    # …
}
@export var walls: Dictionary = {
    "straight":   "res://assets/dungeon_kit/wall/wall_straight.glb",
    "half":       "res://assets/dungeon_kit/wall/wall_half.glb",
    "broken":     "res://assets/dungeon_kit/wall/wall_broken.glb",
    "window":     "res://assets/dungeon_kit/wall/window_open.glb",
    "window_bars":"res://assets/dungeon_kit/wall/window_bars.glb",
    # …
}
@export var doors: Dictionary = {
    "swing_round":  "res://assets/dungeon_kit/door/door_round_arch.glb",
    "swing_gothic": "res://assets/dungeon_kit/door/door_gothic_arch.glb",
    "curtain_round":"res://assets/dungeon_kit/door/door_round_arch_covered.glb",
    "trapdoor":     "res://assets/dungeon_kit/door/trapdoor.glb",
    # …
}
@export var stairs: Dictionary = { … }
@export var features: Dictionary = { … }   # levers, fountains, altars, statues
@export var traps: Dictionary = { … }
@export var containers: Dictionary = { … }
@export var overgrowth: Dictionary = { … }

# Default selection rules (e.g. which floor type if cell.feature is unspecified)
@export var default_floor: String = "standard"
@export var default_wall: String = "straight"
@export var default_swing_door: String = "swing_round"
```

The renderer asks the registry for a logical type (`registry.walls["straight"]`) and gets a scene path. Swapping kits later (Quaternius Sci-Fi pack, custom art) means changing the registry, not the renderer.

### 4.3 Shared texture handling

Every Quaternius dungeon asset shares one `Texture.png` (a tiny color-palette atlas). Two viable approaches:

**Approach 1 — Per-file embedded (simpler):** Each `.glb` embeds `Texture.png` (≈10–50 KB each). 90 files × ~30 KB ≈ 3 MB total — trivial. Godot creates one StandardMaterial3D per file's material, which means many StandardMaterial3D instances all pointing at copies of the same texture. Slower draws *might* matter at scale, but for a typical dungeon (a few hundred mesh instances) it doesn't.

**Approach 2 — Shared external (more work, better batching):** Configure Blender's glTF exporter to write `Texture.png` as a sibling file rather than embedding. All `.glb` files reference the same external `assets/dungeon_kit/shared_texture.png`. Then write a post-import `.import` config override that points every material at a single shared `assets/dungeon_kit/shared_material.tres`. This collapses N material instances to 1 and enables MultiMesh batching.

**Recommendation:** Start with **Approach 1** (embed everything in `.glb`). It is the lowest-friction path and works out of the box. If profiling later shows draw-call pressure (probably won't until dungeons are very dense), upgrade to Approach 2 with a small migration script that rewrites the `.import` files.

### 4.4 Conversion script

A one-time conversion script (Python, run inside Blender) iterates `OneDrive\Pictures\Terrain\Quaternius Dungeon\Blends\*.blend`, opens each, applies transforms, exports `.glb` to the target path. Save the script alongside the assets:

```
assets/dungeon_kit/_convert.py     # blender --background --python _convert.py
```

The script:
1. For each `.blend`, open it.
2. For each mesh object, apply scale and rotation (`bpy.ops.object.transform_apply(scale=True, rotation=True)`) so the glTF exporter writes "clean" vertex data.
3. Optionally apply the **uniform 0.5 scale** here (Quaternius 2-unit cell → arbiter 1-unit cell) so the exported `.glb` is already in arbiter scale.
4. Export `.glb` with `bpy.ops.export_scene.gltf(filepath=..., export_format='GLB', export_apply=True, export_yup=True)`. `export_yup=True` converts Blender Z-up → glTF Y-up (which Godot expects).
5. Lowercase + snake_case the output filename.

This script lives in the repo so re-running it is reproducible. The Quaternius `.blend` source files themselves do **not** need to live in the repo — they're upstream art that we cache the converted output of. We do save the original source folder location in `_SOURCE.md` so future devs can re-run the conversion if Quaternius releases an updated pack.

---

## 5. Asset-to-feature mapping

This section assumes **Strategy A** (edge-resolved rendering) from §3.1. Sizes are given **post-conversion** (after the 0.5 scale bake — so all values are in arbiter world units, where 1.0 = 5 ft = one cell).

### 5.1 Floor tiles — one per air cell

For each air cell at the focus level (and dimmed/dithered for levels below/above), instantiate one floor `.glb`:

| `VoxelCell.feature` (or fallback) | Floor asset | Notes |
|---|---|---|
| `"open"` (default air) | `floor/floor_standard.glb` | Standard square tile. |
| `"open"` with surface-variant flag (e.g. ornate room) | `floor/floor_diamond.glb` or `floor/floor_square_large.glb` | Player-visible distinction for chambers vs. corridors. Tag could come from dungeon stocking. |
| `"pit"` / `"chasm"` | `floor/floor_hole_straight.glb` or `floor/floor_hole_corner.glb` | Renders the half-floor; the player can see down to the next level. |
| Cell adjacent to a stair feature | `floor/floor_standard_half.glb` | Optional — Quaternius has half-tiles to blend the stair platform into the surrounding floor. |
| Cell with overgrowth tag | `overgrowth/grass.glb` over `floor_standard.glb` | Decorative additive prop. |

**Sizing:** 1.0 × 1.0 × ~0.14 (or 0.05 for the thinner variants). Origin at cell center. Y position = `cell_to_world(col, row, level).y` (which is `level * ELEVATION_SCALE`).

**Offset:** None. Floor sits at the cell's world position directly.

**Replaces:** `TacticalGrid3D.build_floor_multimesh_voxel()`.

### 5.2 Wall pieces — one per air-cell edge whose neighbor is solid

For each air cell at the focus level, examine its four cardinal neighbors (N, S, E, W in voxel grid coordinates). For each direction where the neighbor cell is `solidity == "solid"`, place a wall piece on that edge.

| Condition | Wall asset | Orientation |
|---|---|---|
| Solid neighbor, no special tag | `wall/wall_straight.glb` | Rotated to lie along the edge (see §5.2.1). |
| Solid neighbor + "broken" tag (rubble) | `wall/wall_broken.glb` | Same. |
| Solid neighbor + "overgrown" tag (outdoor/abandoned) | `wall/wall_overgrown.glb` | Same. |
| Solid neighbor + "window" tag (specially stocked) | `wall/window_open.glb` or `wall/window_bars.glb` | Same. Surfaces LOS but blocks passage. |
| Solid neighbor + "arch_decorative" tag (ornate transition) | `wall/wall_arch_round.glb` (overhead arch) — see §5.2.3 | Decorative; does NOT replace the wall, sits *above* it. |

#### 5.2.1 Wall placement geometry

A Quaternius wall is **2 Blender units long × 0.29 thick × 2 Blender units tall** → after 0.5 scale bake: **1.0 long × 0.145 thick × 1.0 tall**. It sits along the edge between two cells.

For an air cell at world position `P = cell_to_world(col, row, level)` and a solid neighbor in direction `D` (one of N, S, E, W):
- The midpoint of the shared edge is `P + 0.5 * direction_vector(D)`, where `direction_vector(D)` is the world-space unit vector from cell center to neighbor center.
- The wall mesh's local +Y face (after Z→Y conversion, the wall's outward "thick" face) should point *toward the air cell* (player-visible side gets the textured face).
- The wall's long axis is **perpendicular** to `direction_vector(D)`.

Concretely, in the diamond layout (per `VoxelGrid.cell_to_world`):
- Moving N (col, row) → (col, row−1) is world direction `(+0.5, 0, −0.5)`. The wall's long axis is the perpendicular `(+0.5, 0, +0.5)`.
- Moving S: world direction `(−0.5, 0, +0.5)`, perpendicular `(−0.5, 0, −0.5)`.
- Moving E (col, row) → (col+1, row): world `(+0.5, 0, +0.5)`, perpendicular `(+0.5, 0, −0.5)`.
- Moving W: world `(−0.5, 0, −0.5)`, perpendicular `(−0.5, 0, +0.5)`.

In practice this is `transform = Basis(Quaternion(Y, rotation_for(D))) * translation(P + 0.5 * D)`. The `rotation_for(D)` is one of four 45°-multiple values matching the diamond grid.

**Wall Y offset:** The wall mesh's local Z=0 is its base after glTF Z→Y conversion (which makes it Y=0). The wall stands from Y=0 (floor plane at this level) up to Y=1.0. Multi-level: at level `n`, the wall base sits at `Y = n * ELEVATION_SCALE`, i.e. `0.5 * n`.

**Visual-squash tension:** Because `ELEVATION_SCALE = 0.5`, a level transition is 0.5 world units, but a wall is 1.0 world units tall. This means a single-story wall is **twice as tall as a level's elevation gap** — the wall pokes up past the level above. This is consistent with the current renderer's `WALL_HEIGHT = 1.4` (also taller than 0.5). The visual reading is *"this is a tall wall, taller than people"*, which is what we want. See O-DA-1 in §6.

#### 5.2.2 Camera-occlusion fade

The existing renderer fades wall meshes that lie between the camera and a selected entity. The fade dictionary `_wall_meshes: Dictionary[Vector2i → MeshInstance3D]` needs to be re-keyed for edge-resolved walls. Two options:
- **Re-key by air-cell + direction:** `Dictionary[(Vector3i, int) → Node3D]` where Vector3i is the air cell and int is the direction (0–3). The fade pass iterates these instead of `_wall_meshes`.
- **Re-key by the solid cell (the wall's source):** keep `Dictionary[Vector3i → Array[Node3D]]` because a single solid cell may emit walls on multiple edges (up to 4) that all need to fade together. This preserves the spirit of the current API.

The second is closer to the current code. Recommend that.

#### 5.2.3 Decorative arches (over doorways)

`wall/wall_arch_round.glb` and `arch_gothic.glb` are *frame* pieces meant to sit above a doorway. They are wider than one cell (≈1.5–2.0 cells wide post-scale) and taller than a wall. Place them only where:
- The wall has a door cell on the air-cell side, AND
- The stocking tag flags the door as "ornate".

They do not replace the wall; they sit *above* it, at the level-cap height. Optional decorative pass.

### 5.3 Doors

For each cell with `door_state.is_empty() == false` and `door_state != "destroyed"`:

| `cell.door_type` | `cell.door_material` | Asset | Notes |
|---|---|---|---|
| (any swing door) | `wood_standard`, `wood_thick` | `door/door_round_arch.glb` (or `door_gothic_arch.glb`) | Two-leaf model; the `_L` and `_R` halves are children of the parent scene. |
| (any swing door) | `stone`, `metal` | `door/door_round_arch.glb` | Same mesh, override material with a darker palette tint (see §5.3.2). |
| (any swing door) | `curtain_cloth`, `curtain_leather` | `door/door_round_arch_covered.glb` (or `door_gothic_arch_covered.glb`) | Pre-modeled curtain variant. |
| `"secret"` | (n/a) | (no mesh if `door_detected == false`) — when detected, show as `wall/wall_hole.glb` or render with a faint outline | The current code renders a thin gray box for detected secret doors; we should follow that. |
| `"portcullis"` | (n/a) | `door/door_round_arch.glb` *or* a custom portcullis mesh — Quaternius does not ship one; suggest substituting `wall/window_bars.glb` rotated into the doorway as a placeholder | Open portcullis: translate Y up by 0.6 (matches current behavior). |
| `"trapdoor"` (cell.feature, not door_type) | (n/a) | `door/trapdoor.glb` | Sits in the *floor* of the cell, not on a wall edge. |

#### 5.3.1 Door placement geometry

A door cell is itself an air cell (passable when open). The door visually sits *on* one of its four edges — the edge that connects the corridor / room on either side. `_compute_door_orientation_voxel()` already determines this (returns 45° or −45° based on which neighbor pair is passable).

For Quaternius doors, the placement is:
- World position = `cell_to_world(door_cell)` (same as the air cell's center).
- Rotation = the same `_compute_door_orientation_voxel()` result.
- Y offset = 0 (door sits on the floor of its cell, frame extending upward).
- **Closed:** door is visible with both leaves shut.
- **Open:** rotate one leaf 90° around its hinge (Quaternius door halves have their origin offset to ±1.0 X pre-scale = ±0.5 X post-scale, which puts each origin at the hinge edge — convenient).
- **Locked / stuck:** material override with a darker tint; the leaves stay closed.
- **Destroyed:** do not render the door at all. The cell is passable and visually reads as an open passage. (Per O-DA-8 resolution.)

#### 5.3.2 Material override for door state

The Quaternius door comes with `DarkWood` / `Wood` / `Metal` / `Metal_Light` materials. For `stone` and `metal` door materials, we override the wood materials with a tinted variant. For `locked` / `stuck`, we darken the material by 20% (matches current renderer behavior).

This is a runtime `MeshInstance3D.material_override` on the door scene's mesh nodes. Easy.

#### 5.3.3 Two-leaf doors and open animation

`Doors_RoundArch.blend` ships with two objects (`Doors_RoundArch_L`, `Doors_RoundArch_R`), origins at ±1.0 X. After glTF export, this becomes a scene with two child mesh nodes. To animate "open", rotate `_L` by +90° around its local Y and `_R` by −90° around its local Y (or just one of them for a half-open look). The hinges align with the cell edge naturally because the origins sit at the edge.

For the initial integration, we can skip animation and just snap to closed/open states (matching the current renderer's behavior). Animated swing is a polish pass.

#### 5.3.4 Replaces

`TacticalGrid3D.build_doors_voxel()`.

### 5.4 Stairs

Quaternius `Stairs.blend` is **0.92 tall** at the original 2-unit scale → **0.46 tall** post 0.5 bake. That's slightly *less* than `ELEVATION_SCALE = 0.5`, which is the Y delta of one voxel level. So one Quaternius stair piece climbs *nearly* one full level — close enough.

| `cell.feature` | Asset | Placement |
|---|---|---|
| `"stairs_up_<DIR>"` | `stair/stairs.glb` | Rotate to face `DIR` (use existing `_stair_direction_rotation()` mapping). Tilt: stair model already has its rise built in; no additional X-rotation needed. Position at cell world position. |
| `"stairs_down_<DIR>"` | `stair/stairs.glb` rotated 180° around the cardinal axis | Or use the alt `stair/stairs_2.glb` variant. |

**Caveat:** Quaternius stairs are designed as a 1-cell-footprint piece that visually climbs 5 ft. The voxel arch treats a stair as a one-cell transition (cell at level N has feature `stairs_up_N`, paired with a cell at level N+1). Visually this lines up. We do **not** need two stacked stair pieces — one suffices.

The current renderer draws stairs as a tilted thin box with a Label3D ▲/▼ arrow billboard. Once we have Quaternius stairs, the arrow billboard should remain (it's a UX affordance, not a model element) — render it on top of the asset.

**Replaces:** the stair branch of `TacticalGrid3D.build_features_voxel()`.

### 5.5 Other features

| `cell.feature` | Asset | Notes |
|---|---|---|
| `"ladder"` | `column/column_round.glb` *scaled to be ladder-ish* — Quaternius doesn't ship a ladder. **Defer**; keep the current code-generated vertical box for now. | Flag as missing-asset (O-DA-3 below). |
| `"lever"` | `prop/torch.glb` is *not* a lever. Quaternius doesn't ship a lever. **Defer**; keep current Label3D gear icon. | Flag as missing-asset. |
| `"fountain"` | (no Quaternius fountain) | Use `container/barrel.glb` as a placeholder or defer. |
| `"altar"` / `"statue"` | `prop/statue_fox.glb`, `prop/statue_stag.glb` | Place at cell center. |
| `"column"` (decorative obstacle) | `column/column_round.glb`, `column_square.glb`, etc. | Place at cell center; air cells with column feature remain passable around the column (or not, per stocking). |
| `"trapdoor"` (in floor) | `door/trapdoor.glb` | Inset into floor at cell center. |
| Trap (cell has trap data) | `trap/bear_trap_closed.glb` (or `_open.glb` after triggered) | Only render if `trap.detected == true`. Otherwise floor looks normal. |
| Container (chest, barrel, crate) | `container/chest.glb`, `container/barrel.glb`, etc. | These are floor props placed at cell center alongside the floor tile. |
| Loose decor (pots, candles, bones, debris) | `prop/*.glb` | Decorative; placed by stocking, ignored by gameplay. |
| Wall-mounted torch | `prop/torch.glb` | Mounted to a wall edge; place at +0.5 Y, on the wall-edge facing the air cell. Used by `DungeonLightManager` for visible-light affordance. |

### 5.6 Wilderness assets (out of scope, but noted)

The wilderness pack is **scenery, not modular**. Trees, rocks, plants, etc. are scattered props meant to be placed manually or procedurally — they do not tile to a grid. They are appropriate for:
- The hex map renderer (decorating wilderness hexes with tree/rock clusters).
- The settlement map renderer (decorating town/village outskirts).
- Outdoor "dungeon" levels (overgrown ruins, druid groves) where some Quaternius dungeon assets already include vegetation variants.

This integration plan does **not** cover wilderness assets. They warrant their own GDD once the wilderness/hex visual pass starts. The dungeon kit can use the `overgrowth/` Quaternius dungeon-pack subfolder (which includes some trees and bushes) for indoor-overgrowth dressing.

---

## 6. Open design questions

| ID | Question | Default proposal |
|---|---|---|
| **O-DA-1** | Should we restore `ELEVATION_SCALE = 1.0` (full 5-ft Y per level) when switching to Quaternius assets, so walls and assets look proportionally correct? Or keep `0.5` for the squashed isometric look? | **Keep 0.5 for now**. The squashed Y is intentional for isometric readability per voxel arch §16. Quaternius walls (1.0 tall) will visually overrun the level-cap on multi-level maps, but that's *also* how the current code-generated walls behave (`WALL_HEIGHT = 1.4`). If multi-level dungeons feel wrong visually, revisit with a per-level clipping pass. |
| **O-DA-2** | Strategy A vs. B vs. C in §3? | **Strategy A** (edge-resolved). Confirm this before code work begins. |
| **O-DA-3** | Missing assets in Quaternius pack (ladder, lever, fountain). Wait, source elsewhere, or improvise from existing pack? | **Improvise / defer.** Keep current code-generated geometry for these until a future kit ships them or we commission custom. |
| **O-DA-4** | Texture sharing — embed in `.glb` (Approach 1) or share external (Approach 2)? | **Approach 1** (embed). Revisit if draw-call profiling shows pressure. |
| **O-DA-5** | Should the asset registry be a `.tres` resource (designer-editable in editor) or a hand-edited `.gd` constant dictionary (versioned in git, code-reviewed)? | **`.tres` resource.** Designer-editable is the explicit goal — Jedidiah swaps in new kits without code review. Editing happens in Godot editor; persistence is text-based `.tres` (diffable in git). |
| **O-DA-6** | Per-cell variation: should the registry expose a *list* of floor variants and pick one randomly per cell (seeded by cell coord) for visual variety, or always-the-same? | **Random from list, seeded by cell coord** for variety. Important for player-perceptible spatial memory ("I came from the room with the diamond floor"). |
| **O-DA-7** | Should decorative arches (§5.2.3) be opt-in per cell (stocking tag) or automatically applied at every door cell? | **Opt-in.** Automatic placement clutters corridors; ornate doors should be a stocking choice. |
| **O-DA-8** | ~~What does a "destroyed" door look like? Quaternius doesn't have a broken-door mesh.~~ **Resolved (Jedidiah, 2026-06-01):** Render nothing — just remove the door mesh. The cell remains passable per `door_state == "destroyed"` and reads visually as an open passage. | (Resolved — render no mesh.) |
| **O-DA-9** | Should the conversion script (`_convert.py`) live in the repo, or is the converted `.glb` output the only artifact? | **Both.** Script lives in `assets/dungeon_kit/_convert.py` so future re-runs are reproducible; the `.glb` output is also versioned (binary, but small). |
| **O-DA-10** | Polygon budget: total Quaternius dungeon kit, with all variants instantiated naively, is on the order of 50k–100k polys per cell-dense scene. Is that acceptable for the platform target (desktop, Godot 4)? | **Almost certainly yes** on desktop. Modern GPUs eat this for breakfast. Profile after first import to confirm. Camera occlusion-fade already culls non-focused levels. |
| **O-DA-11** | The voxel `WALL_HEIGHT = 1.4` constant is a *visual* exaggeration over the natural 1.0 cube. Quaternius walls are 1.0 tall (post-scale). Should we scale Quaternius walls by 1.4× Y to match the current renderer's "tall walls" look, or accept Quaternius's natural proportions? | **Accept natural proportions (1.0 tall).** A 5-ft cell with 5-ft tall walls is visually fine. The current 1.4× is a hack to make code-generated boxes look more wall-like; the actual Quaternius mesh has details (top trim, base trim) that already read as a real wall at 1.0. |
| **O-DA-12** | Lighting: Quaternius assets use `SHADING_MODE_UNSHADED` materials by default (no normals, flat color). The current renderer also uses unshaded. Should we keep unshaded (preserves the painterly look) or enable shading + dynamic light from `DungeonLightManager`? | **Keep unshaded for v1.** Adds painterly readability and removes the need for per-cell light baking. Dynamic light is signaled via fog tinting today; revisit if we add per-cell torch-glow falloff. |

---

## 7. Implementation plan summary (for Claude Code)

When the design is approved, the implementation work — **not part of this document** — looks like:

1. **Conversion pass.** Author `assets/dungeon_kit/_convert.py`. Run it once to produce `assets/dungeon_kit/**/*.glb`. Commit the output. Add `_SOURCE.md`.
2. **Asset registry.** Author `engine/shared_types/dungeon_asset_registry.gd` and `data/dungeon_assets.tres`. Populate the dictionaries.
3. **Edge resolver.** Author `engine/subsystems/exploration/wall_edge_resolver.gd` that returns `Array[Dictionary]{air_cell, edge_dir, neighbor_solid_cell}` for a given level.
4. **Asset-based builder.** Author `scenes/maps/dungeon_asset_builder.gd` with static methods `build_floors(map, level, registry)`, `build_walls(map, level, registry, edges)`, `build_doors(map, level, registry)`, `build_features(map, level, registry)` that parallel the existing `TacticalGrid3D.build_*_voxel` static methods but instantiate `.glb` scenes via the registry.
5. **Renderer toggle.** Add a project setting `acks/rendering/dungeon_asset_mode` enum {`code_generated`, `asset_kit`}. In `dungeon_map_renderer_3d.gd::_on_map_loaded`, branch on this setting. Default `asset_kit` once the new path is verified.
6. **Camera-occlusion fade adaptation.** Re-key `_wall_meshes` from `Dictionary[Vector2i → MeshInstance3D]` to `Dictionary[Vector3i → Array[Node3D]]` (per §5.2.2). Update `_fade_walls_between_camera_and_*` methods.
7. **Tests.** Add `tests/exploration/test_wall_edge_resolver.gd` verifying edge enumeration on a sample map. Add `tests/maps/test_dungeon_asset_builder.gd` verifying the right asset instantiates for each cell type.
8. **Headless verification.** The full game must run with the asset-kit mode under `/c/godot/Godot_v4.6.1-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn`.

Phase tagging (per `gdd-dungeon-map-ui.md` §13.3): this is a **Phase H+ (visual polish)** feature, after the gameplay subsystems land. It can ship behind a feature flag at any point — the gameplay does not depend on it.

---

## 8. Other notes and interesting findings

- **Quaternius's `.blend` files have un-applied scales.** `Floor_Standard.blend` has `scale=(1, 1, 0.06)` on the object — this is a Quaternius authoring artifact. The glTF exporter bakes scale into vertex positions, so the converted `.glb` is clean. If we ever bypass glTF and use `.blend` directly, we'd need to apply transforms first. Document this in `_convert.py`.
- **Shared `Texture.png` is tiny.** Inspection showed the atlas image as a `(0, 0)`-pixel placeholder in the metadata (size 0 because Blender hadn't loaded it into memory). The actual disk file is on the order of 256×256 or smaller — a Quaternius signature palette ramp. Cheap to ship.
- **`Wall_ArchRound_Overgrown_Broken.blend` exists.** Combinatorial variants (overgrown + broken + arch + round) ship as separate files. We don't need to expose all of them in the registry initially; pick a representative subset and add more as stocking calls for them.
- **`Curve_1.blend` and `Curve_1_Overgrown.blend`.** These are curved path pieces (S-curves of floor). Quaternius dungeons sometimes have non-grid-aligned curving corridors. Our voxel grid does not support these; ignore for v1.
- **`Floor_Tree.blend`.** A floor tile with a small tree growing through it. Useful for "abandoned dungeon with vegetation invading" stocking — drop into overgrowth subfolder.
- **Statue assets (`Statue_Fox`, `Statue_Stag`) are 2 cells tall.** They visually extend above the wall-cap. With `ELEVATION_SCALE = 0.5`, a 4.6-tall statue post-scale is 2.3 world units tall — overlapping the level above. On multi-level maps this needs occlusion handling; on single-level maps it just looks dramatic.
- **License (Quaternius CC0).** All Quaternius packs are released under CC0 — no attribution required, can be modified and redistributed freely. We should still credit Quaternius in the repo's README and in any in-game credits screen as a matter of professional courtesy.
- **The wilderness pack pairs with a `Quaternius Wilderness Textures` folder** that wasn't inspected here. If the wilderness pack textures are not embedded in the `.blend` files (like the dungeon pack's `Texture.png` is), the conversion script for wilderness will need to handle external textures separately. Defer.
- **The existing renderer's `DOOR_TEXTURE_PATH = "res://assets/walls/wood_oak_weathered.png"`** suggests that even before this plan, there was an intent to use bespoke door textures. Those `.png` files will become unused once Quaternius doors land — flag for cleanup, don't delete in this pass.
- **`Wall_Double_Hole.blend` has rotation_euler X = −90°** in the source. This is a Quaternius authoring oddity; glTF export with `export_apply=True` should bake the rotation. Verify post-conversion.
- **`Doors_*_Covered.blend` (curtain variant).** Per `gdd-dungeon-ui-md` §4.2.1, curtains are bashability-class "free passage" doors — they have no door state, just decorative drape. Use these for cell.door_material == "curtain_cloth"/"curtain_leather"; the player walks through without an Open Door action.

---

## 9. Citations

- **ACKS dungeon mapping scale:** `acore_adventures_and_encounters.xml` — *"Dungeons are typically mapped on graph paper with 1/4 inch square grids at a scale of 10 feet per square."* / *"On large play maps, one square commonly equals 5 feet."* The arbiter has chosen the 5-ft-per-square convention (the "large play map" tactical scale), consistent with the 5' cube voxel grid in `gdd-voxel-tactical-architecture.md`.
- **Door materials and bashability:** `gdd-dungeon-map-ui.md` §4.2.1; `gdd-dungeon-layout.md` §11 (`DoorData`).
- **Cell solidity and adjacency:** `gdd-voxel-tactical-architecture.md` §6.2, §16.9.
- **Existing renderer constants:** `scenes/maps/tactical_grid_3d.gd` lines 22–38.
- **Existing builder functions:** `scenes/maps/tactical_grid_3d.gd::build_floor_multimesh_voxel`, `::build_walls_voxel`, `::build_walls_voxel_individual`, `::build_doors_voxel`, `::build_features_voxel`.
- **Asset measurements:** Direct Blender MCP inspection of the Quaternius pack at `C:\Users\jttau\OneDrive\Pictures\Terrain\Quaternius Dungeon\Blends\` (samples listed in §1.1).

---

## 10. Revision history

- **v1, 2026-06-01 — Initial investigation and plan.** Inventoried Quaternius dungeon (91 files) and wilderness (152 files) packs; measured representative samples in Blender; inspected the existing voxel renderer in `tactical_grid_3d.gd` and `dungeon_map_renderer_3d.gd`; verified scale assumptions against `acore_adventures_and_encounters.xml`; identified the cell-vs-edge conceptual mismatch and proposed Strategy A (edge-resolved rendering); drafted asset organization, naming, registry resource shape, asset-to-feature mapping with placement geometry, and 12 open design questions for Jedidiah's review.
- **v1.1, 2026-06-01 — O-DA-8 resolved.** Destroyed doors render nothing (no debris prop). Jedidiah confirmed the remaining 11 default proposals (O-DA-1 through O-DA-7, O-DA-9 through O-DA-12) as approved; they remain in the table as the design of record.
- **v1.2, 2026-06-13 — IMPLEMENTED (Increments 1–3 + material finale).** All four §7 steps built and verified via Godot MCP screenshots on `data/test_dungeon.json` (behind project setting `acks/rendering/dungeon_asset_mode`, default `code_generated`). New code: `assets/dungeon_kit/_convert.py` (91 `.glb`), `DungeonAssetRegistry`, `WallEdgeResolver` (+8 tests), `DungeonAssetBuilder`, renderer branch + asset-wall fade in `dungeon_map_renderer_3d.gd`. **Corrections to this plan, found against the live code (the code is authoritative):**
  - **§2.1 / O-DA-1 elevation:** the live builders use `VoxelGrid.cell_to_world` where **Y = level × 1.0** (CELL_SIZE), not the `ELEVATION_SCALE = 0.5` this plan assumed (that local `TacticalGrid3D` constant is unused legacy). So at 0.5 kit-scale a wall is exactly 1.0 tall = one level — the squash tension in O-DA-1 does not arise.
  - **§5 floor sizing:** the renderer is a **diamond (45°-rotated) grid** — cells are 0.707 apart. Floors are scaled `kit_scale/√2` (~0.354) **and rotated 45°** to tessellate as diamonds; walls use uniform `kit_scale` and sit at edge midpoints with ±45° rotation (1.0 length slightly overhangs the 0.707 edge, which fills corners per §3.1). This plan's "0.5 → 1.0 cell" floor sizing assumed an axis-aligned grid and is superseded.
  - **§5.3 doors:** `VoxelCell` carries **`door_type`** (arch/unlocked/locked/trapped/secret/portcullis), **not** the `door_material` this plan's table assumed — doors are mapped by `door_type`. Portcullis → `window_bars` placeholder; detected secret → `wall_hole`; undetected secret → no mesh.
  - **O-DA-12 SUPERSEDED:** "keep unshaded for v1" is replaced by applying **`cel_environment.gdshader`** (the project's flat-matte environment cel shader, `gdd-art-direction.md` §7) per-surface, preserving each flat Quaternius color via `albedo_tint`. Jedidiah considered cel bands + dark outline (the `cel_figure` character treatment) and chose the GDD-aligned flat matte so figures still pop.
  - **No texture atlas:** Quaternius dungeon materials are flat per-material `baseColorFactor` (the `Texture.png` in §1/§8 is unused by the node trees). Approach-1 embedding is moot for the core kit; only the tree/dead-tree overgrowth meshes carry external bark `.jpg`s.
  - **Asset overlays:** fog of war, grid lines, door/lever labels, and exit markers are kit-agnostic and reused verbatim from `TacticalGrid3D`'s static builders inside the asset `build_level_group`.
  - **Deferred:** stair ▲/▼ arrows in asset mode (§5.4 wants them kept); ladder/lever/fountain stay code-generated (O-DA-3); `data/dungeon_assets.tres` (using code-default registry for now); in-game verification of fade + real-lighting cel look.
