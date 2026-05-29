class_name DungeonLayout
extends RefCounted

## Output of the dungeon layout generator — one floor's complete spatial layout.
##
## Per `gdd-dungeon-layout.md` §11 (BASELINE schema). DG-V1.B-base produces this
## shape; DG-V1.B-edits will add the §8.3 / §9.3 / §11-overlay additions;
## DG-V1.D will further extend with stocking results (monster_group_id,
## treasure_hoard_id, contents_kind, floor_tier, etc. per V1 GDD §4.2).
##
## A DungeonLayout represents ONE floor. Multi-floor dungeons are an array of
## these, owned by the V1 generator's orchestrator (DG-V1.D).


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

## Stable identifier across save/load. Caller supplies; if empty, the layout
## generator leaves it empty (the V1 orchestrator assigns ids per its
## persistence pass in DG-V1.C/D).
var dungeon_id: String = ""

## From the ACKS d20 dungeon flavor table per layout GDD §2. V1 only supports
## "wizards_dungeon" (per V1 GDD §7); other strings fall back to it.
var dungeon_type: String = "wizards_dungeon"

## "lair" | "small" | "medium" | "large" per layout GDD §3.
var dungeon_size: String = "medium"

## "subterranean" | "above_ground" per layout GDD §8.2. Wizard's Dungeon is
## subterranean. Controls multi-level spatial coherence rules.
var structure_type: String = "subterranean"

## Floor index within the dungeon. 1-indexed. DG-V1.B-base may emit this as 1
## for single-floor generation; the V1 orchestrator (DG-V1.D) overrides for
## multi-floor dungeons.
var level_number: int = 1

## The derived ACKS dungeon level (1-6) for this floor, per V1 GDD §4.2 + §6.
## Set by the generator from the request's floor_tier. Drives the §8.3 door
## material rule and (later) per-floor stocking difficulty.
var floor_tier: int = 1

## True if this is the dungeon's entrance floor (its up-stair connects to the
## overworld). Per V1 GDD §4.2. Set by the generator from the request.
var is_entrance_floor: bool = false


# ---------------------------------------------------------------------------
# Grid
# ---------------------------------------------------------------------------

## Grid width in cells. Each cell is 5'×5'. Per layout GDD §4.3 sizing table:
## lair=21, small=31, medium=51, large=79.
var grid_width: int = 0

## Grid height in cells. Same as grid_width for V1 (square grids).
var grid_height: int = 0

## Indexed [x][y]. cells[x][y] is the DungeonCellData at column x, row y.
## Always exactly grid_width × grid_height.
var cells: Array[Array] = []


# ---------------------------------------------------------------------------
# Detected structure
# ---------------------------------------------------------------------------

## All rooms found by flood-fill room detection (§10.2). Empty before
## detection runs; populated by DungeonRoomDetector during generation.
var rooms: Array[DungeonRoomData] = []

## All doors placed during generation (§8.1). Each DoorData also appears
## in its associated DungeonRoomData.doors list (by reference).
var doors: Array[DungeonDoorData] = []

## All stairs placed during generation (§9.1).
var stairs: Array[DungeonStairData] = []

## Monster groups stocked onto this floor (DG-V1.D §11). Each stands alone — no
## coalescing (§11.7). Persisted to monster_groups; room linkage via room_id.
var monster_groups: Array[MonsterGroupData] = []

## Treasure hoards materialized on this floor (DG-V1.D §13). Persisted to
## treasure_hoards; room linkage via room_id.
var treasure_hoards: Array[TreasureHoardData] = []


# ---------------------------------------------------------------------------
# Entrance
# ---------------------------------------------------------------------------

## The grid cell that connects to the overworld (the entrance to the dungeon).
## Set on the entrance floor only — the V1 orchestrator picks which floor is
## the entrance per its tier-derivation request.
var entrance: Vector2i = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Theme + reproducibility
# ---------------------------------------------------------------------------

## The DungeonTheme used for this layout. Theme parameters are not persisted
## with the dungeon — they live in the theme catalog — so save/load needs
## only dungeon_type to recover. The runtime in-memory layout carries the
## theme by reference for convenience.
var theme: DungeonTheme = null

## Seed used for generation. Required for reproducibility — re-running the
## generator with the same DungeonLayoutRequest and the same seed must
## produce a byte-identical layout.
var generation_seed: int = 0


# ---------------------------------------------------------------------------
# Convenience
# ---------------------------------------------------------------------------

## Fetch the cell at (x, y), or null if out of bounds.
func get_cell(x: int, y: int) -> DungeonCellData:
	if x < 0 or y < 0 or x >= grid_width or y >= grid_height:
		return null
	return cells[x][y]


## Same as get_cell but takes a Vector2i.
func get_cell_at(pos: Vector2i) -> DungeonCellData:
	return get_cell(pos.x, pos.y)


## Lookup a room by id. Returns null if not found.
func find_room(room_id: int) -> DungeonRoomData:
	for r in rooms:
		if r.id == room_id:
			return r
	return null


## Lookup a door by position. Returns null if no door at that cell.
func find_door_at(pos: Vector2i) -> DungeonDoorData:
	for d in doors:
		if d.position == pos:
			return d
	return null
