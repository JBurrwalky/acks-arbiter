class_name DungeonTierDerivation
extends RefCounted

## Per-floor tier derivation (gdd-dungeon-generator-v1.md §6).
##
## floor_tier(i) = clamp(entrance_tier + abs(i - entrance_floor_index), 1, 6),
## where i is the 1-based floor index. The clamp at 6 collapses deep floors of a
## high-entrance-tier dungeon to the maximum ACKS dungeon level; clamp_fired()
## lets the orchestrator emit a warning when that happens.

const MIN_TIER := 1
const MAX_TIER := 6


## Tier for one floor (floor_index is 1-based).
static func tier_for_floor(entrance_tier: int, floor_index: int, entrance_floor_index: int) -> int:
	var raw: int = entrance_tier + absi(floor_index - entrance_floor_index)
	return clampi(raw, MIN_TIER, MAX_TIER)


## Per-floor tiers for floors 1..floor_count.
static func tiers_for_dungeon(entrance_tier: int, floor_count: int, entrance_floor_index: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(1, floor_count + 1):
		out.append(tier_for_floor(entrance_tier, i, entrance_floor_index))
	return out


## True if any floor's pre-clamp tier exceeded MAX_TIER (caller may warn).
static func clamp_fired(entrance_tier: int, floor_count: int, entrance_floor_index: int) -> bool:
	for i in range(1, floor_count + 1):
		if entrance_tier + absi(i - entrance_floor_index) > MAX_TIER:
			return true
	return false
