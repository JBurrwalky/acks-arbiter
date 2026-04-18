-- Migration 032: Location caches for ground-drop inventory persistence
-- Part of the Party Inventory system (gdd-party-inventory.md §8).
--
-- Five cache variants across three location types:
--   loose (dungeon/wilderness/settlement) — ephemeral, decays on timer
--   locked_container (dungeon)            — persistent, tied to a container item
--   hidden_wilderness (wilderness)        — persistent, monthly raid risk

CREATE TABLE IF NOT EXISTS location_caches (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    location_type TEXT NOT NULL CHECK(location_type IN ('hex', 'dungeon_cell', 'settlement_node')),
    location_key TEXT NOT NULL,
    cache_variant TEXT NOT NULL CHECK(cache_variant IN ('loose', 'locked_container', 'hidden_wilderness')),
    container_item_id TEXT REFERENCES inventory_items(id) ON DELETE SET NULL,
    is_persistent INTEGER NOT NULL DEFAULT 0,
    decay_check_day INTEGER DEFAULT NULL,
    created_at_day INTEGER NOT NULL,
    raid_monthly_modifier INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS location_caches_by_location
    ON location_caches(campaign_id, location_type, location_key);

CREATE INDEX IF NOT EXISTS location_caches_by_decay_day
    ON location_caches(decay_check_day)
    WHERE decay_check_day IS NOT NULL;

ALTER TABLE inventory_items ADD COLUMN location_cache_id TEXT
    REFERENCES location_caches(id) ON DELETE CASCADE DEFAULT NULL;
