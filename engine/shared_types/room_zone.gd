class_name RoomZone
extends RefCounted

## A maximal contiguous walkable region of a single room on a single band —
## the stocking unit of the contiguous 3D dungeon model.
##
## Per `gdd-dungeon-contiguous-3d.md` §5.3 / §9.2 (schema APPROVED 2026-07-06).
##
## Every room has at least one zone (zone_index 0, its main floor). Only
## multi-story rooms have more: a grand atrium's balcony/gallery zones sit on
## the upper band with a distinct zone_index and stock at THEIR band's tier.
## Corridors have no zones; circulation rooms (stairwells) have zones for
## identity/fog purposes but are excluded from stocking.
##
## DORMANT in DG-C3D.A: the type and its persistence exist, but nothing
## constructs zones until the vertical composer lands (DG-C3D.D) and nothing
## stocks them until cutover (DG-C3D.F).


# ---------------------------------------------------------------------------
# Zone type vocabulary (§9.2)
# ---------------------------------------------------------------------------

const ZONE_TYPE_MAIN := "main"          ## the room's ground-floor zone (zone_index 0)
const ZONE_TYPE_BALCONY := "balcony"    ## upper-band perimeter ring of an atrium
const ZONE_TYPE_GALLERY := "gallery"    ## disconnected upper-band walkway segment
const ZONE_TYPE_LEDGE := "ledge"        ## natural-cavern irregular upper ledge
const ZONE_TYPE_LANDING := "landing"    ## walkable landing inside a circulation room

const VALID_ZONE_TYPES: Array[String] = [
	ZONE_TYPE_MAIN, ZONE_TYPE_BALCONY, ZONE_TYPE_GALLERY,
	ZONE_TYPE_LEDGE, ZONE_TYPE_LANDING,
]


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

## Owning room's id (dungeon-unique in the composed volume). An atrium and
## its balconies share one room_id — balconies are zones, not rooms.
var room_id: int = -1

## Zone ordinal within the room. 0 = the main floor zone; upper-band zones
## take 1..n. Stamped per-cell as VoxelCell.zone_index at composition time.
var zone_index: int = 0

## The zone's ACKS dungeon level (floor_index). Drives the tier for every
## stocking roll — a balcony over a band-2 atrium floor stocks at ITS band's
## tier, not the atrium floor's.
var band: int = 0

## See ZONE_TYPE_* constants.
var zone_type: String = ZONE_TYPE_MAIN

## Footprint cells at walk_level(band) + level_offset. Vector2i(col, row).
var cells: Array[Vector2i] = []

## RESERVED free-form hook (§5.4) — voxel levels relative to the band walk
## level. Always 0 in this version; validation asserts it.
var level_offset: int = 0


# ---------------------------------------------------------------------------
# Stocking results (relocate from DungeonRoomData at DG-C3D.F)
# ---------------------------------------------------------------------------

## "empty" | "monster" | "monster_lair" | "trap_placeholder" | "unique_placeholder"
## (same vocabulary as DungeonRoomData.contents_kind; CHECK-constrained in the
## room_zones table).
var contents_kind: String = "empty"

## FK (TEXT id) to a monster_groups row once stocked. "" = none.
var monster_group_id: String = ""

## FK (TEXT id) to a treasure_hoards row once stocked. "" = none.
var treasure_hoard_id: String = ""

## LLM-facing current-use string for this zone. The owning room's
## current_purpose remains as the rollup composed from its zones.
var current_purpose: String = ""


# ---------------------------------------------------------------------------
# Convenience
# ---------------------------------------------------------------------------

## Number of footprint cells (== `cells.size()`).
func cell_count() -> int:
	return cells.size()


## True if this zone contains the given grid cell.
func contains_cell(p: Vector2i) -> bool:
	return cells.has(p)


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

## Creates a RoomZone from a dictionary (JSON-loaded data or DB row shape).
## `cells` entries are [col, row] pairs (JSON-safe).
static func from_dict(data: Dictionary) -> RoomZone:
	var zone := RoomZone.new()
	zone.room_id = int(data.get("room_id", -1))
	zone.zone_index = int(data.get("zone_index", 0))
	zone.band = int(data.get("band", 0))
	zone.zone_type = str(data.get("zone_type", ZONE_TYPE_MAIN))
	var cells_raw: Variant = data.get("cells", [])
	if cells_raw is Array:
		for entry in cells_raw:
			if entry is Array and (entry as Array).size() >= 2:
				zone.cells.append(Vector2i(int(entry[0]), int(entry[1])))
	zone.level_offset = int(data.get("level_offset", 0))
	zone.contents_kind = str(data.get("contents_kind", "empty"))
	zone.monster_group_id = str(data.get("monster_group_id", ""))
	zone.treasure_hoard_id = str(data.get("treasure_hoard_id", ""))
	zone.current_purpose = str(data.get("current_purpose", ""))
	return zone


## Serializes this zone to a dictionary. `cells` become [col, row] pairs so
## the result survives JSON.stringify/parse_string round-trips.
func to_dict() -> Dictionary:
	var cells_out: Array = []
	for c in cells:
		cells_out.append([c.x, c.y])
	return {
		"room_id": room_id,
		"zone_index": zone_index,
		"band": band,
		"zone_type": zone_type,
		"cells": cells_out,
		"level_offset": level_offset,
		"contents_kind": contents_kind,
		"monster_group_id": monster_group_id,
		"treasure_hoard_id": treasure_hoard_id,
		"current_purpose": current_purpose,
	}
