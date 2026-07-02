class_name RaiseGarrisonHandler
extends RefCounted

## raise_garrison — the planner-level COMPOSITE intent (gdd-ruler-ai.md §5.2,
## approved §11): fund the domain's garrison up by wrapping the EXISTING
## recruitment handlers. Keyed on state.character_id -> owner_character_id
## like every domain handler.
##
## RAW basis: a ruler must spend >= 2gp per peasant family per month on troops
## (acore_axioms_strongholds_and_domains.xml:216-234; clanholds add +2gp via
## ax_domains_of_chaos §exceptions_from_clanholds, surfaced by
## GarrisonExpenditureCalculator). Under-garrison bleeds -1 morale per
## gp/family short each month (:486). A wilderness domain additionally wants
## 4gp/family or its base morale suffers (:233) — the composite treats that as
## the wilderness funding target (shared trigger:
## RulerActionCatalog.garrison_needs_raising).
##
## Composition strategy (PROJECT CALL, deterministic ordering):
##   * clanhold domains: levy tribal warriors and assign them to the garrison
##     (levy_militia/conscript_troops are RAW-blocked for clanholds,
##     ax_domains_of_chaos.xml:36; the tribal levy is the clanhold equivalent
##     path, ax_domains_of_chaos.xml:417-444 via LevyTribalWarriorsHandler).
##   * everyone else: CONSCRIPTS first — RAW levies conscripts "without
##     affecting domain morale or revenue" (daw_armies_recruitment.xml:315),
##     while each levied militiaman reduces domain revenue by one family and
##     imposes a morale hit until sent home (:429-431) — then militia (the
##     bigger pool, 2 per 10 families vs 1 per 10) only if still short.
##   * still short after the levy pools (or an empty tribal pool): START the
##     RAW mercenary pipeline via solicit_mercenaries
##     (ax_campaign_play.xml:689-704). Hiring itself requires a prior
##     successful solicitation (:566), so offers land as
##     mercenary_offers_pending for a later month — the composite does
##     everything RAW allows in one month and reports the residual honestly.
##
## Each wrapped handler re-checks its own preconditions (clanhold blocks etc.),
## so this composite cannot bypass a RAW gate. Wrapped handlers receive a
## CLEAN state carrying only character_id — params_json addressed to
## raise_garrison itself must not leak into their _parse_params.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "raise_garrison: ruler has no domain"}
	var domain: Dictionary = _get_domain(domain_id)
	if domain.is_empty():
		return {"summary": "raise_garrison: domain not found"}

	var before: Dictionary = GarrisonExpenditureCalculator.compute_from_domain(domain)
	if not RulerActionCatalog.garrison_needs_raising(before):
		return {
			"summary": "raise_garrison: garrison already at its funding target",
			"blocked_reason": "already_at_minimum",
		}

	var delegate_state := {"character_id": character_id}
	var is_clanhold: bool = String(domain.get("domain_style", "civilized")) == "clanhold"
	var steps: Array = []
	if is_clanhold:
		_levy_tribal_into_garrison(delegate_state, domain_id, steps)
	else:
		# Conscripts first (no morale/revenue cost per daw_armies_recruitment
		# :315), then the larger militia pool if still short.
		steps.append({"step": "conscript_troops",
			"result": ConscriptTroopsHandler.on_complete(delegate_state, _runner)})
		if RulerActionCatalog.garrison_needs_raising(
				GarrisonExpenditureCalculator.compute(domain_id)):
			steps.append({"step": "levy_militia",
				"result": LevyMilitiaHandler.on_complete(delegate_state, _runner)})

	# Levy pools exhausted and still short -> start the mercenary pipeline
	# (solicitation this month; hiring needs the resulting offers, RAW :566).
	var solicited := false
	if RulerActionCatalog.garrison_needs_raising(
			GarrisonExpenditureCalculator.compute(domain_id)):
		steps.append({"step": "solicit_mercenaries",
			"result": SolicitMercenariesHandler.on_complete(delegate_state, _runner)})
		solicited = true

	var after: Dictionary = GarrisonExpenditureCalculator.compute(domain_id)
	var at_target: bool = not RulerActionCatalog.garrison_needs_raising(after)
	var summary: String
	if at_target:
		summary = "Garrison raised to its funding target (%d cp/family)" % \
			int(after.get("cp_per_family_value", 0))
	elif solicited:
		summary = ("Garrison raised but still short of its target; mercenaries "
			+ "solicited (offers pending a later month per RAW hiring flow)")
	else:
		summary = "Garrison raised but still short of its target"

	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": _calendar_day(),
		"category": "garrison",
		"subcategory": "raise_garrison_composite",
		"cp_amount": 0,
		"description": summary,
	})
	return {
		"summary": summary,
		"meets_minimum": bool(after.get("meets_minimum", false)),
		"at_target": at_target,
		"solicited_mercenaries": solicited,
		"steps": steps,
		"garrison_before": before,
		"garrison_after": after,
	}


## Clanhold path: levy tribal warriors, then flip the levied units from
## 'available' to 'garrison' so they count toward garrison expense
## (GarrisonExpenditureCalculator counts garrison-assigned units only).
static func _levy_tribal_into_garrison(delegate_state: Dictionary, domain_id: String,
		steps: Array) -> void:
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(delegate_state, null)
	steps.append({"step": "levy_tribal_warriors", "result": result})
	var unit_ids: Array = result.get("unit_ids", [])
	for unit_id_v in unit_ids:
		var unit_id: String = String(unit_id_v)
		if not unit_id.is_empty():
			TroopUnitRepository.update_unit(unit_id, {"assignment_kind": "garrison"})
	if not unit_ids.is_empty():
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id,
			"calendar_day": _calendar_day(),
			"category": "garrison",
			"subcategory": "tribal_warriors_garrisoned",
			"cp_amount": 0,
			"description": "Levied tribal warriors assigned to the garrison",
		})


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


static func _get_domain(domain_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ? LIMIT 1", [domain_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
