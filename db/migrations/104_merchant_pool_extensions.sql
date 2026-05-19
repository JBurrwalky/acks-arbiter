-- Migration 104: merchant_pool extensions (Phase 10B.2 — Trade block, Wave 1).
--
-- Per generation/gdd-phase-10b-2-trade-block.md §4.8 + §0.1.1 (LLM-promotion
-- forward-compat anchor) + §17.1.
--
-- Two additive nullable columns on merchant_pool:
--   * promoted_npc_id — forward-compat hook for the future LLM tool-caller
--     procedure that promotes a transactional merchant into a named NPC. v1
--     has no caller; the column ships so that monthly refresh + expiration
--     + persuade-fail can already check it and preserve promoted rows.
--   * refused_at_calendar_day — persuade-fail preservation path for promoted
--     merchants per §4.7 Path B. NULL means "not refused this cohort";
--     non-NULL means "refused as of this day, cleared at next monthly refresh."
--     Transactional merchants get DELETEd on persuade-fail per RAW L715;
--     promoted merchants survive but refuse this cohort.
--
-- Both nullable; both default NULL. Cohort-aware queries (e.g.,
-- list_visible_merchants) filter with `refused_at_calendar_day IS NULL`.

BEGIN TRANSACTION;

ALTER TABLE merchant_pool ADD COLUMN promoted_npc_id TEXT REFERENCES characters(id);
ALTER TABLE merchant_pool ADD COLUMN refused_at_calendar_day INTEGER;

COMMIT;
