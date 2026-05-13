-- Migration 103: character_legal_status table (Phase 10B prereq, wave Prereq.6).
--
-- Per generation/gdd-settlement-economy.md §10.3. Sibling table to characters
-- (rather than columns on characters itself) — legal status is a narrow
-- concern most characters won't have any data for; keeping it sibling
-- preserves the characters table's leanness.
--
-- Three permanent flags from RAW acore-campaign-hijinks.xml:300-304:
--   * Branded: -1 to Crime & Punishment throws
--   * Maimed (loss of tongue/hands): -2
--   * Proscribed: -3
-- Flags stack additively.
--
-- prior_crimes_modifier_cache is maintained by application logic on every
-- flag update (CharacterLegalStatusRepository.apply_* / clear_flag). The
-- C&P resolver in Phase 10B.3 reads the cache directly to avoid recomputing.
--
-- v1 does NOT mutate combat-affecting character state for Maimed per
-- Phase 10 Q6 [RESOLVED 2026-05-10] — the flag affects C&P proceedings only.
-- [NEEDS-PERMANENT-WOUND-COMBAT-PASS] flag for future combat-state work.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS character_legal_status (
    character_id                    TEXT    PRIMARY KEY REFERENCES characters(id),
    is_branded                      INTEGER NOT NULL DEFAULT 0
        CHECK(is_branded IN (0, 1)),
    is_maimed                       INTEGER NOT NULL DEFAULT 0
        CHECK(is_maimed IN (0, 1)),
    is_proscribed                   INTEGER NOT NULL DEFAULT 0
        CHECK(is_proscribed IN (0, 1)),
    prior_crimes_modifier_cache     INTEGER NOT NULL DEFAULT 0,
    branded_at_calendar_day         INTEGER,
    maimed_at_calendar_day          INTEGER,
    proscribed_at_calendar_day      INTEGER,
    notes                           TEXT    NOT NULL DEFAULT '',
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

COMMIT;
