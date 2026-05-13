-- Migration 099: merchant_pool cache table (Phase 10B prereq, wave Prereq.4).
--
-- Per generation/gdd-settlement-economy.md §7.8. Ships sub-step 11 of the
-- §13.0 consolidated migration plan as a standalone migration (097 was
-- the bulk settlement-economy substrate; 098 added trade_routes; 099
-- adds the merchant pool).
--
-- One row per merchant per cohort. Cohort lifecycle is 28 days
-- (Timekeeping.DAYS_PER_MONTH); monthly refresh wipes the previous cohort
-- and generates a fresh one with max_merchant_count(class) rows.
--
-- Visibility:
--   becomes_visible_calendar_day = 2147483647 (INT32_MAX sentinel) = invisible.
--   becomes_visible_calendar_day <= current_calendar_day = visible.
--   PC-owned domains get current_calendar_day at generation; everyone else
--   gets the sentinel and requires solicit_merchants / locate_merchandise
--   to flip visibility.

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS merchant_pool (
    id                              TEXT    PRIMARY KEY,
    campaign_id                     TEXT    NOT NULL REFERENCES campaigns(id),
    settlement_entrance_id          TEXT    NOT NULL REFERENCES settlement_entrances(id),
    merchandise_type                TEXT    NOT NULL,
    loads_available                 INTEGER NOT NULL DEFAULT 0,
    loads_initial                   INTEGER NOT NULL DEFAULT 0,
    created_at_calendar_day         INTEGER NOT NULL DEFAULT 0,
    expires_at_calendar_day         INTEGER NOT NULL DEFAULT 0,
    becomes_visible_calendar_day    INTEGER NOT NULL DEFAULT 2147483647,
    status                          TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'depleted', 'expired')),
    source_kind                     TEXT    NOT NULL DEFAULT 'monthly_refresh'
        CHECK(source_kind IN ('monthly_refresh', 'manual')),
    created_at                      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_merchant_pool_settlement_status
    ON merchant_pool(settlement_entrance_id, status);
CREATE INDEX IF NOT EXISTS idx_merchant_pool_settlement_merchandise
    ON merchant_pool(settlement_entrance_id, merchandise_type, status);
CREATE INDEX IF NOT EXISTS idx_merchant_pool_expiration
    ON merchant_pool(expires_at_calendar_day, status);
CREATE INDEX IF NOT EXISTS idx_merchant_pool_visibility
    ON merchant_pool(settlement_entrance_id, becomes_visible_calendar_day);

COMMIT;
