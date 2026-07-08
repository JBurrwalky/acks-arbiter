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
## responder. [param reply_ctx] (Phase 3) carries the lie-decision + demeanor-beat
## inputs and the active-effects / npc-move channels the session assembles:
##   { attitude, personality, willingness, topic, true_fact, truth_costs_npc,
##     deception_facts, false_variant, npc_class, npc_role, dice, seed_hint,
##     active_effects, npc_move }
## Returns a Dictionary matching the §13.2 shape.
static func plan_reply(npc_id: String, outcome: Dictionary,
		reply_ctx: Dictionary = {}) -> Dictionary:
	var move_id: String = outcome.get("move_id", "")
	var new_attitude: String = outcome.get("new_attitude", "neutral")
	# The session may pre-set the exact template key for a Phase-3/Q-5 outcome
	# (it knows the resolved band/result); otherwise map from the Phase-1/2 kind.
	var template_outcome: String = String(outcome.get("template_outcome", "")) \
		if outcome.has("template_outcome") else _template_outcome_key(outcome)
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
		"demeanor_beat": null,          # Phase 3 (§13.11) — set below (always present)
		"active_effects": reply_ctx.get("active_effects", []),   # Phase 3 (§5.5)
		"npc_move": reply_ctx.get("npc_move", null),             # Phase 3 (§5.6)
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
	# Phase-3/Q-5 template slots the session precomputed (quest title, reward,
	# a per-move detail line for request_action / parley / surrender / ability).
	for slot in ["quest_title", "reward_summary", "detail"]:
		if outcome.has(slot):
			plan[slot] = outcome.get(slot, "")
	# --- Dialogue Phase 2 ---
	# ask_question disclosure carries the fact through as a template slot; the
	# entry's `accuracy` flows UNCHANGED (the NPC states what they believe, §9.1).
	if outcome.get("kind", "") == DialogueAdjudicator.OUTCOME_KNOWLEDGE:
		var entry: Dictionary = outcome.get("knowledge", {})
		plan["knowledge_fact"] = String(entry.get("fact", ""))
		plan["knowledge_accuracy"] = String(entry.get("accuracy", "true"))

	# --- Dialogue Phase 3 (§9.4 lying + §13.11 demeanor beat) ---
	# The lie decision is deterministic (DeceptionEngine): mark the reply a lie,
	# fabricate the false content engine-side, and deliver it AS the disclosure
	# (the NPC states the false fact confidently). The demeanor beat is present on
	# EVERY reply — leak-vs-hold when lying, personality noise when honest.
	var lie: Variant = DeceptionEngine.decide(npc_id, outcome, reply_ctx)
	var is_lying := lie != null
	if is_lying:
		plan["lie_packet"] = lie
		# Perform the lie AS a confident disclosure of the false fact.
		plan["template_outcome"] = "disclosed"
		plan["move_resolved"] = "ask_question"
		plan["knowledge_fact"] = String((lie as Dictionary).get("assert", ""))
		plan["knowledge_accuracy"] = "false"
	plan["demeanor_beat"] = DeceptionEngine.compose_beat(reply_ctx, is_lying)
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
		# --- Dialogue Phase 2 ---
		DialogueAdjudicator.OUTCOME_KNOWLEDGE:
			return "disclosed"
		DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED:
			# The refusal reason picks the template variant.
			match String(outcome.get("reason", "never")):
				"no_knowledge":
					return "no_knowledge"
				"if_paid":
					return "wants_payment"
				"not_trusted":
					return "not_trusted"
				_:
					return "refused"
		DialogueAdjudicator.OUTCOME_BRIBE:
			return "bribed"
		DialogueAdjudicator.OUTCOME_TERMS:
			return "terms"
		DialogueAdjudicator.OUTCOME_HIRE:
			match String(outcome.get("disposition", "refuse")):
				"accept_elan":
					return "accept_elan"
				"accept":
					return "accept"
				"try_again":
					return "try_again"
				"refuse_slander":
					return "refuse_slander"
				_:
					return "refuse"
		DialogueAdjudicator.OUTCOME_GATHER:
			return "default"
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
	# --- Dialogue Phase 2 ---
	if kind == DialogueAdjudicator.OUTCOME_KNOWLEDGE:
		return "forthcoming"
	if kind == DialogueAdjudicator.OUTCOME_KNOWLEDGE_REFUSED:
		return "guarded"
	if kind == DialogueAdjudicator.OUTCOME_BRIBE:
		return "tempted"
	if kind == DialogueAdjudicator.OUTCOME_TERMS:
		return "bargaining"
	if kind == DialogueAdjudicator.OUTCOME_HIRE:
		match String(outcome.get("disposition", "refuse")):
			"accept_elan", "accept":
				return "eager"
			"try_again":
				return "haggling"
			"refuse_slander":
				return "affronted"
			_:
				return "reluctant"
	return "neutral"


## Engine-generated must_say facts (§13.9 "informationally complete"). Phase 1
## keeps these compact; templates already carry the phrasing.
static func _must_say(outcome: Dictionary) -> Array:
	var out: Array = []
	if outcome.get("becomes_combat", false):
		out.append("turns hostile and moves to attack")
	elif outcome.get("kind", "") == DialogueAdjudicator.OUTCOME_RUMOR:
		out.append("shares a rumor: %s" % outcome.get("rumor_text", ""))
	# --- Dialogue Phase 2 ---
	elif outcome.get("kind", "") == DialogueAdjudicator.OUTCOME_KNOWLEDGE:
		var entry: Dictionary = outcome.get("knowledge", {})
		out.append("discloses: %s" % String(entry.get("fact", "what they know")))
	elif outcome.get("kind", "") == DialogueAdjudicator.OUTCOME_HIRE:
		var disp := String(outcome.get("disposition", "refuse"))
		if disp == "accept" or disp == "accept_elan":
			out.append("agrees to take service")
		elif disp == "refuse_slander":
			out.append("refuses and will speak ill of them")
	return out
