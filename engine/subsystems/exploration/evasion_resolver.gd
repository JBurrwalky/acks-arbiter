class_name EvasionResolver
extends RefCounted

## Wilderness Evasion (Wilderness closure Phase 5).
##
## Pure logic — no DB writes, no signal emission. Caller owns the
## pursuit_states row and any combat-entry routing.
##
## Authority — SACRED:
##   `acore_adventures_and_encounters.xml` §chases_in_the_wilderness:
##     "If combat has not commenced and the fleeing side is surprised, it
##      may flee automatically." (handled at the surprise stage; this
##      resolver covers the explicit-attempt path)
##     "Otherwise, the fleeing party must succeed on the Wilderness Evasion
##      table."
##     Wilderness Evasion table:
##       Up to 4   evaders → 11+ base, +0 / +4 / +8 by pursuer ratio
##       5  to 12  evaders → 14+ base, +0 / +3 / +5
##       13 to 24  evaders → 16+ base, +0 / +3 / +5
##       25+       evaders → 19+ base, +0 / +3 / +5
##     "minimum_escape_chance: 5%."
##     §if_evasion_fails:
##       "The pursuers keep the fleeing party within sight."
##       "If the pursuers have greater movement, they have a 50% chance
##        (11+ on d20) to catch up close."
##       "If that catch-up roll fails, the fleeing side may attempt to
##        escape again."
##       "This cycle repeats daily until either the fleeing side escapes
##        or the pursuers catch them."
##
## v1 reads `pursuer_size / evader_size` to bin the ratio:
##   ≤25%  → +0 modifier on the throw target  (small ambushers)
##   26-75%→ +3/+4 modifier (table varies by row)
##   76%+  → +5/+8 modifier (mass-vs-small)
## Modifier APPLIES TO THE TARGET (raises it = harder to evade — except
## RAW makes the bonus on the EVADER'S throw which lowers difficulty when
## the pursuer is huge). Re-reading the table: the "+8" column makes the
## largest-pursuer case the EASIEST evasion, which matches RAW intent
## ("the larger the pursuing group… the easier it is for the fleeing side").
## So the modifier is BONUS to the throw, not penalty to target. Adjusted
## throw = roll + modifier; succeeded = adjusted >= base_target.


# ---------------------------------------------------------------------------
# Constants — sacred from acore_adventures_and_encounters.xml
# ---------------------------------------------------------------------------

## Wilderness Evasion table. Each row: (max_evaders_inclusive, base_target,
## bonus_low_ratio, bonus_mid_ratio, bonus_high_ratio).
const _EVASION_TABLE := [
	[4,  11, 0, 4, 8],
	[12, 14, 0, 3, 5],
	[24, 16, 0, 3, 5],
	[INF, 19, 0, 3, 5],  # 25+
]
const INF := 9999

const MIN_ESCAPE_CHANCE_PCT := 5  # RAW minimum_escape_chance: 5%
const CATCH_UP_TARGET_D20 := 11   # RAW: 11+ on d20 for 50% catch-up


# ---------------------------------------------------------------------------
# Public API — single evasion attempt
# ---------------------------------------------------------------------------

## Resolve one Wilderness Evasion attempt.
##
## [param evader_size] number of characters in the fleeing party.
## [param pursuer_size] number of creatures pursuing.
## [param judge_modifier] optional integer added to the throw (positive
## helps evader; e.g. +2 for densely wooded terrain). Default 0.
##
## Returns Dictionary:
##   evader_size, pursuer_size: int
##   ratio_band: String           — "low" (<=25%), "mid" (26-75%), "high" (>=76%)
##   base_target: int             — table value before modifiers
##   bonus: int                   — modifier from the ratio column
##   judge_modifier: int          — pass-through
##   roll: int                    — 1d20 result
##   total: int                   — roll + bonus + judge_modifier
##   succeeded: bool              — total >= base_target (with 5% floor enforced)
##   floor_applied: bool          — true when the 5% RAW floor flipped a fail
##                                  to a success on a natural 20 / floor roll
##   notes: String
static func attempt(
	evader_size: int,
	pursuer_size: int,
	judge_modifier: int,
	dice,
) -> Dictionary:
	if evader_size <= 0:
		return _empty_result()
	var row: Array = _row_for_evader_size(evader_size)
	var base_target: int = int(row[1])
	var ratio_band: String = _ratio_band(evader_size, pursuer_size)
	var bonus: int = _ratio_bonus(row, ratio_band)

	var roll: RollResult = dice.roll_digital(20, 1, 0, "wilderness_evasion")
	var total: int = roll.modified_total + bonus + judge_modifier
	var succeeded: bool = total >= base_target

	# RAW minimum_escape_chance: 5% — i.e., a natural 20 always grants a
	# slim chance even when the math says no escape. We model the 5% floor
	# as: a natural 20 always succeeds (1/20 = 5%).
	var floor_applied: bool = false
	if not succeeded and roll.modified_total == 20:
		succeeded = true
		floor_applied = true

	var note: String = ""
	if succeeded and floor_applied:
		note = "Lucky escape (5%% floor)."
	elif succeeded:
		note = "Evasion succeeded (rolled %d, total %d vs %d)." % [
			roll.modified_total, total, base_target]
	else:
		note = "Evasion failed (rolled %d, total %d vs %d)." % [
			roll.modified_total, total, base_target]

	return {
		"evader_size": evader_size,
		"pursuer_size": pursuer_size,
		"ratio_band": ratio_band,
		"base_target": base_target,
		"bonus": bonus,
		"judge_modifier": judge_modifier,
		"roll": roll.modified_total,
		"total": total,
		"succeeded": succeeded,
		"floor_applied": floor_applied,
		"notes": note,
	}


## Resolve a daily catch-up check after a failed evasion. Per RAW:
## "If the pursuers have greater movement, they have a 50% chance (11+ on
## d20) to catch up close. If that catch-up roll fails, the fleeing side
## may attempt to escape again."
##
## [param pursuer_speed_advantage] is a positive integer when the pursuer
## is faster (any positive value triggers the catch-up roll). RAW only
## requires the pursuer be faster — does not scale by how much faster.
##
## Returns Dictionary:
##   eligible: bool                     — pursuer is faster (catch-up rolls)
##   roll: int                          — d20 result (0 when ineligible)
##   target: int                        — 11
##   caught: bool                       — total >= target
##   notes: String
static func catch_up(pursuer_speed_advantage: int, dice) -> Dictionary:
	if pursuer_speed_advantage <= 0:
		return {
			"eligible": false,
			"roll": 0,
			"target": CATCH_UP_TARGET_D20,
			"caught": false,
			"notes": "Pursuer not faster — no catch-up roll.",
		}
	var roll: RollResult = dice.roll_digital(20, 1, 0, "pursuit_catchup")
	var caught: bool = roll.modified_total >= CATCH_UP_TARGET_D20
	return {
		"eligible": true,
		"roll": roll.modified_total,
		"target": CATCH_UP_TARGET_D20,
		"caught": caught,
		"notes": "Caught up." if caught else "Pursuer falls back; evasion may be retried.",
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _row_for_evader_size(evader_size: int) -> Array:
	for entry in _EVASION_TABLE:
		var max_for_band: int = int(entry[0])
		if evader_size <= max_for_band:
			return entry
	return _EVASION_TABLE[-1]


static func _ratio_band(evader_size: int, pursuer_size: int) -> String:
	if evader_size <= 0:
		return "low"
	var ratio_pct: float = (float(pursuer_size) / float(evader_size)) * 100.0
	if ratio_pct <= 25.0:
		return "low"
	elif ratio_pct <= 75.0:
		return "mid"
	return "high"


static func _ratio_bonus(row: Array, ratio_band: String) -> int:
	match ratio_band:
		"low":  return int(row[2])
		"mid":  return int(row[3])
		_:       return int(row[4])


static func _empty_result() -> Dictionary:
	return {
		"evader_size": 0,
		"pursuer_size": 0,
		"ratio_band": "low",
		"base_target": 11,
		"bonus": 0,
		"judge_modifier": 0,
		"roll": 0,
		"total": 0,
		"succeeded": false,
		"floor_applied": false,
		"notes": "no evader",
	}
