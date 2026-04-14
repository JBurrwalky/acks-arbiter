-- Migration 029: Shop inventory and commissions for settlement commerce system
--
-- shop_inventory: persists generated shop stock per POI.
-- Generated on first visit, refreshed monthly (30 game-days).
-- commissions: tracks equipment commissions placed by characters.

CREATE TABLE IF NOT EXISTS shop_inventory (
    id                  TEXT    PRIMARY KEY,
    campaign_id         TEXT    NOT NULL REFERENCES campaigns(id),
    settlement_id       TEXT    NOT NULL,
    poi_id              TEXT    NOT NULL,
    item_key            TEXT    NOT NULL,
    quantity_available  INTEGER NOT NULL DEFAULT 0,
    generated_at_round  INTEGER NOT NULL DEFAULT 0,
    UNIQUE(campaign_id, poi_id, item_key)
);

CREATE INDEX IF NOT EXISTS idx_shop_inventory_poi
    ON shop_inventory(campaign_id, poi_id);

CREATE TABLE IF NOT EXISTS commissions (
    id                  TEXT    PRIMARY KEY,
    campaign_id         TEXT    NOT NULL REFERENCES campaigns(id),
    settlement_id       TEXT    NOT NULL,
    poi_id              TEXT    NOT NULL,
    character_id        TEXT    NOT NULL REFERENCES characters(id),
    item_key            TEXT    NOT NULL,
    quantity            INTEGER NOT NULL DEFAULT 1,
    cost_cp             INTEGER NOT NULL DEFAULT 0,
    ordered_at_round    INTEGER NOT NULL DEFAULT 0,
    ready_at_round      INTEGER NOT NULL DEFAULT 0,
    picked_up           INTEGER NOT NULL DEFAULT 0 CHECK(picked_up IN (0, 1))
);

CREATE INDEX IF NOT EXISTS idx_commissions_poi
    ON commissions(campaign_id, poi_id);

CREATE INDEX IF NOT EXISTS idx_commissions_character
    ON commissions(campaign_id, character_id);
