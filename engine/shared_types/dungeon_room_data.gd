class_name DungeonRoomData
extends RefCounted

## A single room produced by the dungeon layout generator.
##
## Per `gdd-dungeon-layout.md` §11 (BASELINE schema).
##
## A room is a flood-filled connected region of passable, in-bounds, non-corridor
## cells (bounded by walls and door cells). The detector emits one
## DungeonRoomData per detected region with its bounds, cell list, and
## perimeter doors. The layout generator assigns `original_purpose` from the
## theme's purpose table (§6.3); `current_purpose` stays empty in DG-V1.B-base
## (the V1 stocking step in DG-V1.D fills it).


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Stable integer id, unique within a single floor. Assigned by the room
## detector in flood-fill order starting at 0.
var id: int = -1

## Grid coordinates of all cells that belong to this room.
## Each entry is Vector2i(x, y).
var cells: Array[Vector2i] = []

## Axis-aligned bounding box of the room's cells in grid coordinates.
var bounds: Rect2i = Rect2i()

## Area in square feet. Each cell is 5'×5' = 25 sqft.
var area_sqft: int = 0

## Center cell. For rectangular rooms this is the bounds midpoint; for
## irregular shapes (V2 cellular-automata caverns, etc.) it is the centroid.
var center: Vector2i = Vector2i.ZERO

## Doors on this room's perimeter. Each DoorData has `connects` referencing
## this room's id. The same DoorData object also appears in the floor-level
## `DungeonLayout.doors` list — Array is by-reference so changes propagate.
var doors: Array[DungeonDoorData] = []

## What the room was built for, before its current inhabitants moved in.
## Assigned by the layout generator from the theme's §6.3 purpose table.
## E.g. "laboratory", "summoning chamber", "specimen storage" for a
## Wizard's Dungeon room.
var original_purpose: String = ""

## What the room is currently used for. Empty after layout generation;
## populated by the V1 stocking step (DG-V1.D) per its §11.6 table.
var current_purpose: String = ""

## Stocking classification per V1 GDD §4.2. "empty" after layout generation;
## the DG-V1.D stocking step sets "monster" / "monster_lair" /
## "trap_placeholder" / "unique_placeholder". CHECK-constrained in the
## dungeon_rooms table.
var contents_kind: String = "empty"

## FK (TEXT id) to a monster_groups row once stocked (DG-V1.D). "" = none.
var monster_group_id: String = ""

## FK (TEXT id) to a treasure_hoards row once stocked (DG-V1.D). "" = none.
var treasure_hoard_id: String = ""


# ---------------------------------------------------------------------------
# Contiguous 3D volume fields (DG-C3D.A — gdd-dungeon-contiguous-3d.md §9.1)
#
# DORMANT until the vertical composer (DG-C3D.D) populates them; defaults hold
# everywhere until then. The stocking fields above relocate to RoomZone at
# cutover (DG-C3D.F); dual presence during B-E is deliberate — nothing reads
# zones yet.
# ---------------------------------------------------------------------------

## Room kind vocabulary. Circulation rooms (switchback/spiral stairwells) get
## walls, doors, and fog identity but are excluded from the stocking loop.
const KIND_CHAMBER := "chamber"
const KIND_CIRCULATION := "circulation"

const VALID_KINDS: Array[String] = [KIND_CHAMBER, KIND_CIRCULATION]

## The room's ACKS dungeon level (floor_index). A band IS a floor for every
## tier, treasure, and wandering-monster purpose.
var band: int = 0

## "chamber" (default) or "circulation" (stairwell rooms). See KIND_*.
var kind: String = KIND_CHAMBER

## Room height in voxel levels: 2 = standard 10' room; 4 = two-band atrium.
var height_levels: int = 2

## RESERVED free-form hook (gdd-dungeon-contiguous-3d.md §5.4) — voxel levels
## relative to the band walk level. Always 0 in this version; validation
## asserts it.
var level_offset: int = 0

## The room's stocking zones (zone_index 0 = main floor; upper-band
## balcony/gallery zones follow). Empty until DG-C3D.D composes the volume.
var zones: Array[RoomZone] = []


# ---------------------------------------------------------------------------
# Convenience
# ---------------------------------------------------------------------------

## Number of grid cells this room occupies (== `cells.size()`).
func cell_count() -> int:
	return cells.size()


## True if this room contains the given grid cell.
func contains_cell(p: Vector2i) -> bool:
	return cells.has(p)
