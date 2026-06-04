class_name HideoutCostTable
extends RefCounted

## Hideout size + cost lookup, per RAW `rules/ax_thief_skill_update.xml`
## §hideouts_and_syndicates `hideout_size_and_cost` table (SACRED — do not edit
## the numbers).
##
## A hideout's minimum cost and the maximum syndicate size it supports are both
## gated by the MARKET CLASS of the host urban settlement. A larger settlement
## (lower roman numeral / lower integer) supports a larger syndicate but demands
## a costlier minimum hideout.
##
## market_class is the INTEGER form used project-wide
## (`settlement_entrances.market_class`): 6 = Class VI (smallest), 1 = Class I
## (largest). Money helpers return gp unless suffixed `_cp` (cp = gp × 100, the
## Migration 116 currency convention; `hideouts.cp_value` is in cp).
##
## Pure static functions; no DB, no state.
##
##   Class VI  (6): max    25, min   5,000 gp
##   Class V   (5): max    50, min  10,000 gp
##   Class IV  (4): max   100, min  20,000 gp
##   Class III (3): max   375, min  75,000 gp
##   Class II  (2): max   750, min 150,000 gp
##   Class I   (1): max 3,000, min 600,000 gp


## market_class (INTEGER 1..6) -> {min_gp, max_syndicate}. SACRED — transcribed
## verbatim from RAW `ax_thief_skill_update.xml`:63-68.
const _TABLE := {
	6: {"min_gp": 5000,   "max_syndicate": 25},
	5: {"min_gp": 10000,  "max_syndicate": 50},
	4: {"min_gp": 20000,  "max_syndicate": 100},
	3: {"min_gp": 75000,  "max_syndicate": 375},
	2: {"min_gp": 150000, "max_syndicate": 750},
	1: {"min_gp": 600000, "max_syndicate": 3000},
}

## CP per GP (Migration 116 currency convention). 1 gp = 100 cp.
const CP_PER_GP := 100


## True if [param market_class] is a known class (1..6).
static func is_valid_market_class(market_class: int) -> bool:
	return _TABLE.has(market_class)


## Minimum hideout cost in GP for the host settlement's market class.
## Unknown class → 0 (callers should gate on is_valid_market_class first).
static func minimum_cost_gp_for_market_class(market_class: int) -> int:
	return int((_TABLE.get(market_class, {}) as Dictionary).get("min_gp", 0))


## Minimum hideout cost in CP (gp × 100) — the unit of `hideouts.cp_value`.
static func minimum_cost_cp_for_market_class(market_class: int) -> int:
	return minimum_cost_gp_for_market_class(market_class) * CP_PER_GP


## Maximum syndicate size (member count) the host market class supports.
## Unknown class → 0.
static func max_syndicate_for_market_class(market_class: int) -> int:
	return int((_TABLE.get(market_class, {}) as Dictionary).get("max_syndicate", 0))
