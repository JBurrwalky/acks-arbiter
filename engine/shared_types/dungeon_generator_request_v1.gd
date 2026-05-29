class_name DungeonGeneratorRequestV1
extends RefCounted

## Input to DungeonGeneratorV1.generate() (gdd-dungeon-generator-v1.md §4.1).
##
## Tier API is a resolved decision (build plan): per-floor tier =
## clamp(entrance_tier + abs(floor_index - entrance_floor_index), 1, 6).
## See gdd §6 for worked examples.

var entrance_tier: int = 1                    ## 1..6 — difficulty tier of the entrance floor
var floor_count: int = 1                      ## >= 1
var entrance_floor_index: int = 1             ## 1-based index of the entrance floor
var dungeon_type: String = "wizards_dungeon"  ## unknown -> Wizard's Dungeon fallback (§7.1)
var dungeon_size: String = "medium"           ## passed through to the layout generator
var seed: int = 0                             ## master RNG seed; 0 -> randomize
var persist: bool = true                      ## write the result to the DB via DungeonGeneratorRepository
var dungeon_id: String = ""                   ## optional preset id; "" -> CampaignRepository.generate_id()
