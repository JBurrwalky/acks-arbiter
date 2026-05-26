class_name CharacterRetentionHelper
extends RefCounted

## Stage H of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` Q-UGS-58 (v1.14).
##
## Pure-function predicate consulted by PoiCleanup to decide whether an
## `npc_role='on_demand'` character has been "retained" by any party
## member, in which case the cleanup sweep should NOT delete the row.
##
## A character is retained iff ANY of:
##   * `character_type` is 'pc' or 'henchman' — direct PC relationship.
##   * `npc_role` is upgraded above 'on_demand' (i.e. 'henchman',
##     'specialist', 'named_npc', 'stocked', 'baseline_placeholder', or
##     'player') — some party-interaction state promoted the NPC.
##   * `employer_id` is non-NULL — character has been hired by another
##     character (PC or NPC). Catches specialist-hire paths and direct
##     henchman wiring on the characters table itself.
##
## v1 doesn't yet consult quest_rumors / journal_entries / other
## retention surfaces — when those tables are wired into the campaign,
## extend this predicate. The check returns true conservatively when in
## doubt; the only failure mode of a false positive is "kept a NPC row
## the player won't ever interact with again", which is a small data-
## bloat issue, not a correctness one.


## Returns true iff the character should NOT be cleaned up by a
## party-departure or session-boundary sweep.
static func is_character_retained(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	var character: Dictionary = CampaignRepository.get_character(character_id)
	if character.is_empty():
		# Already deleted or never existed; no retention concern.
		return false
	# PC / henchman is the obvious retention.
	var character_type: String = String(character.get("character_type", ""))
	if character_type == "pc" or character_type == "henchman":
		return true
	# npc_role upgraded beyond 'on_demand'.
	var npc_role: String = String(character.get("npc_role", ""))
	if npc_role != "on_demand" and not npc_role.is_empty():
		return true
	# Employed by another character (hired specialist, etc.).
	var employer_v: Variant = character.get("employer_id", null)
	if employer_v != null and not String(employer_v).is_empty():
		return true
	return false
