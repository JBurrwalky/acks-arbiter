-- Migration 059: Follower arrival audit log (Domain Phase 0 — schema only)
--
-- Per `acore_axioms_strongholds_and_domains.xml` §followers_arrival L111-116:
-- a PC's class-attracted followers (5d6×10 0th-level for fighter, etc.)
-- arrive in three waves — half (rounded up) at half-built, additional quarter
-- (rounded up) at stronghold completion, remainder during the first month
-- after completion.
--
-- This table is the audit log of arrival events. The current `domain_followers`
-- (migration 057) holds the standing roster; this table records WHEN each wave
-- arrived so the Phase 4 Stronghold sub-tab can show construction-tied unlock
-- timing and the Phase 10 Departure Log has a permanent record.
--
-- Phase 5's `follower_arrival_resolver.gd` writes here; Phase 0 only declares
-- the schema.

CREATE TABLE IF NOT EXISTS follower_arrivals (
    id                    TEXT    PRIMARY KEY,
    domain_id             TEXT    NOT NULL REFERENCES domains(id),
    calendar_day          INTEGER NOT NULL,
    wave_pct              INTEGER NOT NULL
        CHECK(wave_pct IN (50, 25, 25)),
    follower_count_total  INTEGER NOT NULL DEFAULT 0,
    equipment_kit         TEXT    NOT NULL DEFAULT '',
    created_at            TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_follower_arrivals_domain_id
    ON follower_arrivals (domain_id);
