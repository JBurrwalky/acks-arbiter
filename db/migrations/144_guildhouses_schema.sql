-- Migration 144: guildhouses table (Venturer→Guildhouse refactor).
--
-- Per the Venturer→Guildhouse decoupling: the Venturer does NOT run a domain.
-- Its late-game vehicle is a GUILDHOUSE (which RAW `ax_venturer_class.xml` says
-- "follows the rules for hideouts") in an urban settlement, plus an L12
-- settlement MONOPOLY (1gp/urban-family/month). The guildhouse is its OWN
-- structure, NOT a strongholds row: it secures no domain.
--
-- Apprentices are NOT stored here. They are individual `followers` rows with
-- source_kind='venturer_apprentice' (the pre-existing unified roster), so they
-- can level up, be recruited as henchmen, and become full NPCs. A guildhouse's
-- apprentice count is derived by counting those follower rows (by owner).
--
-- cp_value: money × 100, funded at founding to >= the market-class minimum
--   (reuses the RAW hideout_size_and_cost table — the guildhouse follows hideout
--   rules, so HideoutCostTable applies).
-- market_class: snapshot of the host settlement (INTEGER 1..6; 6 = Class VI).
-- monopoly_seized: 1 once an L12 venturer seizes settlement monopoly power here.
-- status: active / abandoned / seized (mirrors the hideouts vocabulary).
--
-- Non-destructive: CREATE TABLE IF NOT EXISTS, per the migration 143 pattern.
-- (No `followers` migration is needed — its source_kind enum already includes
-- 'venturer_apprentice'.)
CREATE TABLE IF NOT EXISTS guildhouses (
    id                           TEXT    PRIMARY KEY,
    campaign_id                  TEXT    NOT NULL REFERENCES campaigns(id),
    owner_character_id           TEXT    NOT NULL REFERENCES characters(id),
    host_settlement_entrance_id  TEXT    NOT NULL REFERENCES settlement_entrances(id),
    market_class                 INTEGER NOT NULL DEFAULT 6,
    cp_value                     INTEGER NOT NULL DEFAULT 0,
    location_map_id              TEXT    REFERENCES hex_maps(id),
    location_hex_q               INTEGER,
    location_hex_r               INTEGER,
    monopoly_seized              INTEGER NOT NULL DEFAULT 0
        CHECK(monopoly_seized IN (0, 1)),
    monopoly_seized_day          INTEGER,
    status                       TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'abandoned', 'seized')),
    created_at                   TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                   TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_guildhouses_campaign   ON guildhouses(campaign_id);
CREATE INDEX IF NOT EXISTS idx_guildhouses_owner      ON guildhouses(owner_character_id);
CREATE INDEX IF NOT EXISTS idx_guildhouses_settlement ON guildhouses(host_settlement_entrance_id);
