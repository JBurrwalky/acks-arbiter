-- Migration 115: rename + scale the compound `gp_committed` / `gp_invested`
-- columns (and the two stronghold-commission construction-rate companions:
-- `gp_progressed` + `daily_construction_rate_gp`) to cp.
--
-- This is Tier 2 of the unified-cp sweep (Tier 1 = Migration 114). These
-- columns share names across multiple tables (the "compound" columns) and
-- have wider caller surface than the single-table renames in Migration 114.
--
-- gp_committed (3 tables — cumulative cost commitment / activity spend):
--   activity_state.gp_committed     → cp_committed
--   stronghold_commissions.gp_committed     → cp_committed
--   magic_research_projects.gp_committed    → cp_committed
--
-- gp_invested (4 tables — cumulative investment gating capability):
--   consecrated_altars.gp_invested          → cp_invested
--   libraries.gp_invested                   → cp_invested
--   workshops.gp_invested                   → cp_invested
--   laboratories.gp_invested                → cp_invested
--
-- Stronghold-commission construction-rate companions (kept with gp_committed
-- so the whole commission row is cp-native after this migration):
--   stronghold_commissions.gp_progressed              → cp_progressed
--   stronghold_commissions.daily_construction_rate_gp → daily_construction_rate_cp

BEGIN TRANSACTION;

-- gp_committed (3 tables)
ALTER TABLE activity_state RENAME COLUMN gp_committed TO cp_committed;
UPDATE activity_state SET cp_committed = cp_committed * 100;

ALTER TABLE stronghold_commissions RENAME COLUMN gp_committed TO cp_committed;
UPDATE stronghold_commissions SET cp_committed = cp_committed * 100;

ALTER TABLE magic_research_projects RENAME COLUMN gp_committed TO cp_committed;
UPDATE magic_research_projects SET cp_committed = cp_committed * 100;

-- gp_invested (4 tables)
ALTER TABLE consecrated_altars RENAME COLUMN gp_invested TO cp_invested;
UPDATE consecrated_altars SET cp_invested = cp_invested * 100;

ALTER TABLE libraries RENAME COLUMN gp_invested TO cp_invested;
UPDATE libraries SET cp_invested = cp_invested * 100;

ALTER TABLE workshops RENAME COLUMN gp_invested TO cp_invested;
UPDATE workshops SET cp_invested = cp_invested * 100;

ALTER TABLE laboratories RENAME COLUMN gp_invested TO cp_invested;
UPDATE laboratories SET cp_invested = cp_invested * 100;

-- Stronghold-commission construction-rate companions
ALTER TABLE stronghold_commissions RENAME COLUMN gp_progressed TO cp_progressed;
UPDATE stronghold_commissions SET cp_progressed = cp_progressed * 100;

ALTER TABLE stronghold_commissions RENAME COLUMN daily_construction_rate_gp TO daily_construction_rate_cp;
UPDATE stronghold_commissions SET daily_construction_rate_cp = daily_construction_rate_cp * 100;

COMMIT;
