-- Migration 208: widen the dungeon conflict-pass cap key to include the BAND.
-- Review fix (Wave 3 FF-5, gdd-faction-framework.md §9.3/§11.3). The migration-207
-- cap used PRIMARY KEY (dungeon_id, conflict_id) — one row per dungeon+conflict.
-- But run_conflict_pass fires PER DETACHMENT BAND, and one dungeon can hold several
-- detachment bands linked to DIFFERENT (even opposing) parents. Under the old key the
-- FIRST band's pass blocked EVERY other band in the same dungeon+conflict, so a second
-- band never sided with its own parent. The correct granularity is one pass per
-- (dungeon, conflict, band). SQLite cannot ALTER a PRIMARY KEY, so rebuild the table
-- (copy → drop → rename); existing rows survive (each was already unique by dungeon
-- +conflict, so adding faction_id to the key is non-destructive).

-- Atomic all-or-nothing rebuild (matches migrations 011/013/014): the transaction
-- makes the copy → drop → rename indivisible, and DROP ... __new self-heals a retry
-- if a prior attempt was interrupted after the __new table was created (the runner
-- doesn't record a version on failure and re-runs the file from the top on next boot).
DROP TABLE IF EXISTS dungeon_link_conflict_passes__new;

BEGIN TRANSACTION;

CREATE TABLE dungeon_link_conflict_passes__new (
    dungeon_id   TEXT    NOT NULL,
    conflict_id  TEXT    NOT NULL,
    faction_id   TEXT    NOT NULL DEFAULT '',   -- the detachment band that passed
    decision     TEXT    NOT NULL DEFAULT '',   -- the AllegianceEvaluator decision recorded
    passed_day   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (dungeon_id, conflict_id, faction_id)
);
INSERT INTO dungeon_link_conflict_passes__new
    (dungeon_id, conflict_id, faction_id, decision, passed_day)
    SELECT dungeon_id, conflict_id, faction_id, decision, passed_day
    FROM dungeon_link_conflict_passes;
DROP TABLE dungeon_link_conflict_passes;
ALTER TABLE dungeon_link_conflict_passes__new RENAME TO dungeon_link_conflict_passes;

COMMIT;

CREATE INDEX IF NOT EXISTS idx_dungeon_link_conflict_passes_dungeon
    ON dungeon_link_conflict_passes(dungeon_id);
