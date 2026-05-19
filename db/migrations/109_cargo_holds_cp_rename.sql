-- Migration 109: rename cargo_holds.market_value_at_acquisition_gp → _cp.
--
-- Per the 2026-05-15 currency-precision rule: cp is the project's base
-- currency. The column was populated from the buy handler's purchase cp
-- value (recently migrated from gp), so existing rows already hold cp
-- magnitudes — but the column NAME still says gp. This migration:
--   1. Renames the column to its correct unit.
--   2. Does NOT scale existing data; the buy handler started writing cp
--      values when the §10B.2 currency-precision pass shipped (migration
--      108 era), so any pre-108 row would be off by 100×. v1 development
--      has no production DBs older than that, so we don't risk a backfill.
--   3. The smuggling/stolen-path (insert_hijink_yield) is Phase 10B.3
--      future work; no rows exist yet.

BEGIN TRANSACTION;

ALTER TABLE cargo_holds RENAME COLUMN market_value_at_acquisition_gp TO market_value_at_acquisition_cp;

COMMIT;
