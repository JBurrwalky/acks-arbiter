-- Migration 168: self-contained context + rumor seeds on runtime POIs. POIs
-- materialized from setting_poi_seeds carry their context/rumor_seeds; AND 6-mile
-- zoom-in generates NEW POIs that have no setting_poi_seeds row, so the runtime row
-- must self-contain this data (read-back from the generator table is impossible for
-- a generated-at-play POI). JSON: context = {} dict, rumor_seeds = [] array.
-- See gdd-setting-runtime-materialization.md §5.8 / gdd-region-zoom-in.md §5.1.
ALTER TABLE pois ADD COLUMN context TEXT NOT NULL DEFAULT '{}';
ALTER TABLE pois ADD COLUMN rumor_seeds TEXT NOT NULL DEFAULT '[]';
