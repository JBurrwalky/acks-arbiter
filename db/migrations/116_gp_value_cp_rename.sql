-- Migration 116: rename + scale the compound `gp_value` column (3 tables) to cp.
--
-- This completes Tier 2 of the unified-cp sweep (Tier 1 = Migration 114,
-- Tier 2A gp_committed/gp_invested = Migration 115).
--
-- gp_value (3 tables — each conceptually a "money value of this thing"):
--   strongholds.gp_value             — construction cost / minimum-value baseline
--   stronghold_accessories.gp_value  — cost of an installed accessory
--   vassal_obligations.gp_value      — cumulative money moved by this obligation
--
-- Out of scope (deferred):
--   vassal_obligations.magnitude     — heterogeneous semantic per `type` (some
--                                       are gp targets, some are family counts).
--                                       Stays in its current units; future pass
--                                       can decompose by type.
--   monsters.gp_value (no such DB column — XP/treasure equivalence lives in
--                       JSON/runtime catalogs)
--   inventory_items / merchandise (no `gp_value` column on either table)
--
-- These were the three remaining `gp_value` columns flagged for Tier 2 in the
-- Migration 114 build_log entry. Other Tier-2 candidates listed there
-- (monsters.gp_value, inventory_items.gp_value, merchandise.gp_value) turned
-- out not to exist as columns — that prompt was based on a faulty memory of
-- the schema; this migration covers the real targets.

BEGIN TRANSACTION;

ALTER TABLE strongholds RENAME COLUMN gp_value TO cp_value;
UPDATE strongholds SET cp_value = cp_value * 100;

ALTER TABLE stronghold_accessories RENAME COLUMN gp_value TO cp_value;
UPDATE stronghold_accessories SET cp_value = cp_value * 100;

ALTER TABLE vassal_obligations RENAME COLUMN gp_value TO cp_value;
UPDATE vassal_obligations SET cp_value = cp_value * 100;

COMMIT;
