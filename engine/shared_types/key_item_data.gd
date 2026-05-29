class_name KeyItemData
extends RefCounted

## A key for a locked iron/stone door, created by key_lever_placer
## (gdd-dungeon-generator-v1.md §10). Portcullis LEVERS are recorded on the
## DoorData (wired_lever_position), NOT as KeyItems — this type is keys only.
##
## Mirrors the key_items table (DB is ground truth). Generation-time floor/room
## indices are mapped to TEXT ids by the repository at persist time.

const PLACED_MONSTER_INV := "monster_group_inventory"
const PLACED_TREASURE_HOARD := "treasure_hoard"
const PLACED_LOOSE := "loose_in_room"

const VALID_PLACEMENTS: Array[String] = [
	PLACED_MONSTER_INV,
	PLACED_TREASURE_HOARD,
	PLACED_LOOSE,
]

var id: String = ""
var opens_door_floor_index: int = -1               ## floor of the locked door
var opens_door_position: Vector2i = Vector2i(-1, -1)
var placed_in: String = PLACED_LOOSE
var placed_in_room_id: int = -1                    ## DungeonRoomData.id of the room holding the key
var placed_on_floor_index: int = -1                ## floor holding the key
