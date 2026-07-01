-- Migration 179: per-polity hybrid provenance (culture_synthesis_parents).
--
-- gdd-culture-emergence-and-territory.md §3.3/§3.6 / gdd-hybrid-conlang-fusion.md §6.4
-- Phase 4d: when a realm's populated substrate becomes dominantly a first-order
-- HYBRID (the border/conquest merge model), its present-day culture_id is relabeled
-- to that hybrid at finalize and the two BASE parents are recorded here as a JSON
-- pair [base_a, base_b]. Base-cultured realms carry '[]'.
--
-- JSON list column, 1:1 with the polity row -- the natural companion to culture_id.
-- Non-destructive ADD COLUMN with a '[]' default, so existing rows (and the
-- determinism hash, which keys on SettingRepository.POLITY_COLUMNS) carry the new
-- field automatically.

ALTER TABLE setting_polities ADD COLUMN culture_synthesis_parents TEXT NOT NULL DEFAULT '[]';
