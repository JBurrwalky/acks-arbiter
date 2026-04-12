class_name Attitude
extends RefCounted

## ACKS 1e five-state attitude model from rules/ax_reactions_and_influencing.xml.
##
## Diplomatic and seduction tones use HOSTILE..FRIENDLY.
## Intimidation tone substitutes FEARFUL/COWED for INDIFFERENT/FRIENDLY at the
## upper end of the table (the rule treats fearful/cowed as situational variants
## of the friendly result for intimidation only).

const HOSTILE := "hostile"
const UNFRIENDLY := "unfriendly"
const NEUTRAL := "neutral"
const INDIFFERENT := "indifferent"
const FRIENDLY := "friendly"

## Intimidation-only variants per ax_reactions_and_influencing.xml.
const FEARFUL := "fearful"
const COWED := "cowed"

const ALL_DIPLOMATIC: Array = [HOSTILE, UNFRIENDLY, NEUTRAL, INDIFFERENT, FRIENDLY]

## Reputation score thresholds. Score is canonical; tier is cached on the row.
##  score <= -60          -> hostile
## -59..-20               -> unfriendly
## -19..+19               -> neutral
## +20..+59               -> indifferent
##  score >= +60          -> friendly
const SCORE_HOSTILE_MAX := -60
const SCORE_UNFRIENDLY_MAX := -20
const SCORE_NEUTRAL_MAX := 19
const SCORE_INDIFFERENT_MAX := 59

const SCORE_MIN := -100
const SCORE_MAX := 100


static func score_to_tier(score: int) -> String:
	if score <= SCORE_HOSTILE_MAX:
		return HOSTILE
	if score <= SCORE_UNFRIENDLY_MAX:
		return UNFRIENDLY
	if score <= SCORE_NEUTRAL_MAX:
		return NEUTRAL
	if score <= SCORE_INDIFFERENT_MAX:
		return INDIFFERENT
	return FRIENDLY


## Reaction-roll modifier contributed by an attitude tier.
## Mirrors the "already-X" modifier scale in ax_reactions_and_influencing.xml
## (already-hostile -2, already-unfriendly -1, already-indifferent +1) and
## extends symmetrically for indifferent/friendly so faction membership and
## cascade contributions are uniform.
static func tier_to_modifier(tier: String) -> int:
	match tier:
		HOSTILE: return -2
		UNFRIENDLY: return -1
		NEUTRAL: return 0
		INDIFFERENT: return 1
		FRIENDLY: return 2
		FEARFUL: return 1
		COWED: return 2
	return 0


## Step-shift used by attempt-to-influence. Returns the new tier after shifting
## [param current] by [param steps] (positive = toward friendly, negative =
## toward hostile). Clamps at the ends of the diplomatic ladder.
static func shift_tier(current: String, steps: int) -> String:
	var idx := ALL_DIPLOMATIC.find(current)
	if idx == -1:
		idx = 2  # default neutral
	idx = clampi(idx + steps, 0, ALL_DIPLOMATIC.size() - 1)
	return ALL_DIPLOMATIC[idx]


static func clamp_score(score: int) -> int:
	return clampi(score, SCORE_MIN, SCORE_MAX)
