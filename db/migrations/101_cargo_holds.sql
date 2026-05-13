-- Migration 101: cargo_holds table (Phase 10B prereq, wave Prereq.5b).
--
-- Per generation/gdd-settlement-economy.md §9.4. One row per cargo
-- acquisition; `loads_count` aggregates identical fungible loads from the
-- same source. Different acquisitions of the same merchandise type stay in
-- separate rows so each shipment retains its own market_value snapshot for
-- arbitrage profit tracking.
--
-- XOR carrier CHECK enforces "exactly one of draft_vehicle_id / ship_id is
-- non-null per row." Typed FKs preserve referential integrity over a
-- polymorphic carrier_kind/carrier_id pattern.
--
-- ON DELETE CASCADE on both carrier FKs means destroying the carrier row
-- destroys its cargo. SQLite FK enforcement is OFF by default in
-- godot-sqlite; the CASCADE is documented defensive behavior for any path
-- that turns FK enforcement on. v1 carrier destruction uses the soft-delete
-- pattern (is_destroyed=1) which does NOT trigger CASCADE — explicit
-- cargo cleanup happens at caller discretion.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS cargo_holds (
    id                                  TEXT    PRIMARY KEY,
    campaign_id                         TEXT    NOT NULL REFERENCES campaigns(id),
    draft_vehicle_id                    TEXT    REFERENCES draft_vehicles(id) ON DELETE CASCADE,
    ship_id                             TEXT    REFERENCES ships(id) ON DELETE CASCADE,
    merchandise_type                    TEXT    NOT NULL,
    loads_count                         INTEGER NOT NULL DEFAULT 0,
    load_weight_stone                   INTEGER NOT NULL DEFAULT 0,
    market_value_at_acquisition_gp      INTEGER NOT NULL DEFAULT 0,
    source_acquisition_kind             TEXT    NOT NULL DEFAULT 'purchased'
        CHECK(source_acquisition_kind IN ('purchased', 'smuggled', 'stolen', 'shipping_contract')),
    acquired_at_settlement_id           TEXT    REFERENCES settlement_entrances(id),
    acquired_at_calendar_day            INTEGER NOT NULL DEFAULT 0,
    shipping_contract_id                TEXT,
    notes                               TEXT    NOT NULL DEFAULT '',
    created_at                          TEXT    NOT NULL DEFAULT (datetime('now')),
    CHECK ((draft_vehicle_id IS NOT NULL) <> (ship_id IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_cargo_holds_draft_vehicle
    ON cargo_holds(draft_vehicle_id) WHERE draft_vehicle_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cargo_holds_ship
    ON cargo_holds(ship_id) WHERE ship_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cargo_holds_merchandise
    ON cargo_holds(merchandise_type);
CREATE INDEX IF NOT EXISTS idx_cargo_holds_campaign
    ON cargo_holds(campaign_id);

COMMIT;
