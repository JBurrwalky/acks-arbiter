-- Migration 121: domain_departure_log — Phase 11A append-only chronicle
-- of significant losses and lifecycle changes per gdd-domain-tab.md §14 and
-- docs/phase-11-plan.md §11A.
--
-- This is the substrate for Phase 11's lifecycle work: every Phase 11B/C
-- transition (conquest, abandonment, ruler death, succession resolution,
-- stronghold collapse) writes here. Existing Phase 0-10 transitions
-- (classification advancement/regression, morale tier shifts, pillage,
-- vassal loss, religion conversion, monster settlement, calamities) are
-- wired in 11A as well.
--
-- Append-only — see docs/coding_conventions.md for the "log is never
-- DELETEd from" project rule. There is no UPDATE path on this table either:
-- once a row lands it is immutable. This preserves narrative weight per the
-- established Henchmen Departure Log convention.
--
-- domain_id intentionally has NO FK REFERENCES so the log survives a hard
-- domain row deletion (the "conquered by foreign realm" terminal case in
-- Phase 11B will null/release the domains row but the audit history stays).
-- campaign_id keeps its FK because campaign deletion is a full-tear-down
-- operation that cascades all related state.

CREATE TABLE IF NOT EXISTS domain_departure_log (
    id                       TEXT    PRIMARY KEY,
    campaign_id              TEXT    NOT NULL REFERENCES campaigns(id),
    domain_id                TEXT    NOT NULL,
    calendar_day             INTEGER NOT NULL,
    event_type               TEXT    NOT NULL
        CHECK(event_type IN (
            'established',
            'classification_advanced',
            'classification_regressed',
            'territory_lost',
            'stronghold_lost',
            'defeat',
            'pillaged',
            'ruler_changed',
            'ruler_died',
            'succession_started',
            'succession_resolved',
            'succession_lapsed',
            'vassal_lost',
            'vassal_promoted',
            'religion_converted',
            'monster_settled',
            'calamity',
            'morale_tier_dropped',
            'conquered',
            'abandoned',
            'restored'
        )),
    summary                  TEXT    NOT NULL DEFAULT '',
    full_details_json        TEXT    NOT NULL DEFAULT '{}',
    related_ledger_entry_ids TEXT    NOT NULL DEFAULT '[]',
    related_encounter_ids    TEXT    NOT NULL DEFAULT '[]',
    created_at               TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_domain_departure_log_domain_calendar
    ON domain_departure_log(domain_id, calendar_day DESC);

CREATE INDEX IF NOT EXISTS idx_domain_departure_log_campaign_calendar
    ON domain_departure_log(campaign_id, calendar_day DESC);
