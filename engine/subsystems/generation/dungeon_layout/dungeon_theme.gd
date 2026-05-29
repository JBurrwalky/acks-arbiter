class_name DungeonTheme
extends RefCounted

## Theme parameters that control the look and feel of a generated dungeon
## layout per `gdd-dungeon-layout.md` §5.1.
##
## Themes are stored as data, not as code — one DungeonTheme instance per
## entry in the §5.2 table. DG-V1.B-base populates only the Wizard's Dungeon
## theme (the V1 generator's universal fallback per V1 GDD §7); other themes
## from the §5.2 table can be added as needed when V2 introduces additional
## dungeon types.


# ---------------------------------------------------------------------------
# Vocabulary
# ---------------------------------------------------------------------------

const BIAS_SMALL := "small"
const BIAS_MIXED := "mixed"
const BIAS_LARGE := "large"
const BIAS_HUGE := "huge"

const CORRIDOR_STRAIGHT := "straight"
const CORRIDOR_BENT := "bent"
const CORRIDOR_LABYRINTH := "labyrinth"

const ROOM_SHAPE_RECTANGULAR := "rectangular"
const ROOM_SHAPE_IRREGULAR := "irregular"
const ROOM_SHAPE_MIXED := "mixed"

const VERTICAL_NONE := "none"
const VERTICAL_LOW := "low"
const VERTICAL_MEDIUM := "medium"
const VERTICAL_HIGH := "high"

const CORRIDOR_WIDTH_NARROW := "narrow"      ## 5' (1 cell)
const CORRIDOR_WIDTH_STANDARD := "standard"  ## 10' (2 cells) — default
const CORRIDOR_WIDTH_WIDE := "wide"          ## 70/30 mix of 10' / 20'
const CORRIDOR_WIDTH_MIXED := "mixed"        ## 50/30/15/5 mix per §7.1

const STRUCTURE_SUBTERRANEAN := "subterranean"
const STRUCTURE_ABOVE_GROUND := "above_ground"


# ---------------------------------------------------------------------------
# Fields (per §5.1)
# ---------------------------------------------------------------------------

## Display name from the ACKS d20 dungeon flavor table. e.g. "Wizard's Dungeon".
var type_name: String = ""

## BIAS_* — selects the room size range used by DungeonRoomScatter.
##   small: 2-4 cells (10'-20' rooms)
##   mixed: 2-6 cells (10'-30' rooms)
##   large: 3-8 cells (15'-40' rooms)
##   huge:  4-10 cells (20'-50' rooms)
var room_size_bias: String = BIAS_MIXED

## CORRIDOR_STRAIGHT / BENT / LABYRINTH — controls direction-pick probability
## in the recursive maze carver per §7.2.
var corridor_style: String = CORRIDOR_BENT

## 0-100; percentage of dead-end corridor cells to trim per §7.4.
var dead_end_removal: int = 60

## 0.0-1.0; chance of converting a dead-end into a loop connection per §7.3.
var loop_frequency: float = 0.3

## ROOM_SHAPE_* — rectangular for axis-aligned only, irregular for L/T/round
## shape modifications, mixed for a blend.
var room_shape: String = ROOM_SHAPE_MIXED

## Door type weighted roll per §8.2. Keys are the DungeonDoorData TYPE_*
## constants; values are integer weights summing to 100. The default empty
## dict means "use the generic §8.1 table"; populated themes override.
var door_type_weights: Dictionary = {}

## VERTICAL_* — how often the dungeon uses multi-level features. Unused in
## DG-V1.B-base (single-floor only); placeholder for V2 multi-level themes.
var vertical_tendency: String = VERTICAL_NONE

## CORRIDOR_WIDTH_* — controls the corridor carver's per-segment width choice.
var corridor_width: String = CORRIDOR_WIDTH_STANDARD

## Free-text feature tags the LLM consumes for room descriptions. Not used by
## the layout algorithm itself.
var special_features: Array[String] = []

## Monster type tags for themed encounter table construction per §5.3.
## EMPTY for Wizard's Dungeon (per the §5.3 added-2026-05-27 exception:
## Wizard's Dungeon uses the raw Random Monsters by Level table directly,
## not the tag-filter procedure).
var encounter_flavor: Array[String] = []

## STRUCTURE_* — controls multi-level spatial coherence rules per §8.2.
var structure_type: String = STRUCTURE_SUBTERRANEAN

## Weighted purpose table for room original_purpose assignment per §6.3.
## Key is the purpose string (e.g. "laboratory"); value is the integer
## percentage weight. Weights should sum to 100. The room placer rolls a
## weighted pick from this table for each room's `original_purpose`.
var purpose_weights: Dictionary = {}
