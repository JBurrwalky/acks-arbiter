-- Migration 066: Character activity state (Domain Phase 3 - Strenuous Accountant)
--
-- Per-character background accounting for the strenuous-day / overtime rules
-- per `ax_campaign_play.xml` §effort_rules L166-172 and §overtime_rules L173-186:
--
--   "For every six game days of strenuous activity, a character must rest as
--    the day's major activity for one day. If required rest is not taken
--    after six days of strenuous activity, the character suffers a cumulative
--    -1 per day penalty to attack throws, damage rolls, and proficiency throws
--    until caught up on required rest."
--
-- The accountant tracks the running streak silently; combat / proficiency
-- resolvers consume the precomputed penalty via
-- StrenuousAccountant.get_attack_throw_penalty(character_id). The penalty
-- column is denormalized so hot-path reads do not have to recompute.
--
-- One row per character with at least one strenuous activity day on record.
-- Insert lazily; absent rows imply zero penalty.

CREATE TABLE IF NOT EXISTS character_activity_state (
    character_id              TEXT    PRIMARY KEY REFERENCES characters(id),
    strenuous_days_in_streak  INTEGER NOT NULL DEFAULT 0,
    overtime_days_in_streak   INTEGER NOT NULL DEFAULT 0,
    last_rest_day             INTEGER NOT NULL DEFAULT 0,
    attack_throw_penalty      INTEGER NOT NULL DEFAULT 0,
    last_updated_calendar_day INTEGER NOT NULL DEFAULT 0,
    created_at                TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                TEXT    NOT NULL DEFAULT (datetime('now'))
);
