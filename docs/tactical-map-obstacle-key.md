# Tactical Map Obstacle Key

Quick-reference key for the placeholder obstacle markers on generated wilderness
battle maps. Placeholders are **color/shape coded** until real assets land
(water and lava reuse the overland hexmap water look instead of a placeholder).

Source of truth: `engine/subsystems/generation/battlemap/battle_map_obstacle_catalog.gd`
(stamping + colors) and `scenes/maps/tactical_grid_3d.gd` `build_obstacles_voxel`
(shapes). Design: `generation/gdd-combat-map-generation.md` §5.3–§5.6.
If this table and the catalog disagree, the catalog is right — update this file.

## Legend

- **Move** — can a ground walker enter the cell? (Difficult-terrain movement
  costs are a future pathfinding-session feature; today cells are enterable
  or not.)
- **LOS** — does the cell block line of sight? "Low" obstacles block movement
  but can be seen and shot over; they grant **Cover** instead (0–4, applied
  via `VoxelLOS.get_cover_value`).

## Solid blockers (block movement AND sight)

| Obstacle | Placeholder | Color | Move | LOS | Cover | Appears in |
|---|---|---|---|---|---|---|
| Tree | trunk + ball canopy | Dark green canopy, brown trunk | ✗ | Blocks | 3 | Forests, jungle, grassland (lone), civilized fields |
| Dead tree | bare vertical trunk | Grey-brown | ✗ | Blocks | 2 | Swamps |
| Boulder | large rotated cube | Mid grey | ✗ | Blocks | 3 | Mountains, hills, desert, wild grassland |
| Rock outcrop | full-cell block mass | Dark grey-brown | ✗ | Blocks | 4 | Mountains, desert, badlands (multi-cell) |
| Hedgerow | tall thick wall segment | Very dark green | ✗ | Blocks | 3 | Civilized grassland field boundaries |
| Farmstead | solid building block(s) | Wood brown (wall texture) | ✗ | Blocks | — | Civilized grassland (3×4 to 5×6 footprint + fence ring) |

## Low solids (block movement, shoot OVER them)

| Obstacle | Placeholder | Color | Move | LOS | Cover | Appears in |
|---|---|---|---|---|---|---|
| Rock pile | cluster of 3 small cubes | Light grey | ✗ | Clear | 3 | Mountains, rocky hills, desert |
| Fence | thin low rail | Warm brown | ✗ | Clear | 1 | Civilized grassland |
| Low wall | thin low rail | Pale grey stone | ✗ | Clear | 2 | Civilized grassland |
| Ruined wall | thin low rail | Off-white masonry | ✗ | Clear | 3 | Anywhere (15% of maps, 1–2 fragments) |
| Fallen log | horizontal beam | Dark brown | ✗ | Clear | 2 | Forests |

## Soft cover (passable)

| Obstacle | Placeholder | Color | Move | LOS | Cover | Appears in |
|---|---|---|---|---|---|---|
| Brush | pair of small tufts | Mid green | ✓ | Clear | 1 | Forests, jungle, grassland |
| Reeds | pair of small tufts | Yellow-green | ✓ | Clear | 1 | Swamps |
| Scrub | pair of small tufts | Dry olive | ✓ | Clear | 1 | Deserts |

## Water and lava (hexmap water rendering, no placeholder shape)

| Feature | Rendering | Move | LOS | Notes |
|---|---|---|---|---|
| Shallow water | translucent blue plane, low in the cell | ✓ (wade) | Clear | Under one voxel (5') deep — any walker crosses without swimming. Streams, fords, banks, swamp pools. |
| Deep water | opaque blue plane, high in the cell | ✗ | Clear | One+ full voxels deep — swimming required (hook; larger creatures will gain wading leeway at the size build). River channels, lakes, ocean. |
| Lava flow | glowing orange emissive plane | ✗ | Clear | Volcanic mountains. Impassable on foot, fly-over only. Contact (falling in, or force-backed into the flow): save vs Poison & Death — fail = instant death, success = 2d6 fire damage and the victim staggers at the brink. |

## Terrain itself

- **Slopes:** adjacent cells differing by 1 level (5') are walkable grades —
  no climb check. 2+ levels is a bluff/cliff: climbing, flight, or go around.
- **Cliff faces / terrain columns:** soil-toned cube stacks; they block sight
  like any solid mass.
- **Bridges:** wood-textured deck cells spanning a river at bank level.
- **Split maps:** rarely (uncrossed river, chasm, cliff, or lava divider) the
  map is deliberately divided in two — a ranged-only stand-off unless someone
  can fly, swim, or climb. Party and enemies always spawn on opposite sides
  of the divider, never stranded incidentally.

## Surface painting (floor tints/textures)

| Surface | Where |
|---|---|
| Grass (green) | Clear/woods base ground |
| Dirt (brown) | Worn ground, forest floor, patches |
| Stone (grey) | Rocky ground, mountain tops |
| Sand (pale) | Desert, beaches |
| Mud (dark brown) | Swamp, jungle floor |
| Snow (white) | Tundra, glacial mountains |
| Gravel/scree (grey) | Slopes beside cliff faces, badlands |
| Basalt (near-black) | Volcanic ground, cooled lava crossings |
