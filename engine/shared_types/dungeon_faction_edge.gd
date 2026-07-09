class_name DungeonFactionEdge
extends RefCounted

## A connection between two rooms in the faction generator's room graph
## (`gdd-dungeon-factions.md` §4.2 / §4.3). Undirected; stored once per room in
## each endpoint's neighbor list. `kind` classifies the passage for chokepoint
## detection and alert-propagation gating.


# ---------------------------------------------------------------------------
# Edge kinds (§4.3 boundary types)
# ---------------------------------------------------------------------------

const KIND_OPEN := "open"              ## archway / open corridor, no boundary
const KIND_DOOR := "door"             ## ordinary (unlocked/arch) door
const KIND_NARROW := "narrow"         ## narrow (<10') corridor — defensible, not a hard block
const KIND_LOCKED := "locked"         ## locked door — strong boundary (§4.3.3)
const KIND_BARRED := "barred"         ## barred door — strong boundary
const KIND_STUCK := "stuck"           ## stuck door — strong boundary
const KIND_SECRET := "secret"         ## secret door — strong boundary + awareness barrier
const KIND_STAIRS := "stairs"         ## vertical transition between levels (§4.3.4 / §10)

const VALID_KINDS: Array[String] = [
	KIND_OPEN, KIND_DOOR, KIND_NARROW, KIND_LOCKED, KIND_BARRED,
	KIND_STUCK, KIND_SECRET, KIND_STAIRS,
]

## Kinds that are STRONG boundaries: territory expansion never crosses them and
## awareness does not propagate through them (§4.3.3, §5.2 synthesis).
const STRONG_BOUNDARY_KINDS: Array[String] = [
	KIND_LOCKED, KIND_BARRED, KIND_STUCK, KIND_SECRET,
]

## Kinds that are DEFENSIBLE chokepoints: territory expansion stops AT them even
## into empty rooms (§4.2 stop condition, §4.3.2). Includes strong boundaries
## plus narrow corridors and ordinary doors.
const CHOKEPOINT_KINDS: Array[String] = [
	KIND_DOOR, KIND_NARROW, KIND_LOCKED, KIND_BARRED, KIND_STUCK, KIND_SECRET,
]


var to_room_id: int = -1
var kind: String = KIND_OPEN
var width_ft: int = 10                 ## corridor width; <10 is treated as narrow


func is_strong_boundary() -> bool:
	return STRONG_BOUNDARY_KINDS.has(kind)


## True if this edge is a defensible chokepoint that halts territory expansion
## into an otherwise-claimable empty room.
func is_chokepoint() -> bool:
	if CHOKEPOINT_KINDS.has(kind):
		return true
	return width_ft < 10


## True if this edge blocks awareness propagation (secret + all strong-boundary
## doors — factions on either side may not know the other exists, §4.3.3).
func blocks_awareness() -> bool:
	return is_strong_boundary()
