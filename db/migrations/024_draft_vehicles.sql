-- Migration 024: Draft vehicles and vehicle-level inventory
--
-- Adds draft_vehicles table for carts, wagons hitched to draft teams.
-- Adds nullable vehicle_id FK on inventory_items for items stored in vehicles.

CREATE TABLE IF NOT EXISTS draft_vehicles (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    party_id TEXT NOT NULL REFERENCES parties(id),
    item_key TEXT NOT NULL,
    name TEXT NOT NULL DEFAULT '',
    hitched_creatures TEXT NOT NULL DEFAULT '[]',
    is_destroyed INTEGER NOT NULL DEFAULT 0 CHECK(is_destroyed IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

ALTER TABLE inventory_items ADD COLUMN vehicle_id TEXT
    REFERENCES draft_vehicles(id) DEFAULT NULL;
