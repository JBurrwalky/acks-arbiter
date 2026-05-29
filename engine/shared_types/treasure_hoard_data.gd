class_name TreasureHoardData
extends RefCounted

## A materialized treasure hoard (gdd-dungeon-generator-v1.md §13, §4.2).
## Mirrors the treasure_hoards table (DB is ground truth).

const SOURCE_LAIR := "lair"
const SOURCE_UNPROTECTED_EMPTY := "unprotected_empty"
const SOURCE_UNPROTECTED_TRAP := "unprotected_trap_placeholder"
const SOURCE_UNPROTECTED_UNIQUE := "unprotected_unique_placeholder"

const VALID_SOURCES: Array[String] = [
	SOURCE_LAIR,
	SOURCE_UNPROTECTED_EMPTY,
	SOURCE_UNPROTECTED_TRAP,
	SOURCE_UNPROTECTED_UNIQUE,
]

var id: String = ""
var floor_index: int = -1                  ## 1-based floor index during generation
var room_id: int = -1                      ## DungeonRoomData.id within the floor
var source: String = SOURCE_LAIR
var treasure_type_letter: String = ""      ## "" == null (consumed for unprotected_* hoards)
var copper: int = 0
var silver: int = 0
var electrum: int = 0
var gold: int = 0
var platinum: int = 0
var gems: Array = []                       ## [{value_gp:int, gem_class:String}]
var jewelry: Array = []                    ## [{value_gp:int, jewelry_class:String}]
var magic_items: Array = []                ## [{category, specific_item_id, is_placeholder:bool, notes}]
var total_gp_value: int = 0                ## computed after rolling; cached for XP-balance reporting
var is_hidden: bool = false                ## true for unprotected_* hoards (RAW: hidden by default)
