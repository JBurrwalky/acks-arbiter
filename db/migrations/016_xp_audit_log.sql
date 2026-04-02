-- Migration 016: XP audit log table
-- Tracks XP awards by source for journal display and debugging.
-- Source types: adventure_monster, adventure_treasure, domain, mercantile,
--               hijinks, construction, other.

CREATE TABLE IF NOT EXISTS xp_awards (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id    TEXT    NOT NULL REFERENCES characters(id),
    campaign_id     TEXT    NOT NULL REFERENCES campaigns(id),
    amount          INTEGER NOT NULL,
    source_type     TEXT    NOT NULL DEFAULT 'adventure_monster'
        CHECK(source_type IN (
            'adventure_monster',
            'adventure_treasure',
            'domain',
            'mercantile',
            'hijinks',
            'construction',
            'other'
        )),
    description     TEXT    NOT NULL DEFAULT '',
    adventure_id    TEXT    NOT NULL DEFAULT '',
    awarded_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_xp_awards_character
    ON xp_awards(character_id);

CREATE INDEX IF NOT EXISTS idx_xp_awards_campaign
    ON xp_awards(campaign_id);
