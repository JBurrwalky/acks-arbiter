class_name DungeonDoorData
extends RefCounted

## A single door produced by the dungeon layout generator.
##
## Per `gdd-dungeon-layout.md` §11.
##
## Doors carry a `type` (the "what is this door object" property — arch,
## unlocked, locked, trapped, portcullis) and an `is_secret` overlay (the
## "is this door visually disguised as a wall" property, orthogonal to type
## per the §8.1 step-5 secret-as-overlay rule added 2026-05-27). The
## `door_material` field (populated by the §8.3 material rule) governs
## bashability per `gdd-dungeon-map-ui.md`.
##
## Each door occupies a single cell on a room's perimeter. The cell coordinate
## is `position`. The `connects` array lists the room IDs joined by this door
## (typically two adjacent rooms, or one room and the corridor pseudo-room).


# ---------------------------------------------------------------------------
# Door type vocabulary
# ---------------------------------------------------------------------------

const TYPE_ARCH := "arch"
const TYPE_UNLOCKED := "unlocked"
const TYPE_LOCKED := "locked"
const TYPE_TRAPPED := "trapped"
const TYPE_PORTCULLIS := "portcullis"

const VALID_TYPES: Array[String] = [
	TYPE_ARCH,
	TYPE_UNLOCKED,
	TYPE_LOCKED,
	TYPE_TRAPPED,
	TYPE_PORTCULLIS,
]

## ROLL-CATEGORY key used in `theme.door_type_weights` but NOT a final door
## type per the §8.1 step-5 secret-as-overlay rule. A "secret" roll triggers
## a sub-weight roll (50% unlocked / 40% locked / 10% trapped) for the
## underlying type and sets `is_secret = true` on the resulting door. The
## DungeonRoomComposer handles this expansion; consumers of DoorData should
## never see `type == "secret"` after composition.
const ROLL_CATEGORY_SECRET := "secret"


# ---------------------------------------------------------------------------
# Door material vocabulary (§11 schema)
# ---------------------------------------------------------------------------
# The canonical full set of door materials used across ALL dungeon systems.
# The §8.3 layout-generator rule produces a subset (wood_standard, metal,
# stone — plus MATERIAL_NONE for arches and metal for portcullises); the
# curtain materials and wood_thick come from other producers (V2 themes,
# primitive monster lairs, hand-authoring).
#
# Bashability (consumed by gdd-dungeon-map-ui.md §4.2.1 Bash Door logic):
#   curtain_cloth / curtain_leather → no door object; pass through freely
#   wood_standard / wood_thick      → bashable with an axe (1 turn, house rule)
#   stone / metal                   → unbashable (Bash Door greyed out)

const MATERIAL_NONE := ""  ## Arches (open passages) carry no door material.
const MATERIAL_CURTAIN_CLOTH := "curtain_cloth"
const MATERIAL_CURTAIN_LEATHER := "curtain_leather"
const MATERIAL_WOOD_STANDARD := "wood_standard"
const MATERIAL_WOOD_THICK := "wood_thick"
const MATERIAL_STONE := "stone"
const MATERIAL_METAL := "metal"

## Every legal door_material value, including the empty-string "none" sentinel
## for arches. Used by validation + the DG-V1.C `dungeon_doors.door_material`
## CHECK constraint.
const VALID_MATERIALS: Array[String] = [
	MATERIAL_NONE,
	MATERIAL_CURTAIN_CLOTH,
	MATERIAL_CURTAIN_LEATHER,
	MATERIAL_WOOD_STANDARD,
	MATERIAL_WOOD_THICK,
	MATERIAL_STONE,
	MATERIAL_METAL,
]

## Materials a party member can bash through with an axe (per gdd-dungeon-map-ui.md
## §4.2.1). Curtains need no bashing (free passage); stone/metal are unbashable.
const BASHABLE_MATERIALS: Array[String] = [
	MATERIAL_WOOD_STANDARD,
	MATERIAL_WOOD_THICK,
]

## Materials that burn. Consumed by future fire / burning-oil / fireball-vs-door
## systems (not wired to any consumer yet — defined now for forward-compat).
## Cloth and leather curtains and both wood tiers are flammable; stone, metal,
## and the none/arch sentinel are not.
const FLAMMABLE_MATERIALS: Array[String] = [
	MATERIAL_CURTAIN_CLOTH,
	MATERIAL_CURTAIN_LEATHER,
	MATERIAL_WOOD_STANDARD,
	MATERIAL_WOOD_THICK,
]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Grid cell of the door. The door IS this cell (not an edge between cells —
## the project uses cell-based walls per layout GDD §2 "Cell-based walls").
var position: Vector2i = Vector2i.ZERO

## See TYPE_* constants. Defaults to TYPE_UNLOCKED.
var type: String = TYPE_UNLOCKED

## Room IDs this door connects. For a door on a room perimeter facing a
## corridor, this is [room_id, -1] where -1 represents the corridor pseudo-room.
## For a door between two rooms, this is [room_id_a, room_id_b].
var connects: Array[int] = []

## See MATERIAL_* constants. Defaults to MATERIAL_WOOD_STANDARD. Populated by
## the §8.3 material rule in DungeonRoomComposer (the rule produces only
## MATERIAL_NONE for arches, MATERIAL_METAL for portcullises, and
## wood_standard / metal / stone otherwise — the curtain materials and
## wood_thick are reserved for V2 themes and hand-authoring).
var door_material: String = MATERIAL_WOOD_STANDARD

## Default false. Evil doors auto-close every turn (60 rounds) per
## `gdd-dungeon-map-ui.md`. The layout generator never sets this to true in V1;
## it is a hand-authored / V2 generator concern.
var is_evil: bool = false

## Overlay flag per §8.1 step 5 (added 2026-05-27). When true the door is
## visually concealed as part of a wall until discovered (Search action at
## runtime). Orthogonal to `type` — a door may be Locked AND Secret, Trapped
## AND Secret, etc. The composer sets this for any door whose §8.1 weighted
## roll landed on `ROLL_CATEGORY_SECRET`. The §10.1 door inventory in
## `gdd-dungeon-generator-v1.md` § treats wooden Locked+Secret doors as not
## requiring placed keys (bash-once-detected) and §8.3 step 2 keeps secret
## doors at `wood_standard` material regardless of tier.
var is_secret: bool = false

## Grid cell holding the lever wired to this portcullis (§10.3 step 6). Set by
## key_lever_placer when a portcullis receives a lever in a reachable room; the
## cell's terrain_feature becomes "lever_portcullis_<x>_<y>" at finalization.
## Vector2i(-1, -1) means no wired lever (non-portcullis, or downgraded per §10.4).
var wired_lever_position: Vector2i = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Material-derived property helpers (static)
# ---------------------------------------------------------------------------
# Bashability and flammability are DERIVED from door_material, not stored.
# These static helpers are the canonical classifiers — consumers should call
# them rather than re-deriving membership inline, so the rules live in one place.

## True if an axe-wielder can batter this material down (the two wood tiers).
static func is_bashable(material: String) -> bool:
	return material in BASHABLE_MATERIALS


## True if this material burns. No consumer is wired yet (forward-compat for
## fire / burning-oil / spell-vs-door systems); curtains + both wood tiers burn.
static func is_flammable(material: String) -> bool:
	return material in FLAMMABLE_MATERIALS


## True if this material is a hanging curtain (free passage, blocks LOS while
## closed). The §8.3 generator never produces these in V1; reserved for V2.
static func is_curtain(material: String) -> bool:
	return material == MATERIAL_CURTAIN_CLOTH or material == MATERIAL_CURTAIN_LEATHER


# ---------------------------------------------------------------------------
# Convenience (instance)
# ---------------------------------------------------------------------------

## Whether this door blocks movement in its INITIAL post-generation state.
## Used by the V1 generator's navigability pass (§9) to compute reachability.
## Note: portcullises block movement but not LOS; this method is about movement.
## Curtains never block movement (free passage even while closed).
func blocks_movement_initially() -> bool:
	if DungeonDoorData.is_curtain(door_material):
		return false
	return type != TYPE_ARCH  # archways are open passages with no door object


## Convenience instance wrappers around the static material classifiers.
func bashable() -> bool:
	return DungeonDoorData.is_bashable(door_material)


func flammable() -> bool:
	return DungeonDoorData.is_flammable(door_material)
