-- Migration 174: domains.garrison_composition — a DENORMALIZED, display-ready garrison
-- (TEXT JSON: gp budget + per-unit-type troop counts) so the map / LLM narrator / UI can
-- render AX3-level fort detail at the handoff WITHOUT the live troop economy. Derived
-- deterministically from the domain's peasant_families + territory_type per the ACKS II
-- Judges Journal "Realm Apportionment" Step-10 garrison model (gdd-region-zoom-in §2/§5.6d;
-- gdd-setting-runtime-materialization §15.5 M4-3): minimum garrison gp = families ×
-- {2 civilized / 3 borderlands / 4 wilderness}, converted to troops by unit cost with
-- ~25% veterans. The REAL economic troop entity (recruitment, monthly upkeep, troop_units)
-- is a later Domain phase — this is the read-only handoff snapshot. '{}' = no garrison.
ALTER TABLE domains ADD COLUMN garrison_composition TEXT NOT NULL DEFAULT '{}';
