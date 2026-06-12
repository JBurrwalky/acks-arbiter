class_name ExtractDivinePowerHandler
extends RefCounted

## extract_divine_power handler (Phase 10A.2 — Faith block).
##
## Restricted minor activity (weekly cooldown). Per ax_campaign_play.xml
## §extract_divine_power L460-473:
##   - May not be performed more than once per week
##     (restricted_period_rounds = 60480).
##   - Extracts 10gp DP per 50 congregants (i.e. floor(congregants / 5)).
##   - If the caster is the ruler or spiritual advisor of a domain, also
##     extract 0..8 DP per 10 families in the domain (rolled once: 1d9-1).
##   - Requires 50+ congregants.
##   - DP is NOT auto-accumulated per L472: the caster must take this activity
##     each week. The Restricted weekly cooldown enforces the weekly cadence.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "extract_divine_power: no character_id"}

	# Migration 128 (Phase 11D.3): congregants are now per-character-per-domain.
	# Divine-power extraction uses the caster's TOTAL congregation across all
	# domains per RAW ("10 gp per 50 congregants" reads on the caster's whole
	# following), so we sum across domains.
	var congregant_count: int = CampaignRepository.total_congregants_for_character(character_id)
	if congregant_count < 50:
		return {"summary": "extract_divine_power failed: requires 50+ congregants (have %d)" % congregant_count}

	# Congregant-derived DP per RAW: 10 gp per 50 congregants = congregants / 5.
	var base_dp: int = int(congregant_count / 5)

	# Ruler bonus per RAW L470-471: 0..8 DP per 10 families if the caster is
	# the ruler or spiritual advisor of a domain. v1 implements ruler-only;
	# spiritual_advisor relationship modeling is deferred to a future polish.
	var ruler_bonus: int = 0
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if not domain_id.is_empty():
		var domain := _get_domain(domain_id)
		var peasant_families: int = int(domain.get("peasant_families", 0))
		var family_tens: int = int(peasant_families / 10)
		if family_tens > 0:
			# 0..8 per 10 families: roll 1d9-1 per ten-family block? RAW phrasing
			# "between 0 and 8 divine power per 10 families" — interpret as one
			# roll for the whole bonus (uniform 0..8 multiplier on tens), NOT
			# per-10-family roll, since otherwise large domains generate
			# overwhelming DP. Per-domain roll matches the §extract_divine_power
			# weekly-cadence intent.
			var roll_result: RollResult = DiceSystem.roll_digital(9, 1, -1, "extract_divine_power_ruler_bonus")
			var per_ten: int = max(0, roll_result.modified_total)
			ruler_bonus = per_ten * family_tens

	var dp_total_gp: int = base_dp + ruler_bonus
	if dp_total_gp <= 0:
		return {"summary": "extract_divine_power: 0 gp generated this week"}
	# RAW computes DP in gp; convert to cp for the unified storage standard.
	var dp_total_cp: int = dp_total_gp * 100
	var base_dp_cp: int = base_dp * 100
	var ruler_bonus_cp: int = ruler_bonus * 100

	var new_balance: int = CampaignRepository.add_divine_power_cp(character_id, dp_total_cp)
	CampaignRepository.set_divine_power_last_extraction(character_id, _calendar_day())
	EventBus.divine_power_changed.emit(character_id, new_balance, dp_total_cp)

	var summary := "Extracted %s DP (%s from congregants" % [
		Currency.format_cost(dp_total_cp), Currency.format_cost(base_dp_cp),
	]
	if ruler_bonus_cp > 0:
		summary += ", %s from domain families" % Currency.format_cost(ruler_bonus_cp)
	summary += "; new balance %s)" % Currency.format_cost(new_balance)
	return {
		"summary": summary,
		"presentation": {"type": "toast", "text": "DP +%s (extracted)" % Currency.format_cost(dp_total_cp)},
	}


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? LIMIT 1",
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
