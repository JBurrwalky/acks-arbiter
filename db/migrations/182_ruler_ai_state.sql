-- Migration 182: ruler_ai_state — per-ruler planner runtime state, one row per
-- NPC ruler the Regional-LOD system has ever activated (gdd-ruler-ai.md §10,
-- approved by Jedidiah 2026-06-28). Persists what the Phase-3 in-memory LOD
-- cache could not: the ruler's current LOD tier (§8.1 'active'/'backdrop') for
-- save/load reconciliation, the §8.2 demotion grace stamp (demotion_pending_day
-- is the calendar day the ruler LEFT the play window's geometry; NULL when not
-- pending — the ruler stays active until ~1 month elapses or it re-enters),
-- the last strategic turn taken (day + top-scored action id, written by
-- RulerAI.process_campaign_month), and a small {cache_key: entry} JSON
-- narration cache so Seam-A retroactive narration is not regenerated for the
-- same (day, action) — gdd-ruler-ai.md §9.1. Derived runtime state: a
-- drop-and-rebuild loses only narration cache and grace stamps (the next
-- RulerLodManager.sync regenerates tiers), so it is non-destructive in practice.
CREATE TABLE IF NOT EXISTS ruler_ai_state (
    character_id TEXT PRIMARY KEY REFERENCES characters(id),
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    lod_tier TEXT NOT NULL DEFAULT 'backdrop'
        CHECK(lod_tier IN ('active', 'backdrop')),
    last_strategic_turn_day INTEGER NOT NULL DEFAULT 0,
    last_action_id TEXT NOT NULL DEFAULT '',
    demotion_pending_day INTEGER,
    narration_cache TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ruler_ai_state_campaign
    ON ruler_ai_state(campaign_id);
