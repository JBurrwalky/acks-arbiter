-- Migration 171: settlement_entrances.history_context — per-settlement world-history
-- provenance. The setting→runtime materializer (gdd-setting-runtime-materialization
-- §15.3, Jedidiah principle 3) derives, from setting_events, which cultures/polities
-- ruled this hex in the past plus its founding, and persists it here for the LLM
-- narrator / NPC roleplayer to consume. JSON object; '{}' = no recorded history.
-- (The FULL chronicle remains queryable at runtime via setting_events — already in
-- the savegame scope — at zero migration cost; this column is the per-settlement
-- digest the narrator keys on directly.)
ALTER TABLE settlement_entrances ADD COLUMN history_context TEXT NOT NULL DEFAULT '{}';
