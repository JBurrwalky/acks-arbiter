-- Migration 163: add the §7.4f "cultural_shift" event type to setting_events.type.
-- A sovereign realm that has come to rule a large, more-developed foreign subject
-- can adopt that subject's culture (the conqueror "goes native" — Yuan→Chinese,
-- Norman→English), emitted by HistorySimulator._phase_go_native / _apply_go_native
-- as "cultural_shift" (cultures = [from, to], polities = [realm]). SQLite cannot
-- ALTER a CHECK, so rebuild the table (regenerated setting output; existing rows
-- copied for safety). Without the type the event INSERT fails the CHECK and the
-- whole history_sim layer (and generation) aborts.

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
                       'cultural_shift')),
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
