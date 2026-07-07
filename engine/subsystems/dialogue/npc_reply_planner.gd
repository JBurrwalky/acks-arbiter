class_name NpcReplyPlanner
extends RefCounted

## Turns an adjudicated outcome into a deterministic NpcReplyPlan
## (gdd-npc-dialogue.md §13.2). In Phase 1 this is a pure outcome->plan mapping
## consumed by DialogueTemplateProvider (mock) — it NEVER calls LLMManager.generate().
##
## The plan is the contract between the engine (which already decided everything)
## and the performer (which only says it well). Phase 1 populates the fields the
## Tier-0 templates need; the richer fields (lie_packet, demeanor_beat,
## active_effects, npc_move, interjection) are declared for shape stability but
## left at their inert Phase-1 defaults.
##
## No LLM. Deterministic.

const VERBOSITY_CAP := 60   # §13.2 word cap


## Build a plan from a DialogueAdjudicator outcome. [param npc_id] identifies the
## responder. Returns a Dictionary matching the §13.2 shape (Phase-1 subset).
static func plan_reply(npc_id: String, outcome: Dictionary) -> Dictionary:
	var move_id: String = outcome.get("move_id", "")
	var new_attitude: String = outcome.get("new_attitude", "neutral")
	var template_outcome: String = _template_outcome_key(outcome)
	var plan := {
		"npc_id": npc_id,
		"move_resolved": move_id,
		"outcome": outcome.get("kind", "none"),
		"template_outcome": template_outcome,
		"new_attitude": new_attitude,
		"mood": _mood_for(outcome),
		"must_say": _must_say(outcome),
		"must_not_reveal": [],
		"lie_packet": null,
		"demeanor_beat": null,          # Phase 3 (§13.11)
		"active_effects": [],           # Phase 3 (§5.5)
		"npc_move": null,               # Phase 3 (§5.6)
		"interjection": null,           # Phase 4 (§13.6)
		"style": {
			"register": "plain",
			"verbosity_cap": VERBOSITY_CAP,
			"language": "common",
		},
	}
	# ask_rumor carries its rumor text through for the template slot.
	if outcome.has("rumor_text"):
		plan["rumor_text"] = outcome.get("rumor_text", "")
	return plan


# ---------------------------------------------------------------------------
# Internal — deterministic mapping
# ---------------------------------------------------------------------------

## Maps an adjudicated outcome to the template outcome key that DialogueTemplate-
## Provider looks up (must match the keys in data/dialogue/templates/tier0.json).
static func _template_outcome_key(outcome: Dictionary) -> String:
	var kind: String = outcome.get("kind", "none")
	match kind:
		DialogueAdjudicator.OUTCOME_INFLUENCE, DialogueAdjudicator.OUTCOME_COMBAT:
			# COMBAT from an influence roll of 2 still reads as a hostile shift.
			var shift: int = int(outcome.get("attitude_shift", 0))
			if shift > 0:
				return "shift_toward_friendly"
			if shift < 0:
				return "shift_toward_hostile"
			return "no_change"
		DialogueAdjudicator.OUTCOME_PROVOKE:
			return "angered"
		DialogueAdjudicator.OUTCOME_RUMOR:
			return "shared"
		_:
			return "default"


static func _mood_for(outcome: Dictionary) -> String:
	if outcome.get("becomes_combat", false):
		return "enraged"
	var kind: String = outcome.get("kind", "none")
	var shift: int = int(outcome.get("attitude_shift", 0))
	if kind == DialogueAdjudicator.OUTCOME_INFLUENCE:
		if shift > 0:
			return "warming"
		if shift < 0:
			return "cooling"
		return "guarded"
	if kind == DialogueAdjudicator.OUTCOME_PROVOKE:
		return "affronted"
	if kind == DialogueAdjudicator.OUTCOME_RUMOR:
		return "conspiratorial"
	return "neutral"


## Engine-generated must_say facts (§13.9 "informationally complete"). Phase 1
## keeps these compact; templates already carry the phrasing.
static func _must_say(outcome: Dictionary) -> Array:
	var out: Array = []
	if outcome.get("becomes_combat", false):
		out.append("turns hostile and moves to attack")
	elif outcome.get("kind", "") == DialogueAdjudicator.OUTCOME_RUMOR:
		out.append("shares a rumor: %s" % outcome.get("rumor_text", ""))
	return out
