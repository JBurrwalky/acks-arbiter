class_name InteractionResult
extends RefCounted

## Output of InteractionResolver. Captures roll, modifier breakdown, and the
## resulting attitude (or attitude shift, for attempt-to-influence).

const TONE_DIPLOMATIC := "diplomatic"
const TONE_INTIMIDATION := "intimidation"
const TONE_SEDUCTION := "seduction"

const ALL_TONES: Array = [TONE_DIPLOMATIC, TONE_INTIMIDATION, TONE_SEDUCTION]

const KIND_INITIAL := "initial"
const KIND_INFLUENCE := "influence"

var kind: String = KIND_INITIAL
var tone: String = TONE_DIPLOMATIC
var raw_roll: int = 7         # 2d6 raw
var total_modifier: int = 0
var modifier_breakdown: Array = []  # Array of { source, value, category }
var final_total: int = 7
var resulting_attitude: String = Attitude.NEUTRAL  # for KIND_INITIAL
var attitude_shift: int = 0  # signed step count for KIND_INFLUENCE
var charm_like_flag: bool = false  # Mystic Aura: total >= 12
var time_until_next_attempt_seconds: int = 0  # gating per ax_reactions table


func to_dict() -> Dictionary:
	return {
		"kind": kind,
		"tone": tone,
		"raw_roll": raw_roll,
		"total_modifier": total_modifier,
		"modifier_breakdown": modifier_breakdown.duplicate(true),
		"final_total": final_total,
		"resulting_attitude": resulting_attitude,
		"attitude_shift": attitude_shift,
		"charm_like_flag": charm_like_flag,
		"time_until_next_attempt_seconds": time_until_next_attempt_seconds,
	}
