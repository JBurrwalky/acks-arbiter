-- Migration 036: Create voxel_map_cells table for 3D voxel grid storage.
-- Sparse storage: one row per non-default voxel cell.
-- Forward-migrates existing dungeon_map_cells data (door_state, fog_state)
-- with level = level_num * 2 (each old story = 2 voxel levels = 10 feet).
-- The old dungeon_map_cells table is kept for backward compatibility.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS voxel_map_cells (
    map_id TEXT NOT NULL,
    col INTEGER NOT NULL,
    row INTEGER NOT NULL,
    level INTEGER NOT NULL,
    solidity TEXT NOT NULL DEFAULT 'air',
    feature TEXT NOT NULL DEFAULT 'open',
    floor_type TEXT NOT NULL DEFAULT 'none',
    door_state TEXT NOT NULL DEFAULT '',
    door_type TEXT NOT NULL DEFAULT '',
    door_detected INTEGER NOT NULL DEFAULT 1,
    fog_state TEXT NOT NULL DEFAULT 'hidden',
    room_id INTEGER NOT NULL DEFAULT -1,
    is_corridor INTEGER NOT NULL DEFAULT 0,
    cover_value INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (map_id, col, row, level)
);

-- Forward migration: copy mutable state from old dungeon_map_cells table.
-- level = level_num * 2 because each ACKS story is 10 feet = 2 voxel cells tall.
-- Only door_state and fog_state are persisted in the old table; other fields
-- retain their defaults until populated from JSON map data at runtime.
INSERT OR IGNORE INTO voxel_map_cells (map_id, col, row, level, door_state, fog_state)
SELECT dungeon_id, col, row, level_num * 2, door_state, fog_state
FROM dungeon_map_cells;

COMMIT;
