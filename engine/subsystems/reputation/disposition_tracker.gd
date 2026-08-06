class_name DispositionTracker
extends RefCounted

## Updates an NPC's runtime disposition (-5..+5) from interaction outcomes
## (gdd-npc-personality.md §7.1). Disposition is the per-NPC, direct-interaction
## feeling toward the party; DispositionTracker moves it after each reaction /
## influence resolves, records a warming/cooling/stable trend, and keeps a capped
## change log. The disposition then feeds back into the next reaction roll via
## PersonalityReactionModifiers.disposition_modifier (capped ±2).
##
## Scope note (PROJECT CALL): this is intentionally SEPARATE from the broad
## ReputationSystem (faction/settlement/domain/tier-A-B cascade). Disposition is
## the fine-grained personal feeling that a face-to-face conversation moves;
## reputation is the party's wider standing. Keeping them distinct avoids a
## double-count in the reaction roll (disposition stays capped at ±2; the
## reputation tier modifier is layered separately).
##
## RefCounted with a class_name; all static. The core apply_interaction() mutates
## an NpcPersonality in memory (DB-free, testable); persist() writes it back.

const DISP_MIN: int = -5
const DISP_MAX: int = 5
const HISTORY_CAP: int = 8


## Apply an interaction outcome to [param personality]'s disposition, in place.
## [param result] is the InteractionResult from InteractionResolver. Returns
## { delta, disposition, trend }. A null/empty result is a no-op.
static func apply_interaction(personality: NpcPersonality, result) -> Dictionary:
	if personality == null or result == null:
		return {"delta": 0, "disposition": 0, "trend": "stable"}
	var delta: int = _delta_for(result)
	return _apply_delta(personality, delta, _reason_for(result))


## Apply a raw disposition delta (e.g. from a non-interaction event — a gift, a
## betrayal). Positive warms, negative cools. Returns { delta, disposition, trend }.
static func apply_delta(personality: NpcPersonality, delta: int, reason: String = "") -> Dictionary:
	if personality == null:
		return {"delta": 0, "disposition": 0, "trend": "stable"}
	return _apply_delta(personality, delta, reason)


## Persist [param personality] back onto the NPC's characters.personality column.
## [param repo] defaults to CampaignRepository; guarded so test fakes without the
## method are a safe no-op.
static func persist(npc_id: String, personality: NpcPersonality, repo = null) -> bool:
	if personality == null or npc_id.is_empty():
		return false
	var actual_repo = repo if repo != null else CampaignRepository
	if not actual_repo.has_method("update_character_personality"):
		return false
	return actual_repo.update_character_personality(npc_id, personality.to_json())


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

static func _apply_delta(personality: NpcPersonality, delta: int, reason: String) -> Dictionary:
	var before: int = personality.disposition
	var after: int = clampi(before + delta, DISP_MIN, DISP_MAX)
	var effective: int = after - before  # clamping may shrink the delta
	personality.disposition = after
	personality.disposition_trend = _trend_for(effective)
	if effective != 0:
		personality.disposition_history.append({
			"delta": effective,
			"reason": reason,
			"value": after,
		})
		while personality.disposition_history.size() > HISTORY_CAP:
			personality.disposition_history.pop_front()
	return {"delta": effective, "disposition": after, "trend": personality.disposition_trend}


## Disposition delta from an interaction result (PROJECT CALL). Diplomatic and
## seduction warm or cool by the rolled attitude / influence shift. Intimidation
## is coercive: it can only hold steady or breed resentment — compliance via fear
## never raises genuine disposition.
static func _delta_for(result) -> int:
	var tone: String = String(result.tone)
	var kind: String = String(result.kind)
	if tone == InteractionResult.TONE_INTIMIDATION:
		if kind == InteractionResult.KIND_INFLUENCE:
			var shift: int = int(result.attitude_shift)
			if shift > 0:
				return -1  # coerced toward fearful/cowed → resentment
			return shift   # backfired (toward hostile) → cool by the shift
		return _intimidation_seed(String(result.resulting_attitude))
	# Diplomatic / seduction.
	if kind == InteractionResult.KIND_INFLUENCE:
		return int(result.attitude_shift)
	return _diplomatic_seed(String(result.resulting_attitude))


static func _diplomatic_seed(attitude: String) -> int:
	match attitude:
		Attitude.FRIENDLY: return 2
		Attitude.INDIFFERENT: return 1
		Attitude.NEUTRAL: return 0
		Attitude.UNFRIENDLY: return -1
		Attitude.HOSTILE: return -2
	return 0


static func _intimidation_seed(attitude: String) -> int:
	match attitude:
		Attitude.HOSTILE: return -2
		Attitude.UNFRIENDLY: return -1
		Attitude.NEUTRAL: return 0
		Attitude.FEARFUL: return -1
		Attitude.COWED: return -1
	return 0


static func _trend_for(delta: int) -> String:
	if delta > 0:
		return "warming"
	if delta < 0:
		return "cooling"
	return "stable"


static func _reason_for(result) -> String:
	return "%s %s -> %s" % [String(result.tone), String(result.kind),
		String(result.resulting_attitude)]
