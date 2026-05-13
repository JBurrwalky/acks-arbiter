-- Migration 098: trade_routes cache table (Phase 10B prereq, wave Prereq.2b).
--
-- Per generation/gdd-settlement-economy.md §5.5. Ships sub-step 10 of the
-- §13.0 consolidated migration plan — the trade_routes cache consumed by
-- the region resolver (§5.3) that applies RAW step 6 demand modifier shifts.
--
-- One row per ordered pair (settlement_a_id < settlement_b_id) of settlements
-- connected by a valid trade route per RAW criteria
-- (rules/acore-setting-construction-rules.xml:358-365):
--   1. A connecting road, trail, or navigable waterway exists.
--   2. Both markets lie within each other's range_of_trade
--      (acore-setting-construction-rules.xml:264-278).
--
-- The detector (engine/subsystems/commerce/trade_route_detector.gd) writes
-- rows here; the region resolver
-- (engine/subsystems/commerce/region_demand_resolver.gd) reads them.
--
-- invalidated is a soft-delete flag (§5.5) — topology changes mark routes
-- as invalidated=1 so an in-flight region walk completes against a stable
-- snapshot; the next detection sweep either confirms (resets to 0) or
-- deletes the row.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS trade_routes (
    id                          TEXT    PRIMARY KEY,
    campaign_id                 TEXT    NOT NULL REFERENCES campaigns(id),
    settlement_a_id             TEXT    NOT NULL REFERENCES settlement_entrances(id),
    settlement_b_id             TEXT    NOT NULL REFERENCES settlement_entrances(id),
    path_kind                   TEXT    NOT NULL
        CHECK(path_kind IN ('road', 'water', 'mixed')),
    distance_hexes              INTEGER NOT NULL,
    discovered_at_calendar_day  INTEGER NOT NULL DEFAULT 0,
    invalidated                 INTEGER NOT NULL DEFAULT 0
        CHECK(invalidated IN (0, 1)),
    -- Canonical pair ordering enforced so one row represents the pair.
    CHECK(settlement_a_id < settlement_b_id),
    UNIQUE(settlement_a_id, settlement_b_id)
);

CREATE INDEX IF NOT EXISTS idx_trade_routes_a
    ON trade_routes(settlement_a_id, invalidated);
CREATE INDEX IF NOT EXISTS idx_trade_routes_b
    ON trade_routes(settlement_b_id, invalidated);
CREATE INDEX IF NOT EXISTS idx_trade_routes_campaign
    ON trade_routes(campaign_id, invalidated);

COMMIT;
