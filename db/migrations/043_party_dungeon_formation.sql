-- Migration 043: dungeon formation grid + dungeon_eligible flag.
--
-- Per gdd-party-tab.md §7 the Party tab's Formation sub-tab exposes two
-- independent grids:
--   - Wilderness 6×12 — uses the existing party_members.formation_col /
--     formation_row + trained_creatures.formation_col / formation_row columns
--     (introduced in migration 022). γ.3 widens the wilderness grid from the
--     prior 5-col layout to 6 cols; this is a pure UI / constants change —
--     no migration needed because existing values (col 0..4) remain valid in
--     a 6-wide layout.
--   - Dungeon 2×12 — new columns added here so dungeon and wilderness
--     placements persist independently.
--
-- The dungeon grid additionally honors per-creature eligibility: pack mules,
-- horses, oxen, and similar large beasts of burden are wilderness-only;
-- small trained creatures (dogs, hawks, etc.) and PCs / henchmen / vehicles
-- have their own per-row eligibility rules per §7.5. Per-creature
-- eligibility is stored as `dungeon_eligible INTEGER NOT NULL DEFAULT 1` on
-- trained_creatures — defaulting to TRUE keeps existing creature data
-- functioning until catalog authoring narrows the default per species.
--
-- All new columns default to UNASSIGNED (-1) for placement and 1 for the
-- bool flag, so existing rows do not need backfill.

ALTER TABLE party_members
    ADD COLUMN dungeon_formation_col INTEGER NOT NULL DEFAULT -1;
ALTER TABLE party_members
    ADD COLUMN dungeon_formation_row INTEGER NOT NULL DEFAULT -1;

ALTER TABLE trained_creatures
    ADD COLUMN dungeon_formation_col INTEGER NOT NULL DEFAULT -1;
ALTER TABLE trained_creatures
    ADD COLUMN dungeon_formation_row INTEGER NOT NULL DEFAULT -1;
ALTER TABLE trained_creatures
    ADD COLUMN dungeon_eligible INTEGER NOT NULL DEFAULT 1;
