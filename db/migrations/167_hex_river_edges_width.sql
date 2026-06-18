-- Migration 167: river width on runtime river edges. setting_river_edges carries
-- width_category (the generated river's size class); the runtime table dropped it
-- until now. Needed so the wilderness renderer can draw rivers by width and 6-mile
-- zoom-in can size tributaries. Free-text (no CHECK — the generator's width vocab
-- may evolve). '' default = unknown / legacy.
ALTER TABLE hex_river_edges ADD COLUMN width_category TEXT NOT NULL DEFAULT '';
