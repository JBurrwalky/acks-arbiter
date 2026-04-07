-- Migration 020: Hex overlays (rivers & roads) + water constraint update
--
-- Rivers and roads are edge-to-edge overlays on hex cells, not full-hex terrain.
-- Edge numbering: 0=N, 1=NE, 2=SE, 3=S, 4=SW, 5=NW (clockwise from North).
-- One river and one road per hex; edges stored as JSON arrays.

CREATE TABLE IF NOT EXISTS hex_overlays (
    map_id TEXT NOT NULL,
    q INTEGER NOT NULL,
    r INTEGER NOT NULL,
    overlay_type TEXT NOT NULL CHECK(overlay_type IN ('river', 'road')),
    edges TEXT NOT NULL DEFAULT '[]',
    flow_exit INTEGER NOT NULL DEFAULT -1,
    PRIMARY KEY (map_id, q, r, overlay_type),
    FOREIGN KEY (map_id) REFERENCES hex_maps(id)
);

-- Update hex_cells water CHECK: replace 'river' with 'lake'.
-- SQLite cannot ALTER CHECK constraints, so rebuild the table.

ALTER TABLE hex_cells RENAME TO hex_cells_old;

CREATE TABLE hex_cells (
    map_id TEXT NOT NULL REFERENCES hex_maps(id),
    q INTEGER NOT NULL,
    r INTEGER NOT NULL,
    elevation TEXT NOT NULL DEFAULT 'flat'
        CHECK(elevation IN ('flat', 'hills', 'mountains')),
    biome TEXT NOT NULL DEFAULT 'clear'
        CHECK(biome IN ('clear', 'woods', 'jungle', 'swamp', 'desert')),
    water TEXT NOT NULL DEFAULT ''
        CHECK(water IN ('', 'ocean', 'lake')),
    civilization TEXT NOT NULL DEFAULT 'wilderness'
        CHECK(civilization IN ('civilized', 'borderlands', 'wilderness')),
    has_city INTEGER NOT NULL DEFAULT 0 CHECK(has_city IN (0, 1)),
    original_biome TEXT NOT NULL DEFAULT '',
    fog_state TEXT NOT NULL DEFAULT 'hidden'
        CHECK(fog_state IN ('hidden', 'explored', 'visible')),
    PRIMARY KEY (map_id, q, r)
);

-- Copy data, converting any existing water='river' to water='' (rivers are now overlays).
INSERT INTO hex_cells (map_id, q, r, elevation, biome, water, civilization, has_city, original_biome, fog_state)
SELECT map_id, q, r, elevation, biome,
       CASE WHEN water = 'river' THEN '' ELSE water END,
       civilization, has_city, original_biome, fog_state
FROM hex_cells_old;

DROP TABLE hex_cells_old;
