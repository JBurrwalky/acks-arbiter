-- Migration 021: Party state tracking and party-level inventory support
--
-- Adds party_state table for marching order, travel flags, and rations.
-- Adds nullable party_id column to inventory_items for party-level shared loot.

CREATE TABLE IF NOT EXISTS party_state (
    party_id TEXT PRIMARY KEY REFERENCES parties(id),
    marching_order TEXT NOT NULL DEFAULT '[]',
    is_lost INTEGER NOT NULL DEFAULT 0 CHECK(is_lost IN (0, 1)),
    is_force_marching INTEGER NOT NULL DEFAULT 0 CHECK(is_force_marching IN (0, 1)),
    force_march_days_used INTEGER NOT NULL DEFAULT 0,
    days_since_rest INTEGER NOT NULL DEFAULT 0,
    rations_days_remaining INTEGER NOT NULL DEFAULT 0,
    current_mount_type TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Allow inventory items to belong to a party instead of (or in addition to)
-- a character.  NULL means the item belongs to the character_id as before.
ALTER TABLE inventory_items ADD COLUMN party_id TEXT REFERENCES parties(id) DEFAULT NULL;
