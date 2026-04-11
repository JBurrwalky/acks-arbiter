-- Migration 023: Trained creature persistence and creature-level inventory
--
-- Adds trained_creatures table for companion animals (mounts, war animals, etc.).
-- Adds nullable creature_id FK on inventory_items for creature-owned equipment.

CREATE TABLE IF NOT EXISTS trained_creatures (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    party_id TEXT REFERENCES parties(id),
    species_id TEXT NOT NULL,
    purchase_item_key TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL DEFAULT '',
    role TEXT NOT NULL DEFAULT 'L'
        CHECK(role IN ('M', 'WM', 'G', 'H', 'D', 'L', 'WB')),
    tricks_known TEXT NOT NULL DEFAULT '[]',
    trick_limit INTEGER NOT NULL DEFAULT 5,
    morale INTEGER NOT NULL DEFAULT 0,
    handler_id TEXT REFERENCES characters(id) DEFAULT NULL,
    introduced_handlers TEXT NOT NULL DEFAULT '[]',
    hp_current INTEGER NOT NULL DEFAULT 1,
    hp_max INTEGER NOT NULL DEFAULT 1,
    training_complete INTEGER NOT NULL DEFAULT 1 CHECK(training_complete IN (0, 1)),
    is_alive INTEGER NOT NULL DEFAULT 1 CHECK(is_alive IN (0, 1)),
    formation_col INTEGER NOT NULL DEFAULT -1,
    formation_row INTEGER NOT NULL DEFAULT -1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

ALTER TABLE inventory_items ADD COLUMN creature_id TEXT
    REFERENCES trained_creatures(id) DEFAULT NULL;
