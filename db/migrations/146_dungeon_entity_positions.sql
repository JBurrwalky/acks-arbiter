-- Migration 146: per-entity live dungeon positions (savegame full-fidelity restore).
--
-- Per gdd-savegame-system.md §5.2: a party saved inside a dungeon must reload
-- with EVERY member standing on the exact cell/level they occupied (no
-- re-scatter from an anchor). The single parties.dungeon_col/row anchor
-- (migration 017) cannot hold per-member cells, so this table stores one live
-- voxel cell per party entity while the party is in a dungeon.
--
-- entity_id: the controller entity id — a character_id (and, if creatures are
--   ever spawned as dungeon entities, a creature_id). Keyed per (party, entity).
-- col/row/level: the entity's live Vector3i cell on the dungeon voxel grid.
-- dungeon_id: the dungeon's internal id (== voxel_map_cells.map_id), recorded so
--   stale rows from a different dungeon can be distinguished if ever needed.
--
-- Lifecycle: written on save (SessionState.flush_to_db); DELETEd on dungeon exit
-- (DungeonExploreState.exit → clear_dungeon_entity_positions). The loader reads
-- them after rebuilding the dungeon and places each entity exactly.
--
-- Non-destructive: CREATE TABLE IF NOT EXISTS, per the migration 143/144 pattern.
CREATE TABLE IF NOT EXISTS dungeon_entity_positions (
    party_id    TEXT    NOT NULL REFERENCES parties(id),
    entity_id   TEXT    NOT NULL,
    dungeon_id  TEXT    NOT NULL,
    col         INTEGER NOT NULL,
    row         INTEGER NOT NULL,
    level       INTEGER NOT NULL,
    PRIMARY KEY (party_id, entity_id)
);
CREATE INDEX IF NOT EXISTS idx_dungeon_entity_positions_party
    ON dungeon_entity_positions(party_id);
