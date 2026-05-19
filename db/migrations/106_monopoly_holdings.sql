-- Migration 106: monopoly_holdings (Phase 10B.2 — Trade block, Wave 1).
--
-- Per generation/gdd-phase-10b-2-trade-block.md §8.1 + §17.3.
--
-- Plumbing for MonopolyRegistry (§8.2) — the registry of
-- (character_id, settlement_id, merchandise_type) triples that confer the
-- RAW monopolist benefits (acore-campaign-hijinks.xml:713 +3 persuade
-- bonus; :714 2× transaction caps; substrate MarketPriceResolver's
-- monopolist_favor parameter).
--
-- v1 ships the API + table; population is later work (Phase 10B.3 decree
-- extension, etc.). Empty by default. `MonopolyRegistry.has_monopoly`
-- returns false for every lookup until rows are inserted.
--
-- UNIQUE(character_id, settlement_id, merchandise_type): a character can
-- hold at most one monopoly per triple. Re-grant requires revoke first.
--
-- granted_by_authority enumerates the canonical grant paths:
--   * 'domain_ruler' — settlement's parent domain owner issues the grant
--   * 'judge' — Judge-authored grant
--   * 'inherited' — story event / heritable grant
--   * 'purchased' — future market-for-monopolies
--
-- expires_at_calendar_day nullable: NULL = perpetual; non-null = sunset day.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS monopoly_holdings (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    character_id                    TEXT    NOT NULL REFERENCES characters(id),
    settlement_id                   TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    granted_at_calendar_day         INTEGER NOT NULL DEFAULT 0,
    granted_by_character_id         TEXT    REFERENCES characters(id),
    granted_by_authority            TEXT    NOT NULL DEFAULT 'domain_ruler'
        CHECK(granted_by_authority IN ('domain_ruler', 'judge', 'inherited', 'purchased')),
    expires_at_calendar_day         INTEGER,
    notes                           TEXT    NOT NULL DEFAULT '',
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(character_id, settlement_id, merchandise_type)
);

CREATE INDEX IF NOT EXISTS idx_monopoly_holdings_character
    ON monopoly_holdings(character_id);
CREATE INDEX IF NOT EXISTS idx_monopoly_holdings_settlement_merch
    ON monopoly_holdings(settlement_id, merchandise_type);

COMMIT;
