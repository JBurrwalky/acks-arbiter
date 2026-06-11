class_name LairSearchResolver
extends RefCounted

## Wilderness lair discovery (Wilderness closure Phase 4).
##
## Pure logic — no DB writes, no signal emission. The wilderness handler
## queries the placed-but-undiscovered lairs in a hex (via CampaignRepository),
## calls one of the resolver entry points, and applies the result.
##
## Authority — SACRED:
##   `le_wilderness_lair_rules.xml` §searching_for_lairs.abstract_search_procedure
##     "For each hour of searching, equal to six turns, make one secret
##      searching throw on behalf of the party using 1d20."
##     "Determine the target value from the party's daily movement rate
##      through the hex using the lair_search_target_values table."
##   `le_wilderness_lair_rules.xml` §searching_for_lairs.tracking
##     "If any party member has the Tracking proficiency, the party receives
##      a +4 bonus on the lair search roll."
##   `le_wilderness_lair_rules.xml` §searching_for_lairs.aerial_reconnaissance
##     "If the party is capable of air travel, double its daily wilderness
##      movement rate." Aerial recon is exposed via `compute_target_value`'s
##      `is_aerial` flag; v1 of the handler always passes false (no flying
##      mounts wired).
##
## PROJECT-DESIGNED:
##   * `optional_specialist_bonus` parameter on every entry point. Phase 4
##     always passed 0; Phase 6 wires the Pathfinder specialist bonus into
##     this hook without changing the resolver's signature.
##
## (The v1 passive lair-spotting entry point that rolled on every travel_leg
## was removed 2026-06-10 per gdd-lair-discovery.md §10 — the lazy-placement
## redesign has no pre-placed lairs to spot. Wandering substitution and the
## dedicated search are the only discovery paths.)
##
## All randomness flows through the injected `dice` (DiceSystem-like) so
## tests can substitute a scripted roller.


# ---------------------------------------------------------------------------
# Constants — sacred from le_wilderness_lair_rules.xml
# ---------------------------------------------------------------------------

const TRACKING_BONUS := 4
const TRACKING_PROFICIENCY := "tracking"

## Target value table. Rows are (max_miles_inclusive, target_value); the
## last row uses INF as max so 192+ falls through to 2+. Values are the
## minimum 1d20 result needed to spot a lair this hour / leg.
const _TARGET_TABLE := [
	[11, 18],
	[23, 17],
	[35, 16],
	[47, 15],
	[59, 14],
	[71, 13],
	[83, 12],
	[95, 11],
	[107, 10],
	[119, 9],
	[131, 8],
	[143, 7],
	[155, 6],
	[167, 5],
	[179, 4],
	[191, 3],
]
const _TARGET_FLOOR := 2  # 192 miles or more


# ---------------------------------------------------------------------------
# Public API — target value lookup
# ---------------------------------------------------------------------------

## Look up the lair-search target value for a party moving at
## [param daily_miles] miles per day through the hex. When [param is_aerial]
## is true, RAW says "double its daily wilderness movement rate"
## (le_wilderness_lair_rules.xml §aerial_reconnaissance), which we apply
## before the table lookup.
static func compute_target_value(daily_miles: int, is_aerial: bool = false) -> int:
	var miles: int = daily_miles
	if is_aerial:
		miles *= 2
	for row in _TARGET_TABLE:
		var max_miles: int = int(row[0])
		var target: int = int(row[1])
		if miles <= max_miles:
			return target
	return _TARGET_FLOOR


# ---------------------------------------------------------------------------
# Public API — dedicated hour-of-search throw
# ---------------------------------------------------------------------------

## One throw on behalf of the party for one hour of dedicated searching.
##
## RAW (le_wilderness_lair_rules.xml §abstract_search_procedure):
##   "For each hour of searching, equal to six turns, make one secret
##    searching throw on behalf of the party using 1d20."
## During dedicated search the daily movement rate is "11 miles or less"
## per the table → target 18+. The handler should pass `daily_miles = 0`
## when the party is searching in place; this resolver normalizes that to
## the 18+ row.
##
## [param undiscovered_lair_count] — number of placed-but-undiscovered
## lairs in the hex. RAW: "the party discovers a lair if at least one lair
## is present." If 0, the throw is still rolled and recorded (the party
## doesn't know whether the hex has lairs), but `lair_found` is false.
##
## Returns Dictionary:
##   roll: int                 — 1d20 result before bonuses
##   tracking_bonus: int       — 4 if any member has Tracking, else 0
##   specialist_bonus: int     — pass-through from optional_specialist_bonus
##   total: int                — roll + bonuses
##   target: int               — required value for success
##   succeeded: bool           — total >= target
##   lair_found: bool          — succeeded AND undiscovered_lair_count > 0
##   undiscovered_lairs_at_throw: int  — value at time of throw
##   notes: String             — short summary
static func search_hour(
	party: PartyData,
	daily_miles: int,
	undiscovered_lair_count: int,
	dice,
	optional_specialist_bonus: int = 0,
	is_aerial: bool = false,
) -> Dictionary:
	if party == null:
		return _empty_search_result()

	var tracking_bonus: int = TRACKING_BONUS if _party_has_tracking(party) else 0
	var roll: RollResult = dice.roll_digital(20, 1, 0, "lair_search")
	var total: int = roll.modified_total + tracking_bonus + optional_specialist_bonus
	var target: int = compute_target_value(daily_miles, is_aerial)
	var succeeded: bool = total >= target
	var lair_found: bool = succeeded and undiscovered_lair_count > 0

	var note := ""
	if succeeded and lair_found:
		note = "Search succeeded — lair revealed."
	elif succeeded:
		note = "Search succeeded — no lair present in this hex."
	else:
		note = "Search failed (rolled %d, needed %d)." % [total, target]

	return {
		"roll": roll.modified_total,
		"tracking_bonus": tracking_bonus,
		"specialist_bonus": optional_specialist_bonus,
		"total": total,
		"target": target,
		"succeeded": succeeded,
		"lair_found": lair_found,
		"undiscovered_lairs_at_throw": undiscovered_lair_count,
		"notes": note,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _party_has_tracking(party: PartyData) -> bool:
	if party == null or party.character_data.is_empty():
		return false
	for cd: CharacterData in party.character_data:
		if cd.has_proficiency(TRACKING_PROFICIENCY):
			return true
	return false


static func _empty_search_result() -> Dictionary:
	return {
		"roll": 0,
		"tracking_bonus": 0,
		"specialist_bonus": 0,
		"total": 0,
		"target": 18,
		"succeeded": false,
		"lair_found": false,
		"undiscovered_lairs_at_throw": 0,
		"notes": "no party",
	}
