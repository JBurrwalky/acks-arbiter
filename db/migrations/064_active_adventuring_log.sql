-- Migration 064: Active adventuring audit log (Domain Phase 2)
--
-- Append-only audit of `is_active_adventuring_this_month` resolutions per
-- `acore_axioms_strongholds_and_domains.xml` §active_adventuring_growth L137
-- and the project-resolved seven-trigger heuristic (gdd-domain-tab.md §6.2 +
-- docs/domain-roadmap-corrected.md Phase 2 [RESOLVED 2026-05-06]):
--
--   "Active adventuring is defined as: the ruler left the stronghold during
--    the prior game month AND any of: (a) wilderness encounter resolved,
--    (b) lair entered, (c) hex cleared, (d) dungeon entered, (e) battle
--    resolved, (f) siege participated in, (g) returned to a friendly
--    settlement with 1,000 gp or more in new treasure since departure."
--
-- The detector runs in-memory each month; this table records each month's
-- final boolean plus the trigger that satisfied it (for transparency in the
-- Overview sub-tab "Active this month" tooltip).
--
-- triggers_json shape: {"left_stronghold": true, "wilderness_encounter": ...,
-- "lair_entered": ..., "hex_cleared": ..., "dungeon_entered": ...,
-- "battle_resolved": ..., "siege_participated": ..., "treasure_returned_gp": int}

CREATE TABLE IF NOT EXISTS active_adventuring_log (
    id              TEXT    PRIMARY KEY,
    domain_id       TEXT    NOT NULL REFERENCES domains(id),
    calendar_day    INTEGER NOT NULL,
    is_active       INTEGER NOT NULL DEFAULT 0
        CHECK(is_active IN (0, 1)),
    triggers_json   TEXT    NOT NULL DEFAULT '{}',
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_active_adventuring_log_domain_id
    ON active_adventuring_log (domain_id);
CREATE INDEX IF NOT EXISTS idx_active_adventuring_log_calendar_day
    ON active_adventuring_log (calendar_day);
