-- Migration 137: per-cell placement + container properties for treasure_hoards.
--
-- Replaces the room-level claim-on-entry loot model with per-cell interactable
-- containers (chest / barrel / sack / coin_pile / gear_pile) placed at
-- dungeon generation. See generation/gdd-treasure-item-backing.md §15.
--
-- Container properties:
--   cell_x, cell_y, cell_z: voxel cell coordinates within the dungeon
--     (DEFAULT -1 / -1 / 0 = not yet placed; legacy rows from migrations 132
--     pre-date the placement service).
--   container_type: enum of chest / barrel / sack / coin_pile / gear_pile.
--     NULL = not yet assigned. Each maps to a real inventory_items row at
--     materialization time, linked via location_caches.container_item_id.
--   is_locked: chest / barrel / sack containers may carry a lock (requires
--     Pick Lock proficiency throw or a key to open).
--   is_trapped: chest / barrel containers may be trapped (fires on open).
--     Trap-fallback guardrail (Jedidiah 2026-05-29): when the traps system
--     isn't implemented or trap generation errors, the placement service
--     emits is_trapped=0 + is_locked=1 instead — the container becomes a
--     locked chest, and is upgraded back to trapped when traps land.
--
-- All ADD COLUMNs are non-destructive single-column adds (the migration
-- 012 / 134 / 135 pattern). SQLite stamps the defaults onto every existing
-- row in place.
ALTER TABLE treasure_hoards ADD COLUMN cell_x INTEGER NOT NULL DEFAULT -1;
ALTER TABLE treasure_hoards ADD COLUMN cell_y INTEGER NOT NULL DEFAULT -1;
ALTER TABLE treasure_hoards ADD COLUMN cell_z INTEGER NOT NULL DEFAULT 0;
ALTER TABLE treasure_hoards ADD COLUMN container_type TEXT
    CHECK(container_type IS NULL OR container_type IN
        ('chest', 'barrel', 'sack', 'coin_pile', 'gear_pile'));
ALTER TABLE treasure_hoards ADD COLUMN is_locked INTEGER NOT NULL DEFAULT 0
    CHECK(is_locked IN (0, 1));
ALTER TABLE treasure_hoards ADD COLUMN is_trapped INTEGER NOT NULL DEFAULT 0
    CHECK(is_trapped IN (0, 1));
