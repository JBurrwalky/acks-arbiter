class_name EncounterScaler
extends RefCounted

## Sub-unit encounter threshold per gdd-army-warfare.md §4.6 + O-A-10 resolution.
##
## RAW: an N-creature pack equals a unit if N ≥ 20-man-equivalent per
## daw_armies_recruitment.xml §units L723. When a wilderness encounter result
## produces fewer creatures than that threshold, no fightable mass-combat unit
## can be assembled and the encounter is "sub-unit." The player is given
## three options:
##   1. ignore           — the army marches past; encounter bypassed
##   2. engage_with_party — the PC party detaches for a tactical battle
##   3. destroy_with_army — the army crushes the encounter without meaningful battle
##
## For ≥1-unit-equivalent encounters, the standard field-battle resolver
## (Phase 6B) handles the encounter.
##
## Public API:
##   classify(encounter, army_id) -> Dictionary
##     {is_sub_unit, threshold, creature_count, options, recommended_default}
##   resolve_destroy_outcome(encounter, army_id, dice_roller=Callable()) -> Dictionary
##     {creatures_eliminated, creatures_fled, narration_key}

const SUB_UNIT_THRESHOLD := 20  # 20-man-equivalent per RAW §units L723

const OPTION_IGNORE := "ignore"
const OPTION_ENGAGE_WITH_PARTY := "engage_with_party"
const OPTION_DESTROY_WITH_ARMY := "destroy_with_army"


static func classify(encounter: Dictionary, army_id: String) -> Dictionary:
	## encounter dictionary expected to contain at least:
	##   creature_count : int
	##   creature_size_factor : float (default 1.0; smaller-than-man gets <1, larger >1)
	## army_id parameter retained for future heuristics that depend on the army's
	## composition (e.g., refuse Destroy if the encounter contains heavy beasts).
	var raw_count: int = int(encounter.get("creature_count", 0))
	var size_factor: float = float(encounter.get("creature_size_factor", 1.0))
	var man_equivalent_count: int = int(round(float(raw_count) * size_factor))

	var is_sub_unit: bool = man_equivalent_count < SUB_UNIT_THRESHOLD
	var options: Array[String] = []
	var recommended_default: String = ""
	if is_sub_unit:
		options = [OPTION_IGNORE, OPTION_ENGAGE_WITH_PARTY, OPTION_DESTROY_WITH_ARMY]
		recommended_default = OPTION_IGNORE
	else:
		# At/above threshold the field-battle resolver runs; no choice surfaced.
		options = []
		recommended_default = "field_battle"

	return {
		"is_sub_unit": is_sub_unit,
		"threshold": SUB_UNIT_THRESHOLD,
		"creature_count": raw_count,
		"man_equivalent_count": man_equivalent_count,
		"options": options,
		"recommended_default": recommended_default,
		"army_id": army_id,
	}


static func resolve_destroy_outcome(
	encounter: Dictionary,
	army_id: String,
	dice_roller: Callable = Callable()
) -> Dictionary:
	## Per O-A-10: army crushes the encounter; encountered creatures are
	## eliminated unless they successfully flee. No army casualties recorded.
	## Flee check: opposed Move check vs army's effective interception speed.
	## v1 simplification: flat 25% flee chance unless encounter declares
	## explicit flee odds. Phase 7+ replaces this with a real movement contest.
	var raw_count: int = int(encounter.get("creature_count", 0))
	var flee_chance: float = clampf(
		float(encounter.get("flee_chance", 0.25)), 0.0, 1.0
	)
	var roll: float = float(_roll(dice_roller, 1, 100)) / 100.0
	var fled: bool = roll < flee_chance
	var creatures_eliminated: int = raw_count if not fled else 0
	var creatures_fled: int = raw_count if fled else 0
	return {
		"creatures_eliminated": creatures_eliminated,
		"creatures_fled": creatures_fled,
		"narration_key": "army_destroys_encounter" if not fled else "army_overruns_encounter_some_flee",
		"army_id": army_id,
	}


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
