class_name DefensiveResistanceHandler
extends RefCounted

## defensive_resistance — the §5.3/§7.3 composite intent (gdd-ruler-ai.md,
## approved §11): decide whether the ruler resists a requisition/loot/invasion
## by battle, using the DISPOSITION-MODULATED generalization of the
## army-warfare extraction-resistance heuristic (which this planner action
## replaces per gdd-army-warfare.md §4.3.3 — the federation + loyalty
## machinery is reused unchanged; without a disposition the threshold is the
## 0.50 placeholder anchor).
##
## The handler produces the DECISION (will_resist + the federated force);
## routing the resulting battle through the army-warfare field-battle
## resolution stays with the extraction flow (ArmyMarcher's resistance
## wiring — still the documented placeholder that credits extraction
## instantly; see Known issues in the 2026-07-02 build-log entry).
##
## params_json: {
##   attacker_army_id: String,            # required — the offending army
##   defending_own_stronghold: bool,      # optional §7.3 +0.10 term
## }


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "defensive_resistance: ruler has no domain"}
	var params: Dictionary = _parse_params(state)
	var attacker_army_id: String = String(params.get("attacker_army_id", ""))
	if attacker_army_id.is_empty():
		return {
			"summary": "defensive_resistance: no attacker army identified",
			"blocked_reason": "no_attacker_army",
		}

	var disposition: StrategicDisposition = \
		RulerDispositionRepository.get_disposition(character_id)
	var evaluation: Dictionary = ExtractionResistanceHeuristic.evaluate(
		domain_id, attacker_army_id, Timekeeping.get_calendar_day(), null, {
			"disposition": disposition,
			"defending_own_stronghold": bool(
				params.get("defending_own_stronghold", false)),
		})

	var will_resist: bool = bool(evaluation.get("will_resist", false))
	var summary: String
	if will_resist:
		summary = "Resistance mustered: %0.1f BR vs attacker %0.1f BR (threshold ratio %0.2f)" % [
			float(evaluation.get("available_br", 0.0)),
			float(evaluation.get("attacker_br", 0.0)),
			float(evaluation.get("threshold_ratio", 0.5)),
		]
	else:
		summary = "Resistance declined (%s): %0.1f BR vs threshold %0.1f BR" % [
			String(evaluation.get("reason", "")),
			float(evaluation.get("available_br", 0.0)),
			float(evaluation.get("threshold_br", 0.0)),
		]

	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": int(evaluation.get("calendar_day", 0)),
		"category": "other",
		"subcategory": "defensive_resistance_decision",
		"cp_amount": 0,
		"description": summary,
	})
	return {
		"summary": summary,
		"will_resist": will_resist,
		"evaluation": evaluation,
	}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[character_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))
