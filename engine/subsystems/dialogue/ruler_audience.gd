class_name RulerAudience
extends RefCounted

## Persuading rulers — Seam B, made concrete (gdd-npc-dialogue.md §10.3). A ruler
## audience exposes persuade_ruler(packet); this class adjudicates the packet into
## a deterministic persuasion_strength and routes the effect through Seam B
## (RulerStrategyReassessor.apply_validated) WITHOUT relaxing its validation — an
## unknown target_action_id is strict-rejected exactly as a bad bias key is.
##
## Packet (§10.3):
##   { target_action_id: String,   # MUST exist in RulerActionCatalog.ACTION_IDS
##     direction: "dissuade" | "urge",
##     terms: Dictionary,          # tribute, favors, hostages (concessions)
##     expires_after_months: int } # temporary by rule 10.2
##
## Adjudication -> strength (deterministic). A fresh per-issue reaction roll
## (PerIssueResolver, the archetypal extraordinary issue) with relationship tone
## as modifier. persuasion_strength = issue-band base + terms conceded (capped) +
## crisis_response adjustment. Constants PROJECT CALL (§10.3, §17).
##
## Effects (rule 10.2 — situational modifiers + event cancellations ONLY; never
## rewrites StrategicDisposition/axes/morale):
##   dissuade: matching scheduled events cancelled if strength >= 0.6 else
##             postponed; the action's utility gets a ×(1 - 0.7·strength)
##             situational bias next scoring cycle; emit ruler_strategy_reassessed.
##   urge:     v1 supports urging only v1-catalog (defensive/economic) actions; a
##             ×(1 + 0.7·strength) bias raises the action's utility. Urging
##             OFFENSIVE WAR is ruler-AI v2 — refused gracefully, packet reserved.
##
## No LLM on the mock path (apply_validated is the LLM-free validation+acceptance
## entry). Deterministic (injectable dice).

const DIR_DISSUADE := "dissuade"
const DIR_URGE := "urge"

# Strength formula constants (PROJECT CALL, §10.3).
const BAND_BASE := {
	"accept_enthusiastic": 0.8,
	"accept": 0.6,
	"negotiable": 0.4,
}
const CONCESSION_STEP := 0.1
const CONCESSION_CAP := 0.3
const CRISIS_DIPLOMATIC_BONUS := 0.2
const CRISIS_AGGRESSIVE_PENALTY := 0.2
const DISSUADE_CANCEL_THRESHOLD := 0.6
const UTILITY_FACTOR := 0.7

# Urging these is ruler-AI v2 (offensive war) — refuse gracefully (§10.3, §17).
const OFFENSIVE_URGE_ACTIONS := ["declare_war", "issue_ultimatum"]

const TRIGGER := "player_parley"


## Adjudicate a persuade_ruler packet and route the effect through Seam B.
## Returns a Dictionary:
##   { rejected: bool, reason?, strength, band, direction, target_action_id,
##     cancelled_events, postponed, reassess, per_issue }
## [param scheduler] is an optional EventScheduler (dialogue injects
## context.deps.event_scheduler); when absent, cancellation degrades to a
## directive the caller acts on.
static func persuade(ruler_npc_id: String, packet: Dictionary,
		resolver_ctx: Dictionary, current_attitude: String,
		crisis_response: String = "", scheduler = null, dice = null) -> Dictionary:
	var target := String(packet.get("target_action_id", ""))
	var direction := String(packet.get("direction", DIR_DISSUADE))
	var terms: Dictionary = packet.get("terms", {})

	# §10.2 rule 1: the target action must exist in the ruler action vocabulary.
	if not RulerActionCatalog.ACTION_IDS.has(target):
		return {"rejected": true, "reason": "unknown_target_action",
			"target_action_id": target}
	if direction != DIR_DISSUADE and direction != DIR_URGE:
		return {"rejected": true, "reason": "unknown_direction"}
	# Urging offensive war is v2 — refuse gracefully, reserve the packet shape.
	if direction == DIR_URGE and target in OFFENSIVE_URGE_ACTIONS:
		return {"rejected": true, "reason": "urge_offensive_war_is_v2",
			"target_action_id": target, "packet_reserved": true}

	# Adjudication: fresh per-issue reaction roll (extraordinary issue).
	var res: Dictionary = PerIssueResolver.resolve(
		"diplomatic", current_attitude, resolver_ctx, 0, 0, dice)
	var band := String(res.get("result", PerIssueResolver.RESULT_REFUSE))
	var strength := _strength_for(band, terms, crisis_response)

	var out := {
		"rejected": false,
		"strength": strength,
		"band": band,
		"direction": direction,
		"target_action_id": target,
		"cancelled_events": 0,
		"postponed": false,
		"per_issue": res,
		"reassess": {},
	}
	if strength <= 0.0:
		# Failed to persuade — no situational nudge, no cancellation.
		return out

	# Effects.
	if direction == DIR_DISSUADE:
		var mult := clampf(1.0 - UTILITY_FACTOR * strength, 0.25, 4.0)
		out["reassess"] = _seam_b_bias(ruler_npc_id, target, mult)
		if strength >= DISSUADE_CANCEL_THRESHOLD:
			out["cancelled_events"] = _cancel_events(scheduler, ruler_npc_id, target)
		else:
			out["postponed"] = true
	else:  # urge (v1 defensive/economic only)
		var mult_urge := clampf(1.0 + UTILITY_FACTOR * strength, 0.25, 4.0)
		out["reassess"] = _seam_b_bias(ruler_npc_id, target, mult_urge)
	return out


## persuasion_strength = issue-band base + terms conceded (capped) + crisis
## adjustment. Clamped 0..1. Refuse bands yield 0.
static func _strength_for(band: String, terms: Dictionary,
		crisis_response: String) -> float:
	if not BAND_BASE.has(band):
		return 0.0
	var s: float = float(BAND_BASE[band])
	# +0.1 per meaningful concession, capped.
	var concessions := _count_concessions(terms)
	s += minf(float(concessions) * CONCESSION_STEP, CONCESSION_CAP)
	# Ruler crisis_response.
	if crisis_response == "diplomatic":
		s += CRISIS_DIPLOMATIC_BONUS
	elif crisis_response == "aggressive":
		s -= CRISIS_AGGRESSIVE_PENALTY
	return clampf(s, 0.0, 1.0)


## Count the meaningful concessions in a terms package (non-empty tribute/favor/
## hostage entries).
static func _count_concessions(terms: Dictionary) -> int:
	var n := 0
	for key in terms:
		var v: Variant = terms[key]
		if v == null:
			continue
		if v is int or v is float:
			if float(v) > 0.0:
				n += 1
		elif v is String:
			if not (v as String).is_empty():
				n += 1
		elif v is bool:
			if v:
				n += 1
		else:
			n += 1
	return n


## Route the situational bias through Seam B without relaxing validation. The
## reassessor strict-rejects an unknown action key (incl. bare issue_decree), so
## this is the SAME gate the live path uses. Returns the reassess result.
static func _seam_b_bias(ruler_npc_id: String, target_action_id: String,
		mult: float) -> Dictionary:
	return RulerStrategyReassessor.apply_validated(ruler_npc_id, TRIGGER, {
		"suggested_biases": {target_action_id: mult},
	})


## Cancel matching scheduled events (invasion_preparation + the target action's
## own event) owned by the ruler. Returns the total cancelled. No-op (0) when no
## scheduler is supplied.
static func _cancel_events(scheduler, ruler_npc_id: String,
		target_action_id: String) -> int:
	if scheduler == null or not scheduler.has_method("cancel_all_for_owner"):
		return 0
	var total := 0
	total += int(scheduler.cancel_all_for_owner(ruler_npc_id, target_action_id))
	total += int(scheduler.cancel_all_for_owner(ruler_npc_id, "invasion_preparation"))
	return total
