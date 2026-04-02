-- Migration 017: Dungeon grid cell state table + party dungeon position columns.
--
-- Per-cell runtime state for dungeon instances.
-- The static layout (cell types) lives in dungeon_entrances.dungeon_data JSON.
-- Only mutable state (fog visibility, door states) is stored here.
--
-- Note: level_num added to primary key so multi-level dungeons each have
-- independent fog/door states without collisions.

CREATE TABLE IF NOT EXISTS dungeon_map_cells (
    dungeon_id TEXT NOT NULL REFERENCES dungeon_entrances(id),
    level_num INTEGER NOT NULL DEFAULT 1,
    col INTEGER NOT NULL,
    row INTEGER NOT NULL,
    door_state TEXT NOT NULL DEFAULT 'closed',
    fog_state TEXT NOT NULL DEFAULT 'hidden'
        CHECK(fog_state IN ('hidden', 'explored', 'visible')),
    PRIMARY KEY (dungeon_id, level_num, col, row)
);

-- Party position when inside a dungeon.
-- dungeon_id '' means party is not in a dungeon.
ALTER TABLE parties ADD COLUMN dungeon_id TEXT NOT NULL DEFAULT '';
ALTER TABLE parties ADD COLUMN dungeon_level INTEGER NOT NULL DEFAULT 1;
ALTER TABLE parties ADD COLUMN dungeon_col INTEGER NOT NULL DEFAULT 0;
ALTER TABLE parties ADD COLUMN dungeon_row INTEGER NOT NULL DEFAULT 0;
