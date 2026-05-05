-- Migration 052: Tracking & pursuit state (Wilderness closure Phase 5).
--
-- tracking_sessions: per-party-per-trail record of an active tracking attempt.
-- Per acore_proficiencies_rules_and_catalog.xml Tracking entry — characters
-- move at half speed while tracking; weather decay accumulates against the
-- trail (-1 per 12 hours of good weather, -4 per hour of rain/snow). One
-- session per (party, target). Closes on success/failure/abandonment.
--
-- pursuit_states: per-party-per-pursuer record of a failed wilderness evasion.
-- Per acore_adventures_and_encounters.xml §chases_in_the_wilderness — when
-- evasion fails the pursuer keeps the fleeing party in sight; daily 50%
-- catch-up roll repeats until a side ends the chase.

CREATE TABLE IF NOT EXISTS tracking_sessions (
    session_id              TEXT    PRIMARY KEY,
    campaign_id             TEXT    NOT NULL REFERENCES campaigns(id),
    party_id                TEXT    NOT NULL REFERENCES parties(id),
    target_kind             TEXT    NOT NULL DEFAULT 'creature_group'
        CHECK(target_kind IN ('creature_group', 'character', 'caravan')),
    target_label            TEXT    NOT NULL DEFAULT '',
    target_size             INTEGER NOT NULL DEFAULT 1,
    started_at_round        INTEGER NOT NULL DEFAULT 0,
    started_terrain         TEXT    NOT NULL DEFAULT 'clear',
    weather_decay_total     REAL    NOT NULL DEFAULT 0.0,
    last_check_round        INTEGER NOT NULL DEFAULT -1,
    closed                  INTEGER NOT NULL DEFAULT 0 CHECK(closed IN (0, 1)),
    closed_reason           TEXT    NOT NULL DEFAULT ''
        CHECK(closed_reason IN ('', 'success', 'lost_trail', 'abandoned',
                                 'caught_up', 'engaged'))
);

CREATE INDEX IF NOT EXISTS idx_tracking_sessions_party
    ON tracking_sessions(campaign_id, party_id, closed);


CREATE TABLE IF NOT EXISTS pursuit_states (
    pursuit_id              TEXT    PRIMARY KEY,
    campaign_id             TEXT    NOT NULL REFERENCES campaigns(id),
    party_id                TEXT    NOT NULL REFERENCES parties(id),
    pursuer_label           TEXT    NOT NULL DEFAULT '',
    pursuer_size            INTEGER NOT NULL DEFAULT 1,
    pursuer_speed_advantage INTEGER NOT NULL DEFAULT 0,
    started_at_round        INTEGER NOT NULL DEFAULT 0,
    last_check_round        INTEGER NOT NULL DEFAULT -1,
    days_in_pursuit         INTEGER NOT NULL DEFAULT 0,
    closed                  INTEGER NOT NULL DEFAULT 0 CHECK(closed IN (0, 1)),
    closed_reason           TEXT    NOT NULL DEFAULT ''
        CHECK(closed_reason IN ('', 'evaded', 'caught', 'abandoned'))
);

CREATE INDEX IF NOT EXISTS idx_pursuit_states_party
    ON pursuit_states(campaign_id, party_id, closed);
