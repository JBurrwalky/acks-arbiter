class_name RulerAiStateRepository
extends RefCounted

## CRUD for the `ruler_ai_state` table (migration 182) — per-ruler planner
## runtime state, one row per NPC ruler the LOD system has ever activated
## (gdd-ruler-ai.md §10): LOD tier ('active'/'backdrop', §8.1), the §8.2
## demotion-grace stamp (demotion_pending_day; NULL = not pending), the last
## strategic turn (day + top-scored action id), and a small JSON narration
## cache keyed "%d|%s" % [calendar_day, action_id] (§9.1 — avoid re-narrating).
##
## Public API (all static):
##   get_state(character_id) -> Dictionary                # {} when absent
##   upsert(campaign_id, character_id, fields) -> bool    # merge-update
##   active_ruler_ids(campaign_id) -> Array               # lod_tier = 'active'
##   delete_state(character_id) -> bool

## Columns upsert() accepts in [param fields]; anything else is ignored
## (character_id/campaign_id are keys, created_at/updated_at are SQL-managed).
const _UPSERT_FIELDS := [
	"lod_tier", "last_strategic_turn_day", "last_action_id",
	"demotion_pending_day", "narration_cache",
]


## The full row as a Dictionary; {} when the ruler has no state row yet.
## demotion_pending_day reads back as null (not 0) when not pending.
static func get_state(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM ruler_ai_state WHERE character_id = ?", [character_id]
	) or CampaignRepository.db.query_result.is_empty():
		return {}
	return (CampaignRepository.db.query_result[0] as Dictionary).duplicate()


## Merge-update: reads the existing row (if any), overlays the whitelisted
## [param fields], and writes the whole row back (INSERT OR REPLACE on the
## character_id PK). Setting demotion_pending_day to null clears the stamp.
static func upsert(campaign_id: String, character_id: String, fields: Dictionary) -> bool:
	if campaign_id.is_empty() or character_id.is_empty():
		push_error("RulerAiStateRepository.upsert: campaign_id and character_id are required")
		return false
	var row: Dictionary = get_state(character_id)
	var merged: Dictionary = {
		"lod_tier": String(row.get("lod_tier", "backdrop")),
		"last_strategic_turn_day": int(row.get("last_strategic_turn_day", 0)),
		"last_action_id": String(row.get("last_action_id", "")),
		"demotion_pending_day": row.get("demotion_pending_day", null),
		"narration_cache": String(row.get("narration_cache", "{}")),
	}
	for key in _UPSERT_FIELDS:
		if fields.has(key):
			merged[key] = fields[key]
	if not CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO ruler_ai_state
			(character_id, campaign_id, lod_tier, last_strategic_turn_day,
			 last_action_id, demotion_pending_day, narration_cache,
			 created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, COALESCE(?, datetime('now')), datetime('now'))
	""", [
		character_id, campaign_id,
		String(merged["lod_tier"]),
		int(merged["last_strategic_turn_day"]),
		String(merged["last_action_id"]),
		merged["demotion_pending_day"],
		String(merged["narration_cache"]),
		# REPLACE deletes + reinserts; carry the original created_at through
		# so creation order stays stable (NULL = fresh row -> now).
		row.get("created_at", null),
	]):
		push_error("RulerAiStateRepository.upsert: write failed for character=%s" % character_id)
		return false
	return true


## All character_ids whose persisted LOD tier is 'active', in stable creation
## order — the save/load reconciliation source for RulerLodManager.sync().
static func active_ruler_ids(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT character_id FROM ruler_ai_state
		WHERE campaign_id = ? AND lod_tier = 'active'
		ORDER BY created_at, character_id
	""", [campaign_id]):
		return []
	var out: Array = []
	for row_v in CampaignRepository.db.query_result:
		out.append(String((row_v as Dictionary).get("character_id", "")))
	return out


static func delete_state(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	return CampaignRepository.db.query_with_bindings(
		"DELETE FROM ruler_ai_state WHERE character_id = ?", [character_id])
