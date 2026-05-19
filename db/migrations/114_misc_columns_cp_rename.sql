-- Migration 114: rename + scale the remaining small-scope gp columns to cp
-- (ships, faith DP, magical research caps, crossbreed lab cap, congregants
-- pending growth) and rename domain_hexes.land_improvement_gp →
-- land_improvement_level (semantic correction — it stores a 0-3 level, not a
-- gp value).
--
-- Per the 2026-05-18 currency-unification sweep, these are the small,
-- single-table columns left over after Migration 113 (wage columns). The
-- larger compound columns (`gp_committed`, `gp_value`) live on three tables
-- each and are migrated in a follow-up pass.
--
-- Columns migrated (ALTER … RENAME + UPDATE … × 100):
--   ships.monthly_operating_cost_gp           → monthly_operating_cost_cp
--   congregants.monthly_growth_pending_gp     → monthly_growth_pending_cp
--   character_divine_power.divine_power_gp    → divine_power_cp
--   consecrated_altars.dp_substituted_gp      → dp_substituted_cp
--   workshops.max_item_value_supported_gp     → max_item_value_supported_cp
--   laboratories.max_crossbreed_cost_gp       → max_crossbreed_cost_cp
--
-- Semantic rename (NO scaling — stores 0-3 level integer, never money):
--   domain_hexes.land_improvement_gp          → land_improvement_level

BEGIN TRANSACTION;

ALTER TABLE ships RENAME COLUMN monthly_operating_cost_gp TO monthly_operating_cost_cp;
UPDATE ships SET monthly_operating_cost_cp = monthly_operating_cost_cp * 100;

ALTER TABLE congregants RENAME COLUMN monthly_growth_pending_gp TO monthly_growth_pending_cp;
UPDATE congregants SET monthly_growth_pending_cp = monthly_growth_pending_cp * 100;

ALTER TABLE character_divine_power RENAME COLUMN divine_power_gp TO divine_power_cp;
UPDATE character_divine_power SET divine_power_cp = divine_power_cp * 100;

ALTER TABLE consecrated_altars RENAME COLUMN dp_substituted_gp TO dp_substituted_cp;
UPDATE consecrated_altars SET dp_substituted_cp = dp_substituted_cp * 100;

ALTER TABLE workshops RENAME COLUMN max_item_value_supported_gp TO max_item_value_supported_cp;
UPDATE workshops SET max_item_value_supported_cp = max_item_value_supported_cp * 100;

ALTER TABLE laboratories RENAME COLUMN max_crossbreed_cost_gp TO max_crossbreed_cost_cp;
UPDATE laboratories SET max_crossbreed_cost_cp = max_crossbreed_cost_cp * 100;

-- Semantic rename only — column stores a 0-3 level, not gp. NO scaling.
ALTER TABLE domain_hexes RENAME COLUMN land_improvement_gp TO land_improvement_level;

COMMIT;
