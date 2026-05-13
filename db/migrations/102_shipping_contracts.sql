-- Migration 102: shipping_contracts table (Phase 10B prereq, wave Prereq.5c).
--
-- Per generation/gdd-settlement-economy.md §9.7. Tracks contracts the party
-- has ACCEPTED (available-but-unaccepted contracts are rolled fresh on each
-- market visit and don't persist). On accept, Phase 10B.2 also spawns a
-- linked `cargo_holds` row with `source_acquisition_kind='shipping_contract'`
-- and `shipping_contract_id` pointing back to the row created here.
--
-- Status lifecycle:
--   accepted        — contract live, cargo on a carrier, en route
--   in_transit      — explicit transit marker (optional refinement of accepted)
--   delivered       — on-time delivery; fee paid
--   failed_deadline — late delivery; v1 pays no fee
--   cancelled       — explicit cancellation
--
-- The cargo_holds.shipping_contract_id column (added in migration 101 but
-- ungoverned by FK) is the application-level linkage; deliver/cancel look
-- up cargo rows by shipping_contract_id == contract.id.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS shipping_contracts (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    accepted_by_party_id            TEXT    NOT NULL REFERENCES parties(id),
    origin_settlement_id            TEXT    NOT NULL REFERENCES settlement_entrances(id),
    destination_settlement_id       TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    loads_count                     INTEGER NOT NULL DEFAULT 0,
    fee_gp                          INTEGER NOT NULL DEFAULT 0,
    deadline_calendar_day           INTEGER NOT NULL DEFAULT 0,
    status                          TEXT    NOT NULL DEFAULT 'accepted'
        CHECK(status IN ('accepted', 'in_transit', 'delivered', 'failed_deadline', 'cancelled')),
    accepted_at_calendar_day        INTEGER NOT NULL DEFAULT 0,
    delivered_at_calendar_day       INTEGER,
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_shipping_contracts_party
    ON shipping_contracts(accepted_by_party_id, status);
CREATE INDEX IF NOT EXISTS idx_shipping_contracts_destination
    ON shipping_contracts(destination_settlement_id, status);
CREATE INDEX IF NOT EXISTS idx_shipping_contracts_campaign
    ON shipping_contracts(campaign_id, status);

COMMIT;
