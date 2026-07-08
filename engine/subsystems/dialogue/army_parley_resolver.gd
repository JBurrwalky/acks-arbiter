class_name ArmyParleyResolver
extends RefCounted

## Army pre-battle / siege-lull parley (gdd-npc-dialogue.md §10.4). DaW has no
## envoy/surrender mechanic (corpus-confirmed gap) — this constructs one from
## sacred parts: each demand is a §6.5 per-issue reaction (PerIssueResolver) whose
## modifier stack is fed RAW-priced evidence lines from the ACTUAL army context.
##
## When: at army collision, after reaction/stance resolution and BEFORE deployment
## (gdd-army-warfare.md §6 pre-battle pause), or a siege lull. NEVER mid-battle
## (ax_reactions:7). Who: the opposing command_character_id (a real NPC).
##
## Demands (the party is the DEMANDER, the NPC commander the target):
##   demand_surrender / demand_tribute -> INTIMIDATION (ax_reactions:167-205):
##     outnumbering ratios from real BR (:167-189), commander Morale Score
##     subtracting (:181), loss-of-face for proud commanders (:193), siege/terrain
##     disadvantage (:173,190).
##   offer_passage / offer_terms_parley -> DIPLOMATIC with favors/authority lines.
##
## Success tiers -> battle directive (rule 10.2 — dialogue NEVER touches battle
## math; it only cancels/schedules events and emits signals):
##   accept(_enthusiastic) -> "cancel"    (army withdraws/accepts; battle events
##                                          cancelled, tribute/withdrawal scheduled)
##   negotiable / refuse   -> "proceed"   (parley ends, battle proceeds)
##   refuse_flat (roll 2)  -> "immediate" (talks collapse, battle immediate)
##
## No LLM. Deterministic (injectable dice).

const DEMAND_SURRENDER := "demand_surrender"
const DEMAND_TRIBUTE := "demand_tribute"
const OFFER_PASSAGE := "offer_passage"
const OFFER_TERMS := "offer_terms_parley"

const DEMANDS := [DEMAND_SURRENDER, DEMAND_TRIBUTE, OFFER_PASSAGE, OFFER_TERMS]

const DIRECTIVE_CANCEL := "cancel"
const DIRECTIVE_PROCEED := "proceed"
const DIRECTIVE_IMMEDIATE := "immediate"


## Resolve one parley demand. Returns a Dictionary:
##   { demand_id, tone, band, success_tier, directive, per_issue, evidence,
##     followups }
## [param army_ctx] keys (all optional, defaulted safely):
##   { attacker_br: float, defender_br: float, commander_morale_score: int,
##     commander_proud: bool, defender_besieged: bool, terrain_disadvantage: bool,
##     defender_in_own_lair: bool, party_has_authority: bool,
##     favors_owed_by_commander: int, tribute_gp: int }
## [param base_ctx] is the resolver context to extend (CHA etc.); [param terms_mod]
## the ±1 from a prior offer_terms; [param dice] the injectable roll.
static func resolve_demand(demand_id: String, army_ctx: Dictionary,
		base_ctx: Dictionary, current_attitude: String,
		terms_mod: int = 0, dice = null) -> Dictionary:
	var tone := _tone_for(demand_id)
	var ctx: Dictionary = base_ctx.duplicate(true)
	var evidence: Array = _apply_evidence(ctx, tone, demand_id, army_ctx)

	var res: Dictionary = PerIssueResolver.resolve(
		tone, current_attitude, ctx, terms_mod, 0, dice)
	var band := String(res.get("result", PerIssueResolver.RESULT_REFUSE))
	var tier := _success_tier(band)
	var directive := _directive_for(band)
	var followups: Array = _followups_for(demand_id, band, army_ctx)

	return {
		"demand_id": demand_id,
		"tone": tone,
		"band": band,
		"success_tier": tier,
		"directive": directive,
		"per_issue": res,
		"evidence": evidence,
		"followups": followups,
	}


## Cancel matching battle events and schedule the parley follow-ups on a SUCCESS
## (directive "cancel"). Degrades gracefully when no scheduler/owner is supplied
## (the collision handler acts instead). Returns { cancelled: int, scheduled: Array }.
## [param scheduler] is an EventScheduler instance; [param battle_owner_id] the
## owner whose battle events are cancelled (a battle_id or army_id).
static func apply_directive(directive: String, followups: Array,
		scheduler = null, battle_owner_id: String = "") -> Dictionary:
	var out := {"cancelled": 0, "scheduled": []}
	if scheduler == null:
		return out
	if directive == DIRECTIVE_CANCEL and not battle_owner_id.is_empty():
		if scheduler.has_method("cancel_all_for_owner"):
			out["cancelled"] = int(scheduler.cancel_all_for_owner(battle_owner_id))
		for f in followups:
			if not (f is Dictionary):
				continue
			if scheduler.has_method("schedule_after"):
				# EventScheduler.schedule_after(current_time, delay_rounds, type, owner, data).
				var ev_id = scheduler.schedule_after(
					Timekeeping.get_total_rounds(),
					int((f as Dictionary).get("delay_rounds", 0)),
					String((f as Dictionary).get("event_type", "")),
					battle_owner_id,
					(f as Dictionary).get("data", {}))
				(out["scheduled"] as Array).append(ev_id)
	return out


# ---------------------------------------------------------------------------
# Evidence assembly (RAW-priced lines from the real army context)
# ---------------------------------------------------------------------------

## Populate the resolver context with the RAW intimidation/diplomatic evidence
## lines the army context supplies. Returns a human-readable evidence list for
## the reply/log. Mutates [param ctx] in place.
static func _apply_evidence(ctx: Dictionary, tone: String, demand_id: String,
		army_ctx: Dictionary) -> Array:
	var evidence: Array = []
	if tone == InteractionResult.TONE_INTIMIDATION:
		# Outnumbering ratio from real BR (ax_reactions:167-189), bumped one tier
		# when the defender is besieged / at terrain disadvantage (:173,190).
		var ratio := _outnumber_from_br(
			float(army_ctx.get("attacker_br", 0.0)),
			float(army_ctx.get("defender_br", 0.0)))
		if bool(army_ctx.get("defender_besieged", false)) \
				or bool(army_ctx.get("terrain_disadvantage", false)):
			ratio = _bump_ratio(ratio)
			evidence.append("the enemy is pinned by siege/terrain (ax_reactions:173,190)")
		if ratio != "even":
			ctx["outnumber_ratio"] = ratio
			evidence.append("we outnumber them %s (ax_reactions:167-189)" % ratio)
		# Commander Morale Score subtracts (ax_reactions:181).
		var morale := int(army_ctx.get("commander_morale_score", 0))
		if morale != 0:
			ctx["target_morale_score"] = morale
			evidence.append("their commander's resolve holds (morale %d, ax_reactions:181)" % morale)
		# Proud commander fears loss of face — harder to cow (ax_reactions:193).
		if bool(army_ctx.get("commander_proud", false)):
			ctx["target_loss_of_face"] = true
			evidence.append("a proud commander who will not be seen to yield (ax_reactions:193)")
		# Defender holding their own stronghold resists (ax_reactions target lair).
		if bool(army_ctx.get("defender_in_own_lair", false)):
			ctx["target_in_own_lair"] = true
			evidence.append("they hold their own ground")
	else:
		# Diplomatic: authority + favors lines (ax_reactions:77-113).
		if bool(army_ctx.get("party_has_authority", false)):
			ctx["has_legal_authority"] = true
			evidence.append("we speak with lawful authority (ax_reactions:89-93)")
		var favors := int(army_ctx.get("favors_owed_by_commander", 0))
		if favors > 0:
			ctx["favors_owed_to_character"] = favors
			evidence.append("the commander owes us %d favor(s)" % favors)
	return evidence


static func _tone_for(demand_id: String) -> String:
	if demand_id == DEMAND_SURRENDER or demand_id == DEMAND_TRIBUTE:
		return InteractionResult.TONE_INTIMIDATION
	return InteractionResult.TONE_DIPLOMATIC


## Map an actual BR ratio (attacker / defender) to the RAW outnumber tier.
static func _outnumber_from_br(attacker_br: float, defender_br: float) -> String:
	if defender_br <= 0.0:
		return "3:1" if attacker_br > 0.0 else "even"
	var ratio := attacker_br / defender_br
	if ratio >= 3.0:
		return "3:1"
	if ratio >= 1.5:
		return "3:2"
	if ratio > 1.0:
		return "plus"
	return "even"


static func _bump_ratio(ratio: String) -> String:
	match ratio:
		"even": return "plus"
		"plus": return "3:2"
		"3:2": return "3:1"
	return ratio


static func _success_tier(band: String) -> String:
	if PerIssueResolver.is_accept(band):
		return "cowed"          # withdraws or accepts terms
	if band == PerIssueResolver.RESULT_NEGOTIABLE:
		return "partial"
	if band == PerIssueResolver.RESULT_REFUSE_FLAT:
		return "collapse"
	return "refused"


static func _directive_for(band: String) -> String:
	if PerIssueResolver.is_accept(band):
		return DIRECTIVE_CANCEL
	if band == PerIssueResolver.RESULT_REFUSE_FLAT:
		return DIRECTIVE_IMMEDIATE
	return DIRECTIVE_PROCEED


## Battle-event follow-ups scheduled on a successful parley (tribute collection,
## withdrawal march). Event types are army-warfare owned; dialogue only schedules.
static func _followups_for(demand_id: String, band: String, army_ctx: Dictionary) -> Array:
	if not PerIssueResolver.is_accept(band):
		return []
	match demand_id:
		DEMAND_SURRENDER:
			return [{"event_type": "army_surrender", "delay_rounds": 0, "data": {}}]
		DEMAND_TRIBUTE:
			return [{"event_type": "army_tribute_collected", "delay_rounds": 0,
				"data": {"tribute_gp": int(army_ctx.get("tribute_gp", 0))}}]
		OFFER_PASSAGE, OFFER_TERMS:
			return [{"event_type": "army_withdrawal", "delay_rounds": 0, "data": {}}]
	return []
