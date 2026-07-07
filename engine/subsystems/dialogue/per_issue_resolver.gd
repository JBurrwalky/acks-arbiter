class_name PerIssueResolver
extends RefCounted

## Track-2 per-issue reaction resolver (gdd-npc-dialogue.md §6.5). NEW this phase
## (Phase 1 built only the Track-1 relationship-tone track). When the party asks
## for something out of the ordinary — request_action, parley demands, `if_paid`
## knowledge, hire offers (which use their OWN RAW table, resolved separately),
## any `extraordinary`-flagged move — the NPC's answer to THAT request gets its
## own fresh 2d6 reaction roll, distinct from the relationship reaction.
##
## Resolution (§6.5):
##   2d6
##   + tone-appropriate modifier stack (the REQUEST's framing picks the tone)
##   + relationship modifier (§6.1 already-attitude line)
##   + terms modifier (±1 for better/worse terms via offer_terms, acore_equipment:672-676)
##   + status-differential modifier (§6.5, from StatusProfile tiers)
##
## Result bands (project mapping patterned on the RAW hiring bands,
## acore_equipment:677-690):
##   <=2  refuse_flat   (offense check fires, §6.6)
##   3-5  refuse
##   6-8  negotiable    (offer_terms may re-resolve once, else refuse)
##   9-11 accept
##   12+  accept_enthusiastic
##
## The status-differential modifier applies ONLY here (Track 2), NEVER to the
## sacred tone-track tables (§7.1). Deterministic — injectable dice.

const RESULT_REFUSE_FLAT := "refuse_flat"
const RESULT_REFUSE := "refuse"
const RESULT_NEGOTIABLE := "negotiable"
const RESULT_ACCEPT := "accept"
const RESULT_ACCEPT_ENTHUSIASTIC := "accept_enthusiastic"


## Resolve a per-issue ask. Parameters:
##   [param tone]            "diplomatic" | "intimidation" | "seduction" — the
##                           REQUEST's framing (§6.5), not the relationship tone.
##   [param current_attitude] the live relationship attitude (feeds the §6.1
##                           already-attitude relationship modifier only).
##   [param resolver_ctx]    the sacred-modifier context (CHA, proficiencies,
##                           StatusProfile evidence lines) — same shape
##                           InteractionResolver._apply_sacred_modifiers consumes.
##   [param terms_modifier]  ±1 from offer_terms (acore_equipment:672-676).
##   [param status_modifier] the §6.5 status-differential (StatusProfile.
##                           status_differential_modifier), already computed by
##                           the caller (it needs the NPC tier + relevance).
##   [param dice]            injectable roll(count, sides) for determinism.
##
## Returns a Dictionary:
##   { result, raw_roll, total, tone, modifier_total, terms_modifier,
##     status_modifier, relationship_modifier, breakdown }
static func resolve(tone: String, current_attitude: String, resolver_ctx: Dictionary,
		terms_modifier: int = 0, status_modifier: int = 0, dice = null) -> Dictionary:
	var raw := _roll_2d6(dice)

	# Build the sacred stack for this tone (CHA, proficiencies, evidence lines,
	# and the already-attitude relationship modifier). We reuse the resolver's
	# own assembly by injecting `already_attitude` and letting it apply the
	# sacred categories; reputation is not re-applied here (the tone-track roll
	# owns reputation; the per-issue roll is a FRESH reaction whose modifiers are
	# the request framing + relationship + terms + status, per §6.5).
	var injected := resolver_ctx.duplicate(true)
	injected["already_attitude"] = current_attitude
	var stack := ModifierStack.new()
	InteractionResolver._apply_sacred_modifiers(stack, tone, injected)
	var modifier_total := int(stack.calculate(0))

	# The relationship modifier is included inside modifier_total (via the
	# already_attitude line); expose it separately for transparency/logging.
	var relationship_modifier := InteractionResolver._already_attitude_modifier(tone, current_attitude)

	var total := raw + modifier_total + terms_modifier + status_modifier
	return {
		"result": _band(total),
		"raw_roll": raw,
		"total": total,
		"tone": tone,
		"modifier_total": modifier_total,
		"terms_modifier": terms_modifier,
		"status_modifier": status_modifier,
		"relationship_modifier": relationship_modifier,
		"breakdown": _explain(stack),
	}


static func _band(total: int) -> String:
	if total <= 2:
		return RESULT_REFUSE_FLAT
	if total <= 5:
		return RESULT_REFUSE
	if total <= 8:
		return RESULT_NEGOTIABLE
	if total <= 11:
		return RESULT_ACCEPT
	return RESULT_ACCEPT_ENTHUSIASTIC


## Maps a band to the persisted npc_issues.last_result vocabulary
## (NpcIssueData.RESULTS): refused | negotiable | accepted | accepted_enthusiastic.
static func last_result_for_band(band: String) -> String:
	match band:
		RESULT_REFUSE_FLAT, RESULT_REFUSE:
			return "refused"
		RESULT_NEGOTIABLE:
			return "negotiable"
		RESULT_ACCEPT:
			return "accepted"
		RESULT_ACCEPT_ENTHUSIASTIC:
			return "accepted_enthusiastic"
	return "refused"


## Maps a band to an npc_issues.status transition (open stays open on negotiable;
## accept -> granted; refuse -> refused/open per the ladder). PROJECT CALL: a flat
## or plain refuse keeps the issue OPEN so the per-issue ladder (§6.3) can retry;
## the caller closes it to `refused` only when the ladder is exhausted.
static func status_for_band(band: String) -> String:
	match band:
		RESULT_ACCEPT, RESULT_ACCEPT_ENTHUSIASTIC:
			return "granted"
		_:
			return "open"


static func is_accept(band: String) -> bool:
	return band == RESULT_ACCEPT or band == RESULT_ACCEPT_ENTHUSIASTIC


static func _explain(stack: ModifierStack) -> Array:
	var out: Array = []
	for m in stack.get_all_modifiers():
		out.append({
			"source": m.get("source_id", ""),
			"category": m.get("source_type", ""),
			"value": m.get("value", 0),
		})
	return out


static func _roll_2d6(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(2, 6))
	return (randi() % 6 + 1) + (randi() % 6 + 1)
