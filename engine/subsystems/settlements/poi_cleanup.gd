class_name PoiCleanup
extends RefCounted

## Stage H of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §13.8 (v1.14).
##
## Centralized cleanup paths for the POI system:
##
##   * **Q-UGS-58 on-demand NPC sweeps.** When a party leaves a settlement
##     without retaining any of the `npc_role='on_demand'` NPCs that were
##     materialized during the visit (per §5.2 on-demand path), delete
##     those character rows. Also runs at session boundaries as a fallback
##     for any on_demand rows lingering from prior visits.
##   * **Q-UGS-57 spell_offers retention.** Daily sweep that deletes
##     `settlement_poi_spell_offers` rows older than 7 days. Delegates to
##     `SpellOfferRepository.retention_sweep` so the retention window is
##     authoritative in one place.
##   * **Q-UGS-4 abandoned-POI predicate.** Helper used by the Settlement
##     Exploration UI to render "No one here, leave" when a POI's stocked
##     and baseline head NPC slots are both NULL.


## Sweep `npc_role='on_demand'` NPCs whose `home_poi_id` belongs to a POI
## in the given settlement. Skips characters that the retention helper
## says are retained (hired henchmen, named NPCs, employed specialists,
## etc. — see CharacterRetentionHelper for the rules).
##
## Returns the count of deleted characters. Intended to be called from
## the party-departure hook (per `gdd-settlement-exploration-ui.md` exit
## flow) when the party leaves the settlement.
static func party_departure_sweep(settlement_id: String) -> int:
	if settlement_id.is_empty():
		return 0
	var on_demand: Array = CampaignRepository.list_on_demand_characters_for_settlement(
		settlement_id)
	var deleted: int = 0
	for character in on_demand:
		var character_id: String = String(character.get("id", ""))
		if character_id.is_empty():
			continue
		if CharacterRetentionHelper.is_character_retained(character_id):
			continue
		if _delete_character(character_id):
			deleted += 1
	return deleted


## Sweep all `npc_role='on_demand'` rows across the campaign at a session
## boundary (save / load / game-shutdown). Catches rows from prior visits
## that didn't get a party-departure sweep (e.g. mid-visit save / crash).
##
## Returns the count of deleted characters.
static func session_boundary_sweep() -> int:
	var on_demand: Array = CampaignRepository.list_all_on_demand_characters()
	var deleted: int = 0
	for character in on_demand:
		var character_id: String = String(character.get("id", ""))
		if character_id.is_empty():
			continue
		if CharacterRetentionHelper.is_character_retained(character_id):
			continue
		if _delete_character(character_id):
			deleted += 1
	return deleted


## Q-UGS-57 daily spell-offers retention sweep. Wraps
## SpellOfferRepository.retention_sweep for callers (daily-tick hook,
## tests) that prefer the cleanup-module entry point.
static func spell_offers_retention_sweep(
	today_calendar_day: int,
	retention_days: int = 7,
) -> int:
	return SpellOfferRepository.retention_sweep(today_calendar_day, retention_days)


## Q-UGS-4 abandoned-POI predicate. Returns true iff the POI has neither
## a player-stocked character nor a baseline placeholder. The Settlement
## Exploration UI uses this to decide whether to render "No one here,
## leave" in place of the normal POI menu.
static func poi_is_abandoned(poi_id: String) -> bool:
	if poi_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		SELECT stocked_character_id, baseline_head_npc_character_id
		FROM settlement_pois WHERE id = ?
	""", [poi_id]) or CampaignRepository.db.query_result.is_empty():
		return false
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var stocked_v: Variant = row.get("stocked_character_id", null)
	var baseline_v: Variant = row.get("baseline_head_npc_character_id", null)
	var has_stocked: bool = stocked_v != null \
		and not String(stocked_v).is_empty()
	var has_baseline: bool = baseline_v != null \
		and not String(baseline_v).is_empty()
	return not (has_stocked or has_baseline)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Delete a character row. Used by the on_demand sweeps. The schema sets
## the FKs to ON DELETE SET NULL where this character was referenced, so
## no FK violation cascade is needed.
static func _delete_character(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [character_id]):
		return false
	return true
