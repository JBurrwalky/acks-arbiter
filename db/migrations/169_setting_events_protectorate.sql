-- Migration 169: add the §7.4f "protectorate" event type to setting_events.type.
-- Phase 3 auto-coagulation: a viable but sub-Duchy SOVEREIGN realm peacefully joins a
-- stronger same-majority-culture realm within a tier-scaled reach as a vassal (a "treaty
-- of protection") rather than being silently consolidated away. Emitted by
-- HistorySimulator._coagulate as "protectorate" (polities = [joiner, protector],
-- cultures = [joiner, protector]). SQLite cannot ALTER a CHECK, so rebuild the table
-- (regenerated setting output; existing rows copied for safety). Without the type the
-- event INSERT fails the CHECK and the whole history_sim layer (and generation) aborts.

CREATE TABLE setting_events_new (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    tick INTEGER NOT NULL,
    year_before_start INTEGER NOT NULL DEFAULT 0,
    type TEXT NOT NULL
        CHECK(type IN ('founding', 'expansion', 'war', 'conquest', 'vassalage',
                       'secession', 'pillage', 'schism', 'migration',
                       'collapse_rump', 'collapse_shatter', 'depopulation',
                       'golden_age', 'dynasty_change', 'alignment_drift',
                       'rebellion', 'rebellion_won', 'rebellion_concession',
                       'rebellion_crushed', 'rebellion_extinguished', 'razing',
                       'cultural_shift', 'protectorate')),
    polity_ids TEXT NOT NULL DEFAULT '[]',
    culture_ids TEXT NOT NULL DEFAULT '[]',
    hexes TEXT NOT NULL DEFAULT '[]',
    region_hint TEXT NOT NULL DEFAULT '',
    severity REAL NOT NULL DEFAULT 0.0,
    significance REAL NOT NULL DEFAULT 0.0,
    summary_key TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, id)
);

INSERT INTO setting_events_new SELECT * FROM setting_events;
DROP TABLE setting_events;
ALTER TABLE setting_events_new RENAME TO setting_events;

CREATE INDEX IF NOT EXISTS idx_setting_events_tick
    ON setting_events(campaign_id, tick);
