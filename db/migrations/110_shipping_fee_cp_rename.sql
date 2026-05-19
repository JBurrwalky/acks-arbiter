-- Migration 110: rename shipping_contracts.fee_gp and
-- shipping_contract_offers.fee_gp → fee_cp.
--
-- Per the 2026-05-15 currency-precision rule: cp is the project's base
-- currency. Shipping fees were stored in gp; on completion the repository
-- multiplied by 100 to credit cp to the party wallet (the `_credit_party_fee`
-- helper). Migrating to cp removes that conversion and aligns with the
-- broader commerce migration.
--
-- v1 development has no production DBs with pre-migration data; existing
-- shipping_contract_offer rows (ephemeral, per-visit) and contract rows
-- (campaign-persistent) will be scaled by 100 in the same transaction so
-- in-flight contracts continue to pay the same gp magnitude.

BEGIN TRANSACTION;

ALTER TABLE shipping_contracts RENAME COLUMN fee_gp TO fee_cp;
UPDATE shipping_contracts SET fee_cp = fee_cp * 100;

ALTER TABLE shipping_contract_offers RENAME COLUMN fee_gp TO fee_cp;
UPDATE shipping_contract_offers SET fee_cp = fee_cp * 100;

COMMIT;
