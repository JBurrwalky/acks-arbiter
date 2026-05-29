class_name DungeonGeneratorResultV1
extends RefCounted

## Output of DungeonGeneratorV1.generate() (gdd-dungeon-generator-v1.md §4.1).
##
## NOTE: the build plan calls the floor array "layout"; we name it `floors` for
## clarity (it is one DungeonLayout per floor, index 0 == floor 1).

var success: bool = false
var dungeon_id: String = ""
var floors: Array[DungeonLayout] = []         ## one per floor, index 0 == floor 1
var key_items: Array[KeyItemData] = []        ## cross-floor; door<->key bindings (levers live on DoorData)
var errors: Array[String] = []                ## hard-failure messages (success == false)
var warnings: Array[String] = []              ## soft warnings ([BALANCE], tier clamp, door downgrades)
var acceptance_report: Dictionary = {}        ## §14 hard/soft test results
var placeholder_counts: Dictionary = {}       ## {trap_placeholder, unique_placeholder, trapped_door,
                                              ##  magic_item_placeholder, secret_gated_treasure}
