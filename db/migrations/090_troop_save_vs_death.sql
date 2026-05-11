-- Migration 090: troop_units.save_vs_death — Phase 9C polish.
--
-- DiseaseResolver previously used a flat target=14 vs Death for all troops.
-- This migration adds a per-troop save column so disease (and future save-vs-X
-- mechanics) can vary by tier.
--
-- Defaults:
--   untrained → 16 (worse — green levies, peasant militia)
--   average   → 14 (default — RAW Normal Man / 1HD)
--   veteran   → 12 (better — campaign-hardened, ≥ 2 HD effective)
--
-- Per RAW daw_campaigns_troop_tables_summary saving throws aren't explicitly
-- listed for unit-level resolution; project derives by tier as a v1 heuristic.
-- Phase 10+ can refine via per-troop_type catalog mapping.

ALTER TABLE troop_units ADD COLUMN save_vs_death INTEGER NOT NULL DEFAULT 14;

-- Backfill existing rows by tier.
UPDATE troop_units SET save_vs_death = 16 WHERE tier = 'untrained';
UPDATE troop_units SET save_vs_death = 14 WHERE tier = 'average';
UPDATE troop_units SET save_vs_death = 12 WHERE tier = 'veteran';
