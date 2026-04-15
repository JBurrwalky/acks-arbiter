class_name SettlementNavigation
extends RefCounted

## Navigation throw logic for commuting-speed city travel.
##
## Per gdd-settlement-exploration-ui.md §3.3.4:
##   - Target: 11+ on 1d20 every turn at commuting speed.
##   - Exempt if the party has previously traveled this exact route (origin→dest).
##   - +4 modifier if destination POI was previously visited (but route is new).
##   - +4 modifier if any party member has the Navigation proficiency.
##   - On failure: party deviates 1d4+1 blocks from intended route.
##   - Meandering speed: no Navigation throw required (auto-success).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const NAVIGATION_TARGET := 11
const VISITED_DESTINATION_BONUS := 4
const NAVIGATION_PROFICIENCY_BONUS := 4


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Checks whether a Navigation throw is needed and, if so, resolves it.
##
## Returns a result dictionary:
##   exempt: bool — true if no throw was needed (previously traveled route)
##   target: int — the throw target (11)
##   roll: int — the raw d20 roll (0 if exempt)
##   modifier: int — total modifier applied
##   modified_total: int — roll + modifier
##   succeeded: bool — true if exempt or modified_total >= target
##   modifiers_applied: Array[String] — human-readable list of modifiers
static func check_navigation(
	campaign_id: String,
	settlement_id: String,
	origin_poi_id: String,
	dest_poi_id: String,
	party_characters: Array,  ## Array of CharacterData
) -> Dictionary:
	# Check route exemption first.
	if CampaignRepository.has_city_route(campaign_id, settlement_id, origin_poi_id, dest_poi_id):
		return {
			"exempt": true,
			"target": NAVIGATION_TARGET,
			"roll": 0,
			"modifier": 0,
			"modified_total": 0,
			"succeeded": true,
			"modifiers_applied": ["Known route — no throw required"],
		}

	# Calculate modifier.
	var modifier := 0
	var modifiers_applied: Array[String] = []

	# +4 if destination was previously visited (but not this route).
	if CampaignRepository.has_visited_poi(campaign_id, settlement_id, dest_poi_id):
		modifier += VISITED_DESTINATION_BONUS
		modifiers_applied.append("+4 visited destination")

	# +4 if any party member has Navigation proficiency.
	for character in party_characters:
		if character is CharacterData and character.has_proficiency("navigation"):
			modifier += NAVIGATION_PROFICIENCY_BONUS
			modifiers_applied.append("+4 Navigation proficiency (%s)" % character.name)
			break  # Only one bonus regardless of how many have it.

	# Roll the throw.
	var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "navigation_check")
	var raw_roll: int = roll.modified_total  # No modifier on the dice roll itself
	var modified_total: int = raw_roll + modifier
	var succeeded: bool = modified_total >= NAVIGATION_TARGET

	return {
		"exempt": false,
		"target": NAVIGATION_TARGET,
		"roll": raw_roll,
		"modifier": modifier,
		"modified_total": modified_total,
		"succeeded": succeeded,
		"modifiers_applied": modifiers_applied,
	}


## Calculates the deviation when navigation fails.
## Returns the number of blocks the party deviates: 1d4+1 (range 2-5).
static func roll_deviation() -> int:
	var roll: RollResult = DiceSystem.roll_digital(4, 1, 1, "navigation_deviation")
	return roll.modified_total
