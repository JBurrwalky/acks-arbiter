-- Migration 147: savegame slot metadata on game_snapshots (Phase S-2).
--
-- Per gdd-savegame-system.md §6/§7: named save slots are now whole-database
-- file snapshots (VACUUM INTO user://saves/<id>.db), structurally complete —
-- a slot cannot miss a table. game_snapshots becomes the slot METADATA store;
-- its legacy snapshot_data blob now holds a small manifest, not table rows.
--
-- slot_kind:      'manual' (player slot) | 'autosave' (reserved; the live DB is
--                 the working autosave, so autosave files are not written yet).
-- schema_version: highest applied migration version at capture time, for the
--                 best-effort migrate-on-load + version-skew warning (§9).
-- location_label: denormalized place label for the slot list ("Ashford Vale",
--                 "Dungeon — Level 2", etc.), so the list needs no live lookup.
--
-- Non-destructive: three ADD COLUMNs, per the migration 143/144 pattern.
ALTER TABLE game_snapshots ADD COLUMN slot_kind TEXT NOT NULL DEFAULT 'manual';
ALTER TABLE game_snapshots ADD COLUMN schema_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE game_snapshots ADD COLUMN location_label TEXT NOT NULL DEFAULT '';
