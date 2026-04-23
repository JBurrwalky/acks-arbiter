-- Migration 038: party heraldry builder.
-- Adds party_heraldry table for the composable shield data model, plus a
-- heraldry_id FK on parties. Existing parties are left with NULL heraldry_id;
-- the session loader runs a backfill that assigns each a random preset from
-- data/heraldry/presets.json on first load after this migration applies.

CREATE TABLE IF NOT EXISTS party_heraldry (
    heraldry_id         TEXT PRIMARY KEY,
    shape_id            TEXT NOT NULL DEFAULT 'english',
    division_id         TEXT NOT NULL DEFAULT 'plain',
    tincture_primary    TEXT NOT NULL DEFAULT '#dcdcdc',
    tincture_secondary  TEXT NOT NULL DEFAULT '#1a1a1a',
    ordinary_id         TEXT NOT NULL DEFAULT '',
    tincture_ordinary   TEXT NOT NULL DEFAULT '#dcdcdc',
    charge_id           TEXT NOT NULL DEFAULT '',
    tincture_charge     TEXT NOT NULL DEFAULT '#dcdcdc',
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

ALTER TABLE parties ADD COLUMN heraldry_id TEXT REFERENCES party_heraldry(heraldry_id);
