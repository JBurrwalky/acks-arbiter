-- Migration 028: Event scheduler tables
--
-- Persistence for the real-time-with-pause event scheduler (GDD §2).
-- scheduled_events stores the priority queue between save/load cycles.
-- auto_pause_config stores per-campaign player preferences for which
-- event categories trigger auto-pause.

CREATE TABLE IF NOT EXISTS scheduled_events (
    event_id        TEXT    PRIMARY KEY,
    campaign_id     TEXT    NOT NULL REFERENCES campaigns(id),
    fire_time       INTEGER NOT NULL,
    event_type      TEXT    NOT NULL,
    owner_id        TEXT    NOT NULL DEFAULT '',
    data_json       TEXT    NOT NULL DEFAULT '{}',
    priority        INTEGER NOT NULL DEFAULT 20,
    cancelled       INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_scheduled_events_fire_time
    ON scheduled_events(campaign_id, fire_time);

CREATE INDEX IF NOT EXISTS idx_scheduled_events_owner
    ON scheduled_events(campaign_id, owner_id);


CREATE TABLE IF NOT EXISTS auto_pause_config (
    campaign_id     TEXT    NOT NULL REFERENCES campaigns(id),
    event_category  TEXT    NOT NULL,
    pause_tier      INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (campaign_id, event_category)
);
