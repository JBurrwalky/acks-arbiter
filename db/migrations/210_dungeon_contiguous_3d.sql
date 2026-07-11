-- Migration 210: Contiguous 3D dungeon generation — dormant schema (DG-C3D.A).
-- gdd-dungeon-contiguous-3d.md §9 (schema APPROVED by Jedidiah 2026-07-06);
-- build plan docs/dungeon-contiguous-3d-build-plan.md sub-phase A.
--
-- Additive only, zero behavior change: columns default to today's semantics
-- and the two new tables stay empty until the vertical composer (DG-C3D.D)
-- emits zones/stairwells and the cutover (DG-C3D.F) persists them. Old
-- dungeons are never converted — they regenerate on next access once the
-- generator version bumps at DG-C3D.F (contiguous GDD §13 "regenerate, no
-- migration"), so this migration establishes schema only, no row backfills.
--
-- room_zones / stairwells are dungeon-CONTENT tables (like monster_groups /
-- dungeon_rooms): keyed on dungeon_id TEXT (there is no `dungeons` table —
-- the dungeon id is carried in dungeon_entrances.dungeon_data JSON), so NO
-- FK on dungeon_id and NO campaign_id column, per the DG-V1.C / migration-201
-- pattern. They are purged dungeon-scoped in
-- CampaignRepository._campaign_scope_entries() (the dungeon_scoped block),
-- NOT via _SCOPE_DIRECT_CAMPAIGN.

-- --- Zone membership on voxel cells (§9.4) ---
-- -1 = no zone (corridors, non-dungeon maps, pre-DG-C3D content). Stamped at
-- composition time; cannot always be derived from (room_id, band) because
-- disconnected same-band galleries are distinct zones.
ALTER TABLE voxel_map_cells ADD COLUMN zone_index INTEGER NOT NULL DEFAULT -1;

-- --- Room verticality (§9.1) ---
-- band = the room's ACKS dungeon level (floor_index). kind separates stockable
-- chambers from circulation (stairwell) rooms. height_levels 2 = standard 10'
-- room, 4 = two-band atrium. level_offset is the RESERVED free-form hook
-- (§5.4) — always 0 in this version; validation asserts it.
ALTER TABLE dungeon_rooms ADD COLUMN band INTEGER NOT NULL DEFAULT 0;
ALTER TABLE dungeon_rooms ADD COLUMN kind TEXT NOT NULL DEFAULT 'chamber'
    CHECK(kind IN ('chamber', 'circulation'));
ALTER TABLE dungeon_rooms ADD COLUMN height_levels INTEGER NOT NULL DEFAULT 2;
ALTER TABLE dungeon_rooms ADD COLUMN level_offset INTEGER NOT NULL DEFAULT 0;

-- --- Generator version stamp (§13) ---
-- Stamped from DungeonGeneratorV1.GENERATOR_VERSION at insert. The lazy-
-- generation seam (DungeonFixtureService) discards + regenerates any stored
-- dungeon whose version does not match the current constant. 0 = the
-- pre-contiguous (floor-stitched) generator; DG-C3D.F bumps the constant.
ALTER TABLE dungeon_floors ADD COLUMN generator_version INTEGER NOT NULL DEFAULT 0;

-- --- §9.2 RoomZone — the stocking unit ---
-- One row per maximal contiguous walkable region of one room on one band.
-- cells_json is a JSON array of [col, row] pairs at walk_level(band) +
-- level_offset. Stocking-result columns mirror dungeon_rooms (they relocate
-- from rooms to zones at DG-C3D.F; dual presence until then is deliberate).
CREATE TABLE IF NOT EXISTS room_zones (
    id                TEXT    PRIMARY KEY,
    dungeon_id        TEXT    NOT NULL,
    room_id           INTEGER NOT NULL DEFAULT -1,
    zone_index        INTEGER NOT NULL DEFAULT 0,
    band              INTEGER NOT NULL DEFAULT 0,
    zone_type         TEXT    NOT NULL DEFAULT 'main'
        CHECK(zone_type IN ('main', 'balcony', 'gallery', 'ledge', 'landing')),
    cells_json        TEXT    NOT NULL DEFAULT '[]',
    level_offset      INTEGER NOT NULL DEFAULT 0,
    contents_kind     TEXT    NOT NULL DEFAULT 'empty'
        CHECK(contents_kind IN ('empty', 'monster', 'monster_lair', 'trap_placeholder', 'unique_placeholder')),
    monster_group_id  TEXT,
    treasure_hoard_id TEXT,
    current_purpose   TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_room_zones_dungeon ON room_zones(dungeon_id);
CREATE INDEX IF NOT EXISTS idx_room_zones_room ON room_zones(dungeon_id, room_id);

-- --- §9.3 StairwellData — logical vertical connectors ---
-- One row per generated connector (straight run / switchback stairwell /
-- spiral shaft / ramp). bottom/top are the landing approach cells (voxel
-- col/row/level; -1/-1/0 = unset sentinel, mirroring treasure_hoards).
-- run_cells_json is a JSON array of [col, row, level] triples covering every
-- stair/ramp/shaft cell; run cells NEVER carry door cells or gate semantics
-- (contiguous GDD §10.3 — doors are the only gates, at room boundaries).
CREATE TABLE IF NOT EXISTS stairwells (
    id             TEXT    PRIMARY KEY,
    dungeon_id     TEXT    NOT NULL,
    type           TEXT    NOT NULL DEFAULT 'straight'
        CHECK(type IN ('straight', 'switchback', 'spiral', 'ramp')),
    lower_band     INTEGER NOT NULL DEFAULT 0,
    upper_band     INTEGER NOT NULL DEFAULT 0,
    bottom_x       INTEGER NOT NULL DEFAULT -1,
    bottom_y       INTEGER NOT NULL DEFAULT -1,
    bottom_z       INTEGER NOT NULL DEFAULT 0,
    top_x          INTEGER NOT NULL DEFAULT -1,
    top_y          INTEGER NOT NULL DEFAULT -1,
    top_z          INTEGER NOT NULL DEFAULT 0,
    run_cells_json TEXT    NOT NULL DEFAULT '[]',
    width          INTEGER NOT NULL DEFAULT 1,
    room_id        INTEGER NOT NULL DEFAULT -1,
    is_entrance    INTEGER NOT NULL DEFAULT 0 CHECK(is_entrance IN (0, 1))
);
CREATE INDEX IF NOT EXISTS idx_stairwells_dungeon ON stairwells(dungeon_id);
