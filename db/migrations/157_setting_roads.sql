-- Migration 157: setting_roads (Layer 6 §9.2 road network).
--
-- A canonical road is a settlement-to-settlement route produced by Layer 6
-- (Stage 7b) via terrain-cost pathfinding. `hexes` is the ordered path
-- ([[q,r],...]); `road_class` tiers it (highway = inter-realm trade or a route
-- touching a Class I-III market; road = ordinary domestic link). Highways are
-- named (region-painting §6.1) and cross-link to a road-layer setting_regions
-- row via region_id. Written only by the generator, frozen by the Layer-8 lock
-- like the rest of the setting_* tables.
CREATE TABLE IF NOT EXISTS setting_roads (
    id TEXT NOT NULL,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    hexes TEXT NOT NULL DEFAULT '[]',
    from_settlement_id TEXT NOT NULL DEFAULT '',
    to_settlement_id TEXT NOT NULL DEFAULT '',
    road_class TEXT NOT NULL DEFAULT 'road' CHECK(road_class IN ('highway', 'road', 'track')),
    purpose TEXT NOT NULL DEFAULT 'domestic' CHECK(purpose IN ('domestic', 'trade')),
    name TEXT NOT NULL DEFAULT '',
    region_id TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (campaign_id, id)
);
