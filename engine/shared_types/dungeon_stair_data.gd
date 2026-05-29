class_name DungeonStairData
extends RefCounted

## A single stair produced by the dungeon layout generator.
##
## Per `gdd-dungeon-layout.md` §11 (BASELINE schema).
##
## Stairs occupy a single cell. `direction` is "up" or "down". `connects_to_level`
## is set by the multi-floor orchestrator (DG-V1.D); the per-floor generator
## (DG-V1.B-base) just records position + direction. The entrance stair (the
## one connecting to the overworld) is identified by `is_entrance_stair = true`
## on the entrance floor only.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DIRECTION_UP := "up"
const DIRECTION_DOWN := "down"

const VALID_DIRECTIONS: Array[String] = [DIRECTION_UP, DIRECTION_DOWN]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Grid cell of the stair. Vector2i(x, y).
var position: Vector2i = Vector2i.ZERO

## "up" or "down". See DIRECTION_* constants.
var direction: String = DIRECTION_DOWN

## Set by the multi-floor pipeline (DG-V1.D) once the dungeon's floor list is
## known. The per-floor generator (DG-V1.B-base) leaves this at -1.
var connects_to_level: int = -1

## True only for the dungeon's surface entrance stair on its entrance floor.
## False for floor-to-floor stairs and on all non-entrance floors. Set by the
## per-floor generator when it identifies which stair becomes the entrance.
var is_entrance_stair: bool = false
