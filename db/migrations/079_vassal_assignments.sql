-- Migration 079: vassal_assignments
--
-- Per docs/domain-roadmap-corrected.md Phase 7 + acore_axioms_strongholds_and_domains.xml
-- §non_henchman_vassals L392-397, §tribute_inefficiency L398-409.
--
-- Each row records the vassalage relationship between a liege character and
-- a vassal character (whose owned domain becomes a sub-domain of the liege's
-- realm). The vassal_domain_id is set when the vassal already owns a domain
-- at appointment; alternatively, a vassal may be appointed in advance of
-- domain creation and the column is filled in when the domain is created.
--
-- is_henchman_vassal:
--   1 — vassal is a humanoid henchman of the liege (default, base loyalty 0)
--   0 — vassal is a non-henchman noble per RAW §non_henchman_vassals:
--       base loyalty -2 (or -4 if outside trade range of liege's largest urban
--       settlement)
--
-- The inverse pointer (`domains.liege_domain_id`, populated in Phase 0) is
-- the source of truth for tribute and apex chain walks; this table records
-- the *appointment* and the loyalty / status state of each vassal.
--
-- status:
--   active     — vassal is in good standing; tribute flows monthly
--   departed   — voluntary departure (per Phase 11 lifecycle)
--   revolted   — failed loyalty roll on tribute payment / favor / duty
--   deceased   — vassal character died; succession handled per Phase 11

CREATE TABLE IF NOT EXISTS vassal_assignments (
    id                      TEXT    PRIMARY KEY,
    campaign_id             TEXT    NOT NULL REFERENCES campaigns(id),
    liege_character_id      TEXT    NOT NULL REFERENCES characters(id),
    vassal_character_id     TEXT    NOT NULL REFERENCES characters(id),
    vassal_domain_id        TEXT    REFERENCES domains(id),
    assigned_calendar_day   INTEGER NOT NULL DEFAULT 0,
    status                  TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'departed', 'revolted', 'deceased')),
    is_henchman_vassal      INTEGER NOT NULL DEFAULT 1
        CHECK(is_henchman_vassal IN (0, 1)),
    base_loyalty_modifier   INTEGER NOT NULL DEFAULT 0,
    last_loyalty_roll_day   INTEGER NOT NULL DEFAULT 0,
    last_loyalty_outcome    TEXT    NOT NULL DEFAULT '',
    created_at              TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at              TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_vassal_assignments_liege
    ON vassal_assignments(liege_character_id);

CREATE INDEX IF NOT EXISTS idx_vassal_assignments_vassal
    ON vassal_assignments(vassal_character_id);

CREATE INDEX IF NOT EXISTS idx_vassal_assignments_domain
    ON vassal_assignments(vassal_domain_id);

-- Partial unique index: a character may have at most one ACTIVE vassalage
-- to a single liege at a time. Departed/revolted/deceased rows are kept for
-- history per the append-only convention.
CREATE UNIQUE INDEX IF NOT EXISTS idx_vassal_assignments_unique_active
    ON vassal_assignments(liege_character_id, vassal_character_id)
    WHERE status = 'active';
