-- Migration 128: religion conversion schema per gdd-religion-conversion.md §4.1
-- and Phase 11D.3 of docs/phase-11-plan.md.
--
-- Three changes:
--   (a) Full rebuild of `congregants` table — adds per-character-per-domain
--       breakdown (previously keyed solely on character_id).
--   (b) New `domain_religion_conversion` table — tracks active conversion arcs.
--   (c) `domains.effective_religion` column — the practiced religion (vs.
--       `domains.religion` which becomes the declared religion).
--
-- All three changes are required for the religion-conversion mechanic per
-- §4-§5 of the GDD. The full congregants rebuild is Q-RC-5 resolution: no
-- back-compat shim; the new schema is the canonical shape.

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------------
-- (a) Rebuild congregants — add domain_id, switch PK to (character_id, domain_id)
-- via a synthetic id PK + UNIQUE index (matches the GDD §4.1 shape).
-- ---------------------------------------------------------------------------

ALTER TABLE congregants RENAME TO congregants_old;

CREATE TABLE congregants (
    id                          TEXT    PRIMARY KEY,
    character_id                TEXT    NOT NULL REFERENCES characters(id),
    -- No FK on domain_id: tracks even after domain teardown (per GDD §4.1).
    -- The sentinel '' is permitted for dev-test rows with no resolvable primary domain.
    domain_id                   TEXT    NOT NULL DEFAULT '',
    count                       INTEGER NOT NULL DEFAULT 0
        CHECK(count >= 0),
    monthly_growth_pending_cp   INTEGER NOT NULL DEFAULT 0
        CHECK(monthly_growth_pending_cp >= 0),
    last_resolved_calendar_day  INTEGER NOT NULL DEFAULT 0,
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX idx_congregants_caster_domain
    ON congregants(character_id, domain_id);
CREATE INDEX idx_congregants_domain
    ON congregants(domain_id);

-- Backfill: every existing row gets a generated id + a backfilled domain_id
-- equal to the caster's primary domain (their first-created owner_character_id
-- domain). Rows with no resolvable primary domain get '' sentinel.
INSERT INTO congregants
    (id, character_id, domain_id, count, monthly_growth_pending_cp,
     last_resolved_calendar_day, created_at, updated_at)
SELECT
    lower(hex(randomblob(16))),
    c_old.character_id,
    COALESCE(
        (SELECT id FROM domains
         WHERE owner_character_id = c_old.character_id
         ORDER BY created_at LIMIT 1),
        ''
    ),
    c_old.count,
    c_old.monthly_growth_pending_cp,
    c_old.last_resolved_calendar_day,
    c_old.created_at,
    c_old.updated_at
FROM congregants_old AS c_old;

DROP TABLE congregants_old;

-- ---------------------------------------------------------------------------
-- (b) domain_religion_conversion — active conversion arcs.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS domain_religion_conversion (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    domain_id                   TEXT    NOT NULL REFERENCES domains(id),
    from_religion               TEXT    NOT NULL,
    to_religion                 TEXT    NOT NULL,
    from_alignment              TEXT    NOT NULL
        CHECK(from_alignment IN ('lawful', 'neutral', 'chaotic')),
    to_alignment                TEXT    NOT NULL
        CHECK(to_alignment IN ('lawful', 'neutral', 'chaotic')),
    -- UI-convenience derived field; canonical state is the congregants table.
    progress_pct                INTEGER NOT NULL DEFAULT 0
        CHECK(progress_pct BETWEEN 0 AND 100),
    driving_character_id        TEXT    REFERENCES characters(id),  -- nullable
    started_calendar_day        INTEGER NOT NULL,
    last_progressed_calendar_day INTEGER NOT NULL DEFAULT 0,
    -- Per Q-RC-4: heresy/excommunication is OUT of v1; failed_heresy is NOT
    -- a valid status. The four v1 statuses cover all conversion outcomes.
    status                      TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'completed', 'aborted', 'failed_morale')),
    -- Cumulative cp invested in proselytizing for this arc (audit only).
    total_invested_cp           INTEGER NOT NULL DEFAULT 0,
    -- Months at Rebellious morale during this active arc — triggers
    -- failed_morale at 3+ per §7.3.
    months_at_rebellious        INTEGER NOT NULL DEFAULT 0
        CHECK(months_at_rebellious >= 0),
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_drc_domain_active
    ON domain_religion_conversion(domain_id, status);
CREATE INDEX idx_drc_campaign_active
    ON domain_religion_conversion(campaign_id, status);

-- ---------------------------------------------------------------------------
-- (c) domains.effective_religion — practiced religion (vs. declared).
-- Per GDD §4.1: backfill from existing `religion` so pre-128 domains have
-- effective_religion == religion (no active conversion).
-- ---------------------------------------------------------------------------

ALTER TABLE domains ADD COLUMN effective_religion TEXT NOT NULL DEFAULT '';
UPDATE domains SET effective_religion = religion;

COMMIT;

PRAGMA foreign_keys = ON;
