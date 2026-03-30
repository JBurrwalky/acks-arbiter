-- Migration 007: Proficiency infrastructure
-- Adds selections_count and specialization columns to character_proficiencies.
-- selections_count: how many times this proficiency was selected (for stacking proficiencies).
-- specialization: the chosen specialization for specialization-rule proficiencies (e.g. "disarm",
--   "missile", "political_history"). Empty string for non-specialization proficiencies.

ALTER TABLE character_proficiencies ADD COLUMN selections_count INTEGER NOT NULL DEFAULT 1;
ALTER TABLE character_proficiencies ADD COLUMN specialization TEXT NOT NULL DEFAULT '';
