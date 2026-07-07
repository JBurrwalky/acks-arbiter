class_name RulerStrategyReassessor
extends RefCounted

## Seam B of the determinative-AI → LLM contract — gdd-ruler-ai.md §9.2
## (design brief §11.3): when a player action significantly changes a ruler's
## situation, the planner MAY ask a configured LLM for a STRUCTURED strategic
## suggestion. The contract's hard rules (design brief §9.1):
##
##   * Every suggestion is schema-validated against the action vocabulary;
##     unknown, malformed, or rule-violating suggestions are rejected and
##     logged. Rejection is STRICT — any invalid part rejects the whole
##     suggestion (no partial acceptance ambiguity).
##   * A valid suggestion enters the scorer ONLY as a situational modifier —
##     a ONE-TURN pending slot RulerAI._take_turn consumes (an optional §7.1
##     posture override plus multiplicative biases riding the crisis_biases
##     channel and its safety gates). It never executes directly and never
##     mutates the persisted disposition.
##   * With the stub/mock provider, reassessment is a NO-OP — the
##     deterministic scorer already handles the new situation via §6.2/§7.
##
## Accepted suggestion shape (all keys optional, at least one required):
##   suggested_biases: { action_id or "issue_decree|<kind>": multiplier }
##                     — multipliers clamped to [BIAS_MIN, BIAS_MAX]. The BARE
##                     "issue_decree" key is REJECTED: the scorer's per-kind
##                     safety gates (e.g. the raise-tax direction gate) only
##                     guard the specific "issue_decree|<kind>" keys, and a
##                     bare-key bias would ride the ungated fallback — exactly
##                     the rule-violating suggestion §9.2 says to reject.
##   posture:          one of StrategicDisposition.CRISIS_RESPONSES
##                     — overrides the §7.1 bias row for ONE turn
##   aggression_toward: { realm_id: 0..1 } — validated and reported in the
##                     ruler_strategy_reassessed changes, but v1 records it
##                     only (diplomacy dormant, gdd-ruler-ai.md §5.4)
##
## Significance thresholds (which player actions trigger a reassess call) are
## PROJECT CALL pending playtest (§13); callers pass their trigger string.

const TASK_TYPE := "ruler_strategy_reassessment"
const BIAS_MIN := 0.25
const BIAS_MAX := 4.0
const KNOWN_DECREE_KINDS := ["tax", "liturgy"]
const _SUGGESTION_KEYS := ["suggested_biases", "posture", "aggression_toward"]

## {ruler_id: {"biases": {key: multiplier}, "posture": String}} — validated
## one-turn modifiers awaiting the ruler's next monthly turn (in-memory by
## design: under the mock this is never populated, and a lost pending nudge
## degrades to the deterministic baseline).
static var _pending: Dictionary = {}


## The full Seam-B flow for one ruler. Returns
## {reassessed: bool, reason?: String, changes?: Dictionary}.
static func reassess(ruler_npc_id: String, trigger: String,
		situation: Dictionary = {}) -> Dictionary:
	if ruler_npc_id.is_empty() or trigger.is_empty():
		return {"reassessed": false, "reason": "missing_args"}
	var ruler: Dictionary = CampaignRepository.get_character(ruler_npc_id)
	if ruler.is_empty() \
			or String(ruler.get("character_type", "")) in ["pc", "henchman"]:
		return {"reassessed": false, "reason": "not_npc_ruler"}
	# §9.2 mock no-op: no request is made — the stub could only return the
	# generic fallback envelope (and would warn per call).
	if not LLMManager.is_configured():
		return {"reassessed": false, "reason": "llm_not_configured"}
	var context: Dictionary = {
		"task_type": TASK_TYPE,
		"ruler_npc_id": ruler_npc_id,
		"trigger": trigger,
	}
	context.merge(situation)
	var env: ResponseEnvelope = LLMManager.request_narration(context)
	if env == null or not env.success or env.is_fallback:
		return {"reassessed": false, "reason": "fallback_envelope"}
	return apply_validated(ruler_npc_id, trigger, JSON.parse_string(env.text))


## Validate + accept a structured suggestion (the post-envelope half of
## reassess(); public so tests exercise validation/acceptance without an LLM).
## Valid → stores the one-turn pending modifiers and emits
## ruler_strategy_reassessed(ruler_npc_id, trigger, changes).
static func apply_validated(ruler_npc_id: String, trigger: String,
		suggestion: Variant) -> Dictionary:
	if ruler_npc_id.is_empty():
		return {"reassessed": false, "reason": "missing_args"}
	var verdict: Dictionary = validate_suggestion(suggestion)
	if not bool(verdict.get("valid", false)):
		push_warning("RulerStrategyReassessor: rejected suggestion for %s (%s)" % [
			ruler_npc_id, String(verdict.get("reason", ""))])
		return {"reassessed": false, "reason": String(verdict.get("reason", ""))}
	var changes: Dictionary = verdict.get("normalized", {})
	var slot: Dictionary = _pending.get(ruler_npc_id, {"biases": {}, "posture": ""})
	var slot_biases: Dictionary = slot.get("biases", {})
	for bias_key in changes.get("biases", {}):
		var merged: float = float(slot_biases.get(bias_key, 1.0)) \
			* float((changes["biases"] as Dictionary)[bias_key])
		slot_biases[bias_key] = clampf(merged, BIAS_MIN, BIAS_MAX)
	slot["biases"] = slot_biases
	if changes.has("posture"):
		slot["posture"] = String(changes["posture"])
	_pending[ruler_npc_id] = slot
	EventBus.ruler_strategy_reassessed.emit(ruler_npc_id, trigger, changes)
	return {"reassessed": true, "changes": changes}


## Schema validation against the action vocabulary (design brief §9.1).
## Returns {valid: bool, reason: String, normalized: Dictionary}; normalized
## carries clamped copies under "biases" / "posture" / "aggression_toward".
static func validate_suggestion(suggestion: Variant) -> Dictionary:
	if not (suggestion is Dictionary):
		return _invalid("not_a_dictionary")
	var s: Dictionary = suggestion
	if s.is_empty():
		return _invalid("empty_suggestion")
	for key_v in s.keys():
		if not _SUGGESTION_KEYS.has(String(key_v)):
			return _invalid("unknown_key:%s" % String(key_v))
	var normalized: Dictionary = {}
	if s.has("suggested_biases"):
		var raw_biases: Variant = s["suggested_biases"]
		if not (raw_biases is Dictionary):
			return _invalid("biases_not_a_dictionary")
		var biases: Dictionary = {}
		for key_v in (raw_biases as Dictionary):
			var key: String = String(key_v)
			# Bare decree biases bypass the scorer's per-kind safety gates
			# (the raise-tax direction gate guards only "issue_decree|tax").
			if key == "issue_decree":
				return _invalid("decree_bias_requires_kind")
			if not _is_known_action_key(key):
				return _invalid("unknown_action:%s" % key)
			var value: Variant = (raw_biases as Dictionary)[key_v]
			if not (value is float or value is int):
				return _invalid("bias_not_numeric:%s" % key)
			biases[key] = clampf(float(value), BIAS_MIN, BIAS_MAX)
		if biases.is_empty():
			return _invalid("empty_biases")
		normalized["biases"] = biases
	if s.has("posture"):
		if not (s["posture"] is String) \
				or not StrategicDisposition.CRISIS_RESPONSES.has(String(s["posture"])):
			return _invalid("unknown_posture:%s" % String(s["posture"]))
		normalized["posture"] = String(s["posture"])
	if s.has("aggression_toward"):
		var raw_agg: Variant = s["aggression_toward"]
		if not (raw_agg is Dictionary):
			return _invalid("aggression_not_a_dictionary")
		var agg: Dictionary = {}
		for key_v in (raw_agg as Dictionary):
			var value: Variant = (raw_agg as Dictionary)[key_v]
			if not (value is float or value is int):
				return _invalid("aggression_not_numeric:%s" % String(key_v))
			agg[String(key_v)] = clampf(float(value), 0.0, 1.0)
		if agg.is_empty():
			return _invalid("empty_aggression")
		normalized["aggression_toward"] = agg
	if normalized.is_empty():
		return _invalid("no_actionable_content")
	return {"valid": true, "reason": "", "normalized": normalized}


## Pop this ruler's pending one-turn modifiers ({} when none) — called by
## RulerAI._take_turn so a nudge affects exactly one monthly turn.
static func consume_pending(ruler_npc_id: String) -> Dictionary:
	if not _pending.has(ruler_npc_id):
		return {}
	var slot: Dictionary = _pending[ruler_npc_id]
	_pending.erase(ruler_npc_id)
	return slot


## Test/teardown hook.
static func clear_pending() -> void:
	_pending.clear()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## A bias key is valid when it is a registered planner action id (except the
## bare "issue_decree", rejected upstream), or the scorer's
## "issue_decree|<kind>" decree-variant form (§6.2 canonical keys).
static func _is_known_action_key(key: String) -> bool:
	if RulerActionCatalog.ACTION_IDS.has(key):
		return true
	if key.begins_with("issue_decree|"):
		return KNOWN_DECREE_KINDS.has(key.substr("issue_decree|".length()))
	return false


static func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason, "normalized": {}}
