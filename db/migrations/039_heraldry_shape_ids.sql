-- Migration 039: remap legacy shape_ids to the v1 shape vocabulary.
-- The initial Session-1 import used regional shape_ids (english, german,
-- italian, ...) that pointed at PNG masks. Those assets turned out to be
-- unusable, so the renderer pivoted to procedural polygons organized by
-- shape archetype: heater, kite, round, norman, tower, horsehead, swiss.
-- This migration reassigns any existing party_heraldry rows that still
-- carry the old regional ids.

UPDATE party_heraldry SET shape_id = 'heater'    WHERE shape_id = 'english';
UPDATE party_heraldry SET shape_id = 'kite'      WHERE shape_id = 'old_french';
UPDATE party_heraldry SET shape_id = 'norman'    WHERE shape_id = 'german';
UPDATE party_heraldry SET shape_id = 'horsehead' WHERE shape_id = 'italian';
UPDATE party_heraldry SET shape_id = 'tower'     WHERE shape_id IN ('polish_xvib', 'polish_xixa', 'polish_xixc');
-- 'swiss' already matches the v1 vocabulary; no-op.

-- Defensive: any shape_id we did not explicitly remap falls back to heater,
-- so the renderer never sees an unknown shape_id after this migration runs.
UPDATE party_heraldry
SET shape_id = 'heater'
WHERE shape_id NOT IN ('heater', 'kite', 'round', 'norman', 'tower', 'horsehead', 'swiss');
