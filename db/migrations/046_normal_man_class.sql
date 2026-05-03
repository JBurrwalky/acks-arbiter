-- Migration 046: Normal Man as a real class
-- Date: 2026-05-03
-- Purpose: Backfill placeholder Normal Man henchmen to the new normal_man class.
--
-- Prior to this migration, level-0 henchmen were generated as L1 Fighters with a
-- class_metadata flag {"normal_man_placeholder": true}. Now that
-- data/classes/normal_man.json exists, those rows are converted in place.
--
-- The placeholder pattern was: characters.character_class = 'fighter',
-- characters.level = 1, characters.class_metadata contains
-- "normal_man_placeholder":true.
--
-- After this migration:
--   character_class = 'normal_man'
--   level           = 0
--   class_metadata  = '' (the only flag stored for these rows was the placeholder)
--
-- Combat-stat fields (saves, attack throw, hp_max) are NOT recomputed here. Affected
-- rows are sufficiently fresh (created during smoke testing only); the next session
-- run that touches them will derive saves from the normal_man class JSON via
-- ClassRegistry.get_saving_throws("normal_man", 0). For test-DB hygiene, run
-- `Wipe campaign.db` and re-seed if any persisted placeholder-NMs exist.

UPDATE characters
SET character_class = 'normal_man',
    level = 0,
    class_metadata = ''
WHERE class_metadata LIKE '%normal_man_placeholder%';
