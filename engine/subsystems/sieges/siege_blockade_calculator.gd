class_name SiegeBlockadeCalculator
extends RefCounted

## Computes blockade requirements per rules/daw_sieges.xml §blockade L65-193.
##
## Three blockade methods (§blockading_with_units / _with_ships /
## _with_fortifications). A given siege may use one, some, or all in combination
## (RAW §methods_of_siege.general_rules L23-27).
##
## Key public entry points:
##   compute_blockade_requirement(uc, water_facing_pct, defender_navy_size)
##     → {min_units, min_ships, min_circumvallation_ft, ships_required_with_navy}
##   compute_circumvallation_effect(feet, uc)
##     → {units_reduced, is_complete, smuggle_penalty}
##   is_blockade_complete(siege_id) → bool
##     Reads sieges row + siege_artillery (ships) + circumvallation_feet.
##   circumvallation_cp_cost(feet) → int  (cp not gp, project convention)

# RAW §blockade quick_reference L72-75
const UNITS_PER_UC: int = 2                            # L73
const SHIPS_PER_UC_NUMERATOR: int = 1                  # L73 (1/2 ship per UC)
const SHIPS_PER_UC_DENOMINATOR: int = 2
const FEET_PER_UC: int = 250                           # L73
const MIN_BLOCKADE_UNITS: int = 20                     # L74, L78
const MIN_BLOCKADE_SHIPS: int = 10                     # L74, L189
const MIN_BLOCKADE_FEET: int = 2500                    # L74

# RAW §blockading_with_fortifications.effects L108-113
const FEET_PER_UNIT_REDUCTION_INCREMENT: int = 250     # L109
const UNITS_REDUCED_PER_INCREMENT: int = 2             # L109
const COMPLETE_CIRCUMVALLATION_SMUGGLE_PENALTY: int = -4  # L112

# RAW §blockading_with_fortifications.cost_rules L101-107
const CIRCUMVALLATION_CP_PER_100FT: int = 10000        # L102: 100gp/100ft → 10000cp/100ft

# RAW §blockading_with_ships L84-92
const SHIPS_REQUIRED_WHEN_FULLY_WATER_NUMERATOR: int = 1  # L87 (uc / 2)
const SHIPS_REQUIRED_WHEN_FULLY_WATER_DENOMINATOR: int = 2


## Compute the baseline requirement for a complete blockade.
## Returns {min_units, min_ships, min_circumvallation_ft,
##          ships_required_with_navy, ships_water_facing_only}
static func compute_blockade_requirement(
	unit_capacity: int,
	water_facing_pct: int,
	defender_navy_size: int = 0
) -> Dictionary:
	if unit_capacity <= 0:
		return {
			"min_units": MIN_BLOCKADE_UNITS,
			"min_ships": MIN_BLOCKADE_SHIPS,
			"min_circumvallation_ft": MIN_BLOCKADE_FEET,
			"ships_required_with_navy": MIN_BLOCKADE_SHIPS + maxi(0, defender_navy_size),
			"ships_water_facing_only": 0,
		}
	var clamped_pct: int = clampi(water_facing_pct, 0, 100)
	# RAW L78: required units = 2 × UC, minimum 20.
	var land_units: int = maxi(unit_capacity * UNITS_PER_UC, MIN_BLOCKADE_UNITS)
	# RAW L87-88: fully water-surrounded → uc / 2; partial → uc × pct / 2.
	# Banker's rounding for the partial case to avoid drift.
	var ships_required: int = 0
	if clamped_pct >= 100:
		ships_required = XPAwardCalculator.bankers_round(float(unit_capacity) / float(SHIPS_REQUIRED_WHEN_FULLY_WATER_DENOMINATOR))
	else:
		ships_required = XPAwardCalculator.bankers_round(
			float(unit_capacity) * float(clamped_pct) / 100.0 / float(SHIPS_REQUIRED_WHEN_FULLY_WATER_DENOMINATOR)
		)
	ships_required = maxi(ships_required, MIN_BLOCKADE_SHIPS) if clamped_pct > 0 else 0
	# RAW L91: defender navy adds to required ships.
	var ships_with_navy: int = ships_required + maxi(0, defender_navy_size)
	# RAW L73: 250' of circumvallation per UC; min 2,500'.
	var feet_required: int = maxi(unit_capacity * FEET_PER_UC, MIN_BLOCKADE_FEET)
	return {
		"min_units": land_units,
		"min_ships": ships_with_navy,
		"min_circumvallation_ft": feet_required,
		"ships_required_with_navy": ships_with_navy,
		"ships_water_facing_only": ships_required,
	}


## Compute how circumvallation reduces required encirclement units.
## RAW L109: each 250' reduces required units by 2.
## RAW L111: if required units reduced to 0, the stronghold is fully encircled.
## RAW L112: complete circumvallation imposes -4 on smuggling.
static func compute_circumvallation_effect(feet: int, unit_capacity: int) -> Dictionary:
	var units_reduction: int = 0
	if feet > 0:
		@warning_ignore("integer_division")
		var increments: int = feet / FEET_PER_UNIT_REDUCTION_INCREMENT
		units_reduction = increments * UNITS_REDUCED_PER_INCREMENT
	# Required for "complete": feet must cover the full perimeter (= UC × 250').
	var feet_for_complete: int = maxi(unit_capacity * FEET_PER_UC, MIN_BLOCKADE_FEET)
	var is_complete: bool = feet >= feet_for_complete
	var smuggle_penalty: int = COMPLETE_CIRCUMVALLATION_SMUGGLE_PENALTY if is_complete else 0
	return {
		"units_reduced": units_reduction,
		"is_complete": is_complete,
		"smuggle_penalty": smuggle_penalty,
	}


## Cost of circumvallation in cp.
## RAW L102: 100gp per 100' length → 10,000 cp per 100'.
static func circumvallation_cp_cost(feet: int) -> int:
	if feet <= 0:
		return 0
	# Prorate: cost = feet × 10000 / 100 = feet × 100 cp.
	return feet * 100


## Has the besieger achieved a complete blockade given current units, ships,
## and circumvallation? Reads the sieges + siege_artillery rows.
##
## v1 simplification: this is a snapshot; the resolver records the moment the
## blockade is first completed via append_action(siege_id, ..., 'blockade_completed').
static func is_blockade_complete(
	besieging_units: int,
	besieging_ships: int,
	circumvallation_feet: int,
	unit_capacity: int,
	water_facing_pct: int,
	defender_navy_size: int = 0
) -> bool:
	var req: Dictionary = compute_blockade_requirement(unit_capacity, water_facing_pct, defender_navy_size)
	# Each method may partially satisfy. RAW L89-90: walls blockaded by ship
	# don't also need land blockade; remaining land-facing walls do.
	# v1 model: water_facing_pct of perimeter handled by ships if ship count
	# meets the water requirement; remaining (1 - pct) perimeter handled by
	# (units + circumvallation).
	var clamped_pct: int = clampi(water_facing_pct, 0, 100)
	var ship_obligation_met: bool = besieging_ships >= int(req.get("ships_required_with_navy", 0))
	var land_perimeter_pct: float = 1.0 - (float(clamped_pct) / 100.0)
	var land_units_needed: int = XPAwardCalculator.bankers_round(float(int(req.get("min_units", 0))) * land_perimeter_pct)
	var land_feet_needed: int = XPAwardCalculator.bankers_round(float(int(req.get("min_circumvallation_ft", 0))) * land_perimeter_pct)
	var circ_effect: Dictionary = compute_circumvallation_effect(circumvallation_feet, unit_capacity)
	var units_after_circ: int = maxi(0, land_units_needed - int(circ_effect.get("units_reduced", 0)))
	var land_obligation_met: bool = besieging_units >= units_after_circ \
		or (circumvallation_feet >= land_feet_needed and bool(circ_effect.get("is_complete", false)))
	return ship_obligation_met and land_obligation_met


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.
