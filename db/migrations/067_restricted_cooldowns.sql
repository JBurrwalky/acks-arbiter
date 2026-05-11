-- Migration 067: Restricted-frequency activity cooldowns (Domain Phase 3)
--
-- Tracks the per-(character, activity_def) cooldown that gates Restricted-
-- frequency activities per `ax_campaign_play.xml` §frequency_types L156-158:
--
--   "Restricted: takes place within a single game day but cannot be repeated
--    until the stated time period elapses."
--
-- One row per (character_id, activity_def_id) pair currently on cooldown.
-- `cooldown_until_round` is an absolute game-time round count compared against
-- Timekeeping's elapsed-rounds counter. Rows past their cooldown can be
-- cleared opportunistically by the executor.

CREATE TABLE IF NOT EXISTS restricted_cooldowns (
    campaign_id          TEXT    NOT NULL REFERENCES campaigns(id),
    character_id         TEXT    NOT NULL REFERENCES characters(id),
    activity_def_id      TEXT    NOT NULL,
    cooldown_until_round INTEGER NOT NULL,
    created_at           TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (character_id, activity_def_id)
);

CREATE INDEX IF NOT EXISTS idx_restricted_cooldowns_campaign
    ON restricted_cooldowns (campaign_id);
