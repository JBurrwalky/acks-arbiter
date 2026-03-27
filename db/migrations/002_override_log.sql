-- Migration 002: Override system tables
-- Adds override_log (immutable audit trail), game_snapshots (session save points),
-- and dungeon_entrances (placed by override or future dungeon generator).

-- override_log: append-only. Never delete rows.
-- override_type values: "character_stat" | "character_xp" | "character_condition" |
--   "character_status" | "inventory_add" | "inventory_remove" | "inventory_gold" |
--   "hex_terrain" | "hex_fog" | "fog_reveal_all" | "fog_hide_all" |
--   "settlement_placed" | "dungeon_placed" | "encounter_spawned" |
--   "dice_queued" | "dice_cleared" | "snapshot_saved" | "snapshot_restored"
CREATE TABLE IF NOT EXISTS override_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    game_day INTEGER NOT NULL DEFAULT 0,
    game_round INTEGER NOT NULL DEFAULT 0,
    applied_at TEXT NOT NULL DEFAULT (datetime('now')),
    override_type TEXT NOT NULL,
    target_id TEXT NOT NULL DEFAULT '',
    field_changed TEXT NOT NULL DEFAULT '',
    old_value TEXT NOT NULL DEFAULT '',
    new_value TEXT NOT NULL DEFAULT ''
);

-- game_snapshots: capped at 10 per campaign (oldest auto-pruned on 11th save).
-- snapshot_data is a JSON blob of all mutable campaign-scoped table rows.
CREATE TABLE IF NOT EXISTS game_snapshots (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    label TEXT NOT NULL,
    snapshot_data TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- dungeon_entrances: placement record for a dungeon at a hex.
-- dungeon_data is JSON; empty until the dungeon layout generator runs.
CREATE TABLE IF NOT EXISTS dungeon_entrances (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    map_id TEXT NOT NULL REFERENCES hex_maps(id),
    hex_q INTEGER NOT NULL,
    hex_r INTEGER NOT NULL,
    name TEXT NOT NULL DEFAULT 'Unknown Dungeon',
    dungeon_data TEXT NOT NULL DEFAULT ''
);
