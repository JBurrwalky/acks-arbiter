-- Migration 173: domain_hexes.families — per-6-mile-hex peasant family count.
-- This is the grounding the M4-1 6-mile vassal-tree decomposition consumes
-- (gdd-region-zoom-in §5.5/§5.6a; gdd-setting-runtime-materialization §15.5).
-- The materializer distributes each in-window 24-mile hex's population_band across
-- its 16 six-mile children, conserved (the 16 children sum to the parent), so each
-- 6-mile Barony's family budget is grounded and conservation-consistent. Previously
-- population was conserved only at the DOMAIN level (M2b-1; "no per-6-mile-hex
-- population / no consumer — deferred") — the Baron-per-hex decomposition is the
-- consumer that retires that deferral.
ALTER TABLE domain_hexes ADD COLUMN families INTEGER NOT NULL DEFAULT 0;
