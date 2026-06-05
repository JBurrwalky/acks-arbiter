-- Migration 145: origin_template_id — which class template a character was
-- created from (gdd-class-templates.md §6.4).
--
-- NULL for characters created via Path A (kept the gold), built outside the
-- template system, or generated as Normal-Man / out-of-scope NPCs. The
-- ClassedNpcBuilder stamps it for every template-built NPC, and the Path B PC
-- creation flow surfaces it for the creation wizard to stamp.
--
-- Reference-only: useful for narration, save-game inspection, and future
-- analytics; no gameplay logic reads it. Existing rows default to NULL, which
-- CharacterData.from_dict() normalizes to "" in memory (same null-coalescing
-- the henchman employer_id field uses).

ALTER TABLE characters ADD COLUMN origin_template_id TEXT DEFAULT NULL;
