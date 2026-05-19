-- Migration 113: rename + × 100 scale all remaining wage / cost columns
-- across the army, specialist, henchman, and stronghold-construction
-- subsystems to complete the troop wage cp pass.
--
-- Per the 2026-05-16 wage migration: the troop_units cost columns moved to
-- cp last session (Migration 112). This migration finishes the wage surface:
-- army officers, army supply state, specialists, henchmen wages (on the
-- characters table), henchman pool search costs, and stronghold engineer
-- wages.
--
-- Columns migrated (ALTER … RENAME + UPDATE … × 100):
--   characters.wage_gp_per_month                         → wage_cp_per_month
--   specialists.monthly_wage_gp                          → monthly_wage_cp
--   henchman_pools.search_cost_gp                        → search_cost_cp
--   stronghold_commissions.engineer_monthly_wage_gp      → engineer_monthly_wage_cp
--   army_officers.monthly_wage_gp                        → monthly_wage_cp
--   army_supply_state.weekly_supply_cost_gp              → weekly_supply_cost_cp
--   army_supply_state.current_stockpile_gp               → current_stockpile_cp
--
-- All values × 100 so existing rows keep their gp-magnitude semantics under
-- the new cp interpretation. After this migration:
--   * Army officer wages flow into army wage ledger in cp.
--   * Army supply stockpile + weekly cost are cp-native.
--   * Specialist hire wages are cp-native.
--   * Henchman per-month wages on the characters table are cp-native.
--   * Henchman-pool search costs are cp-native.
--   * Stronghold engineer wages are cp-native.

BEGIN TRANSACTION;

-- characters.wage_gp_per_month is NULLable (only set on henchman-type rows);
-- the UPDATE needs to handle the NULL case.
ALTER TABLE characters RENAME COLUMN wage_gp_per_month TO wage_cp_per_month;
UPDATE characters SET wage_cp_per_month = wage_cp_per_month * 100
	WHERE wage_cp_per_month IS NOT NULL;

ALTER TABLE specialists RENAME COLUMN monthly_wage_gp TO monthly_wage_cp;
UPDATE specialists SET monthly_wage_cp = monthly_wage_cp * 100;

ALTER TABLE henchman_pools RENAME COLUMN search_cost_gp TO search_cost_cp;
UPDATE henchman_pools SET search_cost_cp = search_cost_cp * 100;

ALTER TABLE stronghold_commissions RENAME COLUMN engineer_monthly_wage_gp TO engineer_monthly_wage_cp;
UPDATE stronghold_commissions SET engineer_monthly_wage_cp = engineer_monthly_wage_cp * 100;

ALTER TABLE army_officers RENAME COLUMN monthly_wage_gp TO monthly_wage_cp;
UPDATE army_officers SET monthly_wage_cp = monthly_wage_cp * 100;

ALTER TABLE army_supply_state RENAME COLUMN weekly_supply_cost_gp TO weekly_supply_cost_cp;
UPDATE army_supply_state SET weekly_supply_cost_cp = weekly_supply_cost_cp * 100;

ALTER TABLE army_supply_state RENAME COLUMN current_stockpile_gp TO current_stockpile_cp;
UPDATE army_supply_state SET current_stockpile_cp = current_stockpile_cp * 100;

COMMIT;
