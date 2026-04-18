-- Migration 034: Schema sweep markers table.
-- Tracks one-time data-fix sweeps that run in GDScript after migrations apply.
-- The actual entity promotion sweep runs via CampaignRepository._sweep_promote_inventory_entities().

CREATE TABLE IF NOT EXISTS schema_sweep_markers (
    sweep_name TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
