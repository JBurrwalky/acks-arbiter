class_name ThreatEscalationDriver
extends RefCounted

## Phase F — Route 1: NPC challenger escalation (gdd-army-warfare.md §4.10.2).
##
## Closes the gap where an `npc_challenger` threat row emerges on an NPC-owned domain and then
## sits unfielded forever (no player is watching to press the threats-sub-tab buttons). Runs in
## the monthly tick AFTER RulerAI.process_campaign_month, ONLY for NPC rulers in the active-LOD
## set (the same `active_ruler_ids` passed to RulerAI). Per the ruler's personal domain:
##
##   1. Field the challenger — RAW "offers battle at the first opportunity"
##      (acore_axioms_strongholds_and_domains.xml:627-630). Reuses
##      NPCChallengerEmergence.materialize_challenger_as_army (idempotent).
##   2. The defender answers via the §7.3 resistance decision — the SAME machinery as
##      defensive_resistance (ExtractionResistanceHeuristic.evaluate + the ruler's disposition).
##      Accept → mirror the threats-sub-tab dispatch EXACTLY: stronghold present →
##      SiegeDispatcher.dispatch_new_siege (the challenger besieges); no stronghold →
##      BattleDispatcher.dispatch_collision (garrison vs challenger). NPC-vs-NPC resolves silently.
##   3. Refuse → RAW pillage: stamp morale_penalty = 4 (positive; domain_handlers subtracts it),
##      re-offered each month until the ruler accepts, the challenger is defeated, or the domain
##      lifecycle resolves it.
##
## Scope guards (§4.10.1/§4.10.4): runs ONLY for active-LOD NPC domains (player domains and
## backdrop domains are never in `active_ruler_ids`); processes ONLY `npc_challenger` threats
## (bandit swarms never initiate a siege in v1); NEVER as a planner action (it acts on threat
## artifacts, not ruler decisions). Stateless between ticks — re-derives from the threat row +
## payload_json bookkeeping. No migration; no scheduler events of its own (the dispatched
## siege/battle owns its ticks).
##
## Public API:
##   process_campaign_month(campaign_id, calendar_day, active_ruler_ids, scheduler=null) -> Array

static func process_campaign_month(campaign_id: String, calendar_day: int,
		active_ruler_ids: Array, scheduler = null) -> Array:
	var results: Array = []
	if campaign_id.is_empty() or active_ruler_ids.is_empty():
		return results
	for ruler_id_v in active_ruler_ids:
		var ruler_id := String(ruler_id_v)
		if ruler_id.is_empty():
			continue
		var domain := _personal_domain_for_ruler(ruler_id)
		if domain.is_empty():
			continue
		var outcome := _escalate_domain_challenger(domain, ruler_id, calendar_day, scheduler)
		if not outcome.is_empty():
			results.append(outcome)
	return results


# ---------------------------------------------------------------------------
# Per-domain escalation
# ---------------------------------------------------------------------------

static func _escalate_domain_challenger(domain: Dictionary, ruler_id: String,
		calendar_day: int, scheduler) -> Dictionary:
	var domain_id := String(domain.get("id", ""))
	var challenger := DomainThreatRepository.get_active_challenger_for_domain(domain_id)
	if challenger.is_empty():
		return {}
	# §4.10.4 — ONLY npc_challenger escalates; bandit swarms stay raiders.
	if String(challenger.get("kind", "")) != "npc_challenger":
		return {}
	var threat_id := String(challenger.get("id", ""))
	var payload := _parse_payload(challenger)
	# Idempotence: once converted to a siege/battle, never re-dispatch.
	if payload.has("dispatched_day"):
		return {}

	# 1. Field the challenger (idempotent — returns the existing army when already fielded).
	var already_fielded := not _linked_army_id(challenger).is_empty()
	var challenger_army := NPCChallengerEmergence.materialize_challenger_as_army(threat_id)
	if challenger_army.is_empty():
		return {}
	if not already_fielded:
		_emit(threat_id, domain_id, "fielded")

	# 2. The defender answers via the §7.3 resistance decision (accept = will_resist).
	# NOTE on defending_own_stronghold=false: in the extraction-resistance heuristic that term
	# adds +0.10 to the threshold ratio — i.e. it makes "resist" (a field SORTIE) HARDER, modelling
	# a stronghold-holder who prefers to hole up rather than sortie. In the challenger case "accept"
	# with a stronghold present is a siege-DEFENCE (hold the walls), not a sortie, so applying that
	# +0.10 would perversely make a stronghold-holder MORE likely to refuse and be pillaged. We
	# therefore use the disposition baseline (false) — the disposition terms drive accept/refuse.
	var disposition: Variant = RulerDispositionRepository.get_disposition(ruler_id)
	var evaluation: Dictionary = ExtractionResistanceHeuristic.evaluate(
		domain_id, challenger_army, calendar_day, null,
		{"disposition": disposition, "defending_own_stronghold": false})
	_emit(threat_id, domain_id, "battle_offered")
	payload["offered_day"] = calendar_day

	var out := {"threat_id": threat_id, "domain_id": domain_id, "challenger_army_id": challenger_army}
	if bool(evaluation.get("will_resist", false)):
		# 3a. Accept — dispatch exactly like the threats sub-tab.
		var dispatch := _dispatch_accept(challenger_army, domain, challenger, calendar_day, scheduler)
		payload["dispatched_day"] = calendar_day
		payload["dispatch_kind"] = String(dispatch.get("kind", ""))
		out["decision"] = "accept"
		out["dispatch"] = dispatch
		_emit(threat_id, domain_id,
			"siege_started" if String(dispatch.get("kind", "")) == "siege" else "battle_offered")
	else:
		# 3b. Refuse — RAW pillage (-4 morale, stored positive; domain_handlers subtracts it).
		DomainThreatRepository.update(threat_id, {"morale_penalty": 4})
		payload["refused_day"] = calendar_day
		payload["refused_count"] = int(payload.get("refused_count", 0)) + 1
		out["decision"] = "refuse"
		_emit(threat_id, domain_id, "battle_refused")

	DomainThreatRepository.update(threat_id, {"payload_json": JSON.stringify(payload)})
	return out


## Mirror encounters_threats_sub_tab's accept-dispatch: stronghold → the challenger besieges;
## no stronghold → a field battle between the garrison and the challenger.
static func _dispatch_accept(challenger_army: String, domain: Dictionary,
		challenger: Dictionary, calendar_day: int, scheduler) -> Dictionary:
	var domain_id := String(domain.get("id", ""))
	var stronghold_id := _stronghold_for_domain(domain_id)
	var garrison_id := _garrison_army_for_stronghold(stronghold_id)
	if stronghold_id.is_empty():
		# Read the battle hex from the MATERIALISED army (materialize positions it at the threat
		# hex or the domain's stronghold hex) — the threat row's linked_hex_q/r may still be NULL
		# for a never-before-fielded challenger, which would drop the battle onto (0,0).
		var challenger_army_row: Dictionary = ArmyRepository.get_army(challenger_army)
		var hex_q := int(challenger_army_row.get("hex_q", 0)) if challenger_army_row.get("hex_q") != null else 0
		var hex_r := int(challenger_army_row.get("hex_r", 0)) if challenger_army_row.get("hex_r") != null else 0
		var battle := BattleDispatcher.dispatch_collision(garrison_id, challenger_army, hex_q, hex_r, calendar_day)
		return {"kind": "battle", "battle_id": String(battle.get("battle_id", "")), "mode": String(battle.get("mode", ""))}
	var siege := SiegeDispatcher.dispatch_new_siege(challenger_army, stronghold_id, garrison_id, calendar_day, scheduler)
	return {"kind": "siege", "siege_id": String(siege.get("siege_id", "")), "mode": String(siege.get("mode", ""))}


# ---------------------------------------------------------------------------
# Lookups (replicate the threats-sub-tab helpers — those are scene-private)
# ---------------------------------------------------------------------------

static func _personal_domain_for_ruler(ruler_id: String) -> Dictionary:
	if ruler_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[ruler_id]) or CampaignRepository.db.query_result.is_empty():
		return {}
	var domain_id := String(CampaignRepository.db.query_result[0].get("id", ""))
	var domain := CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return {}
	if String(domain.get("lifecycle_state", "active")) in ["abandoned", "salted_to_ruin", "succession_pending"]:
		return {}
	return domain


static func _stronghold_for_domain(domain_id: String) -> String:
	if domain_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM strongholds WHERE domain_id = ? AND status != 'destroyed' LIMIT 1",
		[domain_id]) or CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _garrison_army_for_stronghold(stronghold_id: String) -> String:
	if stronghold_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM armies
		WHERE garrison_stronghold_id = ? AND state != 'disbanded'
		ORDER BY formed_calendar_day DESC LIMIT 1
	""", [stronghold_id]) or CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _linked_army_id(threat: Dictionary) -> String:
	var v: Variant = threat.get("linked_army_id")
	return "" if v == null else String(v)


static func _parse_payload(threat: Dictionary) -> Dictionary:
	var raw := String(threat.get("payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func _emit(threat_id: String, domain_id: String, stage: String) -> void:
	if EventBus.has_signal("threat_escalated"):
		EventBus.emit_signal("threat_escalated", threat_id, domain_id, stage)
