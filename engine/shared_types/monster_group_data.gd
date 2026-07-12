class_name MonsterGroupData
extends RefCounted

## A single rolled monster group — a lair or a patrol (gdd-dungeon-generator-v1.md
## §4.2, §11). No coalescing in V1 (§11.7): each group stands alone, and its
## room_id IS its lair room when is_lair is true.
##
## Mirrors the monster_groups table (DB is ground truth). The generation-time
## fields floor_index / room_id are mapped to floor_id (TEXT) / room_id (TEXT)
## by the repository at persist time.

var id: String = ""
var floor_index: int = -1                  ## 1-based floor index during generation
var room_id: int = -1                      ## DungeonRoomData.id within the floor
## The stocking zone within the room (gdd-dungeon-contiguous-3d.md §9.2).
## DORMANT until the DG-C3D.F cutover stocks per zone: -1 = "no zone" (the
## pre-contiguous per-room model; the floor-stitched stocker never sets it).
var zone_index: int = -1
var monster_name: String = ""
var monster_xp_each: int = 0
var number_appearing: int = 0
var hd: String = ""
var associated_creatures: Array = []       ## [{name, number_appearing, xp_each}]
var is_lair: bool = false
var morale: int = 0
var alignment: String = ""
var treasure_type_letter: String = ""      ## catalog's listed treasure type(s); "" == none
                                            ## (NULL). May be a COMMA-JOINED COMBO ("I,M")
                                            ## — the stocker rolls one hoard per code.
var initial_inventory: Array = []          ## [{item_type, ...}] — e.g. a key placed by §10/step 7
## Generation-time ONLY (not a monster_groups column; the repository ignores it).
## The monster's catalog special_treasure spec, stamped by the encounter roller and
## consumed by the stocker, which rolls it into the lair hoard at generation time.
## Shape: {chance_pct:int, value_dice:String ("1d10x1000"), denomination:"gp", description:String}.
var special_treasure: Dictionary = {}
