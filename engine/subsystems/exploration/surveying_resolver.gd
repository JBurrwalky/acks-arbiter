class_name SurveyingResolver
extends RefCounted

## Land Surveying assessment of total lairs in a hex (Wilderness closure Phase 4).
##
## Pure logic — no DB writes, no signal emission. The wilderness handler
## reads the prior search count from `survey_progress`, calls `assess`,
## and persists the new estimate.
##
## Authority — SACRED:
##   `le_wilderness_lair_rules.xml` §land_surveying.assessment_rules:
##     "A character with the Land Surveying proficiency may attempt to
##      assess the total number of lairs in a hex based on terrain,
##      evidence of cultivation, and similar factors."
##     "The character may attempt one assessment on first arriving in the
##      hex, and one additional assessment each time the hex is searched."
##   `le_wilderness_lair_rules.xml` §land_surveying.procedure:
##     "The Judge secretly rolls 1d20 on the character's behalf."
##     "The base target value is 18+."
##     "Apply a cumulative +4 bonus for each successful search the party
##      has conducted in that hex up to that point."
##     "On success, the character correctly assesses the number of lairs
##      in the hex, and the Judge reveals that number."
##     "If the throw fails with an unmodified 1, the character makes an
##      incorrect assessment, and the Judge rolls or chooses a false number
##      to reveal."
##     "On any other failure, the character does not yet have enough
##      information to make or revise an assessment."
##
## A v1 simplification: when the throw fails on a natural 1, we compute the
## false estimate as `actual ± 1d4` clamped to [0, max_lairs_for_terrain].
## RAW says "the Judge rolls or chooses a false number to reveal" — this
## resolver picks one deterministically from the dice stream.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const BASE_TARGET := 18
const SEARCH_BONUS_PER_SUCCESS := 4
const PROFICIENCY_KEY := "land_surveying"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Resolve a Land Surveying assessment for [param party] on a hex with
## [param successful_searches_so_far] prior successful searches and
## [param actual_lair_count] real lairs (queried by caller from `lairs`
## table — both discovered and undiscovered count toward the assessment).
##
## [param optional_specialist_bonus] — Phase 6 hook for ASSISTING Land
## Surveyor specialists. The wilderness handler computes it via
## `SpecialistBonusResolver`; when a hired specialist is the THROWER (see
## below) the handler excludes that specialist's own +4 from this value
## (a professional does not assist themselves).
##
## [param hired_surveyor] — an active `specialists` row of kind
## land_surveyor, or {}. Eligibility (Jedidiah ruling 2026-06-10, per
## le_wilderness_lair_rules.xml §hirelings L191-195 "Can be hired to assess
## the number of lairs in a hex"): when NO party member has the proficiency
## but a hired Land Surveyor is attached to the party, the specialist makes
## the throw. A proficient party member always takes precedence (the
## specialist then assists via optional_specialist_bonus). Specialists are
## non-adventuring hires with no activity state, so no strenuous penalty
## applies to their throw. (v1 had read RAW as a character-only ability;
## superseded by the ruling.)
##
## Returns Dictionary:
##   eligible: bool             — a proficient member OR a hired Land
##                                Surveyor can make the throw
##   surveyor_id: String        — character id or specialist_id ("" if ineligible)
##   surveyor_is_specialist: bool
##   roll: int                  — 1d20 result
##   target: int                — base 18 minus search bonus
##   search_bonus: int          — 4 × successful_searches_so_far
##   specialist_bonus: int      — pass-through from optional_specialist_bonus
##   succeeded: bool            — total >= target (where total = roll + specialist_bonus)
##   natural_one: bool          — RAW false-reading trigger
##   estimate: int              — revealed number; -1 when no assessment
##   estimate_correct: bool     — true on success, false on natural-1 false reading
##   notes: String              — short summary
static func assess(
	party: PartyData,
	successful_searches_so_far: int,
	actual_lair_count: int,
	dice,
	optional_specialist_bonus: int = 0,
	hired_surveyor: Dictionary = {},
) -> Dictionary:
	if party == null or party.character_data.is_empty():
		return _empty_result()

	var surveyor: CharacterData = _pick_surveyor(party)
	var surveyor_is_specialist: bool = false
	var surveyor_id: String = ""
	var surveyor_name: String = ""
	if surveyor != null:
		surveyor_id = surveyor.id
		surveyor_name = surveyor.name
	elif not hired_surveyor.is_empty() \
			and str(hired_surveyor.get("kind", "")) == SpecialistCatalog.LAND_SURVEYOR:
		surveyor_is_specialist = true
		surveyor_id = str(hired_surveyor.get("specialist_id", ""))
		surveyor_name = str(hired_surveyor.get("name", "Land Surveyor"))
	else:
		return _empty_result()

	var search_bonus: int = SEARCH_BONUS_PER_SUCCESS * max(0, successful_searches_so_far)
	var effective_target: int = BASE_TARGET - search_bonus
	# RAW §effort_rules L168: strenuous penalty applies to proficiency throws.
	# Land Surveying is the Land Surveying proficiency throw. Hired
	# specialists carry no character_activity_state — no penalty.
	var strenuous_penalty: int = 0
	if not surveyor_is_specialist:
		strenuous_penalty = StrenuousAccountant.get_proficiency_throw_penalty(surveyor_id)
	var roll: RollResult = dice.roll_digital(20, 1, 0, "land_surveying")
	var raw: int = roll.modified_total
	var total: int = raw + optional_specialist_bonus - strenuous_penalty
	var succeeded: bool = total >= effective_target
	# Natural-1 RAW trigger uses the unmodified roll, not the modified total.
	var natural_one: bool = (raw == 1)

	var estimate: int = -1
	var estimate_correct: bool = true
	var notes: String = ""

	if succeeded:
		estimate = actual_lair_count
		notes = "Assessment correct: %d lair(s)." % actual_lair_count
	elif natural_one:
		# RAW: "the Judge rolls or chooses a false number to reveal."
		# We roll 1d4 and signed-step from the truth, clamped to [0, +inf).
		var step_roll: RollResult = dice.roll_digital(4, 1, 0, "land_surveying_false")
		var sign_roll: RollResult = dice.roll_digital(2, 1, 0, "land_surveying_false_sign")
		var step: int = step_roll.modified_total
		if sign_roll.modified_total == 1:
			step = -step
		estimate = max(0, actual_lair_count + step)
		estimate_correct = false
		notes = "False reading: surveyor reports %d lair(s)." % estimate
	else:
		notes = "Inconclusive — surveyor cannot assess yet."

	return {
		"eligible": true,
		"surveyor_id": surveyor_id,
		"surveyor_name": surveyor_name,
		"surveyor_is_specialist": surveyor_is_specialist,
		"roll": raw,
		"target": effective_target,
		"search_bonus": search_bonus,
		"specialist_bonus": optional_specialist_bonus,
		"strenuous_penalty": strenuous_penalty,
		"total": total,
		"succeeded": succeeded,
		"natural_one": natural_one,
		"estimate": estimate,
		"estimate_correct": estimate_correct,
		"notes": notes,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _pick_surveyor(party: PartyData) -> CharacterData:
	for cd: CharacterData in party.character_data:
		if cd.has_proficiency(PROFICIENCY_KEY):
			return cd
	return null


static func _empty_result() -> Dictionary:
	return {
		"eligible": false,
		"surveyor_id": "",
		"surveyor_name": "",
		"surveyor_is_specialist": false,
		"roll": 0,
		"target": BASE_TARGET,
		"search_bonus": 0,
		"specialist_bonus": 0,
		"total": 0,
		"succeeded": false,
		"natural_one": false,
		"estimate": -1,
		"estimate_correct": true,
		"notes": "no Land Surveying proficiency in party and no hired Land Surveyor",
	}
