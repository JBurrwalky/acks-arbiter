class_name UnitCapacityCalculator
extends RefCounted

## Single source of truth for stronghold structural-hp ↔ unit-capacity ↔ breach
## math per rules/daw_sieges.xml §siege_mechanics L31-46.
##
## v1 implements the no-map formulas (L37-41: ceil(shp / 1000)). The grid-mapped
## v1.1+ swap-in (L39-40: "If mapped, calculate unit capacity by summing the
## unit capacity of all structures") is a one-method replacement of
## compute_unit_capacity; everything else stays.

# RAW §siege_mechanics.structural_hit_points L31-36
const STONE_GP_PER_SHP: int = 8                  # L32
const WOOD_SHP_RATIO: float = 0.10               # L33

# RAW §siege_mechanics.unit_capacity L37-41
const SHP_PER_UNIT_CAPACITY: int = 1000          # L38

# RAW §siege_mechanics.breaches L42-46
const SHP_PER_BREACH: int = 1000                 # L43


## Estimate stronghold shp from cp_value when no map exists.
## RAW L32: stone shp = ceil(gp_value / 8); in cp, shp = ceil(cp / 800).
## RAW L33: wood shp = 1/10 of comparable stone shp.
## Callers pass the strongholds.cp_value column (since Migration 116).
static func estimate_shp_from_cp_value(cp_value: int, material: String = "stone") -> int:
	if cp_value <= 0:
		return 0
	var stone_shp: int = int(ceil(float(cp_value) / float(STONE_GP_PER_SHP * 100)))
	if material == "wood":
		return int(ceil(float(stone_shp) * WOOD_SHP_RATIO))
	return stone_shp


## Compute unit capacity from shp.
## RAW L38: 1 unit per 1,000 shp, rounded up.
## Minimum 1 (a stronghold with any shp can host at least 1 unit).
static func compute_unit_capacity(shp: int) -> int:
	if shp <= 0:
		return 0
	var uc: int = int(ceil(float(shp) / float(SHP_PER_UNIT_CAPACITY)))
	return maxi(uc, 1)


## Breach count derived from cumulative damage dealt.
## RAW L43: each 1,000 shp of damage creates 1 breach.
## RAW L44: each breach permits 1 additional assaulting unit.
## RAW L45: undamaged strongholds begin with a 1:1 assaulting:defending limit.
static func breach_count_from_damage(damage_dealt: int) -> int:
	if damage_dealt <= 0:
		return 0
	@warning_ignore("integer_division")
	return damage_dealt / SHP_PER_BREACH


## Maximum assaulting units per RAW §assault.resolving_assaults L476-477.
## = unit_capacity + breach_count
static func max_assaulting_units(unit_capacity: int, breach_count: int) -> int:
	return maxi(0, unit_capacity) + maxi(0, breach_count)


## Maximum defending units per RAW §assault.resolving_assaults L481.
## = unit_capacity (no breach bonus on defense)
static func max_defending_units(unit_capacity: int) -> int:
	return maxi(0, unit_capacity)
