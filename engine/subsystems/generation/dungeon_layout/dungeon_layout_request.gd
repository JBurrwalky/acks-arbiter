class_name DungeonLayoutRequest
extends RefCounted

## Input to DungeonLayoutGenerator.generate(). One per floor.
##
## Per `gdd-dungeon-layout.md` §12.1 (Who Calls This Generator). The DG-V1.D
## multi-floor orchestrator (V1 GDD §5) builds one request per floor it wants
## generated. For DG-V1.B-base, this is the simple per-floor input shape;
## §9.3 stair anchors are added in DG-V1.B-edits.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SIZE_LAIR := "lair"
const SIZE_SMALL := "small"
const SIZE_MEDIUM := "medium"
const SIZE_LARGE := "large"

const VALID_SIZES: Array[String] = [SIZE_LAIR, SIZE_SMALL, SIZE_MEDIUM, SIZE_LARGE]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## ACKS dungeon type per layout GDD §2 d20 table (e.g. "wizards_dungeon").
## Unknown values fall back to wizards_dungeon per V1 GDD §7.1.
var dungeon_type: String = "wizards_dungeon"

## "lair" | "small" | "medium" | "large" — see VALID_SIZES.
var dungeon_size: String = SIZE_MEDIUM

## Floor index within the parent dungeon. 1-indexed.
var level_number: int = 1

## RNG seed for reproducibility. Two generations with the same request and
## seed must produce a byte-identical DungeonLayout.
var seed: int = 0

## How many up-stairs to place on this floor. Default 1 (the surface
## connection on the entrance floor, or the up-to-prior-floor on subsequent
## floors). DG-V1.D will set this per-floor.
var stairs_up: int = 1

## How many down-stairs to place. Default 1 (the down-to-next-floor connection).
## DG-V1.D will set this per-floor (last floor of a dungeon has stairs_down = 0).
var stairs_down: int = 1

## True if this is the dungeon's entrance floor — the up-stair becomes the
## entrance to the overworld in that case. DG-V1.D sets this per-request.
var is_entrance_floor: bool = false

## Floor tier per V1 GDD §6 — drives the §8.3 door material rule (portcullis-
## override + metal-vs-wood chances scale at 5% per tier). Range 1-6. DG-V1.D's
## multi-floor orchestrator computes this from the dungeon's entrance tier and
## per-floor offset. The per-floor generator (DG-V1.B-base + B-edits) just
## consumes it for the §8.3 pass. Defaults to 1 (the easiest tier).
var floor_tier: int = 1

## Pre-placed reservation rooms from the whole-dungeon vertical plan
## (DG-C3D.C; contiguous GDD §8 stage B1). Each entry is a Dictionary in the
## `VerticalPlan.reservations_for_band()` shape:
##   rect: Rect2i                — exact footprint (already collision-checked
##                                 within the interior margin by the plan)
##   kind: String                — "circulation" (stairwell room, MST node) |
##                                 "atrium_base" (large room, MST node) |
##                                 "atrium_upper" (blocked region + door-
##                                 eligible balcony ring stub; collision +
##                                 loop-edges only, NOT an MST node, not a
##                                 room in the layout output)
##   ref: RefCounted             — back-reference to the ConnectorPlan /
##                                 AtriumPlan (opaque to the layout layer)
##   is_sole_connector: bool     — true when the circulation room is the only
##                                 connector for its band pair; doors on such
##                                 rooms skip the secret overlay (§10.3)
## Empty (the default) leaves the layout pipeline byte-identical to pre-C
## behavior — the RNG-identity gate the golden-fingerprint test enforces.
var reserved_rooms: Array = []
