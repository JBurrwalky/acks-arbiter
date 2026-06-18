-- Migration 166: runtime `roads` entity — the materialized + 6-mile-generated road
-- network as first-class entities. `hex_overlays` carries per-cell render geometry
-- (edges); THIS table carries each road as an entity (ordered hex path + class +
-- purpose + name) so the game knows WHERE roads are and WHAT they are, and so
-- 6-mile zoom-in can add new roads connecting newly-generated settlements. Mirrors
-- the generator-side setting_roads on the runtime side.
-- See gdd-region-zoom-in.md §5.4 / gdd-setting-runtime-materialization.md §5.3.
CREATE TABLE IF NOT EXISTS roads (
    id            TEXT    PRIMARY KEY,
    campaign_id   TEXT    NOT NULL REFERENCES campaigns(id),
    map_id        TEXT    NOT NULL REFERENCES hex_maps(id),
    hexes         TEXT    NOT NULL DEFAULT '[]',
    road_class    TEXT    NOT NULL DEFAULT 'road'
        CHECK(road_class IN ('highway', 'road', 'track')),
    purpose       TEXT    NOT NULL DEFAULT '',
    name          TEXT    NOT NULL DEFAULT '',
    created_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_roads_map ON roads(map_id);
