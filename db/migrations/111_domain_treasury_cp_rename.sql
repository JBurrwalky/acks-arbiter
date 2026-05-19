-- Migration 111: rename domain treasury / ledger / rate columns from gp to cp.
--
-- Per the 2026-05-15 currency-precision rule: cp is the project's base
-- currency. This migration completes the Phase 7 carry-forward
-- `[NEEDS-DOMAIN-TREASURY-CP-PASS]` by renaming the persistent domain
-- treasury + ledger + rate columns and scaling existing values × 100.
--
-- Columns migrated (each: ALTER … RENAME + UPDATE … * 100):
--   domains.treasury_gp                                → treasury_cp
--   domains.deferred_maintenance_gp                    → deferred_maintenance_cp
--   domains.pending_investment_gp                      → pending_investment_cp
--   domains.tax_rate_gp_per_family                     → tax_rate_cp_per_family
--   domains.liturgy_rate_gp_per_family                 → liturgy_rate_cp_per_family
--   domains.tithe_rate_gp_per_family                   → tithe_rate_cp_per_family
--   domains.repression_gp_per_family_this_month        → repression_cp_per_family_this_month
--   domains.revenue_gp                                 → revenue_cp
--   domains.expenses_gp                                → expenses_cp
--   domains.net_income_gp                              → net_income_cp
--   ledger_entries.gp_amount                           → cp_amount
--
-- All values multiply by 100 so existing balances/rates preserve their
-- gp-magnitude meaning under the new cp interpretation.

BEGIN TRANSACTION;

ALTER TABLE domains RENAME COLUMN treasury_gp TO treasury_cp;
UPDATE domains SET treasury_cp = treasury_cp * 100;

ALTER TABLE domains RENAME COLUMN deferred_maintenance_gp TO deferred_maintenance_cp;
UPDATE domains SET deferred_maintenance_cp = deferred_maintenance_cp * 100;

ALTER TABLE domains RENAME COLUMN pending_investment_gp TO pending_investment_cp;
UPDATE domains SET pending_investment_cp = pending_investment_cp * 100;

ALTER TABLE domains RENAME COLUMN tax_rate_gp_per_family TO tax_rate_cp_per_family;
UPDATE domains SET tax_rate_cp_per_family = tax_rate_cp_per_family * 100;

ALTER TABLE domains RENAME COLUMN liturgy_rate_gp_per_family TO liturgy_rate_cp_per_family;
UPDATE domains SET liturgy_rate_cp_per_family = liturgy_rate_cp_per_family * 100;

ALTER TABLE domains RENAME COLUMN tithe_rate_gp_per_family TO tithe_rate_cp_per_family;
UPDATE domains SET tithe_rate_cp_per_family = tithe_rate_cp_per_family * 100;

ALTER TABLE domains RENAME COLUMN repression_gp_per_family_this_month TO repression_cp_per_family_this_month;
UPDATE domains SET repression_cp_per_family_this_month = repression_cp_per_family_this_month * 100;

ALTER TABLE domains RENAME COLUMN revenue_gp TO revenue_cp;
UPDATE domains SET revenue_cp = revenue_cp * 100;

ALTER TABLE domains RENAME COLUMN expenses_gp TO expenses_cp;
UPDATE domains SET expenses_cp = expenses_cp * 100;

ALTER TABLE domains RENAME COLUMN net_income_gp TO net_income_cp;
UPDATE domains SET net_income_cp = net_income_cp * 100;

ALTER TABLE ledger_entries RENAME COLUMN gp_amount TO cp_amount;
UPDATE ledger_entries SET cp_amount = cp_amount * 100;

COMMIT;
