class_name RulerDispositionRepository
extends RefCounted

## CRUD for the `ruler_dispositions` table (migration 181) — the persisted
## StrategicDisposition strategic layer, one row per NPC ruler keyed by
## character_id (gdd-ruler-ai.md §10). Rows are a regenerable cache of
## StrategicDispositionBuilder.build() over characters.personality +
## characters.alignment.
##
## Public API (all static):
##   save_disposition(campaign_id, character_id, d) -> bool   # idempotent upsert
##   get_disposition(character_id) -> StrategicDisposition    # null when absent
##   has_disposition(character_id) -> bool
##   delete_disposition(character_id) -> bool
##   list_ruler_ids_for_campaign(campaign_id) -> Array        # character_ids


## Idempotent upsert on the character_id PK. The relational dicts serialize
## to JSON TEXT; StrategicDisposition.from_dict parses them back on read.
static func save_disposition(
	campaign_id: String,
	character_id: String,
	d: StrategicDisposition,
) -> bool:
	if campaign_id.is_empty() or character_id.is_empty() or d == null:
		push_error("RulerDispositionRepository.save_disposition: campaign_id, character_id, and disposition are required")
		return false
	if not CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO ruler_dispositions
			(character_id, campaign_id,
			 motivation_primary, motivation_secondary,
			 epistemic_curiosity, societal_orthodoxy, affective_compassion,
			 stress_reactivity, self_interest, in_group_loyalty, mysticism,
			 research_weight, religious_weight, economic_weight, military_weight,
			 expansion_weight, fortification_weight, diplomatic_weight, oppression_weight,
			 crisis_response, aggression_toward, alliance_preference)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		character_id, campaign_id,
		d.motivation_primary, d.motivation_secondary,
		d.epistemic_curiosity, d.societal_orthodoxy, d.affective_compassion,
		d.stress_reactivity, d.self_interest, d.in_group_loyalty, d.mysticism,
		d.research_weight, d.religious_weight, d.economic_weight, d.military_weight,
		d.expansion_weight, d.fortification_weight, d.diplomatic_weight, d.oppression_weight,
		d.crisis_response,
		JSON.stringify(d.aggression_toward),
		JSON.stringify(d.alliance_preference),
	]):
		push_error("RulerDispositionRepository.save_disposition: upsert failed for character=%s" % character_id)
		return false
	return true


## Returns null when no row exists (a ruler whose disposition has not been
## built yet — callers degrade or trigger a build).
static func get_disposition(character_id: String) -> StrategicDisposition:
	if character_id.is_empty():
		return null
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM ruler_dispositions WHERE character_id = ?", [character_id]
	) or CampaignRepository.db.query_result.is_empty():
		return null
	return StrategicDisposition.from_dict(CampaignRepository.db.query_result[0])


static func has_disposition(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	return CampaignRepository.db.query_with_bindings(
		"SELECT character_id FROM ruler_dispositions WHERE character_id = ?",
		[character_id]
	) and not CampaignRepository.db.query_result.is_empty()


static func delete_disposition(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	return CampaignRepository.db.query_with_bindings(
		"DELETE FROM ruler_dispositions WHERE character_id = ?", [character_id])


## All character_ids with a persisted disposition in the campaign, in stable
## creation order.
static func list_ruler_ids_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT character_id FROM ruler_dispositions
		WHERE campaign_id = ?
		ORDER BY created_at, character_id
	""", [campaign_id]):
		return []
	var out: Array = []
	for row_v in CampaignRepository.db.query_result:
		out.append(String((row_v as Dictionary).get("character_id", "")))
	return out
