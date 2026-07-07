-- Migration 177: pin the cliff-detection threshold per region map.
-- gdd-region-zoom-in.md §6 (the rolling, persisted frontier). CliffDetector uses an
-- ADAPTIVE percentile threshold over a map's own land edges so cliff DENSITY is
-- consistent at any map size. But when the 6-mile play map GROWS at the frontier, a
-- recomputed threshold over the enlarged grid would drift and flicker cliffs near the
-- seam. So the threshold computed at the FIRST build is pinned here and reused for every
-- frontier growth, keeping cliffs stable + deterministic. NULL = pre-177 maps → fall back
-- to the adaptive threshold.
ALTER TABLE hex_maps ADD COLUMN cliff_threshold REAL;
