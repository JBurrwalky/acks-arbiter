-- Migration 088: troop_units disease state — Phase 9C disease vagary loop.
--
-- Per RAW daw_vagaries.xml §disease L294-365.
--
-- A diseased unit "cannot move or fight" until duration expires (RAW L300).
-- At end of duration, recovers unless failed by death threshold OR rolled
-- natural 1 (RAW L301-302).
--
-- Schema choice (per O-9C-1 confirmation 2026-05-09): a separate is_diseased
-- boolean column rather than extending the existing `status` enum
-- ('active', 'departed'). Diseased units remain status='active' — they're
-- temporarily incapacitated, not departed. This avoids the SQLite CHECK
-- constraint table-rebuild that would be required to add 'diseased' to status.
--
-- disease_type, disease_recovery_calendar_day, disease_save_failed_by, and
-- disease_natural_roll capture per-unit state needed by DiseaseResolver to
-- resolve the end-of-duration save secretly (RAW L304: saves are hidden from
-- commanders so they don't know which units will recover).

ALTER TABLE troop_units ADD COLUMN is_diseased INTEGER NOT NULL DEFAULT 0
    CHECK(is_diseased IN (0, 1));

ALTER TABLE troop_units ADD COLUMN disease_type TEXT NOT NULL DEFAULT '';

ALTER TABLE troop_units ADD COLUMN disease_recovery_calendar_day INTEGER NOT NULL DEFAULT 0;

ALTER TABLE troop_units ADD COLUMN disease_save_failed_by INTEGER NOT NULL DEFAULT 0;

ALTER TABLE troop_units ADD COLUMN disease_natural_roll INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_troop_units_diseased
    ON troop_units(is_diseased) WHERE is_diseased = 1;

CREATE INDEX IF NOT EXISTS idx_troop_units_disease_recovery
    ON troop_units(disease_recovery_calendar_day) WHERE is_diseased = 1;
