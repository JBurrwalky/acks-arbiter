-- Migration 105: shipping_contract_offers (Phase 10B.2 — Trade block, Wave 1).
--
-- Per generation/gdd-phase-10b-2-trade-block.md §7.2 + §17.2.
--
-- Per-visit transient shipping offers. Rolled fresh on market entry by
-- ShippingContractOfferRoller.roll_for_visit (§7.6, Wave 4); CLEARed on
-- departure by VisitStateManager.on_party_departed_settlement (§9.6).
--
-- Offer accept path: accept_shipping_contract handler (§7.7, Wave 4) reads
-- the offer row, calls ShippingContractRepository.accept_contract +
-- CargoHoldRepository.insert_shipping_contract_load, then DELETEs the offer.
--
-- Lifecycle:
--   INSERT on entry → DELETE on either accept or departure. Idempotent;
--   re-entry without departure re-uses the existing rolled set per §7.6's
--   own idempotency.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS shipping_contract_offers (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    party_id                        TEXT    NOT NULL REFERENCES parties(id),
    origin_settlement_id            TEXT    NOT NULL REFERENCES settlement_entrances(id),
    destination_settlement_id       TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    loads_count                     INTEGER NOT NULL DEFAULT 0,
    load_weight_stone               INTEGER NOT NULL DEFAULT 0,
    route_mode                      TEXT    NOT NULL DEFAULT 'road'
        CHECK(route_mode IN ('road', 'water')),
    distance_miles                  INTEGER NOT NULL DEFAULT 0,
    fee_gp                          INTEGER NOT NULL DEFAULT 0,
    deadline_calendar_day           INTEGER NOT NULL DEFAULT 0,
    rolled_at_calendar_day          INTEGER NOT NULL DEFAULT 0,
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_shipping_contract_offers_party
    ON shipping_contract_offers(party_id, origin_settlement_id);

COMMIT;
