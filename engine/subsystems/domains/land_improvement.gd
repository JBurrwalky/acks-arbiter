class_name LandImprovement
extends RefCounted

## Land improvement attempt resolver per `acore_axioms_strongholds_and_domains.xml`
## §land_improvement L207-215.
##
## Rules:
##   * 25,000 gp per +1 land value per 6-mile hex (= 2,500,000 cp under the
##     unified cp standard, 1 gp = 100 cp).
##   * Hard caps: cumulative improvement ≤ +3 per hex AND final land_value ≤ 9.
##   * Land improvements lose 1 gp value per gp pillaged from the domain
##     (Phase 8 pillage flow consumes this; Phase 0 only declares the cap).
##   * During sieges, treat improvements as wooden structures: multiply SHP
##     dealt by 8 to compute lost gp value (Phase 1 siege subsystem).

const COST_PER_PLUS_ONE_CP := 2_500_000  # RAW 25,000 gp × 100 cp/gp
const MAX_IMPROVEMENT_PER_HEX := 3
const MAX_TOTAL_LAND_VALUE := 9


## Attempt a single +1 land-value improvement on the given hex.
## [param hex] is a row from `domain_hexes` (keys: land_value, land_improvement_level).
## [param cp_committed] is the cp the ruler is willing to spend toward this +1.
## Returns a Dictionary with keys:
##   accepted: bool                 — true if the +1 was applied
##   reason: String                 — code: "ok" | "insufficient_cp" | "improvement_capped"
##                                    | "land_value_capped"
##   new_improvement: int           — resulting land_improvement_level on the hex
##   new_land_value: int            — resulting effective land_value
##   cp_spent: int                  — COST_PER_PLUS_ONE_CP on accept, 0 on reject
static func attempt_improvement(hex: Dictionary, cp_committed: int) -> Dictionary:
	var current_imp: int = int(hex.get("land_improvement_level", 0))
	var current_lv: int = int(hex.get("land_value", 5))

	if cp_committed < COST_PER_PLUS_ONE_CP:
		return {
			"accepted": false, "reason": "insufficient_cp",
			"new_improvement": current_imp, "new_land_value": current_lv,
			"cp_spent": 0,
		}
	if current_imp >= MAX_IMPROVEMENT_PER_HEX:
		return {
			"accepted": false, "reason": "improvement_capped",
			"new_improvement": current_imp, "new_land_value": current_lv,
			"cp_spent": 0,
		}
	if current_lv >= MAX_TOTAL_LAND_VALUE:
		return {
			"accepted": false, "reason": "land_value_capped",
			"new_improvement": current_imp, "new_land_value": current_lv,
			"cp_spent": 0,
		}

	# Final cap check after applying +1: both improvement count and land_value
	# stay within bounds.
	var next_imp: int = current_imp + 1
	var next_lv: int = current_lv + 1
	if next_imp > MAX_IMPROVEMENT_PER_HEX or next_lv > MAX_TOTAL_LAND_VALUE:
		return {
			"accepted": false, "reason": "land_value_capped",
			"new_improvement": current_imp, "new_land_value": current_lv,
			"cp_spent": 0,
		}

	return {
		"accepted": true, "reason": "ok",
		"new_improvement": next_imp, "new_land_value": next_lv,
		"cp_spent": COST_PER_PLUS_ONE_CP,
	}
