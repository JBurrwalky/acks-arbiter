class_name HireMercenariesHandler
extends RefCounted

## hire_mercenaries handler. Singular minor activity per ax_campaign_play.xml
## §hire_mercenaries L559-571. After offer is made, 2d6 reaction roll on the
## Reaction to Hiring Offer table. Phase 3 rolls the reaction and ledgers the
## outcome; the existing Settlement HiringPanel cross-activates this handler
## via ActivityTimeCostExecutor.launch.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var reaction: int = DiceSystem.roll_digital(6, 2, 0, "hire_mercenaries").modified_total
	var outcome: String = _interpret_reaction(reaction)

	# Ledger to the ruler's domain if there is one; mercs hired by non-rulers
	# don't ledger here (the HiringPanel will track those separately).
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if not domain_id.is_empty():
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id,
			"calendar_day": _calendar_day(),
			"category": "other",
			"subcategory": "hire_mercenaries_offer",
			"cp_amount": 0,
			"description": "Hiring offer reaction: %d (%s)" % [reaction, outcome],
		})
	return {
		"summary": "Hiring offer reaction: %d — %s" % [reaction, outcome],
	}


static func _interpret_reaction(roll: int) -> String:
	# 2d6 Reaction to Hiring Offer (RAW table compressed):
	#   2     hostile (offer rejected, may attack)
	#   3-5   refused
	#   6-8   neutral (negotiate)
	#   9-11  accepted
	#   12    enthusiastic (accepted with bonus)
	if roll <= 2:    return "hostile"
	elif roll <= 5:  return "refused"
	elif roll <= 8:  return "neutral"
	elif roll <= 11: return "accepted"
	return "enthusiastic"


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


static func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
