-- Migration 158: setting_fortifications (Layer 6 §9.5 fort placement).
--
-- Strongholds (one per Class I-III market, valued by realm tier), border forts
-- (along realm frontiers, denser on sim-hot frontiers), and watchtowers (along
-- trunk roads through borderlands). Written only by the generator, frozen by the
-- Layer-8 lock like the rest of the setting_* tables.
CREATE TABLE IF NOT EXISTS setting_fortifications (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    hex_q INTEGER NOT NULL,
    hex_r INTEGER NOT NULL,
    fort_type TEXT NOT NULL DEFAULT 'border_fort' CHECK(fort_type IN ('border_fort', 'stronghold', 'watchtower')),
    owner_polity_id TEXT NOT NULL DEFAULT '',
    settlement_id TEXT NOT NULL DEFAULT '',
    road_id TEXT NOT NULL DEFAULT '',
    stronghold_value_gp INTEGER NOT NULL DEFAULT 0,
    is_hot INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (campaign_id, id)
);
