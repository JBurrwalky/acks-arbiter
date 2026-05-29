-- Migration 132: Random Dungeon Generator V1 persistence tables.
--
-- Implements DG-V1.C of docs/dungeon-generator-v1-build-plan.md. Six tables
-- store a generated dungeon's structured output:
--
--   dungeon_floors   — per-floor metadata + the rasterized cell grid (cells_json)
--                      + stairs (stairs_json) + stocking summary (DG-V1.D fills).
--   dungeon_rooms    — per-floor room records + stocking attachments.
--   dungeon_doors    — per-floor door records + key/lever attachments.
--   monster_groups   — stocked monster groups (populated by DG-V1.D; empty for
--                      layout-only dungeons).
--   treasure_hoards  — stocked treasure (DG-V1.D).
--   key_items        — cross-floor key/lever placements (DG-V1.D).
--
-- SELF-CONTAINED: no FK REFERENCES to the existing `dungeons` table (or any
-- other table), per the build plan + the domain_departure_log precedent
-- (migration 121). The `dungeon_id` TEXT column is the external linkage; the
-- intra-dungeon relationships use the TEXT primary keys (floor_id, room_id,
-- etc.). godot-sqlite does not enforce FK constraints anyway; keeping the set
-- self-contained makes cascade-delete an explicit repository operation.
--
-- PERSISTENCE MODEL (DG-V1.C decision — see build_log 2026-05-28):
--   * The full DungeonCellData grid persists as cells_json on dungeon_floors
--     (exact round-trip; aligns with the V1 GDD §12.3 "self-contained
--     snapshot" philosophy and the existing VoxelMapData JSON precedent).
--   * Stairs persist as stairs_json on dungeon_floors (few per floor; a
--     dedicated table would be overkill — the build plan listed 6 tables and
--     did not call for a stairs table).
--   * Rooms and doors ALSO persist structured (dungeon_rooms / dungeon_doors)
--     because stocking (DG-V1.D) attaches content by room/door and queries
--     hit these tables. Room cells are recomputed from bounds on load (V1
--     rooms are rectangles), so they are not duplicated in the room rows.

-- ---------------------------------------------------------------------------
-- dungeon_floors
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dungeon_floors (
    id                      TEXT    PRIMARY KEY,
    dungeon_id              TEXT    NOT NULL,
    floor_index             INTEGER NOT NULL,
    floor_tier              INTEGER NOT NULL DEFAULT 1,
    is_entrance_floor       INTEGER NOT NULL DEFAULT 0 CHECK(is_entrance_floor IN (0, 1)),
    dungeon_type            TEXT    NOT NULL DEFAULT 'wizards_dungeon',
    dungeon_size            TEXT    NOT NULL DEFAULT 'medium',
    structure_type          TEXT    NOT NULL DEFAULT 'subterranean',
    grid_width              INTEGER NOT NULL,
    grid_height             INTEGER NOT NULL,
    entrance_x              INTEGER NOT NULL DEFAULT -1,
    entrance_y              INTEGER NOT NULL DEFAULT -1,
    generation_seed         INTEGER NOT NULL DEFAULT 0,
    -- Stocking summary (DG-V1.D; default 0 for layout-only floors):
    total_monster_xp        INTEGER NOT NULL DEFAULT 0,
    total_treasure_gp_value INTEGER NOT NULL DEFAULT 0,
    xp_to_gp_ratio          REAL    NOT NULL DEFAULT 0.0,
    encounter_table_row     INTEGER NOT NULL DEFAULT 0,
    -- Serialized grid + stairs:
    cells_json              TEXT    NOT NULL DEFAULT '[]',
    stairs_json             TEXT    NOT NULL DEFAULT '[]',
    created_at              TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_dungeon_floors_dungeon
    ON dungeon_floors(dungeon_id);

-- ---------------------------------------------------------------------------
-- dungeon_rooms
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dungeon_rooms (
    id                TEXT    PRIMARY KEY,
    dungeon_id        TEXT    NOT NULL,
    floor_id          TEXT    NOT NULL,
    room_id_in_floor  INTEGER NOT NULL,
    bounds_x          INTEGER NOT NULL,
    bounds_y          INTEGER NOT NULL,
    bounds_w          INTEGER NOT NULL,
    bounds_h          INTEGER NOT NULL,
    area_sqft         INTEGER NOT NULL DEFAULT 0,
    center_x          INTEGER NOT NULL DEFAULT 0,
    center_y          INTEGER NOT NULL DEFAULT 0,
    original_purpose  TEXT    NOT NULL DEFAULT '',
    current_purpose   TEXT    NOT NULL DEFAULT '',
    contents_kind     TEXT    NOT NULL DEFAULT 'empty'
        CHECK(contents_kind IN ('empty', 'monster', 'monster_lair', 'trap_placeholder', 'unique_placeholder')),
    monster_group_id  TEXT,
    treasure_hoard_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_dungeon_rooms_dungeon
    ON dungeon_rooms(dungeon_id);
CREATE INDEX IF NOT EXISTS idx_dungeon_rooms_floor
    ON dungeon_rooms(floor_id);
CREATE INDEX IF NOT EXISTS idx_dungeon_rooms_floor_roomid
    ON dungeon_rooms(floor_id, room_id_in_floor);

-- ---------------------------------------------------------------------------
-- dungeon_doors
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dungeon_doors (
    id                     TEXT    PRIMARY KEY,
    dungeon_id             TEXT    NOT NULL,
    floor_id               TEXT    NOT NULL,
    position_x             INTEGER NOT NULL,
    position_y             INTEGER NOT NULL,
    type                   TEXT    NOT NULL
        CHECK(type IN ('arch', 'unlocked', 'locked', 'trapped', 'portcullis')),
    is_secret              INTEGER NOT NULL DEFAULT 0 CHECK(is_secret IN (0, 1)),
    door_state             TEXT    NOT NULL DEFAULT '',
    door_material          TEXT    NOT NULL DEFAULT 'wood_standard'
        CHECK(door_material IN ('', 'curtain_cloth', 'curtain_leather', 'wood_standard', 'wood_thick', 'stone', 'metal')),
    is_evil                INTEGER NOT NULL DEFAULT 0 CHECK(is_evil IN (0, 1)),
    connects_room_ids      TEXT    NOT NULL DEFAULT '[]',
    required_key_id        TEXT,
    wired_lever_position_x INTEGER NOT NULL DEFAULT -1,
    wired_lever_position_y INTEGER NOT NULL DEFAULT -1
);

CREATE INDEX IF NOT EXISTS idx_dungeon_doors_dungeon
    ON dungeon_doors(dungeon_id);
CREATE INDEX IF NOT EXISTS idx_dungeon_doors_floor
    ON dungeon_doors(floor_id);

-- ---------------------------------------------------------------------------
-- monster_groups (DG-V1.D stocking; created now, populated later)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS monster_groups (
    id                   TEXT    PRIMARY KEY,
    dungeon_id           TEXT    NOT NULL,
    floor_id             TEXT    NOT NULL,
    room_id              TEXT    NOT NULL,
    monster_name         TEXT    NOT NULL DEFAULT '',
    monster_xp_each      INTEGER NOT NULL DEFAULT 0,
    number_appearing     INTEGER NOT NULL DEFAULT 0,
    hd                   TEXT    NOT NULL DEFAULT '',
    associated_creatures TEXT    NOT NULL DEFAULT '[]',
    is_lair              INTEGER NOT NULL DEFAULT 0 CHECK(is_lair IN (0, 1)),
    morale               INTEGER NOT NULL DEFAULT 0,
    alignment            TEXT    NOT NULL DEFAULT '',
    treasure_type_letter TEXT,
    initial_inventory    TEXT    NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS idx_monster_groups_dungeon
    ON monster_groups(dungeon_id);
CREATE INDEX IF NOT EXISTS idx_monster_groups_floor
    ON monster_groups(floor_id);

-- ---------------------------------------------------------------------------
-- treasure_hoards (DG-V1.D stocking)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS treasure_hoards (
    id                   TEXT    PRIMARY KEY,
    dungeon_id           TEXT    NOT NULL,
    floor_id             TEXT    NOT NULL,
    room_id              TEXT    NOT NULL,
    source               TEXT    NOT NULL
        CHECK(source IN ('lair', 'unprotected_empty', 'unprotected_trap_placeholder', 'unprotected_unique_placeholder')),
    treasure_type_letter TEXT,
    copper               INTEGER NOT NULL DEFAULT 0,
    silver               INTEGER NOT NULL DEFAULT 0,
    electrum             INTEGER NOT NULL DEFAULT 0,
    gold                 INTEGER NOT NULL DEFAULT 0,
    platinum             INTEGER NOT NULL DEFAULT 0,
    gems                 TEXT    NOT NULL DEFAULT '[]',
    jewelry              TEXT    NOT NULL DEFAULT '[]',
    magic_items          TEXT    NOT NULL DEFAULT '[]',
    total_gp_value       INTEGER NOT NULL DEFAULT 0,
    is_hidden            INTEGER NOT NULL DEFAULT 0 CHECK(is_hidden IN (0, 1))
);

CREATE INDEX IF NOT EXISTS idx_treasure_hoards_dungeon
    ON treasure_hoards(dungeon_id);
CREATE INDEX IF NOT EXISTS idx_treasure_hoards_floor
    ON treasure_hoards(floor_id);

-- ---------------------------------------------------------------------------
-- key_items (DG-V1.D cross-floor key/lever placement)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS key_items (
    id                    TEXT    PRIMARY KEY,
    dungeon_id            TEXT    NOT NULL,
    opens_door_floor_id   TEXT    NOT NULL,
    opens_door_position_x INTEGER NOT NULL,
    opens_door_position_y INTEGER NOT NULL,
    placed_in             TEXT    NOT NULL
        CHECK(placed_in IN ('monster_group_inventory', 'treasure_hoard', 'loose_in_room')),
    placed_in_room_id     TEXT,
    placed_on_floor_id    TEXT
);

CREATE INDEX IF NOT EXISTS idx_key_items_dungeon
    ON key_items(dungeon_id);
