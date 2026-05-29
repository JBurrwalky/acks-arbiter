class_name SiegeDispatcher
extends RefCounted

## Routes new siege events to the right resolver based on participant
## involvement, and handles PC arrival in an in-progress simplified siege
## (escalation to full DaW rules).
##
## Decision tree:
##   - PC, PC henchman, or PC named NPC vassal in either army → SiegeResolver (full)
##   - Stronghold owned by a PC, PC henchman, or PC vassal → SiegeResolver (full)
##   - Otherwise → SiegeResolverSimplified
##
## Public API:
##   dispatch_new_siege(besieging_army_id, stronghold_id, defending_army_id,
##                       calendar_day, scheduler) -> {siege_id, mode}
##   handle_pc_arrival_in_siege_hex(siege_id, arriving_character_id,
##                                    calendar_day, scheduler) -> bool


static func dispatch_new_siege(
	besieging_army_id: String,
	stronghold_id: String,
	defending_army_id: String,
	calendar_day: int,
	scheduler = null,
	weeks_of_warning: int = 0,
	site: String = ""
) -> Dictionary:
	if besieging_army_id.is_empty() or stronghold_id.is_empty():
		return {"siege_id": "", "mode": "", "error": "missing_args"}
	var is_player_involved: bool = _is_player_involved(besieging_army_id, defending_army_id, stronghold_id)
	if is_player_involved:
		var sid: String = SiegeResolver.start_full_siege(
			besieging_army_id, stronghold_id, defending_army_id,
			calendar_day, scheduler, weeks_of_warning, site
		)
		return {"siege_id": sid, "mode": "full", "is_player_involved": true}
	# NPC-vs-NPC: simplified.
	var sid_simple: String = SiegeResolverSimplified.start_simplified_siege(
		besieging_army_id, stronghold_id, defending_army_id,
		calendar_day, site, scheduler
	)
	return {"siege_id": sid_simple, "mode": "simplified", "is_player_involved": false}


## Called when a PC-owned army arrives in a hex containing an in-progress siege.
## If the siege is currently simplified and the arriving character is a PC /
## PC henchman / PC named NPC vassal, escalate to full DaW rules.
##
## Returns true if escalation occurred; false otherwise.
static func handle_pc_arrival_in_siege_hex(siege_id: String, arriving_character_id: String, calendar_day: int, scheduler = null) -> bool:
	if siege_id.is_empty() or arriving_character_id.is_empty():
		return false
	if not SiegeInterventionHandler.should_escalate_on_pc_arrival(siege_id, arriving_character_id):
		return false
	return SiegeInterventionHandler.escalate_to_full(siege_id, calendar_day, scheduler)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _is_player_involved(besieging_army_id: String, defending_army_id: String, stronghold_id: String) -> bool:
	if _army_is_player_involved(besieging_army_id):
		return true
	if not defending_army_id.is_empty() and _army_is_player_involved(defending_army_id):
		return true
	if _stronghold_is_player_owned(stronghold_id):
		return true
	return false


static func _army_is_player_involved(army_id: String) -> bool:
	if army_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT political_owner_id, command_character_id FROM armies WHERE id = ?",
		[army_id]
	):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var row: Dictionary = CampaignRepository.db.query_result[0]
	if _is_pc_or_pc_associate(str(row.get("political_owner_id", ""))):
		return true
	if _is_pc_or_pc_associate(str(row.get("command_character_id", ""))):
		return true
	return false


static func _stronghold_is_player_owned(stronghold_id: String) -> bool:
	if stronghold_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT owner_character_id FROM strongholds WHERE id = ?", [stronghold_id]
	):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var owner_id: String = String(CampaignRepository.db.query_result[0].get("owner_character_id", ""))
	return _is_pc_or_pc_associate(owner_id)


static func _is_pc_or_pc_associate(character_id: String) -> bool:
	## True if PC, PC's henchman, or PC's named NPC vassal.
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT character_type FROM characters WHERE id = ?", [character_id]
	):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var ctype: String = String(CampaignRepository.db.query_result[0].get("character_type", ""))
	if ctype == "pc":
		return true
	if ctype == "henchman":
		if not CampaignRepository.db.query_with_bindings("""
			SELECT 1 FROM henchman_relationships hr
			JOIN characters c ON c.id = hr.lord_character_id
			WHERE hr.henchman_character_id = ? AND c.character_type = 'pc'
			LIMIT 1
		""", [character_id]):
			return false
		return not CampaignRepository.db.query_result.is_empty()
	if ctype == "npc":
		if not CampaignRepository.db.query_with_bindings("""
			SELECT 1 FROM vassal_assignments va
			JOIN characters c ON c.id = va.liege_character_id
			WHERE va.vassal_character_id = ? AND va.status = 'active'
			      AND c.character_type = 'pc'
			LIMIT 1
		""", [character_id]):
			return false
		return not CampaignRepository.db.query_result.is_empty()
	return false
