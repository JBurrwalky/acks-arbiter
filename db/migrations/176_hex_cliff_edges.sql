-- Migration 176: cliff / canyon edges — impassable elevation gradients.
-- gdd-cliffs-canyons.md §3. A per-edge feature mirroring hex_river_edges: the
-- lex-lower (q, r) of the two adjacent hexes owns the row (no mirror entry),
-- `edge` 0..5 = N,NE,SE,S,SW,NW. Blocks party travel across the edge unless the
-- SHEER_SURFACE_CLIMB gate (Mountaineering + per-climber gear) is satisfied.

CREATE TABLE IF NOT EXISTS hex_cliff_edges (
    map_id       TEXT    NOT NULL REFERENCES hex_maps(id),
    hex_q        INTEGER NOT NULL,
    hex_r        INTEGER NOT NULL,
    edge         INTEGER NOT NULL CHECK(edge BETWEEN 0 AND 5),
    cliff_type   TEXT    NOT NULL DEFAULT 'cliff'
        CHECK(cliff_type IN ('cliff', 'canyon')),
    height_ft    INTEGER NOT NULL DEFAULT 0,        -- climb height (rim - floor)
    high_side    INTEGER NOT NULL DEFAULT 0         -- 0 = owner is top, 1 = neighbour is top
        CHECK(high_side IN (0, 1)),
    PRIMARY KEY (map_id, hex_q, hex_r, edge)
);

CREATE INDEX IF NOT EXISTS idx_hex_cliff_edges_owner
    ON hex_cliff_edges(map_id, hex_q, hex_r);
