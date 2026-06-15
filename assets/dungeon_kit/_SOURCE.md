# Dungeon Kit — Asset Provenance

**Source pack:** Quaternius — "Ultimate Modular Dungeon Pack" (dungeon set).
**License:** CC0 1.0 Universal (public domain dedication). No attribution
required; modification and redistribution permitted. We credit Quaternius in
the project README / in-game credits as professional courtesy (CC0 does not
require it).
**Upstream:** https://quaternius.com/ (free CC0 game assets).

## What's here

90 `.glb` meshes converted from the 91 source `.blend` files (one `.blend`
maps to one `.glb`; the count differs only if a source file held no mesh).
Organized into category subfolders — see `generation/gdd-dungeon-asset-integration-plan.md` §4.1.

| Subfolder | Contents |
|---|---|
| `floor/` | floor tiles, holes, half-tiles, tree-through-floor |
| `wall/` | straight/broken/half/overgrown walls, arch-walls, windows |
| `door/` | two-leaf round/gothic doors, curtain ("covered") variants, trapdoor |
| `stair/` | stair pieces |
| `column/` | columns, standalone arches |
| `structure/` | supports, bridge section, rails |
| `trap/` | bear traps (open/closed) |
| `container/` | chests, barrel, crate, cart, bookcases, pots |
| `prop/` | torch, candles, skull, debris, flags, statues |
| `overgrowth/` | bushes, grass, trees, dead trees, curved path pieces |

## Conversion

- **Source folder:** `C:\Users\jttau\OneDrive\Pictures\Terrain\Quaternius Dungeon\Blends`
  (upstream art; NOT tracked in this repo — only the converted `.glb` output is).
- **Converted:** 2026-06-13, Blender 5.1.0, via `_convert.py` (in this folder).
- **Re-run:** `blender --background --python assets/dungeon_kit/_convert.py`
  (the script auto-detects its own folder as the output root). Pass exact source
  basenames after `--` to convert a subset.

### Conversion recipe (see `_convert.py`)

1. Open each `.blend`; select all MESH objects; make data single-user.
2. Apply **rotation + scale** into vertex data (bakes away Quaternius
   authoring artifacts — e.g. Floor_Standard's un-applied `(1,1,0.06)` object
   scale, Wall_Double_Hole's `-90°` X rotation). **Location is preserved**, so
   two-leaf door halves keep their `±1.0` X hinge origins as node offsets.
3. Export self-contained `.glb` (Z-up → Y-up), modifiers applied, textures
   embedded (Approach 1 / O-DA-4), no cameras/lights/animations.

### Notes for future maintainers

- **No texture atlas.** Quaternius dungeon materials are **flat per-material
  base colors** (`baseColorFactor`: `Main`, `Highlights`, `Wood`, `DarkWood`,
  `Metal`, `Metal_Light`, …), not image-textured. The `Texture.png` referenced
  in the source `.blend`s is unused by the material node trees. This matches the
  unshaded/flat-color rendering decision (O-DA-12). There is nothing to migrate.
- **Native scale preserved.** The `.glb`s are at Quaternius's native 2.0-unit
  cell scale. The arbiter 0.5 "kit scale" (2.0-unit cell → 1.0-unit arbiter
  cell) is applied at **instantiation** time in Godot (registry/builder), not
  baked here — so it stays tunable during visual placement without re-converting.
