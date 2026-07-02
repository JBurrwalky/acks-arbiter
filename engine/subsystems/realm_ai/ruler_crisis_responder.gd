class_name RulerCrisisResponder
extends RefCounted

## Crisis and threat response for the NPC ruler planner — gdd-ruler-ai.md §7.
## Three responsibilities, all deterministic statics:
##
##   1. detect_threats(): classify the §7 threat set for one domain — morale
##      collapse, NPC challenger (accumulating vs materialized), hostile army
##      (a domain_threats row with a linked army), siege, ruined stronghold.
##   2. posture_biases(): the §7.1 crisis_response -> action-bias table plus
##      the §7.2 challenger routing and §7.4 stronghold-loss urgency —
##      returned as {action_key: multiplier} and consumed by
##      RulerActionScorer via ctx["crisis_biases"] (multiplicative, so the
##      §6.1 "apply crisis bias" step composes with scoring while keeping the
##      scorer's deterministic tie-break machinery intact).
##   3. resistance_threshold(): the §7.3 disposition-modulated BR threshold
##      that replaces ExtractionResistanceHeuristic's flat 50% rule.
##
## All numeric constants are PROJECT CALL (§7.1/§7.3 tunable). The
## `diplomatic` posture degrades to `cautious` throughout in v1 (§7.1 —
## no-diplomacy scope; the future gdd-ruler-diplomacy.md replaces the
## degradation with real parley).

# --- §7.3 resistance threshold terms (the RAW-placeholder 0.50 anchor) ---
const RESISTANCE_BASE_RATIO := 0.50
const RESISTANCE_MILITARY_TERM := 0.15   # martial rulers resist from weaker positions
const RESISTANCE_AGGRESSIVE_TERM := 0.10
const RESISTANCE_CAUTIOUS_TERM := 0.15
const RESISTANCE_OWN_STRONGHOLD_TERM := 0.10  # siege advantage emboldens
const RESISTANCE_RATIO_MIN := 0.2
const RESISTANCE_RATIO_MAX := 0.9

# --- §7.1 posture-bias table (PROJECT CALL). Keys are action ids, or
# "action_id|decree_kind" for decree variants (scorer tries the specific key
# first). Applied only while an ACTIVE threat (materialized challenger,
# hostile army, or siege) is present. ---
const _POSTURE_BIASES := {
	# Active defense: resist and muster hard.
	"aggressive": {
		"defensive_resistance": 1.5,
		"call_to_arms": 1.5,
	},
	# Fortify: garrison up, hold the stronghold.
	"defensive": {
		"raise_garrison": 1.5,
		"withstand_siege": 1.5,
		"manage_stronghold": 1.25,
	},
	# Over-prepare and hoard; withdraw rather than meet in the field.
	"cautious": {
		"raise_garrison": 1.5,
		"withstand_siege": 1.5,
		"hold": 1.5,
	},
}

# --- §7.2: a challenger ACCUMULATING (or emerged but not yet fielded as an
# army) — and morale collapse generally — biases STABILITY actions so the
# ruler bleeds the cumulative emergence chance / repairs the tier. The tax
# key is the LOWER-tax lever only (the scorer direction-gates it; boosting a
# raise-tax decree would accelerate the very collapse §7.2 bleeds). ---
const _STABILITY_BIASES := {
	"administer_domain": 1.5,
	"issue_decree|tax": 1.5,
	"raise_garrison": 1.25,
	"repress_population": 1.25,
}

# --- §7.4: stronghold loss/ruin urgency by posture. ---
const _RUIN_BIAS_HARD := 2.0    # aggressive / defensive: rebuild hard, immediately
const _RUIN_BIAS_SOFT := 1.25   # cautious / diplomatic: may hoard before committing


## Classify the §7 threat set for one domain. [param month_result] is the
## tick's per-domain result dict (challenger_summary carries this month's
## accumulation/emergence).
static func detect_threats(domain: Dictionary, month_result: Dictionary = {}) -> Dictionary:
	var domain_id: String = String(domain.get("id", ""))
	var challenger_summary: Dictionary = month_result.get("challenger_summary", {})
	var summary_action: String = String(challenger_summary.get("action", "none"))

	var challenger_materialized: bool = not DomainThreatRepository \
		.get_active_challenger_for_domain(domain_id).is_empty()
	var challenger_accumulating: bool = summary_action == "accumulated" \
		and not challenger_materialized

	# A hostile army in/at the domain: any active threat row with a linked
	# army (a challenger fielded as an army today; extraction/invasion threat
	# writers join in the army-warfare flow).
	var hostile_army: bool = false
	var hostile_army_id: String = ""
	if not domain_id.is_empty() and CampaignRepository.db.query_with_bindings("""
		SELECT linked_army_id FROM domain_threats
		WHERE domain_id = ? AND status = 'active' AND linked_army_id IS NOT NULL
		LIMIT 1
	""", [domain_id]) and not CampaignRepository.db.query_result.is_empty():
		hostile_army_id = String(
			CampaignRepository.db.query_result[0].get("linked_army_id", ""))
		hostile_army = not hostile_army_id.is_empty()

	# Besieged: any non-concluded siege against the domain. The besieging
	# army doubles as the resistance decision's attacker when no threat row
	# supplied one — a besieged ruler must be able to DISPATCH
	# defensive_resistance, not just score it.
	var besieged: bool = false
	if not domain_id.is_empty() and CampaignRepository.db.query_with_bindings("""
		SELECT besieging_army_id FROM sieges
		WHERE domain_id = ? AND current_phase != 'concluded' LIMIT 1
	""", [domain_id]) and not CampaignRepository.db.query_result.is_empty():
		besieged = true
		if hostile_army_id.is_empty():
			hostile_army_id = String(
				CampaignRepository.db.query_result[0].get("besieging_army_id", ""))

	var ruined: bool = String(domain.get("lifecycle_state", "active")) == "ruined_stronghold"
	var morale_collapse: bool = int(domain.get("morale", 0)) <= -3

	return {
		"challenger_accumulating": challenger_accumulating,
		"challenger_materialized": challenger_materialized,
		"hostile_army": hostile_army,
		"hostile_army_id": hostile_army_id,
		"besieged": besieged,
		"ruined_stronghold": ruined,
		"morale_collapse": morale_collapse,
		# The catalog/scorer's "an actual FOE IN THE FIELD" flag. §7.2 routes
		# to defensive actions only when a challenger "has materialized AS AN
		# ARMY" — an emerged challenger with no linked army (the normal NPC
		# post-emergence state; armies materialize via the Phase-9B path) is
		# STABILITY pressure like an accumulator, never a defensive target
		# (an undispatched defensive_resistance would burn the ruler's action
		# slot every month).
		"threat_present": hostile_army or besieged,
	}


## The §7.1/§7.2/§7.4 bias multipliers for one ruler-turn, keyed by action id
## (or "issue_decree|<kind>"). Empty dict when nothing biases.
static func posture_biases(crisis_response: String, threats: Dictionary) -> Dictionary:
	var posture: String = crisis_response
	if posture == "diplomatic":
		posture = "cautious"  # §7.1 v1 degradation
	var out: Dictionary = {}

	if bool(threats.get("threat_present", false)) and _POSTURE_BIASES.has(posture):
		for key in (_POSTURE_BIASES[posture] as Dictionary):
			out[key] = float((_POSTURE_BIASES[posture] as Dictionary)[key])

	# §7.2 stability pressure: an accumulating challenger, an emerged-but-
	# unfielded one (no army to resist yet), or a collapsing morale tier.
	var stability_pressure: bool = bool(threats.get("challenger_accumulating", false)) \
		or (bool(threats.get("challenger_materialized", false))
			and not bool(threats.get("hostile_army", false))) \
		or bool(threats.get("morale_collapse", false))
	if stability_pressure:
		for key in _STABILITY_BIASES:
			out[key] = maxf(float(out.get(key, 1.0)), float(_STABILITY_BIASES[key]))

	if bool(threats.get("ruined_stronghold", false)):
		var ruin_bias: float = _RUIN_BIAS_HARD \
			if posture in ["aggressive", "defensive"] else _RUIN_BIAS_SOFT
		out["manage_stronghold"] = maxf(float(out.get("manage_stronghold", 1.0)), ruin_bias)

	return out


## The §7.3 disposition-modulated resistance threshold ratio.
##
##   0.50 (the RAW-placeholder anchor, gdd-army-warfare.md §4.3.3)
##   - 0.15 x military_weight
##   - 0.10 if crisis_response == "aggressive"
##   + 0.15 if crisis_response == "cautious" (or "diplomatic", §7.1 degradation)
##   + 0.10 if defending_own_stronghold
##   clamped to [0.2, 0.9]
##
## A NULL disposition (backdrop ruler, ownerless domain, pre-planner save)
## degrades to EXACTLY the 0.50 anchor — the regression contract: without a
## disposition the generalized heuristic is byte-identical to the placeholder.
static func resistance_threshold(disposition: StrategicDisposition,
		defending_own_stronghold: bool = false) -> float:
	var ratio: float = RESISTANCE_BASE_RATIO
	if disposition != null:
		ratio -= RESISTANCE_MILITARY_TERM * disposition.military_weight
		if disposition.crisis_response == "aggressive":
			ratio -= RESISTANCE_AGGRESSIVE_TERM
		elif disposition.crisis_response in ["cautious", "diplomatic"]:
			ratio += RESISTANCE_CAUTIOUS_TERM
	if defending_own_stronghold:
		ratio += RESISTANCE_OWN_STRONGHOLD_TERM
	return clampf(ratio, RESISTANCE_RATIO_MIN, RESISTANCE_RATIO_MAX)
