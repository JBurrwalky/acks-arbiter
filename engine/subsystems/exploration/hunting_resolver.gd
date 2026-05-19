class_name HuntingResolver
extends RefCounted

## Wilderness hunting (Wilderness closure Phase 3).
##
## Pure logic — no DB writes, no signal emission. The wilderness_activity
## handler with `kind == "hunt"` calls `attempt(party, dice)`, applies the
## ration_units delta, and routes the toast.
##
## Authority: SACRED — `acore_adventures_and_encounters.xml`
## §rations_and_foraging.hunting:
##   "Activity: Must be the only activity for the day; no travel is possible."
##   "Check: Proficiency throw 14+ on 1d20."
##   "Success: Food for 2d6 man-sized creatures."
##   "Additional rule: One wandering monster check is made during the day of
##    hunting using the appropriate terrain table."
##
## SACRED — `acore_adventures_and_encounters.xml`
## §rations_and_foraging.survival_proficiency_bonus:
##   "Characters with Survival proficiency gain +4 on hunt and forage throws."
##
## Hunt is a deliberate full-day activity, distinct from the daily auto-forage
## tick on the wilderness_day_tick. The player chooses to hunt via the
## wilderness right-click context menu; the wilderness_activity handler
## branches on `kind == "hunt"` and calls this resolver after the wandering
## encounter check fires (or alongside it — see WildernessHandlers).
##
## v1: party designates a single hunter (the active character or first member
## with Survival, falling back to the leader). The throw is per-hunter, not
## per-character. Future polish: allow the player to pick the hunter via UI.


# ---------------------------------------------------------------------------
# Constants — sacred from acore_adventures_and_encounters.xml
# ---------------------------------------------------------------------------

const HUNT_TARGET_UNTRAINED := 14
const SURVIVAL_PROFICIENCY := "survival"
const HUNT_AND_FORAGE_TRAINED_BONUS := 4

const HUNT_DIE_SIDES := 6
const HUNT_DIE_COUNT := 2  # 2d6 person-feeds per RAW success.


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Resolve a hunt for [param party]. Selects the best available hunter
## (first member with Survival; otherwise the active leader / first member),
## rolls 1d20, applies Survival +4 if relevant. On success, rolls 2d6 and
## adds to party.ration_units.
##
## Returns Dictionary:
##   hunter_id:    String
##   hunter_name:  String
##   has_survival: bool
##   roll:         int
##   modifier:     int
##   total:        int
##   target:       int (= 14)
##   succeeded:    bool
##   units_added:  int (0 on failure; 2d6 on success)
##   notes:        String — short summary
static func attempt(party: PartyData, dice) -> Dictionary:
	if party == null or party.character_data.is_empty():
		return _empty_result()

	var hunter: CharacterData = _pick_hunter(party)
	var has_survival: bool = hunter.has_proficiency(SURVIVAL_PROFICIENCY)
	var bonus: int = HUNT_AND_FORAGE_TRAINED_BONUS if has_survival else 0
	# RAW §effort_rules L168: strenuous penalty applies to proficiency throws.
	# Hunting is a Survival proficiency throw per the hunting-foraging GDD.
	var strenuous_penalty: int = StrenuousAccountant.get_proficiency_throw_penalty(hunter.id)
	var roll: RollResult = dice.roll_digital(20, 1, 0, "hunt")
	var total: int = roll.modified_total + bonus - strenuous_penalty
	var succeeded: bool = total >= HUNT_TARGET_UNTRAINED

	var units_added: int = 0
	if succeeded:
		var feed: RollResult = dice.roll_digital(
			HUNT_DIE_SIDES, HUNT_DIE_COUNT, 0, "hunt_yield")
		units_added = feed.modified_total
		party.ration_units += units_added

	var notes: String = "%s hunting: %s (rolled %d%s, total %d vs %d)" % [
		hunter.name,
		"success +%d units" % units_added if succeeded else "failed",
		roll.modified_total,
		" + %d Survival" % bonus if bonus > 0 else "",
		total,
		HUNT_TARGET_UNTRAINED,
	]

	return {
		"hunter_id": hunter.id,
		"hunter_name": hunter.name,
		"has_survival": has_survival,
		"roll": roll.modified_total,
		"modifier": bonus,
		"strenuous_penalty": strenuous_penalty,
		"total": total,
		"target": HUNT_TARGET_UNTRAINED,
		"succeeded": succeeded,
		"units_added": units_added,
		"notes": notes,
	}


# ---------------------------------------------------------------------------
# Internal — hunter selection
# ---------------------------------------------------------------------------

## Pick the best hunter for the party. Preference order:
##   1. First member with Survival proficiency.
##   2. First member overall.
## v1 ignores wis/dex prerequisites and class affinity. Future polish: surface
## a picker UI when multiple candidates have Survival.
static func _pick_hunter(party: PartyData) -> CharacterData:
	for cd: CharacterData in party.character_data:
		if cd.has_proficiency(SURVIVAL_PROFICIENCY):
			return cd
	return party.character_data[0]


static func _empty_result() -> Dictionary:
	return {
		"hunter_id": "",
		"hunter_name": "",
		"has_survival": false,
		"roll": 0,
		"modifier": 0,
		"total": 0,
		"target": HUNT_TARGET_UNTRAINED,
		"succeeded": false,
		"units_added": 0,
		"notes": "no characters present",
	}
