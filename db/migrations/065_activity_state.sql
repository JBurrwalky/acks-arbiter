-- Migration 065: Activity state (Domain Phase 3 - Activity Time-Cost Executor)
--
-- Persists per-character ongoing-frequency activities across game days.
-- Singular and Restricted activities resolve atomically inside the
-- EventScheduler and do NOT persist between days; only Ongoing-frequency
-- activities (`administer_domain`, `oversee_investment`, `magical_research`,
-- `plan_hijink`, etc.) need cross-day state.
--
-- Per `gdd-realtime-scheduler.md` §4.8.3 and `gdd-domain-tab.md` §15.1,
-- each Ongoing activity tracks `ticks_accumulated` (days the daily session
-- fired uninterrupted while the character was at the required location)
-- and `absence_accumulated` (days the character was away or otherwise
-- unable to perform the activity). Tick-tolerance is enforced when
-- `absence_accumulated > ticks_accumulated` (forfeit at next daily boundary).
--
-- frequency_type: 'singular' | 'restricted' | 'ongoing'
-- status: 'active' | 'completed' | 'forfeited' | 'abandoned'
-- location_kind: 'anywhere' | 'in_domain' | 'at_stronghold' | 'at_settlement'
--                | 'at_construction_site' | 'at_dungeon' | 'at_wilderness_hex'
-- location_ref:  free-form pointer matching location_kind (e.g. "domain:<id>",
--                "stronghold:<id>", "settlement:<id>", "hex:<q>,<r>")
-- params_json:   activity-specific launch parameters (e.g. issue_decree value,
--                repress_population gp/family, oversee_investment gp_committed)
-- scheduled_event_id: the EventScheduler event_id of the in-flight session
--                     (empty when no session is currently scheduled)

CREATE TABLE IF NOT EXISTS activity_state (
    id                   TEXT    PRIMARY KEY,
    campaign_id          TEXT    NOT NULL REFERENCES campaigns(id),
    character_id         TEXT    NOT NULL REFERENCES characters(id),
    activity_def_id      TEXT    NOT NULL,
    frequency_type       TEXT    NOT NULL
        CHECK(frequency_type IN ('singular', 'restricted', 'ongoing')),
    status               TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'completed', 'forfeited', 'abandoned')),
    location_kind        TEXT    NOT NULL DEFAULT 'anywhere',
    location_ref         TEXT    NOT NULL DEFAULT '',
    time_cost_rounds     INTEGER NOT NULL DEFAULT 0,
    ticks_required       INTEGER NOT NULL DEFAULT 1,
    ticks_accumulated    INTEGER NOT NULL DEFAULT 0,
    absence_accumulated  INTEGER NOT NULL DEFAULT 0,
    started_calendar_day INTEGER NOT NULL DEFAULT 0,
    last_session_day     INTEGER NOT NULL DEFAULT 0,
    gp_committed         INTEGER NOT NULL DEFAULT 0,
    params_json          TEXT    NOT NULL DEFAULT '{}',
    scheduled_event_id   TEXT    NOT NULL DEFAULT '',
    created_at           TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at           TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_activity_state_character
    ON activity_state (character_id);
CREATE INDEX IF NOT EXISTS idx_activity_state_activity_def
    ON activity_state (activity_def_id);
CREATE INDEX IF NOT EXISTS idx_activity_state_status
    ON activity_state (status);
CREATE INDEX IF NOT EXISTS idx_activity_state_campaign
    ON activity_state (campaign_id);
